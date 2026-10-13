--[[
	LobbyBuilder.lua  (ServerScriptService.Server.LobbyBuilder)

	The lobby: a plaza where everyone waits between matches.

	TOP VIEW (spawn in the middle, -Z = north)

	                 [ SHOOTING RANGE ]  (long practice range with dummies)
	   +----------------- archway ----------------------+
	   |  tree                 lamps                tree |
	   |                                                  |
	   | [CRATES]          ( SPAWN DAIS )        [DUEL    |
	   |  shop             glowing ring           PADS]   |
	   |  (coming soon)                          press F  |
	   |                                                  |
	   |  movement park       [ STAGE + ]     movement    |
	   |  (ceiling, wall)     [ TITLE   ]     park (ramps)|
	   +--------------------------------------------------+

	CRATE SHOP (placeholder): three crates on pedestals under a "CRATES -
	COMING SOON" sign. Each pedestal top is a Part in Lobby.CrateSpots with a
	"Rarity" attribute, so a crate / skin system can find them later.

	Signs are SurfaceGuis. Everything else is flat parts with Neon trims.
]]

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local MapBuilder = require(script.Parent.MapBuilder)

local P = Config.Palette
local C = Config.MapPalette
local V = Vector3.new
local rad = math.rad

local LobbyBuilder = {}

local SIZE = 140 -- the plaza is SIZE x SIZE
local WALL_H = 14

-- A sign board with a title and a subtitle, facing the board's front.
local function sign(model, size, cf, title, subtitle, accent)
	local board = Instance.new("Part")
	board.Anchored = true
	board.Size = size
	board.CFrame = cf
	board.Color = P.UIPanel
	board.Material = Enum.Material.SmoothPlastic
	board.Parent = model
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = board
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, subtitle and 0.6 or 1)
	t.Text = title
	t.TextScaled = true
	t.FontFace = Font.new(Config.UI.FontFamily, Enum.FontWeight.Heavy)
	t.TextColor3 = P.UIText
	t.Parent = gui
	if subtitle then
		local s = t:Clone()
		s.Position = UDim2.fromScale(0.05, 0.62)
		s.Size = UDim2.fromScale(0.9, 0.3)
		s.Text = subtitle
		s.FontFace = Font.new(Config.UI.FontFamily, Enum.FontWeight.Bold)
		s.TextColor3 = accent or P.UIAccent
		s.Parent = gui
	end
	return board
end

local function neon(b, parts)
	return b.material(parts, Enum.Material.Neon)
end

local function tree(b, pos, m)
	b.block(V(6, 1.4, 6), pos + V(0, 0.7, 0), C.Curb, m)
	b.cylinder(6, 1.1, pos + V(0, 4, 0), C.Trunk, m)
	b.soft(function()
		b.ball(7, pos + V(0, 8.6, 0), C.Foliage, m)
		b.ball(5, pos + V(2.2, 7.6, 1), C.FoliageDark, m)
		b.ball(5, pos + V(-2, 8, -1.4), C.FoliageLight, m)
		b.ball(4, pos + V(0.4, 11, 0.3), C.FoliageLight, m)
	end)
	b.decor(function()
		b.block(V(5.2, 0.2, 5.2), pos + V(0, 1.45, 0), C.Soil, m)
	end)
end

local function lamp(b, pos, m)
	b.cylinder(10, 0.45, pos + V(0, 5, 0), C.Metal, m)
	b.decor(function()
		b.cylinder(1, 1, pos + V(0, 0.5, 0), C.Dark, m)
		b.block(V(1.4, 0.4, 1.4), pos + V(0, 10.1, 0), C.Dark, m)
		neon(b, b.ball(1.1, pos + V(0, 10.8, 0), C.LampLight, m))
	end)
end

local function bench(b, cf, m)
	b.decor(function()
		b.part(V(6, 0.4, 1.8), cf * CFrame.new(0, 1.4, 0), C.Wood, m)
		b.part(V(6, 1.2, 0.3), cf * CFrame.new(0, 2.3, 0.8), C.Wood, m)
		b.part(V(0.3, 1.3, 1.6), cf * CFrame.new(2.6, 0.65, 0), C.Dark, m)
		b.part(V(0.3, 1.3, 1.6), cf * CFrame.new(-2.6, 0.65, 0), C.Dark, m)
	end)
