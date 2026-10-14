--[[
	ArenaPillars.lua  (ServerScriptService.Server.ArenaPillars)

	"Pillars": a huge open floor with a grid of giant square pillars. The two
	outer rows are walkable platforms (ramps up at the corners and in the
	middle) with bridges between some of their tops; the middle row is tall
	pillars to hide behind (and grapple to). Wide lanes between the rows for
	sliding and bunny hopping, plus long walls to wall run.
	Point-symmetric bridges, everything else mirrored across X and Z.

	TOP VIEW (X = long axis)

	   +--------------------------------------------------------+
	   | ramp>[P]===[P]    [P]===[P]    [P]       <ramp          |
	   |        runwall   ^ramp          runwall                 |
	   | SPAWN | (low)    [T]     [T]     [T]     (low) | SPAWN  |
	   |        runwall   vramp          runwall                 |
	   | ramp>[P]    [P]===[P]    [P]===[P]       <ramp          |
	   +--------------------------------------------------------+
	   [P] platform pillar   [T] tall pillar   === bridge
]]

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local P = Config.Palette
local C = Config.MapPalette
local V = Vector3.new

local ArenaPillars = {}

local LENGTH, WIDTH = 320, 230 -- floor (X, Z)
local WALL_H = 50
local PLAT_H = 18 -- walkable pillar tops
local TALL_H = 44
local SIZE = 20 -- pillar width
local ROW_Z = 65

function ArenaPillars.Build(b)
	local X, Z, XZ, R = "X", "Z", "XZ", "R"
	local halfL, halfW = LENGTH / 2, WIDTH / 2

	local FLOOR = C.Concrete
	local WALL = C.BuildingB
	local PLAT = P.Light
	local TALL = C.BuildingD
	local RAMP = P.AccentB

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

	-- a platform pillar with a band just under its (walkable) top
	local function platform(pos, m)
		b.block(V(SIZE, PLAT_H, SIZE), V(pos.X, PLAT_H / 2, pos.Z), PLAT, m)
		b.decor(function()
			b.block(V(SIZE + 0.4, 1, SIZE + 0.4), V(pos.X, PLAT_H - 0.8, pos.Z), P.AccentA, m)
			b.block(V(SIZE + 0.3, 1, SIZE + 0.3), V(pos.X, 0.5, pos.Z), C.Trim, m)
		end)
	end

	-- a tall pillar with a cap
	local function tall(pos, height, m)
		b.block(V(SIZE, height, SIZE), V(pos.X, height / 2, pos.Z), TALL, m)
		b.decor(function()
			b.block(V(SIZE + 0.4, 1, SIZE + 0.4), V(pos.X, height + 0.5, pos.Z), P.AccentB, m)
			b.block(V(SIZE + 0.3, 1, SIZE + 0.3), V(pos.X, 0.5, pos.Z), C.Trim, m)
		end)
	end

	-- OUTER ROWS: platforms ---------------------------------------------------------
	platform(V(-100, 0, ROW_Z), XZ)
	platform(V(-50, 0, ROW_Z), XZ)
	platform(V(0, 0, ROW_Z), Z)

	-- MIDDLE ROW: tall pillars + a low one in front of each spawn ---------------------
	tall(V(0, 0, 0), TALL_H)
	tall(V(-50, 0, 0), TALL_H, X)
	b.block(V(SIZE, 6, SIZE), V(-100, 3, 0), C.BuildingB, X)
	b.decor(function()
		b.block(V(SIZE + 0.4, 0.8, SIZE + 0.4), V(-100, 5.4, 0), P.AccentA, X)
	end)

	-- BRIDGES between some platform tops (point-symmetric, so both sides match):
	-- north row: -100 <-> -50 and 0 <-> 50; south row: the rotated copies
	local function bridge(x)
		b.block(V(30, 2, 8), V(x, PLAT_H - 1, ROW_Z), C.Concrete, R)
		b.block(V(30, 2.5, 0.8), V(x, PLAT_H + 1.25, ROW_Z + 3.6), C.Trim, R) -- low edges
		b.block(V(30, 2.5, 0.8), V(x, PLAT_H + 1.25, ROW_Z - 3.6), C.Trim, R)
	end
	bridge(-75)
	bridge(25)

	-- RAMPS ----------------------------------------------------------------------------
	b.ramp(V(-146, 0, ROW_Z), V(1, 0, 0), 36, PLAT_H, 12, RAMP, XZ) -- spawn side -> corner platforms
	b.ramp(V(0, 0, 25), V(0, 0, 1), 30, PLAT_H, 12, RAMP, Z) -- middle lane -> centre platforms

	-- WALL-RUN WALLS ---------------------------------------------------------------------
	b.runWall(V(36, 16, 2), V(-75, 8, 32), XZ) -- between the rows
	b.runWall(V(40, 20, 2), V(-25, 10, 100), XZ) -- outer lanes

	-- SPAWN SHIELD -------------------------------------------------------------------------
	b.block(V(3, 12, 14), V(-126, 6, 0), C.BuildingB, X)
	b.decor(function()
		b.block(V(3.4, 0.6, 14.4), V(-126, 12.3, 0), P.AccentB, X)
		b.block(V(14, 0.1, 22), V(-147, 0.05, 0), P.PlayerA)
		b.block(V(14, 0.1, 22), V(147, 0.05, 0), P.PlayerB)
	end)

	local spawnHeight = 3.2
	local spawns = {
		CFrame.lookAt(V(-147, spawnHeight, 0), V(0, spawnHeight, 0)),
		CFrame.lookAt(V(147, spawnHeight, 0), V(0, spawnHeight, 0)),
	}
	local dummies = {
		{ Position = V(0, PLAT_H, ROW_Z), Face = V(0, 0, -1) },
		{ Position = V(-100, PLAT_H, -ROW_Z), Face = V(1, 0, 0) },
		{ Position = V(-75, PLAT_H, ROW_Z), Face = V(1, 0, 0) },
		{ Position = V(0, 0, -30), Motion = "Strafe", Amount = 8, Speed = 0.3, Face = V(-1, 0, 0) },
		{ Position = V(75, 0, -45), Motion = "Strafe", Amount = 6, Speed = 0.35, Face = V(-1, 0, 0) },
		{ Position = V(100, 6, 0), Face = V(-1, 0, 0) },
		{ Position = V(130, 0, 40), Motion = "Bob", Amount = 6, Speed = 0.5, Face = V(-1, 0, 0) },
	}
	return spawns, dummies
end

return ArenaPillars
