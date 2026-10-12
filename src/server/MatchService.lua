--[[
	MatchService.lua  (ServerScriptService.Server.MatchService)

	Lobby + matchmaking:
	  * Players spawn in the lobby (normal camera).
	  * Pressing PLAY puts you in the queue; the first two queued players are
	    matched into a free arena.
	  * When a match ends, both players come back to the lobby.

	Other services use MatchService.GetMatch(player) to find a player's match.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PowerUps = require(ReplicatedStorage.Shared.PowerUps)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local CharacterService = require(script.Parent.CharacterService)
local MapBuilder = require(script.Parent.MapBuilder)
local DummyService = require(script.Parent.DummyService)
local Match = require(script.Parent.Match)

local MatchService = {}

local lobby
local queue = {} -- ordered list of players waiting
local matchByPlayer = {} -- [player] = Match
local arenas = {} -- [index] = arena info (built on first use)
local arenaInUse = {} -- [index] = true
local practiceOwned = {} -- [player] = { [powerUpId] = stacks }  (lobby Power-Up Lab)
local practiceStats = {} -- [player] = cached stats

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

local function spawnInLobby(player)
	if not player.Parent or matchByPlayer[player] then
		return
	end
	player.CameraMode = Config.Camera.FirstPersonInLobby and Enum.CameraMode.LockFirstPerson
		or Enum.CameraMode.Classic
	CharacterService.Spawn(player, lobby.SpawnCFrame(), {
		Color = Config.Palette.LobbyPlayer,
		MaxHealth = MatchService.GetPracticeStats(player).MaxHealth,
		KillY = lobby.KillY,
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
		if player.Parent then
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
		matchByPlayer[p1] = match
		matchByPlayer[p2] = match
		match:Start()
	end
	broadcastLobby()
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
		else
			-- died in the lobby (fell off): respawn shortly
			task.delay(1.5, spawnInLobby, player)
		end
	end

	Remotes.Get("QueueToggle").OnServerEvent:Connect(onQueueToggle)

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
