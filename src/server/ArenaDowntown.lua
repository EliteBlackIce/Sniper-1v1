--[[
	ArenaDowntown.lua  (ServerScriptService.Server.ArenaDowntown)

	"Downtown": a detailed city block built from flat-coloured parts.
	The map is mirrored across X = 0, so both spawns are identical.

	LAYOUT (top view, X = long axis, spawns at the far left / right)

	        N  skyline (perimeter buildings)
	   [Apartments]-catwalk-[Office tower]   [CITY HALL + clock tower]   (mirrored)
	   ==== sidewalk / lamps / trees ==========================================
	   SPAWN  >>>  bus, cars, barriers  >>>  PLAZA + FOUNTAIN  <<<  ...  SPAWN
	   ==== sidewalk ===========================================================
	   [park + billboard]                                     [park]
	   ===== ELEVATED TRAIN TRACK (parked train in the middle) =====  (stairs up at both ends)
	   [parking lot]   [market stalls]   [shop]
	        S  skyline

	Sightlines: the avenue (long, broken up by the bus/cars/fountain), the
	train deck (long, broken by the train), rooftops (high ground).
	Verticality: fire escapes up the apartment (24), office tower (48) and
	city hall (26), the clock tower (55), the train deck (22) and train roof.
	Wall runs: building faces, the bus, the train, park billboards.

	Colours come from Config.MapPalette.
]]

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local C = Config.MapPalette
local V = Vector3.new
local rad = math.rad

local ArenaDowntown = {}

----------------------------------------------------------------------------
-- PROP HELPERS (all take the builder `b` and a mirror flag `m`)
----------------------------------------------------------------------------

-- A building with a trim base, roof slab, parapet and windows.
-- faces: list of "N","S","E","W" that get windows.
local function building(b, cx, cz, w, d, h, color, faces, m, options)
	options = options or {}
	b.block(V(w, h, d), V(cx, h / 2, cz), color, m)
	b.block(V(w + 0.4, 2, d + 0.4), V(cx, 1, cz), C.Trim, m)
	b.block(V(w + 0.8, 0.8, d + 0.8), V(cx, h + 0.4, cz), C.Roof, m)
	-- parapet around the roof
	if not options.NoParapet then
		b.block(V(w + 0.8, 1.6, 0.8), V(cx, h + 1.6, cz + d / 2), C.Roof, m)
		b.block(V(w + 0.8, 1.6, 0.8), V(cx, h + 1.6, cz - d / 2), C.Roof, m)
		b.block(V(0.8, 1.6, d - 0.8), V(cx + w / 2, h + 1.6, cz), C.Roof, m)
		b.block(V(0.8, 1.6, d - 0.8), V(cx - w / 2, h + 1.6, cz), C.Roof, m)
	end
	-- a cornice band every few floors
	for y = 18, h - 6, 24 do
		b.block(V(w + 0.6, 0.6, d + 0.6), V(cx, y, cz), C.Trim, m)
	end

	-- windows
	local spacing = options.WindowSpacing or 7
	local floorHeight = options.FloorHeight or 8
	for _, face in ipairs(faces or {}) do
		local alongX = face == "N" or face == "S"
		local span = alongX and w or d
		local count = math.floor((span - 6) / spacing)
		local start = -(count - 1) * spacing / 2
		local floors = math.floor((h - 6) / floorHeight)
		for f = 0, floors - 1 do
			local y = 6 + f * floorHeight
			for i = 0, count - 1 do
				local offset = start + i * spacing
				local lit = ((i * 7 + f * 3) % 5) == 0
				local color2 = lit and C.WindowLit or C.Window
				if face == "N" then
					b.block(V(3, 4, 0.3), V(cx + offset, y, cz + d / 2 + 0.1), color2, m)
				elseif face == "S" then
					b.block(V(3, 4, 0.3), V(cx + offset, y, cz - d / 2 - 0.1), color2, m)
				elseif face == "E" then
					b.block(V(0.3, 4, 3), V(cx + w / 2 + 0.1, y, cz + offset), color2, m)
				else
					b.block(V(0.3, 4, 3), V(cx - w / 2 - 0.1, y, cz + offset), color2, m)
				end
			end
		end
	end
end

