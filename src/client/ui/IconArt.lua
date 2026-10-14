--[[
	IconArt.lua  (Client.ui.IconArt)
	Hand-made art for every power-up icon, drawn by Icons.lua out of plain
	GuiObjects (no image assets).

	IconArt[powerUpId] = a list of shapes. Coordinates and sizes are in icon
	units: 0-100 across the whole tile (50, 50 is the centre).

	SHAPES
		{ "Rect",   x, y, w, h, rotationDeg }   centre x/y, rotated about its centre
		{ "Circle", x, y, diameter }
		{ "Ring",   x, y, outerDiameter, thickness }
		{ "Clip",   x, y, w, h, Kids = { shapes } }   only shows the part of
		            its Kids inside the box (kids use the same icon units)
		{ "Glow",   x, y, diameter }            soft translucent light (C = colour)
		"BREAK"     starts a new layer: everything after it gets its own
		            shadow + outline drawn on top of what came before
	Optional keys on a shape
		C = colour      Color3, or a token: "W" white, "A" tile colour,
		                "L" light tile colour, "M" mid-dark tile colour,
		                "D" dark outline ink, "K" near-black
		G = { c1, c2, rot }  gradient (top -> bottom by default)
		T = 0.5         transparency
		R = 0.5         Rect corner rounding, 0-0.5 of the short side (default 0.12)
		Flat = true     no automatic top-lit shading
		O = false       no outline (and no shadow) for this shape
		NoShadow = true no drop shadow
		S = { colour, thickness, transparency }   UIStroke, big icons only
		Big = true      only drawn on icons >= 36px (fine detail)
		Small = true    only drawn on icons < 36px (simplified stand-ins)
	Options on the whole entry
		Tile = Color3     override the tile colour (default def.IconColor)
		Ink = Color3      override the outline colour
		Outline = 3.2     outline thickness (0 = none)
		Shadow = 3.4      drop shadow offset (0 = none)

	ADDING ART FOR A NEW POWER-UP
	Add `IconArt.MyId = art(...)` at the bottom using the helpers below
	(bar, poly, bullet, twinkle, chevron, ...). Power-ups without an entry
	still get the nicer tile, drawing the old `Icon` list from PowerUps.lua.
]]

local IconArt = {}

----------------------------------------------------------------------------
-- palette
----------------------------------------------------------------------------
local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local GOLD = rgb(255, 206, 84)
local GOLD_DARK = rgb(214, 140, 40)
local LEAD = rgb(236, 240, 248)
local STEEL = rgb(186, 198, 214)
local STEEL_DARK = rgb(112, 124, 142)
local RED = rgb(240, 56, 72)
local RED_DARK = rgb(160, 20, 44)
local FIRE = rgb(255, 140, 40)
local YELLOW = rgb(255, 236, 90)
local CYAN = rgb(130, 240, 255)
local SKY = rgb(150, 220, 255)
local PINK = rgb(255, 120, 200)
local PURPLE = rgb(190, 150, 255)
local GREEN = rgb(110, 230, 120)
local WALL = rgb(70, 76, 96)
local WALL_LIGHT = rgb(110, 118, 140)

----------------------------------------------------------------------------
-- helpers (all return shape lists or single shapes)
----------------------------------------------------------------------------
local function with(shape, props)
	for k, v in pairs(props or {}) do
		shape[k] = v
	end
	return shape
end

-- Concatenates shapes and lists of shapes into one list.
local function join(...)
	local out = {}
	for _, item in ipairs({ ... }) do
		if type(item) == "string" or (type(item) == "table" and type(item[1]) == "string" and item[1] ~= "BREAK") then
			table.insert(out, item)
		elseif type(item) == "table" then
			for _, s in ipairs(item) do
				table.insert(out, s)
			end
		end
	end
	return out
end

-- Builds an art entry: art({ options }, shapes...)
local function art(options, ...)
	local list = join(...)
	for k, v in pairs(options or {}) do
		list[k] = v
	end
	return list
end

-- A round-capped line from (x1, y1) to (x2, y2).
local function bar(x1, y1, x2, y2, th, props)
	local dx, dy = x2 - x1, y2 - y1
	local len = math.sqrt(dx * dx + dy * dy)
	return with({ "Rect", (x1 + x2) / 2, (y1 + y2) / 2, len + th, th, math.deg(math.atan2(dy, dx)), R = 0.5 }, props)
end

-- A round-capped polyline through { {x, y}, ... }.
local function poly(points, th, props)
	local out = {}
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		table.insert(out, bar(a[1], a[2], b[1], b[2], th, props and table.clone(props)))
	end
	return out
end

-- Points along a circular arc (degrees, 0 = right, clockwise on screen).
local function arcPoints(cx, cy, r, fromDeg, toDeg, steps)
	local pts = {}
	for i = 0, steps do
		local a = math.rad(fromDeg + (toDeg - fromDeg) * i / steps)
		table.insert(pts, { cx + math.cos(a) * r, cy + math.sin(a) * r })
	end
	return pts
end

-- Point at distance `d` from (x, y) in direction `deg`.
local function along(x, y, deg, d)
	local a = math.rad(deg)
	return x + math.cos(a) * d, y + math.sin(a) * d
end

-- Two-bar arrow head with its tip at (x, y), pointing in direction `deg`.
local function arrowHead(x, y, deg, len, th, props)
	local ax, ay = along(x, y, deg + 140, len)
	local bx, by = along(x, y, deg - 140, len)
	return {
		bar(x, y, ax, ay, th, props and table.clone(props)),
		bar(x, y, bx, by, th, props and table.clone(props)),
	}
end

-- A rifle bullet: back of the casing at (x, y), pointing `deg`.
local function bullet(x, y, deg, len, th, props)
	props = props or {}
	local nx, ny = along(x, y, deg, len * 0.72)
	local cx, cy = along(x, y, deg, len * 0.31)
	local rx, ry = along(x, y, deg, len * 0.05)
	local out = {
		with({ "Rect", nx, ny, len * 0.56, th * 0.9, deg, R = 0.5, C = props.Nose or LEAD, T = props.T }),
		with({ "Rect", cx, cy, len * 0.62, th, deg, R = 0.14, C = props.Casing or GOLD, T = props.T }),
	}
	if not props.T then
		table.insert(out, { "Rect", rx, ry, len * 0.06, th * 1.05, deg, R = 0.3, C = props.Rim or GOLD_DARK, Big = true, O = false })
	end
	return out
end

