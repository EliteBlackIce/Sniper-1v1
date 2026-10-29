--[[
	VictoryScreen.lua  (Client.ui.VictoryScreen)

	End of match. Same look as the in-match HUD banners.

	LAYOUT (top to bottom)
		tag pill        FLAWLESS (5-0) / DOWN TO THE WIRE (5-4) / OPPONENT LEFT
		title           VICTORY or DEFEAT on a faded band, underline wipe
		subtitle        "vs <name>  -  <map>"
		score           big "5 - 3" in each player's colour
		two cards       you on the left: name, WINNER chip, round wins,
		                accuracy / headshots / damage / longest hit (the better
		                number of each pair is lit), the power-ups they ended with
		rewards         rating change (+ tier, RANKED UP / DOWN), keys earned,
		                challenges finished, wager won / lost; UNRANKED against the bot
		footer          "BACK TO LOBBY" + a bar that drains

	ANIMATION
		backdrop fades in, title punches in, underline wipes, the score counts
		up, cards rise one after the other, stats count up, reward chips pop in
		one by one; confetti on a win.

	Data: the Victory snapshot carries each player's Tally (shots, hits,
	headshots, damage, longest hit) and Result (rating, keys, wager), filled
	in by the server when the match is decided (Match.lua).
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

local GOLD = Color3.fromRGB(255, 200, 60)
local WHITE = Color3.new(1, 1, 1)

local CARD_W, CARD_H = 330, 286
local CARD_GAP = 36
local ICON = 24
local STAT_TIME = 0.9 -- seconds the stat numbers take to count up

local VictoryScreen = {}

local gui, overlay, wash, root, rootScale, unlocker
local ui = {}
local isOpen = false
local openToken = 0
local counters = {} -- { Label, From, To, Format, Start } counting up
local footerBar, footerLabel

local function textStroke(label, thickness, transparency)
	return Theme.new("UIStroke", {
		Thickness = thickness or 1.5,
		Transparency = transparency or 0.55,
		Color = Palette.UIBackground,
		Parent = label,
	})
end

-- A rounded pill that grows with its text. Returns (frame, label).
local function pill(parent, text, color, textColor, height, textSize)
	local frame = Theme.new("Frame", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, height or 22),
		BackgroundColor3 = color,
		Parent = parent,
	})
	Theme.corner(frame, UDim.new(0.5, 0))
	Theme.new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = frame })
	local label = Theme.label({
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		Text = text,
		TextSize = textSize or 12,
		TextColor3 = textColor or Palette.UIBackground,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = frame,
	})
	return frame, label
end

local function clear(frame)
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function easeOut(a)
	return 1 - (1 - a) ^ 3
end

-- Counts a label up from `from` to `to` (starts after `delay`).
local function countUp(label, from, to, format, delay)
	label.Text = format(from)
	table.insert(counters, {
		Label = label,
		From = from,
		To = to,
		Format = format,
		Start = os.clock() + (delay or 0),
	})
end

