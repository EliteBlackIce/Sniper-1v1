--[[
	GunModel.lua  (ReplicatedStorage.Shared.GunModel)

	The sniper rifle, described once as a list of flat-coloured parts and
	built twice:
	  * the first-person viewmodel (ViewmodelController, scale 1)
	  * the rifle other players see in your hands (CharacterService, smaller)

	Gun space: the origin is where the right hand holds the pistol grip.
	+X = right, +Y = up, -Z = forward (down the barrel).

	Each part: { Name, Shape, Size, Position, Rotation(degrees), ColorKey, Group }
	  Shape     "Block" | "Cylinder" | "Ball" | "Wedge"
	  Size      for a Cylinder: Vector3(length, diameter, diameter), and the
	            cylinder runs along Z (forward) unless Rotation is given
	            (UP = standing up, X = sideways)
	  ColorKey  a key in Config.Palette
	  Group     "Bolt" parts are animated by the viewmodel (Position is
	            relative to the bolt pivot)
]]

local Config = require(script.Parent.Config)

local GunModel = {}

local V = Vector3.new

local X = V(0, 0, 0) -- "rotation given": a cylinder that stays along X (sideways)
local UP = V(0, 0, 90) -- a cylinder standing up (along Y)

GunModel.Parts = {
	-- STOCK
	{ "StockBody", "Block", V(0.22, 0.28, 0.9), V(0, -0.07, 0.82), nil, "GunFurniture" },
	{ "StockComb", "Block", V(0.2, 0.07, 0.5), V(0, 0.12, 0.84), nil, "GunFurniture" },
	{ "CheekPostA", "Cylinder", V(0.07, 0.04, 0.04), V(0, 0.07, 0.66), UP, "GunMetalLight" },
	{ "CheekPostB", "Cylinder", V(0.07, 0.04, 0.04), V(0, 0.07, 1.02), UP, "GunMetalLight" },
	{ "StockUnder", "Wedge", V(0.22, 0.22, 0.5), V(0, -0.32, 0.98), V(0, 0, 180), "GunFurniture" },
	{ "StockBridge", "Block", V(0.18, 0.1, 0.36), V(0, -0.23, 0.5), nil, "GunFurniture" },
	{ "StockLine", "Block", V(0.226, 0.03, 0.5), V(0, -0.03, 0.88), nil, "GunAccent" },
	{ "StockSpacer", "Block", V(0.23, 0.5, 0.04), V(0, -0.1, 1.29), nil, "GunAccent" },
	{ "ButtPad", "Block", V(0.24, 0.54, 0.09), V(0, -0.1, 1.355), nil, "GunMetal" },
	{ "SlingLoop", "Block", V(0.03, 0.08, 0.14), V(0, -0.27, 1.12), nil, "GunMetalLight" },

	-- GRIP + TRIGGER
	{ "Grip", "Block", V(0.15, 0.38, 0.2), V(0, -0.27, 0.16), V(-18, 0, 0), "GunFurniture" },
	{ "GripCap", "Block", V(0.16, 0.04, 0.22), V(0, -0.46, 0.22), V(-18, 0, 0), "GunMetal" },
	{ "TriggerGuard", "Block", V(0.04, 0.03, 0.36), V(0, -0.25, -0.06), nil, "GunMetalLight" },
	{ "TriggerGuardFront", "Block", V(0.04, 0.14, 0.03), V(0, -0.19, -0.23), nil, "GunMetalLight" },
	{ "Trigger", "Block", V(0.03, 0.11, 0.03), V(0, -0.17, -0.04), V(15, 0, 0), "GunAccent" },

	-- RECEIVER
	{ "Receiver", "Block", V(0.22, 0.24, 1.1), V(0, 0.02, -0.25), nil, "GunMetal" },
	{ "ReceiverTop", "Cylinder", V(1.0, 0.2, 0.2), V(0, 0.1, -0.28), nil, "GunMetal" },
	{ "BoltShroud", "Cylinder", V(0.18, 0.16, 0.16), V(0, 0.08, 0.38), nil, "GunMetalLight" },
	{ "Rail", "Block", V(0.12, 0.04, 0.95), V(0, 0.22, -0.3), nil, "GunMetalLight" },
	{ "EjectionPort", "Block", V(0.02, 0.09, 0.32), V(0.115, 0.06, -0.05), nil, "GunAccent" },
	{ "ScrewA", "Ball", V(0.045, 0.045, 0.045), V(0.112, -0.02, -0.62), nil, "GunMetalLight" },
	{ "ScrewB", "Ball", V(0.045, 0.045, 0.045), V(0.112, -0.02, 0.12), nil, "GunMetalLight" },

	-- MAGAZINE
	{ "Magazine", "Block", V(0.15, 0.3, 0.34), V(0, -0.25, -0.52), V(-6, 0, 0), "GunMetalLight" },
	{ "MagazineBase", "Block", V(0.17, 0.05, 0.38), V(0, -0.41, -0.54), V(-6, 0, 0), "GunMetal" },
	{ "MagRelease", "Block", V(0.03, 0.06, 0.07), V(0.09, -0.12, -0.3), nil, "GunAccent" },

	-- HANDGUARD (free-float tube with a top rail and M-LOK slots)
	{ "HandguardNut", "Cylinder", V(0.08, 0.3, 0.3), V(0, 0, -0.8), nil, "GunMetal" },
	{ "Handguard", "Cylinder", V(1.25, 0.27, 0.27), V(0, 0, -1.45), nil, "GunFurniture" },
	{ "HandguardRail", "Block", V(0.11, 0.04, 1.25), V(0, 0.15, -1.45), nil, "GunMetalLight" },
	{ "HandguardSpine", "Block", V(0.12, 0.04, 1.1), V(0, -0.145, -1.48), nil, "GunMetal" },

	-- BIPOD (folded)
	{ "BipodMount", "Block", V(0.12, 0.07, 0.12), V(0, -0.18, -1.98), nil, "GunMetal" },
	{ "BipodL", "Block", V(0.045, 0.045, 0.6), V(-0.06, -0.21, -1.65), nil, "GunMetalLight" },
	{ "BipodR", "Block", V(0.045, 0.045, 0.6), V(0.06, -0.21, -1.65), nil, "GunMetalLight" },
	{ "BipodFootL", "Ball", V(0.07, 0.07, 0.07), V(-0.06, -0.21, -1.34), nil, "GunMetal" },
	{ "BipodFootR", "Ball", V(0.07, 0.07, 0.07), V(0.06, -0.21, -1.34), nil, "GunMetal" },

	-- BARREL (fluted)
	{ "BarrelCollar", "Cylinder", V(0.1, 0.16, 0.16), V(0, 0.04, -2.1), nil, "GunMetalLight" },
	{ "Barrel", "Cylinder", V(1.95, 0.11, 0.11), V(0, 0.04, -3.0), nil, "GunMetal" },
	{ "FluteL", "Block", V(0.02, 0.022, 1.2), V(-0.055, 0.04, -2.8), nil, "GunMetalLight" },
	{ "FluteR", "Block", V(0.02, 0.022, 1.2), V(0.055, 0.04, -2.8), nil, "GunMetalLight" },
	{ "FluteTop", "Block", V(0.022, 0.02, 1.2), V(0, 0.096, -2.8), nil, "GunMetalLight" },

	-- MUZZLE BRAKE (ported)
	{ "Brake", "Block", V(0.18, 0.16, 0.36), V(0, 0.04, -4.0), nil, "GunMetal" },
	{ "BrakeTip", "Cylinder", V(0.05, 0.13, 0.13), V(0, 0.04, -4.2), nil, "GunMetalLight" },

	-- SCOPE
	{ "ScopeRingFront", "Cylinder", V(0.08, 0.16, 0.16), V(0, 0.36, -0.7), nil, "GunMetalLight" },
	{ "ScopeRingRear", "Cylinder", V(0.08, 0.16, 0.16), V(0, 0.36, -0.02), nil, "GunMetalLight" },
	{ "ScopeRingCapFront", "Block", V(0.17, 0.035, 0.08), V(0, 0.445, -0.7), nil, "GunMetalLight" },
	{ "ScopeRingCapRear", "Block", V(0.17, 0.035, 0.08), V(0, 0.445, -0.02), nil, "GunMetalLight" },
	{ "ScopeMountFront", "Block", V(0.07, 0.12, 0.1), V(0, 0.27, -0.7), nil, "GunMetalLight" },
	{ "ScopeMountRear", "Block", V(0.07, 0.12, 0.1), V(0, 0.27, -0.02), nil, "GunMetalLight" },
	{ "ScopeTube", "Cylinder", V(1.0, 0.13, 0.13), V(0, 0.36, -0.35), nil, "GunMetal" },
	{ "ScopeTaper", "Cylinder", V(0.12, 0.18, 0.18), V(0, 0.36, -0.86), nil, "GunMetal" },
	{ "ScopeObjective", "Cylinder", V(0.34, 0.23, 0.23), V(0, 0.36, -1.03), nil, "GunMetal" },
	{ "ScopeObjectiveRing", "Cylinder", V(0.04, 0.25, 0.25), V(0, 0.36, -1.18), nil, "GunAccent" },
	{ "ScopeLensFront", "Cylinder", V(0.02, 0.2, 0.2), V(0, 0.36, -1.205), nil, "ScopeGlass" },
	{ "ScopeEyepiece", "Cylinder", V(0.26, 0.19, 0.19), V(0, 0.36, 0.25), nil, "GunMetal" },
	{ "ScopeEyepieceRing", "Cylinder", V(0.05, 0.205, 0.205), V(0, 0.36, 0.17), nil, "GunMetalLight" },
	{ "ScopeLensRear", "Cylinder", V(0.02, 0.16, 0.16), V(0, 0.36, 0.385), nil, "ScopeGlass" },
	{ "ScopeTurretHousing", "Block", V(0.16, 0.13, 0.16), V(0, 0.36, -0.38), nil, "GunMetal" },
	{ "ScopeTurretTop", "Cylinder", V(0.09, 0.12, 0.12), V(0, 0.46, -0.38), UP, "GunMetalLight" },
	{ "ScopeTurretTopCap", "Cylinder", V(0.03, 0.135, 0.135), V(0, 0.515, -0.38), UP, "GunAccent" },
	{ "ScopeTurretSide", "Cylinder", V(0.09, 0.11, 0.11), V(0.11, 0.36, -0.38), X, "GunMetalLight" },
	{ "ScopeTurretLeft", "Cylinder", V(0.07, 0.1, 0.1), V(-0.105, 0.36, -0.38), X, "GunMetalLight" },

	-- BOLT (animated; positions are relative to GunModel.BoltPivot)
	{ "BoltHandle", "Block", V(0.26, 0.05, 0.05), V(0.13, 0, 0), nil, "GunMetalLight", "Bolt" },
	{ "BoltKnob", "Ball", V(0.11, 0.11, 0.11), V(0.27, 0, 0), nil, "GunAccent", "Bolt" },
}

