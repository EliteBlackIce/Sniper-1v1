--[[
	FirstPersonView.lua  (Client.FirstPersonView)

	What you see in first person: slim copies of your own avatar's arms
	(skin colour, shirt and all) holding a copy of your own weapon (with
	your power-ups), drawn on the camera every frame so nothing lags.

	Your real character still does every move at full size; that's what
	everyone else sees (BodyAnimator). The copies play the SAME animation
	(WeaponAnim): the weapon goes exactly where it goes on your real body,
	and the arms reach it from shoulders just under the camera.

		FirstPersonView.Draw(source, view, anim, body)   -- each frame
		FirstPersonView.Hide()
		FirstPersonView.GetMuzzle() / GetKnifeTip()      -- (nil while hidden)

	source = the character whose arms and weapon to copy (you, or the kill
	cam's copy of your killer); view = the eyes (CFrame); anim = the
	WeaponAnim.Evaluate output.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local KnifeModel = require(Shared.KnifeModel)

local FP = Config.Body.FirstPerson
local V = Vector3.new
local rad = math.rad

local FirstPersonView = {}

local ARM_NAMES = { "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperArm", "LeftLowerArm", "LeftHand" }
local R6_ARMS = { Right = "Right Arm", Left = "Left Arm" }
local KEEP = { SurfaceAppearance = true, SpecialMesh = true, Decal = true, Texture = true }

local folder -- in the camera
local arms -- { Source, Model, Parts = {[name] = part}, Base = {[name] = size}, Dirty }
local weapons = {} -- [name] = { Source, Model, Root, Items = { {Part, Offset, Bolt} }, BoltRest, Muzzle, Tip }
local shown = false
local current -- the weapon copy drawn this frame

----------------------------------------------------------------------------
-- Building the copies
----------------------------------------------------------------------------
local function setup(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.LocalTransparencyModifier = 0
end

local function strip(part, keep)
	for _, child in ipairs(part:GetChildren()) do
		if not keep(child) then
			child:Destroy()
		end
	end
end

local function ensureFolder()
	local camera = workspace.CurrentCamera
	if not folder or folder.Parent ~= camera then
		if folder then
			folder:Destroy()
		end
		folder = Instance.new("Folder")
		folder.Name = "FirstPerson"
		folder.Parent = camera
		arms = nil
		table.clear(weapons)
	end
	return folder
end

-- plain blocks in the avatar's skin colour (characters without R15 arms)
local function plainArms(source, model)
	local colors = source:FindFirstChildOfClass("BodyColors")
	local parts, base = {}, {}
	for _, name in ipairs(ARM_NAMES) do
		local side = name:sub(1, 1) == "R" and "Right" or "Left"
		local part = Instance.new("Part")
		part.Name = name
		part.Size = V(1, 1, 1)
		local arm = source:FindFirstChild(R6_ARMS[side])
		part.Color = colors and colors[side .. "ArmColor3"] or (arm and arm.Color) or Color3.fromRGB(234, 184, 146)
		part.Material = Enum.Material.SmoothPlastic
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		setup(part)
		part.Parent = model
		parts[name] = part
		base[name] = V(1, name:find("Hand") and 0.35 or 1, 1)
	end
	return parts, base
end

local function buildArms(source)
	if arms then
		arms.Model:Destroy()
		if arms.Connection then
			arms.Connection:Disconnect()
		end
	end
	local model = Instance.new("Model")
	model.Name = "Arms"
	-- (a Humanoid in the model is what makes the shirt show up on the copies)
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.EvaluateStateMachine = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.Parent = model
	for _, item in ipairs(source:GetChildren()) do
		if item:IsA("Shirt") or item:IsA("BodyColors") then
			item:Clone().Parent = model
		end
	end
	local parts, base = {}, {}
	local ok = true
	for _, name in ipairs(ARM_NAMES) do
		local original = source:FindFirstChild(name)
		local copied, part = false, nil
		if original and original:IsA("BasePart") then
			copied, part = pcall(original.Clone, original)
		end
		if not copied or not part then
			ok = false
			break
		end
		strip(part, function(child)
			return KEEP[child.ClassName] == true
		end)
		setup(part)
		part.Transparency = 0
		part.Parent = model
		parts[name] = part
		base[name] = original.Size
	end
	if not ok then
		for _, part in pairs(parts) do
			part:Destroy()
		end
		parts, base = plainArms(source, model)
	end
	model.Parent = ensureFolder()
	arms = { Source = source, Model = model, Parts = parts, Base = base }
	-- the avatar's look can arrive after the character does: rebuild then
	local entry = arms
	entry.Connection = source.ChildAdded:Connect(function(child)
		if child:IsA("Shirt") or child:IsA("BodyColors") or table.find(ARM_NAMES, child.Name) then
			entry.Dirty = true
		end
	end)
end

local function weldedToBolt(part, boltRoot)
	if not boltRoot then
		return false
	end
	for _, item in ipairs(part:GetChildren()) do
		if item:IsA("WeldConstraint") or item:IsA("JointInstance") then
			if item.Part0 == boltRoot or item.Part1 == boltRoot then
				return true
			end
		end
	end
	return false
end

-- A copy of a held weapon (WorldGun / WorldKnife), every part at its offset
-- from the weapon's root (bolt parts from the bolt).
local function buildWeapon(source)
	local root = source:FindFirstChild("WeaponRoot")
	if not root then
		return nil
	end
	local boltRoot = source:FindFirstChild("BoltRoot")
	local boltJoint = root:FindFirstChild("BoltJoint")
	local model = Instance.new("Model")
	model.Name = source.Name
	local copy = { Source = source, Model = model, Items = {}, BoltRest = boltJoint and boltJoint.C0 or CFrame.new() }
	local count = 0
	for _, part in ipairs(source:GetDescendants()) do
		if part:IsA("BasePart") and part ~= root and part ~= boltRoot then
			count += 1
			local onBolt = weldedToBolt(part, boltRoot)
			local from = onBolt and boltRoot.CFrame or root.CFrame
			local clone = part:Clone()
			strip(clone, function(child)
				return not (child:IsA("JointInstance") or child:IsA("WeldConstraint") or child:IsA("Constraint") or child:IsA("BasePart") or child:IsA("LuaSourceContainer"))
			end)
			setup(clone)
			clone.Transparency = part:GetAttribute("BaseTransparency") or part.Transparency
			clone.Parent = model
			table.insert(copy.Items, { Part = clone, Offset = from:ToObjectSpace(part.CFrame), Bolt = onBolt })
			if part.Name == "Barrel" then
				copy.Muzzle = clone:FindFirstChild("Muzzle")
			end
		end
	end
	copy.Count = count
	copy.Parts = table.create(#copy.Items)
	for i, item in ipairs(copy.Items) do
		copy.Parts[i] = item.Part
	end
	copy.CFrames = table.create(#copy.Items)
	model.Parent = ensureFolder()
	return copy
end

local function weaponCopy(source, name)
	local original = source:FindFirstChild(name)
	local copy = weapons[name]
	if copy and (copy.Source ~= original or not original) then
		copy.Model:Destroy()
		copy, weapons[name] = nil, nil
	end
	if original and not copy then
		copy = buildWeapon(original)
		weapons[name] = copy
	end
	return copy
end

----------------------------------------------------------------------------
-- Placing the arms
----------------------------------------------------------------------------
-- Where the elbow goes for a shoulder S and a wrist W (bending toward `pole`).
local function solveElbow(S, W, pole, upper, lower)
	local toW = W - S
	local d = math.clamp(toW.Magnitude, math.abs(upper - lower) + 0.01, upper + lower - 0.002)
	local dir = toW.Magnitude > 1e-4 and toW.Unit or V(0, -1, 0)
	local cosA = math.clamp((upper * upper + d * d - lower * lower) / (2 * upper * d), -1, 1)
	local sinA = math.sqrt(1 - cosA * cosA)
	local side = pole - dir * pole:Dot(dir)
	side = side.Magnitude > 1e-4 and side.Unit or V(0, -1, 0)
	return S + dir * upper * cosA + side * upper * sinA, side
end

-- Resizes a copied limb (rounded, so meshes aren't resized every frame).
local function resize(part, size)
	if (part.Size - size).Magnitude > 0.004 then
		part.Size = size
	end
end

-- A limb from a to b (its -Y runs a -> b), its front (-Z) facing `front`.
local function limb(name, a, b, front, thick)
	local part, base = arms.Parts[name], arms.Base[name]
	local length = math.max(math.floor((b - a).Magnitude * 20 + 0.5) / 20, 0.05)
	local k = thick / math.max(base.X, 0.01)
	resize(part, V(base.X * k, length, base.Z * k))
	local down = (b - a).Unit
	local z = -(front - down * front:Dot(down))
	z = z.Magnitude > 1e-3 and z.Unit or (math.abs(down.Y) < 0.9 and V(0, 1, 0):Cross(down).Unit or V(1, 0, 0))
	local y = -down
	return CFrame.fromMatrix((a + b) / 2, y:Cross(z), y, z)
end

local function placeArm(side, view, handCF, body, parts, cframes)
	local sx = side == "Right" and 1 or -1
	local look, down = view.LookVector, -view.UpVector
	-- the shoulders turn and lean with the body
	local lean = rad(body.Lean or 0)
	local chest = view
		* CFrame.new(0, FP.Shoulder.Y, FP.Shoulder.Z - (body.Forward or 0) - math.sin(lean) * 1.3)
		* CFrame.Angles(0, -rad(body.Yaw or 0), 0)
	local shoulder = (chest * CFrame.new(FP.Shoulder.X * sx, 0, 0)).Position

	local handName = side .. "Hand"
	local handBase = arms.Base[handName]
	local handSize = handBase * (FP.HandWidth / math.max(handBase.X, 0.01))
	resize(arms.Parts[handName], handSize)
	local wrist = (handCF * CFrame.new(0, handSize.Y / 2, 0)).Position
	local pole = (view.RightVector * (0.7 * sx) + down - look * 0.15).Unit
	local elbow, bend = solveElbow(shoulder, wrist, pole, FP.UpperLength, FP.LowerLength)

	local upperDir = (elbow - shoulder).Unit
	local lowerDir = (wrist - elbow).Unit
	-- inner elbows face each other (falls back to away from the bend when straight)
	local upperFront = lowerDir - upperDir * lowerDir:Dot(upperDir)
	upperFront = upperFront.Magnitude > 0.05 and upperFront or -bend
	local lowerFront = -upperDir + lowerDir * upperDir:Dot(lowerDir)
	lowerFront = lowerFront.Magnitude > 0.05 and lowerFront or -bend

	local thick = FP.ArmThickness
	table.insert(parts, arms.Parts[handName])
	table.insert(cframes, handCF)
	table.insert(parts, arms.Parts[side .. "LowerArm"])
	table.insert(cframes, limb(side .. "LowerArm", elbow, wrist, lowerFront, thick * 0.92))
	table.insert(parts, arms.Parts[side .. "UpperArm"])
	table.insert(cframes, limb(side .. "UpperArm", shoulder, elbow, upperFront, thick))
end

----------------------------------------------------------------------------
-- API
----------------------------------------------------------------------------
local function setShown(value)
	if shown == value then
		return
	end
	shown = value
	if folder then
		for _, part in ipairs(folder:GetDescendants()) do
			if part:IsA("BasePart") then
				part.LocalTransparencyModifier = value and 0 or 1
			end
		end
	end
end

function FirstPersonView.Hide()
	setShown(false)
	current = nil
end

-- weaponName: "WorldGun" or "WorldKnife"
function FirstPersonView.Draw(source, view, anim, body, weaponName)
	ensureFolder()
	if not arms or arms.Source ~= source or arms.Dirty or not arms.Model.Parent then
		buildArms(source) -- (new parts start visible)
	end
	setShown(true)
	local parts, cframes = {}, {}
	placeArm("Right", view, view * anim.Right, body or {}, parts, cframes)
	placeArm("Left", view, view * anim.Left, body or {}, parts, cframes)

	-- the weapon in hand; the other one is put away
	current = nil
	for _, name in ipairs({ "WorldGun", "WorldKnife" }) do
		local copy = weaponCopy(source, name)
		if copy then
			local held = name == weaponName
			for _, part in ipairs(copy.Parts) do
				part.LocalTransparencyModifier = held and 0 or 1
			end
			if held then
				current = copy
				local root = view * anim.Weapon
				local bolt = root * copy.BoltRest * (anim.Bolt or CFrame.new())
				for i, item in ipairs(copy.Items) do
					copy.CFrames[i] = (item.Bolt and bolt or root) * item.Offset
				end
				copy.Root = root
				workspace:BulkMoveTo(copy.Parts, copy.CFrames, Enum.BulkMoveMode.FireCFrameChanged)
			end
		end
	end
	workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

function FirstPersonView.IsShown()
	return shown
end

function FirstPersonView.GetMuzzle()
	if shown and current and current.Muzzle then
		return current.Muzzle.WorldPosition
	end
	return nil
end

function FirstPersonView.GetKnifeTip()
	if shown and current and current.Source.Name == "WorldKnife" and current.Root then
		return (current.Root * CFrame.new(KnifeModel.Tip * Config.Knife.WorldScale)).Position
	end
	return nil
end

function FirstPersonView.GetLeftHand()
	if shown and arms and arms.Parts.LeftHand then
		return arms.Parts.LeftHand.Position
	end
	return nil
end

return FirstPersonView