-- Four-point twinkle.
local function twinkle(x, y, s, props)
	return {
		with({ "Rect", x, y, s * 0.12, s, 0, R = 0.5, C = "W", O = false }, props and table.clone(props)),
		with({ "Rect", x, y, s * 0.75, s * 0.12, 0, R = 0.5, C = "W", O = false }, props and table.clone(props)),
		with({ "Rect", x, y, s * 0.4, s * 0.4, 45, R = 0.1, C = "W", O = false }, props and table.clone(props)),
	}
end

-- A "^" chevron with its tip at (x, y), pointing `deg` (-90 = up).
local function chevron(x, y, deg, len, th, props)
	return arrowHead(x, y, deg, len, th, props)
end

-- Moves and scales shapes: (x, y) -> (x * s + dx, y * s + dy).
local function xf(list, dx, dy, s)
	local out = {}
	for _, shape in ipairs(list) do
		if type(shape) ~= "table" then
			table.insert(out, shape)
			continue
		end
		local c = table.clone(shape)
		c[2] = c[2] * s + dx
		c[3] = c[3] * s + dy
		if c[1] == "Rect" or c[1] == "Clip" then
			c[4] = c[4] * s
			c[5] = c[5] * s
		elseif c[1] == "Ring" then
			c[4] = c[4] * s
			c[5] = c[5] * s
		else
			c[4] = c[4] * s
		end
		if c.Kids then
			c.Kids = xf(c.Kids, dx, dy, s)
		end
		table.insert(out, c)
	end
	return out
end

-- Sets props on every shape in a list (returns a copy).
local function paint(list, props)
	local out = {}
	for _, shape in ipairs(list) do
		if type(shape) == "table" then
			local c = table.clone(shape)
			for k, v in pairs(props) do
				c[k] = v
			end
			table.insert(out, c)
		else
			table.insert(out, shape)
		end
	end
	return out
end

-- Running pictogram in a 100x100 box (facing right).
local function runner(color)
	local th = 11
	local p = { C = color or "W" }
	return join(
		poly({ { 56, 36 }, { 40, 46 }, { 30, 40 } }, 9, p), -- back arm
		poly({ { 46, 60 }, { 34, 72 }, { 18, 72 } }, th, p), -- back leg
		bar(57, 34, 46, 60, 14, p), -- torso
		poly({ { 46, 60 }, { 62, 70 }, { 58, 88 } }, th, p), -- front leg
		poly({ { 56, 36 }, { 70, 44 }, { 80, 36 } }, 9, p), -- front arm
		{ "Circle", 66, 18, 17, C = p.C } -- head
	)
end

-- Standing pictogram (head + shoulders + body) in a 100x100 box.
local function figure(color, props)
	local p = with({ C = color or "W" }, props)
	return {
		with({ "Rect", 50, 70, 40, 46, 0, R = 0.45 }, table.clone(p)),
		with({ "Circle", 50, 30, 26 }, table.clone(p)),
	}
end

-- Heart centred at (x, y), width ~ s.
local function heart(x, y, s, props)
	local r = s * 0.3
	return {
		with({ "Circle", x - r * 0.78, y - r * 0.35, r * 2 }, props and table.clone(props)),
		with({ "Circle", x + r * 0.78, y - r * 0.35, r * 2 }, props and table.clone(props)),
		with({ "Rect", x, y + r * 0.42, r * 2.05, r * 2.05, 45, R = 0.1 }, props and table.clone(props)),
	}
end

-- A teardrop pointing up, centred on its round part.
local function drop(x, y, d, props)
	return {
		with({ "Rect", x, y - d * 0.2, d * 0.7, d * 0.7, 45, R = 0.12 }, props and table.clone(props)),
		with({ "Circle", x, y, d }, props and table.clone(props)),
	}
end

-- Brick wall slab.
local function wall(x, y, w, h, props)
	props = props or {}
	local out = {
		with({ "Rect", x, y, w, h, 0, R = 0.12, C = props.C or WALL_LIGHT, T = props.T }, {}),
	}
	local rows = props.Rows or 4
	for i = 1, rows - 1 do
		local ly = y - h / 2 + h * i / rows
		table.insert(out, { "Rect", x, ly, w - 2, 1.8, 0, R = 0.5, C = WALL, O = false, NoShadow = true, Big = true, Flat = true, T = props.T })
		local off = (i % 2 == 0) and -w * 0.18 or w * 0.18
		table.insert(out, {
			"Rect",
			x + off,
			ly - h / rows / 2,
			1.8,
			h / rows - 2,
			0,
			R = 0.5,
			C = WALL,
			O = false,
			NoShadow = true,
			Big = true,
			Flat = true,
			T = props.T,
		})
	end
	return out
end

-- Crosshair reticle.
local function crosshair(x, y, d, th, props)
	local p = props or {}
	local r = d / 2
	local gap = d * 0.16
	return join(
		with({ "Ring", x, y, d, th }, table.clone(p)),
		bar(x, y - r - th * 0.6, x, y - gap, th, table.clone(p)),
		bar(x, y + gap, x, y + r + th * 0.6, th, table.clone(p)),
		bar(x - r - th * 0.6, y, x - gap, y, th, table.clone(p)),
		bar(x + gap, y, x + r + th * 0.6, y, th, table.clone(p))
	)
end


-- Rotates shapes about (cx, cy) by `deg` (clockwise). Clip boxes can't
-- rotate, so don't pass lists containing "Clip" here.
local function spin(list, cx, cy, deg)
	local a = math.rad(deg)
	local cs, sn = math.cos(a), math.sin(a)
	local out = {}
	for _, shape in ipairs(list) do
		if type(shape) ~= "table" then
			table.insert(out, shape)
			continue
		end
		local c = table.clone(shape)
		local dx, dy = c[2] - cx, c[3] - cy
		c[2] = cx + dx * cs - dy * sn
		c[3] = cy + dx * sn + dy * cs
		if c[1] == "Rect" then
			c[6] = (c[6] or 0) + deg
		end
		table.insert(out, c)
	end
	return out
end

-- Impact burst: `n` short rays around (x, y).
local function burst(x, y, inner, outer, n, th, props, startDeg)
	local out = {}
	for i = 0, n - 1 do
		local deg = (startDeg or 0) + i * 360 / n
		local ax, ay = along(x, y, deg, inner)
		local bx, by = along(x, y, deg, outer)
		table.insert(out, bar(ax, ay, bx, by, th, props and table.clone(props)))
	end
	return out
end

-- Eight-point star (two overlapping squares).
local function star8(x, y, s, props, rot)
	rot = rot or 0
	return {
		with({ "Rect", x, y, s, s, rot, R = 0.08 }, props and table.clone(props)),
		with({ "Rect", x, y, s, s, rot + 45, R = 0.08 }, props and table.clone(props)),
	}
end