-- Repeated details generated in loops (rail teeth, M-LOK slots, brake ports)
for i = 0, 7 do
	table.insert(GunModel.Parts, { "RailTooth" .. i, "Block", V(0.13, 0.03, 0.05), V(0, 0.25, -0.68 + i * 0.11), nil, "GunMetal" })
end
for _, side in ipairs({ -1, 1 }) do
	for k = 0, 2 do
		local name = ("MLok%s%d"):format(side < 0 and "L" or "R", k)
		table.insert(GunModel.Parts, { name, "Block", V(0.02, 0.035, 0.16), V(side * 0.136, 0, -1.08 - k * 0.33), nil, "GunMetal" })
	end
end
for k = 0, 2 do
	table.insert(GunModel.Parts, { "BrakePort" .. k, "Block", V(0.19, 0.09, 0.045), V(0, 0.04, -3.9 - k * 0.09), nil, "GunMetalLight" })
end

-- Where the bolt handle rotates/slides from (gun space)
GunModel.BoltPivot = CFrame.new(0.07, 0.08, 0.1)
-- Tip of the barrel (gun space)
GunModel.Muzzle = CFrame.new(0, 0.04, -4.23)
-- Centre of the scope's rear lens (gun space); used to aim down the scope
GunModel.ScopeEye = Vector3.new(0, 0.36, 0.39)

