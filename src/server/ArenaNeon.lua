--[[
	ArenaNeon.lua  (ServerScriptService.Server.ArenaNeon)

	"Neon": city blocks at night. A wide avenue runs between the spawns;
	a raised plaza with a giant billboard sits in the middle. Skyscrapers
	(96 studs, great for wall running) line the sides, mid-rise buildings
	have ramps up to their rooftops and sloped skybridges down to the
	plaza, and low rooftops behind each spawn make sniper perches. Trucks,
	kiosks and barriers cover the street. Dark colours with neon trims.
	Mirrored across X and Z (street props point-symmetric).

	TOP VIEW (X = long axis, spawns left / right)

	   +----------------------------------------------------------------+
	   | [roof] [SKYSCRAPER] [MID-RISE]   ~~~~      [MID-RISE] [SKYSCRAPER] [roof]|
	   |  ramp    ~wall~       ramp \bridge     bridge/ ramp      ~wall~   ramp |
	   | SPAWN billboard  truck   kiosk  ramp> [PLAZA+BILLBOARD] <ramp ... SPAWN|
	   |  ramp    ~wall~       ramp /bridge     bridge\ ramp      ~wall~   ramp |
	   | [roof] [SKYSCRAPER] [MID-RISE]   ~~~~      [MID-RISE] [SKYSCRAPER] [roof]|
	   +----------------------------------------------------------------+
]]

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local P = Config.Palette
local V = Vector3.new
local rgb = Color3.fromRGB

local ArenaNeon = {}

local LENGTH, WIDTH, WALL_H = 600, 420, 120
local PLAZA_H, MID_H, ROOF_H = 20, 30, 20

local ASPHALT = rgb(38, 40, 52)
local WALL = rgb(30, 32, 46)
local BLDG1 = rgb(48, 54, 82)
local BLDG2 = rgb(66, 54, 92)
local BLDG3 = rgb(40, 62, 78)
local CONCRETE = rgb(84, 88, 108)
local RAMP = rgb(112, 102, 164)
local MAGENTA = rgb(255, 64, 180)
local CYAN = rgb(60, 230, 255)
local YELLOW = rgb(255, 210, 70)

