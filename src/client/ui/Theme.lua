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
