--[[
	LobbyBuilder.lua  (ServerScriptService.Server.LobbyBuilder)

	The lobby: a round, enclosed hall (a rotunda) where everyone waits
	between matches. Paved paths lead from the centre to everything there is
	to do, set in alcoves around the curved wall.

	TOP VIEW (-Z = north)

	                     [ SHOOTING RANGE ]
	                            ||  tunnel
	              .-'''''''''''''''''''''''''''-.
	         .-' PORTAL       |       GARDEN    '-.
	       /         \        |        /           \
	      |  CRATE ====== ( SUNKEN CENTRE ) ====== DUEL |
	      |  VAULT         (monument,              AREA |
	       \         /     skylight dome)  \           /
	         '-. WALL RUN     |      PARKOUR      .-'
	              '-.______ STAGE ___________.-'

	  * Centre: a sunken ring with smooth steps down, the monument (the
	    SNIPER DUEL crosshair as two crossed rings over a pool) and a ring of
	    columns holding up a glass skylight dome. You spawn here.
	  * The wall: panels with glowing trims, a plinth, a cornice and lit
	    sconces. The ceiling has radial beams and hanging lights.
	  * North: a tunnel with a gate into the shooting range.
	  * East: the duel area, a raised dais with team-coloured pads.
	  * West: the crate vault, a round dais with the crate altar (the crate is
	    built and animated by each client, see CrateController), the odds board
	    and two light pillars. Lobby.CrateAltar has the "Open Crate" prompt.
	  * South: the stage with the title sign.
	  * Diagonals: the Playground portal, an indoor garden, a parkour corner and
	    a wall-run wall with a low ceiling (Magnetic Boots).

	Detail parts use builder.decor (no collision), so paths stay smooth.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MapBuilder = require(script.Parent.MapBuilder)
local Logo = require(ReplicatedStorage.Shared.Logo)

local P = Config.Palette
local C = Config.MapPalette
local V = Vector3.new
local rad = math.rad

local LobbyBuilder = {}

local R = 64 -- inner radius of the hall
local WALL_H = 26 -- ceiling height
local PIT_R = 22 -- the sunken centre
local PIT_DEPTH = 2.5
local COLUMN_R = 31 -- the edge of the skylight
local COL_R = COLUMN_R + 1.6 -- the ring of columns (set back so their tops sit fully under the roof)
local SEGMENTS = 72 -- more segments = smoother circles

----------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------

-- A point at `radius` from the centre, `deg` degrees clockwise from north.
local function polar(radius, deg, y)
	local a = rad(deg)
	return V(math.sin(a) * radius, y or 0, -math.cos(a) * radius)
end

-- Unit vector pointing outward at `deg`.
local function outward(deg)
	local a = rad(deg)
	return V(math.sin(a), 0, -math.cos(a))
end

-- A CFrame at polar(radius, deg, y) whose -Z faces the centre.
local function facingIn(radius, deg, y)
	local pos = polar(radius, deg, y)
	return CFrame.lookAt(pos, V(0, y or 0, 0))
end

-- A sign board with a title and a subtitle (the text is on the board's front, -Z).
local function sign(model, size, cf, title, subtitle, accent)
	local board = Instance.new("Part")
	board.Anchored = true
	board.Size = size
	board.CFrame = cf
	board.Color = P.UIPanel
	board.Material = Enum.Material.SmoothPlastic
	board.CanCollide = false
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

-- Adds a light to the first part (indoor lighting).
-- Plain accent trim (not glowing; Neon + bloom everywhere looked harsh).
local function accent(_b, parts)
	return parts
end

-- Indoor lights are kept soft: LIGHT_SCALE dims every light in the hall.
local LIGHT_SCALE = 0.45
local function light(parts, color, range, brightness)
	local part = parts and parts[1]
	if part then
		local l = Instance.new("PointLight")
		l.Color = color
		l.Range = (range or 24) * 0.75
		l.Brightness = (brightness or 1.4) * LIGHT_SCALE
		l.Shadows = false
		l.Parent = part
	end
	return parts
end

local function bar(b, a, c, w, color)
	return b.part(V(w, w, (c - a).Magnitude), CFrame.lookAt((a + c) / 2, c), color)
end

local function plant(b, pos, scale)
	scale = scale or 1
	b.block(V(6, 1.4, 6), pos + V(0, 0.7, 0), C.Stone)
	b.cylinder(6 * scale, 1.2 * scale, pos + V(0, 1.4 + 3 * scale, 0), C.Trunk)
	b.decor(function()
		b.block(V(5.2, 0.2, 5.2), pos + V(0, 1.45, 0), C.Soil)
		b.block(V(6.4, 0.3, 6.4), pos + V(0, 1.3, 0), C.Trim)
		for k = 0, 2 do
			local a = k * 2.1 + pos.X
			local from = pos + V(0, 1.4 + 5 * scale, 0)
			bar(b, from, from + V(math.cos(a) * 2.4, 2.4, math.sin(a) * 2.4) * scale, 0.45 * scale, C.Trunk)
		end
	end)
	b.soft(function()
		b.ball(7.4 * scale, pos + V(0, 9 * scale, 0), C.Foliage)
		b.ball(5.4 * scale, pos + V(2.4, 8, 1.2) * scale, C.FoliageDark)
		b.ball(5.4 * scale, pos + V(-2.2, 8.4, -1.6) * scale, C.FoliageLight)
		b.ball(4.6 * scale, pos + V(0.6, 11.6, 0.4) * scale, C.FoliageLight)
	end)
end

local function lampPost(b, pos)
	b.cylinder(9, 0.45, pos + V(0, 4.5, 0), C.Metal)
	b.decor(function()
		b.cylinder(1.2, 1.1, pos + V(0, 0.6, 0), C.Dark)
		b.block(V(1.5, 0.35, 1.5), pos + V(0, 9.1, 0), C.Dark)
		light(neon(b, b.block(V(1, 1.2, 1), pos + V(0, 9.9, 0), C.LampLight)), C.LampLight, 22, 1.2)
		b.block(V(1.7, 0.35, 1.7), pos + V(0, 10.65, 0), C.Dark)
	end)
end

local function bench(b, cf)
	b.decor(function()
		for k = -1, 1 do
			b.part(V(6, 0.22, 0.5), cf * CFrame.new(0, 1.45, k * 0.6), C.Wood)
		end
		b.part(V(6, 0.4, 0.22), cf * CFrame.new(0, 2.2, 0.85), C.Wood)
		b.part(V(6, 0.4, 0.22), cf * CFrame.new(0, 2.8, 0.85), C.Wood)
		for _, x in ipairs({ -2.6, 2.6 }) do
			b.part(V(0.3, 1.4, 1.8), cf * CFrame.new(x, 0.7, 0), C.Dark)
			b.part(V(0.3, 1.6, 0.3), cf * CFrame.new(x, 2.2, 0.85), C.Dark)
		end
	end)
end

local function flowers(b, pos)
	b.decor(function()
		for k = 0, 6 do
			local a = k * 0.9 + pos.Z
			local r = 0.6 + (k % 3) * 0.7
			b.ball(0.7, pos + V(math.cos(a) * r, 0.5, math.sin(a) * r), C.Awning[(k % 3) + 1])
		end
		b.ball(1.6, pos + V(0, 0.3, 0), C.FoliageDark)
	end)
end

-- A ring of blocks between radii ri and ro (an annulus), `thick` tall, top at yTop.
-- skip(deg) can leave gaps.
local function ring(b, ri, ro, yTop, thick, color, count, skip)
	local parts = {}
	for i = 0, count - 1 do
		local deg = (i + 0.5) * 360 / count
		if not (skip and skip(deg)) then
			local mid = (ri + ro) / 2
			local width = 2 * math.pi * ro / count * 1.06
			local pos = polar(mid, deg, yTop - thick / 2)
			for _, part in ipairs(b.part(V(width, thick, ro - ri), CFrame.lookAt(pos, pos + outward(deg)), color)) do
				table.insert(parts, part)
			end
		end
	end
	return parts
end

-- A radial paved path from radius r1 to r2 at `deg`, `width` wide.
local function path(b, r1, r2, deg, width, color)
	local a, c = polar(r1, deg), polar(r2, deg)
	local mid = (a + c) / 2
	local len = r2 - r1
	local frame = CFrame.lookAt(mid, c)
	b.decor(function()
		b.part(V(width, 0.12, len), frame * CFrame.new(0, 0.06, 0), color or C.Sidewalk)
		for _, s in ipairs({ -1, 1 }) do
			b.part(V(0.5, 0.25, len), frame * CFrame.new(s * (width / 2 + 0.25), 0.12, 0), C.Trim)
			accent(b, b.part(V(0.18, 0.06, len), frame * CFrame.new(s * (width / 2 - 0.4), 0.13, 0), C.Trim))
		end
		for z = -len / 2 + 3, len / 2 - 3, 3 do
			b.part(V(width - 1, 0.02, 0.12), frame * CFrame.new(0, 0.13, z), C.Curb)
		end
	end)
	return frame, len
end

----------------------------------------------------------------------------
-- Build
----------------------------------------------------------------------------
function LobbyBuilder.Build()
	local model = Instance.new("Model")
	model.Name = "Lobby"
	local b = MapBuilder.MakeBuilder(Vector3.zero, model)
	local isRangeGap = function(deg)
		return deg < 8 or deg > 352
	end

	-- FLOOR: main ring, smooth steps down into the sunken centre ---------------------
	ring(b, PIT_R + 5.5, R + 4, 0, 3, C.Stone, SEGMENTS)
	b.cylinder(1, PIT_R * 2 + 0.6, V(0, -PIT_DEPTH - 0.5, 0), C.Sidewalk) -- pit floor
	for i = 0, SEGMENTS - 1 do -- the steps: an invisible smooth ramp ring...
		local deg = (i + 0.5) * 360 / SEGMENTS
		local width = 2 * math.pi * (PIT_R + 6) / SEGMENTS * 1.08
		b.invisible(b.ramp(polar(PIT_R, deg, -PIT_DEPTH), outward(deg), 6, PIT_DEPTH, width, C.Stone))
	end
	b.decor(function()
		-- ...and the steps you see
		for k = 0, 2 do
			ring(b, PIT_R + k * 2, PIT_R + 6, -PIT_DEPTH + (k + 1) * PIT_DEPTH / 3, PIT_DEPTH / 3 + 0.02, k % 2 == 0 and C.Stone or C.Sidewalk, SEGMENTS)
			ring(b, PIT_R + k * 2 - 0.08, PIT_R + k * 2 + 0.3, -PIT_DEPTH + (k + 1) * PIT_DEPTH / 3 + 0.03, 0.06, C.Trim, SEGMENTS) -- step nosing
		end
		-- floor pattern: radial joints and rings
		for i = 0, 23 do
			local deg = i * 15
			local a, c = polar(PIT_R + 6, deg, 0.02), polar(R, deg, 0.02)
			b.part(V(0.15, 0.04, (c - a).Magnitude), CFrame.lookAt((a + c) / 2, c), C.Curb)
		end
		for _, r in ipairs({ 40, 52 }) do
			ring(b, r, r + 0.3, 0.04, 0.04, C.Curb, SEGMENTS)
		end
		-- pit floor: inlaid rings
		b.cylinder(0.1, PIT_R * 2 - 2, V(0, -PIT_DEPTH + 0.05, 0), C.Stone)
		b.cylinder(0.12, 30, V(0, -PIT_DEPTH + 0.06, 0), C.Trim)
		b.cylinder(0.14, 29.2, V(0, -PIT_DEPTH + 0.07, 0), C.Sidewalk)
		-- star inlay: alternating tiles around the monument
		for i = 0, 15 do
			local deg = i * 22.5
			local pos = polar(11, deg, -PIT_DEPTH + 0.1)
			b.part(V(3.2, 0.1, 6), CFrame.lookAt(pos, pos + outward(deg)), i % 2 == 0 and C.Stone or C.Concrete)
		end
	end)

	-- OUTER WALL (with the tunnel gap to the north) + detail --------------------------
	ring(b, R, R + 3, WALL_H, WALL_H, C.BuildingA, SEGMENTS, isRangeGap)
	b.decor(function()
		ring(b, R - 1, R, 1.6, 1.6, C.Trim, SEGMENTS, isRangeGap) -- plinth
		ring(b, R - 1.4, R, WALL_H - 1, 1.2, C.Stone, SEGMENTS, isRangeGap) -- cornice
		ring(b, R - 0.8, R, 10.4, 0.6, C.Stone, SEGMENTS, isRangeGap) -- band
		for i = 0, SEGMENTS - 1 do
			local deg = (i + 0.5) * 360 / SEGMENTS
			if not isRangeGap(deg) then
				local w = 2 * math.pi * R / SEGMENTS
				-- recessed panel with a glowing outline (lower), lit window strip (upper)
				local cf = facingIn(R - 0.1, deg, 5.8)
				b.part(V(w * 0.78, 7, 0.2), cf, C.FrameDark)
				b.part(V(w * 0.68, 6.2, 0.3), cf * CFrame.new(0, 0, -0.1), C.BuildingB)
				b.part(V(w * 0.7, 0.15, 0.32), cf * CFrame.new(0, -3.2, -0.1), C.Trim)
				local up = facingIn(R - 0.1, deg, 17)
				b.part(V(w * 0.7, 9, 0.2), up, C.FrameDark)
				b.material(b.part(V(w * 0.6, 8.2, 0.3), up * CFrame.new(0, 0, -0.1), C.Window), Enum.Material.SmoothPlastic, 0.15)
				-- pilaster between panels
				local edge = facingIn(R - 0.5, deg + 180 / SEGMENTS, WALL_H / 2)
				b.part(V(1.4, WALL_H - 2, 1), edge, C.Stone)
				-- a lit sconce on every third pilaster
				if i % 3 == 0 then
					local sconce = facingIn(R - 1.3, deg + 180 / SEGMENTS, 12.5)
					b.part(V(1.2, 1.6, 0.8), sconce, C.Dark)
					light(neon(b, b.part(V(0.8, 1, 0.5), sconce * CFrame.new(0, 0.2, -0.4), C.LampLight)), C.LampLight, 30, 1.3)
				end
			end
		end
	end)

	-- CEILING: ring roof, radial beams, hanging lights; skylight over the centre ------
	ring(b, COLUMN_R - 1.5, R + 3, WALL_H + 1.5, 1.5, C.Roof, SEGMENTS)
	for i = 0, 11 do
		local deg = i * 30 + 15
		b.cylinder(WALL_H, 2.6, polar(COL_R, deg, WALL_H / 2), C.BuildingA) -- columns
	end
	b.decor(function()
		for i = 0, 11 do
			local deg = i * 30 + 15
			local base = polar(COL_R, deg, 0)
			b.block(V(3.6, 1.2, 3.6), base + V(0, 0.6, 0), C.Stone)
			b.block(V(3.8, 1.2, 3.8), base + V(0, WALL_H - 0.6, 0), C.Stone)
			b.cylinder(0.3, 2.9, base + V(0, 3, 0), C.Trim)
			for f = 0, 3 do -- fluting
				b.part(V(0.3, WALL_H - 4, 2.75), CFrame.new(base + V(0, WALL_H / 2, 0)) * CFrame.Angles(0, f * math.pi / 4, 0), C.Stone)
			end
			if i % 2 == 0 then -- potted plant at the base
				local pot = polar(COL_R - 3, deg, 0)
				b.cylinder(1.6, 2.4, pot + V(0, 0.8, 0), C.Trim)
				b.ball(2.6, pot + V(0, 2.4, 0), C.FoliageDark)
				b.ball(1.8, pot + V(0.5, 3.2, 0.3), C.Foliage)
			end
			-- banners between columns: the SNIPER DUEL logo, trimmed in team colours
			-- (none in front of the four main signs: north, east, south, west)
			if (deg + 15) % 90 ~= 0 then
				local team = (i - math.floor((i + 1) / 3)) % 2 == 0 and P.PlayerA or P.PlayerB
				local mid = polar(COL_R, deg + 15, 16.5)
				local bannerCf = CFrame.lookAt(mid, V(0, 16.5, 0))
				local cloth = b.part(V(4.6, 10, 0.2), bannerCf, P.UIPanel)
				for _, part in ipairs(cloth) do
					part.Name = "Banner"
					for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
						Logo.OnPart(part, face, { Layout = "Stacked", Color = P.UIText, Accent = team, Stroke = 9 }, 40)
					end
				end
				for _, x in ipairs({ -2.22, 2.22 }) do
					b.part(V(0.24, 10.3, 0.26), bannerCf * CFrame.new(x, 0, 0), team) -- side trims
				end
				b.part(V(4.84, 0.5, 0.3), bannerCf * CFrame.new(0, -5.1, 0), team) -- bottom hem
				b.cylinder(5.6, 0.3, nil, C.Metal, nil, bannerCf * CFrame.new(0, 5.15, 0)) -- hanging rod
				for _, x in ipairs({ -2.95, 2.95 }) do
					b.ball(0.5, (bannerCf * CFrame.new(x, 5.15, 0)).Position, C.Trim)
					b.part(V(0.08, WALL_H - 21.65, 0.08), bannerCf * CFrame.new(x * 0.8, 5.15 + (WALL_H - 21.65) / 2, 0), C.Metal) -- cords
				end
			end
			-- radial beams under the ceiling
			local a, c = polar(COL_R, deg, WALL_H - 0.8), polar(R, deg, WALL_H - 0.8)
			b.part(V(1.2, 1.4, (c - a).Magnitude), CFrame.lookAt((a + c) / 2, c), C.Trim)
			-- hanging light halfway along each beam
			local hang = polar((COLUMN_R + R) / 2, deg + 15, WALL_H)
			b.block(V(0.15, 5, 0.15), hang - V(0, 2.5, 0), C.Metal)
			b.block(V(2.6, 0.6, 2.6), hang - V(0, 5.2, 0), C.Dark)
			light(neon(b, b.block(V(2, 0.3, 2), hang - V(0, 5.6, 0), C.LampLight)), C.LampLight, 32, 1.4)
		end
		ring(b, R - 2, R, WALL_H, 0.4, C.Trim, SEGMENTS) -- ceiling edge trim
		for _, r in ipairs({ 40, 52 }) do -- ceiling beam rings (coffers)
			ring(b, r, r + 1.2, WALL_H - 0.1, 1.2, C.Trim, SEGMENTS)
		end
		-- skylight drum (sitting on the roof, so no faces overlap) + glass + rim
		ring(b, COLUMN_R - 1.5, COLUMN_R, WALL_H + 7, 5.5, C.BuildingA, SEGMENTS)
		local glass = b.cylinder(0.3, (COLUMN_R - 0.6) * 2, V(0, WALL_H + 7.25, 0), C.Glass)
		b.material(glass, Enum.Material.Glass, 0.1)
		for _, part in ipairs(glass) do
			part.Transparency = 0.6
		end
		ring(b, COLUMN_R - 1.8, COLUMN_R + 0.3, WALL_H + 7.7, 0.5, C.Trim, SEGMENTS) -- rim
		for i = 0, 7 do -- dome ribs
			local deg = i * 45
			bar(b, polar(COLUMN_R - 1, deg, WALL_H + 7.8), V(0, WALL_H + 9.3, 0), 0.6, C.Trim)
		end
		ring(b, COLUMN_R - 2, COLUMN_R, WALL_H, 0.4, C.Trim, SEGMENTS) -- trim under the roof edge
	end)

	-- CENTRE: THE MONUMENT ------------------------------------------------------------
	-- The SNIPER DUEL crosshair in stone and metal: two crossed rings (a
	-- gyroscope, so it reads from every side) with the crosshair's ticks and a
	-- glowing core, on a tiered plinth in a shallow pool.
	local pitY = -PIT_DEPTH
	local POOL_R = 8
	ring(b, POOL_R, POOL_R + 0.9, pitY + 0.9, 0.9, C.Stone, 48) -- pool wall
	b.cylinder(0.5, POOL_R * 2 + 0.2, V(0, pitY + 0.25, 0), C.FrameDark) -- pool floor
	b.cylinder(2.2, 6.4, V(0, pitY + 1.1, 0), C.Stone) -- plinth, lower tier
	b.cylinder(1.4, 4.8, V(0, pitY + 2.9, 0), C.BuildingA) -- upper tier
	local coreY = pitY + 3.6 + 6.2 -- centre of the rings
	b.decor(function()
		ring(b, POOL_R - 0.15, POOL_R + 1.05, pitY + 1.0, 0.12, C.Trim, 48) -- pool coping
		local water = b.cylinder(0.12, POOL_R * 2 - 0.1, V(0, pitY + 0.62, 0), C.Water)
		b.material(water, Enum.Material.SmoothPlastic, 0.4)
		for _, part in ipairs(water) do
			part.Transparency = 0.25
		end
		b.cylinder(0.16, 6.7, V(0, pitY + 1.9, 0), C.Trim) -- tier bands (kept off the tops)
		b.cylinder(0.16, 5.1, V(0, pitY + 3.2, 0), C.Trim)
		b.cylinder(0.3, 5.2, V(0, pitY + 3.75, 0), C.Metal) -- cap
		b.cylinder(1.2, 1.1, V(0, pitY + 4.5, 0), C.Metal) -- neck up to the rings
		for k = 0, 3 do -- uplights round the plinth, shining on the rings
			local pos = polar(3.6, 45 + k * 90, pitY + 2.25)
			b.block(V(0.8, 0.12, 0.8), pos, C.Dark)
			light(neon(b, b.block(V(0.5, 0.08, 0.5), pos + V(0, 0.08, 0), C.LampLight)), C.LampLight, 14, 1)
		end

		-- a vertical ring of `count` segments, facing `normalDeg`
		local function vring(radius, thick, depth, normalDeg, color, count)
			local across = outward(normalDeg + 90) -- in the ring's plane, horizontal
			for i = 0, count - 1 do
				local a = (i + 0.5) / count * math.pi * 2
				local pos = V(0, coreY, 0) + across * math.cos(a) * radius + V(0, math.sin(a) * radius, 0)
				local tangent = across * -math.sin(a) + V(0, math.cos(a), 0)
				local length = 2 * math.pi * radius / count * 1.08
				b.part(V(depth, thick, length), CFrame.lookAt(pos, pos + tangent), color)
			end
		end
		-- the main ring (facing the stage / the range) and the crossed ring
		vring(5.2, 0.8, 0.9, 0, C.BuildingA, 40)
		vring(4.55, 0.25, 1.06, 0, P.AccentA, 40) -- inner accent band
		vring(4.7, 0.6, 0.7, 90, C.Metal, 40)
		-- the crosshair ticks: through the ring at top, bottom, left and right
		for _, info in ipairs({ { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }) do
			local across = outward(90)
			local dir = across * info[1] + V(0, info[2], 0)
			local mid = V(0, coreY, 0) + dir * 5.2
			local vertical = info[2] ~= 0
			b.part(vertical and V(0.7, 3.4, 1.2) or V(3.4, 0.7, 1.2), CFrame.new(mid), C.BuildingA)
		end
		-- the core: a glowing ball in a small metal cage
		light(neon(b, b.ball(1.5, V(0, coreY, 0), P.AccentA)), P.AccentA, 18, 1.2)
		for k = 0, 2 do
			local spin = CFrame.new(0, coreY, 0) * CFrame.Angles(0, rad(k * 60), rad(90))
			b.cylinder(0.12, 2.3, nil, C.Metal, nil, spin)
		end
		-- thin spokes from the core to the ring (the crosshair's lines)
		for _, dir in ipairs({ V(0, 1, 0), V(0, -1, 0), outward(90), -outward(90) }) do
			local a, c = V(0, coreY, 0) + dir * 0.9, V(0, coreY, 0) + dir * 4.4
			bar(b, a, c, 0.18, C.Metal)
		end
	end)
	-- a plaque on the plinth
	local plaque = Instance.new("Part")
	plaque.Name = "Plaque"
	plaque.Anchored = true
	plaque.CanCollide = false
	plaque.Size = V(3.4, 1.1, 0.2)
	plaque.CFrame = CFrame.lookAt(V(0, pitY + 1.15, 3.25), V(0, pitY + 1.15, 10)) -- faces the stage side (south)
	plaque.Color = C.Metal
	plaque.Material = Enum.Material.Metal
	plaque.Parent = model
	Logo.OnPart(plaque, Enum.NormalId.Front, { Layout = "Inline", Color = P.UIText, Accent = P.AccentA, Stroke = 3 }, 60)

	-- benches around the pit, facing the monument
	for k = 0, 3 do
		local deg = 45 + k * 90
		bench(b, facingIn(PIT_R - 4, deg, pitY))
	end

	-- GLASS RAILING around the top of the steps (gaps where the paths are)
	local function onPath(deg)
		for _, d in ipairs({ 0, 90, 180, 270 }) do
			if math.abs((deg - d + 180) % 360 - 180) < 11 then
				return true
			end
		end
		for _, d in ipairs({ 45, 135, 225, 315 }) do
			if math.abs((deg - d + 180) % 360 - 180) < 7 then
				return true
			end
		end
		return false
	end
	local railR = PIT_R + 6.6
	for i = 0, SEGMENTS - 1 do
		local deg = (i + 0.5) * 360 / SEGMENTS
		if not onPath(deg) then
			local w = 2 * math.pi * railR / SEGMENTS * 1.04
			local cf = facingIn(railR, deg, 1.6)
			local panel = b.part(V(w, 2.6, 0.25), cf, C.Glass)
			b.material(panel, Enum.Material.Glass, 0.1)
			for _, part in ipairs(panel) do
				part.Transparency = 0.55
			end
			b.decor(function()
				b.part(V(w + 0.05, 0.3, 0.45), cf * CFrame.new(0, 1.45, 0), C.Trim) -- handrail
				if i % 3 == 0 then
					b.part(V(0.3, 3.1, 0.3), cf * CFrame.new(-w / 2, 0, 0), C.Metal) -- post
				end
			end)
		end
	end

	-- PATHS (from the top of the steps out to each place) ------------------------------
	local stepTop = PIT_R + 6
	for _, deg in ipairs({ 0, 90, 180, 270 }) do
		local frame, len = path(b, stepTop, deg == 270 and 43 or 50, deg, 10) -- (west stops at the crate dais)
		for _, s in ipairs({ -1, 1 }) do
			lampPost(b, (frame * CFrame.new(s * 7, 0, 0)).Position)
		end
	end
	for _, deg in ipairs({ 45, 135, 225, 315 }) do
		path(b, stepTop, 46, deg, 6, C.Stone)
	end
	-- planters + flowers between the paths
	for k = 0, 7 do
		local deg = 22.5 + k * 45
		local pos = polar(38, deg)
		b.part(V(7, 1.2, 3), CFrame.lookAt(pos + V(0, 0.6, 0), V(0, 0.6, 0)), C.Stone)
		b.decor(function()
			b.part(V(6.4, 0.2, 2.4), CFrame.lookAt(pos + V(0, 1.25, 0), V(0, 1.25, 0)), C.Soil)
		end)
		flowers(b, pos + V(1.5, 1.1, 0))
		flowers(b, pos + V(-1.5, 1.1, 0))
	end

	-- NORTH: TUNNEL TO THE SHOOTING RANGE -----------------------------------------------
	b.block(V(18, 3, 14), V(0, -1.5, -R - 4), C.Stone) -- tunnel floor
	b.block(V(2, WALL_H, 14), V(-9, WALL_H / 2, -R - 4), C.BuildingA, "X") -- tunnel sides
	b.block(V(20, 2, 14), V(0, 15, -R - 4), C.BuildingA) -- tunnel ceiling
	b.block(V(20, WALL_H - 14, 2), V(0, (WALL_H + 14) / 2 + 1, -R + 2), C.BuildingA) -- wall above the gate
	b.decor(function()
		neon(b, b.block(V(16, 0.4, 0.4), V(0, 13.6, -R + 2.8), P.AccentA))
		for _, x in ipairs({ -7.6, 7.6 }) do
			b.block(V(1.2, 14, 1.2), V(x, 7, -R + 2.6), C.Stone) -- gate frame
			light(neon(b, b.block(V(0.3, 10, 0.3), V(x * 1.06, 6, -R - 4), P.AccentA)), P.AccentA, 16, 0.8)
		end
		for z = -R - 9, -R + 1, 3.3 do
			b.block(V(17.6, 0.6, 0.6), V(0, 13.7, z), C.Trim) -- ceiling ribs
		end
	end)
	sign(model, V(16, 3, 0.5), CFrame.new(0, 17.5, -R + 0.8) * CFrame.Angles(0, math.pi, 0), "SHOOTING RANGE", nil)

	-- EAST: DUEL AREA -----------------------------------------------------------------------
	b.block(V(12, 1.4, 30), V(56, 0.7, 0), C.Stone)
	b.ramp(V(48, 0, 0), V(1, 0, 0), 2.5, 1.4, 12, C.Stone)
	b.decor(function()
		accent(b, b.block(V(12.2, 0.2, 30.2), V(56, 1.45, 0), P.AccentA))
		for i, z in ipairs({ -7.5, 7.5 }) do
			local color = i == 1 and P.PlayerA or P.PlayerB
			neon(b, b.cylinder(0.15, 10, V(56, 1.5, z), color))
			b.cylinder(0.18, 8.2, V(56, 1.53, z), C.Dark)
			neon(b, b.cylinder(0.2, 2, V(56, 1.56, z), color))
			light(neon(b, b.block(V(1, 12, 0.6), V(61, 7.4, z * 1.9), color)), color, 18, 1)
		end
		-- canopy on two posts
		for _, z in ipairs({ -14, 14 }) do
			b.block(V(1, 14, 1), V(50.5, 8.4, z), C.Metal)
		end
		b.block(V(13, 0.8, 30), V(56.5, 15.6, 0), C.BuildingA)
		accent(b, b.block(V(13.2, 0.25, 30.2), V(56.5, 15.1, 0), P.AccentA))
	end)
	sign(model, V(24, 8, 1), CFrame.new(R - 1.6, 9, 0) * CFrame.Angles(0, math.pi / 2, 0), "1v1 DUEL", "FIND MATCH [F]  -  DUEL A PLAYER [U]")

	-- WEST: CRATE VAULT ---------------------------------------------------------------------
	-- A round dais with the altar in the middle (the crate itself is built and
	-- animated by each client, see CrateController), an odds board on the wall
	-- behind it and two light pillars. Open, calm, and lit like the rest of the hall.
	local vault = V(-53, 0, 0)
	b.cylinder(0.5, 21, vault + V(0, 0.25, 0), C.Stone) -- lower step
	b.cylinder(0.5, 15, vault + V(0, 0.75, 0), C.BuildingA) -- upper step
	b.cylinder(2.2, 5, vault + V(0, 2.1, 0), C.Dark) -- altar pedestal
	b.decor(function()
		-- step edges: a trim band round each step, its top kept below the
		-- step's top so the two never share a surface (that flickers)
		b.cylinder(0.1, 21.3, vault + V(0, 0.4, 0), C.Trim)
		b.cylinder(0.1, 15.3, vault + V(0, 0.9, 0), C.Trim)
		b.cylinder(0.3, 5.6, vault + V(0, 1.15, 0), C.Metal) -- pedestal base + cap
		b.cylinder(0.25, 5.5, vault + V(0, 3.3, 0), C.Metal)
		-- rarity wheel inlaid round the pedestal, one tile per rarity
		local count = #Config.Crates.Rarities
		for k, rarity in ipairs(Config.Crates.Rarities) do
			local a = rad((k - 1) * 360 / count + 180 / count)
			local pos = vault + V(math.cos(a) * 5.4, 1.03, math.sin(a) * 5.4)
			b.part(V(4.4, 0.06, 1.1), CFrame.lookAt(pos, vault + V(0, 1.03, 0)) * CFrame.Angles(0, rad(90), 0), rarity.Color)
		end
	end)
	local ringParts = b.cylinder(0.14, 5.2, vault + V(0, 3.05, 0), P.AccentA)
	neon(b, ringParts)
	for _, part in ipairs(ringParts) do
		part.Name = "AltarRing" -- the client cycles it through the rarity colours
		part.CanCollide = false
	end

	-- the altar anchor: the client builds the crate here; the prompt opens it
	local altar = Instance.new("Part")
	altar.Name = "CrateAltar"
	altar.Anchored = true
	altar.CanCollide = false
	altar.CanQuery = false
	altar.CanTouch = false
	altar.Transparency = 1
	altar.Size = V(4, 0.2, 4)
	altar.CFrame = CFrame.lookAt(vault + V(0, 3.45, 0), vault + V(1, 3.45, 0)) -- crate front faces the hall
	altar.Parent = model
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "OpenCrate"
	prompt.ActionText = "Open Crate"
	prompt.ObjectText = "Crate Vault"
	prompt.KeyboardKeyCode = Enum.KeyCode.X
	prompt.HoldDuration = 0.35
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.UIOffset = Vector2.new(0, 40)
	prompt.Parent = altar

	-- light pillars either side of the dais
	for _, z in ipairs({ -9, 9 }) do
		local base = vault + V(-3.5, 1, z)
		b.block(V(1.2, 10, 1.2), base + V(0, 5, 0), C.BuildingA)
		b.decor(function()
			b.block(V(1.6, 0.6, 1.6), base + V(0, 0.3, 0), C.Metal)
			b.block(V(1.6, 0.6, 1.6), base + V(0, 9.9, 0), C.Metal)
			light(neon(b, b.block(V(0.3, 8, 1.26), base + V(0.5, 5, 0), C.LampLight)), C.LampLight, 22, 1.1)
		end)
	end

	-- odds board on the wall behind: one card per rarity with its chance
	local board = Instance.new("Part")
	board.Name = "OddsBoard"
	board.Anchored = true
	board.CanCollide = false
	board.Size = V(22, 9, 0.4)
	board.CFrame = CFrame.lookAt(V(-60.6, 8.5, 0), V(0, 8.5, 0))
	board.Color = P.UIPanel
	board.Material = Enum.Material.SmoothPlastic
	board.Parent = model
	do
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		gui.Parent = board
		local title = Instance.new("TextLabel")
		title.BackgroundTransparency = 1
		title.Position = UDim2.fromScale(0.05, 0.05)
		title.Size = UDim2.fromScale(0.9, 0.14)
		title.Text = "CRATE ODDS"
		title.TextScaled = true
		title.FontFace = Font.new(Config.UI.FontFamily, Enum.FontWeight.Heavy)
		title.TextColor3 = P.UIText
		title.Parent = gui
		local count = #Config.Crates.Rarities
		for k, rarity in ipairs(Config.Crates.Rarities) do
			local card = Instance.new("Frame")
			card.BackgroundColor3 = P.UIPanelLight
			card.BorderSizePixel = 0
			card.Position = UDim2.fromScale(0.04 + (k - 1) * 0.92 / count + 0.006, 0.26)
			card.Size = UDim2.fromScale(0.92 / count - 0.012, 0.66)
			card.Parent = gui
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 14)
			corner.Parent = card
			local bar = Instance.new("Frame")
			bar.BackgroundColor3 = rarity.Color
			bar.BorderSizePixel = 0
			bar.Size = UDim2.fromScale(1, 0.12)
			bar.Parent = card
			local barCorner = corner:Clone()
			barCorner.Parent = bar
			local chance = Instance.new("TextLabel")
			chance.BackgroundTransparency = 1
			chance.Position = UDim2.fromScale(0.08, 0.24)
			chance.Size = UDim2.fromScale(0.84, 0.36)
			chance.Text = tostring(rarity.Chance) .. "%"
			chance.TextScaled = true
			chance.FontFace = Font.new(Config.UI.FontFamily, Enum.FontWeight.Heavy)
			chance.TextColor3 = rarity.Color
			chance.Parent = card
			local name = chance:Clone()
			name.Position = UDim2.fromScale(0.06, 0.68)
			name.Size = UDim2.fromScale(0.88, 0.18)
			name.Text = rarity.Name
			name.FontFace = Font.new(Config.UI.FontFamily, Enum.FontWeight.Bold)
			name.TextColor3 = P.UIText
			name.Parent = card
		end
	end
	b.decor(function()
		local frame = CFrame.lookAt(V(-60.9, 8.5, 0), V(0, 8.5, 0))
		b.part(V(22.8, 0.4, 0.5), frame * CFrame.new(0, 4.7, 0), C.Metal)
		b.part(V(22.8, 0.4, 0.5), frame * CFrame.new(0, -4.7, 0), C.Metal)
		b.part(V(0.4, 9.8, 0.5), frame * CFrame.new(-11.2, 0, 0), C.Metal)
		b.part(V(0.4, 9.8, 0.5), frame * CFrame.new(11.2, 0, 0), C.Metal)
	end)
	sign(model, V(16, 3.2, 0.5), CFrame.lookAt(V(-60.4, 15.4, 0), V(0, 15.4, 0)), "CRATE VAULT", "OPEN CRATES  -  UNLOCK RIFLE SKINS", P.AccentB)

	-- VENDING MACHINES + BINS ---------------------------------------------------------------
	local function vending(cf, color)
		b.part(V(4, 7, 3), cf * CFrame.new(0, 3.5, 0), color)
		b.decor(function()
			b.material(b.part(V(2.6, 4, 0.2), cf * CFrame.new(-0.4, 4.2, -1.55), C.Glass), Enum.Material.Glass, 0.2)
			for row = 0, 3 do
				for col = 0, 2 do
					b.part(V(0.5, 0.6, 0.3), cf * CFrame.new(-1.2 + col * 0.8, 2.8 + row * 0.9, -1.35), C.Awning[((row + col) % 3) + 1])
				end
			end
			b.part(V(0.6, 2, 0.2), cf * CFrame.new(1.4, 4.4, -1.55), C.Dark) -- keypad
			light(neon(b, b.part(V(3.6, 0.6, 0.2), cf * CFrame.new(0, 6.5, -1.55), C.LampLight)), color, 10, 0.6)
		end)
	end
	vending(facingIn(R - 3, 243, 0), P.PlayerB)
	vending(facingIn(R - 3, 297, 0), P.AccentA)
	vending(facingIn(R - 3, 117, 0), P.PlayerA)
	for _, deg in ipairs({ 20, 160, 200, 340 }) do -- bins by the paths
		local pos = polar(31, deg, 0)
		b.decor(function()
			b.cylinder(2.4, 1.6, pos + V(0, 1.2, 0), C.Metal)
			b.cylinder(0.3, 1.8, pos + V(0, 2.5, 0), C.Dark)
		end)
	end

	-- SOUTH: STAGE --------------------------------------------------------------------------
	b.block(V(36, 3, 12), V(0, 1.5, 55), C.Stone)
	b.ramp(V(0, 0, 44), V(0, 0, 1), 5, 3, 16, C.Stone)
	b.decor(function()
		accent(b, b.block(V(36.4, 0.3, 12.4), V(0, 3.05, 55), P.AccentA))
		for _, x in ipairs({ -15, 15 }) do
			b.block(V(4, 5, 3), V(x, 5.5, 58), C.Dark) -- speakers
			b.block(V(3.4, 3, 2.6), V(x, 9.5, 58), C.Dark)
			b.cylinder(0.2, 2.4, nil, C.Metal, nil, CFrame.new(x, 5.5, 56.4) * CFrame.Angles(0, rad(90), 0))
			b.cylinder(0.2, 1.6, nil, C.Metal, nil, CFrame.new(x, 9.5, 56.6) * CFrame.Angles(0, rad(90), 0))
		end
		for x = -12, 12, 6 do -- light rig hanging from the ceiling
			b.block(V(0.15, 4, 0.15), V(x, WALL_H - 2, 51), C.Metal)
			b.block(V(1.2, 1.4, 1.2), V(x, WALL_H - 4.6, 51), C.Dark)
			light(neon(b, b.block(V(0.9, 0.3, 0.9), V(x, WALL_H - 5.4, 51), x % 12 == 0 and P.AccentA or P.AccentB)), x % 12 == 0 and P.AccentA or P.AccentB, 20, 1)
		end
		b.block(V(30, 0.5, 0.5), V(0, WALL_H - 4, 51), C.Metal)
	end)
	local title = sign(model, V(30, 9, 1), CFrame.new(0, 14, R - 2.2), "", nil)
	title:FindFirstChildOfClass("SurfaceGui"):Destroy()
	Logo.OnPart(title, Enum.NormalId.Front, {
		Layout = "Inline",
		Color = P.UIText,
		Accent = P.AccentA,
		Stroke = 14,
		Subtitle = ("1V1 SNIPER ARENA  -  FIRST TO %d"):format(Config.Match.RoundsToWin),
	}, 40)

	-- NORTH-EAST: INDOOR GARDEN ------------------------------------------------------------
	plant(b, polar(52, 55), 1)
	plant(b, polar(56, 66), 0.85)
	b.cylinder(0.8, 12, polar(50, 28, 0.4), C.Stone) -- pond
	b.decor(function()
		b.material(b.cylinder(0.3, 10.4, polar(50, 28, 0.75), C.Water), Enum.Material.SmoothPlastic, 0.3)
		b.cylinder(0.12, 2, polar(49, 26, 0.95), C.Foliage)
		b.cylinder(0.12, 1.6, polar(52, 31, 0.95), C.Foliage)
		for k = 0, 5 do
			local pos = polar(50, 28) + V(math.cos(k * 1.05) * 6.4, 0.6, math.sin(k * 1.05) * 6.4)
			b.ball(1.4 + (k % 2) * 0.6, pos, C.Concrete) -- rocks
		end
	end)
	bench(b, facingIn(44, 40, 0))

	-- NORTH-WEST: PLAYGROUND PORTAL -----------------------------------------------------------
	local portalDeg = 315
	local portalBase = polar(52, portalDeg, 0)
	local facing = -outward(portalDeg)
	local across = V(-facing.Z, 0, facing.X)
	b.cylinder(1, 14, portalBase + V(0, 0.5, 0), C.Stone)
	b.decor(function()
		accent(b, b.cylinder(0.12, 14.4, portalBase + V(0, 1.02, 0), P.AccentA))
		local centre = portalBase + V(0, 7.5, 0)
		for k = 0, 23 do
			local a = k / 24 * math.pi * 2
			local pos = centre + across * math.cos(a) * 6 + V(0, math.sin(a) * 6, 0)
			local tangent = across * -math.sin(a) + V(0, math.cos(a), 0)
			local grow = k % 2 == 0 and 0 or 0.08
			b.part(V(1.3 + grow, 1.3 + grow, 1.9), CFrame.lookAt(pos, pos + tangent), k % 2 == 0 and C.BuildingA or C.Trim)
		end
		local disc = b.cylinder(0.2, 11.2, nil, P.AccentA, nil, CFrame.lookAt(centre, centre + facing) * CFrame.Angles(0, rad(90), 0))
		light(neon(b, disc), P.AccentA, 20, 1.2)
		for _, part in ipairs(disc) do
			part.Transparency = 0.55
		end
	end)
	sign(model, V(10, 2.2, 0.4), CFrame.lookAt(portalBase + facing * 5.5 + V(0, 2.2, 0), portalBase + facing * 12 + V(0, 2.2, 0)), "PLAYGROUND  [G]", nil)

	-- SOUTH-EAST: PARKOUR -----------------------------------------------------------------------
	local pk = function(r, deg, y)
		return polar(r, deg, y)
	end
	b.ramp(pk(44, 125), outward(125), 6, 3, 6, P.AccentB)
	b.part(V(6, 3, 6), CFrame.lookAt(pk(53, 125, 1.5), pk(53, 125, 1.5) + outward(125)), P.AccentA)
	b.part(V(6, 6, 6), CFrame.lookAt(pk(53, 140, 3), pk(53, 140, 3) + outward(140)), P.Mid)
	b.part(V(6, 9, 6), CFrame.lookAt(pk(55, 155, 4.5), pk(55, 155, 4.5) + outward(155)), P.AccentA)
	b.decor(function()
		for _, info in ipairs({ { 53, 125, 3 }, { 53, 140, 6 }, { 55, 155, 9 } }) do
			local pos = pk(info[1], info[2], info[3] + 0.1)
			accent(b, b.part(V(6.2, 0.25, 6.2), CFrame.lookAt(pos, pos + outward(info[2])), P.AccentA))
		end
	end)

	-- SOUTH-WEST: WALL-RUN WALL + LOW CEILING ----------------------------------------------------
	local wallDeg = 225
	local wallCf = facingIn(50, wallDeg, 7) * CFrame.Angles(0, rad(90), 0)
	b.part(V(24, 14, 1.4), wallCf, P.Light)
	b.decor(function()
		accent(b, b.part(V(24.2, 0.4, 1.6), wallCf * CFrame.new(0, 7.1, 0), P.AccentA))
		for x = -10, 10, 4 do
			b.part(V(0.5, 12, 1.5), wallCf * CFrame.new(x, 0, 0), C.Stone)
		end
	end)
	local ceil = polar(42, 245, 14)
	b.part(V(14, 1.2, 10), CFrame.lookAt(ceil, ceil + outward(245)), P.Mid)
	for _, dx in ipairs({ -6.2, 6.2 }) do
		for _, dz in ipairs({ -4.2, 4.2 }) do
			local post = CFrame.lookAt(ceil, ceil + outward(245)) * CFrame.new(dx, -7, dz)
			b.part(V(0.9, 13.4, 0.9), post, C.Metal)
		end
	end

	-- SHOOTING RANGE (north, through the tunnel) --------------------------------------------
	local rangeStart = -70
	b.block(V(64, 4, 344), V(0, -2, rangeStart - 172), P.Snow)
	b.block(V(2, 8, 344), V(32, 4, rangeStart - 172), P.Light, "X")
	b.block(V(64, 46, 4), V(0, 23, rangeStart - 346), P.Light)
	b.decor(function()
		for _, z in ipairs({ -120, -170, -270, -370 }) do
			b.block(V(60, 0.1, 1), V(0, 0.05, z), P.Mid)
		end
		neon(b, b.block(V(2.4, 0.5, 344), V(32, 8.25, rangeStart - 172), P.AccentA, "X"))
	end)
	b.block(V(16, 20, 10), V(12, 10, -300), P.AccentA)
	b.block(V(8, 5, 3), V(-8, 2.5, -150), P.AccentA)
	b.block(V(6, 8, 3), V(14, 4, -215), P.Mid)
	b.block(V(10, 4, 3), V(-6, 2, -330), P.AccentA)

	model.Parent = workspace
	return {
		Model = model,
		SpawnCFrame = function()
			local angle = math.random() * math.pi * 2
			local radius = 10.5 + math.random() * 7.5 -- outside the monument's pool
			local offset = Vector3.new(math.cos(angle) * radius, pitY + 3.5, math.sin(angle) * radius)
			return CFrame.lookAt(offset, Vector3.new(offset.X * 2, pitY + 3.5, offset.Z * 2))
		end,
		KillY = -60,
		CrateAltar = altar,
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