----------------------------------------------------------------------------
-- Confetti: flat pieces that tumble down the screen (wins only)
----------------------------------------------------------------------------
local function confetti(token, colors)
	local vp = workspace.CurrentCamera.ViewportSize
	for i = 1, 46 do
		if openToken ~= token then
			return
		end
		local w = math.random(6, 11)
		local piece = Theme.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(math.random() * vp.X, -20),
			Size = UDim2.fromOffset(w, math.floor(w * (1.4 + math.random()))),
			Rotation = math.random(0, 180),
			BackgroundColor3 = colors[(i % #colors) + 1],
			ZIndex = 30,
			Parent = gui,
		})
		local fall = 2.2 + math.random() * 1.6
		local drift = (math.random() - 0.5) * 220
		Theme.tween(piece, fall, {
			Position = UDim2.fromOffset(piece.Position.X.Offset + drift, vp.Y + 30),
			Rotation = piece.Rotation + math.random(-540, 540),
		}, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
		task.delay(fall, function()
			piece:Destroy()
		end)
		task.wait(0.035)
	end
end

----------------------------------------------------------------------------
-- Player cards
----------------------------------------------------------------------------
local STATS = {
	{
		Name = "ACCURACY",
		Value = function(t)
			return t.Shots > 0 and math.floor(t.Hits / t.Shots * 100 + 0.5) or nil
		end,
		Format = function(v)
			return ("%d%%"):format(v)
		end,
	},
	{
		Name = "HEADSHOTS",
		Value = function(t)
			return t.Headshots
		end,
		Format = function(v)
			return tostring(math.floor(v))
		end,
	},
	{
		Name = "DAMAGE",
		Value = function(t)
			return math.floor(t.Damage + 0.5)
		end,
		Format = function(v)
			return tostring(math.floor(v))
		end,
	},
	{
		Name = "LONGEST HIT",
		Value = function(t)
			return t.Hits > 0 and t.Longest or nil
		end,
		Format = function(v)
			return ("%d studs"):format(v)
		end,
	},
}

local function buildCard(entry, other, order, isWinner, statDelay)
	local color = ClientState.GetSlotColor(entry.Slot)
	local isMe = entry.UserId == player.UserId

	-- holder keeps the layout slot; the card itself slides up inside it
	local holder = Theme.new("Frame", {
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = ui.cards,
	})
	local card = Theme.new("CanvasGroup", {
		Position = UDim2.fromOffset(0, 60),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Palette.UIPanel,
		BackgroundTransparency = 0.06,
		GroupTransparency = 1,
		Parent = holder,
	})
	Theme.corner(card, 16)
	Theme.stroke(card, color, isWinner and 2.5 or 1.5, isWinner and 0 or 0.4)

	-- colour wash at the top
	local band = Theme.new("Frame", { Size = UDim2.new(1, 0, 0, 74), BackgroundColor3 = color, Parent = card })
	Theme.fade(band, 90, { { 0, 0.55 }, { 1, 1 } })
	local edge = Theme.new("Frame", {
		Position = UDim2.fromOffset(16, 18),
		Size = UDim2.fromOffset(4, 38),
		BackgroundColor3 = color,
		Parent = card,
	})
	Theme.corner(edge, 2)

	local name = Theme.label({
		Position = UDim2.fromOffset(30, 14),
		Size = UDim2.new(1, -110, 0, 26),
		Text = entry.Name or "-",
		TextSize = 21,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = card,
	})
	textStroke(name, 1, 0.7)
	local chips = Theme.new("Frame", {
		Position = UDim2.fromOffset(30, 42),
		Size = UDim2.new(1, -110, 0, 18),
		BackgroundTransparency = 1,
		Parent = card,
	}, {
		Theme.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	if isWinner then
		pill(chips, "WINNER", GOLD, Palette.UIBackground, 18, 10)
	end
	if isMe then
		pill(chips, "YOU", Palette.UIText, Palette.UIBackground, 18, 10)
	elseif entry.IsBot then
		pill(chips, "BOT", Palette.UIPanelLight, Palette.UIText, 18, 10)
	end

	-- round wins, big, on the right
	local wins = Theme.label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -18, 0, 8),
		Size = UDim2.fromOffset(80, 52),
		Text = tostring(entry.Wins or 0),
		TextSize = 50,
		TextXAlignment = Enum.TextXAlignment.Right,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		TextColor3 = isWinner and WHITE or Palette.UISubText,
		Parent = card,
	})
	textStroke(wins, 2, 0.5)

	-- stats: label on the left, number on the right; the better one is lit
	local tally, otherTally = entry.Tally, other and other.Tally
	for i, stat in ipairs(STATS) do
		local y = 84 + (i - 1) * 30
		local row = Theme.new("Frame", {
			Position = UDim2.fromOffset(16, y),
			Size = UDim2.new(1, -32, 0, 26),
			BackgroundColor3 = Palette.UIBackground,
			BackgroundTransparency = 0.55,
			Parent = card,
		})
		Theme.corner(row, 8)
		Theme.label({
			Position = UDim2.fromOffset(12, 0),
			Size = UDim2.new(0.6, 0, 1, 0),
			Text = stat.Name,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Palette.UISubText,
			FontFace = Theme.Font(Enum.FontWeight.Heavy),
			Parent = row,
		})
		local value = tally and stat.Value(tally)
		local otherValue = otherTally and stat.Value(otherTally)
		local better = value ~= nil and value > 0 and (otherValue == nil or value > otherValue)
		local label = Theme.label({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 0),
			Size = UDim2.new(0.5, 0, 1, 0),
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Right,
			FontFace = Theme.Font(Enum.FontWeight.Heavy),
			TextColor3 = better and color:Lerp(WHITE, 0.35) or Palette.UIText,
			Parent = row,
		})
		if better then
			local dot = Theme.new("Frame", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 0, 0.5, 0),
				Size = UDim2.fromOffset(3, 14),
				BackgroundColor3 = color,
				Parent = row,
			})
			Theme.corner(dot, 2)
		end
		if value then
			countUp(label, 0, value, stat.Format, statDelay + i * 0.06)
		else
			label.Text = "-"
		end
	end

	-- the power-ups they ended with
	Theme.label({
		Position = UDim2.fromOffset(18, 208),
		Size = UDim2.new(1, -36, 0, 14),
		Text = "POWER-UPS",
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Palette.UISubText,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = card,
	})
	local grid = Theme.new("Frame", {
		Position = UDim2.fromOffset(16, 226),
		Size = UDim2.new(1, -32, 0, ICON * 2 + 4),
		BackgroundTransparency = 1,
		Parent = card,
	}, {
		Theme.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(ICON, ICON),
			CellPadding = UDim2.fromOffset(4, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local count = 0
	for _, def in ipairs(PowerUps.Definitions) do
		local stacks = entry.PowerUps and entry.PowerUps[def.Id]
		if stacks and stacks > 0 then
			count += 1
			local cell = Theme.new("Frame", { BackgroundTransparency = 1, LayoutOrder = count, Parent = grid })
			local icon = Icons.Create(def, ICON)
			icon.Parent = cell
			if stacks > 1 then
				local badge = Theme.label({
					AnchorPoint = Vector2.new(1, 1),
					Position = UDim2.new(1, 3, 1, 3),
					Size = UDim2.fromOffset(16, 12),
					Text = "x" .. stacks,
					TextSize = 10,
					FontFace = Theme.Font(Enum.FontWeight.Heavy),
					ZIndex = 3,
					Parent = cell,
				})
				textStroke(badge, 1.5, 0.2)
			end
		end
	end
	if count == 0 then
		Theme.label({
			Size = UDim2.fromOffset(CARD_W - 32, ICON),
			Text = "None - never lost a round",
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Palette.UISubText,
			Parent = grid,
		})
	end
	return card
end

----------------------------------------------------------------------------
-- Rewards
----------------------------------------------------------------------------
-- A reward chip: big value on top, a small caption under it. Returns the chip.
local function rewardChip(order, value, caption, color, tag, tagColor)
	local chip = Theme.new("Frame", {
		Size = UDim2.fromOffset(150, 62),
		BackgroundColor3 = Palette.UIBackground,
		BackgroundTransparency = 0.25,
		LayoutOrder = order,
		Visible = false,
		Parent = ui.rewards,
	})
	Theme.corner(chip, 12)
	Theme.stroke(chip, color, 1.5, 0.3)
	local big = Theme.label({
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.new(1, 0, 0, 28),
		Text = value,
		TextSize = 26,
		TextColor3 = color,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = chip,
	})
	textStroke(big, 1.5, 0.5)
	Theme.label({
		Position = UDim2.fromOffset(0, 38),
		Size = UDim2.new(1, 0, 0, 14),
		Text = caption,
		TextSize = 11,
		TextColor3 = Palette.UISubText,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = chip,
	})
	if tag then
		local frame = pill(chip, tag, tagColor or GOLD, Palette.UIBackground, 18, 10)
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.new(0.5, 0, 0, 0)
		frame.ZIndex = 2
	end
	return chip
end

local function signed(n)
	return (n >= 0 and "+" or "") .. tostring(n)
end

local function buildRewards(me)
	clear(ui.rewards)
	local result = me and me.Result or {}
	local list = {}
	if result.RatingDelta then
		local tier = Config.RankTier(result.Rating)
		local up = result.TierChange == "Up"
		local tag = result.TierChange and (up and "RANKED UP" or "RANKED DOWN") or nil
		local color = result.RatingDelta >= 0 and Palette.UIAccent or Palette.UIDanger
		table.insert(list, {
			rewardChip(1, signed(result.RatingDelta), ("%s  %d"):format(result.Tier or tier.Name, result.Rating or 0), color, tag, up and tier.Color or Palette.UIDanger),
			up,
		})
	else
		local opp = ClientState.GetOpponentEntry()
		table.insert(list, {
			rewardChip(1, "-", (opp and opp.IsBot) and "UNRANKED  -  BOT" or "UNRANKED", Palette.UISubText),
			false,
		})
	end
	if result.Keys then
		table.insert(list, { rewardChip(2, signed(result.Keys), result.Keys == 1 and "KEY" or "KEYS", GOLD), false })
	end
	if typeof(result.Challenges) == "table" and (result.Challenges.Keys or 0) > 0 then
		local n = result.Challenges.Count or 1
		table.insert(list, {
			rewardChip(4, signed(result.Challenges.Keys), n == 1 and "CHALLENGE DONE" or (n .. " CHALLENGES DONE"), Palette.UIAccent),
			true,
		})
	end
	if result.Wager then
		local won = result.Wager > 0
		table.insert(list, {
			rewardChip(3, signed(result.Wager), won and "WAGER WON" or "WAGER LOST", won and GOLD or Palette.UIDanger),
			false,
		})
	end
	return list
end

----------------------------------------------------------------------------
-- Open / close
----------------------------------------------------------------------------
local function fit()
	local vp = workspace.CurrentCamera.ViewportSize
	local scale = math.clamp(math.min(vp.X / 1000, vp.Y / 660), 0.5, 1.4)
	rootScale.Scale = scale
	root.Size = UDim2.fromScale(1 / scale, 1 / scale)
end

local function open(snapshot)
	isOpen = true
	openToken += 1
	local token = openToken
	gui.Enabled = true
	unlocker.Visible = true
	ClientState.SetMenu("Victory", true)
	table.clear(counters)
	fit()

	local won = snapshot.MatchWinnerUserId == player.UserId
	local me, opp = ClientState.GetMe(), ClientState.GetOpponentEntry()
	local accent = won and GOLD or Palette.UIDanger

	-- backdrop + a colour glow from the top
	overlay.BackgroundTransparency = 1
	Theme.tween(overlay, 0.45, { BackgroundTransparency = 0.2 })
	wash.BackgroundColor3 = accent
	wash.BackgroundTransparency = 1
	Theme.tween(wash, 0.8, { BackgroundTransparency = won and 0.55 or 0.7 })

	-- tag
	local tag
	if snapshot.Message then
		tag = snapshot.Message
	elseif me and opp then
		local loserWins = math.min(me.Wins or 0, opp.Wins or 0)
		if loserWins == 0 then
			tag = "FLAWLESS"
		elseif loserWins == (snapshot.RoundsToWin or Config.Match.RoundsToWin) - 1 then
			tag = "DOWN TO THE WIRE"
		end
	end
	ui.tag.Visible = tag ~= nil
	if tag then
		ui.tagLabel.Text = tag
		ui.tag.BackgroundColor3 = accent
		Theme.pop(ui.tag, 0.35)
	end

	-- title punches in
	ui.title.Text = won and "VICTORY" or "DEFEAT"
	ui.title.TextColor3 = won and WHITE or Palette.UIDanger
	ui.title.TextTransparency = 1
	ui.title.TextSize = 150
	Theme.tween(ui.title, 0.4, { TextSize = 104, TextTransparency = 0 }, Enum.EasingStyle.Back)
	ui.titleGradient.Enabled = won
	ui.band.Size = UDim2.fromOffset(2400, 0)
	Theme.tween(ui.band, 0.35, { Size = UDim2.fromOffset(2400, 130) }, Enum.EasingStyle.Quint)
	ui.line.BackgroundColor3 = accent
	ui.line.Size = UDim2.fromOffset(0, 4)
	Theme.tween(ui.line, 0.5, { Size = UDim2.fromOffset(340, 4) }, Enum.EasingStyle.Quint)
	ui.sub.Text = ("vs %s%s"):format(opp and opp.Name or "?", snapshot.MapName and ("  -  " .. snapshot.MapName) or "")
	ui.sub.TextTransparency = 1
	Theme.tween(ui.sub, 0.6, { TextTransparency = 0 })
	if won then
		Sfx.Play("Victory")
		Sfx.Play("RoundWon", { Pitch = 0.8 })
	else
		Sfx.Play("RoundLost", { Pitch = 0.85 })
	end

	-- score (yours first, in your colour)
	if me and opp then
		ui.scoreMe.TextColor3 = ClientState.GetSlotColor(me.Slot)
		ui.scoreOpp.TextColor3 = ClientState.GetSlotColor(opp.Slot)
		countUp(ui.scoreMe, 0, me.Wins or 0, tostring, 0.35)
		countUp(ui.scoreOpp, 0, opp.Wins or 0, tostring, 0.35)
		ui.score.Visible = true
	else
		ui.score.Visible = false
	end

	-- cards (you on the left)
	clear(ui.cards)
	local entries = {}
	if me then
		table.insert(entries, me)
	end
	if opp then
		table.insert(entries, opp)
	end
	for i, entry in ipairs(entries) do
		local other = entries[3 - i]
		local isWinner = entry.UserId == snapshot.MatchWinnerUserId
		local delay = 0.55 + i * 0.12
		local card = buildCard(entry, other, i, isWinner, delay + 0.3)
		task.delay(delay, function()
			if openToken == token then
				Theme.tween(card, 0.55, { Position = UDim2.fromOffset(0, 0), GroupTransparency = 0 }, Enum.EasingStyle.Quint)
				Sfx.Play("CardFlip", { Pitch = 0.9 + i * 0.1 })
			end
		end)
	end

	-- rewards pop in one by one
	local chips = buildRewards(me)
	for i, item in ipairs(chips) do
		local chip, big = item[1], item[2]
		task.delay(1.7 + (i - 1) * 0.35, function()
			if openToken ~= token then
				return
			end
			chip.Visible = true
			Theme.pop(chip, big and 0.35 or 0.2)
			Sfx.Play("Ding", { Pitch = 1 + i * 0.12 })
			if big then
				local center = chip.AbsolutePosition + chip.AbsoluteSize / 2
				Theme.burst(gui, center, GOLD, 18, 160, 8)
				Theme.ring(gui, center, GOLD, 220, 5)
			end
		end)
	end

	if won then
		task.spawn(confetti, token, { GOLD, Palette.UIAccent, Palette.PlayerA, Palette.PlayerB, WHITE })
	end
end

local function close()
	if not isOpen then
		return
	end
	isOpen = false
	openToken += 1
	gui.Enabled = false
	unlocker.Visible = false
	table.clear(counters)
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

----------------------------------------------------------------------------
-- Build
----------------------------------------------------------------------------
function VictoryScreen.Start(playerGui)
	gui = Theme.screen("Victory", 8, playerGui)
	gui.Enabled = false
	overlay = Theme.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Palette.UIBackground,
		BackgroundTransparency = 0.2,
		Parent = gui,
	})
	wash = Theme.new("Frame", {
		Size = UDim2.fromScale(1, 0.6),
		BackgroundColor3 = GOLD,
		BackgroundTransparency = 1,
		Parent = overlay,
	})
	Theme.fade(wash, 90, { { 0, 0 }, { 1, 1 } })
	unlocker = Theme.mouseUnlocker(gui)

	-- everything else is laid out in design pixels and scaled to fit
	root = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = overlay,
	})
	rootScale = Theme.new("UIScale", { Parent = root })

	-- vertical stack, centred on the screen
	local stack = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(CARD_W * 2 + CARD_GAP + 40, 640),
		BackgroundTransparency = 1,
		Parent = root,
	})

	-- a faded band behind the title, much wider than the stack (nothing clips it)
	ui.band = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 80),
		Size = UDim2.fromOffset(2400, 130),
		BackgroundColor3 = Palette.UIBackground,
		BackgroundTransparency = 0.4,
		Parent = stack,
	})
	Theme.fade(ui.band, 0, { { 0, 1 }, { 0.3, 0 }, { 0.7, 0 }, { 1, 1 } })

	ui.tag, ui.tagLabel = pill(stack, "", GOLD, Palette.UIBackground, 24, 13)
	ui.tag.AnchorPoint = Vector2.new(0.5, 0)
	ui.tag.Position = UDim2.new(0.5, 0, 0, 0)
	ui.tag.Visible = false

	ui.title = Theme.label({
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 0, 104),
		TextSize = 104,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = stack,
	})
	textStroke(ui.title, 3, 0.4)
	ui.titleGradient = Theme.new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(WHITE, Color3.fromRGB(255, 214, 120)),
		Parent = ui.title,
	})
	ui.line = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 132),
		Size = UDim2.fromOffset(0, 4),
		BackgroundColor3 = GOLD,
		Parent = stack,
	})
	Theme.corner(ui.line, 2)
	ui.sub = Theme.label({
		Position = UDim2.fromOffset(0, 142),
		Size = UDim2.new(1, 0, 0, 22),
		TextSize = 17,
		TextColor3 = Palette.UISubText,
		FontFace = Theme.Font(Enum.FontWeight.SemiBold),
		Parent = stack,
	})
	textStroke(ui.sub, 1, 0.6)

	-- score: "5  -  3"
	ui.score = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 168),
		Size = UDim2.fromOffset(240, 50),
		BackgroundTransparency = 1,
		Parent = stack,
	})
	ui.scoreMe = Theme.label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(0.5, -22, 0, 0),
		Size = UDim2.fromOffset(90, 50),
		TextSize = 46,
		TextXAlignment = Enum.TextXAlignment.Right,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = ui.score,
	})
	textStroke(ui.scoreMe, 2, 0.4)
	Theme.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(30, 50),
		Text = "-",
		TextSize = 34,
		TextColor3 = Palette.UISubText,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = ui.score,
	})
	ui.scoreOpp = Theme.label({
		Position = UDim2.new(0.5, 22, 0, 0),
		Size = UDim2.fromOffset(90, 50),
		TextSize = 46,
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = ui.score,
	})
	textStroke(ui.scoreOpp, 2, 0.4)

	ui.cards = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 228),
		Size = UDim2.fromOffset(CARD_W * 2 + CARD_GAP, CARD_H),
		BackgroundTransparency = 1,
		Parent = stack,
	}, {
		Theme.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, CARD_GAP),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	ui.rewards = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 238 + CARD_H),
		Size = UDim2.fromOffset(CARD_W * 2 + CARD_GAP, 70),
		BackgroundTransparency = 1,
		Parent = stack,
	}, {
		Theme.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			Padding = UDim.new(0, 14),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	-- footer: back to the lobby + a draining bar
	local footer = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(260, 30),
		BackgroundTransparency = 1,
		Parent = root,
	})
	footerLabel = Theme.label({
		Size = UDim2.new(1, 0, 0, 16),
		TextSize = 12,
		TextColor3 = Palette.UISubText,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = footer,
	})
	local track = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 22),
		Size = UDim2.new(1, 0, 0, 4),
		BackgroundColor3 = Palette.UIPanelLight,
		BackgroundTransparency = 0.3,
		Parent = footer,
	})
	Theme.corner(track, 2)
	footerBar = Theme.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Palette.UIText,
		Parent = track,
	})
	Theme.corner(footerBar, 2)

	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		if isOpen then
			fit()
		end
	end)

	RunService.RenderStepped:Connect(function()
		if not isOpen then
			return
		end
		local now = os.clock()
		for i = #counters, 1, -1 do
			local c = counters[i]
			local a = math.clamp((now - c.Start) / STAT_TIME, 0, 1)
			if a > 0 then
				c.Label.Text = c.Format(math.floor(c.From + (c.To - c.From) * easeOut(a) + 0.5))
			end
			if a >= 1 then
				table.remove(counters, i)
			end
		end
		local left = ClientState.TimeLeft()
		if left then
			footerLabel.Text = ("BACK TO LOBBY IN %d"):format(math.ceil(left))
			footerBar.Size = UDim2.fromScale(math.clamp(left / Config.Match.VictoryTime, 0, 1), 1)
		else
			footerLabel.Text = ""
		end
	end)
end

return VictoryScreen
