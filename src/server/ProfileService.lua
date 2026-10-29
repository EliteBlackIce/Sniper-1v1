--[[
	ProfileService.lua  (ServerScriptService.Server.ProfileService)

	Everything about YOU that isn't skins or rating (DataStore):
	  * Lifetime stats: matches, wins, losses, rounds won, kills, headshots,
	    knife kills, shots, hits, damage, longest hit, win streaks, flawless wins.
	  * Challenges (Config.Challenges): DailyCount random dailies every UTC
	    day and WeeklyCount weeklies every week. Progress comes from finished
	    matches; a finished challenge pays its keys straight away (and shows
	    on the victory screen).
	  * Tutorial: finishing it once pays Config.Tutorial.RewardKeys.
	  * Power-up telemetry: across every server, how often each power-up is
	    offered, picked, held at the end of a match and held by the winner.
	    Admins type "/pustats" to print the pick and win rates.

	The client gets its profile through the "Profile" remote and asks for
	it / reports the tutorial through "ProfileAction".
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Util = require(ReplicatedStorage.Shared.Util)

local ProfileService = {}
local MatchService

local CH = Config.Challenges
local STAT_KEYS = {
	"Matches", "Wins", "Losses", "RoundsWon", "Kills", "Headshots", "KnifeKills",
	"Shots", "Hits", "Damage", "Longest", "Streak", "BestStreak", "Flawless", "LongHits",
}

local store, telemetryStore
pcall(function()
	store = DataStoreService:GetDataStore("SniperDuelProfile_v1")
	telemetryStore = DataStoreService:GetDataStore("SniperDuelPowerUpStats_v1")
end)

local data = {} -- [player] = profile
local loadFailed = {} -- [player] = true: never overwrite a save we couldn't read
local pendingTelemetry = {} -- [id] = { Offered, Picked, Held, Won }

local challengeById = {}
for _, list in ipairs({ CH.Daily, CH.Weekly }) do
	for _, c in ipairs(list) do
		challengeById[c.Id] = c
	end
end

local function notify(player, text)
	Remotes.Get("Notify"):FireClient(player, text)
end

local function today()
	return math.floor(os.time() / 86400)
end

local function thisWeek()
	return math.floor((os.time() / 86400 + 3) / 7) -- (weeks start on Monday)
end

----------------------------------------------------------------------------
-- Challenges
----------------------------------------------------------------------------
-- A fresh set: `count` different challenges from `pool`, the same set for
-- this player all day / week (seeded), so rejoining doesn't reroll.
local function rollSet(pool, count, seed)
	local rng = Random.new(seed)
	local ids = {}
	for _, c in ipairs(pool) do
		table.insert(ids, c.Id)
	end
	local list = {}
	while #list < count and #ids > 0 do
		local id = table.remove(ids, rng:NextInteger(1, #ids))
		table.insert(list, { Id = id, Progress = 0, Done = false })
	end
	return list
end

local function refreshChallenges(player, d)
	local day, week = today(), thisWeek()
	if not d.Daily or d.Daily.Day ~= day then
		d.Daily = { Day = day, List = rollSet(CH.Daily, CH.DailyCount, player.UserId * 7 + day) }
	end
	if not d.Weekly or d.Weekly.Week ~= week then
		d.Weekly = { Week = week, List = rollSet(CH.Weekly, CH.WeeklyCount, player.UserId * 13 + week * 31) }
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
	local ok, err = pcall(function()
		store:SetAsync("u" .. player.UserId, d)
	end)
	if not ok then
		warn("[ProfileService] save failed for", player.Name, err)
	end
end

local function send(player)
	local d = data[player]
	if d and player.Parent then
		refreshChallenges(player, d)
		local _, _, seasonEnds = Config.SeasonAt(os.time())
		Remotes.Get("Profile"):FireClient(player, {
			Stats = d.Stats,
			Daily = d.Daily,
			Weekly = d.Weekly,
			Tutorial = d.Tutorial == true,
			DailyResetsAt = (today() + 1) * 86400,
			WeeklyResetsAt = (thisWeek() + 1) * 7 * 86400 - 3 * 86400,
			SeasonEndsAt = seasonEnds,
		})
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
			warn("[ProfileService] couldn't load the profile of", player.Name, result)
		end
	end
	if not player.Parent then
		loadFailed[player] = nil
		return
	end
	local d = { Stats = {}, Tutorial = false }
	for _, key in ipairs(STAT_KEYS) do
		d.Stats[key] = 0
	end
	if typeof(saved) == "table" then
		if typeof(saved.Stats) == "table" then
			for _, key in ipairs(STAT_KEYS) do
				if typeof(saved.Stats[key]) == "number" then
					d.Stats[key] = math.max(0, saved.Stats[key])
				end
			end
		end
		d.Tutorial = saved.Tutorial == true
		-- keep this period's challenges (only ids we still know)
		for _, kind in ipairs({ "Daily", "Weekly" }) do
			local period = saved[kind]
			if typeof(period) == "table" and typeof(period.List) == "table" then
				local list = {}
				for _, c in ipairs(period.List) do
					if typeof(c) == "table" and challengeById[c.Id] then
						table.insert(list, { Id = c.Id, Progress = tonumber(c.Progress) or 0, Done = c.Done == true })
					end
				end
				d[kind] = { Day = period.Day, Week = period.Week, List = list }
			end
		end
	end
	refreshChallenges(player, d)
	data[player] = d
	send(player)
end

----------------------------------------------------------------------------
-- Finished matches
----------------------------------------------------------------------------
local function telemetry(id, field, amount)
	local t = pendingTelemetry[id]
	if not t then
		t = { Offered = 0, Picked = 0, Held = 0, Won = 0 }
		pendingTelemetry[id] = t
	end
	t[field] += amount or 1
end

local function onMatchDecided(match)
	local winner = match.MatchWinner or (match.Aborted and match.ForfeitWinner) or nil
	if not winner then
		return -- cancelled
	end
	local roundsToWin = Config.Match.RoundsToWin
	local anyBot = Util.isBot(match.Players[1]) or Util.isBot(match.Players[2])

	-- power-up telemetry (real duels only: bots pick differently)
	if not anyBot then
		for id, n in pairs(match.CardLog and match.CardLog.Offered or {}) do
			telemetry(id, "Offered", n)
		end
		for id, n in pairs(match.CardLog and match.CardLog.Picked or {}) do
			telemetry(id, "Picked", n)
		end
		for _, p in ipairs(match.Players) do
			for id, stacks in pairs(match.Owned[p] or {}) do
				if stacks > 0 then
					telemetry(id, "Held")
					if p == winner then
						telemetry(id, "Won")
					end
				end
			end
		end
	end

	for _, player in ipairs(match.Players) do
		local d = data[player]
		if d and not Util.isBot(player) and player.Parent then
			local won = player == winner
			local opponent = match:GetOpponent(player)
			local tally = match.Tally and match.Tally[player] or {}
			-- what this match adds (challenge stats use the same names)
			local add = {
				Matches = 1,
				Wins = won and 1 or 0,
				Losses = won and 0 or 1,
				RoundsWon = match.Wins[player] or 0,
				Kills = tally.Kills or 0,
				Headshots = tally.Headshots or 0,
				KnifeKills = tally.KnifeKills or 0,
				Shots = tally.Shots or 0,
				Hits = tally.Hits or 0,
				Damage = math.floor(tally.Damage or 0),
				LongHits = tally.LongHits or 0,
				Flawless = (won and (match.Wins[opponent] or 0) == 0 and (match.Wins[player] or 0) >= roundsToWin) and 1 or 0,
			}
			local s = d.Stats
			for key, value in pairs(add) do
				s[key] = (s[key] or 0) + value
			end
			s.Longest = math.max(s.Longest or 0, tally.Longest or 0)
			s.Streak = won and (s.Streak or 0) + 1 or 0
			s.BestStreak = math.max(s.BestStreak or 0, s.Streak)

			-- challenges
			refreshChallenges(player, d)
			local doneCount, doneKeys = 0, 0
			for _, period in ipairs({ d.Daily, d.Weekly }) do
				for _, c in ipairs(period.List) do
					local def = challengeById[c.Id]
					if def and not c.Done then
						c.Progress = math.min(def.Goal, c.Progress + (add[def.Stat] or 0))
						if c.Progress >= def.Goal then
							c.Done = true
							doneCount += 1
							doneKeys += def.Keys
						end
					end
				end
			end
			if doneKeys > 0 then
				local CrateService = require(script.Parent.CrateService)
				CrateService.GiveKeys(player, doneKeys)
				match:SetResult(player, "Challenges", { Count = doneCount, Keys = doneKeys })
			end
			task.spawn(save, player)
			task.defer(send, player)
		end
	end
end

----------------------------------------------------------------------------
-- Power-up telemetry
----------------------------------------------------------------------------
local function flushTelemetry()
	if not telemetryStore or next(pendingTelemetry) == nil then
		return
	end
	local batch = pendingTelemetry
	pendingTelemetry = {}
	local ok, err = pcall(function()
		telemetryStore:UpdateAsync("global", function(old)
			old = typeof(old) == "table" and old or {}
			for id, t in pairs(batch) do
				local row = typeof(old[id]) == "table" and old[id] or { Offered = 0, Picked = 0, Held = 0, Won = 0 }
				for field, n in pairs(t) do
					row[field] = (tonumber(row[field]) or 0) + n
				end
				old[id] = row
			end
			return old
		end)
	end)
	if not ok then
		warn("[ProfileService] telemetry save failed:", err)
		for id, t in pairs(batch) do -- try again next time
			for field, n in pairs(t) do
				telemetry(id, field, n)
			end
		end
	end
end

-- "/pustats": pick rate (picked / offered) and win rate (won / held) per power-up.
local function printTelemetry(player)
	task.spawn(function()
		flushTelemetry()
		local ok, all = pcall(function()
			return telemetryStore and telemetryStore:GetAsync("global")
		end)
		if not ok or typeof(all) ~= "table" then
			notify(player, "No power-up stats yet")
			return
		end
		local rows = {}
		for id, row in pairs(all) do
			local offered, picked = tonumber(row.Offered) or 0, tonumber(row.Picked) or 0
			local held, won = tonumber(row.Held) or 0, tonumber(row.Won) or 0
			table.insert(rows, {
				Id = id,
				Pick = offered > 0 and picked / offered or 0,
				Win = held > 0 and won / held or 0,
				Held = held,
			})
		end
		table.sort(rows, function(a, b)
			return a.Win > b.Win
		end)
		print("[PowerUpStats] id | pick rate | win rate | matches held")
		for _, r in ipairs(rows) do
			print(("[PowerUpStats] %-18s %5.1f%%  %5.1f%%  %d"):format(r.Id, r.Pick * 100, r.Win * 100, r.Held))
		end
		local top, bottom = rows[1], rows[#rows]
		notify(player, ("POWER-UP STATS IN THE OUTPUT  -  BEST %s %d%%  -  WORST %s %d%%"):format(
			top and top.Id or "-", top and math.floor(top.Win * 100) or 0,
			bottom and bottom.Id or "-", bottom and math.floor(bottom.Win * 100) or 0
		))
	end)
end

local function setupCommand()
	local function run(player)
		if MatchService.IsAdmin and MatchService.IsAdmin(player) then
			printTelemetry(player)
		else
			notify(player, "Admins only")
		end
	end
	if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
		local commands = TextChatService:FindFirstChild("TextChatCommands") or TextChatService
		local command = Instance.new("TextChatCommand")
		command.Name = "SniperDuelPuStats"
		command.PrimaryAlias = "/pustats"
		command.Parent = commands
		command.Triggered:Connect(function(source)
			local player = Players:GetPlayerByUserId(source.UserId)
			if player then
				run(player)
			end
		end)
	else
		local function hook(player)
			player.Chatted:Connect(function(text)
				if string.lower(text) == "/pustats" then
					run(player)
				end
			end)
		end
		Players.PlayerAdded:Connect(hook)
		for _, player in ipairs(Players:GetPlayers()) do
			hook(player)
		end
	end
end

----------------------------------------------------------------------------
-- Init
----------------------------------------------------------------------------
function ProfileService.Init(matchService)
	MatchService = matchService
	MatchService.MatchDecided:Connect(onMatchDecided)

	Remotes.Get("ProfileAction").OnServerEvent:Connect(function(player, action)
		local d = data[player]
		if not d then
			return
		end
		if action == "Get" then
			send(player)
		elseif action == "TutorialDone" and not d.Tutorial then
			d.Tutorial = true
			local CrateService = require(script.Parent.CrateService)
			local reward = Config.Tutorial.RewardKeys
			if reward > 0 and CrateService.GiveKeys(player, reward) then
				notify(player, ("TUTORIAL COMPLETE  -  +%d KEYS"):format(reward))
			end
			task.spawn(save, player)
			send(player)
		end
	end)

	Players.PlayerAdded:Connect(load)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(load, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		save(player)
		data[player] = nil
		loadFailed[player] = nil
	end)
	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(save, player)
		end
		flushTelemetry()
		task.wait(2)
	end)

	-- a new day / week while you're on: refresh your challenges
	task.spawn(function()
		while true do
			task.wait(300)
			flushTelemetry()
			for player in pairs(data) do
				send(player)
			end
		end
	end)
	setupCommand()
end

return ProfileService
