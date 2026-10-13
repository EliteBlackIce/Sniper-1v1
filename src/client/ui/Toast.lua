--[[
	Toast.lua  (Client.ui.Toast)

	Small message that slides in at the top of the screen for a few seconds
	(server "Notify" remote: admin command results, e.g. "BOT MATCH - HARD").
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Sfx = require(script.Parent.Parent.Sfx)
local Theme = require(script.Parent.Theme)

local Palette = Config.Palette

local Toast = {}

local gui, holder
local SHOW_TIME = 3

function Toast.Show(text)
	local card = Theme.panel({
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Palette.UIPanel,
		Parent = holder,
	})
	Theme.stroke(card, Palette.UIAccent, 2, 0.2)
	Theme.new("UIPadding", {
		PaddingLeft = UDim.new(0, 18),
		PaddingRight = UDim.new(0, 18),
		Parent = card,
	})
	local label = Theme.label({
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = string.upper(tostring(text)),
		TextSize = 17,
		FontFace = Theme.Font(Enum.FontWeight.Bold),
		Parent = card,
	})
	local scale = Theme.scaleOf(card)
	scale.Scale = 0.6
	card.BackgroundTransparency = 1
	label.TextTransparency = 1
	Theme.tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	Theme.tween(card, 0.2, { BackgroundTransparency = 0 })
	Theme.tween(label, 0.2, { TextTransparency = 0 })
	Sfx.Play("CardPick", { Volume = 0.4, Pitch = 1.3 })

	task.delay(SHOW_TIME, function()
		Theme.tween(scale, 0.25, { Scale = 0.8 })
		Theme.tween(card, 0.25, { BackgroundTransparency = 1 })
		Theme.tween(label, 0.25, { TextTransparency = 1 })
		task.wait(0.3)
		card:Destroy()
	end)
end

function Toast.Start(playerGui)
	gui = Theme.screen("Toast", 50, playerGui)
	holder = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 120),
		Size = UDim2.fromOffset(600, 200),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	Theme.new("UIListLayout", {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = holder,
	})
	Remotes.Get("Notify").OnClientEvent:Connect(Toast.Show)
end

return Toast
