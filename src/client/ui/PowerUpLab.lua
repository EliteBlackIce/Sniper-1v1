--[[
	PowerUpLab.lua  (Client.ui.PowerUpLab)

	Solo testing for power-ups. In the lobby, press B to open the lab:
		* left click a power-up to add a stack, right click to remove one
		* DRAW 5 CARDS opens the real pick screen with random cards
		* CLEAR ALL removes everything
	Then close the lab and try them on the shooting range dummies.

	The server keeps your lab picks, so server-checked effects like Explosive
	Rounds, Ricochet, Decoy and Phantom Dash really work. Lab picks never
	carry into a match (matches always start with no power-ups).
]]

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local PowerUps = require(Shared.PowerUps)
local Remotes = require(Shared.Remotes)
local ClientState = require(script.Parent.Parent.ClientState)
local Sfx = require(script.Parent.Parent.Sfx)
local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.Icons)
local PickScreen = require(script.Parent.PickScreen)

local Palette = Config.Palette
local LAB_KEY = Enum.KeyCode.B

local PowerUpLab = {}

local gui, panel, grid, unlocker
local tiles = {} -- [id] = { Stacks = TextLabel, Stroke = UIStroke }
local isOpen = false

local function owned()
	return ClientState.Snapshot.PowerUps or {}
end

local function send(action, id)
	Remotes.Get("Practice"):FireServer(action, id)
end

local function refresh()
	local current = owned()
	for id, tile in pairs(tiles) do
		local stacks = current[id] or 0
		local def = PowerUps.Get(id)
		tile.Stacks.Text = stacks > 0 and ("x%d / %d"):format(stacks, def.MaxStacks or 1) or ""
		tile.Stroke.Thickness = stacks > 0 and 3 or 1
		tile.Stroke.Transparency = stacks > 0 and 0 or 0.6
		tile.Frame.BackgroundColor3 = stacks > 0 and Palette.UIPanelLight or Palette.UIPanel
	end
end

function PowerUpLab.Open()
	if isOpen or ClientState.InMatch() then
		return
	end
	isOpen = true
	gui.Enabled = true
	unlocker.Visible = true
	ClientState.SetMenu("Lab", true)
	refresh()
	panel.Size = UDim2.fromOffset(820, 520)
	Theme.tween(panel, 0.2, { Size = UDim2.fromOffset(860, 560) }, Enum.EasingStyle.Back)
end

function PowerUpLab.Close()
	if not isOpen then
		return
	end
	isOpen = false
	gui.Enabled = false
	unlocker.Visible = false
	ClientState.SetMenu("Lab", false)
end

local function drawCards()
	local cards = PowerUps.DrawCards(owned(), Config.Match.CardsPerPick)
	if #cards == 0 then
		return
	end
	PowerUpLab.Close()
	PickScreen.OpenPractice(cards, owned(), function(id)
		send("Add", id)
	end)
end

local function makeTile(def, order)
	local rarity = Config.Rarity[def.Rarity]
	local frame = Theme.new("TextButton", {
		Name = def.Id,
		Text = "",
		AutoButtonColor = true,
		BackgroundColor3 = Palette.UIPanel,
		LayoutOrder = rarity.Order * 100 + order,
		Parent = grid,
	})
	Theme.corner(frame, 10)
	local stroke = Theme.stroke(frame, rarity.Color, 1, 0.6)

	local icon = Icons.Create(def, 40)
	icon.Position = UDim2.fromOffset(8, 8)
	icon.Parent = frame
	Theme.label({
		Position = UDim2.fromOffset(56, 6),
		Size = UDim2.new(1, -60, 0, 20),
		Text = def.Name,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = frame,
	})
	Theme.label({
		Position = UDim2.fromOffset(56, 26),
		Size = UDim2.new(1, -60, 0, 16),
		Text = string.upper(def.Rarity),
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = rarity.Color,
		Parent = frame,
	})
	local stacks = Theme.label({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -8, 1, -4),
		Size = UDim2.fromOffset(60, 16),
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Palette.UIAccent,
		Parent = frame,
	})
	-- description on hover
	frame.MouseEnter:Connect(function()
		panel.Description.Text = def.Name .. ":  " .. def.Description .. "   (Stacks: " .. (def.Stacking or "-") .. ")"
	end)
	frame.Activated:Connect(function()
		Sfx.Play("CardHover")
		send("Add", def.Id)
	end)
	frame.MouseButton2Click:Connect(function()
		Sfx.Play("CardHover", { Pitch = 0.8 })
		send("Remove", def.Id)
	end)
	tiles[def.Id] = { Frame = frame, Stacks = stacks, Stroke = stroke }
