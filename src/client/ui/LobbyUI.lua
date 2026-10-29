--[[
	LobbyUI.lua  (Client.ui.LobbyUI)

	The lobby / playground overlay (hidden while you're in a match, where the
	HUD takes over). Everything hugs the screen edges so the middle stays
	clear while you walk around the lobby in first person.

	Desktop / controller (design pixels, scaled as one piece per group):

	 +---------------------------------------------------------------------------+
	 | (o) SNIPER DUEL   .--------------------------------.   [K 3 KEYS] [C 250  |
	 |     1V1 ARENA     | shirt  bag   swords flask gear |    CREDITS] [<> GOLD |
	 |                   | LOCKER SHOP  DUEL   LAB  SETT. |    1180]  Name  (av) |
	 |  [PLAYGROUND]     |  [L]   [M]   [U]    [B]  [P]   |           * 3 ONLINE |
	 |   free roam...    '--------------------------------'                      |
	 |                                                                           |
	 |                                   +                                       |
	 |                               (crosshair)                                 |
	 |                                                                           |
	 |  [flag PLAYGROUND      G] [bot BOT  N]                                    |
	 |  [ REMATCH NAME               T ]   (gold, only after a match)            |
	 |  [ (o) FIND MATCH           [F] ]   hero: searching = spinner, timer,     |
	 |  [     1V1 - FIRST TO 5         ]         queue count, progress bar       |
	 +---------------------------------------------------------------------------+

	Touch (compact): the bottom is left free for the thumbstick and the
	fire / jump buttons. MobileControls draws the MENU button (Locker, Shop,
	Duel, Lab, Settings) under the wordmark.

	 +---------------------------------------------------------------+
	 | (o) SNIPER DUEL                       [K 3] [C 250] [<> 1180] |
	 | [= MENU]     [REMATCH] [FIND MATCH] [PLAYGROUND] [BOT]        |
	 |                   3 ONLINE - 2 IN QUEUE                       |
	 |                            +                                  |
	 |  (thumbstick)                                 (fire / jump)   |
	 +---------------------------------------------------------------+

	The mouse is locked in first person, so every action shows its key /
	controller button in a quiet keycap (rebindable in Settings > Keyboard /
	Controller). Unbound actions ("-") just hide their keycap.

	Everything is laid out in design pixels on one spacing scale (SP) and
	multiplied by a UIScale per corner group, so it fits a 800x400 phone and
	a 1920x1080 monitor alike.
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
local SP = { XS = 4, S = 8, M = 12, L = 16, XL = 24, XXL = 32 }

-- sizes (design pixels)
local TOP_H = 68 -- top bar row (brand, nav, profile)
local BRAND_W = 260 -- wordmark block; the nav starts after it
local TAB_W, TAB_H = 76, 60 -- nav tiles
local NAV_PAD = 4
local NAV_COUNT = 6
local NAV_W = TAB_W * NAV_COUNT + NAV_PAD * (NAV_COUNT - 1) + NAV_PAD * 2
local PILL_H = 32
local PROFILE_W = 160
local PLAY_W = 340 -- bottom-left play cluster
local MODE_H = 40
local BOT_W = 112
local REMATCH_H = 44
local HERO_H = 76
local HERO_ICON = 28
local TIME_W = 64 -- searching timer on the hero (desktop)
local COMPACT_H = 44 -- touch: one row of buttons
local COMPACT_WIDTHS = { Rematch = 132, FindMatch = 210, Playground = 132, BotMatch = 76, MapVote = 118 }

-- nav tiles (desktop). Ids are Keybinds action ids.
local NAV = {
	{ Id = "Locker", Text = "LOCKER", Icon = "shirt" },
	{ Id = "Shop", Text = "SHOP", Icon = "bag" },
	{ Id = "DuelFriend", Text = "DUEL", Icon = "swords" },
	{ Id = "PowerUpLab", Text = "LAB", Icon = "flask" },
	{ Id = "Profile", Text = "PROFILE", Icon = "target" },
	{ Id = "Settings", Text = "SETTINGS", Icon = "gear" },
}

local gui, root
local scrimCorner, scrimTop
local brand, brandMark, title, tagline, modeRow, modeChip, subtitle
local navBar
local tabs = {} -- [actionId] = tab
local profile, profileBlock, profileSpacer, onlineLabel
local keysPill, keysLabel, creditsLabel, rankPill, rankLabel, rankTier, rankIcon
local captions = {} -- pill captions (hidden on touch)
local stack, statusLabel
local primary, playButton, playgroundButton, rematchButton, heroStroke
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

local function sizeKeyHint(cap, label, key, textSize)
	cap.Size = UDim2.fromOffset(Theme.keycapWidth(key, textSize), math.floor(textSize * 1.85))
	label.Text = key
end

----------------------------------------------------------------------------
-- Buttons
----------------------------------------------------------------------------

--[[
	A flat button: optional icon on the left, a label (+ optional sub line)
	and a quiet keycap on the right. No outline; hover lifts the fill and
	scales it a touch.
]]
local function makeEntry(id, parent, opts)
	opts = opts or {}
	local button = Theme.new("TextButton", {
		Name = id,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Palette.UIPanel,
		BackgroundTransparency = 0.25,
		Parent = parent,
	})
	Theme.corner(button, opts.Radius or 10)
	local pad = opts.Pad or SP.M
	local icon
	if opts.Icon then
		icon = Theme.icon(opts.Icon, opts.IconSize or 16, Palette.UIText)
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, pad, 0.5, 0)
		icon.Parent = button
	end
	local keySize = opts.KeySize or 10
	local cap, capLabel = Theme.keyHint("-", keySize, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -pad, 0.5, 0),
		Parent = button,
	})
	local textSize = opts.TextSize or 14
	local label = Theme.label({
		Name = "Label",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, pad, 0.5, opts.LabelY or 0),
		Size = UDim2.new(1, -pad * 2, 0, textSize + 4),
		TextSize = textSize,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		FontFace = Theme.Font(opts.Weight or Enum.FontWeight.Bold),
		Parent = button,
	})

	local scale = Theme.scaleOf(button)
	local entry = {
		Id = id,
		Button = button,
		Icon = icon,
		IconSize = opts.IconSize or 16,
		Pad = pad,
		Cap = cap,
		CapLabel = capLabel,
		KeySize = keySize,
		Label = label,
		LabelY = opts.LabelY or 0,
		BgRest = 0.25,
		ExtraRight = 0,
		TextX = pad,
		RightX = pad,
		Hover = false,
	}
	local function hoverFill()
		return entry.Hover and math.max(0, entry.BgRest - 0.15) or entry.BgRest
	end
	entry.HoverFill = hoverFill
	button.MouseEnter:Connect(function()
		entry.Hover = true
		Theme.tween(scale, 0.15, { Scale = 1.02 })
		Theme.tween(button, 0.15, { BackgroundTransparency = hoverFill() })
	end)
	button.MouseLeave:Connect(function()
		entry.Hover = false
		Theme.tween(scale, 0.15, { Scale = 1 })
		Theme.tween(button, 0.15, { BackgroundTransparency = hoverFill() })
	end)
	button.MouseButton1Down:Connect(function()
		Theme.tween(scale, 0.08, { Scale = 0.97 })
	end)
	button.MouseButton1Up:Connect(function()
		Theme.tween(scale, 0.25, { Scale = entry.Hover and 1.02 or 1 }, Enum.EasingStyle.Back)
	end)
	entries[id] = entry
	return entry
