--[[
	LobbyUI.lua  (Client.ui.LobbyUI)

	The lobby / playground overlay (hidden while you're in a match, where the
	HUD takes over). Everything hugs the screen edges so the middle stays
	clear while you walk around the lobby in first person:

		top left      SNIPER DUEL wordmark (+ PLAYGROUND chip in the playground)
		top right     player card (avatar, name) + ONLINE, KEYS, CREDITS and RANK chips
		bottom left   action stack: REMATCH (after a match), FIND MATCH
		              (animated "searching" state with timer + queue count),
		              then Playground / Power-Up Lab / Duel / Settings /
		              Play vs bot (admins)

	The mouse is locked in first person, so every action shows its key /
	controller button in a keycap (rebindable in Settings > Keyboard /
	Controller).

	On touch screens the stack becomes one compact row at the top centre
	(Duel, Lab and Settings already have MobileControls buttons) so it never
	covers the thumbstick or the fire / jump buttons.

	Everything is laid out in "design pixels" on a single spacing scale (SP)
	and multiplied by a UIScale per corner group, so it fits a 800x400 phone
	and a 1920x1080 monitor alike.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Sfx = require(script.Parent.Parent.Sfx)
local Theme = require(script.Parent.Theme)
local Keybinds = require(script.Parent.Parent.Keybinds)
local ClientState = require(script.Parent.Parent.ClientState)

local Palette = Config.Palette
local player = Players.LocalPlayer

local LobbyUI = {}
local Controllers

-- one spacing scale for everything (design pixels, before UIScale)
local SP = { XS = 4, S = 8, M = 12, L = 16, XL = 24 }

-- sizes (design pixels)
local STACK_WIDTH = 340 -- desktop action stack
local PRIMARY_HEIGHT = 64
local REMATCH_HEIGHT = 44
local ROW_HEIGHT = 36
local ROW_GAP = 6
local COMPACT_HEIGHT = 46 -- touch: one row of buttons
local COMPACT_WIDTHS = { Rematch = 132, FindMatch = 184, Playground = 124, BotMatch = 72 }

-- secondary buttons (desktop order). Ids are Keybinds action ids.
local SECONDARY = {
	{ Id = "Playground", Text = "PLAYGROUND", Hint = "FREE ROAM" },
	{ Id = "PowerUpLab", Text = "POWER-UP LAB", Hint = "TRY BUILDS" },
	{ Id = "Locker", Text = "LOCKER", Hint = "SKINS" },
	{ Id = "Shop", Text = "SHOP", Hint = "CRATES + CREDITS" },
	{ Id = "BattlePass", Text = "BATTLE PASS", Hint = "SEASON 1" },
	{ Id = "DuelFriend", Text = "DUEL A PLAYER", Hint = "INVITE" },
	{ Id = "Settings", Text = "SETTINGS", Hint = "" },
	{ Id = "BotMatch", Text = "PLAY VS BOT", Hint = "ADMIN" },
}

local gui, root
local scrimLeft, scrimTop
local brand, brandMark, title, tagline, modeRow, modeChip, subtitle
local card, cardPanel, avatar, chipRow, onlineChip, onlineLabel, keysChip, keysLabel
local rankChip, rankLabel, rankTier, rankStroke
local creditsChip, creditsLabel
local stack, statusLabel
local primary, playButton, playgroundButton, rematchButton
local spinner, progressTrack, progressFill, shine, timeLabel, subLabel
local entries = {} -- [actionId] = button entry
local groupScales = {} -- UIScale of each anchored group

local shown = false
local queued = false
local compact = false
local searchStart = os.clock()
local lastSecs = -1
local lastKeys = nil
local lastSnapshot = { InMatch = false, Phase = "Lobby" }

-- Same rule the server uses (MatchService isAdmin); the server still checks.
local function canPlayBot()
	local admin = Config.Admin or {}
	if admin.BotForEveryone then
		return true
	end
	if admin.AllowEveryoneInStudio and RunService:IsStudio() then
		return true
	end
	return table.find(admin.UserIds or {}, player.UserId) ~= nil
end
local SHOW_BOT = canPlayBot()

local function usingGamepad()
	return UserInputService:GetLastInputType().Name:find("Gamepad") ~= nil
end

-- same rule as MobileControls (its buttons are shown exactly when this is true)
local function isTouch()
	return UserInputService.TouchEnabled
		and (UserInputService:GetLastInputType() == Enum.UserInputType.Touch or not UserInputService.KeyboardEnabled)
end

-- "F" or "D-RIGHT" depending on the device you're using
local function keyText(actionId)
	local device = usingGamepad() and "Gamepad" or "Keyboard"
	return Keybinds.Label(Keybinds.Get(actionId, device))
end

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

local function formatTime(secs)
	return string.format("%d:%02d", math.floor(secs / 60), secs % 60)
end

----------------------------------------------------------------------------
-- Buttons
----------------------------------------------------------------------------

-- A button with a keycap chip on the left, a label and an optional hint on
-- the right. Hover / press animate its UIScale and stroke.
local function makeEntry(id, parent, opts)
	opts = opts or {}
	local textSize = opts.TextSize or 15
	local button = Theme.new("TextButton", {
		Name = id,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Palette.UIPanel,
		BackgroundTransparency = 0.2,
		Parent = parent,
	})
	Theme.corner(button, opts.Radius or 10)
	local stroke = Theme.stroke(button, Palette.UIText, 1, 0.88)
	local keySize = opts.KeySize or 12
	local cap, capLabel = Theme.keycap("-", keySize, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, SP.M, 0.5, 0),
		Parent = button,
	})
	local label = Theme.label({
		Name = "Label",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, SP.M, 0.5, opts.LabelY or 0),
		Size = UDim2.new(1, -SP.M * 2, 0, textSize + 4),
		TextSize = textSize,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		FontFace = Theme.Font(opts.Weight or Enum.FontWeight.Bold),
		Parent = button,
	})
	local hint
	if opts.Hint and opts.Hint ~= "" then
		hint = Theme.label({
			Name = "Hint",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -SP.M, 0.5, 0),
			Size = UDim2.fromOffset(96, 14),
			Text = opts.Hint,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = Palette.UISubText,
			FontFace = Theme.Font(Enum.FontWeight.SemiBold),
			Parent = button,
		})
	end

	local scale = Theme.scaleOf(button)
	local entry = {
		Id = id,
		Button = button,
		Stroke = stroke,
		StrokeRest = 0.88,
		Cap = cap,
		CapLabel = capLabel,
		KeySize = keySize,
		Label = label,
		LabelY = opts.LabelY or 0,
		Hint = hint,
		Hover = false,
	}
	button.MouseEnter:Connect(function()
		entry.Hover = true
		Theme.tween(scale, 0.15, { Scale = 1.03 })
		Theme.tween(stroke, 0.15, { Transparency = math.min(entry.StrokeRest, 0.5) })
	end)
	button.MouseLeave:Connect(function()
		entry.Hover = false
		Theme.tween(scale, 0.15, { Scale = 1 })
		Theme.tween(stroke, 0.15, { Transparency = entry.StrokeRest })
	end)
	button.MouseButton1Down:Connect(function()
		Theme.tween(scale, 0.08, { Scale = 0.96 })
	end)
	button.MouseButton1Up:Connect(function()
		Theme.tween(scale, 0.25, { Scale = entry.Hover and 1.03 or 1 }, Enum.EasingStyle.Back)
	end)
	entries[id] = entry
	return entry
