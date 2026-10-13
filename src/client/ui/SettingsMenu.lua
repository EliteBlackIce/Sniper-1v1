--[[
	SettingsMenu.lua  (Client.ui.SettingsMenu)
	Mouse sensitivity, scoped sensitivity and hold/toggle scope.
	Open/close with P (or the lobby button). Settings save to the server
	(DataStore) when the menu closes.
]]

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ClientState = require(script.Parent.Parent.ClientState)
local Theme = require(script.Parent.Theme)

local Palette = Config.Palette

local SettingsMenu = {}

local gui, panel, unlocker
local sliders = {} -- [key] = { Set = function(value) }
local toggleButton
local assistButton
local isOpen = false

-- A horizontal slider bound to ClientState.Settings[key].
local function makeSlider(parent, order, key, labelText)
	local limits = Config.SettingsLimits[key]
	local holder = Theme.new("Frame", {
		Size = UDim2.new(1, 0, 0, 58),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	})
	Theme.label({
		Size = UDim2.new(0.7, 0, 0, 22),
		Text = labelText,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = holder,
	})
	local valueLabel = Theme.label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.3, 0, 0, 22),
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Palette.UIAccent,
		Parent = holder,
	})
	local track = Theme.new("Frame", {
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 0, 8),
		BackgroundColor3 = Palette.UIPanelLight,
		Parent = holder,
	})
	Theme.corner(track, 4)
	local fill = Theme.new("Frame", {
		Size = UDim2.fromScale(0.5, 1),
		BackgroundColor3 = Palette.UIAccent,
		Parent = track,
	})
	Theme.corner(fill, 4)
	local knob = Theme.new("TextButton", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(20, 20),
		BackgroundColor3 = Palette.UIText,
		Text = "",
		AutoButtonColor = false,
		Parent = track,
	})
	Theme.corner(knob, UDim.new(0.5, 0))

	local function show(value)
		local alpha = (value - limits.Min) / (limits.Max - limits.Min)
		fill.Size = UDim2.fromScale(alpha, 1)
		knob.Position = UDim2.fromScale(alpha, 0.5)
		valueLabel.Text = ("%.2f"):format(value)
	end

	local dragging = false
	local function setFromX(x)
		local alpha = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		local value = limits.Min + alpha * (limits.Max - limits.Min)
		value = math.floor(value * 100 + 0.5) / 100
		ClientState.SetSetting(key, value)
		show(value)
	end
	local function begin(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFromX(input.Position.X)
		end
	end
	knob.InputBegan:Connect(begin)
	track.InputBegan:Connect(begin)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	sliders[key] = { Set = show }
	show(ClientState.Settings[key])
end

local function refreshToggle()
	toggleButton.Text = ClientState.Settings.ToggleScope and "TOGGLE" or "HOLD"
	if assistButton then
		assistButton.Text = ClientState.Settings.AimAssist == false and "OFF" or "ON"
	end
end

function SettingsMenu.Open()
	if isOpen then
		return
	end
	isOpen = true
	gui.Enabled = true
	unlocker.Visible = true
	ClientState.SetMenu("Settings", true)
	panel.Size = UDim2.fromOffset(420, 346)
	Theme.tween(panel, 0.2, { Size = UDim2.fromOffset(440, 376) }, Enum.EasingStyle.Back)
end

function SettingsMenu.Close()
	if not isOpen then
		return
	end
	isOpen = false
	gui.Enabled = false
	unlocker.Visible = false
	ClientState.SetMenu("Settings", false)
	ClientState.SaveSettings()
end

function SettingsMenu.Toggle()
	if isOpen then
		SettingsMenu.Close()
	else
		SettingsMenu.Open()
	end
end

function SettingsMenu.Init() end

function SettingsMenu.Start(playerGui)
	gui = Theme.screen("Settings", 10, playerGui)
	gui.Enabled = false

	Theme.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Palette.UIBackground,
		BackgroundTransparency = 0.45,
		Parent = gui,
	})
	unlocker = Theme.mouseUnlocker(gui)

	panel = Theme.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(440, 376),
		BackgroundTransparency = 0,
		Parent = gui,
	})
	Theme.padding(panel, 22)
	Theme.new("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = panel })

	Theme.label({
		Size = UDim2.new(1, 0, 0, 34),
		Text = "SETTINGS",
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		LayoutOrder = 0,
		Parent = panel,
	})
	makeSlider(panel, 1, "Sensitivity", "Mouse sensitivity")
	makeSlider(panel, 2, "ScopedSensitivity", "Scoped sensitivity")

	local scopeRow = Theme.new("Frame", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		Parent = panel,
	})
	Theme.label({
		Size = UDim2.new(0.6, 0, 1, 0),
		Text = "Scope mode",
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = scopeRow,
	})
	toggleButton = Theme.button({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(110, 32),
		TextSize = 15,
		BackgroundColor3 = Palette.UIPanelLight,
		TextColor3 = Palette.UIText,
		Parent = scopeRow,
	})
	toggleButton.Activated:Connect(function()
		ClientState.SetSetting("ToggleScope", not ClientState.Settings.ToggleScope)
		refreshToggle()
	end)
	refreshToggle()

	-- controller aim assist on / off
	local assistRow = Theme.new("Frame", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		LayoutOrder = 4,
		Parent = panel,
	})
	Theme.label({
		Size = UDim2.new(0.6, 0, 1, 0),
		Text = "Aim assist (controller)",
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = assistRow,
	})
	assistButton = Theme.button({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(110, 32),
		TextSize = 15,
		BackgroundColor3 = Palette.UIPanelLight,
		TextColor3 = Palette.UIText,
		Parent = assistRow,
	})
	assistButton.Activated:Connect(function()
		ClientState.SetSetting("AimAssist", ClientState.Settings.AimAssist == false)
		refreshToggle()
	end)
	refreshToggle()

	local closeButton = Theme.button({
		Size = UDim2.new(1, 0, 0, 40),
		Text = "DONE",
		LayoutOrder = 5,
		Parent = panel,
	})
	closeButton.Activated:Connect(SettingsMenu.Close)

	ClientState.SettingsChanged:Connect(function(settings)
		for key, slider in pairs(sliders) do
			slider.Set(settings[key])
		end
		refreshToggle()
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed and UserInputService:GetFocusedTextBox() then
			return -- typing in chat
		end
		if input.KeyCode == Config.UI.SettingsKey then
			SettingsMenu.Toggle()
		elseif input.KeyCode == Enum.KeyCode.Escape and isOpen then
			SettingsMenu.Close()
		end
	end)
end

return SettingsMenu
