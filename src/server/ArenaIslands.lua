--[[
	ArenaIslands.lua  (ServerScriptService.Server.ArenaIslands)

	"Islands": grassy floating islands over a misty low floor. Each spawn
	is on a high island (30 studs up) with long wooden ramps down to the
	floor. Plank bridges lead to two mid islands (38) and from those to
	the big central island (46) with a rock spire on top. Long ramps also
	climb from the floor to the mid and central islands, so falling off
	only costs you height. Rocks and slabs give cover down below; pink
	crystals give cover up top. Mirrored across X and Z.

	TOP VIEW (X = long axis, spawns left / right)

	   +---------------------------------------------------------------+
	   |  ramp     ~slab~   [MID]<ramp      ramp      ramp>[MID]  ~slab~   ramp |
	   | [SPAWN  ]  bridge/    \bridge  [  CENTRAL  ] bridge/   \bridge  [SPAWN ]|
	   | [ISLAND ]    rocks       rocks [  + SPIRE  ]  rocks     rocks   [ISLAND]|
	   | [       ]  bridge\    /bridge  [           ] bridge\   /bridge  [      ]|
	   |  ramp     ~slab~   [MID]<ramp      ramp      ramp>[MID]  ~slab~   ramp |
	   +---------------------------------------------------------------+
]]

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local P = Config.Palette
local V = Vector3.new
local rgb = Color3.fromRGB

local ArenaIslands = {}

local LENGTH, WIDTH, WALL_H = 620, 440, 120
local SPAWN_H, MID_H, CENTER_H = 30, 38, 46

local MIST = rgb(208, 214, 240)
local WALL = rgb(172, 178, 218)
local CLOUD = rgb(236, 238, 250)
local GRASS = rgb(134, 206, 122)
local EARTH = rgb(168, 124, 94)
local ROCK = rgb(150, 144, 164)
local CRYSTAL = rgb(250, 140, 210)
local WOOD = rgb(196, 150, 100)

