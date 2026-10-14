--[[
	ArenaMesa.lua  (ServerScriptService.Server.ArenaMesa)

	"Mesa": a sun-baked sandstone mega-canyon. Two huge mesas (36 studs
	high) line both sides of a wide canyon floor; a natural stone arch
	bridges them over a giant hoodoo in the middle. Long ramps climb onto
	the mesas from each spawn end and from bastions in the canyon, and a
	second tier on each mesa gives the highest sniper perch. Built big:
	players are tiny next to the cliffs. Mirrored (boulders point-symmetric).

	TOP VIEW (X = long axis, spawns left / right)

	   +-----------------------------------------------------------------+
	   | ramp>[======== MESA (36) ==== [tier 50] ==== MESA ========]<ramp |
	   |         ramp> [bastion]         |arch|        [bastion] <ramp   |
	   | SPAWN shield  spires boulders  slab |HOODOO| slab boulders shield SPAWN
	   |         ramp> [bastion]         |arch|        [bastion] <ramp   |
	   | ramp>[======== MESA (36) ==== [tier 50] ==== MESA ========]<ramp |
	   +-----------------------------------------------------------------+
]]

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local P = Config.Palette
local V = Vector3.new
local rgb = Color3.fromRGB

local ArenaMesa = {}

local LENGTH, WIDTH, WALL_H = 620, 380, 120
local MESA_H, TIER_H = 36, 50

local SAND = rgb(232, 202, 156)
local CLIFF = rgb(206, 128, 88)
local CLIFF_DARK = rgb(172, 98, 68)
local ROCK = rgb(224, 164, 112)
local CREAM = rgb(248, 230, 196)
local TEAL = rgb(48, 172, 162)
local RAMP = rgb(240, 186, 98)

