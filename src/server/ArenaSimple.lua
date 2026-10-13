--[[
	ArenaSimple.lua  (ServerScriptService.Server.ArenaSimple)

	"Simple": a clean 1v1 arena in the spirit of ROUNDS. Flat floor, a few
	ramps, walls and blocks to hide behind, and some high ground. No
	decoration: every part is a solid shape you can stand on, hide behind
	or wall run on. Mirrored across X = 0 (and mostly Z = 0), so both
	sides are identical.

	TOP VIEW (X = long axis, spawns at the far left / right)

	   +-----------------------------------------------------------------+
	   |   [platform]=ramp=>          ||          <=ramp=[platform]      |
	   |        []       ====wall====    ====wall====       []           |
	   | SPAWN<=ramp   []         =ramp=>[TOWER]<=ramp=         []  ramp=>SPAWN
	   |        []       ====wall====    ====wall====       []           |
	   |   [platform]=ramp=>          ||          <=ramp=[platform]      |
	   +-----------------------------------------------------------------+

	Colours come from Config.Palette (Snow floor, Light walls, Mid blocks,
	AccentA cover, AccentB ramps).
]]

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local P = Config.Palette
local V = Vector3.new

local ArenaSimple = {}

local LENGTH, WIDTH = 230, 150 -- floor size (X, Z)
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

	-- SPAWN DECKS: raised, with a ramp down toward the middle --------------------
	b.block(V(20, 6, 34), V(-100, 3, 0), P.Mid, X)
	b.ramp(V(-70, 0, 0), V(-1, 0, 0), 20, 6, 14, P.AccentB, X)
	b.block(V(2, 3.5, 10), V(-91, 7.75, -12), P.AccentA, XZ) -- low cover at the deck edge

	-- CENTRE TOWER: high ground with ramps up from both sides --------------------
	b.block(V(18, 10, 22), V(0, 5, 0), P.Mid)
	b.ramp(V(-29, 0, 0), V(1, 0, 0), 20, 10, 10, P.AccentB, X)
	b.block(V(1.6, 4, 8), V(0, 12, 0), P.AccentA) -- cover on top
	b.block(V(4, 2.5, 4), V(-6, 11.25, -9), P.AccentA, XZ)

	-- MID WALLS: tall walls to hide behind and wall run along ---------------------
	b.block(V(34, 14, 2), V(-38, 7, 24), P.Light, XZ)
	b.block(V(34.2, 0.8, 2.2), V(-38, 14.4, 24), P.AccentB, XZ)

	-- SIDE PLATFORMS: second high ground, ramp toward the middle ------------------
	b.block(V(24, 8, 18), V(-48, 4, 52), P.Light, XZ)
	b.ramp(V(-16, 0, 52), V(-1, 0, 0), 20, 8, 8, P.AccentB, XZ)
	b.block(V(8, 3, 2), V(-50, 9.5, 44), P.AccentA, XZ) -- cover on the platform edge

	-- COVER BLOCKS ---------------------------------------------------------------
	b.block(V(6, 6, 6), V(-72, 3, 26), P.Mid, XZ)
	b.block(V(8, 4, 4), V(-62, 2, 9), P.AccentA, XZ) -- low cover beside the spawn ramp
	b.block(V(4, 9, 10), V(-20, 4.5, 38), P.Mid, XZ)
	b.block(V(5, 12, 5), V(-80, 6, 50), P.Mid, XZ) -- pillars
	b.block(V(10, 5, 3), V(-18, 2.5, 64), P.AccentA, XZ)
	b.block(V(3, 6, 12), V(-48, 3, 0), P.AccentA, X) -- in the middle lane
	-- stacked crates: step up onto the side platform from behind
	b.block(V(6, 4, 6), V(-63, 2, 62), P.AccentA, XZ)

	-- Spawns (on the decks, facing the middle)
	local spawnHeight = 6 + 3.2
	local spawns = {
		CFrame.lookAt(V(-102, spawnHeight, 0), V(0, spawnHeight, 0)),
		CFrame.lookAt(V(102, spawnHeight, 0), V(0, spawnHeight, 0)),
	}

	-- Practice dummies for the Playground (Position = the ground under them)
	local dummies = {
		{ Position = V(0, 10, 8), Face = V(-1, 0, 0) },
		{ Position = V(-48, 8, 52), Face = V(1, 0, 0) },
		{ Position = V(48, 8, -52), Face = V(-1, 0, 0) },
		{ Position = V(30, 0, 0), Motion = "Strafe", Amount = 10, Speed = 0.3, Face = V(-1, 0, 0) },
		{ Position = V(-60, 0, -38), Motion = "Strafe", Amount = 12, Speed = 0.25, Face = V(1, 0, 0) },
		{ Position = V(60, 0, 38), Motion = "Strafe", Amount = 12, Speed = 0.25, Face = V(-1, 0, 0) },
		{ Position = V(0, 0, 45), Motion = "Bob", Amount = 8, Speed = 0.5, Face = V(0, 0, -1) },
		{ Position = V(100, 6, 0), Face = V(-1, 0, 0) },
	}
	return spawns, dummies
end

return ArenaSimple
