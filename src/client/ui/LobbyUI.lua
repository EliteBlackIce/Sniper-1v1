--[[
	LobbyUI.lua  (Client.ui.LobbyUI)

	The lobby / playground screen (hidden while you're in a match):
		[F] find a match (animated "searching" state while queued)
		[G] enter / leave the PLAYGROUND (free roam on the match map)
		[H] show / hide the controls list
		[B] Power-Up Lab, [P] settings
	The mouse is locked in first person, so everything has a key.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Sfx = require(script.Parent.Parent.Sfx)
local Theme = require(script.Parent.Theme)

local Palette = Config.Palette
local PLAYGROUND_KEY = Enum.KeyCode.G
local CONTROLS_KEY = Enum.KeyCode.H

local LobbyUI = {}
local Controllers

local gui, root, title, subtitle, controls, playButton, playgroundButton, statusLabel, modeChip, spinner
local shown = false
local queued = false
local controlsVisible = true

local CONTROLS = {
	{ "WASD", "Move (hold W in the air to steer)" },
	{ "SHIFT", "Sprint" },
	{ "C / CTRL", "Slide (tap). Jump out of it any time" },
	{ "SPACE", "Jump  /  Wall jump" },
	{ "HOLD SPACE", "Bunny hop (keeps all your speed)" },
	{ "", "Air strafe: hold A or D + turn the mouse that way" },
	{ "", "Wall run: jump next to a wall and hold W" },
	{ "RMB / LMB", "Scope / Fire" },
	{ "E / Q / R", "Grapple / Decoy / Blink (power-ups)" },
	{ "V", "Inspect rifle" },
	{ "B", "Power-Up Lab: try any power-up" },
	{ "G", "Playground: free roam on the match map" },
	{ "F", "Find a match" },
	{ "H / P", "Hide this list / Settings" },
}

local function styleButton(button, active)
	button.BackgroundColor3 = active and Palette.UIAccent or Palette.UIPanelLight
	button.TextColor3 = active and Palette.UIBackground or Palette.UIText
end

function LobbyUI.OnState(snapshot)
	local visible = not snapshot.InMatch
	if visible and not shown then
		-- fade + slide the whole screen in
		gui.Enabled = true
		root.GroupTransparency = 1
		root.Position = UDim2.fromOffset(0, 24)
		Theme.tween(root, 0.45, { GroupTransparency = 0, Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Quint)
	elseif not visible then
		gui.Enabled = false
	end
	shown = visible
	if not visible then
		return
	end

	queued = snapshot.Queued == true
	if queued then
		playButton.Text = "SEARCHING...   [F] CANCEL"
		styleButton(playButton, false)
		statusLabel.Text = "Waiting for an opponent  (" .. tostring(snapshot.QueueCount or 1) .. " in queue)"
	else
		playButton.Text = "[F]  FIND MATCH"
		styleButton(playButton, true)
		local count = snapshot.QueueCount or 0
		statusLabel.Text = count > 0 and (tostring(count) .. " player(s) waiting - press F to duel")
			or ("Lose a round, pick a power-up, stack a build. First to %d wins."):format(Config.Match.RoundsToWin)
	end
	spinner.Visible = queued

	if snapshot.Playground then
		title.Text = "PLAYGROUND"
		subtitle.Text = "Free roam on the match map. Press B to try power-ups on the dummies."
		playgroundButton.Text = "[G]  BACK TO LOBBY"
		modeChip.Visible = true
	else
		title.Text = "SNIPER DUEL"
		subtitle.Text = "Practise on the range, or press G for the Playground."
		playgroundButton.Text = "[G]  PLAYGROUND"
		modeChip.Visible = false
	end
end

function LobbyUI.Init(controllers)
	Controllers = controllers
end

function LobbyUI.Start(playerGui)
	gui = Theme.screen("Lobby", 2, playerGui)
	root = Theme.new("CanvasGroup", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = gui,
	})

	-- Title
	title = Theme.label({
		Position = UDim2.fromOffset(28, 64),
		Size = UDim2.fromOffset(500, 48),
		Text = "SNIPER DUEL",
		TextSize = 44,
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = root,
	})
	local underline = Theme.new("Frame", {
		Position = UDim2.fromOffset(30, 112),
		Size = UDim2.fromOffset(70, 4),
		BackgroundColor3 = Palette.UIAccent,
		Parent = root,
	})
	Theme.corner(underline, 2)
	subtitle = Theme.label({
		Position = UDim2.fromOffset(30, 122),
		Size = UDim2.fromOffset(600, 20),
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Palette.UISubText,
		FontFace = Theme.Font(Enum.FontWeight.Medium),
		Parent = root,
	})

	-- "PLAYGROUND" chip at the top
	modeChip = Theme.panel({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 64),
		Size = UDim2.fromOffset(220, 34),
		BackgroundColor3 = Palette.UIAccent,
		Visible = false,
		Parent = root,
	})
	Theme.label({
		Size = UDim2.fromScale(1, 1),
		Text = "PLAYGROUND MODE",
		TextSize = 16,
		TextColor3 = Palette.UIBackground,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = modeChip,
	})

	-- Controls
	controls = Theme.panel({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 24, 0.5, 30),
		Size = UDim2.fromOffset(400, 28 + #CONTROLS * 26),
		Parent = root,
	})
	Theme.padding(controls, 14)
	Theme.new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = controls })
	for i, c in ipairs(CONTROLS) do
		local line = Theme.new("Frame", {
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundTransparency = 1,
			LayoutOrder = i,
			Parent = controls,
		})
		if c[1] ~= "" then
			local key = Theme.new("Frame", {
				Size = UDim2.fromOffset(88, 22),
				BackgroundColor3 = Palette.UIPanelLight,
				Parent = line,
			})
			Theme.corner(key, 6)
			Theme.label({ Size = UDim2.fromScale(1, 1), Text = c[1], TextSize = 12, Parent = key })
		end
		Theme.label({
			Position = UDim2.fromOffset(98, 0),
			Size = UDim2.new(1, -98, 1, 0),
			Text = c[2],
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = c[1] == "" and Palette.UISubText or Palette.UIText,
			FontFace = Theme.Font(Enum.FontWeight.Medium),
			Parent = line,
		})
	end

	-- Buttons + status
	playButton = Theme.button({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, -180, 1, -64),
		Size = UDim2.fromOffset(340, 60),
		TextSize = 24,
		Parent = root,
	})
	playgroundButton = Theme.button({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 180, 1, -64),
		Size = UDim2.fromOffset(340, 60),
		TextSize = 24,
		BackgroundColor3 = Palette.UIPanelLight,
		TextColor3 = Palette.UIText,
		Parent = root,
	})
	spinner = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.fromOffset(22, 22),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = playButton,
	})
	Theme.corner(spinner, UDim.new(0.5, 0))
	local spinStroke = Theme.stroke(spinner, Palette.UIAccent, 3, 0)
	Theme.new("UIGradient", {
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
		Parent = spinStroke,
	})
	statusLabel = Theme.label({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -30),
		Size = UDim2.fromOffset(700, 22),
		TextSize = 15,
		TextColor3 = Palette.UISubText,
		FontFace = Theme.Font(Enum.FontWeight.Medium),
		Parent = root,
	})

	local function toggleQueue()
		Sfx.Play("CardPick", { Volume = 0.6 })
		Theme.pop(playButton)
		Remotes.Get("QueueToggle"):FireServer()
	end
	local function togglePlayground()
		Sfx.Play("CardPick", { Volume = 0.6, Pitch = 0.8 })
		Theme.pop(playgroundButton)
		Remotes.Get("PlaygroundToggle"):FireServer()
	end
	local function toggleControls()
		controlsVisible = not controlsVisible
		Theme.tween(controls, 0.3, {
			Position = controlsVisible and UDim2.new(0, 24, 0.5, 30) or UDim2.new(0, -440, 0.5, 30),
		}, Enum.EasingStyle.Quint)
	end
	playButton.Activated:Connect(toggleQueue)
	playgroundButton.Activated:Connect(togglePlayground)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed and UserInputService:GetFocusedTextBox() then
			return
		end
		if not gui.Enabled then
			return
		end
		if input.KeyCode == Config.Lobby.QueueKey then
			toggleQueue()
		elseif input.KeyCode == PLAYGROUND_KEY then
			togglePlayground()
		elseif input.KeyCode == CONTROLS_KEY then
			toggleControls()
		end
	end)

	-- Settings button
	local settingsButton = Theme.button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 64),
		Size = UDim2.fromOffset(150, 40),
		Text = "SETTINGS  (P)",
		TextSize = 15,
		BackgroundColor3 = Palette.UIPanel,
		TextColor3 = Palette.UIText,
		Parent = root,
	})
	settingsButton.Activated:Connect(function()
		Controllers.Settings.Toggle()
	end)

	-- idle animations: spinner while searching, a soft pulse on the find button
	RunService.RenderStepped:Connect(function()
		if not gui.Enabled then
			return
		end
		local t = os.clock()
		spinner.Rotation = (t * 360) % 360
		if not queued then
			local pulse = (math.sin(t * 3) + 1) / 2
			playButton.BackgroundColor3 = Palette.UIAccent:Lerp(Color3.new(1, 1, 1), pulse * 0.12)
		end
	end)

	LobbyUI.OnState({ InMatch = false, Phase = "Lobby" })
end

return LobbyUI
