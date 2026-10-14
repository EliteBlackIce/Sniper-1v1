--[[
	MobileControls.lua  (Client.ui.MobileControls)

	On-screen controls for phones and tablets. Shown while you're using a
	touch screen (hidden as soon as you use a keyboard, mouse or controller).

	  left side    Roblox's own thumbstick moves you; a small FIRE button
	               above it lets you shoot with your left thumb
	  right side   drag anywhere to look (sensitivity in Settings > Touch),
	               FIRE (you can keep dragging on it to aim), SCOPE, JUMP
	               (hold to bunny hop), SLIDE, SPRINT (toggle) and your
	               ability buttons (Grapple / Blink / Decoy, when you have them)
	  top left     one MENU button under the lobby wordmark. In the lobby it
	               opens a small list: SKINS (Locker), SHOP, DUEL, LAB and
	               SETTINGS; in a match it opens Settings directly. Nothing
	               sits near the thumbstick or the fire / jump buttons.

	Buttons don't do anything themselves: they press the same actions as
	the keys (Keybinds.Press), so every rule (cooldowns, menus...) applies.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Theme = require(script.Parent.Theme)
local Keybinds = require(script.Parent.Parent.Keybinds)
local ClientState = require(script.Parent.Parent.ClientState)

local Palette = Config.Palette
local player = Players.LocalPlayer

local MobileControls = {}
local Controllers

local gui, root, lookPad
local menuGui, menuRoot, menuButton, menuPanel
local menuOpen = false
local buttons = {} -- [name] = button
local lookTouches = {} -- [InputObject] = true: touches that turn the camera
local sprintOn = false

local function isTouch()
	return UserInputService.TouchEnabled
		and (UserInputService:GetLastInputType() == Enum.UserInputType.Touch or not UserInputService.KeyboardEnabled)
end

-- A round button. onDown/onUp get called on press / release.
local function roundButton(name, text, size, anchorPos, color, onDown, onUp, dragToLook)
	local button = Theme.new("TextButton", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = anchorPos,
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = color or Palette.UIPanel,
		BackgroundTransparency = 0.25,
		Text = text,
		TextColor3 = Palette.UIText,
		TextSize = math.floor(size * 0.2),
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		AutoButtonColor = false,
		Parent = root,
	})
	Theme.corner(button, UDim.new(0.5, 0))
	Theme.stroke(button, Palette.UIText, 2, 0.6)
	button.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		button.BackgroundTransparency = 0.05
		Theme.pop(button, 0.08)
		if dragToLook then
			lookTouches[input] = true
		end
		if onDown then
			onDown()
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		button.BackgroundTransparency = 0.25
		if onUp then
			onUp()
		end
	end)
	buttons[name] = button
	return button
end

-- same top inset rule as LobbyUI (so the MENU button sits under its wordmark)
local function topInset()
	local inset = 0
	local ok, topLeft = pcall(function()
		return GuiService:GetGuiInset()
	end)
	if ok and typeof(topLeft) == "Vector2" then
		inset = topLeft.Y
	end
	local ok2, rect = pcall(function()
		return GuiService.TopbarInset
	end)
	if ok2 and typeof(rect) == "Rect" then
		inset = math.max(inset, rect.Max.Y)
	end
	return inset
end

local function setMenuOpen(open)
	menuOpen = open
	if not menuPanel then
		return
	end
	menuPanel.Visible = open
	menuButton.BackgroundColor3 = open and Palette.UIAccent or Palette.UIPanel
	local fg = open and Palette.UIBackground or Palette.UIText
	menuButton.Label.TextColor3 = fg
	Theme.tintIcon(menuButton.Icon, fg)
	if open then
		Theme.pop(menuPanel, 0.05)
	end
end

