--[[
	Theme.lua  (Client.ui.Theme)
	Shared UI helpers so every screen looks the same:
	flat colours from Config.Palette, rounded corners, one clean font.
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local Theme = {}
Theme.Palette = Config.Palette

function Theme.Font(weight)
	return Font.new(Config.UI.FontFamily, weight or Enum.FontWeight.Medium)
end

-- Creates an instance with properties and children:
-- Theme.new("Frame", { Size = ..., Parent = ... }, { child1, child2 })
function Theme.new(className, props, children)
	local inst = Instance.new(className)
	if inst:IsA("GuiObject") then
		inst.BorderSizePixel = 0
	end
	local parent
	for key, value in pairs(props or {}) do
		if key == "Parent" then
			parent = value
		else
			inst[key] = value
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	inst.Parent = parent
	return inst
end

function Theme.corner(parent, radius)
	return Theme.new("UICorner", {
		CornerRadius = typeof(radius) == "UDim" and radius or UDim.new(0, radius or Config.UI.CornerRadius),
		Parent = parent,
	})
end

function Theme.stroke(parent, color, thickness, transparency)
	return Theme.new("UIStroke", {
		Color = color or Color3.new(1, 1, 1),
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function Theme.padding(parent, px)
	return Theme.new("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		Parent = parent,
	})
end

function Theme.label(props)
	local defaults = {
		BackgroundTransparency = 1,
		TextColor3 = Config.Palette.UIText,
		FontFace = Theme.Font(Enum.FontWeight.Bold),
		TextSize = 18,
		Text = "",
	}
	for k, v in pairs(props) do
		defaults[k] = v
	end
	return Theme.new("TextLabel", defaults)
end

function Theme.panel(props)
	local defaults = {
		BackgroundColor3 = Config.Palette.UIPanel,
		BackgroundTransparency = 0.08,
	}
	for k, v in pairs(props) do
		defaults[k] = v
	end
	local frame = Theme.new("Frame", defaults)
	Theme.corner(frame)
	return frame
end

function Theme.button(props)
	local defaults = {
		BackgroundColor3 = Config.Palette.UIAccent,
		TextColor3 = Config.Palette.UIBackground,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		TextSize = 20,
		AutoButtonColor = true,
	}
	for k, v in pairs(props) do
		defaults[k] = v
	end
	local button = Theme.new("TextButton", defaults)
	Theme.corner(button)
	return button
end

function Theme.tween(inst, time, goals, style, direction)
	local tween = TweenService:Create(
		inst,
		TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		goals
	)
	tween:Play()
	return tween
end

-- Returns the UIScale of a GUI object (creates one if needed).
function Theme.scaleOf(inst)
	local scale = inst:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Theme.new("UIScale", { Parent = inst })
	end
	return scale
end

-- Quick "pop" animation (grow a little, spring back).
function Theme.pop(inst, amount)
	local scale = Theme.scaleOf(inst)
	scale.Scale = 1 + (amount or 0.12)
	Theme.tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
end

--[[
	UI particle burst: `count` little flat squares fly out from `center`
	(absolute screen position, Vector2) inside `parent`, then fade away.
]]
function Theme.burst(parent, center, color, count, distance, size)
	count = count or 14
	distance = distance or 140
	size = size or 8
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + math.random() * 0.4
		local reach = distance * (0.55 + math.random() * 0.6)
		local bit = Theme.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(center.X, center.Y),
			Size = UDim2.fromOffset(size, size),
			Rotation = math.random(0, 90),
			BackgroundColor3 = color,
			ZIndex = 20,
			Parent = parent,
		})
		Theme.corner(bit, 2)
		local target = center + Vector2.new(math.cos(angle), math.sin(angle)) * reach
		local time = 0.5 + math.random() * 0.35
		Theme.tween(bit, time, {
			Position = UDim2.fromOffset(target.X, target.Y),
			Size = UDim2.fromOffset(2, 2),
			Rotation = bit.Rotation + math.random(-180, 180),
			BackgroundTransparency = 1,
		}, Enum.EasingStyle.Quint)
		task.delay(time + 0.05, function()
			bit:Destroy()
		end)
	end
end

-- An expanding ring (UI shockwave) at an absolute screen position.
function Theme.ring(parent, center, color, size, thickness)
	local ring = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(center.X, center.Y),
		Size = UDim2.fromOffset(10, 10),
		BackgroundTransparency = 1,
		ZIndex = 19,
		Parent = parent,
	})
	Theme.corner(ring, UDim.new(0.5, 0))
	local stroke = Theme.stroke(ring, color, thickness or 6, 0)
	Theme.tween(ring, 0.55, { Size = UDim2.fromOffset(size, size) }, Enum.EasingStyle.Quint)
	Theme.tween(stroke, 0.55, { Transparency = 1, Thickness = 1 })
	task.delay(0.6, function()
		ring:Destroy()
	end)
