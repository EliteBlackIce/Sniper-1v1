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
	  top          LAB (Power-Up Lab, in the lobby), DUEL (challenge a player)
	               and a settings button

	Buttons don't do anything themselves: they press the same actions as
	the keys (Keybinds.Press), so every rule (cooldowns, menus...) applies.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
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

local function pill(name, text, pos, onPress)
	local button = Theme.button({
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = pos,
		Size = UDim2.fromOffset(78, 34),
		Text = text,
		TextSize = 14,
		BackgroundColor3 = Palette.UIPanel,
		TextColor3 = Palette.UIText,
		Parent = root,
	})
	button.Activated:Connect(onPress)
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
	if not show then
		return
	end
	local stats = ClientState.Stats
	local inMatch = ClientState.InMatch()
	buttons.Grapple.Visible = stats.Grapple == true
	buttons.Blink.Visible = stats.Blink == true
	buttons.Decoy.Visible = stats.Decoy == true
	buttons.Lab.Visible = not inMatch
	buttons.Duel.Visible = not inMatch
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

	pill("Lab", "LAB", UDim2.new(0, 60, 0, 120), tap("PowerUpLab"))
	pill("Duel", "DUEL", UDim2.new(0, 150, 0, 120), tap("DuelFriend"))
	pill("Settings", "MENU", UDim2.new(1, -60, 0, 64), tap("Settings"))

	-- smaller on small screens
	local function fit()
		local viewport = workspace.CurrentCamera.ViewportSize
		scale.Scale = math.clamp(math.min(viewport.X / 900, viewport.Y / 500), 0.65, 1.2)
	end
	fit()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)

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
