--[[
	ProfileMenu.lua  (Client.ui.ProfileMenu)

	PROFILE (lobby, key J or the PROFILE tile / mobile MENU):
		STATS       lifetime numbers (ProfileService) + your rank
		CHALLENGES  today's dailies and this week's weeklies: progress bars,
		            key rewards, time until they reset
		SEASON      the season number, time left, your tier + season peak,
		            and the key reward for each tier at the end
		WATCH       every live duel on the server: WATCH puts your camera on
		            it (SpectateController)
	Bottom left: TUTORIAL (the guided first steps, paid once).
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local ClientState = require(script.Parent.Parent.ClientState)
local Sfx = require(script.Parent.Parent.Sfx)
local Keybinds = require(script.Parent.Parent.Keybinds)
local Theme = require(script.Parent.Theme)

local Palette = Config.Palette
local player = Players.LocalPlayer

local ProfileMenu = {}
local Controllers

local W, H = 900, 580
local GOLD = Color3.fromRGB(255, 200, 60)
local TABS = { "Stats", "Challenges", "Season", "Watch" }

local gui, panel, unlocker, pages, tabs, tutorialButton
local isOpen = false
local current = "Stats"
local profile = nil -- latest from the server
local challengeById = {}
for _, list in ipairs({ Config.Challenges.Daily, Config.Challenges.Weekly }) do
	for _, c in ipairs(list) do
		challengeById[c.Id] = c
	end
end

local function clear(frame)
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function commas(n)
	local s = tostring(math.floor(n or 0))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function duration(seconds)
	seconds = math.max(0, math.floor(seconds))
	local d, h, m = seconds // 86400, (seconds % 86400) // 3600, (seconds % 3600) // 60
	if d > 0 then
		return ("%dd %dh"):format(d, h)
	elseif h > 0 then
		return ("%dh %dm"):format(h, m)
	end
	return ("%dm"):format(math.max(m, 1))
end

local function card(parent, props)
	local frame = Theme.new("Frame", {
		BackgroundColor3 = Palette.UIPanelLight,
		BackgroundTransparency = 0.25,
		Parent = parent,
	})
	for k, v in pairs(props or {}) do
		frame[k] = v
	end
	Theme.corner(frame, 12)
	return frame
end

----------------------------------------------------------------------------
-- STATS
----------------------------------------------------------------------------
local function buildStats(page)
	clear(page)
	local s = profile and profile.Stats or {}
	local rating = tonumber(player:GetAttribute("Rating"))
	local tier = rating and Config.RankTier(rating)

	-- rank strip
	local strip = card(page, { Size = UDim2.new(1, 0, 0, 74) })
	Theme.label({
		Position = UDim2.fromOffset(18, 10),
		Size = UDim2.fromOffset(300, 30),
		Text = tier and tier.Name or "UNRANKED",
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = tier and tier.Color or Palette.UISubText,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = strip,
	})
	Theme.label({
		Position = UDim2.fromOffset(18, 42),
		Size = UDim2.fromOffset(420, 20),
		Text = rating and ("RATING %d   ·   PEAK %d   ·   RANKED %d-%d"):format(
			rating,
			tonumber(player:GetAttribute("SeasonPeak")) or rating,
			tonumber(player:GetAttribute("RankWins")) or 0,
			tonumber(player:GetAttribute("RankLosses")) or 0
		) or "Play a duel against a player to get a rating",
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Palette.UISubText,
		Parent = strip,
	})
	local matches = s.Matches or 0
	Theme.label({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -18, 0.5, 0),
		Size = UDim2.fromOffset(260, 40),
		Text = matches > 0 and ("%d%% WINS"):format(math.floor((s.Wins or 0) / matches * 100 + 0.5)) or "NO DUELS YET",
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Palette.UIAccent,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = strip,
	})

	-- stat tiles
	local grid = Theme.new("Frame", {
		Position = UDim2.fromOffset(0, 88),
		Size = UDim2.new(1, 0, 1, -88),
		BackgroundTransparency = 1,
		Parent = page,
	}, {
		Theme.new("UIGridLayout", {
			CellSize = UDim2.new(0.2, -10, 0, 96),
			CellPadding = UDim2.fromOffset(12, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local shots = s.Shots or 0
	local tiles = {
		{ "DUELS", commas(matches) },
		{ "WINS", commas(s.Wins) },
		{ "ROUNDS WON", commas(s.RoundsWon) },
		{ "KILLS", commas(s.Kills) },
		{ "HEADSHOTS", commas(s.Headshots) },
		{ "ACCURACY", shots > 0 and ("%d%%"):format(math.floor((s.Hits or 0) / shots * 100 + 0.5)) or "-" },
		{ "DAMAGE", commas(s.Damage) },
		{ "LONGEST HIT", (s.Longest or 0) > 0 and (commas(s.Longest) .. " studs") or "-" },
		{ "BEST STREAK", commas(s.BestStreak) },
		{ "KNIFE KILLS", commas(s.KnifeKills) },
		{ "FLAWLESS WINS", commas(s.Flawless) },
		{ "300+ STUD HITS", commas(s.LongHits) },
		{ "WIN STREAK", commas(s.Streak) },
		{ "SHOTS FIRED", commas(shots) },
		{ "LOSSES", commas(s.Losses) },
	}
	for i, tile in ipairs(tiles) do
		local f = card(grid, { LayoutOrder = i })
		Theme.label({
			Position = UDim2.fromOffset(0, 16),
			Size = UDim2.new(1, 0, 0, 34),
			Text = tile[2],
			TextSize = 26,
			FontFace = Theme.Font(Enum.FontWeight.Heavy),
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = f,
		})
		Theme.label({
			Position = UDim2.fromOffset(0, 58),
			Size = UDim2.new(1, 0, 0, 16),
			Text = tile[1],
			TextSize = 11,
			TextColor3 = Palette.UISubText,
			FontFace = Theme.Font(Enum.FontWeight.Heavy),
			Parent = f,
		})
	end
end

----------------------------------------------------------------------------
-- CHALLENGES
----------------------------------------------------------------------------
local function challengeRow(parent, entry, order)
	local def = challengeById[entry.Id]
	if not def then
		return
	end
	local row = card(parent, { Size = UDim2.new(1, 0, 0, 74), LayoutOrder = order })
	local done = entry.Done == true
	Theme.label({
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -120, 0, 22),
		Text = def.Text,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = done and Palette.UISubText or Palette.UIText,
		Parent = row,
	})
	local track = Theme.new("Frame", {
		Position = UDim2.fromOffset(16, 44),
		Size = UDim2.new(1, -170, 0, 10),
		BackgroundColor3 = Palette.UIBackground,
		BackgroundTransparency = 0.3,
		Parent = row,
	})
	Theme.corner(track, 5)
	local fill = Theme.new("Frame", {
		Size = UDim2.fromScale(math.clamp((entry.Progress or 0) / def.Goal, 0, 1), 1),
		BackgroundColor3 = done and Palette.UIAccent or GOLD,
		Parent = track,
	})
	Theme.corner(fill, 5)
	Theme.label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -116, 0, 38),
		Size = UDim2.fromOffset(110, 22),
		Text = done and "DONE" or ("%s / %s"):format(commas(entry.Progress or 0), commas(def.Goal)),
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = done and Palette.UIAccent or Palette.UIText,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = row,
	})
	local reward = Theme.new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(84, 44),
		BackgroundColor3 = done and Palette.UIPanel or GOLD,
		BackgroundTransparency = done and 0.3 or 0,
		Parent = row,
	})
	Theme.corner(reward, 10)
	local icon = Theme.icon("key", 16, done and Palette.UISubText or Palette.UIBackground)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 12, 0.5, 0)
	icon.Parent = reward
	Theme.label({
		Position = UDim2.fromOffset(32, 0),
		Size = UDim2.new(1, -36, 1, 0),
		Text = "+" .. def.Keys,
		TextSize = 20,
		TextColor3 = done and Palette.UISubText or Palette.UIBackground,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = reward,
	})
