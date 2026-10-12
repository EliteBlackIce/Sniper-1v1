--[[
	ViewmodelController.lua  (Client.ViewmodelController)

	First-person arms + sniper, built from flat-coloured parts and attached to
	the camera. Only YOU see it (it lives inside workspace.CurrentCamera).

	Animation is all procedural:
		sway     lags behind mouse movement (spring)
		bob      walk/sprint bob based on speed
		recoil   kick back + up when firing (spring)
		bolt     right hand works the bolt after every shot
		aim      slides to the centre when scoping, then hides behind the scope overlay
		poses    lowered while sprinting, tilted while sliding / wall running

	Layout: every part has an offset relative to the "grip" (where the right
	hand holds the gun). +X right, +Y up, -Z forward (down the barrel).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local ClientState = require(script.Parent.ClientState)
local Spring = require(script.Parent.Spring)
local Sfx = require(script.Parent.Sfx)

local Palette = Config.Palette
local player = Players.LocalPlayer

local Viewmodel = {}
local Controllers

-- Where the grip sits in camera space when hip-firing / aiming down the scope.
local HIP_OFFSET = CFrame.new(0.85, -0.92, -1.55)
local ADS_OFFSET = CFrame.new(0, -0.36, -1.15) -- scope centred on screen
local SPRINT_POSE = CFrame.new(-0.15, -0.25, 0.1) * CFrame.Angles(math.rad(-18), math.rad(35), math.rad(12))

local model
local parts = {} -- [name] = BasePart
local staticOffsets = {} -- [name] = CFrame relative to grip
local muzzleOffset = CFrame.new(0, 0.05, -3.25)
local visible = false

local swaySpring = Spring.new(140, 16)
local recoilSpring = Spring.new(220, 18) -- X = pitch, Y = back, Z = roll
local bobTime = 0
local sprintAlpha = 0
local slideAlpha = 0
local wallAlpha = 0
local airOffset = 0
local boltStart, boltDuration = 0, 0
local boltSoundPlayed = true

----------------------------------------------------------------------------
-- Building
----------------------------------------------------------------------------
local function addPart(name, size, offset, color, shape)
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
	staticOffsets[name] = offset
	return part
end

local function build()
	model = Instance.new("Model")
	model.Name = "Viewmodel"

	-- SNIPER (flat colour blocks)
	addPart("Receiver", Vector3.new(0.22, 0.28, 1.6), CFrame.new(0, 0, -0.35), Palette.GunBody)
	addPart("Barrel", Vector3.new(0.09, 0.09, 1.9), CFrame.new(0, 0.05, -2.05), Palette.GunTrim)
	addPart("Brake", Vector3.new(0.15, 0.15, 0.25), CFrame.new(0, 0.05, -3.05), Palette.GunBody)
	addPart("Handguard", Vector3.new(0.2, 0.22, 0.9), CFrame.new(0, -0.02, -1.35), Palette.GunTrim)
	addPart("Stock", Vector3.new(0.2, 0.34, 0.95), CFrame.new(0, -0.1, 0.85), Palette.GunBody)
	addPart("StockPad", Vector3.new(0.22, 0.38, 0.08), CFrame.new(0, -0.1, 1.36), Palette.GunTrim)
	addPart("Grip", Vector3.new(0.16, 0.36, 0.2), CFrame.new(0, -0.27, 0.12) * CFrame.Angles(math.rad(-15), 0, 0), Palette.GunBody)
	addPart("Magazine", Vector3.new(0.14, 0.3, 0.32), CFrame.new(0, -0.27, -0.55), Palette.GunTrim)
	-- Scope
	addPart("ScopeTube", Vector3.new(0.15, 0.15, 1.0), CFrame.new(0, 0.32, -0.4), Palette.GunBody)
	addPart("ScopeFront", Vector3.new(0.22, 0.22, 0.14), CFrame.new(0, 0.32, -0.92), Palette.GunBody)
	addPart("ScopeRear", Vector3.new(0.2, 0.2, 0.14), CFrame.new(0, 0.32, 0.12), Palette.GunBody)
	addPart("ScopeLens", Vector3.new(0.17, 0.17, 0.02), CFrame.new(0, 0.32, -1.0), Palette.ScopeGlass)
	addPart("MountA", Vector3.new(0.08, 0.14, 0.08), CFrame.new(0, 0.19, -0.7), Palette.GunTrim)
	addPart("MountB", Vector3.new(0.08, 0.14, 0.08), CFrame.new(0, 0.19, -0.1), Palette.GunTrim)
	-- Bolt (animated)
	addPart("BoltHandle", Vector3.new(0.26, 0.05, 0.05), CFrame.new(0.17, 0.06, 0.05), Palette.GunTrim)
	addPart("BoltKnob", Vector3.new(0.1, 0.1, 0.1), CFrame.new(0.31, 0.06, 0.05), Palette.GunTrim, Enum.PartType.Ball)

	-- ARMS (hands are blocks, forearms + sleeves are stretched between joints)
	addPart("RightHand", Vector3.new(0.2, 0.24, 0.26), CFrame.identity, Palette.Skin)
	addPart("RightForearm", Vector3.new(0.22, 0.22, 1), CFrame.identity, Palette.Skin)
	addPart("RightSleeve", Vector3.new(0.3, 0.3, 1), CFrame.identity, Palette.Sleeve)
	addPart("LeftHand", Vector3.new(0.2, 0.24, 0.26), CFrame.identity, Palette.Skin)
	addPart("LeftForearm", Vector3.new(0.22, 0.22, 1), CFrame.identity, Palette.Skin)
	addPart("LeftSleeve", Vector3.new(0.3, 0.3, 1), CFrame.identity, Palette.Sleeve)

	model.Parent = workspace.CurrentCamera
end

-- Places a limb part between two points (in grip space).
local function limbBetween(name, a, b)
	local part = parts[name]
	local length = (b - a).Magnitude
	part.Size = Vector3.new(part.Size.X, part.Size.Y, length)
	return CFrame.lookAt((a + b) / 2, b)
end

----------------------------------------------------------------------------
-- Bolt animation: returns right-hand position + bolt offset for progress t (0-1)
----------------------------------------------------------------------------
local GRIP_HAND = Vector3.new(0.02, -0.2, 0.14)
local KNOB_HAND = Vector3.new(0.34, 0.02, 0.1)

local function boltPose(t)
	-- keyframes: reach (0-.15), lift (.15-.3), pull (.3-.5), push (.5-.7), lower (.7-.8), return (.8-1)
	local handPos = GRIP_HAND
	local lift, pull = 0, 0
	local function seg(a, b)
		return math.clamp((t - a) / (b - a), 0, 1)
	end
	local reach = seg(0, 0.15)
	local back = seg(0.8, 1)
	lift = seg(0.15, 0.3) - seg(0.7, 0.8)
	pull = seg(0.3, 0.5) - seg(0.5, 0.7)
	-- smooth the curves
	lift = math.sin(lift * math.pi / 2)
	pull = math.sin(pull * math.pi / 2)

	local atKnob = KNOB_HAND + Vector3.new(0, lift * 0.22, pull * 0.38)
	if t < 0.15 then
		handPos = GRIP_HAND:Lerp(atKnob, reach)
	elseif t < 0.8 then
		handPos = atKnob
	else
		handPos = atKnob:Lerp(GRIP_HAND, back)
	end
	local gunRoll = math.sin(math.clamp(t, 0, 1) * math.pi) * math.rad(14)
	return handPos, lift, pull, gunRoll
end

----------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------
function Viewmodel.PlayFire(scoped)
	local kick = scoped and 0.5 or 1
	recoilSpring:Impulse(Vector3.new(18 * kick, 7 * kick, (math.random() - 0.5) * 6))
end

function Viewmodel.PlayBolt(duration)
	boltStart = os.clock()
	boltDuration = duration
	boltSoundPlayed = false
end

function Viewmodel.GetMuzzlePosition()
	if model and parts.Brake then
		return (parts.Receiver.CFrame * staticOffsets.Receiver:Inverse() * muzzleOffset).Position
	end
	return workspace.CurrentCamera.CFrame.Position
end

function Viewmodel.GetLeftHandPosition()
	return parts.LeftHand and parts.LeftHand.Position or workspace.CurrentCamera.CFrame.Position
end

local function setVisible(v)
	if v == visible then
		return
	end
	visible = v
	for _, part in pairs(parts) do
		part.LocalTransparencyModifier = v and 0 or 1
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
	local alive = humanoid and humanoid.Health > 0
	local scopeAlpha = Controllers.Weapon.GetScopeAlpha()

	local shouldShow = alive and ClientState.IsInArena() and Controllers.Camera.IsFirstPerson() and scopeAlpha < 0.92
	setVisible(shouldShow)
	if not shouldShow and not ClientState.IsInArena() then
		return
	end

	local movement = Controllers.Movement
	local mode = movement.GetMode()
	local speed = movement.GetSpeed()
	local grounded = movement.IsGrounded()

	-- SWAY from mouse movement
	local delta = UserInputService:GetMouseDelta()
	local swayScale = 1 - scopeAlpha * 0.85
	swaySpring.Target = Vector3.new(
		math.clamp(-delta.Y * 0.06, -4, 4),
		math.clamp(-delta.X * 0.06, -4, 4),
		math.clamp(-delta.X * 0.04, -3, 3)
	) * swayScale
	local sway = swaySpring:Update(dt)

	-- BOB from moving on the ground
	local moving = grounded and speed > 2 and mode ~= "Slide"
	if moving then
		bobTime += dt * (6 + speed * 0.22)
	end
	local bobAmount = moving and math.clamp(speed / 30, 0, 1.4) * (1 - scopeAlpha * 0.9) or 0
	local idle = math.sin(os.clock() * 1.6) * 0.012
	local bob = Vector3.new(math.sin(bobTime) * 0.045 * bobAmount, math.abs(math.cos(bobTime)) * 0.05 * bobAmount + idle, 0)

	-- POSES
	local sprinting = grounded and mode == "Ground" and speed > Config.Movement.WalkSpeed + 3
	local boltT = boltDuration > 0 and (os.clock() - boltStart) / boltDuration or 1
	local cycling = boltT < 1
	sprintAlpha = Util.lerp(sprintAlpha, (sprinting and scopeAlpha < 0.1 and not cycling) and 1 or 0, Util.smooth(10, dt))
	slideAlpha = Util.lerp(slideAlpha, mode == "Slide" and 1 or 0, Util.smooth(10, dt))
	wallAlpha = Util.lerp(wallAlpha, mode == "WallRun" and 1 or 0, Util.smooth(10, dt))
	local vy = character and character:FindFirstChild("HumanoidRootPart") and character.HumanoidRootPart.AssemblyLinearVelocity.Y or 0
	airOffset = Util.lerp(airOffset, grounded and 0 or math.clamp(-vy * 0.002, -0.08, 0.08), Util.smooth(8, dt))

	-- RECOIL spring back to rest
	local recoil = recoilSpring:Update(dt)

	-- BOLT
	local handPos, boltLift, boltPull, boltRoll = boltPose(math.clamp(boltT, 0, 1))
	if cycling and not boltSoundPlayed and boltT > 0.3 then
		boltSoundPlayed = true
		Sfx.Play("Bolt")
	end

	-- Combine everything into the grip CFrame
	local base = HIP_OFFSET:Lerp(ADS_OFFSET, scopeAlpha)
	local pose = CFrame.identity:Lerp(SPRINT_POSE, sprintAlpha)
		* CFrame.Angles(0, 0, math.rad(-14) * slideAlpha)
		* CFrame.new(0, -0.12 * slideAlpha, 0)
		* CFrame.Angles(0, 0, math.rad(6) * wallAlpha)
	local grip = camera.CFrame
		* base
		* pose
		* CFrame.new(bob.X, bob.Y + airOffset, recoil.Y * 0.02)
		* CFrame.Angles(math.rad(sway.X + recoil.X * 0.35), math.rad(sway.Y), math.rad(sway.Z + recoil.Z * 0.3))
		* CFrame.Angles(0, 0, -boltRoll)

	-- Gun parts
	local list, cframes = {}, {}
	for name, offset in pairs(staticOffsets) do
		if not name:find("Hand") and not name:find("Forearm") and not name:find("Sleeve") and not name:find("Bolt") then
			table.insert(list, parts[name])
			table.insert(cframes, grip * offset)
		end
	end
	-- Bolt (rotates up and slides back)
	local boltPivot = CFrame.new(0.06, 0.06, 0.05 + boltPull * 0.38) * CFrame.Angles(0, 0, math.rad(75) * boltLift)
	table.insert(list, parts.BoltHandle)
	table.insert(cframes, grip * boltPivot * CFrame.new(0.11, 0, 0))
	table.insert(list, parts.BoltKnob)
	table.insert(cframes, grip * boltPivot * CFrame.new(0.25, 0, 0))

	-- Right arm (follows the bolt animation)
	local rElbow = Vector3.new(0.5, -0.62, 0.95)
	local rShoulder = Vector3.new(0.95, -1.05, 2.0)
	table.insert(list, parts.RightHand)
	table.insert(cframes, grip * CFrame.new(handPos) * CFrame.Angles(math.rad(-10), 0, 0))
	table.insert(list, parts.RightForearm)
	table.insert(cframes, grip * limbBetween("RightForearm", rElbow, handPos + Vector3.new(0, -0.02, 0.12)))
	table.insert(list, parts.RightSleeve)
	table.insert(cframes, grip * limbBetween("RightSleeve", rShoulder, rElbow))

	-- Left arm (holds the handguard)
	local lHand = Vector3.new(0, -0.16, -1.3)
	local lElbow = Vector3.new(-0.55, -0.62, -0.45)
	local lShoulder = Vector3.new(-1.0, -1.0, 0.9)
	table.insert(list, parts.LeftHand)
	table.insert(cframes, grip * CFrame.new(lHand))
	table.insert(list, parts.LeftForearm)
	table.insert(cframes, grip * limbBetween("LeftForearm", lElbow, lHand + Vector3.new(0, -0.02, 0.1)))
	table.insert(list, parts.LeftSleeve)
	table.insert(cframes, grip * limbBetween("LeftSleeve", lShoulder, lElbow))

	workspace:BulkMoveTo(list, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

function Viewmodel.Init(controllers)
	Controllers = controllers
end

function Viewmodel.Start()
	build()
	visible = true
	setVisible(false)
	-- after the camera controller (Camera + 1) so we use the final camera CFrame
	RunService:BindToRenderStep("SniperViewmodel", Enum.RenderPriority.Camera.Value + 2, update)
end

return Viewmodel
