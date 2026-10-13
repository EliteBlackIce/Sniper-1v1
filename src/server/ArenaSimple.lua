--[[
	ArenaSimple.lua  (ServerScriptService.Server.ArenaSimple)

	"Simple": a clean, open 1v1 arena in the spirit of ROUNDS. Flat floor,
	a hill in the middle, high bridges on the sides, long walls and a few
	blocks to hide behind. No decoration: every part is a solid shape you
	can stand on, hide behind or wall run on. Mirrored across X = 0 (and mostly Z = 0), so both
	sides are identical.

	Built for flow: few, big shapes and long gentle ramps, so you can
	bunny hop, slide and wall run across the whole map without snagging.

	TOP VIEW (X = long axis, spawns at the far left / right)

	   +---------------------------------------------------------------+
	   |        /=====ramp=====[ BRIDGE ]=====ramp=====\               |
	   |      ======wall======              ======wall======           |
	   | SPAWN<=ramp    |cover|    /[ HILL ]\    |cover|    ramp=>SPAWN |
	   |      ======wall======              ======wall======           |
	   |        \=====ramp=====[ BRIDGE ]=====ramp=====/               |
	   +---------------------------------------------------------------+

	Colours come from Config.Palette (Snow floor, Light walls, Mid blocks,
	AccentA cover, AccentB ramps).
]]

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local P = Config.Palette
local V = Vector3.new

local ArenaSimple = {}

local LENGTH, WIDTH = 220, 140 -- floor size (X, Z)
local WALL_HEIGHT = 34

function ArenaSimple.Build(b)
	local X, Z, XZ = "X", "Z", "XZ"
	local halfL, halfW = LENGTH / 2, WIDTH / 2

	-- FLOOR + BOUNDARY -------------------------------------------------------
	b.block(V(LENGTH + 10, 4, WIDTH + 10), V(0, -2, 0), P.Snow)
	b.block(V(1.2, 0.1, WIDTH - 10), V(0, 0.05, 0), P.Mid) -- centre line
	b.block(V(LENGTH + 10, WALL_HEIGHT, 4), V(0, WALL_HEIGHT / 2, halfW + 2), P.Light, Z)
	b.block(V(4, WALL_HEIGHT, WIDTH + 10), V(halfL + 2, WALL_HEIGHT / 2, 0), P.Light, X)
	b.block(V(LENGTH + 10, 1, 4.6), V(0, WALL_HEIGHT + 0.5, halfW + 2), P.AccentB, Z) -- top trim
	b.block(V(4.6, 1, WIDTH + 10), V(halfL + 2, WALL_HEIGHT + 0.5, 0), P.AccentB, X)

	-- SPAWN DECKS: raised, with a wide ramp down toward the middle ----------------
	b.block(V(18, 6, 30), V(-98, 3, 0), P.Mid, X)
	b.ramp(V(-69, 0, 0), V(-1, 0, 0), 20, 6, 20, P.AccentB, X)

	-- CENTRE HILL: a low mesa with gentle ramps on all four sides (slide over it)
	b.block(V(28, 4, 28), V(0, 2, 0), P.Mid)
	b.ramp(V(-30, 0, 0), V(1, 0, 0), 16, 4, 28, P.AccentB, X)
	b.ramp(V(0, 0, -30), V(0, 0, 1), 16, 4, 28, P.AccentB, Z)
	b.block(V(2, 5, 12), V(0, 6.5, 0), P.AccentA) -- one spine of cover on top

	-- SIDE BRIDGES: long gentle ramps up to a high deck on each side --------------
	b.block(V(36, 12, 10), V(0, 6, 57), P.Light, Z)
	b.ramp(V(-58, 0, 57), V(1, 0, 0), 40, 12, 10, P.AccentB, XZ)
	b.block(V(36.4, 2, 0.8), V(0, 13, 52.4), P.AccentA, Z) -- low lip: cover at the edge

	-- WALL-RUN WALLS: long and tall, lined up with the lanes ----------------------
	b.block(V(40, 16, 2), V(-55, 8, 32), P.Light, XZ)
	b.block(V(40.2, 0.8, 2.2), V(-55, 16.4, 32), P.AccentB, XZ)

	-- A FEW PIECES OF COVER --------------------------------------------------------
	b.block(V(3, 5, 16), V(-50, 2.5, 0), P.AccentA, X) -- breaks the spawn-to-spawn sightline
	b.block(V(8, 8, 8), V(-80, 4, -26), P.Mid, XZ)

	-- Spawns (on the decks, facing the middle)
	local spawnHeight = 6 + 3.2
	local spawns = {
		CFrame.lookAt(V(-100, spawnHeight, 0), V(0, spawnHeight, 0)),
		CFrame.lookAt(V(100, spawnHeight, 0), V(0, spawnHeight, 0)),
	}

	-- Practice dummies for the Playground (Position = the ground under them)
	local dummies = {
		{ Position = V(0, 4, 9), Face = V(-1, 0, 0) },
		{ Position = V(0, 12, 57), Face = V(0, 0, -1) },
		{ Position = V(0, 12, -57), Face = V(0, 0, 1) },
		{ Position = V(40, 0, 0), Motion = "Strafe", Amount = 10, Speed = 0.3, Face = V(-1, 0, 0) },
		{ Position = V(-30, 0, -45), Motion = "Strafe", Amount = 12, Speed = 0.25, Face = V(1, 0, 0) },
		{ Position = V(30, 0, 45), Motion = "Strafe", Amount = 12, Speed = 0.25, Face = V(-1, 0, 0) },
		{ Position = V(-75, 0, 12), Motion = "Bob", Amount = 8, Speed = 0.5, Face = V(1, 0, 0) },
		{ Position = V(100, 6, 0), Face = V(-1, 0, 0) },
	}
	return spawns, dummies
end

return ArenaSimple
