--[[
	ArenaTemple.lua  (ServerScriptService.Server.ArenaTemple)

	"Temple": a jungle clearing around a giant stepped ziggurat. The
	central pyramid has three tiers (14 / 28 / 42 studs) with a shrine on
	top; grand staircases climb it from the north and south, side ramps
	reach its first tier from the east and west. Two smaller ziggurats
	stand on each half, huge trees (leaves stop bullets but not players)
	shade the edges, and broken columns and carved walls give cover.
	Mirrored across X and Z (ruins point-symmetric).

	TOP VIEW (X = long axis, spawns left / right)

	   +--------------------------------------------------------------+
	   | tree  [ZIGGURAT]  tree   ~wall~  stair  ~wall~ tree [ZIGGURAT] tree|
	   |          ^ramp                 [TIER 1]           ^ramp        |
	   | SPAWN gate shield  columns  ramp>[ 2 [3+shrine] ]<ramp  columns  gate SPAWN
	   |          vramp                 [TIER 1]           vramp        |
	   | tree  [ZIGGURAT]  tree   ~wall~  stair  ~wall~ tree [ZIGGURAT] tree|
	   +--------------------------------------------------------------+
]]

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local P = Config.Palette
local V = Vector3.new
local rgb = Color3.fromRGB

local ArenaTemple = {}

local LENGTH, WIDTH, WALL_H = 580, 400, 120
local T1, T2, T3 = 14, 28, 42 -- tier tops of the big ziggurat

local GRASS = rgb(108, 160, 88)
local WALL = rgb(116, 134, 100)
local STONE = rgb(184, 176, 146)
local MOSS = rgb(128, 150, 108)
local DARK = rgb(92, 100, 84)
local GOLD = rgb(234, 190, 72)
local JADE = rgb(58, 172, 140)
local STAIR = rgb(206, 196, 160)
local LEAF = rgb(64, 136, 72)
local LEAF2 = rgb(92, 164, 82)
local TRUNK = rgb(112, 84, 62)
local WATER = rgb(90, 180, 200)

