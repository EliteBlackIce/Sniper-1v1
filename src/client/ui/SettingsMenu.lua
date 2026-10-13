--[[
	SettingsMenu.lua  (Client.ui.SettingsMenu)

	Three tabs:
		GENERAL     sliders: mouse + scoped mouse sensitivity, controller +
		            scoped controller sensitivity, controller deadzone, field
		            of view. Toggles: scope mode, invert Y (controller), aim
		            assist (controller).
		KEYBOARD    rebind every action: click a binding, then press a key or
		            mouse button (Esc cancels).
		CONTROLLER  same for controller buttons.

	Open / close with the Settings bind (P / Select). Everything saves to the
	server (DataStore) when the menu closes.
]]

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ClientState = require(script.Parent.Parent.ClientState)
local Keybinds = require(script.Parent.Parent.Keybinds)
local Sfx = require(script.Parent.Parent.Sfx)
local Theme = require(script.Parent.Theme)

local Palette = Config.Palette

local SettingsMenu = {}

local gui, panel, unlocker, pages, tabButtons
local refreshers = {} -- functions that redraw values from ClientState.Settings
local isOpen = false
local capturing = nil -- { Device, Action, Button } while waiting for a key press
local PANEL_W, PANEL_H = 560, 520

----------------------------------------------------------------------------
-- Controls
----------------------------------------------------------------------------
local function sectionTitle(parent, order, text)
	Theme.label({
		Size = UDim2.new(1, 0, 0, 22),
		Text = text,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Palette.UIAccent,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		LayoutOrder = order,
		Parent = parent,
	})
end

-- A horizontal slider bound to ClientState.Settings[key].
local function slider(parent, order, key, labelText, decimals)
	local limits = Config.SettingsLimits[key]
	local holder = Theme.new("Frame", {
		Size = UDim2.new(1, -8, 0, 50),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	})
	Theme.label({
		Size = UDim2.new(0.7, 0, 0, 20),
		Text = labelText,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.Font(Enum.FontWeight.Medium),
		Parent = holder,
	})
	local valueLabel = Theme.label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.3, 0, 0, 20),
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Palette.UIAccent,
		Parent = holder,
	})
	local track = Theme.new("Frame", {
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 0, 8),
		BackgroundColor3 = Palette.UIPanelLight,
		Parent = holder,
	})
	Theme.corner(track, 4)
	local fill = Theme.new("Frame", { Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = Palette.UIAccent, Parent = track })
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
		value = value or Config.SettingsDefaults[key]
		local alpha = (value - limits.Min) / (limits.Max - limits.Min)
		fill.Size = UDim2.fromScale(alpha, 1)
		knob.Position = UDim2.fromScale(alpha, 0.5)
		valueLabel.Text = decimals == 0 and tostring(math.floor(value + 0.5)) or ("%.2f"):format(value)
	end

	local dragging = false
	local function setFromX(x)
		local alpha = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		local value = limits.Min + alpha * (limits.Max - limits.Min)
		local factor = decimals == 0 and 1 or 100
		value = math.floor(value * factor + 0.5) / factor
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
	-- controller: select the knob and press left / right on the D-pad
	knob.SelectionGained:Connect(function()
		knob.BackgroundColor3 = Palette.UIAccent
	end)
	knob.SelectionLost:Connect(function()
		knob.BackgroundColor3 = Palette.UIText
	end)
	UserInputService.InputBegan:Connect(function(input)
		if not isOpen or game:GetService("GuiService").SelectedObject ~= knob then
			return
		end
		local step = (limits.Max - limits.Min) / 40
		local current = ClientState.Settings[key] or Config.SettingsDefaults[key]
		if input.KeyCode == Enum.KeyCode.DPadRight then
			ClientState.SetSetting(key, math.clamp(current + step, limits.Min, limits.Max))
		elseif input.KeyCode == Enum.KeyCode.DPadLeft then
			ClientState.SetSetting(key, math.clamp(current - step, limits.Min, limits.Max))
		end
	end)

	table.insert(refreshers, function(settings)
		show(settings[key])
	end)
end

