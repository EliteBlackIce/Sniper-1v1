--[[
	DuelUI.lua  (Client.ui.DuelUI)

	Playing a specific person instead of the random queue:

	  DUEL A PLAYER (U / controller R-stick click / DUEL button on mobile)
	      a list of everyone in the server; CHALLENGE sends them an invite.
	      WAGER: put up keys (presets or any amount you can cover); the
	      other player sees the bet on the invite and agrees by accepting.
	      The winner takes both stakes (MatchService holds them).
	  INVITES
	      when someone challenges you (or asks for a rematch) a card pops up
	      at the top: ACCEPT or DECLINE (it expires after Config.Match.InviteTime).
	  REMATCH
	      the lobby shows a REMATCH button after a match (LobbyUI); the other
	      player gets an invite card here. Against a bot, rematch starts right away.

	The server checks everything (Remotes "Duel" / "DuelInvite", MatchService).
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Sfx = require(script.Parent.Parent.Sfx)
local Theme = require(script.Parent.Theme)
local Keybinds = require(script.Parent.Parent.Keybinds)
local ClientState = require(script.Parent.Parent.ClientState)

local Palette = Config.Palette
local player = Players.LocalPlayer

local DuelUI = {}

local gui, panel, list, unlocker, inviteHolder, wagerBox, wagerNote
local isOpen = false
local stake = 0 -- keys to wager on the next challenge
local openInvites = 0

local function updateMouse()
	local need = isOpen or openInvites > 0
	unlocker.Visible = need
	ClientState.SetMenu("Duel", need)
end

local function refreshList()
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local count = 0
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			count += 1
			local row = Theme.panel({
				Size = UDim2.new(1, 0, 0, 44),
				BackgroundColor3 = Palette.UIPanelLight,
				LayoutOrder = count,
				Parent = list,
			})
			Theme.label({
				Position = UDim2.fromOffset(14, 0),
				Size = UDim2.new(1, -170, 1, 0),
				Text = other.DisplayName,
				TextSize = 17,
				TextXAlignment = Enum.TextXAlignment.Left,
				FontFace = Theme.Font(Enum.FontWeight.Bold),
				Parent = row,
			})
			local busy = other:GetAttribute("InMatch") == true
			local button = Theme.button({
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.fromOffset(140, 32),
				Text = busy and "IN A MATCH" or "CHALLENGE",
				TextSize = 15,
				BackgroundColor3 = busy and Palette.UIPanel or Palette.UIAccent,
				TextColor3 = busy and Palette.UISubText or Palette.UIBackground,
				AutoButtonColor = not busy,
				Parent = row,
			})
			if not busy then
				button.Activated:Connect(function()
					Remotes.Get("Duel"):FireServer("Challenge", other.UserId, stake)
					Sfx.Play("CardPick", { Volume = 0.6 })
					button.Text = "SENT"
					button.BackgroundColor3 = Palette.UIPanel
					button.TextColor3 = Palette.UISubText
				end)
			end
		end
	end
	if count == 0 then
		local row = Theme.new("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, Parent = list })
		Theme.label({
			Size = UDim2.fromScale(1, 1),
			Text = "Nobody else is here yet. Invite a friend to the server!",
			TextSize = 15,
			TextColor3 = Palette.UISubText,
			Parent = row,
		})
	end
end

function DuelUI.Open()
	if isOpen or ClientState.InMatch() then
		return
	end
	isOpen = true
	panel.Visible = true
	refreshList()
	updateMouse()
	Theme.pop(panel, 0.05)
end

function DuelUI.Close()
	if not isOpen then
		return
	end
	isOpen = false
	panel.Visible = false
	updateMouse()
end

-- An invite card: "<name> challenges you" with ACCEPT / DECLINE.
local function showInvite(data)
	if typeof(data) ~= "table" then
		return
	end
	local isRematch = data.Kind == "Rematch"
	local card = Theme.panel({
		Size = UDim2.fromOffset(440, 96),
		BackgroundColor3 = Palette.UIPanel,
		Parent = inviteHolder,
	})
	Theme.stroke(card, Palette.UIAccent, 2, 0.1)
	Theme.label({
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -32, 0, 26),
		Text = isRematch and (tostring(data.Name) .. " wants a rematch!") or (tostring(data.Name) .. " challenges you to a duel!"),
		TextSize = 19,
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = card,
	})
	local timer = Theme.new("Frame", {
		Position = UDim2.new(0, 16, 0, 40),
		Size = UDim2.new(1, -32, 0, 4),
		BackgroundColor3 = Palette.UIAccent,
		Parent = card,
	})
	local wager = tonumber(data.Stake) or 0
	if wager > 0 then
		card.Size = UDim2.fromOffset(440, 118)
		Theme.label({
			Position = UDim2.fromOffset(16, 46),
			Size = UDim2.new(1, -32, 0, 20),
			Text = ("WAGER: %d KEYS EACH  -  THE WINNER TAKES %d"):format(wager, wager * 2),
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Palette.AccentB,
			Parent = card,
		})
	end
	local accept = Theme.button({
		Position = UDim2.new(0, 16, 1, -44),
		Size = UDim2.new(0.5, -22, 0, 34),
		Text = wager > 0 and ("ACCEPT  (BET %d)"):format(wager) or "ACCEPT",
		TextSize = 16,
		Parent = card,
	})
	local decline = Theme.button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 1, -44),
		Size = UDim2.new(0.5, -22, 0, 34),
		Text = "DECLINE",
		TextSize = 16,
		BackgroundColor3 = Palette.UIPanelLight,
		TextColor3 = Palette.UIText,
		Parent = card,
	})
	openInvites += 1
	updateMouse()
	Sfx.Play("CardPick", { Volume = 0.8, Pitch = 1.4 })
	Theme.pop(card, 0.1)

	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		openInvites -= 1
		updateMouse()
		card:Destroy()
	end
	accept.Activated:Connect(function()
		if isRematch then
			Remotes.Get("Duel"):FireServer("Rematch")
		else
			Remotes.Get("Duel"):FireServer("Accept", data.From)
		end
		close()
	end)
	decline.Activated:Connect(function()
		if not isRematch then
			Remotes.Get("Duel"):FireServer("Decline", data.From)
		end
		close()
	end)
	local life = tonumber(data.Time) or Config.Match.InviteTime
	Theme.tween(timer, life, { Size = UDim2.new(0, 0, 0, 4) }, Enum.EasingStyle.Linear)
	task.delay(life, close)
	-- a match starting (you accepted, or they did) clears it too
	local connection
	connection = ClientState.Changed:Connect(function(snapshot)
		if snapshot.InMatch then
			close()
		end
		if closed then
			connection:Disconnect()
		end
	end)
