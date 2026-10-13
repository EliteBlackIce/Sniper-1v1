--[[
	CrateModel.lua  (ReplicatedStorage.Shared.CrateModel)

	The loot crate, built from parts: a dark armoured case with metal corner
	posts, a glowing band in the rarity colour, side handles, a latch, the
	SNIPER DUEL mark on the front and a hinged lid with a glowing cross.

		local crate = CrateModel.Build({ CFrame = cf, Scale = 1.3, Color = c, Parent = folder })
		crate.Model:PivotTo(cf)          -- move the whole crate (pivot = bottom centre)
		CrateModel.SetLid(crate, 40)     -- open the lid 40 degrees
		CrateModel.SetColor(crate, c)    -- recolour the glow, light and emblems

	Front = -Z of the pivot.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logo = require(ReplicatedStorage.Shared.Logo)

local CrateModel = {}

local V = Vector3.new
local BODY = Color3.fromRGB(30, 33, 42)
local PANEL = Color3.fromRGB(22, 24, 31)
local METAL = Color3.fromRGB(104, 110, 124)
local METAL_DARK = Color3.fromRGB(58, 62, 72)

-- body parts: { size, position (bottom centre = 0), colour, material, glow? }
local BODY_PARTS = {
	{ V(4.1, 0.26, 3.1), V(0, 0.13, 0), METAL_DARK, "Metal" }, -- foot
	{ V(3.8, 2.14, 2.8), V(0, 1.33, 0), BODY, "SmoothPlastic" }, -- case
	{ V(3.86, 0.14, 2.86), V(0, 1.02, 0), nil, "Neon", true }, -- glow band
	{ V(2.3, 1.2, 0.08), V(0, 1.5, -1.43), PANEL, "SmoothPlastic", false, "Emblem" }, -- front plate
	{ V(0.16, 0.34, 1.3), V(-2.0, 1.62, 0), METAL, "Metal" }, -- handles
	{ V(0.16, 0.34, 1.3), V(2.0, 1.62, 0), METAL, "Metal" },
	{ V(0.7, 0.5, 0.2), V(0, 2.18, -1.5), METAL, "Metal" }, -- latch
	{ V(0.26, 0.26, 0.1), V(0, 2.18, -1.62), nil, "Neon", true }, -- latch light
}
-- corner posts and the top rim
for _, x in ipairs({ -1.86, 1.86 }) do
	for _, z in ipairs({ -1.36, 1.36 }) do
		table.insert(BODY_PARTS, { V(0.42, 2.3, 0.42), V(x, 1.4, z), METAL, "Metal" })
	end
end
for _, z in ipairs({ -1.36, 1.36 }) do
	table.insert(BODY_PARTS, { V(3.3, 0.2, 0.3), V(0, 2.42, z), METAL_DARK, "Metal" })
end
-- glowing strips down the four corners
for _, x in ipairs({ -1.86, 1.86 }) do
	for _, z in ipairs({ -1.36, 1.36 }) do
		table.insert(BODY_PARTS, { V(0.12, 1.9, 0.12), V(x * 1.115, 1.4, z * 1.15), nil, "Neon", true })
	end
end
for _, x in ipairs({ -1.86, 1.86 }) do
	table.insert(BODY_PARTS, { V(0.3, 0.2, 2.3), V(x, 2.42, 0), METAL_DARK, "Metal" })
end

-- lid parts, relative to the hinge (back top edge of the case)
local HINGE = V(0, 2.52, 1.5)
local LID_PARTS = {
	{ V(4.06, 0.5, 3.06), V(0, 0.25, -1.5), BODY, "SmoothPlastic" }, -- lid
	{ V(3.4, 0.22, 2.4), V(0, 0.6, -1.5), METAL_DARK, "Metal", false, "Top" }, -- raised top
	{ V(3.44, 0.08, 0.2), V(0, 0.74, -1.5), nil, "Neon", true }, -- glowing cross
	{ V(0.2, 0.08, 2.44), V(0, 0.74, -1.5), nil, "Neon", true },
	{ V(4.1, 0.12, 0.16), V(0, 0.06, -3.02), METAL, "Metal" }, -- front lip
	{ V(4.12, 0.08, 3.12), V(0, 0.32, -1.5), nil, "Neon", true }, -- glowing seam round the lid
}

local function makePart(info, scale, color, parent)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = not info[5]
	part.Size = info[1] * scale
	part.Color = info[3] or color
	part.Material = Enum.Material[info[4]]
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

function CrateModel.Build(options)
	options = options or {}
	local scale = options.Scale or 1
	local color = options.Color or Color3.fromRGB(176, 182, 192)
	local pivot = options.CFrame or CFrame.new()

	local model = Instance.new("Model")
	model.Name = options.Name or "Crate"
	local lid = Instance.new("Model")
	lid.Name = "Lid"
	lid.Parent = model

	local crate = { Model = model, Lid = lid, Glow = {}, Emblems = {}, Scale = scale, Parts = {} }
	local function add(info, cf, parent)
		local part = makePart(info, scale, color, parent)
		part.CFrame = cf
		table.insert(crate.Parts, part)
		if info[5] then
			table.insert(crate.Glow, part)
		end
		if info[6] == "Emblem" then
			part.Name = "Emblem"
			table.insert(crate.Emblems, Logo.OnPart(part, Enum.NormalId.Front, { Layout = "Mark", Color = color, Accent = color, Stroke = 6 * scale }, 40))
		elseif info[6] == "Top" then
			part.Name = "LidTop"
			table.insert(crate.Emblems, Logo.OnPart(part, Enum.NormalId.Top, { Layout = "Mark", Color = color, Accent = color, Stroke = 6 * scale }, 40))
		end
		return part
	end
	for _, info in ipairs(BODY_PARTS) do
		add(info, pivot * CFrame.new(info[2] * scale), model)
	end
	crate.HingeOffset = CFrame.new(HINGE * scale)
	local hinge = pivot * crate.HingeOffset
	for _, info in ipairs(LID_PARTS) do
		add(info, hinge * CFrame.new(info[2] * scale), lid)
	end
	model.WorldPivot = pivot
	lid.WorldPivot = hinge

	local core = crate.Parts[2]
	crate.Core = core
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 9 * scale
	light.Brightness = 1.1
	light.Shadows = false
	light.Parent = core
	crate.Light = light

	crate.Color = color
	model.Parent = options.Parent
	return crate
end

function CrateModel.SetColor(crate, color)
	crate.Color = color
	for _, part in ipairs(crate.Glow) do
		part.Color = color
	end
	crate.Light.Color = color
	for _, gui in ipairs(crate.Emblems) do
		for _, item in ipairs(gui:GetDescendants()) do
			if item:IsA("UIStroke") then
				item.Color = color
			elseif item:IsA("Frame") and item.BackgroundTransparency < 1 then
				item.BackgroundColor3 = color
			end
		end
	end
end

-- Opens the lid `degrees` (0 = shut). `extra` is an optional CFrame applied
-- after the hinge turn (e.g. to throw the lid off).
function CrateModel.SetLid(crate, degrees, extra)
	local hinge = crate.Model:GetPivot() * crate.HingeOffset
	crate.Lid:PivotTo(hinge * CFrame.Angles(math.rad(degrees), 0, 0) * (extra or CFrame.new()))
end

-- Fades every part (0 = solid, 1 = gone) on this client only.
function CrateModel.SetFade(crate, alpha, lidOnly)
	for _, part in ipairs(crate.Parts) do
		if not lidOnly or part:IsDescendantOf(crate.Lid) then
			part.LocalTransparencyModifier = alpha
		end
	end
	for _, gui in ipairs(crate.Emblems) do
		if not lidOnly or gui:IsDescendantOf(crate.Lid) then
			gui.Enabled = alpha < 0.5
		end
	end
end

return CrateModel