----------------------------------------------------------------------------
-- more shared pieces
----------------------------------------------------------------------------
local WOOD = rgb(176, 112, 64)
local GRIP = rgb(58, 52, 60)
local ACID = rgb(200, 255, 70)
local ICE = rgb(220, 246, 255)

-- Upright combat knife in a 100x100 box (tip at the top).
local function knife(props)
	props = props or {}
	return {
		{ "Rect", 50, 14, 11.3, 11.3, 45, R = 0.05, C = props.Blade or STEEL },
		{ "Rect", 50, 34, 16, 40, 0, R = 0.12, C = props.Blade or STEEL },
		{ "Rect", 46, 32, 3, 32, 0, R = 0.5, C = "W", O = false, NoShadow = true, Flat = true, Big = true },
		{ "Rect", 50, 57, 32, 8, 0, R = 0.4, C = rgb(80, 86, 104) },
		{ "Rect", 50, 73, 13, 26, 0, R = 0.3, C = props.Grip or GRIP },
		{ "Circle", 50, 88, 13, C = rgb(80, 86, 104) },
	}
end

-- Heater shield in a 100x100 box.
local function shieldShape(props)
	return {
		with({ "Rect", 50, 34, 56, 36, 0, R = 0.18 }, props and table.clone(props)),
		with({ "Rect", 50, 54, 39.6, 39.6, 45, R = 0.1 }, props and table.clone(props)),
	}
end

-- Sliding pictogram (feet first, leaning back) in a 100x100 box.
local function slider(color)
	local p = { C = color or "W" }
	return join(
		poly({ { 40, 52 }, { 26, 62 }, { 22, 74 } }, 9, p), -- back arm (hand on floor)
		bar(42, 50, 60, 68, 14, p), -- torso
		poly({ { 60, 68 }, { 76, 64 }, { 90, 72 } }, 11, p), -- top leg
		poly({ { 60, 68 }, { 72, 76 }, { 88, 80 } }, 11, p), -- bottom leg
		poly({ { 44, 50 }, { 58, 46 }, { 66, 38 } }, 9, p), -- front arm
		{ "Circle", 34, 40, 17, C = p.C } -- head
	)
end

-- Circular arrow (3/4 ring, gap in the top-right, or top-left if `ccw`).
-- The two clip boxes overlap a little so no seam shows.
local function cycleArrow(x, y, d, th, color, ccw)
	color = color or "W"
	local ring = { "Ring", x, y, d, th, C = color }
	local r = d / 2
	local m = ccw and -1 or 1
	local mid = r - th / 2 -- centre line radius
	return join(
		{ "Clip", x - m * (r / 2 - 1), y, r + 4, d + 4, Kids = { ring } },
		{ "Clip", x + m * (r / 2 + 1), y + r / 2, r + 4, r + 4, Kids = { ring } },
		arrowHead(x + m * (th * 1.6), y - mid, ccw and 180 or 0, th * 1.7, th * 0.9, { C = color })
	)
end

----------------------------------------------------------------------------
-- BULLETS
----------------------------------------------------------------------------

-- Ghost Round: a bullet phasing through a brick wall.
IconArt.GhostRound = art(
	{},
	wall(54, 50, 20, 74, { Rows = 5 }),
	"BREAK",
	bullet(4, 52, 0, 46, 18, { T = 0.5, Casing = PURPLE, Nose = PURPLE }),
	bar(8, 34, 30, 34, 4, { T = 0.45, O = false }),
	bar(4, 70, 26, 70, 4, { T = 0.45, O = false }),
	"BREAK",
	bullet(50, 52, 0, 42, 18)
)

-- Ricochet: a bullet trail bouncing off the floor.
IconArt.Ricochet = art(
	{},
	{ "Rect", 50, 84, 78, 9, 0, R = 0.5, C = WALL_LIGHT },
	"BREAK",
	poly({ { 14, 20 }, { 42, 74 } }, 9, { C = "W" }),
	poly({ { 42, 74 }, { 76, 28 } }, 9, { C = "W" }),
	arrowHead(80, 23, -54, 18, 9),
	"BREAK",
	burst(42, 76, 10, 20, 5, 5, { C = YELLOW }, 180),
	{ "Circle", 42, 76, 11, C = YELLOW }
)

-- Split Shot: three bullets fanning out of one muzzle flash.
IconArt.SplitShot = art(
	{},
	star8(16, 52, 22, { C = YELLOW }, 0),
	"BREAK",
	bullet(32, 40, -36, 40, 14),
	bullet(32, 64, 36, 40, 14),
	"BREAK",
	bullet(34, 52, 0, 48, 16)
)

-- Homing Rounds: a bullet curving into a target.
local homingTrail = {}
for i, pt in ipairs(arcPoints(60, 90, 44, 186, 240, 5)) do
	table.insert(homingTrail, { "Circle", pt[1], pt[2], 5 + i * 1.3, T = 0.55 - i * 0.07, O = false })
end
IconArt.HomingRounds = art(
	{},
	crosshair(64, 36, 36, 6, { C = "W" }),
	{ "Circle", 64, 36, 10, C = RED },
	"BREAK",
	homingTrail,
	bullet(34, 60, -40, 36, 14)
)

-- Explosive Rounds: a cartoon blast.
IconArt.ExplosiveRounds = art(
	{},
	star8(50, 50, 62, { C = FIRE }, 10),
	"BREAK",
	star8(50, 50, 40, { C = YELLOW }, 32),
	{ "Circle", 50, 50, 22, C = "W", O = false },
	{ "Circle", 18, 22, 8, C = FIRE },
	{ "Circle", 84, 78, 7, C = FIRE },
	{ "Circle", 82, 24, 5, C = YELLOW, Big = true }
)

-- Shrapnel: an impact on a wall spraying jagged shards.
IconArt.Shrapnel = art(
	{},
	wall(14, 50, 16, 84, { Rows = 5 }),
	"BREAK",
	bar(30, 44, 58, 26, 4, { C = "W", T = 0.4, O = false }),
	bar(30, 54, 66, 58, 4, { C = "W", T = 0.4, O = false }),
	bar(28, 62, 50, 82, 4, { C = "W", T = 0.4, O = false }),
	star8(26, 52, 20, { C = YELLOW }, 15),
	"BREAK",
	{ "Rect", 66, 24, 18, 14, 28, R = 0.08, C = STEEL },
	{ "Rect", 78, 58, 20, 15, -18, R = 0.08, C = STEEL },
	{ "Rect", 56, 84, 13, 11, 52, R = 0.08, C = STEEL }
)

