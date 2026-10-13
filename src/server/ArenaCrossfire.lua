--[[
	ArenaCrossfire.lua  (ServerScriptService.Server.ArenaCrossfire)

	"Crossfire": a compact Rivals-style duel map. Small enough that you find
	each other fast, with three routes between the spawns:

	  NORTH  a covered market hall: close range inside (doorways and an
	         open end), a walkable roof on top (ramp up at each end)
	  MIDDLE a raised plaza with a big centrepiece that blocks the
	         spawn-to-spawn line, low cover around it
	  SOUTH  a container yard: climb the ramp onto a container for height

	Each spawn is a small building with a walkable roof (stairs on both
	sides) so you can hold your end from above. Mirrored across X = 0, so
	both sides are identical; spawns are tinted with the team colours.

	TOP VIEW (X = long axis)

	   +------------------------------------------------------------+
	   |  ramp> [=========== MARKET HALL (roof) ===========] <ramp  |
	   |        |door|             |door|              open end      |
	   | [SPAWN]   wall   pillar   /[PLAZA]\\   pillar   wall  [SPAWN]|
	   |  roof     wall           \\[centre]/            wall    roof |
	   |  ramp> [CONTAINER] crates   low wall   crates [CONTAINER]  |
	   +------------------------------------------------------------+

	Only solid shapes collide; trims and floor markings are decor.
]]

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local P = Config.Palette
local C = Config.MapPalette
local V = Vector3.new

local ArenaCrossfire = {}

local LENGTH, WIDTH = 170, 120 -- floor size (X, Z)
local WALL_HEIGHT = 28

