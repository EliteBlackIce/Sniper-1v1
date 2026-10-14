--[[
	ArenaGlacier.lua  (ServerScriptService.Server.ArenaGlacier)

	"Glacier": an ice fortress built from giant frozen blocks. A two-part
	keep (32 studs high) sits in the middle with a gate between its halves,
	a bridge over the gate and a huge ice crystal in it. Long ramps climb
	onto the keep from both sides, raised bastions guard the four corners,
	and tilted ice boulders and shards give cover on the snowfield. Players
	are tiny next to the blocks. Mirrored (boulders point-symmetric).

	TOP VIEW (X = long axis, spawns left / right)

	   +------------------------------------------------------------+
	   |   ramp>[BASTION]   ~~~~ice slab~~~~   [BASTION]<ramp        |
	   |            ^ramp     ramp> [KEEP] <ramp    ^ramp             |
	   | SPAWN [bunker]  shards  boulders [gate+crystal] boulders [bunker] SPAWN
	   |            vramp     ramp> [KEEP] <ramp    vramp             |
	   |   ramp>[BASTION]   ~~~~ice slab~~~~   [BASTION]<ramp        |
	   +------------------------------------------------------------+
]]

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local P = Config.Palette
local V = Vector3.new
local rgb = Color3.fromRGB

local ArenaGlacier = {}

local LENGTH, WIDTH, WALL_H = 560, 400, 120
local KEEP_H, BASTION_H = 32, 22

local FLOOR = rgb(226, 238, 246)
local WALL = rgb(152, 192, 224)
local ICE = rgb(182, 220, 242)
local DEEP = rgb(106, 158, 206)
local SNOW = rgb(248, 251, 253)
local NAVY = rgb(46, 68, 108)
local GLOW = rgb(120, 232, 255)
local RAMP = rgb(132, 184, 228)