-- Static Charge: a lightning bolt crackling off a passing bullet.
IconArt.StaticCharge = art(
	{},
	poly({ { 62, 14 }, { 38, 52 }, { 62, 50 }, { 38, 86 } }, 13, { C = YELLOW }),
	"BREAK",
	bar(18, 34, 28, 40, 5, { C = "W", Big = true }),
	bar(74, 64, 84, 70, 5, { C = "W", Big = true }),
	bar(74, 36, 86, 32, 5, { C = "W" }),
	bar(16, 66, 26, 62, 5, { C = "W" })
)

-- Pinball: a shiny ball bouncing, damage going up.
IconArt.Pinball = art(
	{},
	poly({ { 10, 28 }, { 28, 66 }, { 44, 40 } }, 6, { C = "W", T = 0.35 }),
	"BREAK",
	{ "Circle", 56, 62, 40, G = { rgb(250, 252, 255), STEEL_DARK } },
	{ "Circle", 50, 54, 12, C = "W", O = false, Flat = true, T = 0.1 },
	"BREAK",
	bar(78, 14, 78, 38, 9, { C = YELLOW }),
	bar(66, 26, 90, 26, 9, { C = YELLOW })
)

-- Momentum Rounds: a bullet with speed streaks.
IconArt.MomentumRounds = art(
	{},
	bar(8, 34, 30, 34, 7, { C = "W", T = 0.2 }),
	bar(4, 52, 28, 52, 7, { C = "W", T = 0.2 }),
	bar(10, 70, 32, 70, 7, { C = "W", T = 0.2 }),
	"BREAK",
	bullet(34, 52, 0, 56, 22)
)

----------------------------------------------------------------------------
-- DAMAGE
----------------------------------------------------------------------------

-- Sky Sniper: a crosshair above the clouds.
IconArt.SkySniper = art(
	{},
	crosshair(50, 38, 44, 7, { C = "W" }),
	{ "Circle", 50, 38, 10, C = RED },
	"BREAK",
	{ "Circle", 32, 74, 26 },
	{ "Circle", 52, 66, 32 },
	{ "Circle", 72, 74, 24 },
	{ "Rect", 52, 80, 64, 16, 0, R = 0.5 }
)

-- Glass Cannon: a cracked glass cannon.
IconArt.GlassCannon = art(
	{ Tile = rgb(120, 180, 235) },
	bar(28, 64, 72, 30, 24, { R = 0.25, G = { rgb(220, 245, 255), rgb(110, 190, 240) }, T = 0.05 }),
	bar(74, 28, 80, 24, 30, { R = 0.25, G = { rgb(220, 245, 255), rgb(110, 190, 240) } }),
	{ "Circle", 24, 68, 18, G = { rgb(220, 245, 255), rgb(110, 190, 240) } },
	"BREAK",
	{ "Circle", 40, 72, 30, C = STEEL },
	{ "Circle", 40, 72, 10, C = STEEL_DARK, O = false },
	"BREAK",
	poly({ { 44, 42 }, { 52, 48 }, { 48, 54 }, { 56, 58 } }, 3, { C = "D", O = false, NoShadow = true, Big = true }),
	bar(34, 54, 62, 32, 4, { C = "W", T = 0.2, O = false, NoShadow = true })
)

-- Marked: an enemy silhouette in a red target lock.
IconArt.Marked = art(
	{},
	{ "Glow", 50, 54, 76, C = RED, T = 0.8 },
	xf(figure("W"), 14, 22, 0.72),
	"BREAK",
	crosshair(50, 44, 40, 6, { C = RED }),
	{ "Rect", 50, 10, 9, 9, 45, R = 0.1, C = RED }
)

-- Hair Trigger: a "re-chamber" arrow charged with lightning.
IconArt.HairTrigger = art(
	{},
	cycleArrow(50, 54, 62, 10, "W"),
	"BREAK",
	poly({ { 56, 34 }, { 44, 56 }, { 58, 54 }, { 46, 76 } }, 8, { C = YELLOW }),
	"BREAK",
	twinkle(82, 50, 14, { C = "W", Big = true })
)

-- Vampire: fangs and a drop of blood.
IconArt.Vampire = art(
	{},
	{ "Rect", 50, 40, 80, 34, 0, R = 0.5, C = RED },
	{ "Rect", 50, 42, 62, 16, 0, R = 0.5, C = "K", O = false },
	{ "Rect", 50, 36, 56, 6, 0, R = 0.3, C = "W", O = false, Flat = true },
	"BREAK",
	{ "Rect", 33, 46, 12, 20, 0, R = 0.25 },
	{ "Rect", 33, 56, 8.5, 8.5, 45, R = 0.05 },
	{ "Rect", 67, 46, 12, 20, 0, R = 0.25 },
	{ "Rect", 67, 56, 8.5, 8.5, 45, R = 0.05 },
	"BREAK",
	drop(67, 80, 14, { C = RED })
)

----------------------------------------------------------------------------
-- MOVEMENT
----------------------------------------------------------------------------

-- Double Jump: two chevrons climbing off the ground.
IconArt.DoubleJump = art(
	{},
	{ "Rect", 50, 86, 56, 7, 0, R = 0.5, C = "W", T = 0.3 },
	"BREAK",
	chevron(50, 48, -90, 30, 12, { C = "W", T = 0.35 }),
	"BREAK",
	chevron(50, 22, -90, 30, 12, { C = "W" })
)

-- Wall Runner: a runner sprinting along a wall.
IconArt.WallRunner = art(
	{},
	wall(13, 50, 16, 90, { Rows = 6 }),
	"BREAK",
	spin(xf(runner("W"), 24, 14, 0.72), 58, 50, -30),
	bar(40, 90, 56, 90, 5, { C = "W", T = 0.4, O = false, Big = true })
)

-- Adrenaline: a syringe.
IconArt.Adrenaline = art(
	{},
	bar(40, 60, 80, 20, 3.5, { C = STEEL }),
	"BREAK",
	bar(26, 74, 58, 42, 20, { R = 0.2 }),
	bar(32, 68, 52, 48, 12, { R = 0.3, C = RED, O = false }),
	bar(22, 62, 36, 76, 6, { C = STEEL_DARK }),
	bar(26, 74, 12, 88, 6, { C = STEEL_DARK }),
	bar(6, 82, 18, 94, 7, { C = STEEL_DARK }),
	"BREAK",
	bar(70, 66, 84, 66, 5, { C = "W", T = 0.3, O = false }),
	bar(76, 76, 88, 76, 5, { C = "W", T = 0.3, O = false })
)