end

-- Sets the label + keycap of a button and fits the label between the icon
-- slot (if shown) and the keycap (if shown).
local function setEntry(entry, key, text, showKey, showIcon)
	entry.Label.Text = text
	local x = entry.Pad
	if entry.Icon then
		entry.Icon.Visible = showIcon == true
		if showIcon then
			x += entry.IconSize + SP.S + 2
		end
	end
	local right = entry.Pad
	local capOn = showKey and key ~= "-"
	entry.Cap.Visible = capOn
	if capOn then
		sizeKeyHint(entry.Cap, entry.CapLabel, key, entry.KeySize)
		right += entry.Cap.Size.X.Offset + SP.S
	end
	entry.TextX = x
	entry.RightX = right
	entry.Label.Position = UDim2.new(0, x, 0.5, entry.LabelY)
	entry.Label.Size = UDim2.new(1, -(x + right + entry.ExtraRight), 0, entry.Label.TextSize + 4)
end

--[[
	Colours of a button:
	  "primary"   accent fill (FIND MATCH)
	  "gold"      AccentB fill (REMATCH)
	  "searching" dark fill + thin accent outline (FIND MATCH while queued)
	  "active"    accent tint (BACK TO LOBBY in the playground)
	  "normal"    dark translucent panel
]]
local function styleEntry(entry, style)
	local b = entry.Button
	local fg, bgRest
	if style == "primary" or style == "gold" then
		local color = style == "gold" and Palette.AccentB or Palette.UIAccent
		b.BackgroundColor3 = color
		bgRest = 0
		fg = Palette.UIBackground
		entry.Cap.BackgroundColor3 = Palette.UIBackground
		entry.Cap.BackgroundTransparency = 0.2
		entry.CapLabel.TextColor3 = color
	elseif style == "searching" then
		b.BackgroundColor3 = Palette.UIPanel
		bgRest = 0.1
		fg = Palette.UIText
		entry.Cap.BackgroundColor3 = Palette.UIPanelLight
		entry.Cap.BackgroundTransparency = 0.3
		entry.CapLabel.TextColor3 = Palette.UISubText
	elseif style == "active" then
		b.BackgroundColor3 = Palette.UIAccent
		bgRest = 0.78
		fg = Palette.UIAccent
		entry.Cap.BackgroundColor3 = Palette.UIPanelLight
		entry.Cap.BackgroundTransparency = 0.3
		entry.CapLabel.TextColor3 = Palette.UIText
	else
		b.BackgroundColor3 = Palette.UIPanel
		bgRest = 0.25
		fg = Palette.UIText
		entry.Cap.BackgroundColor3 = Palette.UIPanelLight
		entry.Cap.BackgroundTransparency = 0.3
		entry.CapLabel.TextColor3 = Palette.UISubText
	end
	entry.BgRest = bgRest
	entry.Label.TextColor3 = fg
	if entry.Icon then
		Theme.tintIcon(entry.Icon, fg)
	end
	b.BackgroundTransparency = entry.HoverFill()