-- An ON/OFF style toggle row. `labels` = { onText, offText }.
local function toggle(parent, order, key, labelText, labels)
	local row = Theme.new("Frame", {
		Size = UDim2.new(1, -8, 0, 34),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	})
	Theme.label({
		Size = UDim2.new(0.65, 0, 1, 0),
		Text = labelText,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.Font(Enum.FontWeight.Medium),
		Parent = row,
	})
	local button = Theme.button({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(120, 30),
		TextSize = 14,
		Parent = row,
	})
	local function show(settings)
		local on = settings[key]
		if on == nil then
			on = Config.SettingsDefaults[key]
		end
		button.Text = on and labels[1] or labels[2]
		button.BackgroundColor3 = on and Palette.UIAccent or Palette.UIPanelLight
		button.TextColor3 = on and Palette.UIBackground or Palette.UIText
	end
	button.Activated:Connect(function()
		local current = ClientState.Settings[key]
		if current == nil then
			current = Config.SettingsDefaults[key]
		end
		ClientState.SetSetting(key, not current)
		Theme.pop(button)
		Sfx.Play("CardHover")
	end)
	table.insert(refreshers, show)
end

----------------------------------------------------------------------------
-- Key binding rows
----------------------------------------------------------------------------
local function setBind(device, actionId, keyName)
	local binds = ClientState.Settings.Binds or {}
	binds = { Keyboard = table.clone(binds.Keyboard or {}), Gamepad = table.clone(binds.Gamepad or {}) }
	binds[device][actionId] = keyName
	ClientState.SetSetting("Binds", binds)
end

local function bindRow(parent, order, device, action)
	local row = Theme.new("Frame", {
		Size = UDim2.new(1, -8, 0, 34),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	})
	Theme.label({
		Size = UDim2.new(0.6, 0, 1, 0),
		Text = action.Name,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.Font(Enum.FontWeight.Medium),
		Parent = row,
	})
	local button = Theme.button({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(150, 30),
		TextSize = 14,
		BackgroundColor3 = Palette.UIPanelLight,
		TextColor3 = Palette.UIText,
		Parent = row,
	})
	button.Activated:Connect(function()
		capturing = { Device = device, Action = action.Id, Button = button }
		button.Text = device == "Gamepad" and "PRESS A BUTTON..." or "PRESS A KEY..."
		button.BackgroundColor3 = Palette.UIAccent
		button.TextColor3 = Palette.UIBackground
		Sfx.Play("CardHover")
	end)
	table.insert(refreshers, function()
		if capturing and capturing.Button == button then
			return
		end
		button.Text = Keybinds.Label(Keybinds.Get(action.Id, device))
		button.BackgroundColor3 = Palette.UIPanelLight
		button.TextColor3 = Palette.UIText
	end)
end

local function refreshAll()
	for _, fn in ipairs(refreshers) do
		fn(ClientState.Settings)
	end
end

-- Finishes a rebind with the pressed input (called from InputBegan).
local function tryCapture(input)
	if not capturing then
		return false
	end
	if input.KeyCode == Enum.KeyCode.Escape then
		capturing = nil
		refreshAll()
		return true
	end
	local name = Keybinds.InputName(input)
	local isPad = Keybinds.IsGamepad(input)
	local wantPad = capturing.Device == "Gamepad"
	if name == "Unknown" or name == "Thumbstick1" or name == "Thumbstick2" or isPad ~= wantPad then
		return true -- wrong kind of input: keep waiting
	end
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.MouseWheel then
		return true
	end
	local device = capturing.Device
	local action = capturing.Action
	capturing = nil
	setBind(device, action, name)
	Sfx.Play("CardPick", { Volume = 0.5 })
	return true
end

