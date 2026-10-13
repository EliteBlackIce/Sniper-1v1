--[[
	VictoryScreen.lua  (Client.ui.VictoryScreen)
	Shown when a player reaches 4 round wins: VICTORY / DEFEAT, the final
	score, and the power-ups each player ended with. Then back to the lobby.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local PowerUps = require(Shared.PowerUps)
local ClientState = require(script.Parent.Parent.ClientState)
local Sfx = require(script.Parent.Parent.Sfx)
local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.Icons)

local Palette = Config.Palette
local player = Players.LocalPlayer

local VictoryScreen = {}

local gui, overlay, title, scoreLabel, messageLabel, columns, footer, unlocker
local isOpen = false

local function buildColumn(entry, slot)
	local column = Theme.panel({
		Size = UDim2.fromOffset(300, 300),
		LayoutOrder = slot,
		Parent = columns,
	})
	Theme.padding(column, 14)
	Theme.stroke(column, ClientState.GetSlotColor(slot), 2, 0)
	Theme.label({
		Size = UDim2.new(1, 0, 0, 26),
		Text = entry.Name .. "  -  " .. tostring(entry.Wins),
		TextSize = 20,
		TextColor3 = ClientState.GetSlotColor(slot),
		Parent = column,
	})
	local grid = Theme.new("Frame", {
		Position = UDim2.fromOffset(0, 36),
		Size = UDim2.new(1, 0, 1, -36),
		BackgroundTransparency = 1,
		Parent = column,
	}, {
		Theme.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(130, 26),
			CellPadding = UDim2.fromOffset(8, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local count = 0
	for _, def in ipairs(PowerUps.Definitions) do
		local stacks = entry.PowerUps[def.Id]
		if stacks and stacks > 0 then
			count += 1
			local cell = Theme.new("Frame", { BackgroundTransparency = 1, LayoutOrder = count, Parent = grid })
			local icon = Icons.Create(def, 26)
			icon.Parent = cell
			Theme.label({
				Position = UDim2.fromOffset(32, 0),
				Size = UDim2.new(1, -32, 1, 0),
				Text = def.Name .. (stacks > 1 and (" x" .. stacks) or ""),
				TextSize = 12,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Config.Rarity[def.Rarity].Color,
				Parent = cell,
			})
		end
	end
	if count == 0 then
		Theme.label({ Text = "No power-ups", TextSize = 14, TextColor3 = Palette.UISubText, Parent = grid })
	end
end

local function open(snapshot)
	isOpen = true
	gui.Enabled = true
	unlocker.Visible = true
	ClientState.SetMenu("Victory", true)

	local won = snapshot.MatchWinnerUserId == player.UserId
	title.Text = won and "VICTORY" or "DEFEAT"
	title.TextColor3 = won and Palette.UIAccent or Palette.UIDanger
	title.TextSize = 140
	Theme.tween(title, 0.5, { TextSize = 96 }, Enum.EasingStyle.Back)
	Sfx.Play(won and "Victory" or "Hurt", { Pitch = won and 1 or 0.6 })

	local me, opp = ClientState.GetMe(), ClientState.GetOpponentEntry()
	scoreLabel.Text = (me and opp) and ("%d  -  %d"):format(me.Wins, opp.Wins) or ""
	messageLabel.Text = snapshot.Message or ""

	for _, child in ipairs(columns:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for slot, entry in ipairs(snapshot.Players or {}) do
		buildColumn(entry, slot)
	end
	overlay.BackgroundTransparency = 1
	Theme.tween(overlay, 0.4, { BackgroundTransparency = 0.15 })
end

local function close()
	if not isOpen then
		return
	end
	isOpen = false
	gui.Enabled = false
	unlocker.Visible = false
	ClientState.SetMenu("Victory", false)
end

function VictoryScreen.OnState(snapshot)
	if snapshot.InMatch and snapshot.Phase == "Victory" then
		if not isOpen then
			open(snapshot)
		end
	else
		close()
	end
end

function VictoryScreen.Init() end

function VictoryScreen.Start(playerGui)
	gui = Theme.screen("Victory", 8, playerGui)
	gui.Enabled = false
	overlay = Theme.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Palette.UIBackground,
		BackgroundTransparency = 0.15,
		Parent = gui,
	})
	unlocker = Theme.mouseUnlocker(gui)

	title = Theme.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.1),
		Size = UDim2.fromOffset(800, 110),
		TextSize = 96,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = overlay,
	})
	scoreLabel = Theme.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.1, 112),
		Size = UDim2.fromOffset(400, 50),
		TextSize = 44,
		Parent = overlay,
	})
	messageLabel = Theme.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.1, 164),
		Size = UDim2.fromOffset(600, 24),
		TextSize = 16,
		TextColor3 = Palette.UISubText,
		Parent = overlay,
	})
	columns = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.1, 210),
		Size = UDim2.fromOffset(640, 310),
		BackgroundTransparency = 1,
		Parent = overlay,
	}, {
		Theme.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 24),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	footer = Theme.label({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -40),
		Size = UDim2.fromOffset(400, 22),
		TextSize = 16,
		TextColor3 = Palette.UISubText,
		Parent = overlay,
	})

	RunService.RenderStepped:Connect(function()
		if isOpen then
			local left = ClientState.TimeLeft()
			footer.Text = left and ("Returning to lobby in %d..."):format(math.ceil(left)) or ""
		end
	end)
end

return VictoryScreen
