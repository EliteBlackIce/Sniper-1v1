--[[
	CameraController.lua  (Client.CameraController)

	* Locks the camera in first person during matches (CameraMode =
	  LockFirstPerson, max zoom 0.5 so you can never zoom out).
	* Hides your own body so it never clips into the camera.
	* FOV: base FOV + movement kicks (sprint / slide / dash / wall run / speed),
	  zooms in while scoped.
	* Camera roll during wall runs and slides, lowered camera while sliding.
	* Aim recoil (kicks your aim up a little each shot).
	* Mouse sensitivity from settings (separate scoped sensitivity).
	* Frees the mouse while a menu is open (pick screen, settings, victory).
	* Screen shake + hit flinch are smooth (noise, not per-frame random) and
	  RESTORATIVE: each frame only the change since last frame is applied,
	  so when they settle your aim is exactly where it was. Scaled by
	  Config.Effects.ScreenShake (number, 0 / false = off) if it is set.

	Runs right AFTER Roblox's default camera each frame, so it only adds
	small offsets on top of the normal first-person camera.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local ClientState = require(script.Parent.ClientState)
local AimAssist = require(script.Parent.AimAssist)

local C = Config.Camera
local player = Players.LocalPlayer

local CameraController = {}
local Controllers

local currentFov = C.BaseFOV
local rightStick = Vector2.zero -- controller look stick (we handle it ourselves)
local touchLook = Vector2.zero -- pixels dragged on the touch look pad since last frame
local currentRoll = 0
local currentDrop = 0
local recoilLeft = 0 -- degrees of pitch still to apply
local fovPunch = 0
local shake = 0
local flinchPitch, flinchYaw, flinchRoll = 0, 0, 0 -- degrees, decaying (hit flinch)
local appliedPitch, appliedYaw = 0, 0 -- the view offset applied last frame
local shakeSeed = math.random() * 100
local bobTime = 0
local bobAmount = 0
local landDip = 0 -- current camera dip from landing (studs)
local landDipVelocity = 0
local hiddenParts = {}
local firstPerson = false

----------------------------------------------------------------------------
-- Public API (used by other controllers)
----------------------------------------------------------------------------
-- Mobile: the look pad (ui/MobileControls) adds finger movement here.
function CameraController.AddTouchLook(delta)
	touchLook += delta
end

function CameraController.AddRecoil(degrees)
	recoilLeft += degrees
end

function CameraController.AddFovPunch(amount)
	fovPunch = math.max(fovPunch, amount)
end

local function shakeScale()
	local s = Config.Effects and Config.Effects.ScreenShake
	if s == false then
		return 0
	end
	return typeof(s) == "number" and math.max(s, 0) or 1
end

function CameraController.Shake(amount)
	if typeof(amount) == "number" then
		shake = math.max(shake, amount)
	end
end

-- Getting hit: the view flinches a little away from the shot (side = -1 / 1)
-- and settles back to the exact same aim.
function CameraController.Flinch(side, amount)
	amount = (typeof(amount) == "number" and amount or 1) * shakeScale()
	side = typeof(side) == "number" and side or 0
	flinchPitch += 0.9 * amount
	flinchYaw += 0.7 * amount * side
	flinchRoll += 2.2 * amount * side
end

-- Camera dips down on landing (bigger fall = bigger dip), then springs back.
function CameraController.LandingDip(fallSpeed)
	-- normal jumps / bunny hops land at ~50 u/s and only get a tiny dip
	local dip = math.min(0.04 + math.max(fallSpeed - 45, 0) * C.LandingDip, C.MaxLandingDip)
	landDipVelocity -= dip * 14
end

function CameraController.IsFirstPerson()
	return firstPerson
end

-- Turns the camera to look the way the character faces (used at spawn).
function CameraController.FaceCharacterForward()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	if root and camera then
		local eye = root.Position + Vector3.new(0, 1.5, 0)
		camera.CFrame = CFrame.lookAt(eye, eye + root.CFrame.LookVector)
	end
end

----------------------------------------------------------------------------
-- Body hiding
----------------------------------------------------------------------------
local function trackCharacter(character)
	table.clear(hiddenParts)
	local function add(item)
		if item:IsA("BasePart") then
			table.insert(hiddenParts, item)
		end
	end
	for _, item in ipairs(character:GetDescendants()) do
		add(item)
	end
	character.DescendantAdded:Connect(add)
end

local function setBodyHidden(hidden)
	local value = hidden and 1 or 0
	for _, part in ipairs(hiddenParts) do
		if part.Parent then
			part.LocalTransparencyModifier = value
		end
	end
end

----------------------------------------------------------------------------
-- Camera mode
----------------------------------------------------------------------------
local function wantsFirstPerson()
	return ClientState.InMatch() or C.FirstPersonInLobby
end

local function applyCameraMode()
	firstPerson = wantsFirstPerson()
	if firstPerson then
		player.CameraMode = Enum.CameraMode.LockFirstPerson
		player.CameraMaxZoomDistance = 0.5
		player.CameraMinZoomDistance = 0.5
	else
		player.CameraMode = Enum.CameraMode.Classic
		player.CameraMinZoomDistance = 0.5
		player.CameraMaxZoomDistance = 18
	end
end

----------------------------------------------------------------------------
-- Per-frame update (after the default camera)
----------------------------------------------------------------------------
local suspended = false

-- The kill cam takes over the camera while it plays.
function CameraController.SetSuspended(value)
	suspended = value
end

local function update(dt)
	local camera = workspace.CurrentCamera
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not camera or suspended then
		-- (someone else owns the camera: forget the offset, don't "undo" it later)
		appliedPitch, appliedYaw = 0, 0
		shake, flinchPitch, flinchYaw, flinchRoll = 0, 0, 0, 0
		return
	end

	-- Keep enforcing the mode (respawns can reset it)
	if wantsFirstPerson() ~= firstPerson or (firstPerson and player.CameraMode ~= Enum.CameraMode.LockFirstPerson) then
		applyCameraMode()
	end

	local movement = Controllers.Movement
	local weapon = Controllers.Weapon
	local hints = movement.GetCameraHints()
	local scopeAlpha = weapon.GetScopeAlpha()

	-- FIELD OF VIEW
	local targetFov = (ClientState.Settings.FieldOfView or C.BaseFOV) + hints.FovKick
	targetFov = Util.lerp(targetFov, C.ScopeFOV, scopeAlpha)
	fovPunch = Util.approach(fovPunch, 0, 40 * dt)
	currentFov = Util.lerp(currentFov, targetFov, Util.smooth(C.FOVLerpSpeed, dt))
	camera.FieldOfView = math.clamp(currentFov + fovPunch * (1 - scopeAlpha), 1, 120)

	-- SENSITIVITY
	local settings = ClientState.Settings
	local sensitivity = settings.Sensitivity
	if scopeAlpha > 0.5 then
		sensitivity = settings.ScopedSensitivity
	end
	if movement.IsBulletTime() then
		sensitivity *= Config.PowerUps.BulletTime.SensitivityScale
	end
	UserInputService.MouseDeltaSensitivity = sensitivity

	-- CAMERA OFFSET: slide drop + running head bob + landing dip
	-- (CameraOffset is used by the default camera next frame)
	currentDrop = Util.lerp(currentDrop, hints.Drop, Util.smooth(C.CameraDropLerpSpeed, dt))
	local speed = movement.GetSpeed()
	local running = movement.IsGrounded() and movement.GetMode() == "Ground" and speed > 4
	bobAmount = Util.lerp(bobAmount, running and math.clamp(speed / Config.Movement.RunSpeed, 0, 1.3) or 0, Util.smooth(10, dt))
	bobTime += dt * (7 + speed * 0.18)
	local bobY = math.sin(bobTime * 2) * C.HeadBob * bobAmount * (1 - scopeAlpha)
	-- landing dip spring
	landDipVelocity += (-landDip * 180 - landDipVelocity * 18) * dt
	landDip += landDipVelocity * dt
	if humanoid then
		-- (first person sits a little behind your eyes so your real arms aren't in your face)
		local back = firstPerson and (Config.Body.CameraBack or 0) or 0
		humanoid.CameraOffset = Vector3.new(0, -currentDrop + bobY + landDip, back)
	end

	-- CONTROLLER LOOK: right stick, with its own sensitivity / deadzone / curve
	if not ClientState.MenuOpen then
		local dz = settings.ControllerDeadzone or 0.15
		local mag = rightStick.Magnitude
		if mag > dz then
			local CC = Config.Controller
			local amount = ((math.min(mag, 1) - dz) / (1 - dz)) ^ CC.ResponseCurve
			local dir = rightStick.Unit * amount
			local sens = scopeAlpha > 0.5 and settings.ControllerScopedSensitivity or settings.ControllerSensitivity
			if movement.IsBulletTime() then
				sens *= Config.PowerUps.BulletTime.SensitivityScale
			end
			local rate = math.rad(CC.TurnSpeed) * (sens or 1) * dt
			local cf = camera.CFrame
			local look = cf.LookVector
			local pitch = math.asin(math.clamp(look.Y, -1, 1))
			local newPitch = math.clamp(pitch + dir.Y * rate * CC.VerticalScale * (settings.InvertY and -1 or 1), -1.4, 1.4)
			local flat = Util.safeUnit(Vector3.new(look.X, 0, look.Z), Vector3.new(0, 0, -1))
			flat = CFrame.Angles(0, -dir.X * rate, 0):VectorToWorldSpace(flat)
			local newLook = flat * math.cos(newPitch) + Vector3.new(0, math.sin(newPitch), 0)
			camera.CFrame = CFrame.lookAt(cf.Position, cf.Position + newLook)
		end
	end

	-- TOUCH LOOK: drag on the right side of the screen
	if touchLook.Magnitude > 0 then
		if not ClientState.MenuOpen then
			local sens = scopeAlpha > 0.5 and (settings.TouchScopedSensitivity or 0.4) or (settings.TouchSensitivity or 1)
			if movement.IsBulletTime() then
				sens *= Config.PowerUps.BulletTime.SensitivityScale
			end
			local k = math.rad(Config.Touch.DegreesPerPixel) * sens
			local cf = camera.CFrame
			local look = cf.LookVector
			local pitch = math.asin(math.clamp(look.Y, -1, 1))
			local newPitch = math.clamp(pitch - touchLook.Y * k * (settings.InvertY and -1 or 1), -1.4, 1.4)
			local flat = Util.safeUnit(Vector3.new(look.X, 0, look.Z), Vector3.new(0, 0, -1))
			flat = CFrame.Angles(0, -touchLook.X * k, 0):VectorToWorldSpace(flat)
			local newLook = flat * math.cos(newPitch) + Vector3.new(0, math.sin(newPitch), 0)
			camera.CFrame = CFrame.lookAt(cf.Position, cf.Position + newLook)
		end
		touchLook = Vector2.zero
	end

	if firstPerson then
		-- AIM ASSIST (controller only): slowdown + gentle pull near a target
		AimAssist.Update(camera, dt, scopeAlpha)

		-- RECOIL: apply the kick over a few frames (this really moves your aim)
		if recoilLeft > 0.001 then
			local step = recoilLeft * math.min(1, dt * 25)
			recoilLeft -= step
			camera.CFrame *= CFrame.Angles(math.rad(step), 0, 0)
		end

		-- ROLL (wall run / slide / strafe tilt). Roll doesn't change the look
		-- direction, so it never affects aim.
		currentRoll = Util.lerp(currentRoll, hints.Roll, Util.smooth(C.TiltLerpSpeed, dt))
		-- SHAKE + FLINCH: smooth noise; only the change since last frame is
		-- applied to pitch / yaw (the default camera keeps it), so the aim
		-- returns exactly when they settle. Roll is re-applied every frame.
		local amp = shake * shakeScale()
		local t = os.clock() * 24
		local wantPitch = math.noise(t, shakeSeed) * amp + flinchPitch
		local wantYaw = math.noise(shakeSeed, t) * amp + flinchYaw
		local shakeRoll = math.noise(t * 0.8, shakeSeed + 7) * amp * 0.8 + flinchRoll
		if shake > 0 then
			shake = Util.approach(shake, 0, 12 * dt)
		end
		local decay = math.exp(-dt * 11)
		flinchPitch *= decay
		flinchYaw *= decay
		flinchRoll *= decay
		local dPitch, dYaw = wantPitch - appliedPitch, wantYaw - appliedYaw
		appliedPitch, appliedYaw = wantPitch, wantYaw
		camera.CFrame *= CFrame.Angles(math.rad(dPitch), math.rad(dYaw), 0)
			* CFrame.Angles(0, 0, math.rad(currentRoll + shakeRoll))

		setBodyHidden(true)

		-- MOUSE: free it while a menu is open, hide the cursor otherwise
		if ClientState.MenuOpen then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		else
			UserInputService.MouseIconEnabled = false
		end
	else
		currentRoll = 0
		appliedPitch, appliedYaw = 0, 0
		UserInputService.MouseIconEnabled = true
	end
end

function CameraController.Init(controllers)
	Controllers = controllers
end

function CameraController.Start()
	if player.Character then
		trackCharacter(player.Character)
	end
	player.CharacterAdded:Connect(trackCharacter)

	applyCameraMode()
	ClientState.Changed:Connect(function(snapshot, old)
		applyCameraMode()
		if snapshot.Phase == "Countdown" and old.Phase ~= "Countdown" then
			-- new round: look toward the arena centre
			task.delay(0.05, CameraController.FaceCharacterForward)
		end
	end)

	Controllers.Movement.Landed:Connect(CameraController.LandingDip)

	AimAssist.Start()
	-- take the right stick away from Roblox's camera so our controller
	-- sensitivity / deadzone settings are used instead
	ContextActionService:BindActionAtPriority("SniperControllerLook", function(_, state, input)
		if state == Enum.UserInputState.Cancel or state == Enum.UserInputState.End then
			rightStick = Vector2.zero
		else
			rightStick = Vector2.new(input.Position.X, input.Position.Y)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 50, Enum.KeyCode.Thumbstick2)
	RunService:BindToRenderStep("SniperCamera", Enum.RenderPriority.Camera.Value + 1, update)
end

return CameraController