end

-- A nav tile: icon, label and a quiet keycap stacked in a 76x60 tile.
local function makeTab(item, order)
	local tab = Theme.new("TextButton", {
		Name = item.Id,
		Size = UDim2.fromOffset(TAB_W, TAB_H),
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Palette.UIPanelLight,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = navBar,
	})
	Theme.corner(tab, 10)
	local icon = Theme.icon(item.Icon, 18, Palette.UIText, Palette.UIPanel)
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, 6)
	icon.Parent = tab
	local label = Theme.label({
		Name = "Label",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 27),
		Size = UDim2.new(1, -4, 0, 13),
		Text = item.Text,
		TextSize = 11,
		FontFace = Theme.Font(Enum.FontWeight.Bold),
		Parent = tab,
	})
	local cap, capLabel = Theme.keyHint("-", 9, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 42),
		Parent = tab,
	})
	local scale = Theme.scaleOf(tab)
	local t = { Id = item.Id, Button = tab, Icon = icon, Label = label, Cap = cap, CapLabel = capLabel, Hover = false }
	tab.MouseEnter:Connect(function()
		t.Hover = true
		Theme.tween(tab, 0.15, { BackgroundTransparency = 0.45 })
		label.TextColor3 = Palette.UIAccent
		Theme.tintIcon(icon, Palette.UIAccent)
	end)
	tab.MouseLeave:Connect(function()
		t.Hover = false
		Theme.tween(tab, 0.15, { BackgroundTransparency = 1 })
		label.TextColor3 = Palette.UIText
		Theme.tintIcon(icon, Palette.UIText)
	end)
	tab.MouseButton1Down:Connect(function()
		Theme.tween(scale, 0.08, { Scale = 0.94 })
	end)
	tab.MouseButton1Up:Connect(function()
		Theme.tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	tabs[item.Id] = t
	return t
end

----------------------------------------------------------------------------
-- Layout
----------------------------------------------------------------------------

local function layoutStack()
	local rematchOn = lastSnapshot.Rematch ~= nil
	rematchButton.Visible = rematchOn

	local function place(entry, x, y, w, h)
		entry.Button.Visible = true
		entry.Button.Size = UDim2.fromOffset(w, h)
		entry.Button.Position = UDim2.fromOffset(x + w / 2, y + h / 2)
	end

	if compact then
		-- one row at the top centre (under the wordmark / pills row)
		local order = {}
		if rematchOn then
			table.insert(order, "Rematch")
		end
		table.insert(order, "FindMatch")
		table.insert(order, "MapVote")
		table.insert(order, "Playground")
		if SHOW_BOT then
			table.insert(order, "BotMatch")
		else
			entries.BotMatch.Button.Visible = false
		end
		local x = 0
		for _, id in ipairs(order) do
			local w = COMPACT_WIDTHS[id]
			place(entries[id], x, 0, w, COMPACT_H)
			x += w + SP.S
		end
		x -= SP.S
		statusLabel.Visible = true
		statusLabel.Position = UDim2.fromOffset(0, COMPACT_H + SP.S)
		statusLabel.Size = UDim2.fromOffset(x, 16)
		stack.Size = UDim2.fromOffset(x, COMPACT_H + SP.S + 16)
	else
		-- bottom-left cluster: modes, (rematch), hero
		local y = 0
		if SHOW_BOT then
			place(entries.Playground, 0, y, PLAY_W - BOT_W - SP.S, MODE_H)
			place(entries.BotMatch, PLAY_W - BOT_W, y, BOT_W, MODE_H)
		else
			place(entries.Playground, 0, y, PLAY_W, MODE_H)
			entries.BotMatch.Button.Visible = false
		end
		y += MODE_H + SP.S
		place(entries.MapVote, 0, y, PLAY_W, MODE_H)
		y += MODE_H + SP.M
		if rematchOn then
			place(entries.Rematch, 0, y, PLAY_W, REMATCH_H)
			y += REMATCH_H + SP.S
		end
		place(primary, 0, y, PLAY_W, HERO_H)
		y += HERO_H
		statusLabel.Visible = false
		stack.Size = UDim2.fromOffset(PLAY_W, y)
	end
end

local function layoutTop()
	if compact then
		brandMark.Size = UDim2.fromOffset(30, 30)
		brandMark.Position = UDim2.fromOffset(0, 0)
		title.Position = UDim2.fromOffset(30 + SP.S, 0)
		title.Size = UDim2.fromOffset(170, 30)
		title.TextSize = 18
		tagline.Visible = false
		navBar.Visible = false
		modeRow.Visible = false
		brand.Size = UDim2.fromOffset(30 + SP.S + 170, 30)

		profileBlock.Visible = false
		profileSpacer.Visible = false
		for _, c in ipairs(captions) do
			c.Visible = false
		end
		profile.Size = UDim2.fromOffset(600, PILL_H)
	else
		local markY = (TOP_H - 44) / 2
		brandMark.Size = UDim2.fromOffset(44, 44)
		brandMark.Position = UDim2.fromOffset(0, markY)
		title.Position = UDim2.fromOffset(44 + SP.M, markY + 1)
		title.Size = UDim2.fromOffset(BRAND_W - 44 - SP.M, 26)
		title.TextSize = 24
		tagline.Visible = true
		tagline.Position = UDim2.fromOffset(44 + SP.M, markY + 28)
		navBar.Visible = true
		navBar.Position = UDim2.fromOffset(BRAND_W + SP.L, 0)
		modeRow.Visible = lastSnapshot.Playground == true
		modeRow.Position = UDim2.fromOffset(0, TOP_H + SP.M)
		brand.Size = UDim2.fromOffset(BRAND_W + SP.L + NAV_W, TOP_H + SP.M + 26)

		profileBlock.Visible = true
		profileSpacer.Visible = true
		for _, c in ipairs(captions) do
			c.Visible = true
		end
		profile.Size = UDim2.fromOffset(700, TOP_H)
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
	profile.Position = UDim2.new(1, -margin, 0, top)
	if compact then
		-- second row, centred under the wordmark / pills row
		stack.AnchorPoint = Vector2.new(0.5, 0)
		stack.Position = UDim2.new(0.5, 0, 0, top + math.floor((30 + SP.S) * scale))
	else
		stack.AnchorPoint = Vector2.new(0, 1)
		stack.Position = UDim2.new(0, margin, 1, -margin)
	end

	-- soft scrims so text stays readable over the 3D lobby (centre stays clear)
	scrimCorner.Visible = not compact
	scrimTop.Size = UDim2.new(1, 120, compact and 0.3 or 0.2, 60)

	-- text sizes per layout
	primary.Label.TextSize = compact and 17 or 24
	primary.LabelY = compact and -7 or -9
	subLabel.TextSize = compact and 10 or 12
	entries.Rematch.Label.TextSize = compact and 13 or 15
	entries.Playground.Label.TextSize = compact and 13 or 14
	entries.BotMatch.Label.TextSize = compact and 13 or 14
	entries.MapVote.Label.TextSize = compact and 13 or 14

	layoutTop()
	layoutStack()
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
		subLabel.Text = time .. "  ·  TAP TO CANCEL"
	else
		local window = lastSnapshot.SearchWindow
		local range = window == -1 and "ANY RATING" or (window and string.format("±%d RATING", window) or nil)
		subLabel.Text = range and string.format("%s  ·  %d IN QUEUE  ·  PRESS TO CANCEL", range, lastSnapshot.QueueCount or 1)
			or string.format("%d IN QUEUE  ·  PRESS TO CANCEL", lastSnapshot.QueueCount or 1)
	end
end

local function refreshPrimary(snapshot)
	local showKey = not compact
	local count = snapshot.QueueCount or 0
	primary.ExtraRight = (queued and not compact) and TIME_W or 0
	if queued then
		setEntry(primary, keyText("FindMatch"), "SEARCHING", showKey, true)
		styleEntry(primary, "searching")
		heroStroke.Transparency = 0.35
		subLabel.TextColor3 = Palette.UISubText
		subLabel.TextTransparency = 0
		updateSearchText()
	else
		setEntry(primary, keyText("FindMatch"), "FIND MATCH", showKey, true)
		styleEntry(primary, "primary")
		heroStroke.Transparency = 1
		subLabel.TextColor3 = Palette.UIBackground
		subLabel.TextTransparency = 0.3
		if count > 0 then
			subLabel.Text = string.format("%d PLAYER%s WAITING", count, count == 1 and "" or "S")
		else
			subLabel.Text = string.format("1V1  ·  FIRST TO %d", Config.Match.RoundsToWin or 5)
		end
	end
	-- the spinner takes the icon's slot while searching
	primary.Icon.Visible = not queued
	spinner.Visible = queued
	subLabel.Position = UDim2.new(0, primary.TextX, 0.5, compact and 9 or 13)
	-- the timer shares the title line, so the sub line keeps the full width
	subLabel.Size = UDim2.new(1, -(primary.TextX + primary.RightX), 0, 14)
	timeLabel.Position = UDim2.new(1, -primary.RightX, 0.5, primary.LabelY)
	timeLabel.Visible = queued and not compact
	progressTrack.Visible = queued
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

local function refreshModes(snapshot)
	local showKey = not compact
	local showIcon = not compact
	local inPlayground = snapshot.Playground == true
	local pgKey = keyText("Playground")
	local pgText = "PLAYGROUND"
	if inPlayground then
		pgText = (compact or #pgKey > 3) and "TO LOBBY" or "BACK TO LOBBY"
	end
	setEntry(entries.Playground, pgKey, pgText, showKey, showIcon)
	styleEntry(entries.Playground, inPlayground and "active" or "normal")
	setEntry(entries.BotMatch, keyText("BotMatch"), "BOT", showKey, showIcon)
	styleEntry(entries.BotMatch, "normal")
	local map = snapshot.MapVote and string.upper(snapshot.MapVote) or "ANY"
	setEntry(entries.MapVote, keyText("MapVote"), compact and map or ("MAP VOTE: " .. map), showKey, showIcon)
	styleEntry(entries.MapVote, snapshot.MapVote and "active" or "normal")
end

local function refreshTabs()
	for _, item in ipairs(NAV) do
		local t = tabs[item.Id]
		local key = keyText(item.Id)
		t.Cap.Visible = key ~= "-"
		sizeKeyHint(t.Cap, t.CapLabel, key, 9)
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

-- RANK pill: your tier + rating (RankService's "Rating" attribute)
local function refreshRank()
	local rating = tonumber(player:GetAttribute("Rating"))
	rankPill.Visible = rating ~= nil
	if not rating then
		return
	end
	local tier = Config.RankTier(rating)
	rankTier.Text = tier.Name
	rankTier.TextColor3 = tier.Color
	Theme.tintIcon(rankIcon, tier.Color)
	rankLabel.Text = tostring(math.floor(rating))
end

local function refreshKeys()
	local keys = tonumber(player:GetAttribute("Keys")) or 0
	keysLabel.Text = tostring(math.floor(keys))
	if lastKeys and keys > lastKeys and shown then
		Theme.pop(keysPill, 0.2)
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
	refreshModes(snapshot)
	refreshTabs()
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
	Theme.corner(tile, UDim.new(0.26, 0))
	local ring = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = tile,
	})
	Theme.corner(ring, UDim.new(0.5, 0))
	Theme.stroke(ring, Palette.UIAccent, 2.5, 0)
	local ticks = {
		{ UDim2.fromScale(0.5, 0.15), UDim2.new(0, 2, 0.18, 0) },
		{ UDim2.fromScale(0.5, 0.85), UDim2.new(0, 2, 0.18, 0) },
		{ UDim2.fromScale(0.15, 0.5), UDim2.new(0.18, 0, 0, 2) },
		{ UDim2.fromScale(0.85, 0.5), UDim2.new(0.18, 0, 0, 2) },
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

-- Top left: wordmark, nav bar, playground chip.
local function buildBrand()
	brand = group("Brand", Vector2.new(0, 0))
	brandMark = buildMark(brand)
	title = Theme.label({
		Name = "Title",
		RichText = true,
		Text = string.format('SNIPER <font color="#%s">DUEL</font>', Palette.UIAccent:ToHex()),
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = brand,
	})
	tagline = Theme.label({
		Name = "Tagline",
		Size = UDim2.fromOffset(BRAND_W - 44 - SP.M, 14),
		Text = "1V1 SNIPER ARENA",
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Palette.UISubText,
		FontFace = Theme.Font(Enum.FontWeight.SemiBold),
		Parent = brand,
	})

	-- nav bar: one translucent pill holding the five tiles
	navBar = Theme.new("Frame", {
		Name = "Nav",
		Size = UDim2.fromOffset(NAV_W, TOP_H),
		BackgroundColor3 = Palette.UIPanel,
		BackgroundTransparency = 0.3,
		Parent = brand,
	})
	Theme.corner(navBar, 14)
	Theme.padding(navBar, NAV_PAD)
	Theme.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, NAV_PAD),
		Parent = navBar,
	})
	for i, item in ipairs(NAV) do
		makeTab(item, i)
	end

	-- "PLAYGROUND" chip + explanation under the wordmark
	modeRow = Theme.new("Frame", {
		Name = "Mode",
		Size = UDim2.fromOffset(420, 26),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = brand,
	})
	modeChip = Theme.new("Frame", {
		Size = UDim2.fromOffset(112, 26),
		BackgroundColor3 = Palette.AccentB,
		Parent = modeRow,
	})
	Theme.corner(modeChip, UDim.new(0.5, 0))
	Theme.label({
		Size = UDim2.fromScale(1, 1),
		Text = "PLAYGROUND",
		TextSize = 12,
		TextColor3 = Palette.UIBackground,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = modeChip,
	})
	subtitle = Theme.label({
		Position = UDim2.fromOffset(112 + SP.M, 0),
		Size = UDim2.new(1, -(112 + SP.M), 1, 0),
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Palette.UIText,
		FontFace = Theme.Font(Enum.FontWeight.Medium),
		Parent = modeRow,
	})
