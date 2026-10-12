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
	            cylinder runs along Z (forward) unless Rotation says otherwise
	  ColorKey  a key in Config.Palette
	  Group     "Bolt" parts are animated by the viewmodel (Position is
	            relative to the bolt pivot)
]]

local Config = require(script.Parent.Config)

local GunModel = {}

local V = Vector3.new

GunModel.Parts = {
	-- STOCK
	{ "StockBody", "Block", V(0.22, 0.3, 0.95), V(0, -0.06, 0.8), nil, "GunFurniture" },
	{ "StockCheek", "Block", V(0.2, 0.09, 0.6), V(0, 0.135, 0.78), nil, "GunFurniture" },
	{ "StockUnder", "Wedge", V(0.22, 0.2, 0.55), V(0, -0.31, 0.95), V(0, 0, 180), "GunFurniture" },
	{ "StockLine", "Block", V(0.226, 0.03, 0.55), V(0, -0.02, 0.86), nil, "GunAccent" },
	{ "ButtPad", "Block", V(0.24, 0.52, 0.08), V(0, -0.1, 1.31), nil, "GunMetal" },

	-- GRIP + TRIGGER
	{ "Grip", "Block", V(0.15, 0.4, 0.2), V(0, -0.27, 0.16), V(-18, 0, 0), "GunFurniture" },
	{ "TriggerGuard", "Block", V(0.04, 0.03, 0.36), V(0, -0.25, -0.06), nil, "GunMetalLight" },
	{ "TriggerGuardFront", "Block", V(0.04, 0.14, 0.03), V(0, -0.19, -0.23), nil, "GunMetalLight" },
	{ "Trigger", "Block", V(0.03, 0.11, 0.03), V(0, -0.17, -0.04), V(15, 0, 0), "GunMetalLight" },

	-- RECEIVER
	{ "Receiver", "Block", V(0.22, 0.24, 1.1), V(0, 0.02, -0.25), nil, "GunMetal" },
	{ "ReceiverTop", "Cylinder", V(1.0, 0.2, 0.2), V(0, 0.1, -0.28), nil, "GunMetal" },
	{ "BoltShroud", "Block", V(0.14, 0.14, 0.16), V(0, 0.08, 0.36), nil, "GunMetalLight" },
	{ "Rail", "Block", V(0.12, 0.05, 0.95), V(0, 0.215, -0.3), nil, "GunMetalLight" },
	{ "EjectionPort", "Block", V(0.02, 0.09, 0.32), V(0.115, 0.06, -0.05), nil, "GunAccent" },

	-- MAGAZINE
	{ "Magazine", "Block", V(0.15, 0.3, 0.34), V(0, -0.25, -0.52), V(-6, 0, 0), "GunMetalLight" },
	{ "MagazineBase", "Block", V(0.17, 0.05, 0.38), V(0, -0.41, -0.54), V(-6, 0, 0), "GunMetal" },

	-- HANDGUARD + BIPOD
	{ "Handguard", "Block", V(0.26, 0.26, 1.15), V(0, -0.01, -1.38), nil, "GunFurniture" },
	{ "HandguardTop", "Block", V(0.2, 0.05, 1.15), V(0, 0.145, -1.38), nil, "GunFurniture" },
	{ "Vent1", "Block", V(0.266, 0.035, 0.16), V(0, 0.03, -1.02), nil, "GunMetal" },
	{ "Vent2", "Block", V(0.266, 0.035, 0.16), V(0, 0.03, -1.38), nil, "GunMetal" },
	{ "Vent3", "Block", V(0.266, 0.035, 0.16), V(0, 0.03, -1.74), nil, "GunMetal" },
	{ "BipodL", "Block", V(0.04, 0.04, 0.62), V(-0.07, -0.17, -1.55), nil, "GunMetalLight" },
	{ "BipodR", "Block", V(0.04, 0.04, 0.62), V(0.07, -0.17, -1.55), nil, "GunMetalLight" },

	-- BARREL
	{ "BarrelCollar", "Cylinder", V(0.12, 0.17, 0.17), V(0, 0.04, -1.99), nil, "GunMetalLight" },
	{ "Barrel", "Cylinder", V(1.9, 0.11, 0.11), V(0, 0.04, -2.9), nil, "GunMetal" },
	{ "Brake", "Block", V(0.18, 0.15, 0.34), V(0, 0.04, -3.9), nil, "GunMetal" },
	{ "BrakeSlot1", "Block", V(0.19, 0.03, 0.06), V(0, 0.04, -3.84), nil, "GunMetalLight" },
	{ "BrakeSlot2", "Block", V(0.19, 0.03, 0.06), V(0, 0.04, -3.97), nil, "GunMetalLight" },

	-- SCOPE
	{ "ScopeRingFront", "Cylinder", V(0.08, 0.16, 0.16), V(0, 0.36, -0.7), nil, "GunMetalLight" },
	{ "ScopeRingRear", "Cylinder", V(0.08, 0.16, 0.16), V(0, 0.36, -0.02), nil, "GunMetalLight" },
	{ "ScopeMountFront", "Block", V(0.07, 0.12, 0.1), V(0, 0.27, -0.7), nil, "GunMetalLight" },
	{ "ScopeMountRear", "Block", V(0.07, 0.12, 0.1), V(0, 0.27, -0.02), nil, "GunMetalLight" },
	{ "ScopeTube", "Cylinder", V(1.0, 0.13, 0.13), V(0, 0.36, -0.35), nil, "GunMetal" },
	{ "ScopeObjective", "Cylinder", V(0.34, 0.23, 0.23), V(0, 0.36, -1.0), nil, "GunMetal" },
	{ "ScopeObjectiveRing", "Cylinder", V(0.04, 0.25, 0.25), V(0, 0.36, -1.15), nil, "GunAccent" },
	{ "ScopeEyepiece", "Cylinder", V(0.26, 0.19, 0.19), V(0, 0.36, 0.25), nil, "GunMetal" },
	{ "ScopeTurretTop", "Cylinder", V(0.08, 0.11, 0.11), V(0, 0.45, -0.38), V(0, 0, 90), "GunMetalLight" },
	{ "ScopeTurretSide", "Cylinder", V(0.08, 0.1, 0.1), V(0.1, 0.36, -0.38), V(0, 0, 0), "GunMetalLight" }, -- rotation given = stays along X (sideways)
	{ "ScopeLensFront", "Cylinder", V(0.02, 0.2, 0.2), V(0, 0.36, -1.175), nil, "ScopeGlass" },
	{ "ScopeLensRear", "Cylinder", V(0.02, 0.16, 0.16), V(0, 0.36, 0.385), nil, "ScopeGlass" },

	-- BOLT (animated; positions are relative to GunModel.BoltPivot)
	{ "BoltHandle", "Block", V(0.26, 0.05, 0.05), V(0.13, 0, 0), nil, "GunMetalLight", "Bolt" },
	{ "BoltKnob", "Ball", V(0.11, 0.11, 0.11), V(0.27, 0, 0), nil, "GunMetalLight", "Bolt" },
}

-- Where the bolt handle rotates/slides from (gun space)
GunModel.BoltPivot = CFrame.new(0.07, 0.08, 0.1)
-- Tip of the barrel (gun space)
GunModel.Muzzle = CFrame.new(0, 0.04, -4.1)
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