end

-- Sets the keycap + label of a button (and moves the label next to the cap).
local function setEntry(entry, key, text, showKey)
	entry.Label.Text = text
	local x = SP.M
	entry.Cap.Visible = showKey
	if showKey then
		local w = Theme.keycapWidth(key, entry.KeySize)
		entry.Cap.Size = UDim2.fromOffset(w, math.floor(entry.KeySize * 1.85))
		entry.CapLabel.Text = key
		x += w + SP.S + 2
	end
	entry.TextX = x
	entry.Label.Position = UDim2.new(0, x, 0.5, entry.LabelY)
	local rightPad = entry.RightPad or SP.M
	entry.Label.Size = UDim2.new(1, -(x + rightPad), 0, entry.Label.TextSize + 4)
	if entry.Hint then
		-- short keys only, so a long controller label never runs into it
		entry.Hint.Visible = showKey and #key <= 3
	end
end

-- Colours of a button: "primary" (accent), "gold" (AccentB), "active"
-- (highlighted outline) or "normal" (dark panel).
local function styleEntry(entry, style)
	local b = entry.Button
	if style == "primary" or style == "gold" then
		local color = style == "gold" and Palette.AccentB or Palette.UIAccent
		b.BackgroundColor3 = color
		b.BackgroundTransparency = 0
		entry.Label.TextColor3 = Palette.UIBackground
		entry.Stroke.Color = Palette.UIText
		entry.StrokeRest = 0.7
		entry.Cap.BackgroundColor3 = Palette.UIBackground
		entry.CapLabel.TextColor3 = color
	elseif style == "active" then
		b.BackgroundColor3 = Palette.UIPanel
		b.BackgroundTransparency = 0.08
		entry.Label.TextColor3 = Palette.UIAccent
		entry.Stroke.Color = Palette.UIAccent
		entry.StrokeRest = 0.25
		entry.Cap.BackgroundColor3 = Palette.UIPanelLight
		entry.CapLabel.TextColor3 = Palette.UIText
	else
		b.BackgroundColor3 = Palette.UIPanel
		b.BackgroundTransparency = 0.2
		entry.Label.TextColor3 = Palette.UIText
		entry.Stroke.Color = Palette.UIText
		entry.StrokeRest = 0.88
		entry.Cap.BackgroundColor3 = Palette.UIPanelLight
		entry.CapLabel.TextColor3 = Palette.UIText
	end
	entry.Stroke.Transparency = entry.Hover and math.min(entry.StrokeRest, 0.5) or entry.StrokeRest
end

----------------------------------------------------------------------------
-- Layout
----------------------------------------------------------------------------

local function secondaryVisible(id)
	if id == "BotMatch" then
		return SHOW_BOT
	end
	if id == "Playground" then
		return true
	end
	return not compact -- Lab / Duel / Settings have MobileControls buttons on touch