-- The local CFrame of a part spec (cylinders are turned to run along Z).
local function specCFrame(spec, scale)
	local rot = spec[5] or Vector3.zero
	local cf = CFrame.new(spec[4] * scale)
		* CFrame.Angles(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z))
	if spec[2] == "Cylinder" and not spec[5] then
		cf *= CFrame.Angles(0, math.rad(90), 0) -- Roblox cylinders run along X
	end
	return cf
end

--[[
	Builds the gun into `parent`.
	options:
		Scale      size multiplier (default 1)
		Anchored   anchor the parts (viewmodel) or leave them free to weld
		CastShadow
	Returns { Parts = {[name] = part}, Offsets = {[name] = CFrame}, Bolt = {[name] = true} }
	Offsets of "Bolt" parts are relative to BoltPivot; all others to the grip.
]]
function GunModel.Build(parent, options)
	options = options or {}
	local scale = options.Scale or 1
	local result = { Parts = {}, Offsets = {}, Bolt = {} }

	for _, spec in ipairs(GunModel.Parts) do
		local name, shape, size = spec[1], spec[2], spec[3]
		local part
		if shape == "Wedge" then
			part = Instance.new("WedgePart")
		else
			part = Instance.new("Part")
			if shape == "Cylinder" then
				part.Shape = Enum.PartType.Cylinder
			elseif shape == "Ball" then
				part.Shape = Enum.PartType.Ball
			end
		end
		part.Name = name
		part.Size = size * scale
		part.Color = Config.Palette[spec[6]] or Color3.new(1, 0, 1)
		part.Material = Enum.Material.SmoothPlastic
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Anchored = options.Anchored == true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.CastShadow = options.CastShadow == true
		part.Parent = parent

		result.Parts[name] = part
		result.Offsets[name] = specCFrame(spec, scale)
		if spec[7] == "Bolt" then
			result.Bolt[name] = true
		end
	end
	return result
end

-- CFrame of every part for a given grip CFrame (bolt closed). Handy for
-- placing the gun once before welding it.
function GunModel.Place(built, grip, scale)
	scale = scale or 1
	local boltPivot = grip * CFrame.new(GunModel.BoltPivot.Position * scale)
	for name, part in pairs(built.Parts) do
		local base = built.Bolt[name] and boltPivot or grip
		part.CFrame = base * built.Offsets[name]
	end
end

return GunModel
