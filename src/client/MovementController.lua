--[[
	MovementController.lua  (Client.MovementController)

	Fast, momentum-based movement with BUNNY HOPPING.

	CONTROLS
		WASD           move
		Space          jump. HOLD it to bunny hop (you re-jump the instant you
		               land and keep all your speed). Wall jump too.
		A/D + mouse    air strafe: hold A and turn the mouse left (or D + right)
		               while in the air to GAIN speed, like CS / TF2
		Left Shift     sprint (hold)
		C or L-Ctrl    slide (tap; tap again to stand). Press it in the air =
		               slide the moment you land. Jump out of a slide any time.
		E              Grapple Hook (power-up)
		R              Blink (power-up)
		Q              Decoy (power-up)

	HOW IT WORKS
	The ground and air physics copy the Source engine (Half-Life, CS, TF2):
	  * ground: friction, then accelerate toward your input direction
	  * air:    the acceleration can only add a tiny bit of speed IN the
	            direction you're pressing, but there's no limit on total speed.
	            Turning the mouse while strafing keeps your input sideways to
	            your velocity, which bends and grows it. That's air strafing.
	  * landing with Space held jumps again on the same frame, before any
	            friction is applied, so no speed is lost. That's bunny hopping.

	We keep our own horizontal velocity (`momentum`) and drive the character
	with a LinearVelocity in Plane mode (horizontal only), so gravity and
	jumping still use normal Roblox physics.

	Modes: Ground, Air, Slide, WallRun, Grapple, Ceiling.
	Other scripts can listen to Movement.Jumped / Landed / Slid.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)
local Util = require(Shared.Util)
local ClientState = require(script.Parent.ClientState)
local Sfx = require(script.Parent.Sfx)
local Keybinds = require(script.Parent.Keybinds)

local M = Config.Movement
local C = Config.Camera
local PU = Config.PowerUps
local player = Players.LocalPlayer

local Movement = {}
local Controllers

Movement.Jumped = Signal.new() -- ()
Movement.Landed = Signal.new() -- (fallSpeed)
Movement.Slid = Signal.new() -- () a slide started

-- Character references
local character, humanoid, root, linearVelocity

-- Movement state
local mode = "Ground"
local momentum = Vector3.zero -- horizontal velocity we are driving
local lastDrive = Vector3.zero -- what we actually commanded last frame
local pendingImpulse = Vector3.zero -- knockback etc. added next frame
local pendingLift = nil -- vertical velocity to set next frame
local airJumpsLeft = 0

local sprintHeld, slideHeld, jumpHeld = false, false, false
local jumpPressedAt = -10 -- for the jump buffer
local slidePressedAt = -10 -- slide pressed in the air = slide on landing
local lastGroundedTime = 0 -- for coyote time
local forceJumpUntil = 0 -- keep re-applying jump velocity for a moment

local now = os.clock
local lastGroundJumpTime = 0
local lastLiftTime = 0
local lastSlideTime = 0
local lastPhantomTime = 0
local peakY = 0
local lowestVelocityY = 0 -- fastest fall speed this air time (for landing effects)

local wall = { Normal = Vector3.zero, Side = 0, Timer = 0, Y = 0, LastNormal = nil, LastTime = 0, Recharged = true, ReadyAt = 0 }
local grapple = { Point = nil, Timer = 0, ReadyAt = 0 }
local speedBoost = { Until = 0, Multiplier = 1 }
local bulletTime = { Until = 0, ReadyAt = 0, UsedThisAir = false }
local decoyReadyAt = 0
local blinkReadyAt = 0

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

--[[
	Source-engine acceleration.
	Adds speed along `wishDir` until the speed IN THAT DIRECTION reaches
	`addCap`. In the air addCap is tiny (AirSpeedCap), which is exactly what
	makes air strafing gain speed when you turn while strafing.
]]
local function accelerate(v, wishDir, wishSpeed, accel, dt, addCap)
	local current = v:Dot(wishDir)
	local addSpeed = (addCap or wishSpeed) - current
	if addSpeed <= 0 then
		return v
	end
	local accelSpeed = math.min(accel * dt * wishSpeed, addSpeed)
	return v + wishDir * accelSpeed
end

-- Source-engine ground friction.
local function applyFriction(v, friction, dt)
	local speed = v.Magnitude
	if speed < 0.05 then
		return Vector3.zero
	end
	local control = math.max(speed, M.StopSpeed)
	local newSpeed = math.max(speed - control * friction * dt, 0)
	return v * (newSpeed / speed)
end

-- Second Wind boost x Adrenaline power-up
local function speedMultiplier()
	local boost = now() < speedBoost.Until and speedBoost.Multiplier or 1
	return boost * stats().MoveSpeedMultiplier
end

-- Spring Legs power-up
local function jumpPower()
	return M.JumpPower * stats().JumpMultiplier
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
	params.RespectCanCollide = true -- leaves and other non-solid detail aren't walls or floors
	local exclude = { character, workspace.CurrentCamera }
	for _, name in ipairs({ "Effects", "Decoys", "Dummies", "Bots" }) do
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

--[[
	ANTI-CLIPPING: before we push the character, sweep a body-sized box in the
	direction we're about to move. If a wall is in the way, remove the part of
	the velocity that points into it, so we slide along walls instead of
	shoving into (and sometimes through) them. The box starts a little above
	the feet so curbs, steps and ramps don't count as walls.
]]
local function clipAgainstWalls(v, dt)
	local speed = v.Magnitude
	if speed < 0.5 then
		return v
	end
	local params = makeRaycastParams()
	for _ = 1, 2 do -- twice, for corners
		speed = v.Magnitude
		if speed < 0.5 then
			break
		end
		local dir = v / speed
		local start = root.Position + Vector3.new(0, 0.4, 0) - dir * 0.6
		local result = workspace:Blockcast(
			CFrame.lookAt(start, start + dir),
			Vector3.new(1.9, 3.6, 1),
			dir * (speed * dt + 1.4),
			params
		)
		if not result or math.abs(result.Normal.Y) > 0.6 then
			break
		end
		local n = Util.flat(result.Normal)
		if n.Magnitude < 0.01 then
			break
		end
		n = n.Unit
		local into = v:Dot(n)
		if into >= 0 then
			break
		end
		v -= n * into
	end
	return v
end

-- True if we are falling and the ground is just below (so a Space press now
-- should be a buffered bunny hop, not a double jump).
local function groundIsClose()
	local vy = root.AssemblyLinearVelocity.Y
	if vy > 0 then
		return false
	end
	local reach = 3.6 + math.min(-vy * M.JumpBuffer, 8)
	return workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), makeRaycastParams()) ~= nil
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

