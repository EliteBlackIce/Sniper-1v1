--[[
	Icons.lua  (Client.ui.Icons)
	Draws a power-up icon entirely out of GuiObjects (no image assets):

	  * a polished tile: colour gradient, centre glow, top sheen, a rarity
	    ring (Config.Rarity colour) and, on big icons, a little rarity gem
	  * the hand-made art for the power-up from IconArt.lua
	    (falls back to the old `Icon` shape list in PowerUps.lua)

	Art is drawn "sticker style" in layers. Every layer is drawn three times:
	a soft drop shadow, a dark outline (each shape grown a little), then the
	real fills on top. So overlapping shapes merge into one outlined
	silhouette. See the top of IconArt.lua for the shape format.

	Icons.Create(def, size) -> Frame (size x size, not parented)
	Below DETAIL_SIZE pixels fine detail (strokes, `Big` shapes, the gem) is
	dropped so the icon stays readable at 24px.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local IconArt = require(script.Parent.IconArt)

local Icons = {}

local WHITE = Color3.new(1, 1, 1)
local INK = Config.Palette.UIBackground
local DETAIL_SIZE = 36 -- icons smaller than this drop fine detail

local DEFAULT_OUTLINE = 3.2 -- art outline thickness (icon units, 100 = full icon)
local DEFAULT_SHADOW = 3.4 -- drop shadow offset (icon units)
local SHADOW_TRANSPARENCY = 0.55

----------------------------------------------------------------------------
-- small helpers
----------------------------------------------------------------------------
local function new(className, props)
	local inst = Instance.new(className)
	if inst:IsA("GuiObject") then
		inst.BorderSizePixel = 0
	end
	for key, value in pairs(props) do
		if key ~= "Parent" then
			inst[key] = value
		end
	end
	inst.Parent = props.Parent
	return inst
end

local function corner(parent, radius)
	return new("UICorner", {
		CornerRadius = typeof(radius) == "UDim" and radius or UDim.new(0, radius),
		Parent = parent,
	})
end

local function colorSeq(points)
	local keys = {}
	for i, p in ipairs(points) do
		keys[i] = ColorSequenceKeypoint.new(p[1], p[2])
	end
	return ColorSequence.new(keys)
end

local function numberSeq(points)
	local keys = {}
	for i, p in ipairs(points) do
		keys[i] = NumberSequenceKeypoint.new(p[1], p[2])
	end
	return NumberSequence.new(keys)
end

local function gradient(parent, colors, rotation, transparency)
	return new("UIGradient", {
		Color = colors and colorSeq(colors) or ColorSequence.new(WHITE),
		Transparency = transparency and numberSeq(transparency) or NumberSequence.new(0),
		Rotation = rotation or 90,
		Parent = parent,
	})
end

local function lighten(c, a)
	return c:Lerp(WHITE, a)
end

local function darken(c, a)
	return c:Lerp(INK, a)
end

----------------------------------------------------------------------------
-- art renderer
----------------------------------------------------------------------------

-- Colour tokens usable in IconArt: W white, A tile colour, L light tile
-- colour, M mid-dark tile colour, D dark ink (tinted), K near-black.
local function resolveColor(token, ctx)
	if typeof(token) == "Color3" then
		return token
	elseif token == nil or token == "W" then
		return WHITE
	elseif token == "A" then
		return ctx.base
	elseif token == "L" then
		return lighten(ctx.base, 0.55)
	elseif token == "M" then
		return darken(ctx.base, 0.4)
	elseif token == "D" then
		return ctx.ink
	elseif token == "K" then
		return INK
	end
	return WHITE
end

local function shapeVisible(shape, ctx)
	if shape.Big and not ctx.big then
		return false
	end
	if shape.Small and ctx.big then
		return false
	end
	return true
end

local buildShape -- forward

-- Builds one shape for one pass ("shadow" | "outline" | "fill").
-- ox, oy: top-left of the parent frame in icon units.
buildShape = function(parent, shape, ctx, pass, ox, oy)
	if not shapeVisible(shape, ctx) then
		return
	end
	local kind = shape[1]
	local u = ctx.u
	local alpha = shape.T or 0

	-- which passes draw this shape
	if pass == "shadow" and (shape.NoShadow or alpha > 0.3 or kind == "Glow") then
		return
	end
	if pass == "outline" and (shape.O == false or kind == "Glow") then
		return
	end
	if kind == "Glow" and pass ~= "fill" then
		return
	end

	local grow = 0
	if pass ~= "fill" then
		grow = (shape.O == false) and 0 or ctx.outline
	end

	local x, y = shape[2], shape[3]

	if kind == "Glow" then
		-- three stacked translucent discs: a cheap radial glow
		local d = shape[4]
		local color = resolveColor(shape.C, ctx)
		for _, k in ipairs({ 1, 0.72, 0.46 }) do
			local disc = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset((x - ox) * u, (y - oy) * u),
				Size = UDim2.fromOffset(d * k * u, d * k * u),
				BackgroundColor3 = color,
				BackgroundTransparency = shape.T or 0.82,
				Parent = parent,
			})
			corner(disc, UDim.new(0.5, 0))
		end
		return
	end

	if kind == "Clip" then
		local w, h = shape[4], shape[5]
		local left, top = x - w / 2 - grow, y - h / 2 - grow
		local clip = new("Frame", {
			Position = UDim2.fromOffset((left - ox) * u, (top - oy) * u),
			Size = UDim2.fromOffset((w + 2 * grow) * u, (h + 2 * grow) * u),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			Parent = parent,
		})
		for _, kid in ipairs(shape.Kids or {}) do
			buildShape(clip, kid, ctx, pass, left, top)
		end
		return
	end

	local w, h, rot
	if kind == "Circle" or kind == "Ring" then
		w, h, rot = shape[4], shape[4], 0
	else -- Rect
		w, h, rot = shape[4], shape[5], shape[6] or 0
	end

	local frame = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset((x - ox) * u, (y - oy) * u),
		Rotation = rot,
		BackgroundColor3 = WHITE,
		Parent = parent,
	})

	-- colour + transparency for this pass
	local color
	if pass == "shadow" then
		color = INK
		alpha = 1 - (1 - alpha) * (1 - SHADOW_TRANSPARENCY)
	elseif pass == "outline" then
		color = ctx.ink
	else
		color = resolveColor(shape.C, ctx)
	end

	if kind == "Ring" then
		local th = shape[5] or 6
		local strokePx = math.max(1, (th + 2 * grow) * u)
		local outer = (w + 2 * grow) * u
		local inner = math.max(0, outer - 2 * strokePx)
		frame.Size = UDim2.fromOffset(inner, inner)
		frame.BackgroundTransparency = 1
		corner(frame, UDim.new(0.5, 0))
		local stroke = new("UIStroke", {
			Color = (pass == "fill" and shape.G) and WHITE or color,
			Thickness = strokePx,
			Transparency = alpha,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			LineJoinMode = Enum.LineJoinMode.Round,
			Parent = frame,
		})
		if pass == "fill" and shape.G then
			local g = shape.G
			gradient(stroke, { { 0, resolveColor(g[1], ctx) }, { 1, resolveColor(g[2], ctx) } }, g[3] or 90)
		end
		return
	end

	frame.Size = UDim2.fromOffset((w + 2 * grow) * u, (h + 2 * grow) * u)
	frame.BackgroundTransparency = alpha
	if kind == "Circle" then
		corner(frame, UDim.new(0.5, 0))
	else
		local round = shape.R or 0.12
		corner(frame, math.min(w, h) * round * u + grow * u)
	end

	if pass ~= "fill" then
		frame.BackgroundColor3 = color
		return
	end

	-- fill: shaded with a gradient that stays lit from the top even when the
	-- shape is rotated
	local lightRot = 90 - rot
	if shape.G then
		local g = shape.G
		gradient(frame, {
			{ 0, resolveColor(g[1], ctx) },
			{ 1, resolveColor(g[2], ctx) },
		}, (g[3] or 90) - rot)
	elseif shape.Flat then
		frame.BackgroundColor3 = color
	else
		gradient(frame, { { 0, lighten(color, 0.22) }, { 1, darken(color, 0.14) } }, lightRot)
	end

	if shape.S and ctx.big then
		local s = shape.S
		new("UIStroke", {
			Color = resolveColor(s[1], ctx),
			Thickness = math.max(1, (s[2] or 1.5) * u),
			Transparency = s[3] or 0,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Parent = frame,
		})
	end
