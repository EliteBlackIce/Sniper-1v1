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

	Runs right AFTER Roblox's default camera each frame, so it only adds
	small offsets on top of the normal first-person camera.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
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
local currentRoll = 0
local currentDrop = 0
local recoilLeft = 0 -- degrees of pitch still to apply
local fovPunch = 0
local shake = 0
local bobTime = 0
local bobAmount = 0
local landDip = 0 -- current camera dip from landing (studs)
local landDipVelocity = 0
local hiddenParts = {}
local firstPerson = false

----------------------------------------------------------------------------
-- Public API (used by other controllers)
----------------------------------------------------------------------------
function CameraController.AddRecoil(degrees)
	recoilLeft += degrees
end

function CameraController.AddFovPunch(amount)
	fovPunch = math.max(fovPunch, amount)
end

function CameraController.Shake(amount)
	shake = math.max(shake, amount)
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
local function update(dt)
	local camera = workspace.CurrentCamera
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not camera then
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
	local targetFov = C.BaseFOV + hints.FovKick
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
		humanoid.CameraOffset = Vector3.new(0, -currentDrop + bobY + landDip, 0)
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
		local shakeOffset = CFrame.identity
		if shake > 0.01 then
			shakeOffset = CFrame.Angles(
				math.rad((math.random() - 0.5) * shake),
				math.rad((math.random() - 0.5) * shake),
				0
			)
			shake = Util.approach(shake, 0, 12 * dt)
		end
		camera.CFrame *= CFrame.Angles(0, 0, math.rad(currentRoll)) * shakeOffset

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
	RunService:BindToRenderStep("SniperCamera", Enum.RenderPriority.Camera.Value + 1, update)
end

return CameraController
