--[[
	ArenaMonolith.lua  (ServerScriptService.Server.ArenaMonolith)

	"Monolith": a brutalist concrete megastructure. Four massive towers
	(44 studs high) stand in pairs on each half, each pair joined by a
	skybridge that crosses the whole map. Long ramps run up to every tower
	from the spawn end and from the middle, and a 100-stud monolith in the
	centre splits the map. Pillboxes, slabs and blocks cover the floor.
	Mirrored across X and Z (floor blocks point-symmetric).

	TOP VIEW (X = long axis, spawns left / right)

	   +-------------------------------------------------------------+
	   |         ~~slab~~                         ~~slab~~            |
	   |   ramp> [TOWER] <ramp      |      ramp> [TOWER] <ramp        |
	   | ~slab~     ||    pillbox   |   pillbox     ||     ~slab~     |
	   | SPAWN shld ||skybridge  [MONOLITH]   skybridge|| shld SPAWN  |
	   | ~slab~     ||    pillbox   |   pillbox     ||     ~slab~     |
	   |   ramp> [TOWER] <ramp      |      ramp> [TOWER] <ramp        |
	   +-------------------------------------------------------------+
]]

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local P = Config.Palette
local V = Vector3.new
local rgb = Color3.fromRGB

local ArenaMonolith = {}

local LENGTH, WIDTH, WALL_H = 600, 420, 120
local TOWER_H = 44

local FLOOR = rgb(150, 150, 146)
local WALL = rgb(176, 176, 172)
local TOWER = rgb(196, 194, 188)
local DARK = rgb(92, 94, 100)
local ORANGE = rgb(240, 116, 44)
local YELLOW = rgb(246, 200, 62)
local RAMP = rgb(222, 128, 74)

