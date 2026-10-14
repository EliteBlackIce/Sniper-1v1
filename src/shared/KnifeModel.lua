--[[
	KnifeModel.lua  (ReplicatedStorage.Shared.KnifeModel)

	The combat knife: in your real character's hand (BodyAnimator) and in other
	players' hands (CharacterService "WorldKnife").

	If a model named Config.Knife.MeshTemplate ("CombatKnife") is in
	ReplicatedStorage (the server moves it there from the Workspace), the
	knife is built from its meshes ("Blade" + "Handle", from the
	CombatKnife.glb import). Otherwise a knife is built from parts.

	Knife space: origin = the middle of the handle, blade toward -Z, cutting
	edge toward -Y, +X = the flat side. Studs.

		local built = KnifeModel.Build(parent, { Scale = 1, Anchored = true })
		KnifeModel.Place(built, cf)           -- knife origin at cf
		built.Parts[name], built.Offsets[name]
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local KnifeModel = {}

local V = Vector3.new
local K = Config.Knife

-- The baked GLB's bounding box (knife space), used to fit the imported meshes.
KnifeModel.Bounds = { Min = V(-0.065, -0.1546, -1.168), Max = V(0.0667, 0.1044, 0.232) }
KnifeModel.Grip = CFrame.new(0, -0.01, -0.1) -- where the hand closes round the handle
KnifeModel.Tip = V(0, -0.03, -1.15)

-- flat paint for the meshes (by name)
KnifeModel.MeshPaint = {
	{ Match = "blade", Key = "Blade", Color = Color3.fromRGB(176, 182, 190), Material = Enum.Material.Metal },
	{ Match = "", Key = "Handle", Color = Color3.fromRGB(34, 36, 40), Material = Enum.Material.SmoothPlastic }, -- handle + guard
}

-- The parts knife: { name, shape, size, position, rotation (degrees), colour, material }
local STEEL = Color3.fromRGB(176, 182, 190)
local EDGE = Color3.fromRGB(222, 226, 232)
local GRIP = Color3.fromRGB(34, 36, 40)
local GUARD = Color3.fromRGB(70, 74, 82)
KnifeModel.Parts = {
	{ "Blade", "Block", V(0.03, 0.15, 0.62), V(0, 0.0, -0.73), nil, STEEL, "Metal" },
	{ "Edge", "Block", V(0.02, 0.05, 0.6), V(0, -0.085, -0.72), nil, EDGE, "Metal" },
	{ "Tip", "Wedge", V(0.03, 0.15, 0.18), V(0, 0.0, -1.13), nil, STEEL, "Metal" }, -- slopes down to the point
	{ "Spine", "Block", V(0.035, 0.03, 0.4), V(0, 0.085, -0.62), nil, GUARD, "Metal" },
	{ "Guard", "Block", V(0.09, 0.32, 0.05), V(0, -0.01, -0.42), nil, GUARD, "Metal" },
	{ "Handle", "Cylinder", V(0.56, 0.13, 0.13), V(0, -0.01, -0.12), V(0, 90, 0), GRIP, "SmoothPlastic" },
	{ "Pommel", "Cylinder", V(0.07, 0.16, 0.16), V(0, -0.01, 0.19), V(0, 90, 0), GUARD, "Metal" },
}
for i = 0, 3 do -- grip rings
	table.insert(KnifeModel.Parts, { "Ring" .. i, "Cylinder", V(0.03, 0.145, 0.145), V(0, -0.01, -0.3 + i * 0.13), V(0, 90, 0), GUARD, "Metal" })
end

-- paint groups of the parts knife (Skins recolour by them)
local PARTS_PAINT = { Blade = "Blade", Edge = "Edge", Tip = "Blade", Spine = "Fittings", Guard = "Fittings", Handle = "Handle", Pommel = "Fittings" }

local function templateParts(template)
	local list = {}
	for _, item in ipairs(template:GetDescendants()) do
		if item:IsA("BasePart") then
			table.insert(list, item)
		end
	end
	if template:IsA("BasePart") then
		table.insert(list, template)
	end
	return list
end

function KnifeModel.FindTemplate()
	if game == nil or Config.Knife.UseImportedKnife == false then
		return nil
	end
	local template = ReplicatedStorage:FindFirstChild(K.MeshTemplate or "CombatKnife")
	if template and #templateParts(template) > 0 then
		return template
	end
	return nil
end

local function boundsOf(parts, rot)
	local huge = math.huge
	local mn, mx = V(huge, huge, huge), V(-huge, -huge, -huge)
	for _, part in ipairs(parts) do
		local cf = rot * part.CFrame
		local h = part.Size / 2
		for _, sx in ipairs({ -1, 1 }) do
			for _, sy in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					local c = cf * V(h.X * sx, h.Y * sy, h.Z * sz)
					mn = mn:Min(c)
					mx = mx:Max(c)
				end
			end
		end
	end
	return mn, mx
end

-- Where each imported mesh goes in knife space (works out the importer's turn).
local layoutCache = setmetatable({}, { __mode = "k" })
local function meshLayout(template)
	local parts = templateParts(template)
	local cached = layoutCache[template]
	if cached and cached.Count == #parts then
		return cached.Layout -- (rebuilt if more meshes have replicated since)
	end
	local best, bestScore = 0, -math.huge
	for _, yaw in ipairs(K.MeshYaw and { K.MeshYaw } or { 0, 90, 180, 270 }) do
		local rot = CFrame.Angles(0, math.rad(yaw), 0)
		local mn, mx = boundsOf(parts, rot)
		local size = mx - mn
		local score = size.Z - math.max(size.X, size.Y) * 2
		for _, part in ipairs(parts) do
			if part.Name:lower():find("blade") then
				local pmn = boundsOf({ part }, rot)
				if math.abs(pmn.Z - mn.Z) < size.Z * 0.03 then
					score += 1000 -- the blade reaches the front (-Z)
				end
			end
		end
		if score > bestScore then
			best, bestScore = yaw, score
		end
	end
	local rot = CFrame.Angles(0, math.rad(best), 0)
	local mn, mx = boundsOf(parts, rot)
	local B = KnifeModel.Bounds
	local k = (B.Max.Z - B.Min.Z) / math.max(mx.Z - mn.Z, 1e-3)
	local layout = {}
	for i, part in ipairs(parts) do
		local cf = rot * part.CFrame
		table.insert(layout, {
			Part = part,
			Name = part.Name ~= "" and part.Name .. i or ("Mesh" .. i),
			Size = part.Size * k,
			Offset = CFrame.new(B.Min + (cf.Position - mn) * k) * cf.Rotation,
		})
	end
	-- a Secret model can mark the middle of its handle with an Attachment
	-- named "Grip": line that up with the normal knife's grip
	local grip = template:FindFirstChild("Grip", true)
	if grip and grip:IsA("Attachment") then
		local at = B.Min + ((rot * CFrame.new(grip.WorldPosition)).Position - mn) * k
		for _, info in ipairs(layout) do
			info.Offset = info.Offset - at + KnifeModel.Grip.Position
		end
	end
	layoutCache[template] = { Layout = layout, Count = #parts }
	return layout
end

local function paint(part)
	if not part:IsA("MeshPart") then
		return
	end
	if (K.MeshPaint or "Always") ~= "Always" and (part.TextureID ~= "" or part:FindFirstChildOfClass("SurfaceAppearance")) then
		return
	end
	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("SurfaceAppearance") then
			child:Destroy()
		end
	end
	pcall(function()
		part.TextureID = ""
	end)
	local name = part.Name:lower()
	for _, rule in ipairs(KnifeModel.MeshPaint) do
		if name:find(rule.Match, 1, true) then
			part.Color = rule.Color
			part.Material = rule.Material
			return
		end
	end
end

--[[
	options: Scale (default 1), Anchored, CastShadow
	Returns { Parts = {[name] = part}, Offsets = {[name] = CFrame}, Scale, UsesMesh }
]]
function KnifeModel.Build(parent, options)
	options = options or {}
	local scale = options.Scale or 1
	local result = { Parts = {}, Offsets = {}, Scale = scale }
	local function setup(part, name, offset)
		part.Name = name
		part.Anchored = options.Anchored == true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.CastShadow = options.CastShadow == true
		part.Parent = parent
		result.Parts[name] = part
		result.Offsets[name] = offset
	end
	-- options.Template: a Secret skin's own model (an Instance) instead of the knife
	local template = options.Template or KnifeModel.FindTemplate()
	if template then
		result.UsesMesh = true
		for _, info in ipairs(meshLayout(template)) do
			local part = info.Part:Clone()
			for _, child in ipairs(part:GetChildren()) do
				if child:IsA("JointInstance") or child:IsA("Constraint") or child:IsA("BasePart") then
					child:Destroy()
				end
			end
			part.Size = info.Size * scale
			part:SetAttribute("Paint", info.Part.Name:lower():find("blade") and "Blade" or "Handle")
			if not options.KeepTextures then
				paint(part)
			end
			setup(part, info.Name, info.Offset.Rotation + info.Offset.Position * scale)
		end
	else
		for _, spec in ipairs(KnifeModel.Parts) do
			local name, shape, size, pos, rot, color, material = table.unpack(spec)
			local part
			if shape == "Wedge" then
				part = Instance.new("WedgePart")
			else
				part = Instance.new("Part")
				part.Shape = Enum.PartType[shape]
			end
			part.Size = size * scale
			part:SetAttribute("Paint", PARTS_PAINT[name] or (name:find("Ring") and "Fittings") or "Handle")
			part.Color = color
			part.Material = Enum.Material[material]
			part.TopSurface = Enum.SurfaceType.Smooth
			part.BottomSurface = Enum.SurfaceType.Smooth
			local r = rot or Vector3.zero
			setup(part, name, CFrame.new(pos * scale) * CFrame.Angles(math.rad(r.X), math.rad(r.Y), math.rad(r.Z)))
		end
	end
	return result
end

-- Puts every part at `cf` (the knife origin).
function KnifeModel.Place(built, cf)
	for name, part in pairs(built.Parts) do
		part.CFrame = cf * built.Offsets[name]
	end
end

return KnifeModel
