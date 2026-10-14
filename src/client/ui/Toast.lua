--[[
	Toast.lua  (Client.ui.Toast)

	Short messages from the server "Notify" remote (admin command results,
	e.g. "BOT MATCH - HARD"). Small pills stacked in the lower middle of the
	screen, below the crosshair and above the speedometer, newest at the
	bottom. At most MAX_TOASTS at once (the oldest leaves early) and each one
	lives SHOW_TIME seconds.
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
local SHOW_TIME = 2.6
local MAX_TOASTS = 3
local REST_FILL = 0.12
local order = 0
local live = {} -- oldest first: { Card, Label, Dot, Scale }

local function dismiss(toast)
	local index = table.find(live, toast)
	if not index then
		return -- already leaving
	end
	table.remove(live, index)
	Theme.tween(toast.Scale, 0.2, { Scale = 0.9 })
	Theme.tween(toast.Card, 0.2, { BackgroundTransparency = 1 })
	Theme.tween(toast.Label, 0.2, { TextTransparency = 1 })
	Theme.tween(toast.Dot, 0.2, { BackgroundTransparency = 1 })
	task.delay(0.22, function()
		toast.Card:Destroy()
	end)
end

function Toast.Show(text)
	if not holder then
		return
	end
	order += 1
	local card = Theme.new("Frame", {
		Name = "Toast",
		Size = UDim2.fromOffset(0, 34),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Palette.UIPanel,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = holder,
	})
	Theme.corner(card, UDim.new(0.5, 0))
	Theme.new("UIPadding", {
		PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 16),
		Parent = card,
	})
	Theme.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
		Parent = card,
	})
	local dot = Theme.new("Frame", {
		Size = UDim2.fromOffset(6, 6),
		BackgroundColor3 = Palette.UIAccent,
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = card,
	})
	Theme.corner(dot, UDim.new(0.5, 0))
	local label = Theme.label({
		Size = UDim2.fromOffset(0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = string.upper(tostring(text)),
		TextSize = 14,
		TextTransparency = 1,
		FontFace = Theme.Font(Enum.FontWeight.Bold),
		LayoutOrder = 2,
		Parent = card,
	})
	local scale = Theme.scaleOf(card)
	scale.Scale = 0.9
	Theme.tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	Theme.tween(card, 0.18, { BackgroundTransparency = REST_FILL })
	Theme.tween(label, 0.18, { TextTransparency = 0 })
	Theme.tween(dot, 0.18, { BackgroundTransparency = 0 })
	Sfx.Play("CardPick", { Volume = 0.35, Pitch = 1.3 })

	local toast = { Card = card, Label = label, Dot = dot, Scale = scale }
	table.insert(live, toast)
	while #live > MAX_TOASTS do
		dismiss(live[1])
	end
	task.delay(SHOW_TIME, dismiss, toast)
end

function Toast.Start(playerGui)
	gui = Theme.screen("Toast", 50, playerGui)
	holder = Theme.new("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.78),
		Size = UDim2.fromOffset(640, 130),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	Theme.new("UIListLayout", {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = holder,
	})
	-- a bit smaller on phones
	local scale = Theme.scaleOf(holder)
	local function fit()
		local camera = workspace.CurrentCamera
		local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
		scale.Scale = math.clamp(math.min(viewport.X / 1100, viewport.Y / 620), 0.75, 1.15)
	end
	fit()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end
	Remotes.Get("Notify").OnClientEvent:Connect(Toast.Show)
end

return Toast