function ArenaCrossfire.Build(b)
	local X, Z, XZ = "X", "Z", "XZ"
	local halfL, halfW = LENGTH / 2, WIDTH / 2

	-- FLOOR + BOUNDARY -------------------------------------------------------
	b.block(V(LENGTH + 10, 4, WIDTH + 10), V(0, -2, 0), C.Sidewalk)
	b.block(V(LENGTH + 10, WALL_HEIGHT, 4), V(0, WALL_HEIGHT / 2, halfW + 2), C.BuildingB, Z)
	b.block(V(4, WALL_HEIGHT, WIDTH + 10), V(halfL + 2, WALL_HEIGHT / 2, 0), C.BuildingB, X)
	b.decor(function()
		b.block(V(LENGTH + 10, 1, 4.6), V(0, WALL_HEIGHT + 0.5, halfW + 2), P.AccentB, Z)
		b.block(V(4.6, 1, WIDTH + 10), V(halfL + 2, WALL_HEIGHT + 0.5, 0), P.AccentB, X)
		b.block(V(LENGTH, 1.2, 0.6), V(0, 0.6, halfW - 0.3), C.Trim, Z) -- skirting
		b.block(V(0.6, 1.2, WIDTH), V(halfL - 0.3, 0.6, 0), C.Trim, X)
		-- lane markings
		b.block(V(1, 0.06, WIDTH - 20), V(0, 0.03, 0), P.AccentB)
		b.block(V(LENGTH - 40, 0.06, 0.6), V(0, 0.03, 30), C.Curb, Z)
	end)

	-- SPAWN BUILDINGS (walkable roof, stairs on both sides) --------------------
	b.block(V(20, 12, 2), V(-74, 6, 15), C.BuildingA, XZ) -- side walls
	b.block(V(2, 12, 2), V(-65, 6, 7.5), C.BuildingA, XZ) -- front pillars
	b.block(V(21, 1.5, 32), V(-74.5, 12.75, 0), C.Roof, X) -- roof
	b.block(V(1, 2.5, 11), V(-64.5, 14.75, 10.5), C.BuildingA, XZ) -- roof cover (gap in the middle)
	b.ramp(V(-62, 0, 18), V(-1, 0, 0), 18, 13.5, 4, P.AccentA, XZ) -- stairs up to the roof
	b.decor(function()
		-- team-coloured floor and roof trim
		b.block(V(19, 0.08, 28), V(-74, 0.04, 0), P.PlayerA)
		b.block(V(19, 0.08, 28), V(74, 0.04, 0), P.PlayerB)
		b.block(V(21.4, 0.6, 32.4), V(-74.5, 13.8, 0), P.AccentB, X)
		b.block(V(0.4, 1.2, 12), V(-64.1, 10.4, 0), P.PlayerA) -- sign over the door
		b.block(V(0.4, 1.2, 12), V(64.1, 10.4, 0), P.PlayerB)
	end)
	b.block(V(4, 4, 4), V(-56, 2, 10), C.Wood, XZ) -- crates outside the door

	-- CENTRE PLAZA ---------------------------------------------------------------
	b.block(V(26, 3, 26), V(0, 1.5, 0), C.Stone)
	b.ramp(V(-21, 0, 0), V(1, 0, 0), 8, 3, 14, C.Stone, X)
	b.ramp(V(0, 0, -21), V(0, 0, 1), 8, 3, 14, C.Stone, Z)
	b.block(V(5, 8, 9), V(0, 7, 0), C.BuildingA) -- centrepiece (blocks the spawn-to-spawn line)
	b.block(V(6, 2.5, 1.5), V(-8, 4.25, 9), P.AccentA, XZ) -- low cover on the plaza
	b.decor(function()
		b.block(V(26.4, 0.4, 26.4), V(0, 3.1, 0), C.Trim)
		b.block(V(5.6, 0.6, 9.6), V(0, 11.2, 0), P.AccentB)
		b.block(V(5.2, 1, 9.2), V(0, 3.5, 0), C.Trim)
	end)

	-- MID COVER --------------------------------------------------------------
	b.block(V(1.5, 4, 10), V(-38, 2, 14), C.BuildingA, XZ) -- low walls
	b.block(V(4, 9, 4), V(-30, 4.5, 0), C.BuildingA, X) -- pillars
	b.decor(function()
		b.block(V(1.9, 0.5, 10.4), V(-38, 4.25, 14), P.AccentB, XZ)
		b.block(V(4.4, 0.6, 4.4), V(-30, 9.3, 0), P.AccentB, X)
	end)

	-- NORTH: MARKET HALL (close range inside, walkable roof) -------------------
	-- south wall with two doorways
	b.block(V(15, 10, 1), V(-22.5, 5, 40.5), C.BuildingA, X)
	b.block(V(18, 10, 1), V(0, 5, 40.5), C.BuildingA)
	b.block(V(6, 3, 1), V(-12, 8.5, 40.5), C.BuildingA, X) -- over the doors
	-- end walls: solid at the front, open at the back
	b.block(V(1, 10, 10), V(-30.5, 5, 45), C.BuildingA, X)
	b.block(V(1, 3, 8), V(-30.5, 8.5, 54), C.BuildingA, X)
	b.block(V(61, 1.5, 18.5), V(0, 10.75, 49.25), C.Roof) -- roof
	b.block(V(8, 2.5, 1), V(-12, 12.75, 40.75), P.AccentA, X) -- cover on the roof edge
	b.ramp(V(-48, 0, 45), V(1, 0, 0), 17, 11.5, 6, P.AccentA, X) -- ramp up to the roof
	b.block(V(4, 4, 4), V(-18, 2, 52), C.Wood, X) -- crates inside
	b.block(V(3, 3, 3), V(-6, 1.5, 47), C.Wood, X)
	b.decor(function()
		b.block(V(61.4, 0.6, 18.9), V(0, 11.8, 49.25), P.AccentB)
		b.block(V(60, 1.2, 1.2), V(0, 9.4, 39.9), P.AccentA) -- awning strip
		for x = -27, 27, 6 do
			b.block(V(0.3, 2, 0.4), V(x, 5.5, 39.8), C.Trim) -- window bars on the wall
		end
	end)

	-- SOUTH: CONTAINER YARD -------------------------------------------------------
	b.block(V(20, 8.5, 8), V(-28, 4.25, -46), C.Awning[2], X) -- container
	b.ramp(V(-52, 0, -46), V(1, 0, 0), 14, 8.5, 6, P.AccentA, X) -- ramp onto it
	b.block(V(4, 4, 4), V(-12, 2, -44), C.Wood, X) -- crates
	b.block(V(3, 3, 3), V(-8, 1.5, -51), C.Wood, X)
	b.block(V(12, 4, 1.5), V(0, 2, -40), C.BuildingA) -- low wall in the middle of the yard
	b.block(V(8, 8.5, 16), V(-60, 4.25, -46), C.Awning[1], X) -- container by the spawn
	b.decor(function()
		for k = -4, 4 do
			b.block(V(0.4, 7.6, 8.1), V(-28 + k * 2.2, 4.25, -46), C.Dark:Lerp(C.Awning[2], 0.6), X) -- ribs
		end
		for k = -3, 3 do
			b.block(V(8.1, 7.6, 0.4), V(-60, 4.25, -46 + k * 2.2), C.Dark:Lerp(C.Awning[1], 0.6), X)
		end
		b.block(V(20.1, 0.5, 8.1), V(-28, 8.3, -46), C.Trim, X)
		b.block(V(8.1, 0.5, 16.1), V(-60, 8.3, -46), C.Trim, X)
		b.block(V(12.4, 0.5, 1.9), V(0, 4.25, -40), P.AccentB)
	end)

	-- Spawns (inside the spawn buildings, facing the middle)
	local spawnHeight = 3.2
	local spawns = {
		CFrame.lookAt(V(-76, spawnHeight, 0), V(0, spawnHeight, 0)),
		CFrame.lookAt(V(76, spawnHeight, 0), V(0, spawnHeight, 0)),
	}

	-- Practice dummies for the Playground (Position = the ground under them)
	local dummies = {
		{ Position = V(0, 3, 8), Face = V(-1, 0, 0) },
		{ Position = V(-74, 13.5, 4), Face = V(1, 0, 0) },
		{ Position = V(12, 11.5, 50), Face = V(0, 0, -1) },
		{ Position = V(-28, 8.5, -46), Face = V(1, 0, 0) },
		{ Position = V(10, 0, 48), Face = V(-1, 0, 0) },
		{ Position = V(-45, 0, 25), Motion = "Strafe", Amount = 8, Speed = 0.3, Face = V(1, 0, 0) },
		{ Position = V(45, 0, -25), Motion = "Strafe", Amount = 8, Speed = 0.3, Face = V(-1, 0, 0) },
		{ Position = V(20, 0, -30), Motion = "Bob", Amount = 6, Speed = 0.5, Face = V(-1, 0, 0) },
	}
	return spawns, dummies
end

return ArenaCrossfire