-- Featherweight: a drifting feather.
IconArt.Featherweight = art(
	{},
	{ "Rect", 54, 44, 32, 70, 38, R = 0.5 },
	"BREAK",
	bar(26, 86, 70, 16, 4, { C = "M", O = false }),
	bar(54, 42, 68, 42, 2.5, { C = "M", O = false, NoShadow = true, Big = true }),
	bar(46, 54, 62, 58, 2.5, { C = "M", O = false, NoShadow = true, Big = true }),
	bar(52, 44, 40, 34, 2.5, { C = "M", O = false, NoShadow = true, Big = true }),
	bar(44, 56, 34, 50, 2.5, { C = "M", O = false, NoShadow = true, Big = true }),
	bar(34, 72, 24, 70, 4, { C = "W" }),
	bar(36, 76, 30, 82, 4, { C = "W" }),
	"BREAK",
	bar(18, 30, 18, 44, 4, { C = "W", T = 0.4, O = false }),
	bar(84, 54, 84, 70, 4, { C = "W", T = 0.4, O = false })
)

-- Spring Legs: a coil spring with an up arrow.
IconArt.SpringLegs = art(
	{},
	{ "Rect", 50, 72, 40, 6, 16, R = 0.5, C = STEEL_DARK },
	{ "Rect", 50, 60, 40, 6, 16, R = 0.5, C = STEEL_DARK },
	{ "Rect", 50, 48, 40, 6, 16, R = 0.5, C = STEEL_DARK },
	"BREAK",
	{ "Rect", 50, 88, 50, 8, 0, R = 0.4, C = rgb(80, 86, 104) },
	{ "Rect", 50, 78, 40, 7, -16, R = 0.5 },
	{ "Rect", 50, 66, 40, 7, -16, R = 0.5 },
	{ "Rect", 50, 54, 40, 7, -16, R = 0.5 },
	{ "Rect", 50, 42, 40, 7, -16, R = 0.5 },
	{ "Rect", 50, 34, 50, 8, 0, R = 0.4, C = rgb(80, 86, 104) },
	"BREAK",
	chevron(50, 8, -90, 18, 9, { C = YELLOW })
)

-- Blink: a faded runner teleporting into a solid one.
IconArt.Blink = art(
	{},
	paint(xf(runner(), 0, 22, 0.56), { T = 0.6, O = false, C = "L" }),
	bar(36, 56, 44, 56, 5, { C = "W", T = 0.3, O = false }),
	bar(50, 56, 58, 56, 5, { C = "W", T = 0.3, O = false }),
	"BREAK",
	xf(runner(), 42, 22, 0.56),
	"BREAK",
	twinkle(40, 24, 18, { C = "W" }),
	twinkle(88, 66, 12, { C = "W", Big = true })
)

-- Grapple Hook: a three-prong hook with its rope.
local hook = join(
	bar(50, 22, 50, 70, 8),
	poly({ { 50, 24 }, { 36, 30 }, { 30, 44 } }, 8),
	poly({ { 50, 24 }, { 64, 30 }, { 70, 44 } }, 8),
	bar(50, 22, 50, 10, 8),
	{ "Ring", 50, 76, 16, 5 }
)
IconArt.GrappleHook = art(
	{},
	poly({ { 36, 64 }, { 28, 72 }, { 22, 70 }, { 12, 82 } }, 5, { C = rgb(220, 190, 140) }),
	"BREAK",
	spin(paint(hook, { C = STEEL }), 50, 50, 42)
)

-- Rocket Jump: a rocket taking off.
IconArt.RocketJump = art(
	{},
	{ "Circle", 50, 80, 18, C = FIRE },
	{ "Rect", 50, 88, 13, 13, 45, R = 0.1, C = FIRE },
	{ "Circle", 50, 78, 9, C = YELLOW, O = false },
	"BREAK",
	{ "Rect", 36, 62, 12, 22, -28, R = 0.3, C = RED },
	{ "Rect", 64, 62, 12, 22, 28, R = 0.3, C = RED },
	{ "Rect", 50, 42, 26, 52, 0, R = 0.5 },
	{ "Rect", 50, 62, 26, 14, 0, R = 0.2 },
	{ "Clip", 50, 23, 30, 12, Kids = { { "Rect", 50, 42, 26, 52, 0, R = 0.5, C = RED, O = false } } },
	{ "Circle", 50, 42, 12, C = CYAN, S = { "D", 1.5 } }
)

-- Phantom Step: a ghost leaving fading afterimages.
local function ghost(x, props)
	return paint({
		{ "Circle", x, 40, 42 },
		{ "Rect", x, 58, 42, 34, 0, R = 0.1 },
		{ "Circle", x - 14, 76, 14 },
		{ "Circle", x, 76, 14 },
		{ "Circle", x + 14, 76, 14 },
	}, props)
end
IconArt.PhantomDash = art(
	{},
	ghost(30, { T = 0.75, O = false }),
	ghost(44, { T = 0.5, O = false }),
	"BREAK",
	ghost(60, {}),
	{ "Rect", 53, 42, 7, 12, 0, R = 0.5, C = "K", O = false },
	{ "Rect", 67, 42, 7, 12, 0, R = 0.5, C = "K", O = false }
)

-- Magnetic Boots: a horseshoe magnet pulling up toward the ceiling.
IconArt.MagneticBoots = art(
	{},
	{ "Rect", 50, 9, 76, 6, 0, R = 0.5, C = "W", T = 0.35, O = false },
	bar(34, 22, 34, 16, 4, { C = "W", T = 0.3, O = false }),
	bar(66, 22, 66, 16, 4, { C = "W", T = 0.3, O = false }),
	"BREAK",
	{ "Clip", 50, 74, 60, 30, Kids = { { "Ring", 50, 58, 50, 16 } } },
	{ "Rect", 33, 50, 16, 28, 0, R = 0.05 },
	{ "Rect", 67, 50, 16, 28, 0, R = 0.05 },
	{ "Rect", 33, 32, 16, 12, 0, R = 0.15, C = STEEL },
	{ "Rect", 67, 32, 16, 12, 0, R = 0.15, C = STEEL }
)

-- Shockwave Landing: a slam with waves rippling out.
IconArt.ShockwaveLanding = art(
	{},
	{ "Clip", 50, 60, 96, 36, Kids = {
		{ "Ring", 50, 80, 86, 5, C = "W", T = 0.45 },
		{ "Ring", 50, 80, 58, 6, C = "W" },
	} },
	{ "Rect", 50, 84, 84, 8, 0, R = 0.5, C = "W" },
	"BREAK",
	bar(50, 10, 50, 50, 11, { C = YELLOW }),
	arrowHead(50, 60, 90, 20, 11, { C = YELLOW })
)