-- Switchback fire escape stairs up the outside of a building.
-- origin: ground point on the wall where the stairs start (Y ignored)
-- outward: unit vector pointing away from the wall; lateral: along the wall
local function fireEscape(b, origin, outward, lateral, levels, rise, m)
	local run, landing = 12, 4
	local base = V(origin.X, 0, origin.Z)
	for i = 0, levels - 1 do
		local y0 = rise * i
		local even = i % 2 == 0
		local lane = even and 1.5 or 4.5 -- the two lanes sit side by side
		local low = base + outward * lane + lateral * (even and landing or (landing + run)) + V(0, y0, 0)
		b.ramp(low, even and lateral or -lateral, run, rise, 3, C.Metal, m)
		-- landing at the top of this flight
		local landingCenter = even and (landing + run + landing / 2) or (landing / 2)
		local lp = base + outward * 3 + lateral * landingCenter + V(0, y0 + rise - 0.3, 0)
		local size = math.abs(outward.X) > 0.5 and V(6, 0.6, landing) or V(landing, 0.6, 6)
		b.block(size, lp, C.Metal, m)
		-- outer railing on the landing
		local rp = base + outward * 6 + lateral * landingCenter + V(0, y0 + rise + 1.2, 0)
		local railSize = math.abs(outward.X) > 0.5 and V(0.3, 3, landing) or V(landing, 3, 0.3)
		b.block(railSize, rp, C.Dark, m)
	end
end

local function acUnit(b, pos, m)
	b.block(V(4, 2.4, 3), pos + V(0, 1.2, 0), C.Metal, m)
	b.cylinder(0.3, 2.2, pos + V(0, 2.55, 0), C.Dark, m)
end

local function waterTower(b, pos, m)
	for _, o in ipairs({ V(2.6, 0, 2.6), V(-2.6, 0, 2.6), V(2.6, 0, -2.6), V(-2.6, 0, -2.6) }) do
		b.block(V(0.6, 8, 0.6), pos + o + V(0, 4, 0), C.Dark, m)
	end
	b.cylinder(7, 7.5, pos + V(0, 11.5, 0), C.Wood, m)
	b.cylinder(0.6, 8.2, pos + V(0, 15.3, 0), C.Trim, m)
	b.cylinder(1.2, 4, pos + V(0, 16.2, 0), C.Trim, m)
end

local function antenna(b, pos, height, m)
	b.cylinder(height, 0.4, pos + V(0, height / 2, 0), C.Metal, m)
	b.ball(0.9, pos + V(0, height, 0), Config.Palette.PlayerB, m)
end

-- Billboard on two legs; faceDir is the way the ad faces (+Z or -Z).
local function billboard(b, pos, width, height, legHeight, color, m)
	b.block(V(0.8, legHeight, 0.8), pos + V(-width / 2 + 2, legHeight / 2, 0), C.Metal, m)
	b.block(V(0.8, legHeight, 0.8), pos + V(width / 2 - 2, legHeight / 2, 0), C.Metal, m)
	b.block(V(width, height, 1.2), pos + V(0, legHeight + height / 2, 0), C.Dark, m)
	b.block(V(width - 1.6, height - 1.6, 1.4), pos + V(0, legHeight + height / 2, 0), color, m)
	b.block(V(width * 0.5, 1.2, 1.5), pos + V(-width * 0.12, legHeight + height * 0.62, 0), C.RoadWhite, m)
	b.block(V(width * 0.3, 1.2, 1.5), pos + V(-width * 0.22, legHeight + height * 0.38, 0), C.RoadWhite, m)
end

local function lamp(b, pos, armDir, m)
	b.cylinder(13, 0.5, pos + V(0, 6.5, 0), C.Metal, m)
	b.block(V(1.2, 0.8, 1.2), pos + V(0, 0.4, 0), C.Dark, m)
	local arm = pos + V(0, 13, 0) + armDir * 1.5
	b.part(V(0.35, 0.35, 3), CFrame.lookAt(arm, arm + armDir), C.Metal, m)
	b.part(V(1.4, 0.5, 2.2), CFrame.lookAt(arm + armDir * 1.8 - V(0, 0.3, 0), arm + armDir * 3), C.LampLight, m)
end

