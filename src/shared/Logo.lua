--[[
	Logo.lua  (ReplicatedStorage.Shared.Logo)

	The SNIPER DUEL logo, built from GUI frames (no images): a crosshair mark
	and the wordmark. Used on the lobby banners and signs (SurfaceGuis) and
	on the crate emblems.

		Logo.Make(parent, {
			Layout = "Stacked" | "Inline" | "Mark",  -- default "Stacked"
			Color = Color3,        -- main colour (default white)
			Accent = Color3,       -- "DUEL" + centre dot (default Palette.UIAccent)
			Stroke = number,       -- ring thickness in pixels (default: from size)
			Subtitle = string?,    -- small line under the wordmark
		})

	The logo fills `parent` (a Frame, SurfaceGui, BillboardGui...).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Logo = {}

local function new(className, props)
	local inst = Instance.new(className)
	for key, value in pairs(props) do
		if key ~= "Parent" then
			inst[key] = value
		end
	end
	inst.Parent = props.Parent
	return inst
end

local function font(weight)
	return Font.new(Config.UI.FontFamily, weight or Enum.FontWeight.Heavy)
end

-- The crosshair mark: a ring, four ticks pointing in, a dot in the middle.
function Logo.Mark(parent, color, accent, stroke, position, size)
	local mark = new("Frame", {
		Name = "Mark",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position or UDim2.fromScale(0.5, 0.5),
		Size = size or UDim2.fromScale(1, 1),
		Parent = parent,
	})
	new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = mark })
	local ring = new("Frame", {
		Name = "Ring",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.78, 0.78),
		Parent = mark,
	})
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = ring })
	local uiStroke = new("UIStroke", { Color = color, Thickness = stroke or 4, Parent = ring })
	if not stroke then
		-- keep the ring in proportion on screen GUIs
		local function fit()
			uiStroke.Thickness = math.max(1.5, mark.AbsoluteSize.X * 0.055)
		end
		mark:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
		fit()
	end
	-- ticks: from outside the ring to part way in
	for _, info in ipairs({
		{ UDim2.fromScale(0.5, 0.11), UDim2.fromScale(0.06, 0.3) },
		{ UDim2.fromScale(0.5, 0.89), UDim2.fromScale(0.06, 0.3) },
		{ UDim2.fromScale(0.11, 0.5), UDim2.fromScale(0.3, 0.06) },
		{ UDim2.fromScale(0.89, 0.5), UDim2.fromScale(0.3, 0.06) },
	}) do
		new("Frame", {
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = info[1],
			Size = info[2],
			Parent = mark,
		})
	end
	local dot = new("Frame", {
		Name = "Dot",
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.13, 0.13),
		Parent = mark,
	})
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = dot })
	return mark
end

local function word(parent, text, color, position, size, align)
	return new("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(align == Enum.TextXAlignment.Left and 0 or 0.5, 0.5),
		Position = position,
		Size = size,
		Text = text,
		TextScaled = true,
		TextXAlignment = align or Enum.TextXAlignment.Center,
		FontFace = font(Enum.FontWeight.Heavy),
		TextColor3 = color,
		Parent = parent,
	})
end

function Logo.Make(parent, options)
	options = options or {}
	local color = options.Color or Color3.new(1, 1, 1)
	local accent = options.Accent or Config.Palette.UIAccent
	local layout = options.Layout or "Stacked"

	local root = new("Frame", {
		Name = "SniperDuelLogo",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = parent,
	})

	if layout == "Mark" then
		Logo.Mark(root, color, accent, options.Stroke)
	elseif layout == "Inline" then
		-- [mark] SNIPER DUEL  (subtitle under the words). Everything sits in
		-- one centred box with a fixed shape, so the mark and the words line
		-- up the same on any board, and both words are one label (one size).
		local hasSub = options.Subtitle ~= nil
		local box = new("Frame", {
			Name = "Inline",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.94, 0.86),
			Parent = root,
		})
		new("UIAspectRatioConstraint", { AspectRatio = 4, Parent = box })
		-- the mark is a square as tall as the box: 1/4 of its width
		Logo.Mark(box, color, accent, options.Stroke, UDim2.fromScale(0.125, 0.5), UDim2.fromScale(0.25, 1))
		local words = word(
			box,
			string.format('SNIPER <font color="#%s">DUEL</font>', accent:ToHex()),
			color,
			UDim2.fromScale(0.3, hasSub and 0.38 or 0.5),
			UDim2.fromScale(0.7, hasSub and 0.62 or 0.8),
			Enum.TextXAlignment.Left
		)
		words.RichText = true
		if hasSub then
			local sub = word(box, options.Subtitle, color, UDim2.fromScale(0.3, 0.84), UDim2.fromScale(0.7, 0.2), Enum.TextXAlignment.Left)
			sub.FontFace = font(Enum.FontWeight.Bold)
			sub.TextTransparency = 0.15
		end
	else
		-- mark on top, SNIPER / a rule / DUEL underneath (tall banners)
		Logo.Mark(root, color, accent, options.Stroke, UDim2.fromScale(0.5, 0.27), UDim2.fromScale(0.62, 0.36))
		word(root, "SNIPER", color, UDim2.fromScale(0.5, 0.58), UDim2.fromScale(0.86, 0.14))
		new("Frame", {
			BackgroundColor3 = accent,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.67),
			Size = UDim2.fromScale(0.5, 0.012),
			Parent = root,
		})
		word(root, "DUEL", accent, UDim2.fromScale(0.5, 0.76), UDim2.fromScale(0.6, 0.13))
		if options.Subtitle then
			local sub = word(root, options.Subtitle, color, UDim2.fromScale(0.5, 0.88), UDim2.fromScale(0.8, 0.06))
			sub.FontFace = font(Enum.FontWeight.Bold)
		end
	end
	return root
end

-- A SurfaceGui with the logo on one face of `part`.
function Logo.OnPart(part, face, options, pixelsPerStud)
	local gui = new("SurfaceGui", {
		Name = "Logo" .. face.Name,
		Face = face,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = pixelsPerStud or 50,
		LightInfluence = 0.4,
		Parent = part,
	})
	Logo.Make(gui, options)
	return gui
end

return Logo