end

local function buildChallenges(page)
	clear(page)
	if not profile then
		Theme.label({ Size = UDim2.fromScale(1, 1), Text = "Loading...", TextColor3 = Palette.UISubText, Parent = page })
		return
	end
	local now = os.time()
	for i, info in ipairs({
		{ "DAILY", profile.Daily, profile.DailyResetsAt },
		{ "WEEKLY", profile.Weekly, profile.WeeklyResetsAt },
	}) do
		local column = Theme.new("Frame", {
			Position = UDim2.new((i - 1) * 0.5, i == 1 and 0 or 8, 0, 0),
			Size = UDim2.new(0.5, -8, 1, 0),
			BackgroundTransparency = 1,
			Parent = page,
		})
		Theme.label({
			Size = UDim2.new(1, 0, 0, 26),
			Text = info[1],
			TextSize = 22,
			TextXAlignment = Enum.TextXAlignment.Left,
			FontFace = Theme.Font(Enum.FontWeight.Heavy),
			Parent = column,
		})
		Theme.label({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromOffset(200, 26),
			Text = info[3] and ("NEW IN " .. duration(info[3] - now)) or "",
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = Palette.UISubText,
			FontFace = Theme.Font(Enum.FontWeight.Heavy),
			Parent = column,
		})
		local list = Theme.new("Frame", {
			Position = UDim2.fromOffset(0, 36),
			Size = UDim2.new(1, 0, 1, -36),
			BackgroundTransparency = 1,
			Parent = column,
		}, {
			Theme.new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		for order, entry in ipairs(info[2] and info[2].List or {}) do
			challengeRow(list, entry, order)
		end
	end
end

----------------------------------------------------------------------------
-- SEASON
----------------------------------------------------------------------------
local function buildSeason(page)
	clear(page)
	local season, _, ends = Config.SeasonAt(os.time())
	local rating = tonumber(player:GetAttribute("Rating"))
	local peak = tonumber(player:GetAttribute("SeasonPeak")) or rating
	local peakTier = peak and Config.RankTier(peak)
	local head = card(page, { Size = UDim2.new(1, 0, 0, 110) })
	Theme.label({
		Position = UDim2.fromOffset(20, 14),
		Size = UDim2.fromOffset(400, 44),
		Text = "SEASON " .. season,
		TextSize = 40,
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = head,
	})
	Theme.label({
		Position = UDim2.fromOffset(20, 62),
		Size = UDim2.fromOffset(520, 20),
		Text = ("ENDS IN %s  ·  YOUR REWARD IS SET BY THE BEST TIER YOU REACH"):format(duration(ends - os.time())),
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Palette.UISubText,
		Parent = head,
	})
	Theme.label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 18),
		Size = UDim2.fromOffset(300, 34),
		Text = peakTier and ("SEASON BEST: " .. peakTier.Name) or "UNRANKED",
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = peakTier and peakTier.Color or Palette.UISubText,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = head,
	})
	Theme.label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 56),
		Size = UDim2.fromOffset(300, 20),
		Text = rating and ("NOW %d  ·  PEAK %d"):format(rating, peak or rating) or "",
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Palette.UISubText,
		Parent = head,
	})

	local row = Theme.new("Frame", {
		Position = UDim2.fromOffset(0, 126),
		Size = UDim2.new(1, 0, 0, 180),
		BackgroundTransparency = 1,
		Parent = page,
	}, {
		Theme.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local tiers = Config.Rank.Tiers
	for i, tier in ipairs(tiers) do
		local reached = peak ~= nil and peak >= tier.Min
		local f = card(row, { Size = UDim2.new(1 / #tiers, -9, 1, 0), LayoutOrder = i })
		if peakTier == tier then
			Theme.stroke(f, tier.Color, 2, 0)
		end
		local badge = Theme.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 18),
			Size = UDim2.fromOffset(46, 46),
			Rotation = 45,
			BackgroundColor3 = tier.Color,
			BackgroundTransparency = reached and 0 or 0.7,
			Parent = f,
		})
		Theme.corner(badge, 8)
		Theme.label({
			Position = UDim2.fromOffset(0, 80),
			Size = UDim2.new(1, 0, 0, 20),
			Text = tier.Name,
			TextSize = 14,
			TextColor3 = reached and tier.Color or Palette.UISubText,
			FontFace = Theme.Font(Enum.FontWeight.Heavy),
			Parent = f,
		})
		Theme.label({
			Position = UDim2.fromOffset(0, 102),
			Size = UDim2.new(1, 0, 0, 16),
			Text = tier.Min .. "+",
			TextSize = 12,
			TextColor3 = Palette.UISubText,
			Parent = f,
		})
		Theme.label({
			Position = UDim2.fromOffset(0, 134),
			Size = UDim2.new(1, 0, 0, 26),
			Text = "+" .. (Config.Rank.Season.Rewards[tier.Name] or 0) .. " KEYS",
			TextSize = 17,
			TextColor3 = reached and GOLD or Palette.UISubText,
			FontFace = Theme.Font(Enum.FontWeight.Heavy),
			Parent = f,
		})
	end
	Theme.label({
		Position = UDim2.fromOffset(0, 322),
		Size = UDim2.new(1, 0, 0, 40),
		Text = ("When the season ends your rating moves %d%% of the way back to %d, and the next season starts."):format(
			math.floor((1 - Config.Rank.Season.ResetFactor) * 100 + 0.5),
			Config.Rank.StartRating
		),
		TextSize = 14,
		TextWrapped = true,
		TextColor3 = Palette.UISubText,
		Parent = page,
	})
end

----------------------------------------------------------------------------
-- WATCH
----------------------------------------------------------------------------
local function buildWatch(page)
	clear(page)
	local snapshot = ClientState.Snapshot
	local live = (not snapshot.InMatch and snapshot.LiveMatches) or {}
	if #live == 0 then
		Theme.label({
			Size = UDim2.fromScale(1, 1),
			Text = "No duels being played right now. Check back in a moment!",
			TextSize = 18,
			TextColor3 = Palette.UISubText,
			Parent = page,
		})
		return
	end
	local list = Theme.new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = page,
	}, {
		Theme.new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for i, m in ipairs(live) do
		local row = card(list, { Size = UDim2.new(1, -10, 0, 70), LayoutOrder = i })
		local a, b = m.Players[1] or {}, m.Players[2] or {}
		Theme.label({
			Position = UDim2.fromOffset(18, 10),
			Size = UDim2.new(1, -200, 0, 28),
			RichText = true,
			Text = ('<font color="#%s">%s</font>  %d - %d  <font color="#%s">%s</font>'):format(
				Palette.PlayerA:ToHex(), tostring(a.Name or "?"), a.Wins or 0, b.Wins or 0, Palette.PlayerB:ToHex(), tostring(b.Name or "?")
			),
			TextSize = 20,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			FontFace = Theme.Font(Enum.FontWeight.Heavy),
			Parent = row,
		})
		Theme.label({
			Position = UDim2.fromOffset(18, 40),
			Size = UDim2.new(1, -200, 0, 18),
			Text = ("%s  ·  ROUND %d  ·  %d WATCHING"):format(string.upper(m.Map or "?"), m.Round or 1, m.Watchers or 0),
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Palette.UISubText,
			Parent = row,
		})
		local watching = snapshot.Spectating == m.Id
		local button = Theme.button({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(150, 44),
			Text = watching and "STOP" or "WATCH",
			TextSize = 18,
			BackgroundColor3 = watching and Palette.UIPanelLight or Palette.UIAccent,
			TextColor3 = watching and Palette.UIText or Palette.UIBackground,
			Parent = row,
		})
		button.Activated:Connect(function()
			Sfx.Play("CardPick", { Pitch = 1.1 })
			Remotes.Get("Spectate"):FireServer(not watching and m.Id or nil)
			if not watching then
				ProfileMenu.Close()
			end
		end)
	end
end

----------------------------------------------------------------------------
-- Open / close
----------------------------------------------------------------------------
local builders = { Stats = buildStats, Challenges = buildChallenges, Season = buildSeason, Watch = buildWatch }

function ProfileMenu.Show(name)
	current = name
	for pageName, page in pairs(pages) do
		page.Visible = pageName == name
	end
	for tabName, button in pairs(tabs) do
		local on = tabName == name
		button.BackgroundColor3 = on and Palette.UIAccent or Palette.UIPanelLight
		button.TextColor3 = on and Palette.UIBackground or Palette.UIText
	end
	builders[name](pages[name])
end

function ProfileMenu.Open(page)
	if ClientState.InMatch() or (ClientState.MenuOpen and not isOpen) then
		return
	end
	if not isOpen then
		isOpen = true
		gui.Enabled = true
		unlocker.Visible = true
		ClientState.SetMenu("Profile", true)
		panel.Size = UDim2.fromOffset(W - 40, H - 40)
		Theme.tween(panel, 0.2, { Size = UDim2.fromOffset(W, H) }, Enum.EasingStyle.Back)
		Sfx.Play("CardPick", { Pitch = 1.05, Volume = 0.6 })
		Remotes.Get("ProfileAction"):FireServer("Get")
	end
	ProfileMenu.Show(page or current)
end

function ProfileMenu.Close()
	if not isOpen then
		return
	end
	isOpen = false
	gui.Enabled = false
	unlocker.Visible = false
	ClientState.SetMenu("Profile", false)
end

function ProfileMenu.Toggle()
	if isOpen then
		ProfileMenu.Close()
	else
		ProfileMenu.Open()
	end
end

function ProfileMenu.IsOpen()
	return isOpen
end

-- The latest profile from the server (Tutorial uses it).
function ProfileMenu.GetProfile()
	return profile
end

function ProfileMenu.Init(controllers)
	Controllers = controllers
end

function ProfileMenu.Start(playerGui)
	gui = Theme.screen("Profile", 9, playerGui)
	gui.Enabled = false
	Theme.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Palette.UIBackground,
		BackgroundTransparency = 0.35,
		Parent = gui,
	})
	unlocker = Theme.mouseUnlocker(gui)
	panel = Theme.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(W, H),
		BackgroundTransparency = 0,
		Parent = gui,
	})
	Theme.padding(panel, 20)
	local scale = Theme.new("UIScale", { Parent = panel })
	local function fit()
		local view = workspace.CurrentCamera.ViewportSize
		scale.Scale = math.min(1, (view.X - 40) / W, (view.Y - 40) / H)
	end
	fit()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)

	Theme.label({
		Size = UDim2.new(0.4, 0, 0, 34),
		Text = "PROFILE",
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = panel,
	})
	Theme.label({
		Position = UDim2.fromOffset(0, 36),
		Size = UDim2.new(0.4, 0, 0, 20),
		Text = player.DisplayName,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Palette.UISubText,
		Parent = panel,
	})
	tabs, pages = {}, {}
	for i, name in ipairs(TABS) do
		local button = Theme.button({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -(#TABS - i) * 138, 0, 4),
			Size = UDim2.fromOffset(130, 36),
			Text = string.upper(name),
			TextSize = 15,
			Parent = panel,
		})
		button.Activated:Connect(function()
			Sfx.Play("CardHover", { Pitch = 1.2 })
			ProfileMenu.Show(name)
		end)
		tabs[name] = button
		pages[name] = Theme.new("Frame", {
			Position = UDim2.fromOffset(0, 72),
			Size = UDim2.new(1, 0, 1, -130),
			BackgroundTransparency = 1,
			Visible = false,
			Parent = panel,
		})
	end

	tutorialButton = Theme.button({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromOffset(260, 42),
		Text = "TUTORIAL",
		TextSize = 17,
		BackgroundColor3 = GOLD,
		Parent = panel,
	})
	tutorialButton.Activated:Connect(function()
		ProfileMenu.Close()
		if Controllers and Controllers.Tutorial then
			Controllers.Tutorial.Start()
		end
	end)
	local done = Theme.button({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromOffset(160, 42),
		Text = "DONE",
		TextSize = 18,
		Parent = panel,
	})
	done.Activated:Connect(ProfileMenu.Close)

	local function refreshTutorialButton()
		local paid = profile and profile.Tutorial
		tutorialButton.Text = paid and "REPLAY TUTORIAL" or ("TUTORIAL  ·  +%d KEYS"):format(Config.Tutorial.RewardKeys)
	end
	refreshTutorialButton()

	Remotes.Get("Profile").OnClientEvent:Connect(function(data)
		if typeof(data) ~= "table" then
			return
		end
		profile = data
		refreshTutorialButton()
		if isOpen and current ~= "Watch" then
			builders[current](pages[current])
		end
	end)
	ClientState.Changed:Connect(function(snapshot, old)
		if snapshot.InMatch then
			ProfileMenu.Close()
		elseif isOpen and current == "Watch" then
			-- live scores move: rebuild the list (cheap: a few rows)
			local a, b = snapshot.LiveMatches, old and old.LiveMatches
			if a ~= b then
				buildWatch(pages.Watch)
			end
		end
	end)
	-- the countdowns tick down while it's open
	local nextTick = 0
	RunService.Heartbeat:Connect(function()
		if isOpen and (current == "Challenges" or current == "Season") and os.clock() >= nextTick then
			nextTick = os.clock() + 30
			builders[current](pages[current])
		end
	end)

	local function onActionInput(input, processed)
		if processed and UserInputService:GetFocusedTextBox() then
			return
		end
		if Controllers and Controllers.Settings and Controllers.Settings.IsOpen() then
			return
		end
		if Keybinds.Matches("Profile", input) then
			if isOpen then
				ProfileMenu.Close()
			elseif not ClientState.InMatch() then
				ProfileMenu.Open()
			end
		end
	end
	UserInputService.InputBegan:Connect(onActionInput)
	Keybinds.VirtualBegan:Connect(onActionInput)
end

return ProfileMenu
