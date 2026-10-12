--[[
	Icons.lua  (Client.ui.Icons)
	Draws a power-up's flat icon from the simple shape list in PowerUps.lua.
	No images needed: every icon is a few rounded frames on a coloured tile.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Theme = require(script.Parent.Theme)

local Icons = {}

--[[
	def   power-up definition (PowerUps.Get(id))
	size  pixel size of the square icon
	Returns a Frame (not parented).
]]
function Icons.Create(def, size)
	local tile = Theme.new("Frame", {
		Name = "Icon_" .. def.Id,
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = def.IconColor,
	})
	Theme.corner(tile, math.floor(size * 0.22))

	local scale = size / 64
	for _, shape in ipairs(def.Icon or {}) do
		local kind, x, y = shape[1], shape[2], shape[3]
		local color = shape.Dark and def.IconColor:Lerp(Config.Palette.UIBackground, 0.75) or Color3.new(1, 1, 1)
		local frame = Theme.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(x, y),
			BackgroundColor3 = color,
			BackgroundTransparency = shape.A or 0,
			Parent = tile,
		})
		if kind == "Circle" then
			frame.Size = UDim2.fromScale(shape[4], shape[4])
			Theme.corner(frame, UDim.new(0.5, 0))
		elseif kind == "Ring" then
			frame.Size = UDim2.fromScale(shape[4], shape[4])
			frame.BackgroundTransparency = 1
			Theme.corner(frame, UDim.new(0.5, 0))
			Theme.stroke(frame, color, math.max(1, (shape[5] or 3) * scale), shape.A or 0)
		else -- "Rect"
			frame.Size = UDim2.fromScale(shape[4], shape[5])
			frame.Rotation = shape[6] or 0
			Theme.corner(frame, UDim.new(shape.Round or 0.15, 0))
		end
	end
	return tile
end

return Icons
