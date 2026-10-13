--[[
	MatchService.lua  (ServerScriptService.Server.MatchService)

	Lobby + matchmaking:
	  * Players spawn in the lobby (normal camera).
	  * Pressing PLAY puts you in the queue; the first two queued players are
	    matched into a free arena.
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
local CharacterService = require(script.Parent.CharacterService)
local MapBuilder = require(script.Parent.MapBuilder)
local DummyService = require(script.Parent.DummyService)
local Match = require(script.Parent.Match)
local BotService = require(script.Parent.BotService)

local MatchService = {}

local lobby
local queue = {} -- ordered list of players waiting
local matchByPlayer = {} -- [player] = Match
local arenas = {} -- [index] = arena info (built on first use)
local arenaInUse = {} -- [index] = true
local practiceOwned = {} -- [player] = { [powerUpId] = stacks }  (lobby Power-Up Lab)
local practiceStats = {} -- [player] = cached stats
local inPlayground = {} -- [player] = true while free-roaming the Playground
local playground -- arena info for the Playground (built the first time someone enters)

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

local function lobbySnapshot(player)
	return {
		InMatch = false,
		Phase = "Lobby",
		Queued = isQueued(player),
		QueueCount = #queue,
		PlayersOnline = #Players:GetPlayers(),
		PowerUps = table.clone(practiceOwned[player] or {}),
		Playground = inPlayground[player] == true,
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
	})
	sendLobbyState(player)
end

local function getFreeArena()
	for i = 1, Config.Match.MaxArenas do
		if not arenaInUse[i] then
			if not arenas[i] then
				arenas[i] = MapBuilder.BuildArena(i)
			end
			arenaInUse[i] = true
			return arenas[i]
		end
	end
	return nil
end

----------------------------------------------------------------------------
-- Matchmaking
----------------------------------------------------------------------------
local function onMatchFinished(match)
	arenaInUse[match.Arena.Index] = nil
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

local function tryStartMatches()
	-- drop anyone who left
	for i = #queue, 1, -1 do
		if not queue[i].Parent then
			table.remove(queue, i)
		end
	end
	while #queue >= 2 do
		local arena = getFreeArena()
		if not arena then
			break
		end
		local p1 = table.remove(queue, 1)
		local p2 = table.remove(queue, 1)
		local match = Match.new(p1, p2, arena, onMatchFinished)
		inPlayground[p1] = nil
		inPlayground[p2] = nil
		matchByPlayer[p1] = match
		matchByPlayer[p2] = match
		match:Start()
	end
	broadcastLobby()
end

----------------------------------------------------------------------------
-- Admin commands (bot matches)
----------------------------------------------------------------------------
local function notify(player, text)
	Remotes.Get("Notify"):FireClient(player, text)
end

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
	local arena = getFreeArena()
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
	local match = Match.new(player, bot, arena, onMatchFinished)
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

local function onQueueToggle(player)
	if matchByPlayer[player] then
		return
	end
	local index = table.find(queue, player)
	if index then
		table.remove(queue, index)
	else
		table.insert(queue, player)
	end
	tryStartMatches()
end

----------------------------------------------------------------------------
-- Init
----------------------------------------------------------------------------
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
	Remotes.Get("AdminCommand").OnServerEvent:Connect(onAdminCommand)
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
		local humanoid = CharacterService.GetAliveHumanoid(player)
		if humanoid then
			humanoid.MaxHealth = MatchService.GetPracticeStats(player).MaxHealth
			humanoid.Health = humanoid.MaxHealth
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
		local index = table.find(queue, player)
		if index then
			table.remove(queue, index)
		end
		local match = matchByPlayer[player]
		if match then
			match:OnPlayerLeft(player)
			matchByPlayer[player] = nil
		end
		task.defer(broadcastLobby)
	end)
end

return MatchService