local function tree(b, pos, scale, m)
	scale = scale or 1
	b.block(V(5, 1.2, 5), pos + V(0, 0.6, 0), C.Curb, m) -- planter
	b.block(V(4.2, 0.2, 4.2), pos + V(0, 1.25, 0), C.Trunk, m)
	b.cylinder(7 * scale, 1.1 * scale, pos + V(0, 3.5 * scale, 0), C.Trunk, m)
	b.ball(8 * scale, pos + V(0, 8 * scale, 0), C.Foliage, m)
	b.ball(5.5 * scale, pos + V(2.2, 9.5, 1.2) * scale, C.FoliageDark, m)
	b.ball(5 * scale, pos + V(-2, 9.8, -1.6) * scale, C.Foliage, m)
end

-- A parked car. cf = position on the ground + facing (car's front is -Z).
local function car(b, cf, color, m)
	b.part(V(4.8, 1.8, 10), cf * CFrame.new(0, 1.6, 0), color, m)
	b.part(V(4.2, 1.6, 5.4), cf * CFrame.new(0, 3.3, 0.6), C.Window, m)
	b.part(V(4.3, 0.3, 5), cf * CFrame.new(0, 4.2, 0.6), color, m)
	for _, o in ipairs({ V(2.3, 1.1, 3.2), V(-2.3, 1.1, 3.2), V(2.3, 1.1, -3.2), V(-2.3, 1.1, -3.2) }) do
		b.cylinder(0.8, 2.2, nil, C.Dark, m, cf * CFrame.new(o))
	end
	b.part(V(1, 0.45, 0.2), cf * CFrame.new(1.6, 1.9, -5.05), C.LampLight, m)
	b.part(V(1, 0.45, 0.2), cf * CFrame.new(-1.6, 1.9, -5.05), C.LampLight, m)
	b.part(V(1, 0.45, 0.2), cf * CFrame.new(1.6, 1.9, 5.05), Config.Palette.PlayerB, m)
	b.part(V(1, 0.45, 0.2), cf * CFrame.new(-1.6, 1.9, 5.05), Config.Palette.PlayerB, m)
end

-- A city bus (big cover, and a wall to run along).
local function bus(b, cf, m)
	b.part(V(8.5, 7.5, 30), cf * CFrame.new(0, 4.6, 0), C.Bus, m)
	b.part(V(8.7, 2.6, 26), cf * CFrame.new(0, 6, 1), C.Window, m)
	b.part(V(8.7, 0.8, 30.2), cf * CFrame.new(0, 2.4, 0), C.RoadWhite, m)
	b.part(V(8.3, 3, 0.3), cf * CFrame.new(0, 6, -15.05), C.Window, m) -- windscreen
	b.part(V(7, 0.6, 26), cf * CFrame.new(0, 8.6, 1), C.Trim, m) -- roof unit
	for _, z in ipairs({ -9.5, 9.5 }) do
		for _, x in ipairs({ 4.1, -4.1 }) do
			b.cylinder(1, 2.6, nil, C.Dark, m, cf * CFrame.new(x, 1.3, z))
		end
	end
end

-- Concrete jersey barrier.
local function barrier(b, cf, m)
	b.part(V(2.4, 1.4, 8), cf * CFrame.new(0, 0.7, 0), C.Concrete, m)
	b.part(V(1.3, 1.8, 8), cf * CFrame.new(0, 2.3, 0), C.Concrete, m)
	b.part(V(1.35, 0.5, 8.05), cf * CFrame.new(0, 2.6, 0), Config.Palette.AccentB, m)
end

local function bench(b, cf, m)
	b.part(V(5, 0.4, 1.6), cf * CFrame.new(0, 1.4, 0), C.Wood, m)
	b.part(V(5, 1.4, 0.3), cf * CFrame.new(0, 2.3, 0.75), C.Wood, m)
	b.part(V(0.3, 1.2, 1.4), cf * CFrame.new(2.1, 0.6, 0), C.Metal, m)
	b.part(V(0.3, 1.2, 1.4), cf * CFrame.new(-2.1, 0.6, 0), C.Metal, m)
end

local function crates(b, pos, m)
	b.block(V(4, 4, 4), pos + V(0, 2, 0), C.Wood, m)
	b.block(V(4, 4, 4), pos + V(4.2, 2, 0.5), C.Wood, m)
	b.block(V(3.6, 3.6, 3.6), pos + V(2, 5.8, 0.2), Config.Palette.AccentB, m)
	b.block(V(4.2, 0.3, 4.2), pos + V(0, 4.1, 0), C.Trunk, m)
end

-- Market stall with a striped canopy.
local function stall(b, pos, color, m)
	b.block(V(10, 3.4, 4), pos + V(0, 1.7, 0), C.Wood, m)
	b.block(V(10.4, 0.4, 4.4), pos + V(0, 3.6, 0), C.Trim, m)
	for _, x in ipairs({ -4.6, 4.6 }) do
		b.block(V(0.4, 8, 0.4), pos + V(x, 4, -1.8), C.Metal, m)
		b.block(V(0.4, 8, 0.4), pos + V(x, 4, 1.8), C.Metal, m)
	end
	b.block(V(11, 0.5, 5.6), pos + V(0, 8.2, 0), color, m)
	b.block(V(11, 1, 0.3), pos + V(0, 7.6, -2.8), C.RoadWhite, m)
end

----------------------------------------------------------------------------
-- BUILD
----------------------------------------------------------------------------
function ArenaDowntown.Build(b)
	local X, Z = "X", "Z"
	local XZ = "XZ"

	-- GROUND ----------------------------------------------------------------
	b.block(V(460, 4, 320), V(0, -2, 0), C.Asphalt)
	-- avenue centre dashes + edge lines
	for x = -200, -54, 14 do
		b.block(V(7, 0.08, 0.6), V(x, 0.04, 0), C.RoadLine, X)
	end
	b.block(V(150, 0.08, 0.5), V(-128, 0.04, 15.5), C.RoadWhite, XZ)
	-- crosswalks at the plaza
	for z = -13, 13, 4 do
		b.block(V(6, 0.08, 2), V(-52, 0.04, z), C.RoadWhite, X)
	end
	-- sidewalks + curbs (north and south of the avenue)
	b.block(V(158, 0.5, 12), V(-125, 0.25, 24), C.Sidewalk, XZ)
	b.block(V(158, 0.6, 0.6), V(-125, 0.3, 17.8), C.Curb, XZ)
	b.block(V(158, 0.5, 14), V(-125, 0.25, 37), C.Sidewalk, X) -- forecourt in front of the north buildings

	-- CENTRAL PLAZA + FOUNTAIN ----------------------------------------------
	b.block(V(92, 0.5, 92), V(0, 0.25, 0), C.Sidewalk)
	for i = -40, 40, 10 do
		b.block(V(92, 0.06, 0.3), V(0, 0.53, i), C.Curb)
		b.block(V(0.3, 0.06, 92), V(i, 0.53, 0), C.Curb)
	end
	b.cylinder(2.6, 26, V(0, 1.8, 0), C.Curb)
	b.cylinder(0.4, 23, V(0, 3, 0), C.Water)
	b.cylinder(7, 3, V(0, 6, 0), C.BuildingA)
	b.cylinder(0.9, 10, V(0, 9.4, 0), C.Curb)
	b.cylinder(0.3, 9, V(0, 9.9, 0), C.Water)
	b.ball(1.8, V(0, 10.8, 0), C.Water)
	for _, p in ipairs({ V(-30, 0.5, -30) }) do
		bench(b, CFrame.new(p) * CFrame.Angles(0, rad(45), 0), XZ)
	end
	tree(b, V(-38, 0.5, -38), 1, XZ)
	tree(b, V(-38, 0.5, 38), 1, X)
	lamp(b, V(-44, 0.5, -22), V(1, 0, 0), XZ)

	-- CITY HALL (north of the plaza, centred) --------------------------------
	building(b, 0, 72, 46, 32, 26, C.BuildingA, { "S", "E", "W" })
	b.block(V(48, 2, 8), V(0, 1, 52), C.Concrete) -- porch floor
	for x = -18, 18, 7.2 do
		b.cylinder(20, 2.4, V(x, 12, 50), C.BuildingA)
	end
	b.block(V(50, 1.6, 9), V(0, 22.8, 51.5), C.BuildingA) -- porch roof
	b.block(V(50, 0.6, 9.4), V(0, 21.8, 51.5), C.Trim)
	b.block(V(10, 7, 0.4), V(0, 3.5, 55.9), C.Dark) -- doors
	-- clock tower
	b.block(V(12, 26, 12), V(0, 39, 74), C.BuildingA)
	b.block(V(13, 0.8, 13), V(0, 46, 74), C.Trim)
	b.cylinder(0.4, 7.5, nil, C.RoadWhite, nil, CFrame.new(0, 46, 67.8) * CFrame.Angles(0, rad(90), 0))
	b.part(V(0.5, 3, 0.2), CFrame.new(0, 47.2, 67.5), C.Dark)
	b.part(V(2.4, 0.5, 0.2), CFrame.new(1, 46, 67.5), C.Dark)
	b.block(V(14, 1.2, 14), V(0, 52.6, 74), C.Roof)
	b.block(V(9, 4, 9), V(0, 55.2, 74), C.BuildingA)
	b.block(V(5, 4, 5), V(0, 59.2, 74), C.Roof)
	antenna(b, V(0, 61.2, 74), 6)
	-- fire escapes on both sides up to the roof
	fireEscape(b, V(-23, 0, 58), V(-1, 0, 0), V(0, 0, 1), 3, 26 / 3, X)
	acUnit(b, V(-14, 26.8, 84), X)

	-- OFFICE TOWER (north, mirrored) ------------------------------------------
	building(b, -95, 69, 34, 46, 48, C.BuildingB, { "S", "E", "W" }, X)
	fireEscape(b, V(-112, 0, 50), V(-1, 0, 0), V(0, 0, 1), 6, 8, X)
	acUnit(b, V(-102, 48.8, 80), X)
	acUnit(b, V(-88, 48.8, 82), X)
	antenna(b, V(-84, 48.8, 58), 14, X)
	-- rooftop sniper nest
	b.block(V(10, 2.4, 1.6), V(-95, 50, 48.6), Config.Palette.AccentA, X)
	b.block(V(1.6, 2.4, 6), V(-80.6, 50, 52), Config.Palette.AccentA, X)

	-- APARTMENTS (north-west, mirrored) + catwalk to the office tower ---------
	building(b, -152.5, 72, 45, 56, 24, C.BuildingC, { "S", "E" }, X)
	fireEscape(b, V(-130, 0, 50), V(1, 0, 0), V(0, 0, 1), 3, 8, X)
	b.block(V(6, 0.6, 4), V(-121, 23.7, 68), C.Metal, X) -- catwalk
	b.block(V(6, 2.4, 0.3), V(-121, 25.2, 70), C.Dark, X)
	b.block(V(6, 2.4, 0.3), V(-121, 25.2, 66), C.Dark, X)
	waterTower(b, V(-165, 24.8, 88), X)
	acUnit(b, V(-145, 24.8, 92), X)
	billboard(b, V(-152, 24.8, 99), 30, 10, 4, Config.Palette.PlayerA, X)
	-- shop awnings on the apartment's street side
	for i, x in ipairs({ -168, -152, -136 }) do
		b.part(V(12, 0.5, 4), CFrame.new(x, 8, 41.5) * CFrame.Angles(rad(-15), 0, 0), C.Awning[i], X)
		b.block(V(6, 6.5, 0.4), V(x, 3.25, 43.9), C.Dark, X)
	end

	-- SKYLINE (perimeter buildings, windows face the arena) -------------------
	building(b, -230, 0, 24, 330, 70, C.BuildingD, { "E" }, X, { WindowSpacing = 9, FloorHeight = 9, NoParapet = true })
	-- (segments run from the corner at x = -218 to the middle at x = 0)
	local north = { { -189, 58, 76, C.BuildingD }, { -122, 76, 54, C.BuildingE }, { -42, 84, 66, C.BuildingD } }
	for _, seg in ipairs(north) do
		building(b, seg[1], 160, seg[2], 24, seg[3], seg[4], { "S" }, X, { WindowSpacing = 8, FloorHeight = 9, NoParapet = true })
	end
	local south = { { -189, 58, 58, C.BuildingE }, { -122, 76, 72, C.BuildingD }, { -42, 84, 50, C.BuildingE } }
	for _, seg in ipairs(south) do
		building(b, seg[1], -160, seg[2], 24, seg[3], seg[4], { "N" }, X, { WindowSpacing = 8, FloorHeight = 9, NoParapet = true })
	end

	-- SPAWN: TRANSIT STATIONS (mirrored) -------------------------------------
	b.block(V(30, 4, 40), V(-192, 2, 0), C.Concrete, X)
	b.block(V(30.4, 0.4, 40.4), V(-192, 4.2, 0), C.Sidewalk, X)
	b.block(V(1.2, 0.1, 40), V(-178, 4.45, 0), Config.Palette.AccentB, X) -- platform edge line
	b.ramp(V(-165, 0, 0), V(-1, 0, 0), 12, 4, 16, C.Concrete, X)
	for _, z in ipairs({ -16, 16 }) do
		b.block(V(1, 10, 1), V(-182, 9.4, z), C.Metal, X)
		b.block(V(1, 10, 1), V(-202, 9.4, z), C.Metal, X)
	end
	b.block(V(26, 1, 38), V(-192, 14.9, 0), Config.Palette.AccentA, X) -- canopy (ceiling to run on)
	b.block(V(10, 4, 1), V(-192, 13, 19.2), C.Dark, X) -- station sign
	barrier(b, CFrame.new(-172, 0, 14), X)
	barrier(b, CFrame.new(-172, 0, -14), X)

	-- AVENUE COVER (mirrored) -----------------------------------------------
	bus(b, CFrame.new(-82, 0, -6) * CFrame.Angles(0, rad(90), 0), X)
	car(b, CFrame.new(-140, 0, 9) * CFrame.Angles(0, rad(90), 0), C.CarColors[1], X)
	car(b, CFrame.new(-118, 0, -9) * CFrame.Angles(0, rad(65), 0), C.CarColors[2], X)
	car(b, CFrame.new(-60, 0, 10) * CFrame.Angles(0, rad(100), 0), C.CarColors[3], X)
	barrier(b, CFrame.new(-47, 0, 9), X)
	barrier(b, CFrame.new(-47, 0, -9), X)
	-- street furniture along the sidewalks
	for x = -190, -60, 35 do
		lamp(b, V(x, 0.5, 26), V(0, 0, -1), X)
		lamp(b, V(x, 0.5, -26), V(0, 0, 1), X)
	end
	for _, x in ipairs({ -172, -103, -68 }) do
		tree(b, V(x, 0.5, -26), 0.9, X)
	end
	tree(b, V(-160, 0.5, 26), 0.9, X)
	b.cylinder(2.2, 1.4, V(-150, 1.6, -27), C.Metal, X) -- bins
	b.cylinder(2.2, 1.4, V(-96, 1.6, 27), C.Metal, X)

	-- PARK (south of the avenue, mirrored) ------------------------------------
	b.block(V(84, 0.3, 26), V(-92, 0.15, -47), C.Grass, X)
	for _, p in ipairs({ V(-120, 0.3, -42), V(-78, 0.3, -54), V(-58, 0.3, -40) }) do
		tree(b, p, 1.15, X)
	end
	b.block(V(16, 2.6, 2.4), V(-100, 1.3, -38), C.FoliageDark, X) -- hedges (cover)
	b.block(V(2.4, 2.6, 12), V(-66, 1.3, -50), C.FoliageDark, X)
	bench(b, CFrame.new(-90, 0.3, -56), X)
	billboard(b, V(-92, 0, -33), 34, 12, 4, Config.Palette.PlayerB, X) -- wall-runnable

	-- ELEVATED TRAIN TRACK (south, along the whole map) -----------------------
	b.block(V(440, 2, 14), V(0, 21, -75), C.Concrete)
	b.block(V(440, 0.6, 15), V(0, 20, -75), C.Trim)
	-- low walls with gaps where the stairs arrive (x = +-150)
	b.block(V(440, 1.6, 0.8), V(0, 22.8, -81.6), C.Curb)
	b.block(V(56, 1.6, 0.8), V(-182, 22.8, -68.4), C.Curb, X)
	b.block(V(292, 1.6, 0.8), V(0, 22.8, -68.4), C.Curb)
	-- rails + sleepers
	b.block(V(440, 0.3, 0.4), V(0, 22.2, -77), C.Metal)
	b.block(V(440, 0.3, 0.4), V(0, 22.2, -73), C.Metal)
	for x = -216, -4, 8 do
		b.block(V(1.2, 0.15, 6), V(x, 22.05, -75), C.Trunk, X)
	end
	-- pillars
	for _, x in ipairs({ -20, -70, -120, -170 }) do
		b.block(V(4, 20, 8), V(x, 10, -75), C.Concrete, X)
		b.block(V(6, 1.5, 12), V(x, 19.25, -75), C.Trim, X)
	end
	-- stairs up (from the south sidewalk side)
	b.ramp(V(-150, 0, -34), V(0, 0, -1), 34, 22, 6, C.Concrete, X)
	-- the parked train (cover in the middle of the deck; stand on its roof)
	b.block(V(44, 8.5, 9), V(0, 26.5, -75), C.Train)
	b.block(V(44.2, 2.4, 9.2), V(0, 27.5, -75), C.Window)
	b.block(V(44.2, 0.6, 9.2), V(0, 24.4, -75), C.RoadWhite)
	b.block(V(42, 0.6, 7), V(0, 31, -75), C.Trim)
	b.block(V(0.3, 6, 3), V(-22.1, 25.2, -75), C.Dark) -- doors at the ends
	b.block(V(0.3, 6, 3), V(22.1, 25.2, -75), C.Dark)

	-- MARKET + SHOP (south, mirrored) -----------------------------------------
	stall(b, V(-62, 0, -100), C.Awning[1], X)
	stall(b, V(-34, 0, -100), C.Awning[2], X)
	stall(b, V(-34, 0, -116), C.Awning[3], X)
	crates(b, V(-50, 0, -110), X)
	building(b, -112, -122, 34, 26, 14, C.BuildingE, { "N", "E" }, X)
	b.part(V(34, 0.5, 5), CFrame.new(-112, 9, -107.6) * CFrame.Angles(rad(15), 0, 0), C.Awning[1], X)
	crates(b, V(-92, 0, -112), X) -- climb onto the shop roof
	b.block(V(4, 8, 4), V(-91, 4, -118), C.Wood, X)
	acUnit(b, V(-118, 14.8, -128), X)

	-- SHIPPING CONTAINERS (climbable cover, mirrored): crate -> container -> stacked container
	local function container(cf, color)
		b.part(V(8, 8.5, 20), cf * CFrame.new(0, 4.25, 0), color, X)
		for k = -3, 3 do
			b.part(V(8.1, 7.5, 0.4), cf * CFrame.new(0, 4.25, k * 2.6), C.Dark:Lerp(color, 0.6), X) -- ribs
		end
		b.part(V(8.1, 0.5, 20.1), cf * CFrame.new(0, 8.3, 0), C.Trim, X)
	end
	container(CFrame.new(-150, 0, -98), C.Awning[1])
	container(CFrame.new(-140, 0, -98), C.Awning[2])
	container(CFrame.new(-145, 8.5, -101) * CFrame.Angles(0, rad(12), 0), C.Awning[3])
	crates(b, V(-158, 0, -88), X)

	-- WAREHOUSE (south, mirrored)
	building(b, -62, -132, 34, 20, 18, C.BuildingA, { "N" }, X, { WindowSpacing = 8 })
	b.block(V(12, 10, 0.4), V(-62, 5, -121.9), C.Metal, X) -- roller door
	for y = 1, 9, 1.4 do
		b.block(V(12.1, 0.2, 0.5), V(-62, y, -121.8), C.Trim, X)
	end

	-- STATUE PLAZA (south centre)
	b.block(V(36, 0.5, 30), V(0, 0.25, -112), C.Sidewalk)
	b.block(V(8, 3, 8), V(0, 1.5, -112), C.Concrete)
	b.block(V(6, 0.6, 6), V(0, 3.3, -112), C.Trim)
	b.part(V(2.4, 9, 2.4), CFrame.new(0, 8, -112) * CFrame.Angles(0, rad(45), rad(12)), Config.Palette.AccentA)
	b.ball(3.4, V(0.9, 12.8, -112), Config.Palette.AccentB)
	tree(b, V(-14, 0.5, -122), 0.9, X)
	tree(b, V(-14, 0.5, -102), 0.9, X)
	bench(b, CFrame.new(-8, 0.5, -125) * CFrame.Angles(0, rad(180), 0), X)

	-- PARKING LOT (south-west, mirrored) --------------------------------------
	for i = 0, 4 do
		b.block(V(0.4, 0.08, 12), V(-198 + i * 8, 0.04, -112), C.RoadWhite, X)
	end
	car(b, CFrame.new(-194, 0, -112), C.CarColors[4], X)
	car(b, CFrame.new(-178, 0, -112), C.CarColors[5], X)
	car(b, CFrame.new(-170, 0, -96) * CFrame.Angles(0, rad(90), 0), C.CarColors[2], X)

	-- Spawns (on the station platforms, facing the city)
	local spawnHeight = 4.4 + 3.2
	return {
		CFrame.lookAt(V(-192, spawnHeight, 0), V(0, spawnHeight, 0)),
		CFrame.lookAt(V(192, spawnHeight, 0), V(0, spawnHeight, 0)),
	}
end

return ArenaDowntown
