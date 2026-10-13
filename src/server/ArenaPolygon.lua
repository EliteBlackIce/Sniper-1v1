--[[
	ArenaPolygon.lua  (ServerScriptService.Server.ArenaPolygon)

	"Polygon": a compact 1v1 arena in the Rivals style. An octagon of tall
	walls packed with things to fight around: high walls that split the
	lanes, ramps and ledges to jump off, and plenty of cover (hexagonal
	pillars, crate stacks, low walls, raised blocks). Low-poly look: flat
	colours, angled shapes, no textures. Mirrored across X and Z.

	TOP VIEW (X = long axis, spawns left / right)

	          ___________ catwalk (ramps at both ends) ___________
	        /   block    \\ tall wall /  hex    \\ tall wall /  block   \\
	       / hex                                                   hex \\
	      |  SPAWN  | shield   crates   [ TOWER ]   crates  shield | SPAWN |
	      |  deck   |  wall    hex       ramps N/S    hex    wall  |  deck |
	       \\ hex                                                   hex /
	        \\   block    / tall wall \\  hex    / tall wall \\  block   /
	          ¯¯¯¯¯¯¯¯¯¯¯ catwalk (ramps at both ends) ¯¯¯¯¯¯¯¯¯¯¯
]]

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local P = Config.Palette
local C = Config.MapPalette
local V = Vector3.new
local rad = math.rad

local ArenaPolygon = {}

local WALL_H = 40