end

-- A diagonal white shine that sweeps across `inst` once (or forever).
function Theme.shine(inst, duration, loop, strength)
	local band = Theme.new("Frame", {
		Name = "Shine",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 8,
		Parent = inst,
	})
	local corner = inst:FindFirstChildOfClass("UICorner")
	if corner then
		Theme.corner(band, corner.CornerRadius)
	end
	local peak = 1 - (strength or 0.45)
	local gradient = Theme.new("UIGradient", {
		Rotation = 25,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.4, 1),
			NumberSequenceKeypoint.new(0.5, peak),
			NumberSequenceKeypoint.new(0.6, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Offset = Vector2.new(-1, 0),
		Parent = band,
	})
	local tween = TweenService:Create(
		gradient,
		TweenInfo.new(duration or 0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, loop and -1 or 0, false, loop and 0.9 or 0),
		{ Offset = Vector2.new(1, 0) }
	)
	tween:Play()
	if not loop then
		task.delay((duration or 0.8) + 0.05, function()
			band:Destroy()
		end)
	end
	return band, tween
end

-- Rough pixel width of a short upper-case keycap label ("F", "D-RIGHT"),
-- so a keycap chip can be sized without measuring text (GothamSSm Heavy).
function Theme.keycapWidth(text, textSize)
	textSize = textSize or 13
	return math.max(math.floor(textSize * 2), math.ceil(#tostring(text) * textSize * 0.7) + 12)
end

-- A small keyboard-key chip showing a binding. Returns (frame, label).
-- `props` are applied to the frame (Position, AnchorPoint, Parent...).
function Theme.keycap(text, textSize, props)
	textSize = textSize or 13
	local defaults = {
		Name = "Keycap",
		Size = UDim2.fromOffset(Theme.keycapWidth(text, textSize), math.floor(textSize * 1.85)),
		BackgroundColor3 = Config.Palette.UIPanelLight,
	}
	for k, v in pairs(props or {}) do
		defaults[k] = v
	end
	local frame = Theme.new("Frame", defaults)
	Theme.corner(frame, 6)
	Theme.stroke(frame, Config.Palette.UIText, 1, 0.8)
	local label = Theme.label({
		Name = "Key",
		Size = UDim2.fromScale(1, 1),
		Text = tostring(text),
		TextSize = textSize,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = frame,
	})
	return frame, label
end

-- A UIGradient that only fades transparency. `points` is a list of
-- { position (0-1), transparency } pairs; rotation in degrees.
function Theme.fade(parent, rotation, points)
	local keypoints = {}
	for _, p in ipairs(points) do
		table.insert(keypoints, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return Theme.new("UIGradient", {
		Rotation = rotation or 0,
		Transparency = NumberSequence.new(keypoints),
		Parent = parent,
	})
end

----------------------------------------------------------------------------
-- Additive helpers (lobby overhaul). Nothing above depends on these.
----------------------------------------------------------------------------

-- One spacing scale (design pixels) for layouts that want it.
Theme.Space = { XS = 4, S = 8, M = 12, L = 16, XL = 24, XXL = 32 }

-- A quiet keycap: no outline, translucent fill, dim text. Returns (frame, label).
function Theme.keyHint(text, textSize, props)
	textSize = textSize or 11
	local defaults = {
		Name = "KeyHint",
		Size = UDim2.fromOffset(Theme.keycapWidth(text, textSize), math.floor(textSize * 1.85)),
		BackgroundColor3 = Config.Palette.UIPanelLight,
		BackgroundTransparency = 0.3,
	}
	for k, v in pairs(props or {}) do
		defaults[k] = v
	end
	local frame = Theme.new("Frame", defaults)
	Theme.corner(frame, 5)
	local label = Theme.label({
		Name = "Key",
		Size = UDim2.fromScale(1, 1),
		Text = tostring(text),
		TextSize = textSize,
		TextColor3 = Config.Palette.UISubText,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = frame,
	})
	return frame, label
end

-- Flat vector icons built from frames (no image assets). Every part is
-- placed in 0-1 scale units so the icon works at any size. Parts tagged
-- with the "Cut" attribute are drawn in the cut-out colour (eyes, holes).
local ICON_SHAPES = {}
do
	-- { "R", x, y, w, h, rotation, round } rectangle (round = corner scale)
	-- { "O", x, y, d }                      filled circle
	-- { "Ring", x, y, d }                   outline circle
	-- add .Cut = true to draw in the cut-out colour
	local function cut(t)
		t.Cut = true
		return t
	end
	ICON_SHAPES.target = {
		{ "Ring", 0.5, 0.5, 0.56 },
		{ "R", 0.5, 0.08, 0.09, 0.2 },
		{ "R", 0.5, 0.92, 0.09, 0.2 },
		{ "R", 0.08, 0.5, 0.2, 0.09 },
		{ "R", 0.92, 0.5, 0.2, 0.09 },
		{ "O", 0.5, 0.5, 0.18 },
	}
	ICON_SHAPES.flag = {
		{ "R", 0.26, 0.5, 0.09, 0.86, 0, 0.5 },
		{ "R", 0.57, 0.32, 0.52, 0.38, 0, 0.15 },
	}
	ICON_SHAPES.bot = {
		{ "R", 0.5, 0.2, 0.08, 0.2 },
		{ "O", 0.5, 0.11, 0.18 },
		{ "R", 0.5, 0.6, 0.82, 0.6, 0, 0.28 },
		cut({ "O", 0.35, 0.58, 0.16 }),
		cut({ "O", 0.65, 0.58, 0.16 }),
	}
	ICON_SHAPES.shirt = {
		{ "R", 0.22, 0.36, 0.38, 0.2, -32, 0.2 },
		{ "R", 0.78, 0.36, 0.38, 0.2, 32, 0.2 },
		{ "R", 0.5, 0.58, 0.52, 0.7, 0, 0.12 },
		cut({ "O", 0.5, 0.24, 0.2 }),
	}
	ICON_SHAPES.bag = {
		{ "Ring", 0.5, 0.32, 0.32 },
		{ "R", 0.5, 0.66, 0.78, 0.58, 0, 0.16 },
	}
	ICON_SHAPES.swords = {
		{ "R", 0.5, 0.48, 0.12, 0.9, 45, 0.5 },
		{ "R", 0.5, 0.48, 0.12, 0.9, -45, 0.5 },
		{ "R", 0.3, 0.7, 0.34, 0.11, 45, 0.5 },
		{ "R", 0.7, 0.7, 0.34, 0.11, -45, 0.5 },
	}
	ICON_SHAPES.flask = {
		{ "R", 0.5, 0.1, 0.4, 0.1, 0, 0.5 },
		{ "R", 0.5, 0.28, 0.22, 0.34 },
		{ "O", 0.5, 0.65, 0.66 },
		cut({ "O", 0.4, 0.68, 0.14 }),
	}
	local gear = { { "Ring", 0.5, 0.5, 0.46 } }
	for i = 0, 7 do
		local a = i * math.pi / 4
		table.insert(gear, { "R", 0.5 + 0.37 * math.cos(a), 0.5 + 0.37 * math.sin(a), 0.17, 0.17, math.deg(a), 0.2 })
	end
	ICON_SHAPES.gear = gear
	ICON_SHAPES.key = {
		{ "Ring", 0.26, 0.5, 0.28 },
		{ "R", 0.64, 0.5, 0.52, 0.12 },
		{ "R", 0.74, 0.62, 0.08, 0.18 },
		{ "R", 0.86, 0.6, 0.08, 0.14 },
	}
	ICON_SHAPES.coin = {
		{ "O", 0.5, 0.5, 0.86 },
		cut({ "O", 0.5, 0.5, 0.44 }),
		{ "O", 0.5, 0.5, 0.26 },
	}
	ICON_SHAPES.diamond = {
		{ "R", 0.5, 0.5, 0.62, 0.62, 45, 0.15 },
		cut({ "R", 0.5, 0.5, 0.24, 0.24, 45, 0.1 }),
	}
	ICON_SHAPES.menu = {
		{ "R", 0.5, 0.22, 0.86, 0.13, 0, 0.5 },
		{ "R", 0.5, 0.5, 0.86, 0.13, 0, 0.5 },
		{ "R", 0.5, 0.78, 0.86, 0.13, 0, 0.5 },
	}
end

--[[
	Theme.icon(name, size, color, cutColor) -> Frame (not parented)
	names: target, flag, bot, shirt, bag, swords, flask, gear, key, coin,
	       diamond, menu. Unknown names give an empty frame.
]]
function Theme.icon(name, size, color, cutColor)
	color = color or Config.Palette.UIText
	cutColor = cutColor or Config.Palette.UIBackground
	local thick = math.max(1.5, size * 0.1)
	local frame = Theme.new("Frame", {
		Name = "Icon",
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
	})
	for _, s in ipairs(ICON_SHAPES[name] or {}) do
		local kind = s[1]
		local partColor = s.Cut and cutColor or color
		local part = Theme.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(s[2], s[3]),
			BackgroundColor3 = partColor,
			Parent = frame,
		})
		if s.Cut then
			part:SetAttribute("Cut", true)
		end
		if kind == "R" then
			part.Size = UDim2.fromScale(s[4], s[5])
			part.Rotation = s[6] or 0
			if s[7] then
				Theme.corner(part, UDim.new(s[7], 0))
			end
		elseif kind == "O" then
			part.Size = UDim2.fromScale(s[4], s[4])
			Theme.corner(part, UDim.new(0.5, 0))
		else -- "Ring" (the stroke sits outside the frame, so shrink it a bit)
			local d = math.max(0.05, s[4] - thick / size)
			part.Size = UDim2.fromScale(d, d)
			part.BackgroundTransparency = 1
			Theme.corner(part, UDim.new(0.5, 0))
			Theme.stroke(part, partColor, thick, 0)
		end
	end
	return frame
end

-- Recolours an icon from Theme.icon (cut-out parts keep their colour).
function Theme.tintIcon(icon, color)
	for _, part in ipairs(icon:GetChildren()) do
		if part:IsA("Frame") and not part:GetAttribute("Cut") then
			part.BackgroundColor3 = color
			local stroke = part:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = color
			end
		end
	end
end

-- A ScreenGui that ignores the top bar inset and survives respawns.
function Theme.screen(name, displayOrder, parent)
	return Theme.new("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = displayOrder or 0,
		Parent = parent,
	})
end

-- An invisible button with Modal = true: while it's visible, Roblox frees
-- the mouse even in first person. Toggle `.Visible` to lock/unlock.
function Theme.mouseUnlocker(parent)
	return Theme.new("TextButton", {
		Name = "MouseUnlock",
		Modal = true,
		BackgroundTransparency = 1,
		Text = "",
		Size = UDim2.fromOffset(0, 0),
		Visible = false,
		Parent = parent,
	})
end

return Theme