end

-- A currency / rank pill: icon, value (and a small caption on desktop).
local function buildPill(name, order)
	local pill = Theme.new("Frame", {
		Name = name,
		Size = UDim2.fromOffset(0, PILL_H),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Palette.UIPanel,
		BackgroundTransparency = 0.25,
		LayoutOrder = order,
		Parent = profile,
	})
	Theme.corner(pill, UDim.new(0.5, 0))
	Theme.new("UIPadding", {
		PaddingLeft = UDim.new(0, SP.M - 2),
		PaddingRight = UDim.new(0, SP.M),
		Parent = pill,
	})
	Theme.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, SP.XS + 2),
		Parent = pill,
	})
	Theme.new("UISizeConstraint", {
		MinSize = Vector2.new(72, PILL_H),
		Parent = pill,
	})
	return pill
end

local function pillText(parent, order, text, size, weight, color)
	return Theme.label({
		Size = UDim2.fromOffset(0, size + 3),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = text,
		TextSize = size,
		TextColor3 = color or Palette.UIText,
		FontFace = Theme.Font(weight),
		LayoutOrder = order,
		Parent = parent,
	})
end

local function pillIcon(parent, name, color)
	local icon = Theme.icon(name, 16, color, Palette.UIPanel)
	icon.LayoutOrder = 1
	icon.Parent = parent
	return icon