end

function DuelUI.Start(playerGui)
	gui = Theme.screen("Duel", 7, playerGui)
	unlocker = Theme.mouseUnlocker(gui)

	panel = Theme.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(460, 480),
		BackgroundColor3 = Palette.UIBackground,
		Visible = false,
		Parent = gui,
	})
	Theme.padding(panel, 18)
	Theme.label({
		Size = UDim2.new(1, 0, 0, 30),
		Text = "DUEL A PLAYER",
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = panel,
	})
	-- WAGER: keys each of you puts up (the winner takes both); any amount you
	-- can cover, your opponent sees it and agrees by accepting
	Theme.label({
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.fromOffset(80, 30),
		Text = "WAGER",
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Palette.AccentB,
		Parent = panel,
	})
	local presets = {}
	local function setStake(value)
		local most = tonumber(player:GetAttribute("WagerKeys")) or 0
		stake = math.clamp(math.floor(tonumber(value) or 0), 0, most)
		wagerBox.Text = stake > 0 and tostring(stake) or ""
		for amount, button in pairs(presets) do
			local on = amount == stake
			button.BackgroundColor3 = on and Palette.AccentB or Palette.UIPanelLight
			button.TextColor3 = on and Palette.UIBackground or (amount <= most and Palette.UIText or Palette.UISubText)
		end
		wagerNote.Text = ("You can bet up to %d keys (keys you earned; bought keys can't be bet)"):format(most)
	end
	for i, amount in ipairs(Config.Match.WagerOptions or { 0, 5, 10, 25 }) do
		local button = Theme.button({
			Position = UDim2.fromOffset(70 + (i - 1) * 56, 40),
			Size = UDim2.fromOffset(50, 30),
			Text = amount == 0 and "NONE" or tostring(amount),
			TextSize = 13,
			Parent = panel,
		})
		button.Activated:Connect(function()
			Sfx.Play("CardHover")
			setStake(amount)
		end)
		presets[amount] = button
	end
	wagerBox = Theme.new("TextBox", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 40),
		Size = UDim2.fromOffset(84, 30),
		PlaceholderText = "ANY",
		Text = "",
		ClearTextOnFocus = false,
		TextSize = 15,
		FontFace = Theme.Font(Enum.FontWeight.Bold),
		TextColor3 = Palette.UIText,
		PlaceholderColor3 = Palette.UISubText,
		BackgroundColor3 = Palette.UIPanelLight,
		Parent = panel,
	})
	Theme.corner(wagerBox, 8)
	wagerBox.FocusLost:Connect(function()
		setStake(wagerBox.Text:gsub("%D", ""))
	end)
	wagerNote = Theme.label({
		Position = UDim2.fromOffset(0, 74),
		Size = UDim2.new(1, 0, 0, 16),
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Palette.UISubText,
		FontFace = Theme.Font(Enum.FontWeight.Medium),
		Parent = panel,
	})
	setStake(0)
	player:GetAttributeChangedSignal("WagerKeys"):Connect(function()
		setStake(stake)
	end)

	list = Theme.new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 98),
		Size = UDim2.new(1, 0, 1, -152),
		BackgroundTransparency = 1,
		ScrollBarThickness = 4,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = panel,
	})
	Theme.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	local close = Theme.button({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.fromOffset(160, 40),
		Text = "CLOSE",
		TextSize = 17,
		Parent = panel,
	})
	close.Activated:Connect(DuelUI.Close)

	inviteHolder = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 170),
		Size = UDim2.fromOffset(440, 320),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	Theme.new("UIListLayout", {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 8),
		Parent = inviteHolder,
	})

	Remotes.Get("DuelInvite").OnClientEvent:Connect(showInvite)

	local function onActionInput(input, processed)
		if processed and UserInputService:GetFocusedTextBox() then
			return
		end
		if Keybinds.Matches("DuelFriend", input) then
			if isOpen then
				DuelUI.Close()
			else
				DuelUI.Open()
			end
		elseif input.KeyCode == Enum.KeyCode.Escape and isOpen then
			DuelUI.Close()
		end
	end
	UserInputService.InputBegan:Connect(onActionInput)
	Keybinds.VirtualBegan:Connect(onActionInput)

	Players.PlayerAdded:Connect(function()
		if isOpen then
			refreshList()
		end
	end)
	Players.PlayerRemoving:Connect(function()
		if isOpen then
			task.defer(refreshList)
		end
	end)
	ClientState.Changed:Connect(function(snapshot)
		if snapshot.InMatch then
			DuelUI.Close()
		end
	end)
end

return DuelUI