function ArenaMesa.Build(b)
	local X, Z, XZ, R = "X", "Z", "XZ", "R"
	local halfL, halfW = LENGTH / 2, WIDTH / 2

	-- a block turned around Y (degrees) with a decorative cap
	local function rock(size, pos, yaw, color, cap, m)
		local cf = CFrame.new(pos) * CFrame.Angles(0, math.rad(yaw), 0)
		b.part(size, cf, color, m)
		b.decor(function()
			b.part(V(size.X + 0.6, 1, size.Z + 0.6), cf * CFrame.new(0, size.Y / 2 + 0.5, 0), cap, m)
		end)
	end

	-- FLOOR + CLIFF WALLS (with strata bands) ---------------------------------
	b.shell(LENGTH, WIDTH, WALL_H, SAND, CLIFF, CREAM)
	b.decor(function()
		for _, y in ipairs({ 44, 86 }) do
			b.block(V(LENGTH, 5, 1), V(0, y, halfW - 0.5), CLIFF_DARK, Z)
			b.block(V(1, 5, WIDTH - 2), V(halfL - 0.5, y, 0), CLIFF_DARK, X)
		end
	end)

	-- MESAS (x -200..200, z 90..190) + second tier --------------------------------
	b.block(V(400, MESA_H, 100), V(0, MESA_H / 2, 140), CLIFF, Z)
	b.block(V(160, TIER_H - MESA_H, 50), V(0, (MESA_H + TIER_H) / 2, 165), CLIFF_DARK, Z) -- x -80..80, z 140..190
	b.decor(function()
		b.block(V(401, 3, 1), V(0, MESA_H - 3, 89.6), CREAM, Z) -- edge band
		b.block(V(1, 3, 100), V(200.4, MESA_H - 3, 140), CREAM, XZ)
		b.block(V(161, 2, 1), V(0, TIER_H - 2, 139.6), TEAL, Z)
	end)
	-- ramps onto the mesa ends (from the spawn end) and onto the tier
	b.slopeTo(V(-200, MESA_H, 140), V(1, 0, 0), MESA_H, 40, RAMP, XZ, 22) -- x -289..-200
	b.slopeTo(V(-80, TIER_H, 165), V(1, 0, 0), TIER_H - MESA_H, 30, RAMP, XZ, 22)

	-- BASTIONS: ramp along the mesa face up to a landing that juts into the canyon
	b.slope(V(-170, 0, 74), V(1, 0, 0), MESA_H, 32, RAMP, XZ, 22) -- x -170..-81
	b.block(V(40, MESA_H, 32), V(-61, MESA_H / 2, 74), CLIFF, XZ) -- x -81..-41, z 58..90
	b.decor(function()
		b.block(V(40.6, 3, 1), V(-61, MESA_H - 3, 57.6), CREAM, XZ)
	end)
	rock(V(16, 6, 4), V(-61, MESA_H + 3, 62), 0, ROCK, TEAL, XZ) -- bastion lip

	-- MESA-TOP COVER: crenels along the rim, boulders, tier parapet ------------------
	for _, x in ipairs({ -175, -128 }) do
		rock(V(18, 7, 5), V(x, MESA_H + 3.5, 93), 0, ROCK, TEAL, XZ)
	end
	rock(V(12, 7, 5), V(-30, MESA_H + 3.5, 93), 0, ROCK, TEAL, XZ)
	rock(V(26, 16, 22), V(-145, MESA_H + 8, 140), 18, ROCK, CREAM, XZ)
	rock(V(30, 5, 4), V(-45, TIER_H + 2.5, 143), 0, ROCK, TEAL, XZ)

	-- THE ARCH + HOODOO in the middle ----------------------------------------------
	b.block(V(26, 28, 26), V(0, 14, 0), CLIFF_DARK) -- hoodoo (blocks spawn-to-spawn shots)
	b.block(V(44, 8, 180), V(0, MESA_H - 4, 0), CLIFF) -- arch deck, flush with the mesas
	b.decor(function()
		b.block(V(44.6, 2, 180), V(0, MESA_H - 9, 0), CREAM)
		b.block(V(26.6, 2, 26.6), V(0, 4, 0), CREAM)
	end)
	rock(V(3, 5, 26), V(-20.5, MESA_H + 2.5, 30), 0, ROCK, TEAL, XZ) -- arch cover

	-- CANYON FLOOR -------------------------------------------------------------------
	-- spawn shield + side cover
	rock(V(8, 20, 28), V(-226, 10, 0), 0, CLIFF_DARK, TEAL, X)
	rock(V(16, 10, 12), V(-262, 5, 48), 0, ROCK, TEAL, XZ)
	-- hoodoo spires
	b.block(V(14, 58, 14), V(-222, 29, 76), CLIFF_DARK, XZ)
	b.decor(function()
		b.block(V(16, 4, 16), V(-222, 59.99, 76), CREAM, XZ)
	end)
	-- boulders (point-symmetric)
	rock(V(30, 18, 22), V(-188, 9, -32), 25, ROCK, CREAM, R)
	rock(V(22, 13, 18), V(-180, 6.5, 30), -15, ROCK, CREAM, R)
	rock(V(18, 11, 30), V(-58, 5.5, -36), 10, ROCK, CREAM, R)
	rock(V(14, 20, 14), V(-130, 10, -36), 40, CLIFF, CREAM, R)
	-- tall slabs to wall run along
	b.runWall(V(84, 40, 6), V(-112, 20, 22), R, CLIFF, TEAL)
	b.runWall(V(70, 44, 6), V(-255, 22, 104), XZ, CLIFF, TEAL)

	-- spawn pads
	b.decor(function()
		b.block(V(24, 0.2, 30), V(-282, 0.1, 0), P.PlayerA)
		b.block(V(24, 0.2, 30), V(282, 0.1, 0), P.PlayerB)
	end)

	local spawnHeight = 3.2
	local spawns = {
		CFrame.lookAt(V(-282, spawnHeight, 0), V(0, spawnHeight, 0)),
		CFrame.lookAt(V(282, spawnHeight, 0), V(0, spawnHeight, 0)),
	}
	local dummies = {
		{ Position = V(0, MESA_H, -8), Face = V(-1, 0, 0) },
		{ Position = V(-100, MESA_H, -130), Face = V(1, 0, 0) },
		{ Position = V(60, TIER_H, 165), Face = V(-1, 0, 0) },
		{ Position = V(61, MESA_H, -74), Face = V(-1, 0, 0) },
		{ Position = V(120, 0, 0), Motion = "Strafe", Amount = 8, Speed = 0.3, Face = V(-1, 0, 0) },
		{ Position = V(-130, 0, 50), Motion = "Strafe", Amount = 8, Speed = 0.25, Face = V(1, 0, 0) },
		{ Position = V(200, 0, -60), Motion = "Bob", Amount = 8, Speed = 0.4, Face = V(-1, 0, 0) },
		{ Position = V(282, 0, 0), Face = V(-1, 0, 0) },
	}
	return spawns, dummies
end

return ArenaMesa