function Movement.GetWallSide()
	return mode == "WallRun" and wall.Side or 0
end

function Movement.GetGrapplePoint()
	return grapple.Point
end

function Movement.GetCooldowns()
	return {
		Grapple = math.max(0, grapple.ReadyAt - now()),
		Blink = math.max(0, blinkReadyAt - now()),
		Decoy = math.max(0, decoyReadyAt - now()),
		BulletTime = math.max(0, bulletTime.ReadyAt - now()),
	}
end

function Movement.IsGrounded()
	return humanoid ~= nil and humanoid.FloorMaterial ~= Enum.Material.Air
end

function Movement.IsSprinting()
	return mode == "Ground" and sprintHeld and momentum.Magnitude > M.RunSpeed * 0.8
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
-- Moves
----------------------------------------------------------------------------
-- PHANTOM STEP power-up: slides and wall jumps turn you invisible briefly.
local function phantomStep()
	if stats().PhantomDash and now() - lastPhantomTime > 0.6 then
		lastPhantomTime = now()
		Remotes.Get("Ability"):FireServer("PhantomDash", {})
		Controllers.Effects.PhantomFlash()
	end
end

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
	-- boost, but never above the cap (so slide spam can't snowball)
	if speed < M.SlideBoostCap then
		speed = math.min(speed + M.SlideBoost, M.SlideBoostCap)
	end
	momentum = momentum.Unit * speed
	Sfx.Play("Dash", { Pitch = 0.7, Volume = 0.6 })
	Movement.Slid:Fire()
	phantomStep()
end

local function onLanded()
	local fell = peakY - root.Position.Y
	local fallSpeed = -lowestVelocityY
	peakY = root.Position.Y
	lowestVelocityY = 0
	mode = "Ground"
	airJumpsLeft = stats().AirJumps
	bulletTime.UsedThisAir = false
	if fallSpeed > 30 then
		Sfx.Play("Land", { Volume = math.clamp(fallSpeed / 80, 0.3, 1.2) })
	end
	Movement.Landed:Fire(fallSpeed)
	lastGroundedTime = now()
	-- SHOCKWAVE LANDING power-up
	if stats().ShockwaveLanding and fell >= PU.ShockwaveLanding.MinFallHeight then
		Remotes.Get("Ability"):FireServer("Shockwave", {})
		Controllers.Camera.Shake(2.5)
	end
	if (M.SlideHold and slideHeld) or now() - slidePressedAt < 0.35 then
		startSlide()
	end
end

-- Jump off the ground (or out of a slide). Called from the step so it can
-- happen on the exact landing frame (bunny hop).
local function groundJump()
	if mode == "Slide" and momentum.Magnitude < M.SlideBoostCap then
		momentum += Util.safeUnit(momentum) * M.SlideJumpBoost
	end
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	setVerticalVelocity(jumpPower())
	-- the Humanoid can briefly hold us down (e.g. right after landing or
	-- mid-slide); re-apply the jump velocity for a few frames so jumps never fail
	forceJumpUntil = now() + 0.08
	lastGroundJumpTime = now()
	lastGroundedTime = -10
	jumpPressedAt = -10
	mode = "Air"
	peakY = root.Position.Y
	Sfx.Play("Jump", { Pitch = 0.95 + math.random() * 0.1 })
	Movement.Jumped:Fire()
end

local function endGrapple(popUp)
	if not grapple.Point then
		return
	end
	grapple.Point = nil
	grapple.ReadyAt = now() + stats().GrappleCooldown
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

-- BLINK power-up: teleport where you're looking, keeping your momentum.
local function startBlink()
	local s = stats()
	if not s.Blink or now() < blinkReadyAt then
		return
	end
	blinkReadyAt = now() + s.BlinkCooldown
	local camera = workspace.CurrentCamera
	local look = camera.CFrame.LookVector
	-- mostly horizontal: you can blink up or down a little, not straight into the floor
	local dir = Vector3.new(look.X, math.clamp(look.Y, -0.35, 0.6), look.Z).Unit
	local from = root.Position
	-- sweep a body-sized box so you can never end up inside a wall
	local hit = workspace:Blockcast(CFrame.lookAt(from, from + dir), Vector3.new(2, 4.6, 1), dir * s.BlinkDistance, makeRaycastParams())
	local to = hit and (from + dir * math.max(hit.Distance - 0.4, 0)) or (from + dir * s.BlinkDistance)
	-- don't end up inside the floor
	local floor = workspace:Raycast(to + Vector3.new(0, 3, 0), Vector3.new(0, -6, 0), makeRaycastParams())
	if floor then
		to = Vector3.new(to.X, math.max(to.Y, floor.Position.Y + 3), to.Z)
	end
	root.CFrame = CFrame.new(to) * root.CFrame.Rotation
	if mode == "Ground" or mode == "Slide" then
		mode = "Air"
	end
	Controllers.Camera.AddFovPunch(C.BlinkFOVKick)
	Controllers.Effects.Blink(from, to)
	Remotes.Get("Ability"):FireServer("Blink", { From = from, To = to })
	Sfx.Play("Dash", { Pitch = 1.7 })
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
	Sfx.Play("Jump", { Pitch = 1.15 })
	Movement.Jumped:Fire()
	phantomStep()
end

local function airJump()
	airJumpsLeft -= 1
	pendingLift = M.AirJumpVelocity * stats().JumpMultiplier
	-- re-aim momentum toward your keys (keeps your speed)
	local wish = wishDirection()
	if wish.Magnitude > 0.1 then
		momentum = wish.Unit * math.max(momentum.Magnitude, M.AirJumpMinSpeed * speedMultiplier())
	end
	mode = "Air"
	Sfx.Play("Jump", { Pitch = 1.25 })
	Movement.Jumped:Fire()
end

local function onJumpPressed()
	jumpPressedAt = now()
	if not canMove() then
		return
	end
	if mode == "WallRun" then
		wallJump()
	elseif mode == "Grapple" then
		endGrapple(true)
	elseif mode == "Air" and now() - lastGroundedTime < M.CoyoteTime then
		groundJump() -- just ran or slid off a ledge: still counts as a ground jump
	elseif mode == "Air" then
		if now() - lastGroundJumpTime < 0.12 then
			return -- we only just left the ground
		end
		if groundIsClose() then
			return -- about to land: the jump buffer turns this into a bunny hop
		end
		if airJumpsLeft > 0 then
			airJump()
		end
	end
	-- Ground / Slide jumps happen in the step (so they line up with landing)
end

----------------------------------------------------------------------------
-- Per-mode updates
----------------------------------------------------------------------------
local function updateGround(dt, wish)
	local wishSpeed = (sprintHeld and M.SprintSpeed or M.RunSpeed) * speedMultiplier()
	momentum = applyFriction(momentum, M.Friction, dt)
	if wish.Magnitude > 0.05 then
		momentum = accelerate(momentum, wish.Unit, wishSpeed * math.min(wish.Magnitude, 1), M.GroundAccel, dt)
	end
	humanoid.WalkSpeed = math.max(wishSpeed, 1)
end

local function updateAir(dt, wish)
	if wish.Magnitude < 0.05 then
		return
	end
	local dir = wish.Unit
	local mult = speedMultiplier()
	-- 1) Source air strafing: a small cap in the pressed direction but no
	--    limit on total speed (A/D + turning the mouse = more speed)
	momentum = accelerate(momentum, dir, M.AirControlSpeed * mult, M.AirAccel, dt, M.AirSpeedCap * mult)
	-- 2) Air steering: holding forward turns your momentum toward where you
	--    look, keeping your speed (easy, snappy control in the air)
	local forwardness = math.max(0, dir:Dot(cameraFlatLook()))
	if forwardness > 0 then
		momentum = steer(momentum, dir, M.AirSteer * forwardness * dt)
	end
	-- 3) When you're slow you can always get up to running speed in the air
	if momentum.Magnitude < M.AirMinSpeed * mult then
		momentum = accelerate(momentum, dir, M.AirMinSpeed * mult, M.AirLowSpeedAccel, dt)
	end
