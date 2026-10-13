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
	function builder.runWall(size, pos, mirror)
		builder.block(size, pos, Palette.Light, mirror)
		local trim = Vector3.new(size.X + 0.2, 0.6, size.Z + 0.2)
		builder.block(trim, pos + Vector3.new(0, size.Y / 2 + 0.3, 0), Palette.AccentB, mirror)
	end

	return builder
end

-- Other map modules (e.g. ArenaDowntown) use the same builder.
MapBuilder.MakeBuilder = makeBuilder

----------------------------------------------------------------------------
-- ARENA
----------------------------------------------------------------------------
local ARENA_LENGTH = 360 -- X
local ARENA_WIDTH = 250 -- Z
local WALL_HEIGHT = 70

-- The original simple arena ("Classic"). Set Config.Match.Map = "Classic" to use it.
local function buildClassicArena(index)
	local origin = Vector3.new(0, 0, index * Config.Match.ArenaSpacing)
	local model = Instance.new("Model")
	model.Name = "Arena" .. index

	local b = makeBuilder(origin, model)
	local V = Vector3.new

	-- Floor + subtle lane stripes
	b.block(V(ARENA_LENGTH, 4, ARENA_WIDTH), V(0, -2, 0), Palette.Snow)
	b.block(V(ARENA_LENGTH - 20, 0.1, 1.2), V(0, 0.05, 70), Palette.Mid, "Z")
	b.block(V(1.2, 0.1, ARENA_WIDTH - 20), V(0, 0.05, 0), Palette.Mid)

	-- Outer walls
	local halfL, halfW = ARENA_LENGTH / 2, ARENA_WIDTH / 2
	b.block(V(ARENA_LENGTH + 8, WALL_HEIGHT, 4), V(0, WALL_HEIGHT / 2, halfW + 2), Palette.Light, "Z")
	b.block(V(4, WALL_HEIGHT, ARENA_WIDTH), V(halfL + 2, WALL_HEIGHT / 2, 0), Palette.Light, "X")
	-- Wall base trim
	b.block(V(ARENA_LENGTH, 1.5, 1), V(0, 0.75, halfW - 0.5), Palette.Mid, "Z")

	-- SPAWN DECKS (one per side) -----------------------------------------
	b.block(V(36, 8, 46), V(-158, 4, 0), Palette.Mid, "X")
	b.block(V(36.2, 0.4, 46.2), V(-158, 8.2, 0), Palette.Snow, "X") -- deck top
	b.ramp(V(-120, 0, 0), V(-1, 0, 0), 20, 8, 14, Palette.AccentB, "X")
	b.ramp(V(-158, 0, 43), V(0, 0, -1), 20, 8, 12, Palette.AccentB, "XZ")
	-- Spawn cover on the deck edge
	b.block(V(3, 5, 12), V(-143, 10.5, 15), Palette.AccentA, "XZ")
	-- Canopy above spawn (a ceiling to run on with Magnetic Boots)
	b.block(V(28, 2, 30), V(-162, 26, 0), Palette.Mid, "X")
	b.block(V(2, 18, 2), V(-149, 17, 14), Palette.Dark, "XZ")

	-- CENTER TOWER --------------------------------------------------------
	b.block(V(22, 40, 22), V(0, 20, 0), Palette.Light)
	b.block(V(34, 2, 34), V(0, 41, 0), Palette.Mid) -- overhanging top (ceiling run)
	b.block(V(3, 4, 10), V(-11, 44, 0), Palette.AccentA, "X")
	-- Stair blocks to the top (double jump between them)
	b.block(V(12, 13, 12), V(-25, 6.5, -25), Palette.Mid, "XZ")
	b.block(V(10, 28, 10), V(-15, 14, -25), Palette.Light, "XZ")

	-- MID TOWERS ----------------------------------------------------------
	b.block(V(16, 26, 16), V(-75, 13, -70), Palette.Light, "XZ")
	b.block(V(22, 2, 22), V(-75, 27, -70), Palette.Mid, "XZ")
	b.block(V(3, 4, 8), V(-75, 30, -79), Palette.AccentA, "XZ")
	-- Step + ramp up to the step
	b.block(V(12, 14, 12), V(-59, 7, -70), Palette.Mid, "XZ")
	b.ramp(V(-31, 0, -70), V(-1, 0, 0), 22, 14, 10, Palette.AccentB, "XZ")
	-- Bridge between the two mid towers on the same side (crosses the centre lane)
	b.block(V(8, 1.5, 124), V(-75, 27.25, 0), Palette.Mid, "X")
	b.block(V(0.6, 1.2, 124), V(-78.7, 28.6, 0), Palette.AccentB, "X")
	b.block(V(0.6, 1.2, 124), V(-71.3, 28.6, 0), Palette.AccentB, "X")

	-- WALL-RUN WALLS ------------------------------------------------------
	-- Long lanes: walls separating the side lanes from the middle
	b.runWall(V(70, 26, 2), V(-50, 13, -90), "XZ")
	-- Near spawn: a pair of walls to run along out of spawn
	b.runWall(V(46, 22, 2), V(-112, 11, -34), "XZ")
	-- Near centre: blocks the middle lane sightline and gives a wall to run
	b.runWall(V(2, 22, 40), V(-38, 11, 0), "X")
	-- Tall wall in the side lane for big wall runs
	b.runWall(V(40, 34, 2), V(0, 17, -108), "Z")

	-- COVER ----------------------------------------------------------------
	b.block(V(4, 6, 12), V(-95, 3, 0), Palette.AccentA, "X")
	b.block(V(14, 4, 3), V(-65, 2, 0), Palette.AccentA, "X")
	b.block(V(10, 5, 4), V(-122, 2.5, -62), Palette.AccentA, "XZ")
	b.block(V(6, 8, 6), V(-28, 4, -52), Palette.AccentA, "XZ")
	b.block(V(6, 5, 10), V(-100, 2.5, -108), Palette.AccentA, "XZ")
	b.block(V(8, 4, 8), V(-40, 2, -110), Palette.AccentA, "XZ")
	b.block(V(5, 10, 5), V(-140, 5, -95), Palette.Mid, "XZ")

	local folder = workspace:FindFirstChild("Arenas")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Arenas"
		folder.Parent = workspace
	end
	model.Parent = folder

	local spawnHeight = 8.4 + 3.2
	return {
		Model = model,
		Index = index,
		Origin = origin,
		FloorY = origin.Y,
		-- Spawns face the centre of the map
		Spawns = {
			CFrame.lookAt(origin + V(-160, spawnHeight, 0), origin + V(0, spawnHeight, 0)),
			CFrame.lookAt(origin + V(160, spawnHeight, 0), origin + V(0, spawnHeight, 0)),
		},
	}