function ArenaIslands.Build(b)
	local X, Z, XZ, R = "X", "Z", "XZ", "R"
	local halfL, halfW = LENGTH / 2, WIDTH / 2

	-- A floating island: grass top, earth body and a tapering rocky underside.
	-- The underside either floats well above the floor or becomes a stem that
	-- reaches it (never a low gap you could get stuck in).
	local function island(x, z, top, sx, sz, m)
		b.block(V(sx, 3, sz), V(x, top - 1.5, z), GRASS, m)
		b.block(V(sx, 9, sz), V(x, top - 7.5, z), EARTH, m)
		local y, scale = top - 12, 0.7
		while y > 0 and scale > 0.25 do
			local h = 8
			if y - h < 8 then
				h = y -- reach down to the floor as a stem
			end
			b.block(V(sx * scale, h, sz * scale), V(x, y - h / 2, z), ROCK, m)
			y -= h
			scale -= 0.25
		end
		b.decor(function()
			b.block(V(sx + 0.6, 1, sz + 0.6), V(x, top - 3.5, z), CLOUD, m)
		end)
	end

	local function crystal(pos, height, tilt, m)
		local cf = CFrame.new(pos + V(0, height / 2 - 1, 0)) * CFrame.Angles(math.rad(tilt), math.rad(30), 0)
		b.material(b.part(V(6, height, 6), cf, CRYSTAL, m), Enum.Material.Neon)
	end

	-- FLOOR + WALLS ----------------------------------------------------------------------------
	b.shell(LENGTH, WIDTH, WALL_H, MIST, WALL, CLOUD)
	b.decor(function()
		b.block(V(LENGTH, 8, 1), V(0, 54, halfW - 0.5), CLOUD, Z)
		b.block(V(1, 8, WIDTH - 2), V(halfL - 0.5, 54, 0), CLOUD, X)
	end)

	-- SPAWN ISLANDS (x -302..-222, z -50..50) with ramps down to the floor ------------------------
	island(-262, 0, SPAWN_H, 80, 100, X)
	b.slopeTo(V(-262, SPAWN_H, 50), V(0, 0, -1), SPAWN_H, 30, WOOD, XZ, 22) -- z 50..124
	b.capped(V(8, 10, 22), V(-230, SPAWN_H + 5, 0), ROCK, CRYSTAL, X) -- spawn shield
	crystal(V(-290, SPAWN_H, 38), 16, 12, XZ)

	-- MID ISLANDS (x -175..-105, z 80..150) -------------------------------------------------------
	island(-140, 115, MID_H, 70, 70, XZ)
	b.slopeTo(V(-105, MID_H, 130), V(-1, 0, 0), MID_H, 26, WOOD, XZ, 24) -- from the floor, x -105..-20
	crystal(V(-152, MID_H, 132), 18, 10, XZ)
	b.capped(V(22, 6, 4), V(-150, MID_H + 3, 84), ROCK, CRYSTAL, XZ)

	-- CENTRAL ISLAND (x +-50, z +-65) + rock spire ----------------------------------------------------
	island(0, 0, CENTER_H, 100, 130, nil)
	b.slopeTo(V(0, CENTER_H, 65), V(0, 0, -1), CENTER_H, 30, WOOD, Z, 24) -- from the floor, z 65..168
	b.block(V(20, 40, 20), V(0, CENTER_H + 20, 0), ROCK)
	b.decor(function()
		b.block(V(21, 2, 21), V(0, CENTER_H + 36, 0), CLOUD)
	end)
	crystal(V(-30, CENTER_H, -40), 14, -12, XZ)
	b.capped(V(4, 6, 24), V(-46, CENTER_H + 3, 0), ROCK, CRYSTAL, X)

	-- PLANK BRIDGES: spawn -> mid -> centre ------------------------------------------------------------
	b.incline(V(-222, SPAWN_H, 35), V(-175, MID_H, 100), 12, 2, WOOD, XZ)
	b.incline(V(-105, MID_H, 95), V(-50, CENTER_H, 45), 12, 2, WOOD, XZ)

	-- FLOOR COVER -----------------------------------------------------------------------------------
	b.capped(V(24, 16, 24), V(-160, 8, -10), ROCK, CRYSTAL, R)
	b.capped(V(18, 12, 30), V(-90, 6, 40), ROCK, CRYSTAL, R)
	b.capped(V(30, 10, 14), V(-40, 5, -100), ROCK, CRYSTAL, R)
	b.runWall(V(80, 36, 5), V(-200, 18, 168), XZ, WALL, CRYSTAL)

	b.decor(function()
		b.block(V(24, 0.2, 30), V(-272, SPAWN_H + 0.1, 0), P.PlayerA)
		b.block(V(24, 0.2, 30), V(272, SPAWN_H + 0.1, 0), P.PlayerB)
	end)

	local spawnHeight = SPAWN_H + 3.2
	local spawns = {
		CFrame.lookAt(V(-272, spawnHeight, 0), V(0, spawnHeight, 0)),
		CFrame.lookAt(V(272, spawnHeight, 0), V(0, spawnHeight, 0)),
	}
	local dummies = {
		{ Position = V(0, CENTER_H, -40), Face = V(-1, 0, 0) },
		{ Position = V(-140, MID_H, 110), Face = V(1, 0, 0) },
		{ Position = V(140, MID_H, -110), Face = V(-1, 0, 0) },
		{ Position = V(-250, SPAWN_H, -36), Face = V(1, 0, 0) },
		{ Position = V(100, 0, -10), Motion = "Strafe", Amount = 8, Speed = 0.3, Face = V(-1, 0, 0) },
		{ Position = V(-120, 0, 30), Motion = "Strafe", Amount = 8, Speed = 0.25, Face = V(1, 0, 0) },
		{ Position = V(200, 0, 60), Motion = "Bob", Amount = 8, Speed = 0.4, Face = V(-1, 0, 0) },
		{ Position = V(272, SPAWN_H, 0), Face = V(-1, 0, 0) },
	}
	return spawns, dummies
end

return ArenaIslands
