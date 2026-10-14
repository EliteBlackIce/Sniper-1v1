--[[
	ArenaQuarry.lua  (ServerScriptService.Server.ArenaQuarry)

	"Quarry": big L-shaped blocks with walkable rooftops (a ramp up from the
	sheltered courtyard inside the L and one from outside), a tall wall right
	in the middle to wall run along, long free-standing walls and a raised
	overlook near each spawn. Point-symmetric (each side is the other turned
	180 degrees), so the two halves look different but play the same.

	TOP VIEW (X = long axis)

	   +----------------------------------------------------------+
	   |  runwall       ramp v                                     |
	   |   |       [====L roof====]      runwall ======            |
	   |   |        [L]  ^ramp                                     |
	   | SPAWN shield         cover  | centre |  cover   shield SPAWN|
	   |                             | wall   |      ramp v  [L]   |
	   |  ====== runwall              [====L roof====]       |     |
	   | [overlook]                          ramp ^      runwall   |
	   +----------------------------------------------------------+
]]

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local P = Config.Palette
local C = Config.MapPalette
local V = Vector3.new

local ArenaQuarry = {}

local LENGTH, WIDTH = 320, 220 -- floor (X, Z)
local WALL_H = 50
local ROOF = 16 -- L-block height

function ArenaQuarry.Build(b)
	local X, Z, R = "X", "Z", "R"
	local halfL, halfW = LENGTH / 2, WIDTH / 2

	local FLOOR = C.Concrete
	local WALL = C.BuildingE
	local BLOCK = C.BuildingE
	local COVER = P.Mid
	local RAMP = P.AccentB

	local function capped(size, pos, color, cap, m)
		b.block(size, pos, color, m)
		b.decor(function()
			b.block(V(size.X + 0.3, 0.6, size.Z + 0.3), pos + V(0, size.Y / 2 + 0.3, 0), cap, m)
		end)
	end
	-- a walkable block: a band just under the top instead of a cap
	local function banded(size, pos, color, band, m)
		b.block(size, pos, color, m)
		b.decor(function()
			b.block(V(size.X + 0.4, 1, size.Z + 0.4), pos + V(0, size.Y / 2 - 0.8, 0), band, m)
		end)
	end

	-- FLOOR + OUTER WALLS ------------------------------------------------------
	b.block(V(LENGTH + 10, 4, WIDTH + 10), V(0, -2, 0), FLOOR)
	b.block(V(LENGTH + 10, WALL_H, 4), V(0, WALL_H / 2, halfW + 2), WALL, Z)
	b.block(V(4, WALL_H, WIDTH + 10), V(halfL + 2, WALL_H / 2, 0), WALL, X)
	b.decor(function()
		b.block(V(LENGTH + 10, 1, 4.6), V(0, WALL_H + 0.5, halfW + 2), P.AccentA, Z)
		b.block(V(4.6, 1, WIDTH + 10), V(halfL + 2, WALL_H + 0.5, 0), P.AccentA, X)
		b.block(V(LENGTH, 1.2, 0.6), V(0, 0.6, halfW - 0.3), C.Trim, Z)
		b.block(V(0.6, 1.2, WIDTH), V(halfL - 0.3, 0.6, 0), C.Trim, X)
	end)

	-- L-BLOCKS with walkable roofs -------------------------------------------------
	-- long arm x -70..-10 (z 40..60), short arm z 10..40 (x -70..-50)
	b.block(V(60, ROOF, 20), V(-40, ROOF / 2, 50), BLOCK, R)
	b.block(V(20, ROOF, 30), V(-60, ROOF / 2, 25), BLOCK, R)
	b.decor(function()
		b.block(V(60.4, 1, 20.4), V(-40, ROOF - 0.8, 50), P.AccentA, R)
		b.block(V(20.4, 1, 30.2), V(-60, ROOF - 0.8, 24.9), P.AccentA, R)
	end)
	b.ramp(V(-28, 0, 8), V(0, 0, 1), 32, ROOF, 12, RAMP, R) -- from the courtyard
	b.ramp(V(-40, 0, 92), V(0, 0, -1), 32, ROOF, 12, RAMP, R) -- from outside
	-- roof cover
	capped(V(1.5, 4, 14), V(-12, ROOF + 2, 50), COVER, P.AccentB, R)
	capped(V(14, 6, 2), V(-58, ROOF + 3, 58), COVER, P.AccentB, R)

	-- CENTRE: one tall wall to wall run along (blocks the spawn-to-spawn line) ---
	b.runWall(V(2, 24, 48), V(0, 12, 0))
	capped(V(12, 8, 12), V(-25, 4, -20), C.BuildingC, P.AccentB, R)

	-- LONG FREE-STANDING WALLS --------------------------------------------------------
	b.runWall(V(60, 20, 2), V(-90, 10, -45), R)
	b.runWall(V(2, 20, 50), V(-110, 10, 60), R)

	-- OVERLOOK near each spawn (raised platform, ramp up) -------------------------------
	banded(V(30, 10, 30), V(-130, 5, -80), C.BuildingB, P.AccentB, R)
	b.ramp(V(-130, 0, -39), V(0, 0, -1), 26, 10, 12, RAMP, R)
	capped(V(1.5, 4, 12), V(-115.75, 12, -82), COVER, P.AccentA, R) -- low wall on the edge

	-- COVER ---------------------------------------------------------------------------------
	capped(V(8, 6, 8), V(-70, 3, -15), COVER, P.AccentA, R)
	capped(V(10, 7, 10), V(-40, 3.5, -85), C.BuildingC, P.AccentB, R)
	capped(V(10, 26, 10), V(-25, 13, -60), C.BuildingB, P.AccentA, R) -- tall pillar
	capped(V(4, 12, 18), V(-125, 6, 8), C.BuildingB, P.AccentB, R) -- spawn shield
	b.decor(function()
		b.block(V(14, 0.1, 22), V(-148, 0.05, 0), P.PlayerA)
		b.block(V(14, 0.1, 22), V(148, 0.05, 0), P.PlayerB)
	end)

	local spawnHeight = 3.2
	local spawns = {
		CFrame.lookAt(V(-148, spawnHeight, 0), V(0, spawnHeight, 0)),
		CFrame.lookAt(V(148, spawnHeight, 0), V(0, spawnHeight, 0)),
	}
	local dummies = {
		{ Position = V(-30, ROOF, 50), Face = V(1, 0, 0) },
		{ Position = V(130, 10, 80), Face = V(-1, 0, 0) },
		{ Position = V(0, 0, -35), Motion = "Strafe", Amount = 8, Speed = 0.3, Face = V(0, 0, 1) },
		{ Position = V(60, 0, 20), Motion = "Strafe", Amount = 6, Speed = 0.35, Face = V(-1, 0, 0) },
		{ Position = V(-90, 0, 20), Motion = "Strafe", Amount = 6, Speed = 0.3, Face = V(1, 0, 0) },
		{ Position = V(100, 0, -20), Motion = "Bob", Amount = 6, Speed = 0.5, Face = V(-1, 0, 0) },
		{ Position = V(148, 0, 0), Face = V(-1, 0, 0) },
	}
	return spawns, dummies
end

return ArenaQuarry