function ArenaMonolith.Build(b)
	local X, Z, XZ, R = "X", "Z", "XZ", "R"
	local halfL, halfW = LENGTH / 2, WIDTH / 2

	-- FLOOR + WALLS (dark panel joints, floor lane lines) ----------------------------
	b.shell(LENGTH, WIDTH, WALL_H, FLOOR, WALL, DARK)
	b.decor(function()
		for x = -240, 240, 80 do
			b.block(V(2, WALL_H - 4, 1), V(x, WALL_H / 2, halfW - 0.5), DARK, Z)
		end
		for z = -140, 140, 70 do
			b.block(V(1, WALL_H - 4, 2), V(halfL - 0.5, WALL_H / 2, z), DARK, X)
		end
		b.block(V(LENGTH, 4, 1), V(0, 70, halfW - 1), ORANGE, Z)
		b.block(V(1, 4, WIDTH - 4), V(halfL - 1, 70, 0), ORANGE, X)
		b.block(V(LENGTH - 40, 0.2, 2), V(0, 0.1, 82), YELLOW, Z) -- lane lines
	end)

	-- TOWERS (x -172..-108, z 88..152) -----------------------------------------------
	b.block(V(64, TOWER_H, 64), V(-140, TOWER_H / 2, 120), TOWER, XZ)
	b.decor(function()
		b.block(V(64.6, 3, 64.6), V(-140, 22, 120), DARK, XZ) -- window band
		b.block(V(64.6, 2, 64.6), V(-140, TOWER_H - 2, 120), ORANGE, XZ)
	end)
	b.slopeTo(V(-172, TOWER_H, 120), V(1, 0, 0), TOWER_H, 34, RAMP, XZ, 26) -- from the spawn end
	b.slopeTo(V(-108, TOWER_H, 120), V(-1, 0, 0), TOWER_H, 34, RAMP, XZ, 26) -- from the middle
	-- tower-top cover (gaps left for the skybridge and the ramps)
	b.capped(V(12, 6, 4), V(-163, TOWER_H + 3, 90.5), DARK, ORANGE, XZ)
	b.capped(V(12, 6, 4), V(-117, TOWER_H + 3, 90.5), DARK, ORANGE, XZ)
	b.capped(V(22, 12, 14), V(-140, TOWER_H + 6, 140), TOWER, ORANGE, XZ)

	-- SKYBRIDGES across the map, joining each pair of towers ---------------------------
	b.block(V(28, 6, 176), V(-140, TOWER_H - 3, 0), DARK, X) -- z -88..88
	b.capped(V(3, 5, 30), V(-152.5, TOWER_H + 2.5, 30), TOWER, ORANGE, XZ)
	b.capped(V(3, 5, 30), V(-127.5, TOWER_H + 2.5, -50), TOWER, ORANGE, XZ)
	b.decor(function()
		b.block(V(28.6, 1, 176), V(-140, TOWER_H - 6.5, 0), ORANGE, X)
	end)

	-- THE MONOLITH ----------------------------------------------------------------------
	b.block(V(36, 6, 96), V(0, 3, 0), DARK) -- plinth (jumpable step)
	b.block(V(16, 100, 70), V(0, 56, 0), TOWER)
	b.decor(function()
		b.material(b.block(V(16.6, 84, 3), V(0, 54, 0), ORANGE), Enum.Material.Neon)
		b.block(V(17, 2, 71), V(0, 107, 0), DARK)
	end)

	-- FLOOR COVER ----------------------------------------------------------------------
	b.capped(V(30, 16, 30), V(-60, 8, 46), DARK, ORANGE, XZ) -- pillboxes
	b.capped(V(12, 14, 26), V(-100, 7, -14), TOWER, ORANGE, R)
	b.capped(V(24, 10, 12), V(-190, 5, -40), TOWER, YELLOW, R)
	b.capped(V(20, 12, 12), V(-215, 6, 168), DARK, ORANGE, XZ)
	-- concrete slabs to wall run along
	b.runWall(V(80, 40, 6), V(-215, 20, 64), XZ, WALL, ORANGE)
	b.runWall(V(70, 36, 6), V(-60, 18, 172), XZ, WALL, ORANGE)

	-- SPAWN: shield + brutalist canopy (a ceiling for magnetic boots) ------------------------
	b.capped(V(8, 18, 26), V(-234, 9, 0), DARK, ORANGE, X)
	b.block(V(40, 6, 64), V(-280, 33, 0), TOWER, X)
	b.block(V(6, 30, 6), V(-266, 15, 28), DARK, XZ)
	b.decor(function()
		b.block(V(40.6, 1, 64.6), V(-280, 29.5, 0), ORANGE, X)
		b.block(V(24, 0.2, 30), V(-272, 0.1, 0), P.PlayerA)
		b.block(V(24, 0.2, 30), V(272, 0.1, 0), P.PlayerB)
	end)

	local spawnHeight = 3.2
	local spawns = {
		CFrame.lookAt(V(-272, spawnHeight, 0), V(0, spawnHeight, 0)),
		CFrame.lookAt(V(272, spawnHeight, 0), V(0, spawnHeight, 0)),
	}
	local dummies = {
		{ Position = V(-140, TOWER_H, 112), Face = V(1, 0, 0) },
		{ Position = V(140, TOWER_H, -112), Face = V(-1, 0, 0) },
		{ Position = V(-140, TOWER_H, -6), Face = V(1, 0, 0) },
		{ Position = V(0, 6, -40), Face = V(-1, 0, 0) },
		{ Position = V(60, 0, -10), Motion = "Strafe", Amount = 8, Speed = 0.3, Face = V(-1, 0, 0) },
		{ Position = V(-90, 0, 60), Motion = "Strafe", Amount = 8, Speed = 0.25, Face = V(1, 0, 0) },
		{ Position = V(180, 0, -20), Motion = "Bob", Amount = 8, Speed = 0.4, Face = V(-1, 0, 0) },
		{ Position = V(272, 0, 0), Face = V(-1, 0, 0) },
	}
	return spawns, dummies
end

return ArenaMonolith