----------------------------------------------------------------------------
-- Tabs + panel
----------------------------------------------------------------------------
local function makePage(name)
	local page = Theme.new("ScrollingFrame", {
		Name = name,
		Position = UDim2.fromOffset(0, 54),
		Size = UDim2.new(1, 0, 1, -110),
		BackgroundTransparency = 1,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = Palette.UISubText,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Visible = false,
		Parent = panel,
	}, {
		Theme.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	pages[name] = page
	return page
end

local function showTab(name)
	for tabName, page in pairs(pages) do
		page.Visible = tabName == name
		local button = tabButtons[tabName]
		button.BackgroundColor3 = tabName == name and Palette.UIAccent or Palette.UIPanelLight
		button.TextColor3 = tabName == name and Palette.UIBackground or Palette.UIText
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
	refreshAll()
	local scale = Theme.scaleOf(panel)
	scale.Scale = 0.92
	Theme.tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
end

function SettingsMenu.Close()
	if not isOpen then
		return
	end
	isOpen = false
	capturing = nil
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
	pages, tabButtons = {}, {}

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
		Size = UDim2.fromOffset(PANEL_W, PANEL_H),
		BackgroundTransparency = 0,
		Parent = gui,
	})
	Theme.padding(panel, 20)

	Theme.label({
		Size = UDim2.new(0.5, 0, 0, 34),
		Text = "SETTINGS",
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = panel,
	})

	-- tabs
	local tabs = Theme.new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(330, 34),
		BackgroundTransparency = 1,
		Parent = panel,
	}, {
		Theme.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			Padding = UDim.new(0, 6),
		}),
	})
	for i, name in ipairs({ "GENERAL", "KEYBOARD", "CONTROLLER" }) do
		local button = Theme.button({
			Size = UDim2.fromOffset(i == 1 and 96 or 108, 32),
			Text = name,
			TextSize = 13,
			LayoutOrder = i,
			Parent = tabs,
		})
		tabButtons[name] = button
		button.Activated:Connect(function()
			capturing = nil
			refreshAll()
			showTab(name)
			Sfx.Play("CardHover")
		end)
	end

	-- GENERAL
	local general = makePage("GENERAL")
	sectionTitle(general, 1, "MOUSE")
	slider(general, 2, "Sensitivity", "Mouse sensitivity")
	slider(general, 3, "ScopedSensitivity", "Scoped mouse sensitivity")
	sectionTitle(general, 4, "CONTROLLER")
	slider(general, 5, "ControllerSensitivity", "Controller sensitivity")
	slider(general, 6, "ControllerScopedSensitivity", "Scoped controller sensitivity")
	slider(general, 7, "ControllerDeadzone", "Stick deadzone")
	toggle(general, 8, "InvertY", "Invert look (Y)", { "ON", "OFF" })
	toggle(general, 9, "AimAssist", "Aim assist", { "ON", "OFF" })
	sectionTitle(general, 10, "GAME")
	slider(general, 11, "FieldOfView", "Field of view", 0)
	toggle(general, 12, "ToggleScope", "Scope mode", { "TOGGLE", "HOLD" })

	-- KEYBOARD / CONTROLLER
	local keyboard = makePage("KEYBOARD")
	local controller = makePage("CONTROLLER")
	for i, action in ipairs(Keybinds.Actions) do
		bindRow(keyboard, i, "Keyboard", action)
		bindRow(controller, i, "Gamepad", action)
	end
	Theme.label({
		Size = UDim2.new(1, -8, 0, 20),
		Text = "Move with WASD / left stick and look with the mouse / right stick (not rebindable).",
		TextSize = 12,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Palette.UISubText,
		LayoutOrder = 99,
		Parent = keyboard,
	})

	-- bottom buttons
	local reset = Theme.button({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromOffset(180, 40),
		Text = "RESET DEFAULTS",
		TextSize = 14,
		BackgroundColor3 = Palette.UIPanelLight,
		TextColor3 = Palette.UIText,
		Parent = panel,
	})
	reset.Activated:Connect(function()
		capturing = nil
		for key, value in pairs(Config.SettingsDefaults) do
			ClientState.Settings[key] = value
		end
		ClientState.SetSetting("Binds", { Keyboard = {}, Gamepad = {} })
		Theme.pop(reset)
	end)
	local done = Theme.button({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromOffset(160, 40),
		Text = "DONE",
		Parent = panel,
	})
	done.Activated:Connect(SettingsMenu.Close)

	showTab("GENERAL")
	refreshAll()
	ClientState.SettingsChanged:Connect(refreshAll)

	-- shrink the panel on small screens
	local scale = Theme.scaleOf(panel)
	local function fit()
		local viewport = workspace.CurrentCamera.ViewportSize
		scale.Scale = math.min(1, (viewport.X - 30) / PANEL_W, (viewport.Y - 30) / PANEL_H)
	end
	fit()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)

	UserInputService.InputBegan:Connect(function(input, processed)
		if isOpen and tryCapture(input) then
			return
		end
		if processed and UserInputService:GetFocusedTextBox() then
			return -- typing in chat
		end
		if Keybinds.Matches("Settings", input) then
			SettingsMenu.Toggle()
		elseif input.KeyCode == Enum.KeyCode.Escape and isOpen then
			SettingsMenu.Close()
		end
	end)
end

return SettingsMenu
