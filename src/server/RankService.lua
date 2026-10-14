--[[
	RankService.lua  (ServerScriptService.Server.RankService)

	Ranked rating (Config.Rank):
	  * Every player has a rating (player attributes "Rating", "RankWins",
	    "RankLosses"), saved in a DataStore. New players start at
	    Config.Rank.StartRating.
	  * When a match between two players ends, the winner gains and the
	    loser loses rating (Elo: the bigger the upset, the bigger the swing).
	    Leaving a match counts as a loss. Bot matches don't count.
	  * The leaderboard wall in the lobby (LobbyBuilder's "Leaderboard"
	    board) shows the top players, from an OrderedDataStore, refreshed
	    every Config.Rank.LeaderboardRefresh seconds. Without DataStore
	    access (Studio with API access off) it ranks whoever is online.
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Util = require(ReplicatedStorage.Shared.Util)

local RankService = {}

local RK = Config.Rank
local MatchService

local store, board
pcall(function()
	store = DataStoreService:GetDataStore("Rank_v1")
	board = DataStoreService:GetOrderedDataStore("RankBoard_v1")
end)

local data = {} -- [player] = { Rating, Wins, Losses, Peak }
local loadFailed = {} -- [player] = true: never overwrite a save we couldn't read
local names = {} -- [userId] = display name (cache for the board)

local function notify(player, text)
	Remotes.Get("Notify"):FireClient(player, text)
end

local function publish(player)
	local d = data[player]
	if d then
		player:SetAttribute("Rating", d.Rating)
		player:SetAttribute("RankWins", d.Wins)
		player:SetAttribute("RankLosses", d.Losses)
	end
end

----------------------------------------------------------------------------
-- Saving
----------------------------------------------------------------------------
local function save(player)
	local d = data[player]
	if not store or not d or loadFailed[player] then
		return
	end
	local key = "u" .. player.UserId
	local ok, err = pcall(function()
		store:SetAsync(key, { Rating = d.Rating, Wins = d.Wins, Losses = d.Losses, Peak = d.Peak })
	end)
	if not ok then
		warn("[RankService] save failed for", player.Name, err)
	end
	if board then
		pcall(function()
			board:SetAsync(key, math.floor(d.Rating))
		end)
	end
end

local function load(player)
	local saved
	if store then
		local ok, result
		for attempt = 1, 3 do
			ok, result = pcall(function()
				return store:GetAsync("u" .. player.UserId)
			end)
			if ok then
				break
			end
			task.wait(attempt)
		end
		if ok then
			saved = result
		else
			loadFailed[player] = true
			warn("[RankService] couldn't load the rating of", player.Name, result)
		end
	end
	if not player.Parent then
		return
	end
	local d = { Rating = RK.StartRating, Wins = 0, Losses = 0, Peak = RK.StartRating }
	if typeof(saved) == "table" then
		for _, field in ipairs({ "Rating", "Wins", "Losses", "Peak" }) do
			if typeof(saved[field]) == "number" then
				d[field] = math.max(0, math.floor(saved[field]))
			end
		end
	end
	data[player] = d
	names[player.UserId] = player.DisplayName
	publish(player)
end

-- A player who already left (forfeited, or quit on the victory screen):
-- change their saved rating.
local function adjustOffline(userId, delta, won)
	if not store then
		return
	end
	task.spawn(function()
		local rating
		pcall(function()
			store:UpdateAsync("u" .. userId, function(old)
				old = typeof(old) == "table" and old or { Rating = RK.StartRating, Wins = 0, Losses = 0, Peak = RK.StartRating }
				old.Rating = math.max(0, math.floor((old.Rating or RK.StartRating) + delta))
				if won then
					old.Wins = (old.Wins or 0) + 1
					old.Peak = math.max(old.Peak or 0, old.Rating)
				else
					old.Losses = (old.Losses or 0) + 1
				end
				rating = old.Rating
				return old
			end)
		end)
		if board and rating then
			pcall(function()
				board:SetAsync("u" .. userId, rating)
			end)
		end
	end)
end

----------------------------------------------------------------------------
-- Rating changes
----------------------------------------------------------------------------
local lastKnown = {} -- [userId] = { Rating, Played } (so a player who left can still be scored)

local function ratingOf(player)
	local d = data[player]
	if d then
		return d.Rating, d.Wins + d.Losses
	end
	local known = lastKnown[player.UserId]
	if known then
		return known.Rating, known.Played
	end
	return RK.StartRating, 0
end

-- Elo: how much the winner gains (and the loser loses).
local function swing(winnerRating, loserRating, played)
	local expected = 1 / (1 + 10 ^ ((loserRating - winnerRating) / 400))
	local k = played < RK.PlacementMatches and RK.PlacementK or RK.K
	return math.max(1, math.floor(k * (1 - expected) + 0.5))
end

local function onMatchFinished(match)
	local a, b = match.Players[1], match.Players[2]
	if not a or not b or Util.isBot(a) or Util.isBot(b) then
		return -- matches against the bot are unranked
	end
	local winner = match.MatchWinner or (match.Aborted and match.ForfeitWinner) or nil
	if not winner then
		return -- cancelled
	end
	if not match.MatchWinner then
		-- a forfeit only counts once a round has been played (no free rating
		-- from an alt that joins and leaves)
		local rounds = 0
		for _, wins in pairs(match.Wins or {}) do
			rounds += wins
		end
		if rounds < 1 then
			return
		end
	end
	local loser = winner == a and b or a
	local wr, wPlayed = ratingOf(winner)
	local lr, lPlayed = ratingOf(loser)
	local gain = swing(wr, lr, wPlayed)
	local loss = swing(wr, lr, lPlayed)

	for _, info in ipairs({ { winner, gain, true }, { loser, -loss, false } }) do
		local player, delta, won = info[1], info[2], info[3]
		local d = data[player]
		if d and player.Parent then
			local before = Config.RankTier(d.Rating)
			d.Rating = math.max(0, d.Rating + delta)
			d.Peak = math.max(d.Peak, d.Rating)
			if won then
				d.Wins += 1
			else
				d.Losses += 1
			end
			publish(player)
			local after = Config.RankTier(d.Rating)
			local text = ("%s%d RATING  -  %s %d"):format(delta >= 0 and "+" or "", delta, after.Name, d.Rating)
			if after ~= before then
				text = (after.Min > before.Min and "RANKED UP!  " or "RANKED DOWN  ") .. text
			end
			if not loadFailed[player] then
				notify(player, text)
				task.spawn(save, player)
			end
		elseif not d then
			adjustOffline(player.UserId, delta, won) -- they already left
		end
	end
end

----------------------------------------------------------------------------
-- Leaderboard
----------------------------------------------------------------------------
local function nameOf(userId)
	if names[userId] then
		return names[userId]
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	names[userId] = ok and name or ("Player " .. userId)
	return names[userId]
end

-- The top players: { { Name, Rating } } (best first).
local function topPlayers()
	local list = {}
	local seen = {}
	if board then
		local ok, pages = pcall(function()
			return board:GetSortedAsync(false, RK.LeaderboardSize)
		end)
		if ok and pages then
			for _, entry in ipairs(pages:GetCurrentPage()) do
				local userId = tonumber(tostring(entry.key):sub(2))
				if userId then
					seen[userId] = #list + 1
					table.insert(list, { UserId = userId, Rating = entry.value })
				end
			end
		end
	end
	-- online players are always current (the ordered store lags a little)
	for player, d in pairs(data) do
		if player.Parent and not loadFailed[player] then
			local index = seen[player.UserId]
			if index then
				list[index].Rating = d.Rating
			else
				table.insert(list, { UserId = player.UserId, Rating = d.Rating })
			end
		end
	end
	table.sort(list, function(x, y)
		return x.Rating > y.Rating
	end)
	local top = {}
	for i = 1, math.min(#list, RK.LeaderboardSize) do
		top[i] = { Name = nameOf(list[i].UserId), Rating = math.floor(list[i].Rating) }
	end
	return top
end

local function drawBoard(rows, top)
	for i, row in ipairs(rows) do
		local entry = top[i]
		row.Name.Text = entry and entry.Name or "-"
		row.Rating.Text = entry and tostring(entry.Rating) or ""
		local tier = entry and Config.RankTier(entry.Rating)
		row.Tier.Text = tier and tier.Name or ""
		row.Tier.TextColor3 = tier and tier.Color or Color3.new(1, 1, 1)
		row.Frame.BackgroundTransparency = entry and (i <= 3 and 0.55 or 0.75) or 0.9
	end
end

-- Builds the board's text on the lobby's Leaderboard part.
local function buildBoard(part)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = part
	local font = Config.UI.FontFamily
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromScale(0.05, 0.03)
	title.Size = UDim2.fromScale(0.9, 0.12)
	title.Text = "TOP SNIPERS"
	title.TextScaled = true
	title.FontFace = Font.new(font, Enum.FontWeight.Heavy)
	title.TextColor3 = Config.Palette.UIText
	title.Parent = gui
	local sub = title:Clone()
	sub.Position = UDim2.fromScale(0.05, 0.15)
	sub.Size = UDim2.fromScale(0.9, 0.05)
	sub.Text = "RANKED RATING  -  WIN DUELS TO CLIMB"
	sub.FontFace = Font.new(font, Enum.FontWeight.Bold)
	sub.TextColor3 = Config.Palette.UIAccent
	sub.Parent = gui
	local rows = {}
	local n = RK.LeaderboardSize
	for i = 1, n do
		local frame = Instance.new("Frame")
		frame.BackgroundColor3 = i == 1 and Color3.fromRGB(255, 196, 60) or i == 2 and Color3.fromRGB(200, 206, 216)
			or i == 3 and Color3.fromRGB(205, 130, 80) or Config.Palette.UIPanelLight
		frame.BorderSizePixel = 0
		frame.Position = UDim2.fromScale(0.05, 0.23 + (i - 1) * 0.074)
		frame.Size = UDim2.fromScale(0.9, 0.064)
		frame.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.25, 0)
		corner.Parent = frame
		local function text(x, w, align, weight, color)
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Position = UDim2.fromScale(x, 0.12)
			label.Size = UDim2.fromScale(w, 0.76)
			label.TextScaled = true
			label.TextXAlignment = align
			label.FontFace = Font.new(font, weight)
			label.TextColor3 = color or Config.Palette.UIText
			label.Parent = frame
			return label
		end
		text(0.02, 0.08, Enum.TextXAlignment.Center, Enum.FontWeight.Heavy).Text = tostring(i)
		rows[i] = {
			Frame = frame,
			Name = text(0.13, 0.47, Enum.TextXAlignment.Left, Enum.FontWeight.Bold),
			Tier = text(0.6, 0.2, Enum.TextXAlignment.Right, Enum.FontWeight.Heavy),
			Rating = text(0.82, 0.16, Enum.TextXAlignment.Right, Enum.FontWeight.Heavy, Config.Palette.UIAccent),
		}
	end
	drawBoard(rows, {})
	return rows
end

function RankService.Init(matchService)
	MatchService = matchService
	MatchService.MatchFinished:Connect(onMatchFinished)

	Players.PlayerAdded:Connect(load)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(load, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local d = data[player]
		if d then
			lastKnown[player.UserId] = { Rating = d.Rating, Played = d.Wins + d.Losses }
		end
		save(player)
		data[player] = nil
		loadFailed[player] = nil
	end)
	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(save, player)
		end
		task.wait(2)
	end)

	local lobby = MatchService.GetLobby()
	local part = lobby and lobby.Leaderboard
	if part then
		local rows = buildBoard(part)
		task.spawn(function()
			task.wait(5) -- (let the first players load)
			while true do
				local ok, top = pcall(topPlayers)
				if ok then
					drawBoard(rows, top)
				else
					warn("[RankService] leaderboard:", top)
				end
				task.wait(RK.LeaderboardRefresh)
			end
		end)
	end
end

return RankService