function ArenaGlacier.Build(b)
	local X, Z, XZ, R = "X", "Z", "XZ", "R"
	local halfL, halfW = LENGTH / 2, WIDTH / 2

	-- a block turned around Y (degrees) with a snow cap
	local function berg(size, pos, yaw, color, m)
		local cf = CFrame.new(pos) * CFrame.Angles(0, math.rad(yaw), 0)
		b.part(size, cf, color, m)
		b.decor(function()
			b.part(V(size.X + 0.6, 1.2, size.Z + 0.6), cf * CFrame.new(0, size.Y / 2 + 0.6, 0), SNOW, m)
		end)
	end

	-- FLOOR + GLACIER WALLS ---------------------------------------------------------
	b.shell(LENGTH, WIDTH, WALL_H, FLOOR, WALL, SNOW)
	b.decor(function()
		for x = -210, 210, 70 do
			b.block(V(8, WALL_H - 10, 1), V(x, WALL_H / 2 + 2, halfW - 0.5), DEEP, Z) -- ice pilasters
		end
		for z = -120, 120, 80 do
			b.block(V(1, WALL_H - 10, 8), V(halfL - 0.5, WALL_H / 2 + 2, z), DEEP, X)
		end
		b.block(V(LENGTH, 3, 1), V(0, 62, halfW - 1), GLOW, Z)
		b.block(V(1, 3, WIDTH - 4), V(halfL - 1, 62, 0), GLOW, X)
	end)

	-- THE KEEP: two halves with a gate between them ---------------------------------
	b.block(V(64, KEEP_H, 76), V(0, KEEP_H / 2, 62), ICE, Z) -- x -32..32, z 24..100
	b.block(V(40, 6, 48), V(0, KEEP_H - 3, 0), DEEP) -- bridge over the gate
	b.part(V(18, 20, 18), CFrame.new(0, 10, 0) * CFrame.Angles(0, math.rad(45), 0), DEEP) -- gate crystal
	b.decor(function()
		b.block(V(64.6, 2, 76.6), V(0, KEEP_H - 2, 62), SNOW, Z) -- snow rim
		b.block(V(40.6, 1, 48), V(0, KEEP_H - 6.5, 0), GLOW)
		b.part(V(18.6, 1.2, 18.6), CFrame.new(0, 20.6, 0) * CFrame.Angles(0, math.rad(45), 0), GLOW)
	end)
	b.slopeTo(V(-32, KEEP_H, 62), V(1, 0, 0), KEEP_H, 36, RAMP, XZ, 24) -- x -104..-32
	-- keep-top cover: corner merlons, a low wall over the gate and a tall ice tower
	berg(V(14, 8, 10), V(-24, KEEP_H + 4, 94), 0, DEEP, XZ)
	berg(V(4, 6, 20), V(-18, KEEP_H + 3, 0), 0, DEEP, X)
	b.block(V(22, 70, 22), V(0, KEEP_H + 35, 82), WALL, Z)
	b.decor(function()
		b.block(V(23, 3, 23), V(0, KEEP_H + 71.5, 82), SNOW, Z)
		b.block(V(23, 2, 23), V(0, KEEP_H + 40, 82), GLOW, Z)
	end)

	-- CORNER BASTIONS (x -180..-120, z 100..160) -----------------------------------
	b.block(V(60, BASTION_H, 60), V(-150, BASTION_H / 2, 130), ICE, XZ)
	b.decor(function()
		b.block(V(60.6, 2, 60.6), V(-150, BASTION_H - 2, 130), SNOW, XZ)
	end)
	b.slopeTo(V(-180, BASTION_H, 130), V(1, 0, 0), BASTION_H, 30, RAMP, XZ, 24) -- from the spawn end
	b.slopeTo(V(-150, BASTION_H, 100), V(0, 0, 1), BASTION_H, 30, RAMP, XZ, 24) -- from the field
	berg(V(4, 6, 22), V(-122, BASTION_H + 3, 142), 0, DEEP, XZ)
	berg(V(12, 6, 4), V(-127, BASTION_H + 3, 102), 0, DEEP, XZ)

	-- SNOWFIELD: giant tilted ice boulders and shards (point-symmetric) --------------
	berg(V(30, 24, 30), V(-82, 12, -14), 15, ICE, R)
	berg(V(40, 16, 22), V(-150, 8, 30), 0, DEEP, R)
	berg(V(26, 12, 20), V(-160, 6, -40), 30, ICE, R)
	berg(V(18, 18, 18), V(-56, 9, -140), 40, DEEP, R)
	b.part(V(12, 48, 12), CFrame.new(-190, 24, 30) * CFrame.Angles(0, math.rad(45), math.rad(8)), WALL, R) -- leaning shard
	b.part(V(10, 36, 10), CFrame.new(-70, 18, 120) * CFrame.Angles(0, math.rad(20), math.rad(-6)), WALL, R)
	-- long ice slabs to wall run along
	b.runWall(V(100, 40, 6), V(-65, 20, 168), XZ, ICE, GLOW)

	-- SPAWN BUNKERS --------------------------------------------------------------------
	berg(V(8, 18, 24), V(-212, 9, 0), 0, DEEP, X)
	berg(V(26, 12, 6), V(-238, 6, 34), 0, ICE, XZ)
	b.decor(function()
		b.block(V(24, 0.2, 30), V(-254, 0.1, 0), P.PlayerA)
		b.block(V(24, 0.2, 30), V(254, 0.1, 0), P.PlayerB)
	end)
	b.decor(function()
		b.material(b.block(V(0.4, 1, 20), V(-207.8, 4, 0), GLOW, X), Enum.Material.Neon)
	end)

	local spawnHeight = 3.2
	local spawns = {
		CFrame.lookAt(V(-254, spawnHeight, 0), V(0, spawnHeight, 0)),
		CFrame.lookAt(V(254, spawnHeight, 0), V(0, spawnHeight, 0)),
	}
	local dummies = {
		{ Position = V(-10, KEEP_H, 60), Face = V(-1, 0, 0) },
		{ Position = V(8, KEEP_H, -6), Face = V(1, 0, 0) },
		{ Position = V(150, BASTION_H, -130), Face = V(-1, 0, 0) },
		{ Position = V(-150, BASTION_H, 130), Face = V(1, 0, 0) },
		{ Position = V(60, 0, -60), Motion = "Strafe", Amount = 8, Speed = 0.3, Face = V(-1, 0, 0) },
		{ Position = V(-140, 0, 10), Motion = "Strafe", Amount = 8, Speed = 0.25, Face = V(1, 0, 0) },
		{ Position = V(150, 0, 60), Motion = "Bob", Amount = 8, Speed = 0.4, Face = V(-1, 0, 0) },
		{ Position = V(254, 0, 0), Face = V(-1, 0, 0) },
	}
	return spawns, dummies
end

return ArenaGlacier
