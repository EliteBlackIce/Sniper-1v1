--[[
	ArenaBridges.lua  (ServerScriptService.Server.ArenaBridges)

	"Bridges": two raised plateaus (one per spawn) joined by three wide
	bridges that cross a low pit. Fight across the bridges for the long
	sightlines, or drop into the pit and run underneath them; ramps lead
	back up to the plateaus. Mirrored across X and Z (pit cover is
	point-symmetric).

	TOP VIEW (X = long axis)

	   +----------------------------------------------------------+
	   |  PLATEAU  [====== side bridge (wall on it) ======] PLATEAU|
	   |  block  <ramp     pit: runwall, cover       ramp>  block  |
	   |  SPAWN shield [======= centre bridge =======] shield SPAWN|
	   |  block  <ramp     pit: runwall, cover       ramp>  block  |
	   |           [====== side bridge (wall on it) ======]        |
	   +----------------------------------------------------------+
]]

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local P = Config.Palette
local C = Config.MapPalette
local V = Vector3.new

local ArenaBridges = {}

local LENGTH, WIDTH = 330, 230 -- floor (X, Z)
local WALL_H = 50
local TOP = 16 -- plateau + bridge height
local PIT_X = 80 -- the pit spans x = -80..80

function ArenaBridges.Build(b)
	local X, Z, XZ, R = "X", "Z", "XZ", "R"
	local halfL, halfW = LENGTH / 2, WIDTH / 2

	local FLOOR = C.Concrete
	local WALL = C.BuildingA
	local PLATEAU = C.BuildingB
	local BRIDGE = P.Light
	local COVER = P.Mid
	local RAMP = P.AccentB

	local function capped(size, pos, color, cap, m)
		b.block(size, pos, color, m)
		b.decor(function()
			b.block(V(size.X + 0.3, 0.6, size.Z + 0.3), pos + V(0, size.Y / 2 + 0.3, 0), cap, m)
		end)
	end

	-- FLOOR (the pit) + OUTER WALLS ------------------------------------------------
	b.block(V(LENGTH + 10, 4, WIDTH + 10), V(0, -2, 0), FLOOR)
	b.block(V(LENGTH + 10, WALL_H, 4), V(0, WALL_H / 2, halfW + 2), WALL, Z)
	b.block(V(4, WALL_H, WIDTH + 10), V(halfL + 2, WALL_H / 2, 0), WALL, X)
	b.decor(function()
		b.block(V(LENGTH + 10, 1, 4.6), V(0, WALL_H + 0.5, halfW + 2), P.AccentA, Z)
		b.block(V(4.6, 1, WIDTH + 10), V(halfL + 2, WALL_H + 0.5, 0), P.AccentA, X)
		b.block(V(2 * PIT_X, 1.2, 0.6), V(0, 0.6, halfW - 0.3), C.Trim, Z) -- pit skirting
	end)

	-- PLATEAUS -------------------------------------------------------------------
	local plateauLen = halfL - PIT_X
	b.block(V(plateauLen, TOP, WIDTH), V(-(PIT_X + plateauLen / 2), TOP / 2, 0), PLATEAU, X)
	b.decor(function()
		b.block(V(0.6, 1, WIDTH), V(-(PIT_X - 0.1), TOP - 0.8, 0), P.AccentA, X) -- edge band
	end)
	-- ramps from the pit up to the plateau (between the bridges)
	b.ramp(V(-(PIT_X - 34), 0, 38), V(-1, 0, 0), 34, TOP, 16, RAMP, XZ)

	-- BRIDGES (top flush with the plateaus) --------------------------------------
	local span = 2 * PIT_X
	b.block(V(span, 2, 24), V(0, TOP - 1, 0), BRIDGE) -- centre bridge
	b.block(V(span, 2, 16), V(0, TOP - 1, 75), BRIDGE, Z) -- side bridges
	b.block(V(6, TOP - 2, 6), V(0, (TOP - 2) / 2, 75), C.Trim, Z) -- supports
	b.block(V(6, TOP - 2, 6), V(-45, (TOP - 2) / 2, 0), C.Trim, X)
	b.decor(function()
		b.block(V(span, 0.6, 24.4), V(0, TOP - 1.4, 0), P.AccentB)
		b.block(V(span, 0.6, 16.4), V(0, TOP - 1.4, 75), P.AccentB, Z)
	end)
	-- centre bridge: a block in the middle (no spawn-to-spawn shots) + low rails
	capped(V(6, 8, 10), V(0, TOP + 4, 0), C.BuildingC, P.AccentA)
	b.block(V(30, 3, 1), V(-40, TOP + 1.5, 11.5), COVER, XZ)
	-- side bridges: a long wall along the outer edge to run on, plus cover
	b.runWall(V(60, 12, 1.5), V(0, TOP + 6, 82.25), Z)
	capped(V(4, 6, 8), V(-40, TOP + 3, 73), COVER, P.AccentA, XZ)

	-- THE PIT ------------------------------------------------------------------------
	b.runWall(V(50, 12, 2), V(0, 6, 50), Z)
	capped(V(10, 10, 16), V(-25, 5, 34), COVER, P.AccentA, R)
	capped(V(8, 8, 8), V(-20, 4, -4), C.BuildingC, P.AccentB, R) -- under the centre bridge
	capped(V(14, 8, 14), V(-40, 4, 100), COVER, P.AccentA, R)

	-- PLATEAU COVER ---------------------------------------------------------------------
	capped(V(4, 14, 22), V(-102, TOP + 7, 0), C.BuildingC, P.AccentB, X) -- spawn shield
	capped(V(24, 16, 30), V(-130, TOP + 8, 70), C.BuildingC, P.AccentB, XZ) -- big blocks
	capped(V(8, 5, 8), V(-92, TOP + 2.5, 52), COVER, P.AccentA, XZ)
	b.runWall(V(40, 16, 2), V(-120, TOP + 8, 40), XZ)
	b.decor(function()
		b.block(V(14, 0.1, 22), V(-150, TOP + 0.05, 0), P.PlayerA)
		b.block(V(14, 0.1, 22), V(150, TOP + 0.05, 0), P.PlayerB)
	end)

	local spawnHeight = TOP + 3.2
	local spawns = {
		CFrame.lookAt(V(-150, spawnHeight, 0), V(0, spawnHeight, 0)),
		CFrame.lookAt(V(150, spawnHeight, 0), V(0, spawnHeight, 0)),
	}
	local dummies = {
		{ Position = V(-10, TOP, 0), Face = V(-1, 0, 0) },
		{ Position = V(-55, TOP, 75), Face = V(1, 0, 0) },
		{ Position = V(0, 0, 4), Motion = "Strafe", Amount = 6, Speed = 0.3, Face = V(-1, 0, 0) },
		{ Position = V(-60, 0, 62), Motion = "Strafe", Amount = 6, Speed = 0.35, Face = V(1, 0, 0) },
		{ Position = V(40, 0, -60), Motion = "Bob", Amount = 6, Speed = 0.5, Face = V(-1, 0, 0) },
		{ Position = V(100, TOP, -70), Face = V(-1, 0, 0) },
		{ Position = V(150, TOP, 0), Face = V(-1, 0, 0) },
	}
	return spawns, dummies
end

return ArenaBridges