end

local function layoutStack()
	local rematchOn = lastSnapshot.Rematch ~= nil
	rematchButton.Visible = rematchOn

	local function place(entry, x, y, w, h)
		entry.Button.Visible = true
		entry.Button.Size = UDim2.fromOffset(w, h)
		entry.Button.Position = UDim2.fromOffset(x + w / 2, y + h / 2)
	end

	if compact then
		-- one row at the top centre
		local order = {}
		if rematchOn then
			table.insert(order, "Rematch")
		end
		table.insert(order, "FindMatch")
		table.insert(order, "Playground")
		if SHOW_BOT then
			table.insert(order, "BotMatch")
		end
		for _, item in ipairs(SECONDARY) do
			entries[item.Id].Button.Visible = false
		end
		local x = 0
		for _, id in ipairs(order) do
			local w = COMPACT_WIDTHS[id]
			place(entries[id], x, 0, w, COMPACT_HEIGHT)
			x += w + SP.S
		end
		x -= SP.S
		statusLabel.Visible = true
		statusLabel.Position = UDim2.fromOffset(0, COMPACT_HEIGHT + SP.S)
		statusLabel.Size = UDim2.fromOffset(x, 16)
		statusLabel.TextXAlignment = Enum.TextXAlignment.Center
		stack.Size = UDim2.fromOffset(x, COMPACT_HEIGHT + SP.S + 16)
		return x
	else
		-- vertical stack, bottom left
		local y = 0
		if rematchOn then
			place(entries.Rematch, 0, y, STACK_WIDTH, REMATCH_HEIGHT)
			y += REMATCH_HEIGHT + SP.S
		end
		place(primary, 0, y, STACK_WIDTH, PRIMARY_HEIGHT)
		y += PRIMARY_HEIGHT + SP.M
		for _, item in ipairs(SECONDARY) do
			local entry = entries[item.Id]
			if secondaryVisible(item.Id) then
				place(entry, 0, y, STACK_WIDTH, ROW_HEIGHT)
				y += ROW_HEIGHT + ROW_GAP
			else
				entry.Button.Visible = false
			end
		end
		y -= ROW_GAP
		statusLabel.Visible = false
		stack.Size = UDim2.fromOffset(STACK_WIDTH, y)
	end
	return 0
end

local function layoutBrand()
	if compact then
		brandMark.Size = UDim2.fromOffset(30, 30)
		title.Position = UDim2.fromOffset(30 + SP.S, 0)
		title.Size = UDim2.fromOffset(180, 30)
		title.TextSize = 20
		title.Visible = true
		tagline.Visible = false
		modeRow.Visible = false
		brand.Size = UDim2.fromOffset(220, 30)
	else
		brandMark.Size = UDim2.fromOffset(48, 48)
		title.Position = UDim2.fromOffset(48 + SP.M, -2)
		title.Size = UDim2.fromOffset(320, 34)
		title.TextSize = 32
		title.Visible = true
		tagline.Visible = true
		modeRow.Visible = lastSnapshot.Playground == true
		brand.Size = UDim2.fromOffset(420, 48 + SP.M + 26)
	end
end

local function layoutCard()
	if compact then
		cardPanel.Visible = false
		onlineChip.Visible = false
		chipRow.Position = UDim2.fromScale(1, 0)
		card.Size = UDim2.fromOffset(200, 28)
	else
		cardPanel.Visible = true
		onlineChip.Visible = true
		chipRow.Position = UDim2.new(1, 0, 0, 56 + SP.S)
		card.Size = UDim2.fromOffset(260, 56 + SP.S + 28)
	end
end

-- Positions every group for the current screen size / device.
local function relayout()
	compact = isTouch()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local scale
	if compact then
		scale = math.clamp(math.min(viewport.X / 900, viewport.Y / 460), 0.72, 1.2)
	else
		scale = math.clamp(math.min(viewport.X / 1400, viewport.Y / 800), 0.6, 1.35)
	end
	for _, uiScale in ipairs(groupScales) do
		uiScale.Scale = scale
	end

	local margin = math.floor((compact and SP.M or SP.XL) * scale)
	local top = topInset() + math.floor((compact and SP.S or SP.L) * scale)
	brand.Position = UDim2.fromOffset(margin, top)
	card.Position = UDim2.new(1, -margin, 0, top)
	if compact then
		stack.AnchorPoint = Vector2.new(0.5, 0)
		stack.Position = UDim2.new(0.5, 0, 0, top)
	else
		stack.AnchorPoint = Vector2.new(0, 1)
		stack.Position = UDim2.new(0, margin, 1, -margin)
	end

	-- soft scrims so text stays readable over the 3D lobby (centre stays clear)
	scrimLeft.Visible = not compact
	scrimTop.Size = UDim2.new(1, 120, compact and 0.3 or 0.22, 60)

	-- text sizes for the compact row
	primary.Label.TextSize = compact and 18 or 22
	subLabel.TextSize = compact and 11 or 12
	primary.RightPad = compact and 36 or 112
	timeLabel.Visible = queued and not compact
	entries.Rematch.Label.TextSize = compact and 14 or 15
	for _, item in ipairs(SECONDARY) do
		entries[item.Id].Label.TextSize = compact and 14 or 15
	end

	layoutBrand()
	layoutCard()
	local rowWidth = layoutStack()
	if compact then
		-- a very wide row (rematch + bot on a small phone): keep just the mark
		local brandRight = margin + (30 + SP.S + 150) * scale
		local rowLeft = viewport.X / 2 - rowWidth * scale / 2
		title.Visible = rowLeft > brandRight + SP.S
	end
