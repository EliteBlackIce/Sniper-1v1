--[[
	MovementController.lua  (Client.MovementController)

	Fast, momentum-based movement on top of the normal Roblox Humanoid.

	CONTROLS
		WASD           move
		Left Shift     sprint (hold) on the ground / AIR DASH when in the air
		C or L-Ctrl    slide (hold). Pressing it in the air = slide on landing
		Space          jump, double jump, wall jump, (Magnetic Boots: hold under
		               a ceiling to cling to it)
		E              Grapple Hook (power-up)
		Q              Decoy (power-up)

	HOW IT WORKS
	We keep our own horizontal velocity, `momentum`, and drive the character
	with a LinearVelocity constraint in "Plane" mode (horizontal only). That
	means gravity and jumping still work normally, but WE decide horizontal
	speed, so momentum carries between moves: slide -> jump keeps your speed,
	wall run -> dash keeps your speed, etc.

	Every move is a "mode":
		Ground   walking / sprinting (extra speed bleeds off slowly)
		Air      falling / jumping (air control + momentum)
		Slide    low friction ground slide
		WallRun  running along a wall
		Dash     short burst in the air
		Grapple  being pulled toward the hook point
		Ceiling  clinging to a ceiling (Magnetic Boots)

	The Camera reads GetCameraHints() for FOV kick, roll and camera drop.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Util = require(Shared.Util)
local ClientState = require(script.Parent.ClientState)
local Sfx = require(script.Parent.Sfx)

local M = Config.Movement
local C = Config.Camera
local PU = Config.PowerUps
local player = Players.LocalPlayer

local Movement = {}
local Controllers

-- Character references
local character, humanoid, root, linearVelocity

-- Movement state
local mode = "Ground"
local momentum = Vector3.zero -- horizontal velocity we are driving
local lastDrive = Vector3.zero -- what we actually commanded last frame
local pendingImpulse = Vector3.zero -- knockback etc. added next frame
local pendingLift = nil -- vertical velocity to set next frame
local airJumpsLeft = 0
local dashesLeft = 0

local sprintHeld, slideHeld, jumpHeld = false, false, false

local now = os.clock
local lastLandTime = 0
local lastGroundJumpTime = 0
local lastLiftTime = 0
local lastSlideTime = 0
local lastDashTime = 0
local peakY = 0

local dash = { Timer = 0, Dir = Vector3.zero, ExitSpeed = 0 }
local wall = { Normal = Vector3.zero, Side = 0, Timer = 0, Y = 0, LastNormal = nil, LastTime = 0 }
local grapple = { Point = nil, Timer = 0, ReadyAt = 0 }
local speedBoost = { Until = 0, Multiplier = 1 }
local bulletTime = { Until = 0, ReadyAt = 0, UsedThisAir = false }
local decoyReadyAt = 0

local fovKick = 0

----------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------
local function stats()
	return ClientState.Stats
end

local function canMove()
	if not (character and humanoid and root and linearVelocity) then
		return false
	end
	if humanoid.Health <= 0 or root.Anchored or character:GetAttribute("Frozen") then
		return false
	end
	return true
end

local function approachVector(current, target, maxDelta)
	local delta = target - current
	if delta.Magnitude <= maxDelta then
		return target
	end
	return current + delta.Unit * maxDelta
end

-- Rotates the direction of `v` toward `dir` by fraction t, keeping its length.
local function steer(v, dir, t)
	if v.Magnitude < 0.1 or dir.Magnitude < 0.1 then
		return v
	end
	local newDir = v.Unit:Lerp(dir.Unit, math.clamp(t, 0, 1))
	if newDir.Magnitude < 0.05 then
		return v
	end
	return newDir.Unit * v.Magnitude
end

local function speedMultiplier()
	return now() < speedBoost.Until and speedBoost.Multiplier or 1
end

local function wishDirection()
	local dir = humanoid and humanoid.MoveDirection or Vector3.zero
	dir = Util.flat(dir)
	if dir.Magnitude > 1 then
		dir = dir.Unit
	end
	return dir
end

local function cameraFlatLook()
	local camera = workspace.CurrentCamera
	return Util.safeUnit(Util.flat(camera.CFrame.LookVector), Vector3.new(0, 0, -1))
end

local function makeRaycastParams()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = { character, workspace.CurrentCamera }
	for _, name in ipairs({ "Effects", "Decoys" }) do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(exclude, folder)
		end
	end
	-- other players are not walls
	for _, other in ipairs(Players:GetPlayers()) do
		if other.Character then
			table.insert(exclude, other.Character)
		end
	end
	params.FilterDescendantsInstances = exclude
	return params
end

local function setVerticalVelocity(y)
	local v = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(v.X, y, v.Z)
end

----------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------

-- Push the character (knockback, rocket jump). Horizontal part is added to
-- momentum, vertical part sets the upward speed.
function Movement.ApplyImpulse(velocity)
	pendingImpulse += Util.flat(velocity)
	if velocity.Y > 1 then
		pendingLift = math.max(pendingLift or 0, velocity.Y)
	end
end

function Movement.IsBulletTime()
	return now() < bulletTime.Until
end

function Movement.GetMode()
	return mode
end

function Movement.GetSpeed()
	return momentum.Magnitude
end

function Movement.GetGrapplePoint()
	return grapple.Point
end

function Movement.GetCooldowns()
	return {
		Grapple = math.max(0, grapple.ReadyAt - now()),
		Decoy = math.max(0, decoyReadyAt - now()),
		BulletTime = math.max(0, bulletTime.ReadyAt - now()),
	}
end

function Movement.IsGrounded()
	return humanoid ~= nil and humanoid.FloorMaterial ~= Enum.Material.Air
end

-- FOV kick / roll / camera drop for the CameraController.
function Movement.GetCameraHints()
	local hints = { FovKick = fovKick, Roll = 0, Drop = 0 }
	if not humanoid then
		return hints
	end
	if mode == "WallRun" then
		hints.Roll = wall.Side * C.WallRunTilt
	elseif mode == "Slide" then
		hints.Roll = C.SlideTilt
		hints.Drop = C.SlideCameraDrop
	else
		-- tiny strafe tilt
		local camera = workspace.CurrentCamera
		local strafe = wishDirection():Dot(camera.CFrame.RightVector)
		hints.Roll = -strafe * C.StrafeTilt
	end
	return hints
end

----------------------------------------------------------------------------
-- Move starters
----------------------------------------------------------------------------
local function startSlide()
	if now() - lastSlideTime < M.SlideCooldown then
		return
	end
	local speed = momentum.Magnitude
	if speed < M.SlideMinSpeed then
		return
	end
	lastSlideTime = now()
	mode = "Slide"
	momentum = momentum.Unit * math.min(speed + M.SlideBoost, M.SlideMaxSpeed)
	Sfx.Play("Dash", { Pitch = 0.7, Volume = 0.6 })
end

local function onLanded()
	local fell = peakY - root.Position.Y
	peakY = root.Position.Y
	mode = "Ground"
	lastLandTime = now()
	airJumpsLeft = stats().AirJumps
	dashesLeft = M.DashesPerAir
	bulletTime.UsedThisAir = false
	if fell > 6 then
		Sfx.Play("Land", { Volume = math.clamp(fell / 20, 0.4, 1.2) })
	end
	-- SHOCKWAVE LANDING power-up
	if stats().ShockwaveLanding and fell >= PU.ShockwaveLanding.MinFallHeight then
		Remotes.Get("Ability"):FireServer("Shockwave", {})
		Controllers.Camera.Shake(2.5)
	end
	if slideHeld then
		startSlide()
	end
end

local function startDash()
	if dashesLeft <= 0 or now() - lastDashTime < M.DashCooldown then
		return
	end
	dashesLeft -= 1
	lastDashTime = now()
	local wish = wishDirection()
	local dir = wish.Magnitude > 0.1 and wish.Unit or cameraFlatLook()
	dash.Dir = dir
	dash.Timer = M.DashDuration
	dash.ExitSpeed = math.max(M.DashExitSpeed, momentum.Magnitude) * speedMultiplier()
	mode = "Dash"
	Controllers.Camera.AddFovPunch(C.DashFOVKick)
	Sfx.Play("Dash")
	-- PHANTOM DASH power-up: the server makes us invisible
	if stats().PhantomDash then
		Remotes.Get("Ability"):FireServer("PhantomDash", {})
		Controllers.Effects.PhantomFlash()
	end
end

local function endGrapple(popUp)
	if not grapple.Point then
		return
	end
	grapple.Point = nil
	grapple.ReadyAt = now() + M.GrappleCooldown
	Remotes.Get("Ability"):FireServer("GrappleEnd", {})
	Controllers.Effects.SetLocalGrapple(nil)
	mode = "Air"
	if popUp then
		pendingLift = math.max(pendingLift or 0, 32)
	end
end

local function startGrapple()
	if not stats().Grapple or now() < grapple.ReadyAt or grapple.Point then
		return
	end
	local camera = workspace.CurrentCamera
	local result = workspace:Raycast(
		camera.CFrame.Position,
		camera.CFrame.LookVector * M.GrappleRange,
		makeRaycastParams()
	)
	if not result then
		grapple.ReadyAt = now() + 0.3 -- small penalty for a miss
		return
	end
	grapple.Point = result.Position
	grapple.Timer = 0
	mode = "Grapple"
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	Remotes.Get("Ability"):FireServer("GrappleStart", { Point = result.Position })
	Controllers.Effects.SetLocalGrapple(result.Position)
	Sfx.Play("Ability")
end

local function startDecoy()
	if not stats().Decoy or now() < decoyReadyAt then
		return
	end
	decoyReadyAt = now() + PU.Decoy.Cooldown
	local wish = wishDirection()
	local dir = wish.Magnitude > 0.1 and wish.Unit or cameraFlatLook()
	Remotes.Get("Ability"):FireServer("Decoy", { Direction = dir })
	Sfx.Play("Ability", { Pitch = 1.3 })
end

local function wallJump()
	local along = Util.flat(momentum - wall.Normal * momentum:Dot(wall.Normal))
	momentum = along + wall.Normal * M.WallJumpOut
	pendingLift = M.WallJumpUp
	wall.LastNormal = wall.Normal
	wall.LastTime = now()
	mode = "Air"
	airJumpsLeft = stats().AirJumps -- wall jumps refresh your air jumps
	Sfx.Play("Jump", { Pitch = 1.15 })
end

local function onJumpPressed()
	if not canMove() then
		return
	end
	if mode == "WallRun" then
		wallJump()
	elseif mode == "Grapple" then
		endGrapple(true)
	elseif mode == "Slide" then
		-- the Humanoid does the jump itself; we add a little speed
		momentum += Util.safeUnit(momentum) * M.SlideJumpBoost
		mode = "Air"
		lastGroundJumpTime = now()
		Sfx.Play("Jump")
	elseif mode == "Ground" and Movement.IsGrounded() then
		lastGroundJumpTime = now()
		Sfx.Play("Jump")
	elseif mode == "Air" or mode == "Dash" or (mode == "Ground" and not Movement.IsGrounded()) then
		if now() - lastGroundJumpTime < 0.12 then
			return -- that was the ground jump itself
		end
		if airJumpsLeft > 0 then
			airJumpsLeft -= 1
			pendingLift = M.AirJumpVelocity
			-- re-aim momentum toward input (keeps your speed)
			local wish = wishDirection()
			if wish.Magnitude > 0.1 then
				momentum = wish.Unit * math.max(momentum.Magnitude, M.WalkSpeed)
			end
			if mode == "Dash" then
				momentum = dash.Dir * dash.ExitSpeed
			end
			mode = "Air"
			Sfx.Play("Jump", { Pitch = 1.25 })
		end
	end
end

----------------------------------------------------------------------------
-- Per-mode updates
----------------------------------------------------------------------------
local function updateGround(dt, wish)
	local target = (sprintHeld and M.SprintSpeed or M.WalkSpeed) * speedMultiplier()
	local speed = momentum.Magnitude
	if speed > target + 0.5 then
		-- carrying extra speed (from a slide/dash/fall): bleed it off slowly,
		-- not at all right after landing so you can chain a jump
		if now() - lastLandTime > M.BhopGrace then
			speed = math.max(target, speed - M.ExcessFriction * dt)
		end
		momentum = steer(momentum, wish, 6 * dt).Unit * speed
		if wish.Magnitude < 0.1 then
			momentum = approachVector(momentum, Vector3.zero, M.GroundFriction * 0.5 * dt)
		end
	else
		local accel = wish.Magnitude > 0.1 and M.GroundAccel or M.GroundFriction
		momentum = approachVector(momentum, wish * target, accel * dt)
	end
	humanoid.WalkSpeed = math.max(target, 1)
end

local function updateAir(dt, wish)
	local speedCap = math.max(momentum.Magnitude, M.AirMaxInputSpeed * speedMultiplier())
	if wish.Magnitude > 0.1 then
		momentum = steer(momentum, wish, M.AirTurnRate * dt)
		momentum += wish * M.AirAccel * dt
		if momentum.Magnitude > speedCap then
			momentum = momentum.Unit * speedCap
		end
	end
	-- light drag on speed above normal air speed
	local excess = momentum.Magnitude - M.AirMaxInputSpeed
	if excess > 0 then
		momentum = momentum.Unit * (momentum.Magnitude - excess * M.AirDrag * dt)
	end
	peakY = math.max(peakY, root.Position.Y)
end

local function tryStartWallRun(wish)
	if momentum.Magnitude < M.WallRunMinSpeed or wish.Magnitude < 0.1 then
		return false
	end
	local params = makeRaycastParams()
	-- need some air under us
	if workspace:Raycast(root.Position, Vector3.new(0, -4, 0), params) then
		return false
	end
	local right = root.CFrame.RightVector
	for _, side in ipairs({ 1, -1 }) do
		local result = workspace:Raycast(root.Position, right * side * M.WallCheckDistance, params)
		if result and math.abs(result.Normal.Y) < 0.3 then
			local normal = Util.flat(result.Normal).Unit
			local recentlyLeft = wall.LastNormal
				and now() - wall.LastTime < M.WallReattachDelay
				and wall.LastNormal:Dot(normal) > 0.9
			local runningInto = math.abs(momentum.Unit:Dot(normal)) > 0.85
			if not recentlyLeft and not runningInto then
				mode = "WallRun"
				wall.Normal = normal
				wall.Side = side
				wall.Timer = 0
				wall.Y = math.max(root.AssemblyLinearVelocity.Y * 0.4, M.WallRunStartLift)
				airJumpsLeft = stats().AirJumps
				dashesLeft = M.DashesPerAir
				return true
			end
		end
	end
	return false
end

local function updateWallRun(dt, wish)
	local result =
		workspace:Raycast(root.Position, -wall.Normal * (M.WallCheckDistance + 1.5), makeRaycastParams())
	local infinite = stats().InfiniteWallRun
	wall.Timer += dt
	local expired = not infinite and wall.Timer > M.WallRunDuration
	if not result or math.abs(result.Normal.Y) > 0.3 or expired or wish.Magnitude < 0.1 then
		wall.LastNormal = wall.Normal
		wall.LastTime = now()
		mode = "Air"
		return
	end
	wall.Normal = Util.flat(result.Normal).Unit

	local along = Util.flat(momentum - wall.Normal * momentum:Dot(wall.Normal))
	if along.Magnitude < 1 then
		local look = cameraFlatLook()
		along = look - wall.Normal * look:Dot(wall.Normal)
	end
	local speed = math.max(momentum.Magnitude, M.WallRunSpeed * speedMultiplier())
	momentum = Util.safeUnit(along) * speed - wall.Normal * 3 -- press into the wall

	if infinite then
		wall.Y = Util.approach(wall.Y, 0, M.WallRunGravity * dt)
	else
		wall.Y -= M.WallRunGravity * dt
	end
	setVerticalVelocity(wall.Y)
end

local function updateSlide(dt, wish)
	local speed = momentum.Magnitude - M.SlideFriction * dt
	momentum = steer(momentum, wish, M.SlideSteer * dt)
	if speed < M.SlideEndSpeed or not slideHeld then
		mode = "Ground"
		momentum = Util.safeUnit(momentum) * math.max(speed, 0)
		return
	end
	momentum = Util.safeUnit(momentum) * speed
	humanoid.WalkSpeed = 4 -- calm the run animation while sliding
end

local function updateDash(dt)
	dash.Timer -= dt
	momentum = dash.Dir * M.DashSpeed * speedMultiplier()
	setVerticalVelocity(1.5) -- dashes are flat
	if dash.Timer <= 0 then
		momentum = dash.Dir * dash.ExitSpeed
		mode = Movement.IsGrounded() and "Ground" or "Air"
	end
end

local function updateGrapple(dt)
	grapple.Timer += dt
	local toPoint = grapple.Point - root.Position
	if toPoint.Magnitude < M.GrappleReleaseDistance or grapple.Timer > M.GrappleMaxTime then
		endGrapple(false)
		return
	end
	local velocity = Vector3.new(momentum.X, root.AssemblyLinearVelocity.Y, momentum.Z)
	velocity = approachVector(velocity, toPoint.Unit * M.GrapplePullSpeed, M.GrappleAccel * dt)
	momentum = Util.flat(velocity)
	setVerticalVelocity(velocity.Y)
end

local function tryStartCeiling()
	if not (stats().CeilingRun and jumpHeld) then
		return false
	end
	local result = workspace:Raycast(root.Position, Vector3.new(0, 5, 0), makeRaycastParams())
	if result and result.Normal.Y < -0.7 then
		mode = "Ceiling"
		return true
	end
	return false
end

local function updateCeiling(dt, wish)
	local result = workspace:Raycast(root.Position, Vector3.new(0, 5.5, 0), makeRaycastParams())
	if not jumpHeld or not result then
		mode = "Air"
		return
	end
	local target = M.SprintSpeed * speedMultiplier()
	momentum = approachVector(momentum, wish * math.max(target, momentum.Magnitude), M.GroundAccel * dt)
	setVerticalVelocity(3) -- keep pressed against the ceiling
	airJumpsLeft = stats().AirJumps
	dashesLeft = M.DashesPerAir
end

----------------------------------------------------------------------------
-- Bullet Time (power-up): scoped in mid-air -> slow time for yourself
----------------------------------------------------------------------------
local function updateBulletTime(dt, grounded)
	local cfg = PU.BulletTime
	local scoped = Controllers.Weapon.IsScoped()
	if Movement.IsBulletTime() then
		if grounded or not scoped then
			bulletTime.Until = 0
			Controllers.Effects.SetBulletTime(false)
			return
		end
		-- fall much slower
		local v = root.AssemblyLinearVelocity
		local y = v.Y + workspace.Gravity * (1 - cfg.GravityScale) * dt
		if y < 0 then
			y *= (1 - math.min(1, 6 * dt))
		end
		setVerticalVelocity(y)
		return
	end
	if Controllers.Effects.IsBulletTimeVisible() then
		Controllers.Effects.SetBulletTime(false)
	end
	if stats().BulletTime and scoped and not grounded and not bulletTime.UsedThisAir and now() >= bulletTime.ReadyAt then
		bulletTime.UsedThisAir = true
		bulletTime.Until = now() + cfg.Duration
		bulletTime.ReadyAt = now() + cfg.Cooldown
		Remotes.Get("Ability"):FireServer("BulletTime", {})
		Controllers.Effects.SetBulletTime(true)
	end
end

----------------------------------------------------------------------------
-- Main step
----------------------------------------------------------------------------
local function step(dt)
	if not canMove() then
		if linearVelocity then
			linearVelocity.Enabled = false
		end
		momentum = Vector3.zero
		lastDrive = Vector3.zero
		pendingImpulse = Vector3.zero
		pendingLift = nil
		fovKick = 0
		if grapple.Point then
			grapple.Point = nil
			Controllers.Effects.SetLocalGrapple(nil)
		end
		return
	end
	linearVelocity.Enabled = true

	local velocity = root.AssemblyLinearVelocity
	local horizontal = Util.flat(velocity)

	-- If something blocked us (a wall), the real velocity is lower than what
	-- we commanded last frame: swap that part of our momentum for the real
	-- velocity. Changes made since then (slide boost, wall jump...) are kept.
	if mode ~= "Dash" and mode ~= "Grapple" and mode ~= "WallRun" and not Movement.IsBulletTime() then
		if horizontal.Magnitude < lastDrive.Magnitude - 3 then
			momentum = horizontal + (momentum - lastDrive)
		end
	end

	-- External impulses (knockback / rocket jump)
	if pendingImpulse.Magnitude > 0 then
		momentum += pendingImpulse
		pendingImpulse = Vector3.zero
	end
	if pendingLift then
		setVerticalVelocity(pendingLift)
		if mode == "Ground" or mode == "Slide" or mode == "WallRun" or mode == "Ceiling" then
			mode = "Air"
		end
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		pendingLift = nil
		lastLiftTime = now()
	end

	-- "grounded" ignores the first moments after any jump/launch, so the
	-- floor we just left doesn't instantly count as a landing
	local justLaunched = now() - math.max(lastGroundJumpTime, lastLiftTime) < 0.15
	local grounded = Movement.IsGrounded() and not justLaunched
	local wish = wishDirection()
	if not grounded then
		peakY = math.max(peakY, root.Position.Y) -- for Shockwave Landing
	end

	-- Ground <-> air transitions
	if grounded and (mode == "Air" or mode == "WallRun" or mode == "Ceiling") then
		onLanded()
	elseif not grounded and (mode == "Ground" or mode == "Slide") then
		mode = "Air"
		peakY = root.Position.Y
	end

	if mode == "Ground" then
		updateGround(dt, wish)
	elseif mode == "Slide" then
		updateSlide(dt, wish)
	elseif mode == "Air" then
		updateAir(dt, wish)
		if not tryStartCeiling() then
			tryStartWallRun(wish)
		end
	elseif mode == "WallRun" then
		updateWallRun(dt, wish)
	elseif mode == "Dash" then
		updateDash(dt)
	elseif mode == "Grapple" then
		updateGrapple(dt)
	elseif mode == "Ceiling" then
		updateCeiling(dt, wish)
	end

	updateBulletTime(dt, grounded)

	-- Drive the character
	local drive = momentum
	if Movement.IsBulletTime() then
		drive *= PU.BulletTime.MoveScale
	end
	linearVelocity.PlaneVelocity = Vector2.new(drive.X, drive.Z)
	lastDrive = drive

	-- FOV kick from movement
	local speed = momentum.Magnitude
	local kick = 0
	if mode == "Slide" then
		kick = C.SlideFOVKick
	elseif mode == "WallRun" then
		kick = C.WallRunFOVKick
	elseif mode == "Dash" then
		kick = C.DashFOVKick
	elseif speed > M.WalkSpeed + 2 then
		kick = C.SprintFOVKick
	end
	kick += math.clamp((speed - M.SprintSpeed) * C.SpeedFOVPerStud, 0, C.MaxSpeedFOV)
	fovKick = Util.lerp(fovKick, kick, Util.smooth(8, dt))
end

----------------------------------------------------------------------------
-- Character setup
----------------------------------------------------------------------------
local function onCharacterAdded(newCharacter)
	character = newCharacter
	humanoid = newCharacter:WaitForChild("Humanoid")
	root = newCharacter:WaitForChild("HumanoidRootPart")

	humanoid.UseJumpPower = true
	humanoid.JumpPower = M.JumpPower
	humanoid.WalkSpeed = M.WalkSpeed

	local attachment = root:FindFirstChild("RootAttachment") or root:FindFirstChild("RootRigAttachment")
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "MoveAttachment"
		attachment.Parent = root
	end

	linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Name = "MoveVelocity"
	linearVelocity.Attachment0 = attachment
	linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	linearVelocity.PrimaryTangentAxis = Vector3.xAxis
	linearVelocity.SecondaryTangentAxis = Vector3.zAxis
	linearVelocity.MaxForce = 200000
	linearVelocity.Enabled = false
	linearVelocity.Parent = root

	mode = "Ground"
	momentum = Vector3.zero
	lastDrive = Vector3.zero
	airJumpsLeft = stats().AirJumps
	dashesLeft = M.DashesPerAir
	grapple.Point = nil
	speedBoost.Until = 0
	bulletTime.Until = 0
	peakY = root.Position.Y

	humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Jumping and mode == "Ground" then
			lastGroundJumpTime = now()
		end
	end)
end

----------------------------------------------------------------------------
-- Input
----------------------------------------------------------------------------
-- Roblox's own control scripts bind Space (and some mouse buttons) with
-- ContextActionService, which marks those inputs as "processed". So we only
-- ignore input while the player is typing in a text box (e.g. chat).
local function isTyping(processed)
	return processed and UserInputService:GetFocusedTextBox() ~= nil
end

local function onInputBegan(input, processed)
	if isTyping(processed) then
		return
	end
	local key = input.KeyCode
	if key == Enum.KeyCode.Space or key == Enum.KeyCode.ButtonA then
		jumpHeld = true
		onJumpPressed()
	elseif key == Enum.KeyCode.LeftShift or key == Enum.KeyCode.ButtonL3 then
		sprintHeld = true
		if canMove() and (mode == "Air" or mode == "WallRun") then
			startDash()
		end
	elseif key == M.SlideKey or key == Enum.KeyCode.LeftControl or key == Enum.KeyCode.ButtonB then
		slideHeld = true
		if canMove() and mode == "Ground" then
			startSlide()
		end
	elseif key == Enum.KeyCode.E then
		if canMove() then
			if grapple.Point then
				endGrapple(false)
			else
				startGrapple()
			end
		end
	elseif key == Enum.KeyCode.Q then
		if canMove() and ClientState.IsFighting() then
			startDecoy()
		end
	end
end

local function onInputEnded(input)
	local key = input.KeyCode
	if key == Enum.KeyCode.Space or key == Enum.KeyCode.ButtonA then
		jumpHeld = false
	elseif key == Enum.KeyCode.LeftShift or key == Enum.KeyCode.ButtonL3 then
		sprintHeld = false
	elseif key == M.SlideKey or key == Enum.KeyCode.LeftControl or key == Enum.KeyCode.ButtonB then
		slideHeld = false
	end
end

function Movement.Init(controllers)
	Controllers = controllers
end

function Movement.Start()
	workspace.Gravity = M.Gravity

	if player.Character then
		task.spawn(onCharacterAdded, player.Character)
	end
	player.CharacterAdded:Connect(onCharacterAdded)

	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputEnded:Connect(onInputEnded)

	Remotes.Get("Knockback").OnClientEvent:Connect(function(velocity)
		if typeof(velocity) == "Vector3" then
			Movement.ApplyImpulse(velocity)
			Controllers.Camera.Shake(2)
		end
	end)

	Remotes.Get("Buff").OnClientEvent:Connect(function(buff)
		if buff.Type == "SpeedBoost" then
			speedBoost.Until = now() + buff.Duration
			speedBoost.Multiplier = buff.Multiplier
		end
	end)

	RunService.Heartbeat:Connect(step)
end

return Movement
