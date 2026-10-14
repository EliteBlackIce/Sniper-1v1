--[[
	ArenaZiggurat.lua  (ServerScriptService.Server.ArenaZiggurat)

	"Ziggurat": a big stepped pyramid in the middle of a wide, open floor.
	Three tiers, each with ramps up, and a crown of low walls on top for the
	king of the hill. The corners are open, with big L-shaped walls and a
	raised corner ledge; long walls along the sides to wall run.
	Mirrored across X and Z.

	TOP VIEW (X = long axis)

	   +---------------------------------------------------------+
	   | [ledge]<ramp  L        ======runwall======        L      |
	   |               ^ramp   ____________   ^ramp               |
	   | SPAWN shield   ramp> |  tier 1-3  | <ramp  shield  SPAWN |
	   |               vramp   ¯¯¯¯¯¯¯¯¯¯¯¯   vramp               |
	   | [ledge]<ramp  L        ======runwall======        L      |
	   +---------------------------------------------------------+
]]

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local P = Config.Palette
local C = Config.MapPalette
local V = Vector3.new

local ArenaZiggurat = {}

local LENGTH, WIDTH = 300, 240 -- floor (X, Z)
local WALL_H = 50
local STEP = 8 -- tier height

function ArenaZiggurat.Build(b)
	local X, Z, XZ = "X", "Z", "XZ"
	local halfL, halfW = LENGTH / 2, WIDTH / 2

	local FLOOR = C.Sidewalk
	local WALL = C.BuildingA
	local RAMP = P.AccentB

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
		b.block(V(LENGTH, 1.2, 0.6), V(0, 0.6, halfW - 0.3), C.Trim, Z)
		b.block(V(0.6, 1.2, WIDTH), V(halfL - 0.3, 0.6, 0), C.Trim, X)
	end)

	-- THE ZIGGURAT: three tiers ---------------------------------------------------
	local tiers = {
		{ size = 96, color = C.BuildingC },
		{ size = 60, color = C.Stone },
		{ size = 28, color = C.BuildingC },
	}
	for i, tier in ipairs(tiers) do
		local top = i * STEP
		b.block(V(tier.size, STEP, tier.size), V(0, top - STEP / 2, 0), tier.color)
		b.decor(function()
			b.block(V(tier.size + 0.4, 1, tier.size + 0.4), V(0, top - 0.8, 0), i == 2 and P.AccentA or C.Trim)
		end)
	end
	-- tier 1: ramps from the floor on every side
	b.ramp(V(-72, 0, 0), V(1, 0, 0), 24, STEP, 18, RAMP, X)
	b.ramp(V(-28, 0, 72), V(0, 0, -1), 24, STEP, 14, RAMP, XZ)
	-- tier 2: ramps on the north / south faces
	b.ramp(V(0, STEP, 48), V(0, 0, -1), 18, STEP, 14, P.AccentA, Z)
	-- tier 3: ramps on the east / west faces
	b.ramp(V(-30, 2 * STEP, 0), V(1, 0, 0), 16, STEP, 12, RAMP, X)
	-- crown: low corner walls on the top
	b.block(V(9, 4, 1.5), V(-9.5, 3 * STEP + 2, -13.25), P.Mid, XZ)
	b.block(V(1.5, 4, 6.5), V(-13.25, 3 * STEP + 2, -9.25), P.Mid, XZ)
	b.decor(function()
		b.block(V(9.3, 0.4, 1.8), V(-9.5, 3 * STEP + 4.2, -13.25), P.AccentB, XZ)
		b.block(V(1.8, 0.4, 6.8), V(-13.25, 3 * STEP + 4.2, -9.25), P.AccentB, XZ)
	end)
	-- tier-1 cover (so the ring isn't a shooting gallery)
	capped(V(10, 5, 3), V(-38, STEP + 2.5, 38), P.Mid, P.AccentA, XZ)

	-- CORNERS: L-shaped walls and a raised ledge ---------------------------------------
	capped(V(40, 22, 4), V(-100, 11, -62), P.Light, P.AccentA, XZ)
	capped(V(4, 22, 40), V(-78, 11, -84), P.Light, P.AccentA, XZ)
	b.block(V(30, 12, 30), V(-135, 6, -105), C.BuildingB, XZ)
	b.decor(function()
		b.block(V(30.4, 1, 30.4), V(-135, 11.2, -105), P.AccentA, XZ)
	end)
	b.ramp(V(-94, 0, -105), V(-1, 0, 0), 26, 12, 12, RAMP, XZ)

	-- SIDES: long walls to wall run ------------------------------------------------------
	b.runWall(V(70, 22, 2), V(0, 11, 92), Z)

	-- SPAWN SHIELDS + floor cover ----------------------------------------------------------
	capped(V(4, 14, 16), V(-112, 7, 0), C.BuildingB, P.AccentB, X)
	capped(V(8, 6, 8), V(-90, 3, 30), P.Mid, P.AccentA, XZ)
	b.decor(function()
		b.block(V(14, 0.1, 22), V(-135, 0.05, 0), P.PlayerA)
		b.block(V(14, 0.1, 22), V(135, 0.05, 0), P.PlayerB)
	end)

	local spawnHeight = 3.2
	local spawns = {
		CFrame.lookAt(V(-135, spawnHeight, 0), V(0, spawnHeight, 0)),
		CFrame.lookAt(V(135, spawnHeight, 0), V(0, spawnHeight, 0)),
	}
	local dummies = {
		{ Position = V(0, 3 * STEP, 0), Face = V(-1, 0, 0) },
		{ Position = V(-40, STEP, 20), Face = V(1, 0, 0) },
		{ Position = V(20, 2 * STEP, -20), Face = V(-1, 0, 0) },
		{ Position = V(60, 0, -72), Motion = "Strafe", Amount = 8, Speed = 0.3, Face = V(-1, 0, 0) },
		{ Position = V(-100, 0, 40), Motion = "Strafe", Amount = 6, Speed = 0.35, Face = V(1, 0, 0) },
		{ Position = V(-135, 12, -105), Face = V(1, 0, 0) },
		{ Position = V(110, 0, 40), Motion = "Bob", Amount = 6, Speed = 0.5, Face = V(-1, 0, 0) },
	}
	return spawns, dummies
end

return ArenaZiggurat