-- One row of the MENU list: icon + label.
local function menuItem(name, text, iconName, order, onPress)
	local button = Theme.new("TextButton", {
		Name = name,
		Size = UDim2.new(1, 0, 0, 38),
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Palette.UIPanelLight,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = menuPanel,
	})
	Theme.corner(button, 8)
	local icon = Theme.icon(iconName, 16, Palette.UIText, Palette.UIPanel)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 10, 0.5, 0)
	icon.Parent = button
	Theme.label({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 36, 0.5, 0),
		Size = UDim2.new(1, -44, 0, 16),
		Text = text,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.Font(Enum.FontWeight.Bold),
		Parent = button,
	})
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			button.BackgroundTransparency = 0.4
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			button.BackgroundTransparency = 1
		end
	end)
	button.Activated:Connect(function()
		setMenuOpen(false)
		onPress()
	end)
	buttons[name] = button
	return button
end

local function hold(action)
	return function()
		Keybinds.Press(action, true)
	end, function()
		Keybinds.Press(action, false)
	end
end

local function tap(action)
	return function()
		Keybinds.Press(action, true)
		Keybinds.Press(action, false)
	end
end

local function refresh()
	local show = isTouch() and not ClientState.MenuOpen
	gui.Enabled = show
	menuGui.Enabled = show
	if not show then
		setMenuOpen(false)
		return
	end
	local stats = ClientState.Stats
	local inMatch = ClientState.InMatch()
	buttons.Grapple.Visible = stats.Grapple == true
	buttons.Blink.Visible = stats.Blink == true
	buttons.Decoy.Visible = stats.Decoy == true
	if inMatch and menuOpen then
		setMenuOpen(false) -- the list is lobby-only (MENU opens Settings in a match)
	end
	buttons.Sprint.BackgroundColor3 = sprintOn and Palette.UIAccent or Palette.UIPanel
end

function MobileControls.Init(controllers)
	Controllers = controllers
end

