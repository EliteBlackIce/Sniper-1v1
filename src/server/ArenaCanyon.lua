--[[
	ArenaCanyon.lua  (ServerScriptService.Server.ArenaCanyon)

	"Canyon": two long raised ridges run down both sides of the map with a
	wide trench between them. Big, simple shapes: ramps up onto the ridges
	from each spawn and from the trench, one bridge across the middle, a few
	large cover blocks in the trench and long walls to wall run along.
	Mirrored across X and Z (trench cover is point-symmetric).

	TOP VIEW (X = long axis, spawns left / right)

	   +------------------------------------------------------------+
	   | ramp> [=============== RIDGE (runwall on top) =========] <ramp|
	   |          ramp^            |bridge|           ^ramp          |
	   | SPAWN  shield  runwall  cover  [ ]  cover  runwall shield SPAWN|
	   |          rampv            |bridge|           vramp          |
	   | ramp> [=============== RIDGE ===========================] <ramp|
	   +------------------------------------------------------------+
]]

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local P = Config.Palette
local C = Config.MapPalette
local V = Vector3.new

local ArenaCanyon = {}

local LENGTH, WIDTH = 340, 220 -- floor (X, Z)
local WALL_H = 50
local RIDGE_H = 14

function ArenaCanyon.Build(b)
	local X, Z, XZ, R = "X", "Z", "XZ", "R"
	local halfL, halfW = LENGTH / 2, WIDTH / 2

	local FLOOR = C.Stone
	local WALL = C.BuildingA
	local RIDGE = C.BuildingC
	local COVER = P.Mid
	local RAMP = P.AccentB

	-- a block with a coloured cap on top (decor)
	local function capped(size, pos, color, cap, m)
		b.block(size, pos, color, m)
		b.decor(function()
			b.block(V(size.X + 0.3, 0.6, size.Z + 0.3), pos + V(0, size.Y / 2 + 0.3, 0), cap, m)
		end)
	end

	-- FLOOR + OUTER WALLS ------------------------------------------------------
	b.block(V(LENGTH + 10, 4, WIDTH + 10), V(0, -2, 0), FLOOR)
	b.block(V(LENGTH + 10, WALL_H, 4), V(0, WALL_H / 2, halfW + 2), WALL, Z)
	b.block(V(4, WALL_H, WIDTH + 10), V(halfL + 2, WALL_H / 2, 0), WALL, X)
	b.decor(function()
		b.block(V(LENGTH + 10, 1, 4.6), V(0, WALL_H + 0.5, halfW + 2), P.AccentB, Z)
		b.block(V(4.6, 1, WIDTH + 10), V(halfL + 2, WALL_H + 0.5, 0), P.AccentB, X)
		b.block(V(0.6, 1.2, WIDTH), V(halfL - 0.3, 0.6, 0), C.Trim, X) -- skirting at the spawn ends
	end)

	-- RIDGES (one along each side wall) -----------------------------------------
	b.block(V(220, RIDGE_H, 66), V(0, RIDGE_H / 2, 77), RIDGE, Z) -- x -110..110, z 44..110
	b.decor(function()
		b.block(V(220.4, 1, 0.6), V(0, RIDGE_H - 0.8, 43.9), C.Trim, Z) -- edge band
		b.block(V(0.6, 1, 66.4), V(-110.1, RIDGE_H - 0.8, 77), C.Trim, XZ)
	end)
	-- ramps up from each spawn onto the ridge ends
	b.ramp(V(-140, 0, 77), V(1, 0, 0), 30, RIDGE_H, 20, RAMP, XZ)
	-- ramps up from the trench onto the ridges
	b.ramp(V(-40, 0, 14), V(0, 0, 1), 30, RIDGE_H, 14, P.AccentA, XZ)

	-- ridge-top cover and a long wall to run along
	capped(V(6, 8, 22), V(-70, RIDGE_H + 4, 78), COVER, P.AccentA, XZ)
	capped(V(28, 6, 3), V(-30, RIDGE_H + 3, 52), COVER, P.AccentA, XZ)
	b.runWall(V(80, 16, 2), V(0, RIDGE_H + 8, 96), Z)

	-- BRIDGE across the middle of the trench -------------------------------------
	b.block(V(18, 2, 88), V(0, RIDGE_H - 1, 0), C.Concrete) -- top flush with the ridges
	b.block(V(1, 3, 36), V(-8.5, RIDGE_H + 1.5, 0), COVER, X) -- half walls on the bridge
	b.block(V(6, RIDGE_H - 2, 6), V(0, (RIDGE_H - 2) / 2, 38), C.Trim, Z) -- supports
	b.decor(function()
		b.block(V(1.4, 0.4, 36.4), V(-8.5, RIDGE_H + 3.2, 0), P.AccentB, X)
	end)

	-- TRENCH COVER (big blocks, point-symmetric) ---------------------------------
	capped(V(10, 10, 20), V(-16, 5, 6), C.BuildingB, P.AccentB, R) -- blocks the spawn-to-spawn line
	capped(V(14, 8, 10), V(-60, 4, -24), COVER, P.AccentA, R)
	capped(V(8, 12, 8), V(-95, 6, 22), C.BuildingB, P.AccentB, R)
	b.runWall(V(44, 18, 2), V(-70, 9, 0), X) -- long wall down the trench

	-- SPAWN ENDS ----------------------------------------------------------------
	capped(V(4, 12, 16), V(-122, 6, 0), C.BuildingB, P.AccentB, X) -- spawn shield
	capped(V(12, 7, 12), V(-150, 3.5, -30), COVER, P.AccentA, R)
	b.decor(function()
		b.block(V(14, 0.1, 22), V(-152, 0.05, 0), P.PlayerA)
		b.block(V(14, 0.1, 22), V(152, 0.05, 0), P.PlayerB)
	end)

	local spawnHeight = 3.2
	local spawns = {
		CFrame.lookAt(V(-152, spawnHeight, 0), V(0, spawnHeight, 0)),
		CFrame.lookAt(V(152, spawnHeight, 0), V(0, spawnHeight, 0)),
	}
	local dummies = {
		{ Position = V(0, RIDGE_H, -12), Face = V(-1, 0, 0) },
		{ Position = V(-60, RIDGE_H, 70), Face = V(1, 0, 0) },
		{ Position = V(30, RIDGE_H, -80), Face = V(-1, 0, 0) },
		{ Position = V(60, 0, -10), Motion = "Strafe", Amount = 6, Speed = 0.35, Face = V(-1, 0, 0) },
		{ Position = V(-30, 0, -6), Motion = "Strafe", Amount = 6, Speed = 0.3, Face = V(1, 0, 0) },
		{ Position = V(100, 0, 6), Motion = "Bob", Amount = 6, Speed = 0.5, Face = V(-1, 0, 0) },
		{ Position = V(152, 0, 0), Face = V(-1, 0, 0) },
	}
	return spawns, dummies
end

return ArenaCanyon