end

----------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------

local function updateSearchText()
	local secs = math.max(0, math.floor(os.clock() - searchStart))
	lastSecs = secs
	local time = formatTime(secs)
	timeLabel.Text = time
	if compact then
		subLabel.Text = time .. " · TAP TO CANCEL"
	else
		subLabel.Text = string.format("%d IN QUEUE  ·  PRESS TO CANCEL", lastSnapshot.QueueCount or 1)
	end
end

local function refreshPrimary(snapshot)
	local showKey = not compact
	local count = snapshot.QueueCount or 0
	if queued then
		setEntry(primary, keyText("FindMatch"), "SEARCHING", showKey)
		styleEntry(primary, "active")
		primary.Label.TextColor3 = Palette.UIText
		subLabel.TextColor3 = Palette.UISubText
		subLabel.TextTransparency = 0
		updateSearchText()
	else
		setEntry(primary, keyText("FindMatch"), "FIND MATCH", showKey)
		styleEntry(primary, "primary")
		subLabel.TextColor3 = Palette.UIBackground
		subLabel.TextTransparency = 0.25
		if count > 0 then
			subLabel.Text = string.format("%d PLAYER%s WAITING", count, count == 1 and "" or "S")
		else
			subLabel.Text = string.format("1V1  ·  FIRST TO %d", Config.Match.RoundsToWin or 5)
		end
	end
	subLabel.Position = UDim2.new(0, primary.TextX or SP.M, 0.5, compact and 10 or 12)
	subLabel.Size = UDim2.new(1, -((primary.TextX or SP.M) + (compact and 36 or 48)), 0, 16)
	spinner.Visible = queued
	progressTrack.Visible = queued
	timeLabel.Visible = queued and not compact
	shine.Visible = not queued
end

local function refreshRematch(snapshot)
	local rematch = snapshot.Rematch
	local entry = entries.Rematch
	if not rematch then
		return
	end
	local name = string.upper(tostring(rematch.Name or "?"))
	local showKey = not compact
	if rematch.Requested then
		setEntry(entry, keyText("Rematch"), compact and "WAITING..." or ("WAITING FOR " .. name .. "..."), showKey)
		styleEntry(entry, "normal")
	elseif rematch.TheyRequested then
		setEntry(entry, keyText("Rematch"), compact and "ACCEPT" or ("ACCEPT REMATCH VS " .. name), showKey)
		styleEntry(entry, "gold")
	else
		setEntry(entry, keyText("Rematch"), compact and "REMATCH" or ("REMATCH " .. name), showKey)
		styleEntry(entry, "gold")
	end
end

local function refreshSecondaries(snapshot)
	local showKey = not compact
	for _, item in ipairs(SECONDARY) do
		local entry = entries[item.Id]
		local text = item.Text
		local style = "normal"
		if item.Id == "Playground" and snapshot.Playground then
			text = "BACK TO LOBBY"
			style = "active"
			if entry.Hint then
				entry.Hint.Text = "EXIT"
			end
		elseif item.Id == "Playground" and entry.Hint then
			entry.Hint.Text = item.Hint
		end
		if compact and item.Id == "BotMatch" then
			text = "BOT"
		elseif compact and item.Id == "Playground" and snapshot.Playground then
			text = "TO LOBBY"
		end
		setEntry(entry, keyText(item.Id), text, showKey)
		styleEntry(entry, style)
	end
end

local function refreshInfo(snapshot)
	local online = #Players:GetPlayers()
	onlineLabel.Text = string.format("%d ONLINE", online)

	-- playground chip under the wordmark (desktop) / status line (touch)
	modeChip.Visible = snapshot.Playground == true
	subtitle.Text = snapshot.Playground and "Free roam on the match map." or ""
	modeRow.Visible = snapshot.Playground == true and not compact

	local parts = {}
	if snapshot.Playground then
		table.insert(parts, "PLAYGROUND MODE")
	end
	table.insert(parts, string.format("%d ONLINE", online))
	local count = snapshot.QueueCount or 0
	if not queued and count > 0 then
		table.insert(parts, string.format("%d IN QUEUE", count))
	end
	statusLabel.Text = table.concat(parts, "  ·  ")
end