end

function PowerUpLab.Init() end

function PowerUpLab.Start(playerGui)
	gui = Theme.screen("PowerUpLab", 9, playerGui)
	gui.Enabled = false
	Theme.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Palette.UIBackground,
		BackgroundTransparency = 0.4,
		Parent = gui,
	})
	unlocker = Theme.mouseUnlocker(gui)

	panel = Theme.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(860, 560),
		BackgroundTransparency = 0,
		Parent = gui,
	})
	Theme.padding(panel, 20)
	-- shrink on small screens
	local scale = Theme.new("UIScale", { Parent = panel })
	local function fit()
		local viewport = workspace.CurrentCamera.ViewportSize
		scale.Scale = math.min(1, (viewport.X - 40) / 860, (viewport.Y - 40) / 560)
	end
	fit()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)

	Theme.label({
		Size = UDim2.new(1, 0, 0, 34),
		Text = "POWER-UP LAB",
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = panel,
	})
	Theme.label({
		Position = UDim2.fromOffset(0, 36),
		Size = UDim2.new(1, 0, 0, 20),
		Text = "Try any power-up on the range.  Left click: add  -  Right click: remove  -  B: close",
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Palette.UISubText,
		FontFace = Theme.Font(Enum.FontWeight.Medium),
		Parent = panel,
	})

	-- scrolls (mouse wheel) when there are more power-ups than fit
	grid = Theme.new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 68),
		Size = UDim2.new(1, 0, 1, -150),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Palette.UISubText,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = panel,
	}, {
		Theme.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(196, 56),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	for i, def in ipairs(PowerUps.Definitions) do
		makeTile(def, i)
	end

	local description = Theme.label({
		Name = "Description",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -52),
		Size = UDim2.new(1, 0, 0, 22),
		Text = "Hover a power-up to read what it does.",
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Palette.UIText,
		FontFace = Theme.Font(Enum.FontWeight.Medium),
		Parent = panel,
	})
	description.Name = "Description"

	local draw = Theme.button({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromOffset(240, 42),
		Text = "DRAW 5 CARDS",
		TextSize = 18,
		Parent = panel,
	})
	draw.Activated:Connect(drawCards)
	local clear = Theme.button({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 252, 1, 0),
		Size = UDim2.fromOffset(160, 42),
		Text = "CLEAR ALL",
		TextSize = 18,
		BackgroundColor3 = Palette.UIPanelLight,
		TextColor3 = Palette.UIText,
		Parent = panel,
	})
	clear.Activated:Connect(function()
		send("Clear")
	end)
	local done = Theme.button({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromOffset(160, 42),
		Text = "DONE",
		TextSize = 18,
		Parent = panel,
	})
	done.Activated:Connect(PowerUpLab.Close)

	ClientState.Changed:Connect(function(snapshot)
		if snapshot.InMatch then
			PowerUpLab.Close()
		else
			refresh()
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed and UserInputService:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == LAB_KEY then
			if PickScreen.IsPracticeOpen() then
				PickScreen.Close()
			elseif isOpen then
				PowerUpLab.Close()
			elseif not ClientState.InMatch() then
				PowerUpLab.Open()
			end
		end
	end)
end

return PowerUpLab