end

-- Builds the arena for match slot `index` (each slot gets its own copy).
function MapBuilder.BuildArena(index)
	if Config.Match.Map == "Classic" then
		return buildClassicArena(index)
	end
	local ArenaDowntown = require(script.Parent.ArenaDowntown)
	local origin = Vector3.new(0, 0, index * Config.Match.ArenaSpacing)
	local model = Instance.new("Model")
	model.Name = "Arena" .. index .. "_Downtown"
	local spawns = ArenaDowntown.Build(makeBuilder(origin, model))

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
		Origin = origin,
		FloorY = origin.Y,
		Spawns = { base * spawns[1], base * spawns[2] },
	}
end

----------------------------------------------------------------------------
-- LOBBY (a small movement playground around the queue sign)
----------------------------------------------------------------------------
function MapBuilder.BuildLobby()
	local model = Instance.new("Model")
	model.Name = "Lobby"
	local b = makeBuilder(Vector3.zero, model)
	local V = Vector3.new

	b.block(V(140, 4, 140), V(0, -2, 0), Palette.Snow)
	b.block(V(140, 3, 2), V(0, 1.5, 69), Palette.Mid, "Z")
	b.block(V(2, 3, 140), V(69, 1.5, 0), Palette.Mid, "X")
	-- Practice wall-run walls (along the sides so the range stays visible), ramp and boxes
	b.runWall(V(2, 20, 50), V(-44, 10, -20), "X")
	b.ramp(V(-10, 0, 30), V(-1, 0, 0), 20, 8, 12, Palette.AccentB)
	b.block(V(16, 8, 16), V(-38, 4, 30), Palette.Mid)
	b.block(V(10, 16, 10), V(-38, 8, 48), Palette.Light)
	b.block(V(8, 4, 8), V(30, 2, 30), Palette.AccentA)
	b.block(V(8, 8, 8), V(42, 4, 38), Palette.AccentA)
	b.block(V(30, 2, 20), V(30, 24, 0), Palette.Mid) -- a ceiling for Magnetic Boots fans
	b.block(V(2, 23, 2), V(16, 11.5, -9), Palette.Dark, "Z")

	-- SHOOTING RANGE (north of the lobby, along -Z) ------------------------
	b.block(V(64, 4, 344), V(0, -2, -242), Palette.Snow)
	b.block(V(2, 8, 344), V(32, 4, -242), Palette.Light, "X") -- side walls
	b.block(V(64, 46, 4), V(0, 23, -416), Palette.Light) -- back wall
	for _, z in ipairs({ -120, -170, -270, -370 }) do
		b.block(V(60, 0.1, 1), V(0, 0.05, z), Palette.Mid) -- distance lines
	end
	b.block(V(16, 20, 10), V(12, 10, -300), Palette.AccentA) -- sniper's nest dummy platform
	b.block(V(8, 5, 3), V(-8, 2.5, -150), Palette.AccentA)
	b.block(V(6, 8, 3), V(14, 4, -215), Palette.Mid)
	b.block(V(10, 4, 3), V(-6, 2, -330), Palette.AccentA)

	-- Title sign (behind spawn, facing the lobby)
	local sign = newPart("Part", V(44, 12, 1), CFrame.new(0, 14, 66), Palette.UIPanel, model)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = sign
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 0.62)
	title.Text = "SNIPER DUEL"
	title.TextScaled = true
	title.FontFace = Font.new(Config.UI.FontFamily, Enum.FontWeight.Heavy)
	title.TextColor3 = Palette.UIText
	title.Parent = gui
	local sub = title:Clone()
	sub.Position = UDim2.fromScale(0, 0.62)
	sub.Size = UDim2.fromScale(1, 0.28)
	sub.Text = ("1v1  -  FIRST TO %d"):format(Config.Match.RoundsToWin)
	sub.FontFace = Font.new(Config.UI.FontFamily, Enum.FontWeight.Bold)
	sub.TextColor3 = Palette.UIAccent
	sub.Parent = gui

	model.Parent = workspace
	return {
		Model = model,
		SpawnCFrame = function()
			local offset = Vector3.new(math.random(-12, 12), 3.5, math.random(-12, 12))
			return CFrame.lookAt(offset, Vector3.new(0, 3.5, -60))
		end,
		KillY = -60,
		-- practice dummies on the range (see DummyService)
		DummySpots = {
			{ Position = V(-10, 0, -110), Motion = "Static" },
			{ Position = V(8, 0, -135), Motion = "Strafe", Amount = 8, Speed = 0.35 },
			{ Position = V(0, 0, -185), Motion = "Strafe", Amount = 14, Speed = 0.25 },
			{ Position = V(-14, 0, -235), Motion = "Static" },
			{ Position = V(-12, 4, -260), Motion = "Bob", Amount = 10, Speed = 0.6 },
			{ Position = V(12, 20, -300), Motion = "Static" },
			{ Position = V(0, 0, -370), Motion = "Strafe", Amount = 18, Speed = 0.2 },
		},
	}
end

return MapBuilder