end

-- Top right: KEYS, CREDITS, RANK pills, then avatar + name + online count.
local function buildProfile()
	profile = group("Profile", Vector2.new(1, 0))
	Theme.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, SP.S),
		Parent = profile,
	})

	keysPill = buildPill("Keys", 1)
	pillIcon(keysPill, "key", Palette.AccentB)
	keysLabel = pillText(keysPill, 2, "0", 15, Enum.FontWeight.Heavy)
	table.insert(captions, pillText(keysPill, 3, "KEYS", 10, Enum.FontWeight.Bold, Palette.UISubText))

	local creditsPill = buildPill("Credits", 2)
	pillIcon(creditsPill, "coin", Color3.fromRGB(255, 196, 60))
	creditsLabel = pillText(creditsPill, 2, "0", 15, Enum.FontWeight.Heavy)
	table.insert(captions, pillText(creditsPill, 3, "CREDITS", 10, Enum.FontWeight.Bold, Palette.UISubText))

	rankPill = buildPill("Rank", 3)
	rankIcon = pillIcon(rankPill, "diamond", Palette.UIText)
	rankTier = pillText(rankPill, 2, "", 11, Enum.FontWeight.Heavy)
	rankLabel = pillText(rankPill, 3, "", 15, Enum.FontWeight.Heavy)
	rankPill.Visible = false

	-- a little extra room between the pills and the player
	profileSpacer = Theme.new("Frame", {
		Name = "Spacer",
		Size = UDim2.fromOffset(SP.XS, 1),
		BackgroundTransparency = 1,
		LayoutOrder = 9,
		Parent = profile,
	})

	profileBlock = Theme.new("Frame", {
		Name = "Player",
		Size = UDim2.fromOffset(PROFILE_W, 44),
		BackgroundTransparency = 1,
		LayoutOrder = 10,
		Parent = profile,
	})
	local avatar = Theme.new("ImageLabel", {
		Name = "Avatar",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = Palette.UIPanelLight,
		ScaleType = Enum.ScaleType.Crop,
		Image = "",
		Parent = profileBlock,
	})
	Theme.corner(avatar, UDim.new(0.5, 0))
	Theme.stroke(avatar, Palette.UIAccent, 2, 0.35)
	Theme.label({
		Name = "DisplayName",
		Position = UDim2.fromOffset(0, 3),
		Size = UDim2.new(1, -(40 + SP.M), 0, 20),
		Text = player.DisplayName,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd,
		FontFace = Theme.Font(Enum.FontWeight.Bold),
		Parent = profileBlock,
	})
	local onlineRow = Theme.new("Frame", {
		Name = "Online",
		Position = UDim2.fromOffset(0, 25),
		Size = UDim2.new(1, -(40 + SP.M), 0, 14),
		BackgroundTransparency = 1,
		Parent = profileBlock,
	})
	Theme.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, SP.XS + 1),
		Parent = onlineRow,
	})
	local dot = Theme.new("Frame", {
		Size = UDim2.fromOffset(6, 6),
		BackgroundColor3 = Palette.AccentA,
		LayoutOrder = 1,
		Parent = onlineRow,
	})
	Theme.corner(dot, UDim.new(0.5, 0))
	onlineLabel = Theme.label({
		Size = UDim2.fromOffset(0, 14),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = "1 ONLINE",
		TextSize = 11,
		TextColor3 = Palette.UISubText,
		FontFace = Theme.Font(Enum.FontWeight.SemiBold),
		LayoutOrder = 2,
		Parent = onlineRow,
	})
	task.spawn(function()
		local ok, image = pcall(function()
			return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		end)
		avatar.Image = (ok and image)
			or ("rbxthumb://type=AvatarHeadShot&id=" .. tostring(player.UserId) .. "&w=150&h=150")
	end)