end

-- Splits an art list into layers at "BREAK" markers.
local function splitLayers(art)
	local layers, current = {}, {}
	for _, shape in ipairs(art) do
		if shape == "BREAK" then
			if #current > 0 then
				table.insert(layers, current)
			end
			current = {}
		elseif type(shape) == "table" then
			table.insert(current, shape)
		end
	end
	if #current > 0 then
		table.insert(layers, current)
	end
	return layers
end

local function drawArt(holder, art, ctx)
	local shadowOffset = (art.Shadow or DEFAULT_SHADOW) * ctx.u
	if shadowOffset > 0 then
		shadowOffset = math.max(1, shadowOffset)
	end
	for _, layer in ipairs(splitLayers(art)) do
		if shadowOffset > 0 then
			local shadow = new("Frame", {
				Name = "Shadow",
				Position = UDim2.fromOffset(0, shadowOffset),
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Parent = holder,
			})
			for _, shape in ipairs(layer) do
				buildShape(shadow, shape, ctx, "shadow", 0, 0)
			end
		end
		if ctx.outline > 0 then
			local outline = new("Frame", {
				Name = "Outline",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Parent = holder,
			})
			for _, shape in ipairs(layer) do
				buildShape(outline, shape, ctx, "outline", 0, 0)
			end
		end
		local fill = new("Frame", {
			Name = "Fill",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Parent = holder,
		})
		for _, shape in ipairs(layer) do
			buildShape(fill, shape, ctx, "fill", 0, 0)
		end
	end