function MobileControls.Start(playerGui)
	gui = Theme.screen("MobileControls", 1, playerGui)
	root = Theme.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = gui })
	local scale = Theme.scaleOf(root)

	-- look pad: the right part of the screen (behind the buttons). It's
	-- Active, so Roblox's camera ignores these touches and we turn instead.
	lookPad = Theme.new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(0.55, 1),
		BackgroundTransparency = 1,
		Active = true,
		ZIndex = 0,
		Parent = gui,
	})
	lookPad.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			lookTouches[input] = true
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if lookTouches[input] and Controllers and Controllers.Camera.AddTouchLook then
			Controllers.Camera.AddTouchLook(Vector2.new(input.Delta.X, input.Delta.Y))
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		lookTouches[input] = nil
	end)

	local T = Config.Touch
	local function br(x, y)
		return UDim2.new(1, -x, 1, -y) -- from the bottom-right corner
	end
	roundButton("Fire", "FIRE", T.FireButtonSize, br(200, 175), Palette.PlayerB, function()
		Keybinds.Press("Fire", true)
	end, function()
		Keybinds.Press("Fire", false)
	end, true)
	roundButton("FireLeft", "FIRE", 70, UDim2.new(0, 120, 1, -270), Palette.PlayerB, function()
		Keybinds.Press("Fire", true)
	end, function()
		Keybinds.Press("Fire", false)
	end)
	local scopeDown, scopeUp = hold("Scope")
	roundButton("Scope", "SCOPE", 72, br(85, 215), Palette.UIPanel, scopeDown, scopeUp, true)
	local jumpDown, jumpUp = hold("Jump")
	roundButton("Jump", "JUMP", 84, br(80, 95), Palette.UIPanel, jumpDown, jumpUp)
	roundButton("Slide", "SLIDE", 64, br(190, 65), Palette.UIPanel, tap("Slide"))
	roundButton("Sprint", "RUN", 56, br(290, 60), Palette.UIPanel, function()
		sprintOn = not sprintOn
		Keybinds.Press("Sprint", sprintOn)
		refresh()
	end)
	roundButton("Grapple", "HOOK", 58, br(80, 310), Palette.UIPanel, tap("Grapple"))
	roundButton("Blink", "BLINK", 58, br(150, 300), Palette.UIPanel, tap("Blink"))
	roundButton("Decoy", "DECOY", 58, br(220, 300), Palette.UIPanel, tap("Decoy"))
	-- switch rifle <-> knife (with the knife out, FIRE slashes and SCOPE stabs)
	roundButton("Knife", "KNIFE", 58, br(305, 165), Palette.UIPanel, function()
		if Controllers and Controllers.Knife then
			Controllers.Knife.Toggle()
		end
	end)

	-- MENU (top left, under the lobby wordmark): its own ScreenGui above the
	-- lobby so the list can open over it, clear of notches like LobbyUI.
	menuGui = Theme.screen("MobileMenu", 3, playerGui)
	pcall(function()
		menuGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	end)
	menuRoot = Theme.new("Frame", {
		Name = "Menu",
		Size = UDim2.fromOffset(150, 320),
		BackgroundTransparency = 1,
		Parent = menuGui,
	})
	local menuScale = Theme.scaleOf(menuRoot)
	menuButton = Theme.new("TextButton", {
		Name = "MenuButton",
		Size = UDim2.fromOffset(96, 34),
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Palette.UIPanel,
		BackgroundTransparency = 0.15,
		Parent = menuRoot,
	})
	Theme.corner(menuButton, UDim.new(0.5, 0))
	local menuIcon = Theme.icon("menu", 14, Palette.UIText)
	menuIcon.Name = "Icon"
	menuIcon.AnchorPoint = Vector2.new(0, 0.5)
	menuIcon.Position = UDim2.new(0, 14, 0.5, 0)
	menuIcon.Parent = menuButton
	Theme.label({
		Name = "Label",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 36, 0.5, 0),
		Size = UDim2.new(1, -44, 0, 16),
		Text = "MENU",
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = menuButton,
	})
	buttons.Menu = menuButton

	menuPanel = Theme.new("Frame", {
		Name = "List",
		Position = UDim2.fromOffset(0, 34 + 6),
		Size = UDim2.fromOffset(150, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Palette.UIPanel,
		BackgroundTransparency = 0.1,
		Visible = false,
		Parent = menuRoot,
	})
	Theme.corner(menuPanel, 12)
	Theme.padding(menuPanel, 6)
	Theme.new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 2),
		Parent = menuPanel,
	})
	menuItem("Skins", "SKINS", "shirt", 1, function()
		if Controllers and Controllers.Locker then
			Controllers.Locker.Toggle()
		end
	end)
	menuItem("Shop", "SHOP", "bag", 2, function()
		if Controllers and Controllers.Shop then
			Controllers.Shop.Toggle()
		end
	end)
	menuItem("Duel", "DUEL", "swords", 3, tap("DuelFriend"))
	menuItem("Lab", "LAB", "flask", 4, tap("PowerUpLab"))
	menuItem("Settings", "SETTINGS", "gear", 5, tap("Settings"))

	local openSettings = tap("Settings")
	menuButton.Activated:Connect(function()
		Theme.pop(menuButton, 0.06)
		if ClientState.InMatch() then
			setMenuOpen(false)
			openSettings()
		else
			setMenuOpen(not menuOpen)
		end
	end)
	setMenuOpen(false)

	-- smaller on small screens. root is sized 1/scale so that, after the
	-- UIScale shrinks it, it still covers the whole screen and the buttons
	-- stay anchored to the real corners.
	local function fit()
		local viewport = workspace.CurrentCamera.ViewportSize
		scale.Scale = math.clamp(math.min(viewport.X / 900, viewport.Y / 500), 0.65, 1.2)
		root.Size = UDim2.fromScale(1 / scale.Scale, 1 / scale.Scale)
		-- MENU: same scale / margins as LobbyUI's touch layout, under its
		-- 30px wordmark row
		local s = math.clamp(math.min(viewport.X / 900, viewport.Y / 460), 0.72, 1.2)
		menuScale.Scale = s
		menuRoot.Position = UDim2.fromOffset(math.floor(12 * s), topInset() + math.floor((8 + 30 + 10) * s))
	end
	fit()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	pcall(function()
		GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(fit)
	end)

	UserInputService.LastInputTypeChanged:Connect(refresh)
	ClientState.Changed:Connect(refresh)
	ClientState.MenuChanged:Connect(refresh)
	player.CharacterAdded:Connect(function()
		sprintOn = false
		refresh()
	end)
	refresh()
end

return MobileControls
