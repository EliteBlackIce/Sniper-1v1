--[[
	MatchService.lua  (ServerScriptService.Server.MatchService)

	Lobby + matchmaking:
	  * Players spawn in the lobby (normal camera).
	  * Pressing PLAY puts you in the queue. Players are paired by rating:
	    each one accepts opponents within a window that widens the longer
	    they wait, and after Config.Match.Matchmaking.AnyoneAfter seconds
	    anyone will do (the oldest waiter is matched first).
	  * Map vote: every player can pick a favourite map (or ANY). A match
	    uses the map both picked, or one of their two picks at random.
	  * Spectating: lobby players can watch any live match (its snapshots
	    and shots are sent to them too).
	  * When a match ends, both players come back to the lobby.
	  * Admin commands: "/bot [easy|normal|hard]" (or N in the lobby) starts a
	    match against a bot, "/endbot" ends it (see Config.Admin).

	Other services use MatchService.GetMatch(player) to find a player's match.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PowerUps = require(ReplicatedStorage.Shared.PowerUps)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Util = require(ReplicatedStorage.Shared.Util)
local Signal = require(ReplicatedStorage.Shared.Signal)
local CharacterService = require(script.Parent.CharacterService)
local MapBuilder = require(script.Parent.MapBuilder)
local DummyService = require(script.Parent.DummyService)
local Match = require(script.Parent.Match)
local BotService = require(script.Parent.BotService)

local MatchService = {}
MatchService.MatchFinished = Signal.new() -- (match) after a match ends and everyone is back in the lobby
-- (match) the moment the result is known, before the victory screen: rating
-- and keys are paid here and written into match.Results so the screen shows
-- them. Handlers run straight away (Signal uses task.spawn) and must not
-- yield before calling match:SetResult.
MatchService.MatchDecided = Signal.new()

local lobby
local queue = {} -- ordered list of players waiting
local matchByPlayer = {} -- [player] = Match
local arenas = {} -- [index] = arena info (built on first use)
local arenaInUse = {} -- [index] = true
local practiceOwned = {} -- [player] = { [powerUpId] = stacks }  (lobby Power-Up Lab)
local practiceStats = {} -- [player] = cached stats
local inPlayground = {} -- [player] = true while free-roaming the Playground
local invites = {} -- [target] = { [challenger] = { Until = os.clock() expiry, Stake = keys } }
local rematches = {} -- [player] = { Opponent, BotDifficulty, Name, Until, Wants }
local playground -- arena info for the Playground (built the first time someone enters)
local queuedAt = {} -- [player] = os.clock() they joined the queue
local mapVote = {} -- [player] = map name they'd like (nil = any)
local spectating = {} -- [player] = the Match they're watching

----------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------
function MatchService.GetMatch(player)
	return matchByPlayer[player]
end

local function isQueued(player)
	return table.find(queue, player) ~= nil
end

-- Power-ups a player is trying out in the lobby (Power-Up Lab).
function MatchService.GetPracticeStats(player)
	local stats = practiceStats[player]
	if not stats then
		stats = PowerUps.ComputeStats(practiceOwned[player] or {})
		practiceStats[player] = stats
	end
	return stats
end

local MM = Config.Match.Matchmaking or {}

local function ratingOf(player)
	return tonumber(player:GetAttribute("Rating")) or Config.Rank.StartRating
end

-- How far apart in rating this queued player accepts (math.huge = anyone).
local function windowOf(player, now)
	local waited = now - (queuedAt[player] or now)
	if waited >= (MM.AnyoneAfter or 45) then
		return math.huge
	end
	return (MM.BaseWindow or 150) + waited * (MM.GrowPerSecond or 12)
end

-- Every live match, for the lobby's WATCH list.
local function liveMatches()
	local list, seen = {}, {}
	for _, match in pairs(matchByPlayer) do
		if not seen[match] and not match.Finished then
			seen[match] = true
			local players = {}
			for slot, p in ipairs(match.Players) do
				players[slot] = { Name = p.DisplayName, Wins = match.Wins[p] or 0, Bot = Util.isBot(p) or nil }
			end
			local watchers = 0
			for _ in pairs(match.Spectators or {}) do
				watchers += 1
			end
			table.insert(list, {
				Id = match.Id,
				Map = match.Arena and match.Arena.MapName,
				Round = match.Round,
				Phase = match.Phase,
				Players = players,
				Watchers = watchers,
			})
		end
	end
	table.sort(list, function(a, b)
		return a.Id < b.Id
	end)
	return list
end

local function lobbySnapshot(player)
	local window = isQueued(player) and windowOf(player, os.clock()) or nil
	return {
		InMatch = false,
		Phase = "Lobby",
		Queued = isQueued(player),
		QueueCount = #queue,
		PlayersOnline = #Players:GetPlayers(),
		PowerUps = table.clone(practiceOwned[player] or {}),
		Playground = inPlayground[player] == true,
		SearchWindow = window and (window == math.huge and -1 or math.floor(window)) or nil,
		MapVote = mapVote[player],
		Maps = MapBuilder.GetMapList(),
		LiveMatches = liveMatches(),
		Spectating = spectating[player] and spectating[player].Id or nil,
		Rematch = (function()
			local r = rematches[player]
			if not r or os.clock() > r.Until then
				return nil
			end
			local theirs = r.Opponent and rematches[r.Opponent]
			return {
				Name = r.Name,
				Requested = r.Wants == true,
				TheyRequested = theirs ~= nil and theirs.Opponent == player and theirs.Wants == true,
			}
		end)(),
	}
end

local function sendLobbyState(player)
	if player.Parent and not matchByPlayer[player] then
		Remotes.Get("MatchState"):FireClient(player, lobbySnapshot(player))
	end
end

local function broadcastLobby()
	for _, player in ipairs(Players:GetPlayers()) do
		sendLobbyState(player)
	end
end

-- PLAYGROUND: a free-roam copy of the match map with dummies everywhere and
-- the Power-Up Lab, for trying movement and builds without an opponent.
-- (Each map lists its own dummy spots.)
local function getPlayground()
	if not playground then
		playground = MapBuilder.BuildArena(Config.Match.MaxArenas + 2)
		playground.Model.Name = "Playground"
		DummyService.AddSpots(playground.DummySpots or {}, playground.Origin)
	end
	return playground
end

local function spawnInLobby(player)
	if not player.Parent or matchByPlayer[player] then
		return
	end
	if inPlayground[player] then
		local arena = getPlayground()
		player.CameraMode = Enum.CameraMode.LockFirstPerson
		CharacterService.Spawn(player, arena.Spawns[math.random(1, 2)], {
			Color = Config.Palette.LobbyPlayer,
			MaxHealth = MatchService.GetPracticeStats(player).MaxHealth,
			PowerUps = practiceOwned[player],
			KillY = arena.FloorY - Config.Match.VoidDepth,
			Shield = MatchService.GetPracticeStats(player).StartShield,
		})
		sendLobbyState(player)
		return
	end
	player.CameraMode = Config.Camera.FirstPersonInLobby and Enum.CameraMode.LockFirstPerson
		or Enum.CameraMode.Classic
	CharacterService.Spawn(player, lobby.SpawnCFrame(), {
		Color = Config.Palette.LobbyPlayer,
		MaxHealth = MatchService.GetPracticeStats(player).MaxHealth,
		KillY = lobby.KillY,
		PowerUps = practiceOwned[player],
		Shield = MatchService.GetPracticeStats(player).StartShield,
	})
	sendLobbyState(player)
end

-- Each new match picks a random map (never the last one played on this
-- server when there is a choice). A slot that still holds a different map
-- is torn down and rebuilt with the new one.
local lastMapName = nil

local function getFreeArena(preferred)
	if preferred and not table.find(MapBuilder.GetMapList(), preferred) then
		preferred = nil
	end
	for i = 1, Config.Match.MaxArenas do
		if not arenaInUse[i] then
			local mapName = preferred or MapBuilder.PickMap(lastMapName)
			lastMapName = mapName
			local arena = arenas[i]
			if arena and arena.MapName ~= mapName then
				arena.Model:Destroy()
				arenas[i] = nil
			end
			if not arenas[i] then
				arenas[i] = MapBuilder.BuildArena(i, mapName)
			end
			arenaInUse[i] = true
			return arenas[i]
		end
	end
	return nil
end

-- The map two players get: the one they both voted for, else one of
-- their votes at random, else nil (a random map).
local function chooseMap(p1, p2)
	local votes = {}
	for _, p in ipairs({ p1, p2 }) do
		if not Util.isBot(p) and mapVote[p] then
			table.insert(votes, mapVote[p])
		end
	end
	if #votes == 0 then
		return nil
	end
	return votes[math.random(1, #votes)]
end

----------------------------------------------------------------------------
-- Spectating
----------------------------------------------------------------------------
local function stopSpectating(player, quiet)
	local match = spectating[player]
	if match and match.Spectators then
		match.Spectators[player] = nil
	end
	spectating[player] = nil
	if match and not quiet and player.Parent then
		Remotes.Get("SpectateState"):FireClient(player, nil)
	end
end

local function startSpectating(player, matchId)
	if matchByPlayer[player] or typeof(matchId) ~= "number" then
		return
	end
	local target
	for _, match in pairs(matchByPlayer) do
		if match.Id == matchId and not match.Finished then
			target = match
			break
		end
	end
	if not target or spectating[player] == target then
		return
	end
	stopSpectating(player, true)
	target.Spectators = target.Spectators or {}
	target.Spectators[player] = true
	spectating[player] = target
	Remotes.Get("SpectateState"):FireClient(player, target:Snapshot())
end

----------------------------------------------------------------------------
-- Matchmaking
----------------------------------------------------------------------------
local function notify(player, text)
	Remotes.Get("Notify"):FireClient(player, text)
end

-- Duel wagers: the winner takes both stakes; no winner (cancelled) = refunds.
-- (Whoever leaves forfeits: their stake is already gone.)
local function settleWager(match)
	local stake = match.Wager or 0
	if stake <= 0 or match.WagerSettled then
		return
	end
	match.WagerSettled = true
	local CrateService = require(script.Parent.CrateService)
	local winner = match.MatchWinner or (match.Aborted and match.ForfeitWinner) or nil
	if winner then
		-- (both players see the wager on the victory screen)
		if winner.Parent and CrateService.GiveKeys(winner, stake * 2) then
			match:SetResult(winner, "Wager", stake * 2)
		end
		local loser = match:GetOpponent(winner)
		if loser then
			match:SetResult(loser, "Wager", -stake)
		end
	else
		for _, player in ipairs(match.Players) do
			if not Util.isBot(player) and player.Parent and CrateService.GiveKeys(player, stake) then
				notify(player, ("WAGER REFUNDED  -  %d KEYS"):format(stake))
			end
		end
	end
end

local function onDecided(match)
	if match.DecidedFired then
		return
	end
	match.DecidedFired = true
	settleWager(match)
	MatchService.MatchDecided:Fire(match)
end

local function onMatchFinished(match)
	arenaInUse[match.Arena.Index] = nil
	for watcher in pairs(match.Spectators or {}) do
		stopSpectating(watcher)
	end
	onDecided(match) -- (normally already done by OnDecided)
	MatchService.MatchFinished:Fire(match)
	-- remember who you just played so you can ask for a rematch
	local a, b = match.Players[1], match.Players[2]
	for _, pair in ipairs({ { a, b }, { b, a } }) do
		local me, them = pair[1], pair[2]
		if not Util.isBot(me) and me.Parent and (Util.isBot(them) or them.Parent) then
			rematches[me] = {
				Opponent = not Util.isBot(them) and them or nil,
				BotDifficulty = Util.isBot(them) and them.Difficulty or nil,
				Name = them.DisplayName,
				Until = os.clock() + Config.Match.RematchWindow,
				Wants = false,
			}
		end
	end
	for _, player in ipairs(match.Players) do
		if matchByPlayer[player] == match then
			matchByPlayer[player] = nil
		end
		if Util.isBot(player) then
			BotService.Remove(player)
		elseif player.Parent then
			task.spawn(spawnInLobby, player)
		end
	end
	broadcastLobby()
end

-- Creates a match; its state snapshot also carries the map name (MapName)
-- so the HUD can show it.
local function newMatch(p1, p2, arena)
	for _, p in ipairs({ p1, p2 }) do
		stopSpectating(p)
		queuedAt[p] = nil
	end
	local match = Match.new(p1, p2, arena, onMatchFinished)
	match.OnDecided = onDecided
	return match
end

-- The server is shutting down: give every wager still in play back.
function MatchService.RefundAllWagers()
	local done = {}
	for _, match in pairs(matchByPlayer) do
		if not done[match] then
			done[match] = true
			if (match.Wager or 0) > 0 and not match.WagerSettled then
				match.WagerSettled = true
				local CrateService = require(script.Parent.CrateService)
				for _, player in ipairs(match.Players) do
					if not Util.isBot(player) and player.Parent then
						CrateService.GiveKeys(player, match.Wager)
					end
				end
			end
		end
	end
end

-- The next pair to match: the longest waiter with the closest rating that
-- either player's window accepts. Returns two queue indexes (i < j) or nil.
local function findPair()
	local now = os.clock()
	for i, a in ipairs(queue) do
		local best, bestDiff
		for j = i + 1, #queue do
			local b = queue[j]
			local diff = math.abs(ratingOf(a) - ratingOf(b))
			if diff <= math.max(windowOf(a, now), windowOf(b, now)) and (not bestDiff or diff < bestDiff) then
				best, bestDiff = j, diff
			end
		end
		if best then
			return i, best
		end
	end
	return nil
end

-- quiet = only tell the lobby if a match started (the once-a-second retry)
local function tryStartMatches(quiet)
	-- drop anyone who left
	for i = #queue, 1, -1 do
		if not queue[i].Parent then
			table.remove(queue, i)
		end
	end
	local started = false
	while #queue >= 2 do
		local i, j = findPair()
		if not i then
			break
		end
		local arena = getFreeArena(chooseMap(queue[i], queue[j]))
		if not arena then
			break
		end
		local p2 = table.remove(queue, j)
		local p1 = table.remove(queue, i)
		started = true
		local match = newMatch(p1, p2, arena)
		inPlayground[p1] = nil
		inPlayground[p2] = nil
		matchByPlayer[p1] = match
		matchByPlayer[p2] = match
		match:Start()
	end
	if started or not quiet then
		broadcastLobby()
	end
end

----------------------------------------------------------------------------
-- Admin commands (bot matches)
----------------------------------------------------------------------------

local function isAdmin(player)
	local admin = Config.Admin
	if admin.BotForEveryone then
		return true
	end
	if admin.AllowEveryoneInStudio and RunService:IsStudio() then
		return true
	end
	if table.find(admin.UserIds, player.UserId) then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId
	end
	local ok, rank = pcall(function()
		return player:GetRankInGroup(game.CreatorId)
	end)
	return ok and rank >= 255 -- group owner
end

MatchService.IsAdmin = isAdmin

-- "hard" -> "Hard" (falls back to the default difficulty)
local function difficultyName(text)
	if typeof(text) == "string" and #text > 0 then
		local name = string.upper(text:sub(1, 1)) .. string.lower(text:sub(2))
		if Config.Bot.Difficulties[name] then
			return name
		end
	end
	return Config.Bot.DefaultDifficulty
end

function MatchService.StartBotMatch(player, difficulty)
	if matchByPlayer[player] then
		notify(player, "Finish your current match first")
		return
	end
	local arena = getFreeArena(mapVote[player])
	if not arena then
		notify(player, "All arenas are busy - try again soon")
		return
	end
	local index = table.find(queue, player)
	if index then
		table.remove(queue, index)
	end
	difficulty = difficultyName(difficulty)
	local bot = BotService.Create(difficulty)
	inPlayground[player] = nil
	local match = newMatch(player, bot, arena)
	matchByPlayer[player] = match
	matchByPlayer[bot] = match
	BotService.Attach(bot, match)
	notify(player, "Bot match - " .. difficulty)
	match:Start()
	broadcastLobby()
end

local function endBotMatch(player)
	local match = matchByPlayer[player]
	if match and (Util.isBot(match.Players[1]) or Util.isBot(match.Players[2])) then
		match:Cancel()
		notify(player, "Bot match ended")
	else
		notify(player, "You're not in a bot match")
	end
end

local function onAdminCommand(player, command, arg)
	if typeof(command) ~= "string" then
		return
	end
	if not isAdmin(player) then
		notify(player, "Admins only")
		return
	end
	command = string.lower(command)
	if command == "bot" then
		MatchService.StartBotMatch(player, arg)
	elseif command == "endbot" then
		endBotMatch(player)
	end
end

-- "/bot hard" -> onAdminCommand(player, "bot", "hard")
local function onChat(player, text)
	local command, arg = string.match(string.lower(text), "^[/!](%a+)%s*(%a*)")
	if command == "bot" or command == "endbot" then
		onAdminCommand(player, command, arg)
	end
end

local function setupChatCommands()
	if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
		-- new chat: registered commands (they never show up as messages)
		local commands = TextChatService:FindFirstChild("TextChatCommands") or TextChatService
		for _, alias in ipairs({ "/bot", "/endbot" }) do
			local command = Instance.new("TextChatCommand")
			command.Name = "SniperDuel" .. alias:sub(2)
			command.PrimaryAlias = alias
			command.Parent = commands
			command.Triggered:Connect(function(source, text)
				local player = Players:GetPlayerByUserId(source.UserId)
				if player then
					onChat(player, text)
				end
			end)
		end
	else
		-- legacy chat
		local function hook(player)
			player.Chatted:Connect(function(text)
				onChat(player, text)
			end)
		end
		Players.PlayerAdded:Connect(hook)
		for _, player in ipairs(Players:GetPlayers()) do
			hook(player)
		end
	end
end

----------------------------------------------------------------------------
-- Duels: challenge a player from the lobby, and rematches
----------------------------------------------------------------------------
-- stake: keys each player puts up (0 = no wager); both have agreed to it
local function startPrivateMatch(p1, p2, stake)
	stake = stake or 0
	if matchByPlayer[p1] or matchByPlayer[p2] or not p1.Parent or not p2.Parent then
		return false
	end
	local arena = getFreeArena(chooseMap(p1, p2))
	if not arena then
		notify(p1, "All arenas are busy - try again soon")
		notify(p2, "All arenas are busy - try again soon")
		return false
	end
	if stake > 0 then
		-- hold both stakes until the duel ends
		local CrateService = require(script.Parent.CrateService)
		if not CrateService.TakeKeys(p1, stake) then
			notify(p1, ("You don't have %d keys for this wager"):format(stake))
			notify(p2, p1.DisplayName .. " doesn't have the keys for this wager any more")
			arenaInUse[arena.Index] = nil
			return false
		end
		if not CrateService.TakeKeys(p2, stake) then
			CrateService.GiveKeys(p1, stake)
			notify(p2, ("You don't have %d keys for this wager"):format(stake))
			notify(p1, p2.DisplayName .. " doesn't have the keys for this wager any more")
			arenaInUse[arena.Index] = nil
			return false
		end
		for _, p in ipairs({ p1, p2 }) do
			notify(p, ("WAGER: %d KEYS EACH  -  THE WINNER TAKES %d"):format(stake, stake * 2))
		end
	end
	for _, p in ipairs({ p1, p2 }) do
		local index = table.find(queue, p)
		if index then
			table.remove(queue, index)
		end
		inPlayground[p] = nil
		invites[p] = nil
		rematches[p] = nil
	end
	local match = newMatch(p1, p2, arena)
	match.Wager = stake
	matchByPlayer[p1] = match
	matchByPlayer[p2] = match
	match:Start()
	broadcastLobby()
	return true
end

local function inviteValid(target, from)
	local list = invites[target]
	return list and list[from] and os.clock() < list[from].Until
end

-- A wager amount from the client: a whole number of keys, 0 or more.
local function cleanStake(value)
	if typeof(value) ~= "number" or value ~= value then
		return 0
	end
	return math.clamp(math.floor(value), 0, 1000000)
end

local function onDuel(player, action, arg, wager)
	if typeof(action) ~= "string" or matchByPlayer[player] then
		return
	end
	local inviteRemote = Remotes.Get("DuelInvite")
	if action == "Challenge" then
		local target = typeof(arg) == "number" and Players:GetPlayerByUserId(arg) or nil
		if not target or target == player then
			return
		end
		if matchByPlayer[target] then
			notify(player, target.DisplayName .. " is in a match")
			return
		end
		if inviteValid(target, player) then
			return -- already waiting
		end
		local stake = cleanStake(wager)
		if stake > 0 then
			local CrateService = require(script.Parent.CrateService)
			if CrateService.GetKeys(player) < stake then
				notify(player, ("You only have %d keys you can wager (bought keys can't be bet)"):format(CrateService.GetKeys(player)))
				return
			end
		end
		invites[target] = invites[target] or {}
		invites[target][player] = { Until = os.clock() + Config.Match.InviteTime, Stake = stake }
		inviteRemote:FireClient(target, {
			From = player.UserId,
			Name = player.DisplayName,
			Kind = "Challenge",
			Time = Config.Match.InviteTime,
			Stake = stake,
		})
		notify(player, "Challenge sent to " .. target.DisplayName .. (stake > 0 and (" (%d key wager)"):format(stake) or ""))
	elseif action == "Accept" then
		local from = typeof(arg) == "number" and Players:GetPlayerByUserId(arg) or nil
		if from and inviteValid(player, from) then
			local stake = invites[player][from].Stake or 0
			invites[player][from] = nil
			startPrivateMatch(from, player, stake)
		else
			notify(player, "That challenge expired")
		end
	elseif action == "Decline" then
		local from = typeof(arg) == "number" and Players:GetPlayerByUserId(arg) or nil
		if from and invites[player] then
			invites[player][from] = nil
			notify(from, player.DisplayName .. " declined your challenge")
		end
	elseif action == "Rematch" then
		local r = rematches[player]
		if not r or os.clock() > r.Until then
			notify(player, "No rematch available")
			return
		end
		if r.BotDifficulty then
			rematches[player] = nil
			MatchService.StartBotMatch(player, r.BotDifficulty)
			return
		end
		local opponent = r.Opponent
		if not opponent or not opponent.Parent then
			notify(player, r.Name .. " left")
			rematches[player] = nil
			sendLobbyState(player)
			return
		end
		r.Wants = true
		local theirs = rematches[opponent]
		if theirs and theirs.Opponent == player and theirs.Wants then
			startPrivateMatch(opponent, player)
			return
		end
		if matchByPlayer[opponent] then
			notify(player, r.Name .. " is already in another match")
			return
		end
		inviteRemote:FireClient(opponent, { From = player.UserId, Name = player.DisplayName, Kind = "Rematch", Time = Config.Match.InviteTime })
		notify(player, "Rematch requested")
		sendLobbyState(player)
		sendLobbyState(opponent)
	end
end

local function onQueueToggle(player)
	if matchByPlayer[player] then
		return
	end
	local index = table.find(queue, player)
	if index then
		table.remove(queue, index)
		queuedAt[player] = nil
	else
		table.insert(queue, player)
		queuedAt[player] = os.clock()
	end
	tryStartMatches()
end

----------------------------------------------------------------------------
-- Init
----------------------------------------------------------------------------
-- The lobby (built in Init): Model, CrateAltar, ...
function MatchService.GetLobby()
	return lobby
end

function MatchService.Init()
	lobby = MapBuilder.BuildLobby()
	DummyService.Init(lobby.DummySpots)

	CharacterService.OnDied = function(player)
		local match = matchByPlayer[player]
		if match then
			match:OnPlayerDied(player)
		elseif not Util.isBot(player) then
			-- died in the lobby (fell off): respawn shortly
			task.delay(1.5, spawnInLobby, player)
		end
	end

	Remotes.Get("QueueToggle").OnServerEvent:Connect(onQueueToggle)
	Remotes.Get("MapVote").OnServerEvent:Connect(function(player, mapName)
		if mapName == nil or (typeof(mapName) == "string" and table.find(MapBuilder.GetMapList(), mapName)) then
			mapVote[player] = mapName
			sendLobbyState(player)
		end
	end)
	Remotes.Get("Spectate").OnServerEvent:Connect(function(player, matchId)
		if matchId == nil then
			stopSpectating(player)
		else
			startSpectating(player, matchId)
		end
		sendLobbyState(player)
	end)
	-- windows widen while people wait, and the WATCH list follows live scores
	task.spawn(function()
		local lastLive = ""
		while true do
			task.wait(1)
			if #queue >= 2 then
				tryStartMatches(true)
			end
			local parts = {}
			for _, m in ipairs(liveMatches()) do
				table.insert(parts, ("%d:%s:%d:%d:%d"):format(m.Id, m.Phase, m.Round or 0, (m.Players[1] and m.Players[1].Wins or 0) * 10 + (m.Players[2] and m.Players[2].Wins or 0), m.Watchers))
			end
			local live = table.concat(parts, ",")
			if live ~= lastLive or #queue > 0 then
				-- (queued players also see their search window widen)
				lastLive = live
				broadcastLobby()
			end
		end
	end)
	Remotes.Get("AdminCommand").OnServerEvent:Connect(onAdminCommand)
	Remotes.Get("Duel").OnServerEvent:Connect(onDuel)
	setupChatCommands()

	-- enter / leave the Playground
	Remotes.Get("PlaygroundToggle").OnServerEvent:Connect(function(player)
		if matchByPlayer[player] then
			return
		end
		inPlayground[player] = not inPlayground[player] or nil
		task.spawn(spawnInLobby, player)
	end)

	-- POWER-UP LAB: try any power-up in the lobby
	Remotes.Get("Practice").OnServerEvent:Connect(function(player, action, id)
		if matchByPlayer[player] then
			return
		end
		local owned = practiceOwned[player] or {}
		local def = typeof(id) == "string" and PowerUps.Get(id) or nil
		if action == "Add" and def then
			owned[id] = math.min((owned[id] or 0) + 1, def.MaxStacks or 1)
		elseif action == "Remove" and def then
			owned[id] = (owned[id] or 0) > 1 and owned[id] - 1 or nil
		elseif action == "Clear" then
			owned = {}
		else
			return
		end
		practiceOwned[player] = owned
		practiceStats[player] = nil
		-- Thick Skin etc. apply right away
		local humanoid, character = CharacterService.GetAliveHumanoid(player)
		if humanoid then
			humanoid.MaxHealth = MatchService.GetPracticeStats(player).MaxHealth
			humanoid.Health = humanoid.MaxHealth
			character:SetAttribute("Shield", MatchService.GetPracticeStats(player).StartShield) -- Overshield
		end
		CharacterService.RefreshWorldGun(player, owned)
		sendLobbyState(player)
	end)

	Remotes.Get("PickCard").OnServerEvent:Connect(function(player, index)
		local match = matchByPlayer[player]
		if match then
			match:OnPickCard(player, index)
		end
	end)

	local function onPlayerAdded(player)
		player:SetAttribute("InMatch", false)
		spawnInLobby(player)
		broadcastLobby()
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		practiceOwned[player] = nil
		practiceStats[player] = nil
		inPlayground[player] = nil
		invites[player] = nil
		rematches[player] = nil
		for _, list in pairs(invites) do
			list[player] = nil
		end
		local index = table.find(queue, player)
		if index then
			table.remove(queue, index)
		end
		queuedAt[player] = nil
		mapVote[player] = nil
		stopSpectating(player, true)
		local match = matchByPlayer[player]
		if match then
			match:OnPlayerLeft(player)
			matchByPlayer[player] = nil
		end
		task.defer(broadcastLobby)
	end)
end

return MatchService