end

-- A loot crate model (placeholder art): box, lid, metal bands, glowing seam.
local function crate(b, pos, color)
	b.block(V(4.4, 3, 4.4), pos + V(0, 1.5, 0), C.Dark)
	b.decor(function()
		b.block(V(4.6, 0.9, 4.6), pos + V(0, 3.4, 0), color) -- lid
		neon(b, b.block(V(4.5, 0.18, 4.5), pos + V(0, 3, 0), color)) -- glowing seam
		for _, x in ipairs({ -1.5, 1.5 }) do
			b.block(V(0.35, 3.1, 4.5), pos + V(x, 1.5, 0), C.Metal) -- bands
		end
		b.block(V(1, 1, 0.3), pos + V(0, 2.3, -2.3), P.UIText) -- lock
		neon(b, b.ball(0.5, pos + V(0, 2.3, -2.45), color))
	end)
end

function LobbyBuilder.Build()
	local model = Instance.new("Model")
	model.Name = "Lobby"
	local b = MapBuilder.MakeBuilder(Vector3.zero, model)
	local half = SIZE / 2

	-- PLAZA FLOOR ------------------------------------------------------------
	b.block(V(SIZE, 4, SIZE), V(0, -2, 0), C.Sidewalk)
	b.decor(function()
		for i = -half + 10, half - 10, 10 do -- paving grid
			b.block(V(SIZE, 0.06, 0.3), V(0, 0.03, i), C.Curb)
			b.block(V(0.3, 0.06, SIZE), V(i, 0.03, 0), C.Curb)
		end
	end)

	-- WALLS (tall enough to frame the plaza, with glowing trims) ---------------
	b.block(V(2, WALL_H, SIZE), V(half + 1, WALL_H / 2, 0), C.BuildingB, "X")
	b.block(V(SIZE + 4, WALL_H, 2), V(0, WALL_H / 2, half + 1), C.BuildingB)
	b.block(V(half - 16, WALL_H, 2), V(-(16 + (half - 16) / 2), WALL_H / 2, -half - 1), C.BuildingB, "X") -- north (archway gap)
	b.decor(function()
		neon(b, b.block(V(2.4, 0.5, SIZE), V(half + 1, WALL_H + 0.25, 0), P.AccentA, "X"))
		neon(b, b.block(V(SIZE + 4, 0.5, 2.4), V(0, WALL_H + 0.25, half + 1), P.AccentA))
		neon(b, b.block(V(half - 16, 0.5, 2.4), V(-(16 + (half - 16) / 2), WALL_H + 0.25, -half - 1), P.AccentA, "X"))
		b.block(V(1, 1.4, SIZE), V(half - 0.5, 0.7, 0), C.Trim, "X") -- skirting
		b.block(V(SIZE, 1.4, 1), V(0, 0.7, half - 0.5), C.Trim)
		for z = -half + 14, half - 14, 14 do -- wall panels
			b.block(V(0.6, WALL_H - 4, 0.8), V(half - 0.3, WALL_H / 2, z), C.BuildingA, "X")
		end
	end)

	-- ARCHWAY to the shooting range (north)
	b.block(V(4, 22, 4), V(-18, 11, -half - 1), C.BuildingA, "X")
	b.block(V(40, 4, 4), V(0, 24, -half - 1), C.BuildingA)
	b.decor(function()
		neon(b, b.block(V(40.4, 0.6, 4.4), V(0, 22.2, -half - 1), P.AccentA))
	end)
	sign(model, V(24, 3.2, 0.6), CFrame.new(0, 24, -half + 1.2) * CFrame.Angles(0, math.pi, 0), "SHOOTING RANGE", nil)

	-- SPAWN DAIS (centre) ---------------------------------------------------------
	b.cylinder(1, 34, V(0, 0.5, 0), C.Stone)
	b.decor(function()
		neon(b, b.cylinder(0.12, 35, V(0, 0.95, 0), P.AccentA))
		b.cylinder(0.14, 31, V(0, 1.02, 0), C.Stone)
		neon(b, b.cylinder(0.16, 8, V(0, 1.05, 0), P.AccentB))
		b.cylinder(0.18, 6.6, V(0, 1.07, 0), C.Stone)
	end)

	-- STAGE + TITLE (south) ------------------------------------------------------
	b.block(V(50, 3, 14), V(0, 1.5, half - 9), C.Stone)
	b.ramp(V(0, 0, half - 22), V(0, 0, 1), 6, 3, 18, C.Stone) -- steps up to the stage
	b.block(V(56, 24, 2), V(0, 12, half - 1.5), C.BuildingA) -- backdrop
	b.decor(function()
		neon(b, b.block(V(50.4, 0.4, 14.4), V(0, 3.1, half - 9), P.AccentA))
		for _, x in ipairs({ -22, 22 }) do -- banners in the team colours
			b.block(V(6, 14, 0.4), V(x, 13, half - 2.8), x < 0 and P.PlayerA or P.PlayerB)
			b.block(V(6.4, 0.8, 0.6), V(x, 20.4, half - 2.8), C.Metal)
		end
	end)
	sign(model, V(32, 11, 1), CFrame.new(0, 14, half - 3), "SNIPER DUEL", ("1v1  -  FIRST TO %d"):format(Config.Match.RoundsToWin))

	-- DUEL PADS (east): where duels start ------------------------------------------
	b.block(V(26, 1, 40), V(half - 15, 0.5, 0), C.Stone)
	for i, z in ipairs({ -10, 10 }) do
		local color = i == 1 and P.PlayerA or P.PlayerB
		b.decor(function()
			neon(b, b.cylinder(0.15, 11, V(half - 15, 1.05, z), color))
			b.cylinder(0.18, 9, V(half - 15, 1.08, z), C.Dark)
		end)
	end
	sign(model, V(30, 9, 1), CFrame.new(half - 0.6, 8, 0) * CFrame.Angles(0, math.pi / 2, 0), "1v1 DUEL", "FIND MATCH [F]  -  DUEL A FRIEND [U]")

	-- CRATE SHOP (west): placeholder for loot crates / rifle skins ------------------
	b.block(V(26, 1, 40), V(-half + 15, 0.5, 0), C.Dark)
	b.decor(function()
		neon(b, b.block(V(26.4, 0.3, 40.4), V(-half + 15, 1.05, 0), P.AccentB))
	end)
	local spots = Instance.new("Folder")
	spots.Name = "CrateSpots"
	spots.Parent = model
	local crates = { { -12, "Rare" }, { 0, "Legendary" }, { 12, "Epic" } }
	for i, info in ipairs(crates) do
		local z, rarity = info[1], info[2]
		local color = Config.Rarity[rarity].Color
		local base = V(-half + 15, 1, z)
		b.cylinder(1.6, 6, base + V(0, 0.8, 0), C.Stone)
		b.decor(function()
			neon(b, b.cylinder(0.2, 6.3, base + V(0, 1.5, 0), color))
		end)
		crate(b, base + V(0, 1.6, 0), color)
		-- marker the future crate system will use
		local spot = Instance.new("Part")
		spot.Name = "CrateSpot" .. i
		spot.Anchored = true
		spot.CanCollide = false
		spot.CanQuery = false
		spot.Transparency = 1
		spot.Size = V(4, 0.2, 4)
		spot.CFrame = CFrame.new(base + V(0, 1.7, 0))
		spot:SetAttribute("Rarity", rarity)
		spot.Parent = spots
	end
	sign(model, V(30, 9, 1), CFrame.new(-half + 0.6, 8, 0) * CFrame.Angles(0, -math.pi / 2, 0), "CRATES", "RIFLE SKINS  -  COMING SOON", P.AccentB)

	-- MOVEMENT PARK (south-east): ramps and boxes ------------------------------------
	b.ramp(V(20, 0, 40), V(1, 0, 0), 16, 6, 10, P.AccentB)
	b.block(V(12, 6, 10), V(42, 3, 40), P.AccentA)
	b.block(V(8, 10, 8), V(52, 5, 52), P.Mid)
	b.block(V(6, 3, 6), V(30, 1.5, 54), P.AccentA)
	-- (south-west): a ceiling for Magnetic Boots and a wall for Wall Runner
	b.block(V(26, 1.5, 16), V(-40, 18, 44), P.Mid)
	for _, x in ipairs({ -52.5, -27.5 }) do
		for _, z in ipairs({ 37, 51 }) do
			b.block(V(1.5, 17.25, 1.5), V(x, 8.625, z), C.Metal) -- posts
		end
	end
	b.block(V(30, 16, 2), V(-42, 8, 26), P.Light)
	b.decor(function()
		neon(b, b.block(V(30.4, 0.5, 2.4), V(-42, 16.25, 26), P.AccentA))
	end)

	-- DECOR: trees, lamps, benches ----------------------------------------------------
	for _, pos in ipairs({ V(-56, 0, -56), V(56, 0, -56), V(-26, 0, -56), V(26, 0, -56) }) do
		tree(b, pos)
	end
	for _, pos in ipairs({ V(-22, 0, -24), V(22, 0, -24), V(-22, 0, 24), V(22, 0, 24) }) do
		lamp(b, pos)
	end
	bench(b, CFrame.new(-12, 0, -30) * CFrame.Angles(0, 0, 0))
	bench(b, CFrame.new(12, 0, -30))
	bench(b, CFrame.new(-34, 0, 0) * CFrame.Angles(0, rad(90), 0))
	bench(b, CFrame.new(34, 0, 0) * CFrame.Angles(0, rad(-90), 0))

	-- SHOOTING RANGE (north of the lobby, along -Z) ---------------------------------
	local rangeStart = -half
	b.block(V(64, 4, 344), V(0, -2, rangeStart - 172), P.Snow)
	b.block(V(2, 8, 344), V(32, 4, rangeStart - 172), P.Light, "X") -- side walls
	b.block(V(64, 46, 4), V(0, 23, rangeStart - 346), P.Light) -- back wall
	b.decor(function()
		for _, z in ipairs({ -120, -170, -270, -370 }) do
			b.block(V(60, 0.1, 1), V(0, 0.05, z), P.Mid) -- distance lines
		end
		neon(b, b.block(V(2.4, 0.5, 344), V(32, 8.25, rangeStart - 172), P.AccentA, "X"))
	end)
	b.block(V(16, 20, 10), V(12, 10, -300), P.AccentA) -- sniper's nest dummy platform
	b.block(V(8, 5, 3), V(-8, 2.5, -150), P.AccentA)
	b.block(V(6, 8, 3), V(14, 4, -215), P.Mid)
	b.block(V(10, 4, 3), V(-6, 2, -330), P.AccentA)

	model.Parent = workspace
	return {
		Model = model,
		SpawnCFrame = function()
			local angle = math.random() * math.pi * 2
			local radius = math.random() * 10
			local offset = Vector3.new(math.cos(angle) * radius, 4.5, math.sin(angle) * radius)
			return CFrame.lookAt(offset, Vector3.new(0, 4.5, -60))
		end,
		KillY = -60,
		CrateSpots = spots,
		-- practice dummies on the range (see DummyService)
		DummySpots = {
			{ Position = V(-10, 0, -110), Motion = "Static" },
			{ Position = V(8, 0, -135), Motion = "Strafe", Amount = 8, Speed = 0.35 },
			{ Position = V(0, 0, -185), Motion = "Strafe", Amount = 14, Speed = 0.25 },
			{ Position = V(-14, 0, -235), Motion = "Static" },
			{ Position = V(-12, 4, -260), Motion = "Bob", Amount = 10, Speed = 0.6 },
			{ Position = V(12, 20, -300), Motion = "Static" },
			{ Position = V(0, 0, -370), Motion = "Strafe", Amount = 18, Speed = 0.2 },
		},
	}
end

return LobbyBuilder
