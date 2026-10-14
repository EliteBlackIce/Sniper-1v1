--[[
	MapBuilder.lua  (ServerScriptService.Server.MapBuilder)

	Builds the lobby and the arena out of simple flat-coloured parts.
	Everything is SmoothPlastic and takes its colour from Config.Palette.

	The arena is built from a HALF map that gets mirrored, so both spawns are
	perfectly fair. Coordinates below are LOCAL to the arena centre:
		X = long axis (spawns at -X and +X)
		Y = up (floor top is at Y = 0)
		Z = width

	Mirror flags on each piece:
		nil   place once
		"X"   also place a copy mirrored across X = 0 (other team's side)
		"Z"   also place a copy mirrored across Z = 0
		"XZ"  place 4 copies (both mirrors)
		"R"   also place a copy turned 180 degrees around the centre (point symmetry)

	Collision (clean hitboxes): only the big solid shapes collide. Detail
	parts (window frames, railings, steps, car trim...) are built inside
	builder.decor(...) and neither collide nor stop bullets, so they can't
	snag you or eat shots. Stairs are an invisible smooth ramp under the
	visible steps. builder.soft(...) parts (tree leaves) don't collide but
	still block bullets and sight.
]]

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local Palette = Config.Palette
local MapBuilder = {}

----------------------------------------------------------------------------
-- Part helpers
----------------------------------------------------------------------------

-- Reflects a CFrame across the world X=0 plane. The rotation M*R*M is still a
-- proper rotation, and the result looks like a true mirror image for any part
-- that is symmetric across its own X axis (blocks, wedges, cylinders).
local function mirrorX(cf)
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	return CFrame.new(-x, y, z, r00, -r01, -r02, -r10, r11, r12, -r20, r21, r22)
end

-- Mirror across Z = 0 is "mirror across X, then spin 180 degrees around Y".
local function mirrorZ(cf)
	return CFrame.Angles(0, math.pi, 0) * mirrorX(cf)
end

local function newPart(className, size, cf, color, parent, shape)
	local part = Instance.new(className)
	if shape then
		part.Shape = shape
	end
	part.Anchored = true
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CastShadow = true
	part.Parent = parent
	return part
end

-- A builder places parts relative to an origin, with optional mirroring.
local function makeBuilder(origin, parent)
	local base = CFrame.new(origin)
	local builder = {}
	local mode = nil -- nil (solid) / "decor" / "soft"

	local function applyMode(part)
		if mode == "decor" or mode == "soft" then
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = mode == "soft"
		end
	end

	-- Runs fn with every part it places marked as detail (no collision, no hits).
	function builder.decor(fn)
		local old = mode
		mode = "decor"
		fn()
		mode = old
	end

	-- Like decor, but bullets and line of sight still stop at these parts.
	function builder.soft(fn)
		local old = mode
		mode = "soft"
		fn()
		mode = old
	end

	-- Makes parts invisible (collision-only shapes).
	function builder.invisible(parts)
		for _, part in ipairs(parts) do
			part.Transparency = 1
			part.CastShadow = false
		end
		return parts
	end

	-- Sets a material (e.g. Neon for lights) on the parts.
	function builder.material(parts, material, reflectance)
		for _, part in ipairs(parts) do
			part.Material = material
			if reflectance then
				part.Reflectance = reflectance
			end
		end
		return parts
	end

	function builder.place(className, size, localCF, color, mirror, shape)
		local cfs = { localCF }
		if mirror == "R" then
			-- point symmetry: a copy turned 180 degrees around the centre
			table.insert(cfs, CFrame.Angles(0, math.pi, 0) * localCF)
		end
		if mirror == "X" or mirror == "XZ" then
			table.insert(cfs, mirrorX(localCF))
		end
		if mirror == "Z" or mirror == "XZ" then
			for i = 1, #cfs do
				table.insert(cfs, mirrorZ(cfs[i]))
			end
		end
		local parts = {}
		for _, cf in ipairs(cfs) do
			local part = newPart(className, size, base * cf, color, parent, shape)
			applyMode(part)
			table.insert(parts, part)
		end
		return parts
	end

	function builder.block(size, pos, color, mirror)
		return builder.place("Part", size, CFrame.new(pos), color, mirror)
	end

	-- A block with any CFrame (rotated)
	function builder.part(size, cf, color, mirror)
		return builder.place("Part", size, cf, color, mirror)
	end

	-- A cylinder `length` long, `diameter` wide. By default it stands UP
	-- (vertical); pass a CFrame with rotation to lay it down.
	function builder.cylinder(length, diameter, pos, color, mirror, cf)
		local placeCF = cf or (CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2))
		return builder.place("Part", Vector3.new(length, diameter, diameter), placeCF, color, mirror, Enum.PartType.Cylinder)
	end

	function builder.ball(diameter, pos, color, mirror)
		return builder.place("Part", Vector3.one * diameter, CFrame.new(pos), color, mirror, Enum.PartType.Ball)
	end

	-- A ramp whose LOW edge is centred at `lowPoint` (on the ground) and that
	-- rises toward horizontal direction `dir`.
	-- A WedgePart rises toward its local +Z, so we look along -dir.
	function builder.ramp(lowPoint, dir, length, height, width, color, mirror)
		dir = Vector3.new(dir.X, 0, dir.Z).Unit
		local center = lowPoint + dir * (length / 2) + Vector3.new(0, height / 2, 0)
		local cf = CFrame.lookAt(center, center - dir)
		return builder.place("WedgePart", Vector3.new(width, height, length), cf, color, mirror)
	end

	-- A free-standing wall made for wall running, with an accent trim on top.
	-- (color / trimColor are optional: default Palette.Light / Palette.AccentB)
	function builder.runWall(size, pos, mirror, color, trimColor)
		builder.block(size, pos, color or Palette.Light, mirror)
		local old = mode
		mode = "decor"
		local trim = Vector3.new(size.X + 0.4, 1, size.Z + 0.4)
		builder.block(trim, pos + Vector3.new(0, size.Y / 2 + 0.5, 0), trimColor or Palette.AccentB, mirror)
		mode = old
	end

	-- A ramp at a given slope (degrees, default 22) instead of a given length.
	-- Returns the parts and the ramp's length (its high edge is lowPoint + dir * length).
	function builder.slope(lowPoint, dir, height, width, color, mirror, degrees)
		local length = height / math.tan(math.rad(degrees or 22))
		return builder.ramp(lowPoint, dir, length, height, width, color, mirror), length
	end

	-- Same, but given the TOP edge (where the ramp meets the platform it climbs
	-- onto, at the platform's height) and the direction it rises toward.
	function builder.slopeTo(topEdge, dir, height, width, color, mirror, degrees)
		local length = height / math.tan(math.rad(degrees or 22))
		dir = Vector3.new(dir.X, 0, dir.Z).Unit
		local lowPoint = topEdge - dir * length - Vector3.new(0, height, 0)
		return builder.ramp(lowPoint, dir, length, height, width, color, mirror), length
	end

	-- A sloped (or flat) slab whose TOP surface runs along the centre line from
	-- point `a` to point `b` (bridges between platforms at different heights).
	function builder.incline(a, b, width, thickness, color, mirror)
		local mid = (a + b) / 2
		local cf = CFrame.lookAt(mid, b) * CFrame.new(0, -thickness / 2, 0)
		return builder.place("Part", Vector3.new(width, thickness, (b - a).Magnitude), cf, color, mirror)
	end

	-- A solid block with a thin decorative cap on top.
	function builder.capped(size, pos, color, capColor, mirror)
		local parts = builder.block(size, pos, color, mirror)
		local old = mode
		mode = "decor"
		builder.block(Vector3.new(size.X + 0.6, 1, size.Z + 0.6), pos + Vector3.new(0, size.Y / 2 + 0.5, 0), capColor, mirror)
		mode = old
		return parts
	end

	-- Floor (top at Y = 0) and four tall outer walls around a length x width
	-- arena, with a trim band on top and along the bottom of the walls.
	function builder.shell(length, width, wallHeight, floorColor, wallColor, trimColor)
		local V = Vector3.new
		local halfL, halfW = length / 2, width / 2
		builder.block(V(length + 20, 6, width + 20), V(0, -3, 0), floorColor)
		builder.block(V(length + 20, wallHeight, 10), V(0, wallHeight / 2, halfW + 5), wallColor, "Z")
		builder.block(V(10, wallHeight, width), V(halfL + 5, wallHeight / 2, 0), wallColor, "X")
		local old = mode
		mode = "decor"
		builder.block(V(length + 21, 2, 11), V(0, wallHeight + 1, halfW + 5), trimColor, "Z")
		builder.block(V(11, 2, width), V(halfL + 5, wallHeight + 1, 0), trimColor, "X")
		builder.block(V(length, 3, 1), V(0, 1.5, halfW - 0.5), trimColor, "Z")
		builder.block(V(1, 3, width - 2), V(halfL - 0.5, 1.5, 0), trimColor, "X")
		mode = old
	end

	return builder
end

-- The Arena<Name> map modules and LobbyBuilder use the same builder.
MapBuilder.MakeBuilder = makeBuilder

----------------------------------------------------------------------------
-- MAP ROTATION
-- Config.Match.Maps = { "Mesa", "Glacier", ... }  each match picks one at
--                                                  random (never the same
--                                                  map twice in a row)
-- Config.Match.Maps = nil                          same, with DEFAULT_MAPS
-- Config.Match.Maps = false                        always Config.Match.Map
-- Names without an Arena<Name> module are skipped; if nothing usable is
-- left, the rotation falls back to DEFAULT_MAPS.
----------------------------------------------------------------------------
local DEFAULT_MAPS = { "Mesa", "Glacier", "Monolith", "Temple", "Neon", "Islands" }

local function mapExists(name)
	return type(name) == "string" and script.Parent:FindFirstChild("Arena" .. name) ~= nil
end

-- The maps a match can be played on (only ones that actually exist).
function MapBuilder.GetMapList()
	local list = Config.Match.Maps
	if list == nil then
		list = DEFAULT_MAPS
	elseif type(list) ~= "table" then
		list = { Config.Match.Map }
	end
	local maps = {}
	for _, name in ipairs(list) do
		if mapExists(name) and not table.find(maps, name) then
			table.insert(maps, name)
		end
	end
	if #maps == 0 then
		for _, name in ipairs(DEFAULT_MAPS) do
			if mapExists(name) then
				table.insert(maps, name)
			end
		end
	end
	return maps
end

-- Picks a random map for the next match, avoiding `previous` when there is a choice.
function MapBuilder.PickMap(previous)
	local maps = MapBuilder.GetMapList()
	if #maps > 1 and previous then
		local index = table.find(maps, previous)
		if index then
			table.remove(maps, index)
		end
	end
	return maps[math.random(1, #maps)]
end

-- Builds the arena for match slot `index` (each slot gets its own copy) using
-- map `mapName` (default: the first map in the rotation). The returned info
-- has the map's name in MapName.
function MapBuilder.BuildArena(index, mapName)
	-- each map is a module ArenaMesa / ArenaGlacier / ... that returns its
	-- spawns and playground dummy spots
	if not mapExists(mapName) then
		mapName = MapBuilder.GetMapList()[1]
	end
	local mapModule = require(script.Parent["Arena" .. mapName])
	local origin = Vector3.new(0, 0, index * Config.Match.ArenaSpacing)
	local model = Instance.new("Model")
	model.Name = "Arena" .. index .. "_" .. mapName
	local spawns, dummySpots = mapModule.Build(makeBuilder(origin, model))

	local folder = workspace:FindFirstChild("Arenas")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Arenas"
		folder.Parent = workspace
	end
	model.Parent = folder

	local base = CFrame.new(origin)
	return {
		Model = model,
		Index = index,
		MapName = mapName,
		Origin = origin,
		FloorY = origin.Y,
		Spawns = { base * spawns[1], base * spawns[2] },
		DummySpots = dummySpots or {}, -- for the Playground (local to Origin)
	}
end

----------------------------------------------------------------------------
-- LOBBY (built by LobbyBuilder)
----------------------------------------------------------------------------
function MapBuilder.BuildLobby()
	-- the lobby lives in its own module (required here, after MapBuilder has loaded)
	return require(script.Parent.LobbyBuilder).Build()
end

return MapBuilder