end

-- Converts the old PowerUps.lua `Icon` list (0-1 coordinates, white/dark)
-- into IconArt shapes so un-drawn power-ups still look at home.
local function legacyArt(def)
	local art = {}
	for _, s in ipairs(def.Icon or {}) do
		local kind = s[1]
		local c = s.Dark and "D" or "W"
		if kind == "Circle" then
			table.insert(art, { "Circle", s[2] * 100, s[3] * 100, s[4] * 100, C = c, T = s.A })
		elseif kind == "Ring" then
			table.insert(art, { "Ring", s[2] * 100, s[3] * 100, s[4] * 100, (s[5] or 3) * 100 / 64, C = c, T = s.A })
		else
			table.insert(art, {
				"Rect",
				s[2] * 100,
				s[3] * 100,
				s[4] * 100,
				s[5] * 100,
				s[6] or 0,
				R = s.Round or 0.15,
				C = c,
				T = s.A,
			})
		end
	end
	return art
end

----------------------------------------------------------------------------
-- the tile
----------------------------------------------------------------------------
--[[
	def   power-up definition (PowerUps.Get(id))
	size  pixel size of the square icon
	Returns a Frame (not parented).
	Each (power-up, size) is built once; later calls return a clone.
]]
local cache = {}

local function build(def, size)
	local art = IconArt[def.Id]
	local base = (art and art.Tile) or def.IconColor or Color3.fromRGB(120, 130, 150)
	local rarity = Config.Rarity and Config.Rarity[def.Rarity]
	local rarityColor = rarity and rarity.Color or lighten(base, 0.5)
	local big = size >= DETAIL_SIZE
	local radius = math.floor(size * 0.22 + 0.5)

	local ctx = {
		u = size / 100,
		big = big,
		base = base,
		ink = (art and art.Ink) or base:Lerp(INK, 0.78),
		outline = 0,
	}

	-- root stays transparent so callers can add their own UIStroke to it
	local tile = new("Frame", {
		Name = "Icon_" .. def.Id,
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
	})
	corner(tile, radius)

	-- body: vertical gradient, lighter at the top
	local body = new("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		Parent = tile,
	})
	corner(body, radius)
	gradient(body, {
		{ 0, lighten(base, 0.2) },
		{ 0.55, base },
		{ 1, darken(base, 0.42) },
	}, 90)

	-- soft light behind the art
	for _, k in ipairs({ 0.84, 0.6 }) do
		local disc = new("Frame", {
			Name = "Glow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.48),
			Size = UDim2.fromScale(k, k),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.86,
			Parent = tile,
		})
		corner(disc, UDim.new(0.5, 0))
	end

	-- glossy sheen over the top half
	local inset = math.max(1, math.floor(size * 0.04))
	local sheen = new("Frame", {
		Name = "Sheen",
		Position = UDim2.fromOffset(inset, inset),
		Size = UDim2.new(1, -2 * inset, 0.46, 0),
		BackgroundColor3 = WHITE,
		Parent = tile,
	})
	corner(sheen, math.max(1, radius - inset))
	gradient(sheen, nil, 90, { { 0, 0.62 }, { 1, 1 } })

	-- the art
	local holder = new("Frame", {
		Name = "Art",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = tile,
	})
	local shapes = art or legacyArt(def)
	ctx.outline = (shapes.Outline or DEFAULT_OUTLINE)
	drawArt(holder, shapes, ctx)

	-- rarity ring (drawn inside the tile edge, gradient for a metallic feel)
	local ringPx = big and math.max(2, math.floor(size * 0.04 + 0.5)) or 1
	local ring = new("Frame", {
		Name = "RarityRing",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -2 * ringPx, 1, -2 * ringPx),
		BackgroundTransparency = 1,
		Parent = tile,
	})
	corner(ring, math.max(1, radius - ringPx))
	local ringStroke = new("UIStroke", {
		Color = WHITE,
		Thickness = ringPx,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = ring,
	})
	gradient(ringStroke, {
		{ 0, lighten(rarityColor, 0.55) },
		{ 0.5, rarityColor },
		{ 1, darken(rarityColor, 0.3) },
	}, 60)

	if big then
		-- thin inner bevel highlight
		local bevel = new("Frame", {
			Name = "Bevel",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -2 * ringPx - 2, 1, -2 * ringPx - 2),
			BackgroundTransparency = 1,
			Parent = tile,
		})
		corner(bevel, math.max(1, radius - ringPx - 1))
		local bevelStroke = new("UIStroke", {
			Color = WHITE,
			Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Parent = bevel,
		})
		gradient(bevelStroke, nil, 90, { { 0, 0.45 }, { 0.5, 0.9 }, { 1, 1 } })

		-- rarity gem in the top-right corner
		local gemSize = math.max(6, math.floor(size * 0.13))
		local gemPos = UDim2.new(1, -math.floor(size * 0.15), 0, math.floor(size * 0.15))
		local gemOutline = new("Frame", {
			Name = "GemOutline",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = gemPos,
			Size = UDim2.fromOffset(gemSize + 4, gemSize + 4),
			Rotation = 45,
			BackgroundColor3 = INK,
			Parent = tile,
		})
		corner(gemOutline, 3)
		local gem = new("Frame", {
			Name = "Gem",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = gemPos,
			Size = UDim2.fromOffset(gemSize, gemSize),
			Rotation = 45,
			BackgroundColor3 = WHITE,
			Parent = tile,
		})
		corner(gem, 2)
		gradient(gem, {
			{ 0, lighten(rarityColor, 0.6) },
			{ 0.5, rarityColor },
			{ 1, darken(rarityColor, 0.35) },
		}, 90 - 45 + 0)
		local glint = new("Frame", {
			Name = "Glint",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = gemPos + UDim2.fromOffset(-gemSize * 0.18, -gemSize * 0.18),
			Size = UDim2.fromOffset(math.max(2, gemSize * 0.28), math.max(2, gemSize * 0.28)),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.1,
			Parent = tile,
		})
		corner(glint, UDim.new(0.5, 0))
	end

	return tile
end

function Icons.Create(def, size)
	local key = def.Id .. "@" .. size
	local template = cache[key]
	if not template then
		template = build(def, size)
		cache[key] = template
	end
	return template:Clone()
end

return Icons