function ArenaNeon.Build(b)
	local X, Z, XZ, R = "X", "Z", "XZ", "R"
	local halfL, halfW = LENGTH / 2, WIDTH / 2
	local NEON = Enum.Material.Neon

	-- glowing decor strip
	local function neon(size, pos, color, m)
		b.decor(function()
			b.material(b.block(size, pos, color, m), NEON)
		end)
	end

	-- FLOOR + DARK WALLS with neon bands, avenue edge lines ---------------------------
	b.shell(LENGTH, WIDTH, WALL_H, ASPHALT, WALL, CONCRETE)
	for _, y in ipairs({ 40, 84 }) do
		neon(V(LENGTH, 1.5, 1), V(0, y, halfW - 0.5), y == 40 and CYAN or MAGENTA, Z)
		neon(V(1, 1.5, WIDTH - 2), V(halfL - 0.5, y, 0), y == 40 and CYAN or MAGENTA, X)
	end
	neon(V(LENGTH - 80, 0.2, 1.5), V(0, 0.1, 46), YELLOW, Z)

	-- CENTRAL PLAZA (x +-40, z +-60) + BILLBOARD ----------------------------------------
	b.block(V(80, PLAZA_H, 120), V(0, PLAZA_H / 2, 0), CONCRETE)
	neon(V(80.6, 1, 120.6), V(0, PLAZA_H - 1.5, 0), MAGENTA)
	b.slopeTo(V(-40, PLAZA_H, 16), V(1, 0, 0), PLAZA_H, 24, RAMP, XZ, 22) -- x -90..-40, z 4..28
	b.block(V(6, 34, 50), V(0, PLAZA_H + 17, 0), WALL) -- billboard (blocks spawn-to-spawn shots)
	neon(V(6.6, 24, 42), V(0, PLAZA_H + 19, 0), CYAN)
	b.capped(V(4, 5, 8), V(-36, PLAZA_H + 2.5, 0), CONCRETE, YELLOW, X)
	b.capped(V(16, 5, 4), V(-12, PLAZA_H + 2.5, -50), CONCRETE, YELLOW, XZ)

	-- SKYSCRAPERS (x -215..-145, z 110..190) ---------------------------------------------
	b.block(V(70, 96, 80), V(-180, 48, 150), BLDG1, XZ)
	for _, x in ipairs({ -203, -180, -157 }) do
		neon(V(2, 70, 1), V(x, 50, 109.6), CYAN, XZ)
	end
	neon(V(70.6, 2, 80.6), V(-180, 93, 150), MAGENTA, XZ)

	-- MID-RISES with rooftop ramps + skybridges to the plaza (x -110..-50, z 100..170)
	b.block(V(60, MID_H, 70), V(-80, MID_H / 2, 135), BLDG2, XZ)
	neon(V(60.6, 1.2, 70.6), V(-80, MID_H - 2, 135), YELLOW, XZ)
	neon(V(60.6, 1.2, 70.6), V(-80, 12, 135), CYAN, XZ)
	b.slopeTo(V(-85, MID_H, 100), V(0, 0, 1), MID_H, 30, RAMP, XZ, 24) -- x -100..-70, z 33..100
	b.incline(V(-55, MID_H, 100), V(-30, PLAZA_H, 60), 14, 2, CONCRETE, XZ)
	b.capped(V(24, 6, 4), V(-80, MID_H + 3, 168), CONCRETE, MAGENTA, XZ)
	b.capped(V(10, 8, 10), V(-100, MID_H + 4, 120), BLDG3, CYAN, XZ)

	-- LOW ROOFTOPS behind the spawns (x -300..-245, z 140..200) -----------------------------
	b.block(V(55, ROOF_H, 60), V(-272.5, ROOF_H / 2, 170), BLDG3, XZ)
	neon(V(55.6, 1.2, 60.6), V(-272.5, ROOF_H - 2, 170), CYAN, XZ)
	b.slopeTo(V(-272, ROOF_H, 140), V(0, 0, 1), ROOF_H, 26, RAMP, XZ, 24) -- z 95..140
	b.capped(V(20, 5, 3), V(-262, ROOF_H + 2.5, 143), CONCRETE, YELLOW, XZ)

	-- STREET COVER (point-symmetric) ----------------------------------------------------------
	b.capped(V(36, 13, 13), V(-150, 6.5, -18), BLDG1, CYAN, R) -- box truck
	b.block(V(10, 9, 13), V(-127, 4.5, -18), BLDG3, R) -- its cab
	b.capped(V(16, 12, 16), V(-130, 6, 70), BLDG2, MAGENTA, R) -- kiosk
	b.capped(V(20, 6, 4), V(-210, 3, -55), CONCRETE, YELLOW, R) -- barriers
	b.capped(V(4, 6, 20), V(-110, 3, 8), CONCRETE, YELLOW, R)
	b.capped(V(14, 10, 24), V(-120, 5, -60), BLDG3, CYAN, R)
	-- walls to wall run along
	b.runWall(V(80, 34, 5), V(-200, 17, 62), XZ, BLDG1, MAGENTA)

	-- SPAWN: billboard shield --------------------------------------------------------------
	b.block(V(6, 20, 26), V(-230, 10, 0), WALL, X)
	neon(V(6.6, 14, 20), V(-230, 11, 0), MAGENTA, X)
	b.decor(function()
		b.block(V(24, 0.2, 30), V(-272, 0.1, 0), P.PlayerA)
		b.block(V(24, 0.2, 30), V(272, 0.1, 0), P.PlayerB)
	end)

	local spawnHeight = 3.2
	local spawns = {
		CFrame.lookAt(V(-272, spawnHeight, 0), V(0, spawnHeight, 0)),
		CFrame.lookAt(V(272, spawnHeight, 0), V(0, spawnHeight, 0)),
	}
	local dummies = {
		{ Position = V(0, PLAZA_H, -42), Face = V(-1, 0, 0) },
		{ Position = V(80, MID_H, -140), Face = V(-1, 0, 0) },
		{ Position = V(-272, ROOF_H, 178), Face = V(1, 0, 0) },
		{ Position = V(-80, MID_H, 140), Face = V(1, 0, 0) },
		{ Position = V(100, 0, 0), Motion = "Strafe", Amount = 8, Speed = 0.3, Face = V(-1, 0, 0) },
		{ Position = V(-150, 0, 38), Motion = "Strafe", Amount = 8, Speed = 0.25, Face = V(1, 0, 0) },
		{ Position = V(200, 0, -20), Motion = "Bob", Amount = 8, Speed = 0.4, Face = V(-1, 0, 0) },
		{ Position = V(272, 0, 0), Face = V(-1, 0, 0) },
	}
	return spawns, dummies
end

return ArenaNeon