-- Bullet Time: a stopwatch whose hand is a bullet.
IconArt.BulletTime = art(
	{},
	{ "Rect", 50, 14, 16, 9, 0, R = 0.3, C = STEEL },
	{ "Rect", 50, 20, 7, 8, 0, R = 0.1, C = STEEL },
	{ "Rect", 76, 26, 8, 10, 45, R = 0.3, C = STEEL },
	{ "Circle", 50, 56, 64, C = "W" },
	"BREAK",
	{ "Circle", 50, 56, 48, C = rgb(255, 246, 220), O = false, Flat = true },
	bar(50, 36, 50, 38, 3, { C = STEEL_DARK, O = false, NoShadow = true }),
	bar(50, 74, 50, 76, 3, { C = STEEL_DARK, O = false, NoShadow = true }),
	bar(30, 56, 32, 56, 3, { C = STEEL_DARK, O = false, NoShadow = true }),
	bar(68, 56, 70, 56, 3, { C = STEEL_DARK, O = false, NoShadow = true }),
	"BREAK",
	bullet(46, 60, -50, 30, 9),
	{ "Circle", 50, 56, 7, C = "K", O = false }
)

-- Quickdraw: a rifle scope with fast-forward chevrons.
IconArt.Quickdraw = art(
	{},
	{ "Rect", 50, 40, 52, 13, 0, R = 0.3, C = rgb(70, 76, 92) },
	{ "Rect", 80, 40, 14, 24, 0, R = 0.25, C = rgb(70, 76, 92) },
	{ "Rect", 20, 40, 12, 19, 0, R = 0.25, C = rgb(70, 76, 92) },
	{ "Rect", 50, 30, 10, 10, 0, R = 0.2, C = rgb(90, 96, 114) },
	{ "Rect", 87, 40, 3, 18, 0, R = 0.5, C = CYAN, O = false },
	"BREAK",
	chevron(48, 72, 0, 18, 9, { C = "W" }),
	chevron(66, 72, 0, 18, 9, { C = "W" })
)

----------------------------------------------------------------------------
-- SURVIVAL / UTILITY
----------------------------------------------------------------------------

-- Thick Skin: a sturdy shield with a health cross.
IconArt.ThickSkin = art(
	{},
	{ "Rect", 50, 34, 56, 36, 0, R = 0.18 },
	{ "Rect", 50, 54, 39.6, 39.6, 45, R = 0.1 },
	"BREAK",
	{ "Rect", 50, 46, 10, 30, 0, R = 0.2, C = GREEN, O = false },
	{ "Rect", 50, 46, 30, 10, 0, R = 0.2, C = GREEN, O = false }
)

-- Second Wind: a winged heart (an extra life).
local wingL = {
	{ "Rect", 24, 38, 30, 10, 18, R = 0.5 },
	{ "Rect", 22, 48, 28, 10, 4, R = 0.5 },
	{ "Rect", 26, 58, 22, 10, -10, R = 0.5 },
}
local wingR = {}
for _, w in ipairs(wingL) do
	local c = table.clone(w)
	c[2] = 100 - c[2]
	c[6] = -c[6]
	table.insert(wingR, c)
end
IconArt.SecondWind = art(
	{},
	wingL,
	wingR,
	"BREAK",
	heart(50, 52, 46, { C = RED }),
	{ "Circle", 40, 42, 8, C = "W", O = false, T = 0.25, Flat = true }
)

-- Wallhack Pulse: an eye seeing through a wall.
IconArt.WallhackPulse = art(
	{},
	wall(50, 50, 78, 62, { Rows = 4, T = 0.35 }),
	{ "Ring", 50, 50, 90, 3, C = "W", T = 0.5, O = false, Big = true },
	"BREAK",
	{ "Rect", 50, 50, 66, 34, 0, R = 0.5 },
	{ "Circle", 50, 50, 26, C = CYAN, S = { "D", 1.5 } },
	{ "Circle", 50, 50, 11, C = "K", O = false },
	{ "Circle", 46, 46, 5, C = "W", O = false, Flat = true }
)

-- Decoy: you and your hologram.
local holo = paint(xf(figure(), 34, 18, 0.66), { C = "W", T = 0.45, O = false })
IconArt.Decoy = art(
	{},
	holo,
	{ "Rect", 67, 50, 32, 3, 0, R = 0.5, C = "A", O = false, NoShadow = true, Flat = true, Big = true },
	{ "Rect", 67, 62, 32, 3, 0, R = 0.5, C = "A", O = false, NoShadow = true, Flat = true, Big = true },
	{ "Rect", 67, 74, 32, 3, 0, R = 0.5, C = "A", O = false, NoShadow = true, Flat = true, Big = true },
	{ "Rect", 67, 88, 36, 5, 0, R = 0.5, C = "W", T = 0.2, O = false },
	"BREAK",
	xf(figure("W"), 0, 22, 0.62)
)

----------------------------------------------------------------------------
-- NEW BULLET MODS
----------------------------------------------------------------------------

-- Acid Rounds: a dripping bullet over a bubbling puddle.
IconArt.AcidRounds = art(
	{},
	{ "Rect", 50, 80, 76, 16, 0, R = 0.5, C = ACID },
	{ "Circle", 34, 72, 10, C = ACID },
	{ "Circle", 62, 70, 14, C = ACID },
	"BREAK",
	{ "Circle", 62, 70, 5, C = "W", O = false, T = 0.2, Flat = true },
	{ "Circle", 30, 80, 4, C = "W", O = false, T = 0.3, Flat = true, Big = true },
	bullet(16, 30, 18, 48, 15, { Casing = GOLD }),
	"BREAK",
	drop(66, 52, 9, { C = ACID })
)

-- Frost Rounds: a snowflake.
local flake = {}
for i = 0, 2 do
	local deg = i * 60 + 90
	local ax, ay = along(50, 50, deg, 34)
	local bx, by = along(50, 50, deg + 180, 34)
	table.insert(flake, bar(ax, ay, bx, by, 8, { C = ICE }))
	for _, sgn in ipairs({ 1, -1 }) do
		local tipx, tipy = along(50, 50, deg + (sgn > 0 and 0 or 180), 22)
		for _, side in ipairs({ 45, -45 }) do
			local ex, ey = along(tipx, tipy, deg + (sgn > 0 and 0 or 180) + 180 + side, -12)
			table.insert(flake, bar(tipx, tipy, ex, ey, 6, { C = ICE }))
		end
	end
end
IconArt.FrostRounds = art({}, flake, "BREAK", { "Rect", 50, 50, 12, 12, 45, R = 0.15, C = SKY })