-- RANK chip: your tier + rating (RankService's "Rating" attribute)
local function refreshRank()
	local rating = tonumber(player:GetAttribute("Rating"))
	rankChip.Visible = rating ~= nil
	if not rating then
		return
	end
	local tier = Config.RankTier(rating)
	rankTier.Text = tier.Name
	rankTier.TextColor3 = tier.Color
	rankStroke.Color = tier.Color
	rankLabel.Text = tostring(math.floor(rating))
end

local function refreshKeys()
	local keys = tonumber(player:GetAttribute("Keys")) or 0
	keysLabel.Text = tostring(math.floor(keys))
	if lastKeys and keys > lastKeys and shown then
		Theme.pop(keysChip, 0.2)
	end
	lastKeys = keys
end

function LobbyUI.OnState(snapshot)
	lastSnapshot = snapshot
	if not gui then
		return
	end
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

	local wasQueued = queued
	queued = snapshot.Queued == true
	if queued and not wasQueued then
		searchStart = os.clock()
		lastSecs = -1
	end

	relayout()
	refreshPrimary(snapshot)
	refreshRematch(snapshot)
	refreshSecondaries(snapshot)
	refreshInfo(snapshot)
end

function LobbyUI.Init(controllers)
	Controllers = controllers
end

----------------------------------------------------------------------------
-- Build
----------------------------------------------------------------------------

-- A group anchored to a screen corner, scaled as one piece.
local function group(name, anchor)
	local frame = Theme.new("Frame", {
		Name = name,
		AnchorPoint = anchor,
		BackgroundTransparency = 1,
		Parent = root,
	})
	table.insert(groupScales, Theme.scaleOf(frame))
	return frame
end

-- Crosshair logo mark: dark tile, accent ring, four ticks, red dot.
local function buildMark(parent)
	local tile = Theme.new("Frame", {
		Name = "Mark",
		BackgroundColor3 = Palette.UIPanel,
		BackgroundTransparency = 0.1,
		Parent = parent,
	})
	Theme.corner(tile, UDim.new(0.24, 0))
	Theme.stroke(tile, Palette.UIAccent, 1.5, 0.55)
	local ring = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.54, 0.54),
		BackgroundTransparency = 1,
		Parent = tile,
	})
	Theme.corner(ring, UDim.new(0.5, 0))
	Theme.stroke(ring, Palette.UIAccent, 2.5, 0)
	local ticks = {
		{ UDim2.fromScale(0.5, 0.15), UDim2.new(0, 2, 0.2, 0) },
		{ UDim2.fromScale(0.5, 0.85), UDim2.new(0, 2, 0.2, 0) },
		{ UDim2.fromScale(0.15, 0.5), UDim2.new(0.2, 0, 0, 2) },
		{ UDim2.fromScale(0.85, 0.5), UDim2.new(0.2, 0, 0, 2) },
	}
	for _, t in ipairs(ticks) do
		Theme.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = t[1],
			Size = t[2],
			BackgroundColor3 = Palette.UIText,
			Parent = tile,
		})
	end
	local dot = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.12, 0.12),
		BackgroundColor3 = Palette.PlayerB,
		Parent = tile,
	})
	Theme.corner(dot, UDim.new(0.5, 0))
	return tile
end

-- Little gold key glyph for the KEYS chip.
local function buildKeyIcon(parent)
	local icon = Theme.new("Frame", {
		Name = "KeyIcon",
		Size = UDim2.fromOffset(18, 18),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = parent,
	})
	local bow = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(9, 9),
		BackgroundTransparency = 1,
		Parent = icon,
	})
	Theme.corner(bow, UDim.new(0.5, 0))
	Theme.stroke(bow, Palette.AccentB, 2, 0)
	Theme.new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 9, 0.5, 0),
		Size = UDim2.fromOffset(9, 2),
		BackgroundColor3 = Palette.AccentB,
		Parent = icon,
	})
	Theme.new("Frame", {
		Position = UDim2.new(0, 13, 0.5, 0),
		Size = UDim2.fromOffset(2, 4),
		BackgroundColor3 = Palette.AccentB,
		Parent = icon,
	})
	Theme.new("Frame", {
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.fromOffset(2, 3),
		BackgroundColor3 = Palette.AccentB,
		Parent = icon,
	})
	return icon
end

-- A pill chip with a horizontal row inside (icon, value, caption).
local function buildChip(name, parent, order, strokeColor)
	local chip = Theme.new("Frame", {
		Name = name,
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Palette.UIPanel,
		BackgroundTransparency = 0.15,
		LayoutOrder = order,
		Parent = parent,
	})
	Theme.corner(chip, UDim.new(0.5, 0))
	Theme.stroke(chip, strokeColor or Palette.UIText, 1, strokeColor and 0.45 or 0.88)
	Theme.new("UIPadding", {
		PaddingLeft = UDim.new(0, SP.M - 2),
		PaddingRight = UDim.new(0, SP.M),
		Parent = chip,
	})
	Theme.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, SP.XS + 2),
		Parent = chip,
	})
	return chip
end