function ArenaTemple.Build(b)
	local X, Z, XZ, R = "X", "Z", "XZ", "R"
	local halfL, halfW = LENGTH / 2, WIDTH / 2

	local function tree(x, z, height)
		b.cylinder(height, 7, V(x, height / 2, z), TRUNK, XZ)
		b.soft(function()
			b.block(V(36, 12, 36), V(x, height + 2, z), LEAF, XZ)
			b.block(V(22, 8, 22), V(x + 4, height + 12, z - 3), LEAF2, XZ)
		end)
	end

	-- FLOOR + MOSSY WALLS + water channels ---------------------------------------------
	b.shell(LENGTH, WIDTH, WALL_H, GRASS, WALL, STONE)
	b.decor(function()
		b.block(V(LENGTH, 6, 1), V(0, 48, halfW - 0.5), DARK, Z)
		b.block(V(1, 6, WIDTH - 2), V(halfL - 0.5, 48, 0), DARK, X)
		b.block(V(LENGTH - 60, 0.2, 12), V(0, 0.1, 180), WATER, Z)
	end)

	-- THE GREAT ZIGGURAT ------------------------------------------------------------------
	b.block(V(150, T1, 160), V(0, T1 / 2, 0), STONE) -- x +-75, z +-80
	b.block(V(110, T2 - T1, 116), V(0, (T1 + T2) / 2, 0), MOSS) -- x +-55, z +-58
	b.block(V(70, T3 - T2, 72), V(0, (T2 + T3) / 2, 0), STONE) -- x +-35, z +-36
	b.decor(function()
		b.block(V(150.6, 2, 160.6), V(0, T1 - 2, 0), GOLD)
		b.block(V(110.6, 2, 116.6), V(0, T2 - 2, 0), JADE)
		b.block(V(70.6, 2, 72.6), V(0, T3 - 2, 0), GOLD)
	end)
	-- grand staircases (north + south) over all three tiers, side ramps onto tier 1
	b.slopeTo(V(0, T3, -36), V(0, 0, 1), T3, 30, STAIR, Z, 24) -- z -130..-36
	b.slopeTo(V(-75, T1, 50), V(1, 0, 0), T1, 24, STAIR, XZ, 24) -- x -106..-75
	-- shrine on top: four pillars and a roof
	b.block(V(5, 16, 5), V(-14, T3 + 8, -14), DARK, XZ)
	b.block(V(40, 4, 40), V(0, T3 + 18, 0), STONE)
	b.decor(function()
		b.block(V(40.6, 1.4, 40.6), V(0, T3 + 20.7, 0), GOLD)
	end)
	b.capped(V(10, 5, 10), V(0, T3 + 2.5, 0), JADE, GOLD) -- altar
	-- tier-edge cover
	b.capped(V(4, 6, 22), V(-52, T2 + 3, -30), STONE, GOLD, XZ)
	b.capped(V(4, 5, 30), V(-72, T1 + 2.5, -15), MOSS, JADE, XZ)

	-- SIDE ZIGGURATS (x -205..-125, z 85..155) ---------------------------------------------
	b.block(V(80, 16, 70), V(-165, 8, 120), STONE, XZ)
	b.block(V(40, 14, 40), V(-180, 23, 130), MOSS, XZ) -- top at 30
	b.decor(function()
		b.block(V(80.6, 2, 70.6), V(-165, 14, 120), GOLD, XZ)
		b.block(V(40.6, 2, 40.6), V(-180, 28, 130), JADE, XZ)
	end)
	b.slopeTo(V(-165, 16, 85), V(0, 0, 1), 16, 26, STAIR, XZ, 24) -- from the field
	b.slopeTo(V(-160, 30, 125), V(-1, 0, 0), 14, 18, STAIR, XZ, 24) -- up to the top
	b.capped(V(16, 6, 4), V(-180, 33, 112), STONE, GOLD, XZ)

	-- SPAWN GATES + SHIELDS ---------------------------------------------------------------------
	b.block(V(10, 40, 10), V(-240, 20, 34), STONE, XZ)
	b.block(V(10, 8, 78), V(-240, 44, 0), MOSS, X)
	b.decor(function()
		b.block(V(10.6, 1.4, 78.6), V(-240, 44, 0), GOLD, X)
	end)
	b.capped(V(8, 18, 24), V(-212, 9, 0), MOSS, GOLD, X)

	-- RUINS (point-symmetric): broken columns, a fallen column, blocks ------------------------
	b.cylinder(30, 10, V(-110, 15, -20), STONE, R)
	b.cylinder(18, 10, V(-128, 9, 52), STONE, R)
	b.cylinder(36, 10, nil, MOSS, R, CFrame.new(-160, 5, -32) * CFrame.Angles(0, math.rad(30), 0))
	b.capped(V(16, 12, 16), V(-120, 6, -60), MOSS, JADE, R)
	b.capped(V(24, 9, 12), V(-196, 4.5, 50), STONE, JADE, R)
	-- carved walls to wall run along
	b.runWall(V(90, 38, 6), V(-70, 19, 116), XZ, STONE, GOLD)

	-- TREES -------------------------------------------------------------------------------------
	tree(-250, 72, 42)
	tree(-100, 152, 46)
	tree(-246, 166, 40)

	b.decor(function()
		b.block(V(24, 0.2, 30), V(-262, 0.1, 0), P.PlayerA)
		b.block(V(24, 0.2, 30), V(262, 0.1, 0), P.PlayerB)
	end)

	local spawnHeight = 3.2
	local spawns = {
		CFrame.lookAt(V(-262, spawnHeight, 0), V(0, spawnHeight, 0)),
		CFrame.lookAt(V(262, spawnHeight, 0), V(0, spawnHeight, 0)),
	}
	local dummies = {
		{ Position = V(0, T3, -26), Face = V(-1, 0, 0) },
		{ Position = V(-65, T1, -70), Face = V(1, 0, 0) },
		{ Position = V(40, T2, 50), Face = V(-1, 0, 0) },
		{ Position = V(180, 30, -130), Face = V(-1, 0, 0) },
		{ Position = V(130, 0, 0), Motion = "Strafe", Amount = 8, Speed = 0.3, Face = V(-1, 0, 0) },
		{ Position = V(-140, 0, -30), Motion = "Strafe", Amount = 8, Speed = 0.25, Face = V(1, 0, 0) },
		{ Position = V(200, 0, 40), Motion = "Bob", Amount = 8, Speed = 0.4, Face = V(-1, 0, 0) },
		{ Position = V(262, 0, 0), Face = V(-1, 0, 0) },
	}
	return spawns, dummies
end

return ArenaTemple