-- Serrated Rounds: a saw-toothed blade drawing blood.
local saw = { { "Rect", 50, 40, 70, 16, 0, R = 0.25, C = STEEL } }
for i = 0, 5 do
	table.insert(saw, { "Rect", 22 + i * 11.2, 48, 10, 10, 45, R = 0.05, C = STEEL })
end
IconArt.SerratedRounds = art(
	{},
	spin(saw, 50, 44, -20),
	{ "Rect", 30, 40, 40, 3, -20, R = 0.5, C = "W", O = false, NoShadow = true, Flat = true, Big = true },
	"BREAK",
	drop(40, 76, 14, { C = RED_DARK }),
	drop(64, 82, 10, { C = RED_DARK })
)

-- Impact Rounds: a hit that shoves hard.
IconArt.ImpactRounds = art(
	{},
	bar(50, 26, 70, 26, 6, { C = "W", T = 0.3, O = false }),
	bar(50, 74, 70, 74, 6, { C = "W", T = 0.3, O = false }),
	"BREAK",
	bar(36, 50, 74, 50, 15, { C = "W" }),
	arrowHead(84, 50, 0, 24, 14, { C = "W" }),
	"BREAK",
	star8(28, 50, 32, { C = YELLOW }, 12),
	{ "Circle", 28, 50, 12, C = "W", O = false }
)

-- Disruptor Rounds: an ability crossed out.
IconArt.DisruptorRounds = art(
	{},
	poly({ { 56, 26 }, { 42, 52 }, { 58, 50 }, { 44, 76 } }, 9, { C = YELLOW }),
	"BREAK",
	{ "Ring", 50, 51, 68, 10, C = RED },
	bar(28, 29, 72, 73, 10, { C = RED, R = 0.3 })
)

-- Railgun: a beam punching through a row of walls.
IconArt.Railgun = art(
	{},
	wall(26, 50, 10, 70, { Rows = 4 }),
	wall(50, 50, 10, 70, { Rows = 4 }),
	wall(74, 50, 10, 70, { Rows = 4 }),
	"BREAK",
	{ "Glow", 50, 50, 70, C = CYAN, T = 0.8 },
	{ "Rect", 50, 50, 92, 14, 0, R = 0.5, C = CYAN },
	{ "Rect", 50, 50, 88, 5, 0, R = 0.5, C = "W", O = false, Flat = true }
)

-- Double Tap: two bullets side by side.
IconArt.DoubleTap = art(
	{},
	bullet(38, 86, -90, 66, 18),
	"BREAK",
	bullet(64, 86, -90, 66, 18),
	"BREAK",
	twinkle(84, 62, 14, { Big = true })
)

-- Deadeye: an eye in a scope, with a charge arc filling up.
IconArt.Deadeye = art(
	{},
	crosshair(50, 52, 64, 6, { C = "W" }),
	{ "Clip", 34, 52, 34, 72, Kids = { { "Ring", 50, 52, 82, 6, C = YELLOW } } },
	"BREAK",
	{ "Rect", 50, 52, 40, 22, 0, R = 0.5 },
	{ "Circle", 50, 52, 16, C = RED },
	{ "Circle", 50, 52, 6, C = "K", O = false }
)

----------------------------------------------------------------------------
-- NEW DAMAGE / KNIFE
----------------------------------------------------------------------------

-- Last Stand: a fire burning over a nearly empty health bar.
IconArt.LastStand = art(
	{},
	{ "Rect", 50, 82, 70, 14, 0, R = 0.4, C = rgb(50, 40, 50) },
	{ "Rect", 24, 82, 14, 8, 0, R = 0.3, C = RED, O = false },
	"BREAK",
	drop(50, 50, 40, { C = FIRE }),
	"BREAK",
	drop(50, 56, 22, { C = YELLOW, O = false })
)

-- Executioner: a heavy axe.
IconArt.Executioner = art(
	{},
	spin({
		{ "Rect", 40, 54, 10, 76, 0, R = 0.4, C = WOOD },
		"BREAK",
		{ "Rect", 60, 22, 32, 14, -20, R = 0.15, C = STEEL },
		{ "Rect", 60, 40, 32, 14, 20, R = 0.15, C = STEEL },
		{ "Rect", 52, 31, 20, 18, 0, R = 0.1, C = STEEL },
		{ "Circle", 64, 31, 40, C = STEEL },
		{ "Rect", 80, 31, 3, 32, 0, R = 0.5, C = "W", O = false, NoShadow = true, Flat = true, Big = true },
		{ "Rect", 40, 31, 14, 18, 0, R = 0.2, C = STEEL_DARK },
	}, 50, 50, -24)
)

-- Long Shot: a bullet at the end of a long measured trail.
local dashes = {}
for i = 0, 3 do
	table.insert(dashes, bar(10 + i * 12, 44, 15 + i * 12, 44, 5, { C = "W", T = 0.5 - i * 0.1, O = false }))
end
IconArt.LongShot = art(
	{},
	dashes,
	"BREAK",
	bullet(56, 44, 0, 34, 15),
	"BREAK",
	{ "Rect", 50, 74, 78, 6, 0, R = 0.5, C = "W" },
	{ "Rect", 12, 74, 6, 18, 0, R = 0.5, C = "W" },
	{ "Rect", 88, 74, 6, 18, 0, R = 0.5, C = "W" }
)

-- Keen Edge: a gleaming knife.
IconArt.KeenEdge = art(
	{ Tile = rgb(150, 162, 182) },
	spin(knife({ Blade = rgb(240, 246, 255) }), 50, 50, 40),
	"BREAK",
	twinkle(36, 30, 22),
	twinkle(76, 70, 12, { Big = true })
)

-- Hunter's Knife: a knife on the run.
IconArt.HuntersKnife = art(
	{},
	bar(8, 34, 26, 34, 6, { C = "W", T = 0.3, O = false }),
	bar(6, 52, 24, 52, 6, { C = "W", T = 0.3, O = false }),
	bar(10, 70, 26, 70, 6, { C = "W", T = 0.3, O = false }),
	"BREAK",
	spin(knife(), 56, 50, 60)
)

----------------------------------------------------------------------------
-- NEW MOVEMENT
----------------------------------------------------------------------------

-- Power Slide: sliding feet-first with dust.
IconArt.PowerSlide = art(
	{},
	{ "Rect", 54, 88, 84, 6, 0, R = 0.5, C = "W", T = 0.3, O = false },
	{ "Circle", 14, 80, 12, C = "W", T = 0.45, O = false },
	{ "Circle", 24, 82, 9, C = "W", T = 0.45, O = false },
	"BREAK",
	xf(slider(), 4, 2, 0.94)
)