local function buildBrand()
	brand = group("Brand", Vector2.new(0, 0))
	brandMark = buildMark(brand)
	title = Theme.label({
		Name = "Title",
		RichText = true,
		Text = string.format('SNIPER <font color="#%s">DUEL</font>', Palette.UIAccent:ToHex()),
		TextSize = 32,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = brand,
	})
	tagline = Theme.label({
		Name = "Tagline",
		Position = UDim2.fromOffset(48 + SP.M, 32),
		Size = UDim2.fromOffset(320, 14),
		Text = "1V1 SNIPER ARENA",
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Palette.UISubText,
		FontFace = Theme.Font(Enum.FontWeight.SemiBold),
		Parent = brand,
	})

	-- "PLAYGROUND" chip + explanation under the wordmark
	modeRow = Theme.new("Frame", {
		Name = "Mode",
		Position = UDim2.fromOffset(0, 48 + SP.M),
		Size = UDim2.fromOffset(420, 26),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = brand,
	})
	modeChip = Theme.new("Frame", {
		Size = UDim2.fromOffset(118, 26),
		BackgroundColor3 = Palette.AccentB,
		Parent = modeRow,
	})
	Theme.corner(modeChip, UDim.new(0.5, 0))
	Theme.label({
		Size = UDim2.fromScale(1, 1),
		Text = "PLAYGROUND",
		TextSize = 13,
		TextColor3 = Palette.UIBackground,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = modeChip,
	})
	subtitle = Theme.label({
		Position = UDim2.fromOffset(118 + SP.S + 2, 0),
		Size = UDim2.new(1, -(118 + SP.S + 2), 1, 0),
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Palette.UIText,
		FontFace = Theme.Font(Enum.FontWeight.Medium),
		Parent = modeRow,
	})
end

local function buildCard()
	card = group("Player", Vector2.new(1, 0))

	cardPanel = Theme.new("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(260, 56),
		BackgroundColor3 = Palette.UIPanel,
		BackgroundTransparency = 0.15,
		Parent = card,
	})
	Theme.corner(cardPanel, 12)
	Theme.stroke(cardPanel, Palette.UIText, 1, 0.88)
	avatar = Theme.new("ImageLabel", {
		Name = "Avatar",
		Position = UDim2.fromOffset(SP.S, SP.S),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = Palette.UIPanelLight,
		ScaleType = Enum.ScaleType.Crop,
		Image = "",
		Parent = cardPanel,
	})
	Theme.corner(avatar, UDim.new(0.5, 0))
	Theme.stroke(avatar, Palette.UIAccent, 2, 0.2)
	Theme.label({
		Name = "DisplayName",
		Position = UDim2.fromOffset(40 + SP.L, 9),
		Size = UDim2.new(1, -(40 + SP.L + SP.M), 0, 20),
		Text = player.DisplayName,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		FontFace = Theme.Font(Enum.FontWeight.Bold),
		Parent = cardPanel,
	})
	Theme.label({
		Name = "UserName",
		Position = UDim2.fromOffset(40 + SP.L, 30),
		Size = UDim2.new(1, -(40 + SP.L + SP.M), 0, 16),
		Text = "@" .. player.Name,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = Palette.UISubText,
		FontFace = Theme.Font(Enum.FontWeight.Medium),
		Parent = cardPanel,
	})
	task.spawn(function()
		local ok, image = pcall(function()
			return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		end)
		avatar.Image = (ok and image)
			or ("rbxthumb://type=AvatarHeadShot&id=" .. tostring(player.UserId) .. "&w=150&h=150")
	end)

	-- chips under the card: ONLINE, KEYS (right aligned)
	chipRow = Theme.new("Frame", {
		Name = "Chips",
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(260, 28),
		BackgroundTransparency = 1,
		Parent = card,
	})
	Theme.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, SP.S),
		Parent = chipRow,
	})

	onlineChip = buildChip("Online", chipRow, 1)
	local dot = Theme.new("Frame", {
		Size = UDim2.fromOffset(8, 8),
		BackgroundColor3 = Palette.AccentA,
		LayoutOrder = 1,
		Parent = onlineChip,
	})
	Theme.corner(dot, UDim.new(0.5, 0))
	onlineLabel = Theme.label({
		Size = UDim2.fromOffset(0, 16),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = "1 ONLINE",
		TextSize = 12,
		FontFace = Theme.Font(Enum.FontWeight.Bold),
		LayoutOrder = 2,
		Parent = onlineChip,
	})

	keysChip = buildChip("Keys", chipRow, 2, Palette.AccentB)
	buildKeyIcon(keysChip)
	keysLabel = Theme.label({
		Size = UDim2.fromOffset(0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = "0",
		TextSize = 15,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		LayoutOrder = 2,
		Parent = keysChip,
	})
	Theme.label({
		Size = UDim2.fromOffset(0, 16),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = "KEYS",
		TextSize = 11,
		TextColor3 = Palette.UISubText,
		FontFace = Theme.Font(Enum.FontWeight.Bold),
		LayoutOrder = 3,
		Parent = keysChip,
	})
	creditsChip = buildChip("Credits", chipRow, 3, Color3.fromRGB(255, 196, 60))
	creditsLabel = Theme.label({
		Size = UDim2.fromOffset(0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = "0",
		TextSize = 15,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		LayoutOrder = 1,
		Parent = creditsChip,
	})
	Theme.label({
		Size = UDim2.fromOffset(0, 16),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = "CREDITS",
		TextSize = 11,
		TextColor3 = Palette.UISubText,
		FontFace = Theme.Font(Enum.FontWeight.Bold),
		LayoutOrder = 2,
		Parent = creditsChip,
	})
	rankChip = buildChip("Rank", chipRow, 4, Palette.UIText)
	rankStroke = rankChip:FindFirstChildOfClass("UIStroke")
	rankTier = Theme.label({
		Size = UDim2.fromOffset(0, 16),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = "",
		TextSize = 12,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		LayoutOrder = 1,
		Parent = rankChip,
	})
	rankLabel = Theme.label({
		Size = UDim2.fromOffset(0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = "",
		TextSize = 15,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		LayoutOrder = 2,
		Parent = rankChip,
	})
	rankChip.Visible = false
end

local function buildStack()
	stack = group("Actions", Vector2.new(0, 1))

	-- REMATCH (after a match, for a little while)
	local rematch = makeEntry("Rematch", stack, { TextSize = 15, Weight = Enum.FontWeight.Heavy })
	rematchButton = rematch.Button
	rematchButton.Visible = false

	-- FIND MATCH (primary)
	primary = makeEntry("FindMatch", stack, {
		TextSize = 22,
		KeySize = 14,
		Radius = 12,
		LabelY = -8,
		Weight = Enum.FontWeight.Heavy,
	})
	playButton = primary.Button
	subLabel = Theme.label({
		Name = "Sub",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, SP.M, 0.5, 12),
		Size = UDim2.new(1, -SP.M * 2, 0, 16),
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		FontFace = Theme.Font(Enum.FontWeight.Bold),
		Parent = playButton,
	})
	spinner = Theme.new("Frame", {
		Name = "Spinner",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -SP.L, 0.5, 0),
		Size = UDim2.fromOffset(22, 22),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = playButton,
	})
	Theme.corner(spinner, UDim.new(0.5, 0))
	local spinStroke = Theme.stroke(spinner, Palette.UIAccent, 3, 0)
	Theme.fade(spinStroke, 0, { { 0, 0 }, { 1, 1 } })
	timeLabel = Theme.label({
		Name = "Time",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -(SP.L + 22 + SP.M), 0.5, -8),
		Size = UDim2.fromOffset(60, 22),
		Text = "0:00",
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Palette.UIAccent,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Visible = false,
		Parent = playButton,
	})
	-- indeterminate progress bar along the bottom while searching
	progressTrack = Theme.new("Frame", {
		Name = "Progress",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -5),
		Size = UDim2.new(1, -SP.L * 2, 0, 3),
		BackgroundColor3 = Palette.UIPanelLight,
		ClipsDescendants = true,
		Visible = false,
		Parent = playButton,
	})
	Theme.corner(progressTrack, 2)
	progressFill = Theme.new("Frame", {
		Size = UDim2.fromScale(0.35, 1),
		BackgroundColor3 = Palette.UIAccent,
		Parent = progressTrack,
	})
	Theme.corner(progressFill, 2)
	shine = Theme.shine(playButton, 1.4, true, 0.22)

	-- secondary actions
	for i, item in ipairs(SECONDARY) do
		local entry = makeEntry(item.Id, stack, { TextSize = 15, Hint = item.Hint })
		entry.Button.LayoutOrder = i
	end
	playgroundButton = entries.Playground.Button

	-- status line (compact layout: online / queue / playground)
	statusLabel = Theme.label({
		Name = "Status",
		Size = UDim2.fromOffset(300, 16),
		TextSize = 12,
		TextColor3 = Palette.UIText,
		TextTransparency = 0.1,
		FontFace = Theme.Font(Enum.FontWeight.SemiBold),
		Visible = false,
		Parent = stack,
	})
	Theme.new("UIStroke", {
		Thickness = 1,
		Transparency = 0.6,
		Color = Palette.UIBackground,
		Parent = statusLabel,
	})
