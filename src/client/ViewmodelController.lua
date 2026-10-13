--[[
	ViewmodelController.lua  (Client.ViewmodelController)

	First-person arms + sniper, built from flat-coloured parts and attached to
	the camera. Only YOU see it (it lives inside workspace.CurrentCamera).
	The rifle itself comes from Shared/GunModel (same model other players see).

	All animation is procedural (no animation assets needed):
		equip     gun swings up into view when you spawn
		sway      lags behind mouse movement
		bob       figure-8 walk/run bob, stronger when sprinting
		jump/land gun dips when you jump and slams down when you land hard
		dash      gun pulls back
		poses     lowered while sprinting, canted while sliding, tilted on wall runs
		recoil    kick back + up, muzzle flash
		bolt      right hand leaves the grip, works the bolt, comes back
		aim       slides to the centre when scoping, then hides behind the scope
		inspect   press V to admire the rifle

	Gun space: origin = right hand on the grip, +X right, +Y up, -Z forward.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local GunModel = require(Shared.GunModel)
local Util = require(Shared.Util)
local ClientState = require(script.Parent.ClientState)
local Spring = require(script.Parent.Spring)
local Sfx = require(script.Parent.Sfx)

local Palette = Config.Palette
local VM = Config.Viewmodel
local player = Players.LocalPlayer

local Viewmodel = {}
local Controllers

local rad = math.rad

-- Where the grip sits in camera space when hip-firing / aiming down the scope.
local HIP_OFFSET = CFrame.new(0.62, -0.7, -1.1)
local ADS_OFFSET = CFrame.new(-GunModel.ScopeEye.X, -GunModel.ScopeEye.Y, -0.55 - GunModel.ScopeEye.Z)
local SPRINT_POSE = CFrame.new(-0.1, -0.22, 0.15) * CFrame.Angles(rad(-16), rad(38), rad(14))
local EQUIP_POSE = CFrame.new(0.15, -1.2, 0.45) * CFrame.Angles(rad(-55), rad(25), rad(20))

-- Hands (gun space)
local RIGHT_GRIP = CFrame.new(0, -0.22, 0.18) * CFrame.Angles(rad(-18), 0, 0)
local KNOB_HOLD = CFrame.new(0.3, 0.02, 0.07) -- relative to the animated bolt pivot
local LEFT_HOLD = CFrame.new(0, -0.21, -1.15) -- behind the folded bipod
-- Arm joints (gun space). Shoulders sit behind the camera, out of view.
local RIGHT_ELBOW = Vector3.new(0.42, -0.62, 0.78)
local RIGHT_SHOULDER = Vector3.new(0.95, -1.1, 1.9)
local LEFT_ELBOW = Vector3.new(-0.42, -0.62, -0.55)
local LEFT_SHOULDER = Vector3.new(-1.0, -1.05, 0.95)

local model
local gun -- result of GunModel.Build
local parts = {} -- extra parts: hands, arms, flash
local visible = false

local swaySpring = Spring.new(140, 16) -- rotation (degrees)
local recoilSpring = Spring.new(220, 18) -- X = pitch, Y = push back, Z = roll
local moveSpring = Spring.new(150, 13) -- position offset from jumps / landings / dashes
local bobTime = 0
local sprintAlpha, slideAlpha, wallAlpha, airOffset = 0, 0, 0, 0
local boltStart, boltDuration = 0, 0
local boltSoundPlayed = true
local equipStart = -10
local inspectStart, inspecting = 0, false
local flashUntil = 0
local lastCharacter
local hadGun = false

----------------------------------------------------------------------------
-- Building
----------------------------------------------------------------------------
local function addPart(name, size, color, shape)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	if shape then
		part.Shape = shape
	end
	part.Parent = model
	parts[name] = part
	return part
end

local function build()
	model = Instance.new("Model")
	model.Name = "Viewmodel"
	gun = GunModel.Build(model, { Anchored = true })

	-- Gloved hands
	for _, side in ipairs({ "Right", "Left" }) do
		addPart(side .. "Palm", Vector3.new(0.21, 0.27, 0.25), Palette.Glove)
		addPart(side .. "Fingers", Vector3.new(0.22, 0.23, 0.08), Palette.Glove)
		addPart(side .. "Thumb", Vector3.new(0.07, 0.07, 0.19), Palette.Glove)
		addPart(side .. "Cuff", Vector3.new(0.3, 0.3, 0.14), Palette.SleeveCuff)
		addPart(side .. "Forearm", Vector3.new(0.27, 0.27, 1), Palette.Sleeve)
		addPart(side .. "Elbow", Vector3.new(0.3, 0.3, 0.3), Palette.Sleeve, Enum.PartType.Ball)
		addPart(side .. "UpperArm", Vector3.new(0.32, 0.32, 1), Palette.Sleeve)
	end
	-- the left palm lies flat under the handguard
	parts.LeftPalm.Size = Vector3.new(0.27, 0.1, 0.33)
	parts.LeftFingers.Size = Vector3.new(0.06, 0.2, 0.28)
	parts.LeftThumb.Size = Vector3.new(0.06, 0.14, 0.2)

	-- Muzzle flash (a flat star)
	addPart("FlashCore", Vector3.new(0.4, 0.4, 0.4), Palette.MuzzleFlash, Enum.PartType.Ball)
	addPart("FlashA", Vector3.new(0.07, 0.9, 0.07), Palette.MuzzleFlash)
	addPart("FlashB", Vector3.new(0.9, 0.07, 0.07), Palette.MuzzleFlash)
	addPart("FlashLong", Vector3.new(0.12, 0.12, 0.7), Palette.MuzzleFlash)
	for _, name in ipairs({ "FlashCore", "FlashA", "FlashB", "FlashLong" }) do
		if Config.Effects.NeonEffects then
			parts[name].Material = Enum.Material.Neon -- glows with bloom
		end
	end
	-- a light that flashes with each shot (lights up your arms and the room)
	local light = Instance.new("PointLight")
	light.Name = "MuzzleLight"
	light.Color = Palette.MuzzleFlash
	light.Range = 14
	light.Brightness = 0
	light.Shadows = false
	light.Parent = parts.FlashCore

	model.Parent = workspace.CurrentCamera
end

-- CFrame for a limb part stretched between points a and b.
local function limbBetween(part, a, b)
	local length = math.max((b - a).Magnitude, 0.05)
	if math.abs(part.Size.Z - length) > 0.001 then
		part.Size = Vector3.new(part.Size.X, part.Size.Y, length)
	end
	return CFrame.lookAt((a + b) / 2, b)
end

----------------------------------------------------------------------------
-- Animation helpers
----------------------------------------------------------------------------
local function easeOutBack(t)
	local c1, c3 = 1.4, 2.4
	return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

local function seg(t, a, b)
	return math.clamp((t - a) / (b - a), 0, 1)
end

local function smoothstep(t)
	return t * t * (3 - 2 * t)
end

-- Bolt cycle for progress t (0-1).
-- Returns: bolt pivot CFrame (gun space), right hand CFrame (gun space), gun roll.
local function boltPose(t)
	-- reach (0-.15) lift (.15-.3) pull (.3-.5) push (.5-.68) lower (.68-.8) return (.8-1)
	local lift = smoothstep(seg(t, 0.15, 0.3)) - smoothstep(seg(t, 0.68, 0.8))
	local pull = smoothstep(seg(t, 0.3, 0.5)) - smoothstep(seg(t, 0.5, 0.68))
	local pivot = GunModel.BoltPivot * CFrame.new(0, 0, pull * 0.4) * CFrame.Angles(0, 0, rad(80) * lift)
	local onKnob = pivot * KNOB_HOLD * CFrame.Angles(0, 0, rad(-25))
	local reach = smoothstep(seg(t, 0, 0.15))
	local back = smoothstep(seg(t, 0.8, 1))
	local hand
	if t <= 0 or t >= 1 then
		hand = RIGHT_GRIP
	elseif t < 0.15 then
		hand = RIGHT_GRIP:Lerp(onKnob, reach)
	elseif t < 0.8 then
		hand = onKnob
	else
		hand = onKnob:Lerp(RIGHT_GRIP, back)
	end
	local roll = math.sin(math.clamp(t, 0, 1) * math.pi) * rad(16)
	return pivot, hand, roll
end

----------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------
function Viewmodel.PlayFire(scoped)
	local kick = scoped and 0.5 or 1
	recoilSpring:Impulse(Vector3.new(22 * kick, 9 * kick, (math.random() - 0.5) * 8))
	flashUntil = os.clock() + 0.05
	inspecting = false
end

function Viewmodel.PlayBolt(duration)
	boltStart = os.clock()
	boltDuration = duration
	boltSoundPlayed = false
end

function Viewmodel.PlayEquip()
	equipStart = os.clock()
	inspecting = false
	Sfx.Play("Bolt", { Pitch = 1.3, Volume = 0.6 })
end

function Viewmodel.GetMuzzlePosition()
	if gun and gun.Parts.Receiver then
		local grip = gun.Parts.Receiver.CFrame * gun.Offsets.Receiver:Inverse()
		return (grip * GunModel.Muzzle).Position
	end
	return workspace.CurrentCamera.CFrame.Position
end

function Viewmodel.GetLeftHandPosition()
	return parts.LeftPalm and parts.LeftPalm.Position or workspace.CurrentCamera.CFrame.Position
end

local function setVisible(v)
	if v == visible then
		return
	end
	visible = v
	for _, part in pairs(gun.Parts) do
		part.LocalTransparencyModifier = v and 0 or 1
	end
	for name, part in pairs(parts) do
		if not name:find("Flash") then
			part.LocalTransparencyModifier = v and 0 or 1
		end
	end
end

----------------------------------------------------------------------------
-- Per-frame update
----------------------------------------------------------------------------
local function update(dt)
	local camera = workspace.CurrentCamera
	if model.Parent ~= camera then
		model.Parent = camera
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local alive = humanoid ~= nil and humanoid.Health > 0
	local hasGun = ClientState.HasGun()
	local scopeAlpha = Controllers.Weapon.GetScopeAlpha()

	-- replay the equip animation on a new life / when the gun comes back
	if alive and hasGun and (character ~= lastCharacter or not hadGun) then
		Viewmodel.PlayEquip()
	end
	lastCharacter = character
	hadGun = alive and hasGun

	local shouldShow = alive and hasGun and Controllers.Camera.IsFirstPerson() and scopeAlpha < 0.92
	setVisible(shouldShow)
	if not shouldShow then
		for name, part in pairs(parts) do
			if name:find("Flash") then
				part.LocalTransparencyModifier = 1
			end
		end
		if not hasGun then
			return
		end
	end

	local movement = Controllers.Movement
	local mode = movement.GetMode()
	local speed = movement.GetSpeed()
	local grounded = movement.IsGrounded()
	local t = os.clock()

	-- SWAY from mouse movement
	local delta = UserInputService:GetMouseDelta()
	local swayScale = (1 - scopeAlpha * 0.85) * VM.SwayAmount
	swaySpring.Target = Vector3.new(
		math.clamp(-delta.Y * swayScale, -5, 5),
		math.clamp(-delta.X * swayScale, -5, 5),
		math.clamp(-delta.X * swayScale * 0.7, -4, 4)
	)
	local sway = swaySpring:Update(dt)

	-- BOB: figure-8 while running on the ground
	local running = grounded and speed > 2 and mode == "Ground"
	if running then
		bobTime += dt * (7 + speed * 0.2)
	end
	local bobAmount = running and math.clamp(speed / Config.Movement.RunSpeed, 0, 1.4) * (1 - scopeAlpha * 0.9) * VM.BobAmount or 0
	local idle = math.sin(t * 1.7) * 0.012
	local bobPos = Vector3.new(math.sin(bobTime) * 0.05, math.sin(bobTime * 2) * 0.035 + idle, 0) * bobAmount
	local bobRoll = math.sin(bobTime) * rad(2.2) * bobAmount

	-- POSES
	local boltT = boltDuration > 0 and (t - boltStart) / boltDuration or 1
	local cycling = boltT < 1
	local sprinting = movement.IsSprinting() and scopeAlpha < 0.1 and not cycling
	sprintAlpha = Util.lerp(sprintAlpha, sprinting and 1 or 0, Util.smooth(10, dt))
	slideAlpha = Util.lerp(slideAlpha, mode == "Slide" and 1 or 0, Util.smooth(12, dt))
	wallAlpha = Util.lerp(wallAlpha, movement.GetWallSide(), Util.smooth(10, dt))
	local vy = root and root.AssemblyLinearVelocity.Y or 0
	airOffset = Util.lerp(airOffset, grounded and 0 or math.clamp(-vy * 0.0025, -0.1, 0.1), Util.smooth(8, dt))

	-- EQUIP
	local equipT = math.clamp((t - equipStart) / VM.EquipTime, 0, 1)
	local equipPose = EQUIP_POSE:Lerp(CFrame.identity, easeOutBack(equipT))

	-- INSPECT (V)
	local inspectPose = CFrame.identity
	if inspecting then
		local it = (t - inspectStart) / 2.4
		if it >= 1 or scopeAlpha > 0.05 or cycling then
			inspecting = false
		else
			local w = math.sin(it * math.pi) ^ 0.7
			local wiggle = math.sin(it * math.pi * 3) * 0.08 * w
			inspectPose = CFrame.new(-0.4 * w, 0.2 * w, 0.3 * w)
				* CFrame.Angles(rad(12) * w + wiggle, rad(55) * w, rad(-40) * w)
		end
	end

	-- SPRINGS
	local recoil = recoilSpring:Update(dt)
	local kick = moveSpring:Update(dt)

	-- BOLT
	local boltPivot, rightHand, boltRoll = boltPose(math.clamp(boltT, 0, 1))
	if cycling and not boltSoundPlayed and boltT > 0.3 then
		boltSoundPlayed = true
		Sfx.Play("Bolt")
	end

	-- Combine everything into the grip CFrame (camera space -> world)
	local base = HIP_OFFSET:Lerp(ADS_OFFSET, scopeAlpha)
	local pose = CFrame.identity:Lerp(SPRINT_POSE, sprintAlpha)
		* CFrame.new(0, -0.14 * slideAlpha, 0.05 * slideAlpha)
		* CFrame.Angles(0, 0, rad(-18) * slideAlpha)
		* CFrame.Angles(0, 0, rad(9) * wallAlpha)
	local grip = camera.CFrame
		* base
		* equipPose
		* inspectPose
		* pose
		* CFrame.new(bobPos.X + kick.X, bobPos.Y + airOffset + kick.Y, kick.Z + recoil.Y * 0.02)
		* CFrame.Angles(rad(sway.X + recoil.X * 0.35), rad(sway.Y), rad(sway.Z + recoil.Z * 0.3) + bobRoll)
		* CFrame.Angles(0, 0, -boltRoll)

	local list, cframes = {}, {}
	local function put(part, cf)
		table.insert(list, part)
		table.insert(cframes, cf)
	end

	-- Gun (bolt parts follow the animated bolt pivot)
	local boltWorld = grip * boltPivot
	for name, part in pairs(gun.Parts) do
		put(part, (gun.Bolt[name] and boltWorld or grip) * gun.Offsets[name])
	end

	-- Right hand + arm
	local rh = grip * rightHand
	put(parts.RightPalm, rh)
	put(parts.RightFingers, rh * CFrame.new(0, -0.02, -0.15))
	put(parts.RightThumb, rh * CFrame.new(-0.12, 0.07, -0.06))
	local rWrist = (rightHand * CFrame.new(0, -0.04, 0.17)).Position
	put(parts.RightCuff, grip * limbBetween(parts.RightCuff, rWrist, rWrist + (RIGHT_ELBOW - rWrist).Unit * 0.14))
	put(parts.RightForearm, grip * limbBetween(parts.RightForearm, RIGHT_ELBOW, rWrist))
	put(parts.RightElbow, grip * CFrame.new(RIGHT_ELBOW))
	put(parts.RightUpperArm, grip * limbBetween(parts.RightUpperArm, RIGHT_SHOULDER, RIGHT_ELBOW))

	-- Left hand + arm (holds the handguard)
	local lh = grip * LEFT_HOLD
	put(parts.LeftPalm, lh)
	put(parts.LeftFingers, lh * CFrame.new(0.155, 0.09, 0))
	put(parts.LeftThumb, lh * CFrame.new(-0.155, 0.07, 0.02))
	local lWrist = (LEFT_HOLD * CFrame.new(-0.05, -0.06, 0.2)).Position
	put(parts.LeftCuff, grip * limbBetween(parts.LeftCuff, lWrist, lWrist + (LEFT_ELBOW - lWrist).Unit * 0.14))
	put(parts.LeftForearm, grip * limbBetween(parts.LeftForearm, LEFT_ELBOW, lWrist))
	put(parts.LeftElbow, grip * CFrame.new(LEFT_ELBOW))
	put(parts.LeftUpperArm, grip * limbBetween(parts.LeftUpperArm, LEFT_SHOULDER, LEFT_ELBOW))

	-- Muzzle flash
	local flashing = shouldShow and t < flashUntil
	local muzzle = grip * GunModel.Muzzle * CFrame.Angles(0, 0, math.random() * math.pi)
	for _, name in ipairs({ "FlashCore", "FlashA", "FlashB", "FlashLong" }) do
		parts[name].LocalTransparencyModifier = flashing and 0 or 1
	end
	if Config.Effects.Lights then
		parts.FlashCore.MuzzleLight.Brightness = flashing and 7 or 0
	end
	put(parts.FlashCore, muzzle * CFrame.new(0, 0, -0.15))
	put(parts.FlashA, muzzle * CFrame.new(0, 0, -0.15))
	put(parts.FlashB, muzzle * CFrame.new(0, 0, -0.15))
	put(parts.FlashLong, muzzle * CFrame.new(0, 0, -0.45))

	workspace:BulkMoveTo(list, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

function Viewmodel.Init(controllers)
	Controllers = controllers
end

function Viewmodel.Start()
	build()
	visible = true
	setVisible(false)

	-- movement reactions
	Controllers.Movement.Jumped:Connect(function()
		moveSpring:Impulse(Vector3.new(0, -2.2, 0))
	end)
	Controllers.Movement.Landed:Connect(function(fallSpeed)
		local strength = math.clamp((fallSpeed - 25) / 60, 0.08, 1.6)
		moveSpring:Impulse(Vector3.new(0, -3.5 * strength, 0))
		recoilSpring:Impulse(Vector3.new(-10 * strength, 0, 0))
	end)
	Controllers.Movement.Slid:Connect(function()
		moveSpring:Impulse(Vector3.new(0, -1.5, 2.5))
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed and UserInputService:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == VM.InspectKey and visible and not inspecting then
			inspecting = true
			inspectStart = os.clock()
			Sfx.Play("CardHover", { Pitch = 0.8, Volume = 1.5 })
		end
	end)

	-- after the camera controller (Camera + 1) so we use the final camera CFrame
	RunService:BindToRenderStep("SniperViewmodel", Enum.RenderPriority.Camera.Value + 2, update)
end

return Viewmodel
