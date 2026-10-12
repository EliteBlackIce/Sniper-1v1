--[[
	LobbyUI.lua  (Client.ui.LobbyUI)
	Lobby screen: PLAY / queue button, queue status, controls list and a
	settings button. Hidden while you're in a match.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Sfx = require(script.Parent.Parent.Sfx)
local Theme = require(script.Parent.Theme)

local Palette = Config.Palette

local LobbyUI = {}
local Controllers

local gui, playButton, statusLabel

local CONTROLS = {
	{ "WASD", "Move" },
	{ "SHIFT", "Sprint  /  Air dash" },
	{ "C / CTRL", "Slide (keeps momentum)" },
	{ "SPACE", "Jump  /  Double jump  /  Wall jump" },
	{ "", "Wall run: jump next to a wall and hold W" },
	{ "RMB", "Scope" },
	{ "LMB", "Fire" },
	{ "E / Q", "Grapple / Decoy (power-ups)" },
	{ "P", "Settings" },
}

function LobbyUI.OnState(snapshot)
	gui.Enabled = not snapshot.InMatch
	if snapshot.InMatch then
		return
	end
	if snapshot.Queued then
		playButton.Text = "IN QUEUE  -  CANCEL"
		playButton.BackgroundColor3 = Palette.UIPanelLight
		playButton.TextColor3 = Palette.UIText
		statusLabel.Text = "Waiting for an opponent...  (" .. tostring(snapshot.QueueCount or 1) .. " in queue)"
	else
		playButton.Text = "PLAY"
		playButton.BackgroundColor3 = Palette.UIAccent
		playButton.TextColor3 = Palette.UIBackground
		local queued = snapshot.QueueCount or 0
		statusLabel.Text = queued > 0 and (tostring(queued) .. " player(s) waiting - press PLAY to duel")
			or "1v1 sniper duel  -  first to 4 rounds"
	end
end

function LobbyUI.Init(controllers)
	Controllers = controllers
end

function LobbyUI.Start(playerGui)
	gui = Theme.screen("Lobby", 2, playerGui)

	-- Title
	Theme.label({
		Position = UDim2.fromOffset(28, 64),
		Size = UDim2.fromOffset(400, 48),
		Text = "SNIPER DUEL",
		TextSize = 44,
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = gui,
	})
	Theme.label({
		Position = UDim2.fromOffset(30, 110),
		Size = UDim2.fromOffset(400, 20),
		Text = "Lose a round, pick a power-up. First to 4 wins.",
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Palette.UISubText,
		FontFace = Theme.Font(Enum.FontWeight.Medium),
		Parent = gui,
	})

	-- Controls
	local controls = Theme.panel({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 24, 0.5, 20),
		Size = UDim2.fromOffset(340, 28 + #CONTROLS * 26),
		Parent = gui,
	}, nil)
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
				Size = UDim2.fromOffset(78, 22),
				BackgroundColor3 = Palette.UIPanelLight,
				Parent = line,
			})
			Theme.corner(key, 6)
			Theme.label({ Size = UDim2.fromScale(1, 1), Text = c[1], TextSize = 12, Parent = key })
		end
		Theme.label({
			Position = UDim2.fromOffset(88, 0),
			Size = UDim2.new(1, -88, 1, 0),
			Text = c[2],
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = c[1] == "" and Palette.UISubText or Palette.UIText,
			FontFace = Theme.Font(Enum.FontWeight.Medium),
			Parent = line,
		})
	end

	-- Play button + status
	playButton = Theme.button({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -64),
		Size = UDim2.fromOffset(320, 64),
		Text = "PLAY",
		TextSize = 28,
		Parent = gui,
	})
	playButton.Activated:Connect(function()
		Sfx.Play("CardPick", { Volume = 0.6 })
		Remotes.Get("QueueToggle"):FireServer()
	end)
	statusLabel = Theme.label({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -30),
		Size = UDim2.fromOffset(600, 22),
		TextSize = 15,
		TextColor3 = Palette.UISubText,
		FontFace = Theme.Font(Enum.FontWeight.Medium),
		Parent = gui,
	})

	-- Settings button
	local settingsButton = Theme.button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 64),
		Size = UDim2.fromOffset(150, 40),
		Text = "SETTINGS  (P)",
		TextSize = 15,
		BackgroundColor3 = Palette.UIPanel,
		TextColor3 = Palette.UIText,
		Parent = gui,
	})
	settingsButton.Activated:Connect(function()
		Controllers.Settings.Toggle()
	end)

	LobbyUI.OnState({ InMatch = false, Phase = "Lobby" })
end

return LobbyUI