end

local function tryStartWallRun(wish)
	-- Wall Runner power-up only, once per jump, with a cooldown
	if not stats().WallRun or not wall.Recharged or now() < wall.ReadyAt then
		return false
	end
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
				wall.Y = math.max(root.AssemblyLinearVelocity.Y * 0.2, M.WallRunStartLift)
				wall.Recharged = false
				wall.ReadyAt = now() + stats().WallRunCooldown
							return true
			end
		end
	end
	return false
end

local function updateWallRun(dt, wish)
	local result =
		workspace:Raycast(root.Position, -wall.Normal * (M.WallCheckDistance + 1.5), makeRaycastParams())
	wall.Timer += dt
	local expired = wall.Timer > stats().WallRunTime
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
	-- no speed boost: capped, and the wall slowly drags you down
	local speed = math.min(momentum.Magnitude, M.WallRunMaxSpeed * speedMultiplier()) * (1 - M.WallRunDrag * dt)
	momentum = Util.safeUnit(along) * speed - wall.Normal * 3 -- press into the wall

	wall.Y -= M.WallRunGravity * dt
	setVerticalVelocity(wall.Y)
end

local function updateSlide(dt, wish)
	momentum = applyFriction(momentum, M.SlideFriction, dt)
	momentum = steer(momentum, wish, M.SlideSteer * dt)
	if momentum.Magnitude < M.SlideEndSpeed or (M.SlideHold and not slideHeld) then
		mode = "Ground"
		return
	end
	humanoid.WalkSpeed = 4 -- calm the run animation while sliding