-- Slingshot: a launched figure leaving a slingshot.
IconArt.Slingshot = art(
	{},
	bar(50, 62, 50, 90, 10, { C = WOOD }),
	poly({ { 50, 64 }, { 34, 54 }, { 30, 36 } }, 10, { C = WOOD }),
	poly({ { 50, 64 }, { 66, 54 }, { 70, 36 } }, 10, { C = WOOD }),
	"BREAK",
	poly({ { 30, 38 }, { 50, 52 }, { 70, 38 } }, 4, { C = rgb(60, 50, 50), O = false }),
	"BREAK",
	{ "Circle", 50, 18, 18, C = "W" },
	bar(50, 30, 50, 40, 4, { C = "W", T = 0.4, O = false })
)

-- Air Dash: a runner bursting forward mid-air.
IconArt.AirDash = art(
	{},
	{ "Circle", 18, 56, 18, C = "W", T = 0.5, O = false },
	{ "Circle", 10, 46, 12, C = "W", T = 0.6, O = false },
	bar(16, 32, 34, 32, 5, { C = "W", T = 0.3, O = false }),
	bar(10, 74, 30, 74, 5, { C = "W", T = 0.3, O = false }),
	"BREAK",
	spin(xf(runner(), 22, 6, 0.8), 60, 50, 20)
)

-- Kinetic Armor: a shield in motion.
IconArt.KineticArmor = art(
	{},
	bar(8, 30, 26, 30, 6, { C = "W", T = 0.3, O = false }),
	bar(4, 48, 24, 48, 6, { C = "W", T = 0.3, O = false }),
	bar(8, 66, 26, 66, 6, { C = "W", T = 0.3, O = false }),
	"BREAK",
	xf(shieldShape({ G = { rgb(230, 240, 255), STEEL } }), 14, 4, 0.86),
	"BREAK",
	chevron(66, 46, 0, 14, 7, { C = "A" }),
	chevron(54, 46, 0, 14, 7, { C = "A" })
)

----------------------------------------------------------------------------
-- NEW ABILITIES
----------------------------------------------------------------------------

-- Recall: a rewind arrow around a clock.
IconArt.Recall = art(
	{},
	cycleArrow(50, 54, 64, 10, "W", true),
	"BREAK",
	bar(50, 54, 50, 38, 6, { C = "W" }),
	bar(50, 54, 62, 60, 6, { C = "W" }),
	{ "Circle", 50, 54, 9, C = "K", O = false }
)

-- Barrier Dome: a bubble shield stopping a bullet.
IconArt.BarrierDome = art(
	{},
	{ "Rect", 50, 84, 84, 7, 0, R = 0.5, C = "W", T = 0.2 },
	"BREAK",
	{ "Clip", 50, 52, 80, 62, Kids = {
		{ "Circle", 50, 84, 72, C = CYAN, T = 0.55, O = false },
		{ "Ring", 50, 84, 72, 6, C = "W" },
		{ "Ring", 50, 84, 50, 3, C = "W", T = 0.5, O = false, Big = true },
	} },
	"BREAK",
	bullet(74, 18, 110, 26, 10),
	burst(64, 48, 6, 14, 3, 4, { C = YELLOW }, -160)
)

-- Smoke Grenade: a grenade with a billowing cloud.
IconArt.SmokeGrenade = art(
	{},
	{ "Circle", 66, 34, 30, C = "W", T = 0.25 },
	{ "Circle", 80, 50, 22, C = "W", T = 0.25 },
	{ "Circle", 52, 22, 20, C = "W", T = 0.35 },
	"BREAK",
	{ "Rect", 40, 64, 34, 40, 0, R = 0.45, C = rgb(96, 110, 90) },
	{ "Rect", 40, 64, 34, 4, 0, R = 0.5, C = rgb(66, 76, 62), O = false, NoShadow = true, Big = true },
	{ "Rect", 40, 42, 16, 9, 0, R = 0.2, C = STEEL_DARK },
	bar(48, 40, 58, 50, 5, { C = STEEL_DARK }),
	{ "Ring", 30, 40, 11, 3, C = STEEL }
)

-- Sonar: a radar screen with a blip.
IconArt.Sonar = art(
	{},
	{ "Circle", 50, 50, 72, C = rgb(20, 60, 56) },
	"BREAK",
	{ "Ring", 50, 50, 50, 2.5, C = GREEN, T = 0.3, O = false },
	{ "Ring", 50, 50, 26, 2.5, C = GREEN, T = 0.3, O = false, Big = true },
	bar(50, 50, 72, 30, 4, { C = GREEN, O = false }),
	{ "Circle", 50, 50, 6, C = GREEN, O = false },
	{ "Glow", 64, 62, 20, C = RED, T = 0.6 },
	{ "Circle", 64, 62, 9, C = RED, O = false },
	"BREAK",
	{ "Ring", 50, 50, 72, 6, C = "W" }
)

----------------------------------------------------------------------------
-- NEW SURVIVAL
----------------------------------------------------------------------------

-- Regeneration: a heart with healing pluses rising.
IconArt.Regeneration = art(
	{},
	heart(46, 56, 58, { C = "W" }),
	"BREAK",
	{ "Rect", 46, 54, 7, 22, 0, R = 0.2, C = GREEN, O = false },
	{ "Rect", 46, 54, 22, 7, 0, R = 0.2, C = GREEN, O = false },
	"BREAK",
	{ "Rect", 80, 30, 4, 14, 0, R = 0.4, C = "W" },
	{ "Rect", 80, 30, 14, 4, 0, R = 0.4, C = "W" },
	{ "Rect", 82, 56, 3, 10, 0, R = 0.4, C = "W", Big = true },
	{ "Rect", 82, 56, 10, 3, 0, R = 0.4, C = "W", Big = true }
)

-- Overshield: a shield inside a glowing bubble.
IconArt.Overshield = art(
	{},
	{ "Circle", 50, 50, 80, C = CYAN, T = 0.65, O = false },
	{ "Ring", 50, 50, 80, 4, C = "W", T = 0.15 },
	"BREAK",
	xf(shieldShape({ G = { rgb(250, 252, 255), rgb(200, 220, 245) } }), 20, 18, 0.6),
	"BREAK",
	{ "Rect", 34, 30, 6, 6, 45, R = 0.1, C = "W", O = false, Big = true }
)

-- Bloodlust: a blood drop on a shield.
IconArt.Bloodlust = art(
	{},
	shieldShape({ C = "W" }),
	"BREAK",
	drop(50, 52, 26, { C = RED, O = false })
)

-- Fight or Flight: hit, then run.
IconArt.FightOrFlight = art(
	{},
	star8(26, 42, 30, { C = YELLOW }, 15),
	"BREAK",
	xf(runner(), 22, 8, 0.82)
)

return IconArt