end

-- Bottom left: mode row, rematch, FIND MATCH hero.
local function buildStack()
	stack = group("Actions", Vector2.new(0, 1))

	-- PLAYGROUND / BOT (admins)
	makeEntry("Playground", stack, { Icon = "flag", TextSize = 14 })
	makeEntry("BotMatch", stack, { Icon = "bot", TextSize = 14 })
	-- MAP VOTE: cycles ANY -> each map -> ANY
	makeEntry("MapVote", stack, { Icon = "flag", TextSize = 14 })
	playgroundButton = entries.Playground.Button

	-- REMATCH (after a match, for a little while)
	local rematch = makeEntry("Rematch", stack, { TextSize = 15, Weight = Enum.FontWeight.Heavy, Pad = SP.L })
	rematchButton = rematch.Button
	rematchButton.Visible = false

	-- FIND MATCH (hero)
	primary = makeEntry("FindMatch", stack, {
		Icon = "target",
		IconSize = HERO_ICON,
		TextSize = 24,
		KeySize = 13,
		Radius = 14,
		LabelY = -9,
		Pad = SP.L,
		Weight = Enum.FontWeight.Heavy,
	})
	playButton = primary.Button
	heroStroke = Theme.stroke(playButton, Palette.UIAccent, 1.5, 1)
	subLabel = Theme.label({
		Name = "Sub",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, SP.L, 0.5, 13),
		Size = UDim2.new(1, -SP.L * 2, 0, 14),
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		FontFace = Theme.Font(Enum.FontWeight.Bold),
		Parent = playButton,
	})
	-- spinner sits in the icon's slot while searching
	spinner = Theme.new("Frame", {
		Name = "Spinner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, SP.L + HERO_ICON / 2, 0.5, 0),
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
		Position = UDim2.new(1, -SP.L, 0.5, 0),
		Size = UDim2.fromOffset(TIME_W - SP.XS, 24),
		Text = "0:00",
		TextSize = 20,
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

	-- status line (compact layout: online / queue / playground)
	statusLabel = Theme.label({
		Name = "Status",
		Size = UDim2.fromOffset(300, 16),
		TextSize = 11,
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

	-- soft gradient scrims behind the corners (never over the centre)
	scrimCorner = Theme.new("Frame", {
		Name = "ScrimCorner",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, -60, 1, 60),
		Size = UDim2.new(0.5, 60, 0.55, 60),
		BackgroundColor3 = Palette.UIBackground,
		ZIndex = 0,
		Parent = root,
	})
	Theme.fade(scrimCorner, -35, { { 0, 0.3 }, { 0.5, 0.75 }, { 1, 1 } })
	scrimTop = Theme.new("Frame", {
		Name = "ScrimTop",
		Position = UDim2.fromOffset(-60, -60),
		Size = UDim2.new(1, 120, 0.2, 60),
		BackgroundColor3 = Palette.UIBackground,
		ZIndex = 0,
		Parent = root,
	})
	Theme.fade(scrimTop, 90, { { 0, 0.4 }, { 1, 1 } })

	buildBrand()
	buildProfile()
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
	local function botMatch()
		Sfx.Play("CardPick", { Volume = 0.6, Pitch = 1.2 })
		Theme.pop(entries.BotMatch.Button, 0.06)
		Remotes.Get("AdminCommand"):FireServer("bot")
	end
	local function cycleMap()
		local maps = lastSnapshot.Maps or {}
		if #maps == 0 then
			return
		end
		Sfx.Play("CardHover", { Pitch = 1.2 })
		Theme.pop(entries.MapVote.Button, 0.06)
		local index = lastSnapshot.MapVote and table.find(maps, lastSnapshot.MapVote) or 0
		Remotes.Get("MapVote"):FireServer(maps[index + 1]) -- (past the last map: nil = ANY)
	end
	entries.MapVote.Button.Activated:Connect(cycleMap)
	rematchButton.Activated:Connect(requestRematch)
	playButton.Activated:Connect(toggleQueue)
	playgroundButton.Activated:Connect(togglePlayground)
	entries.BotMatch.Button.Activated:Connect(botMatch)

	-- nav tiles run the same code as their keys
	local navActions = {
		Locker = function()
			if Controllers and Controllers.Locker then
				Controllers.Locker.Toggle()
			end
		end,
		Shop = function()
			if Controllers and Controllers.Shop then
				Controllers.Shop.Toggle()
			end
		end,
		DuelFriend = function()
			if Controllers and Controllers.Duel then
				Controllers.Duel.Open()
			end
		end,
		PowerUpLab = function()
			Keybinds.Press("PowerUpLab", true)
			Keybinds.Press("PowerUpLab", false)
		end,
		Settings = function()
			if Controllers and Controllers.Settings then
				Controllers.Settings.Toggle()
			end
		end,
		Profile = function()
			if Controllers and Controllers.Profile then
				Controllers.Profile.Toggle()
			end
		end,
	}
	for _, item in ipairs(NAV) do
		local t = tabs[item.Id]
		t.Button.Activated:Connect(function()
			Sfx.Play("CardPick", { Volume = 0.4, Pitch = 1.15 })
			Theme.pop(t.Button, 0.06)
			navActions[item.Id]()
		end)
	end

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
		elseif Keybinds.Matches("MapVote", input) and not ClientState.MenuOpen then
			cycleMap()
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
			playButton.BackgroundColor3 = Palette.UIAccent:Lerp(Color3.new(1, 1, 1), pulse * 0.08)
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
