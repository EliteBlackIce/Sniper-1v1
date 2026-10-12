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
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local CharacterService = require(script.Parent.CharacterService)
local MapBuilder = require(script.Parent.MapBuilder)
local Match = require(script.Parent.Match)

local MatchService = {}

local lobby
local queue = {} -- ordered list of players waiting
local matchByPlayer = {} -- [player] = Match
local arenas = {} -- [index] = arena info (built on first use)
local arenaInUse = {} -- [index] = true

----------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------
function MatchService.GetMatch(player)
	return matchByPlayer[player]
end

local function isQueued(player)
	return table.find(queue, player) ~= nil
end

local function lobbySnapshot(player)
	return {
		InMatch = false,
		Phase = "Lobby",
		Queued = isQueued(player),
		QueueCount = #queue,
		PlayersOnline = #Players:GetPlayers(),
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
	player.CameraMode = Enum.CameraMode.Classic
	CharacterService.Spawn(player, lobby.SpawnCFrame(), {
		Color = Config.Palette.LobbyPlayer,
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