end

function LobbyUI.Start(playerGui)
	gui = Theme.screen("Lobby", 2, playerGui)
	-- keep clear of notches / rounded corners (the top bar is handled by topInset)
	pcall(function()
		gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	end)
	root = Theme.new("CanvasGroup", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = gui,
	})

	-- soft gradient scrims behind the panels (never over the centre)
	scrimLeft = Theme.new("Frame", {
		Name = "ScrimLeft",
		Position = UDim2.fromOffset(-60, -60),
		Size = UDim2.new(0.5, 60, 1, 120),
		BackgroundColor3 = Palette.UIBackground,
		ZIndex = 0,
		Parent = root,
	})
	Theme.fade(scrimLeft, 0, { { 0, 0.3 }, { 0.45, 0.68 }, { 1, 1 } })
	scrimTop = Theme.new("Frame", {
		Name = "ScrimTop",
		Position = UDim2.fromOffset(-60, -60),
		Size = UDim2.new(1, 120, 0.22, 60),
		BackgroundColor3 = Palette.UIBackground,
		ZIndex = 0,
		Parent = root,
	})
	Theme.fade(scrimTop, 90, { { 0, 0.35 }, { 1, 1 } })

	buildBrand()
	buildCard()
	buildStack()

	local function toggleQueue()
		Sfx.Play("CardPick", { Volume = 0.6 })
		Theme.pop(playButton, 0.06)
		Remotes.Get("QueueToggle"):FireServer()
	end
	local function togglePlayground()
		Sfx.Play("CardPick", { Volume = 0.6, Pitch = 0.8 })
		Theme.pop(playgroundButton, 0.06)
		Remotes.Get("PlaygroundToggle"):FireServer()
	end
	local function requestRematch()
		Sfx.Play("CardPick", { Volume = 0.6, Pitch = 1.1 })
		Theme.pop(rematchButton, 0.06)
		Remotes.Get("Duel"):FireServer("Rematch")
	end
	rematchButton.Activated:Connect(requestRematch)

	local function botMatch()
		Sfx.Play("CardPick", { Volume = 0.6, Pitch = 1.2 })
		Theme.pop(entries.BotMatch.Button, 0.06)
		Remotes.Get("AdminCommand"):FireServer("bot")
	end
	playButton.Activated:Connect(toggleQueue)
	playgroundButton.Activated:Connect(togglePlayground)
	entries.BotMatch.Button.Activated:Connect(botMatch)

	-- Lab / Duel / Settings buttons run the same code as their keys
	entries.PowerUpLab.Button.Activated:Connect(function()
		Theme.pop(entries.PowerUpLab.Button, 0.06)
		Keybinds.Press("PowerUpLab", true)
		Keybinds.Press("PowerUpLab", false)
	end)
	entries.BattlePass.Button.Activated:Connect(function()
		Theme.pop(entries.BattlePass.Button, 0.06)
		if Controllers and Controllers.BattlePass then
			Controllers.BattlePass.Toggle()
		end
	end)
	entries.Shop.Button.Activated:Connect(function()
		Theme.pop(entries.Shop.Button, 0.06)
		if Controllers and Controllers.Shop then
			Controllers.Shop.Toggle()
		end
	end)
	entries.Locker.Button.Activated:Connect(function()
		Theme.pop(entries.Locker.Button, 0.06)
		if Controllers and Controllers.Locker then
			Controllers.Locker.Toggle()
		end
	end)
	entries.DuelFriend.Button.Activated:Connect(function()
		Theme.pop(entries.DuelFriend.Button, 0.06)
		if Controllers and Controllers.Duel then
			Controllers.Duel.Open()
		end
	end)
	entries.Settings.Button.Activated:Connect(function()
		Theme.pop(entries.Settings.Button, 0.06)
		if Controllers and Controllers.Settings then
			Controllers.Settings.Toggle()
		end
	end)

	local function onActionInput(input, processed)
		if processed and UserInputService:GetFocusedTextBox() then
			return
		end
		if Controllers and Controllers.Settings and Controllers.Settings.IsOpen() then
			return -- rebinding keys / moving sliders in Settings
		end
		if not gui.Enabled then
			return
		end
		if Keybinds.Matches("FindMatch", input) then
			toggleQueue()
		elseif Keybinds.Matches("Playground", input) then
			togglePlayground()
		elseif Keybinds.Matches("BotMatch", input) then
			botMatch()
		elseif Keybinds.Matches("Rematch", input) and rematchButton.Visible then
			requestRematch()
		end
	end
	UserInputService.InputBegan:Connect(onActionInput)
	Keybinds.VirtualBegan:Connect(onActionInput)

	-- idle animations: spinner, progress bar and timer while searching, a
	-- soft pulse on the find button otherwise
	RunService.RenderStepped:Connect(function()
		if not gui.Enabled then
			return
		end
		local t = os.clock()
		if queued then
			spinner.Rotation = (t * 360) % 360
			local p = (t * 0.7) % 1
			progressFill.Position = UDim2.fromScale(p * 1.35 - 0.35, 0)
			if math.floor(t - searchStart) ~= lastSecs then
				updateSearchText()
			end
		else
			local pulse = (math.sin(t * 3) + 1) / 2
			playButton.BackgroundColor3 = Palette.UIAccent:Lerp(Color3.new(1, 1, 1), pulse * 0.1)
		end
	end)

	-- KEYS (crates): LocalPlayer attribute "Keys"
	refreshKeys()
	player:GetAttributeChangedSignal("Keys"):Connect(refreshKeys)
	-- CREDITS (bought in the SHOP): LocalPlayer attribute "Credits"
	local function refreshCredits()
		creditsLabel.Text = tostring(math.floor(tonumber(player:GetAttribute("Credits")) or 0))
	end
	refreshCredits()
	player:GetAttributeChangedSignal("Credits"):Connect(refreshCredits)
	-- RANK: LocalPlayer attribute "Rating"
	refreshRank()
	player:GetAttributeChangedSignal("Rating"):Connect(refreshRank)

	local function refreshIfShown()
		if shown then
			LobbyUI.OnState(lastSnapshot)
		end
	end
	Players.PlayerAdded:Connect(refreshIfShown)
	Players.PlayerRemoving:Connect(function()
		task.defer(refreshIfShown)
	end)

	-- button labels follow your keybinds, the device you're using and the
	-- screen size
	ClientState.SettingsChanged:Connect(function()
		LobbyUI.OnState(lastSnapshot)
	end)
	UserInputService.LastInputTypeChanged:Connect(refreshIfShown)
	local function watchCamera()
		local camera = workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshIfShown)
		end
	end
	watchCamera()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		watchCamera()
		refreshIfShown()
	end)
	pcall(function()
		GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(refreshIfShown)
	end)

	LobbyUI.OnState({ InMatch = false, Phase = "Lobby" })
end

return LobbyUI