end

local function updateGrapple(dt)
	grapple.Timer += dt
	local toPoint = grapple.Point - root.Position
	if toPoint.Magnitude < M.GrappleReleaseDistance or grapple.Timer > M.GrappleMaxTime then
		endGrapple(false)
		return
	end
	local velocity = Vector3.new(momentum.X, root.AssemblyLinearVelocity.Y, momentum.Z)
	local pull = M.GrapplePullSpeed * stats().GrapplePull
	velocity = approachVector(velocity, toPoint.Unit * pull, M.GrappleAccel * stats().GrapplePull * dt)
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
	-- runs like the ground, but with no friction so you keep your speed
	if wish.Magnitude > 0.05 then
		momentum = accelerate(momentum, wish.Unit, M.SprintSpeed * speedMultiplier(), M.GroundAccel, dt)
	end
	setVerticalVelocity(3) -- keep pressed against the ceiling
	airJumpsLeft = stats().AirJumps
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
		bulletTime.Until = now() + stats().BulletTimeDuration
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
	if mode ~= "Grapple" and mode ~= "WallRun" and not Movement.IsBulletTime() then
		if horizontal.Magnitude < lastDrive.Magnitude - 3 then
			momentum = horizontal + (momentum - lastDrive)
		end
	end

	-- External impulses (knockback / rocket jump / double jump)
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
	local justLaunched = now() - math.max(lastGroundJumpTime, lastLiftTime) < 0.12
	local grounded = Movement.IsGrounded() and not justLaunched
	local wish = wishDirection()
	if now() < forceJumpUntil and root.AssemblyLinearVelocity.Y < jumpPower() * 0.75 then
		setVerticalVelocity(jumpPower())
	end
	if not grounded then
		peakY = math.max(peakY, root.Position.Y) -- for Shockwave Landing
		lowestVelocityY = math.min(lowestVelocityY, velocity.Y)
	end

	-- Ground <-> air transitions
	if grounded and (mode == "Air" or mode == "WallRun" or mode == "Ceiling") then
		onLanded()
	elseif not grounded and (mode == "Ground" or mode == "Slide") then
		mode = "Air"
		peakY = root.Position.Y
	end

	-- JUMP / BUNNY HOP: holding Space (or a buffered press) jumps on the very
	-- frame we touch the ground, BEFORE friction runs, so no speed is lost.
	if grounded and (mode == "Ground" or mode == "Slide") then
		lastGroundedTime = now()
		wall.Recharged = true -- touching the ground recharges your wall run
		local wantsJump = (M.AutoBhop and jumpHeld) or (now() - jumpPressedAt < M.JumpBuffer)
		if wantsJump then
			groundJump()
		end
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
	elseif mode == "Grapple" then
		updateGrapple(dt)
	elseif mode == "Ceiling" then
		updateCeiling(dt, wish)
	end

	-- hard speed limit
	local maxSpeed = M.MaxSpeed * stats().MoveSpeedMultiplier
	if momentum.Magnitude > maxSpeed then
		momentum = momentum.Unit * maxSpeed
	end

	-- never push into walls (prevents clipping / phasing through thin walls)
	if mode ~= "WallRun" then
		momentum = clipAgainstWalls(momentum, dt)
	end

	-- FEATHERWEIGHT power-up: cancel part of gravity while airborne
	local gravityScale = stats().GravityScale
	if gravityScale < 1 and mode == "Air" and not Movement.IsBulletTime() then
		local v = root.AssemblyLinearVelocity
		setVerticalVelocity(v.Y + workspace.Gravity * (1 - gravityScale) * dt)
	end

	updateBulletTime(dt, grounded)

	-- Drive the character
	local drive = momentum
	if Movement.IsBulletTime() then
		drive *= PU.BulletTime.MoveScale
	end
	linearVelocity.PlaneVelocity = Vector2.new(drive.X, drive.Z)
	lastDrive = drive
	humanoid.JumpPower = 0 -- jumps are done by this script (so the Jump key can be rebound)

	-- FOV kick from movement
	local speed = momentum.Magnitude
	local kick = 0
	if mode == "Slide" then
		kick = C.SlideFOVKick
	elseif mode == "WallRun" then
		kick = C.WallRunFOVKick
	elseif speed > M.RunSpeed + 2 then
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
	humanoid.JumpPower = 0 -- jumps are done by this script (so the Jump key can be rebound)
	-- Roblox's own jump is always on Space; turn it off so only our Jump bind jumps
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	humanoid.WalkSpeed = M.RunSpeed

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
	grapple.Point = nil
	speedBoost.Until = 0
	bulletTime.Until = 0
	peakY = root.Position.Y
	lowestVelocityY = 0

	humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Jumping and (mode == "Ground" or mode == "Slide") then
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
	if Keybinds.Matches("Jump", input) then
		jumpHeld = true
		onJumpPressed()
	elseif Keybinds.Matches("Sprint", input) then
		sprintHeld = true
	elseif Keybinds.Matches("Slide", input) then
		slideHeld = true
		if canMove() then
			if mode == "Ground" then
				startSlide()
			elseif mode == "Slide" and not M.SlideHold then
				mode = "Ground" -- tap again to stand up
			elseif mode == "Air" then
				slidePressedAt = now() -- slide as soon as we land
			end
		end
	elseif Keybinds.Matches("Grapple", input) then
		if canMove() then
			if grapple.Point then
				endGrapple(false)
			else
				startGrapple()
			end
		end
	elseif Keybinds.Matches("Blink", input) then
		if canMove() and ClientState.CanShoot() then
			startBlink()
		end
	elseif Keybinds.Matches("Decoy", input) then
		if canMove() and ClientState.CanShoot() then
			startDecoy()
		end
	end
end

local function onInputEnded(input)
	if Keybinds.Matches("Jump", input) then
		jumpHeld = false
	elseif Keybinds.Matches("Sprint", input) then
		sprintHeld = false
	elseif Keybinds.Matches("Slide", input) then
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