function ArenaPolygon.Build(b)
	local X, Z, XZ = "X", "Z", "XZ"

	local WALL = C.BuildingB
	local TALL = P.Light
	local COVER = P.Mid
	local STONE = C.Stone
	local ACCENT = P.AccentA
	local ACCENT2 = P.AccentB

	-- hexagonal pillar: three overlapping boxes turned 60 degrees apart
	local function hexPillar(pos, height, radius, color, m)
		for k = 0, 2 do
			b.part(V(radius * 1.732, height, radius), CFrame.new(pos + V(0, height / 2, 0)) * CFrame.Angles(0, k * math.pi / 3, 0), color, m)
		end
		b.decor(function()
			for k = 0, 2 do
				b.part(V(radius * 1.732 + 0.3, 0.5, radius + 0.2), CFrame.new(pos + V(0, height + 0.15, 0)) * CFrame.Angles(0, k * math.pi / 3, 0), ACCENT2, m)
			end
		end)
	end

	-- a straight wall with a coloured cap and two panel lines (yaw in degrees)
	local function wall(size, pos, yaw, color, m)
		local cf = CFrame.new(pos) * CFrame.Angles(0, rad(yaw or 0), 0)
		b.part(size, cf, color, m)
		b.decor(function()
			b.part(V(size.X + 0.2, 0.6, size.Z + 0.3), cf * CFrame.new(0, size.Y / 2 + 0.3, 0), ACCENT, m)
			b.part(V(size.X + 0.05, 0.3, size.Z + 0.1), cf * CFrame.new(0, -size.Y / 2 + 1.2, 0), C.Trim, m)
			if size.Y > 8 then
				b.part(V(size.X + 0.05, 0.25, size.Z + 0.1), cf * CFrame.new(0, size.Y * 0.15, 0), C.Trim, m)
			end
		end)
	end

	-- FLOOR + OCTAGON OF TALL WALLS -------------------------------------------
	b.block(V(180, 4, 130), V(0, -2, 0), C.Concrete)
	b.block(V(4, WALL_H, 54), V(77, WALL_H / 2, 0), WALL, X) -- ends (x = +-75)
	b.block(V(104, WALL_H, 4), V(0, WALL_H / 2, 52), WALL, Z) -- sides (z = +-50)
	b.part(V(39, WALL_H, 4), CFrame.new(64, WALL_H / 2, 39) * CFrame.Angles(0, rad(45), 0), WALL, XZ) -- angled corners
	b.decor(function()
		-- floor: a big hexagon outline round the middle, lane lines, spawn zones
		for k = 0, 5 do
			local a = k * math.pi / 3
			local mid = V(math.cos(a + math.pi / 6) * 26, 0.04, math.sin(a + math.pi / 6) * 26)
			b.part(V(30, 0.08, 1), CFrame.lookAt(mid, mid + V(-math.sin(a + math.pi / 6), 0, math.cos(a + math.pi / 6))) * CFrame.Angles(0, rad(90), 0), C.Trim)
		end
		b.block(V(12, 0.08, 24), V(-66, 6.05, 0), P.PlayerA)
		b.block(V(12, 0.08, 24), V(66, 6.05, 0), P.PlayerB)
		b.block(V(100, 0.08, 0.8), V(0, 0.04, 30), C.Curb, Z)
		-- wall panels + top trim on the octagon
		b.block(V(0.6, 1, 54), V(74.7, 6, 0), ACCENT, X)
		b.block(V(104, 1, 0.6), V(0, 6, 49.7), ACCENT, Z)
		for z = -20, 20, 10 do
			b.block(V(0.5, 28, 0.6), V(74.7, 22, z), C.Trim, X)
		end
		for x = -40, 40, 10 do
			b.block(V(0.6, 28, 0.5), V(x, 22, 49.7), C.Trim, Z)
		end
	end)

	-- SPAWN DECKS + SHIELD WALLS ------------------------------------------------
	b.block(V(12, 6, 24), V(-66, 3, 0), STONE, X)
	b.ramp(V(-50, 0, 0), V(-1, 0, 0), 10, 6, 12, ACCENT, X)
	wall(V(1.5, 3, 6), V(-60.5, 7.5, 8), 0, COVER, XZ) -- deck-edge cover
	wall(V(2, 16, 14), V(-44, 8, 0), 0, TALL, X) -- shield: no spawn-to-spawn shots

	-- CENTRAL TOWER: ramps up from the north and south, cover on top --------------
	b.block(V(16, 8, 16), V(0, 4, 0), STONE)
	b.ramp(V(0, 0, 20), V(0, 0, -1), 12, 8, 8, ACCENT, Z)
	wall(V(1, 2.5, 6), V(-7.5, 9.25, 4), 0, COVER, XZ)
	b.decor(function()
		b.block(V(16.4, 0.4, 16.4), V(0, 8.2, 0), C.Trim)
		b.block(V(16.2, 1, 16.2), V(0, 1, 0), C.Trim)
	end)

	-- TALL WALLS splitting the lanes (high: you can't see or jump over them) -------
	wall(V(18, 20, 2), V(-26, 10, -22), 25, TALL, XZ)
	wall(V(12, 12, 1.5), V(-12, 6, -38), 30, TALL, XZ)

	-- SIDE CATWALKS: ramps up at both ends, a low edge to jump off -----------------
	b.block(V(60, 1.5, 6), V(0, 9.25, 46), STONE, Z)
	b.ramp(V(-44, 0, 46), V(1, 0, 0), 14, 10, 6, ACCENT, XZ)
	b.block(V(60, 2.4, 0.6), V(0, 11.2, 43.3), COVER, Z) -- the low edge
	for x = -24, 24, 16 do
		b.block(V(1, 8.5, 1), V(x, 4.25, 44), C.Metal, Z) -- supports
	end
	b.decor(function()
		b.block(V(60.2, 0.4, 0.8), V(0, 12.6, 43.3), ACCENT2, Z)
	end)

	-- COVER, lots of it -------------------------------------------------------------
	hexPillar(V(-20, 0, 10), 10, 3, STONE, XZ)
	hexPillar(V(-38, 0, 32), 12, 3.2, STONE, XZ)
	hexPillar(V(0, 0, 32), 9, 3, STONE, Z)
	wall(V(8, 4, 1.2), V(-12, 2, -24), 0, COVER, XZ) -- low walls
	wall(V(1.2, 4, 8), V(-54, 2, -16), 0, COVER, XZ)
	-- crate stacks (turned for a low-poly look)
	b.part(V(5, 5, 5), CFrame.new(-30, 2.5, -6) * CFrame.Angles(0, rad(45), 0), C.Wood, XZ)
	b.part(V(4, 4, 4), CFrame.new(-30.5, 7, -6.3) * CFrame.Angles(0, rad(20), 0), ACCENT2, XZ)
	b.decor(function()
		b.part(V(5.2, 0.4, 5.2), CFrame.new(-30, 4.4, -6) * CFrame.Angles(0, rad(45), 0), C.Trunk, XZ)
	end)
	-- raised blocks in the corners (jump up, shoot down)
	b.block(V(10, 5, 10), V(-50, 2.5, -32), COVER, XZ)
	b.decor(function()
		b.block(V(10.3, 0.4, 10.3), V(-50, 5.1, -32), ACCENT2, XZ)
	end)
	-- small kicker ramps to launch yourself across
	b.ramp(V(-28, 0, -34), V(1, 0, 1), 6, 3, 5, ACCENT2, XZ)

	-- Spawns (on the decks, facing the middle)
	local spawnHeight = 6 + 3.2
	local spawns = {
		CFrame.lookAt(V(-66, spawnHeight, 0), V(0, spawnHeight, 0)),
		CFrame.lookAt(V(66, spawnHeight, 0), V(0, spawnHeight, 0)),
	}
	local dummies = {
		{ Position = V(0, 8, 4), Face = V(-1, 0, 0) },
		{ Position = V(-10, 10, 46), Face = V(0, 0, -1) },
		{ Position = V(50, 5, 32), Face = V(-1, 0, 0) },
		{ Position = V(36, 0, 0), Motion = "Strafe", Amount = 6, Speed = 0.35, Face = V(-1, 0, 0) },
		{ Position = V(-20, 0, 26), Motion = "Strafe", Amount = 6, Speed = 0.3, Face = V(1, 0, 0) },
		{ Position = V(10, 0, -16), Motion = "Bob", Amount = 6, Speed = 0.5, Face = V(0, 0, 1) },
		{ Position = V(66, 6, 0), Face = V(-1, 0, 0) },
	}
	return spawns, dummies
end

return ArenaPolygon
