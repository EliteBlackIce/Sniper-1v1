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
local PLAYGROUND_DUMMIES = {
	{ Position = Vector3.new(-120, 0.5, 5), Motion = "Strafe", Amount = 10, Speed = 0.3, Face = Vector3.new(1, 0, 0) },
	{ Position = Vector3.new(60, 0.5, -5), Motion = "Strafe", Amount = 12, Speed = 0.25, Face = Vector3.new(-1, 0, 0) },
	{ Position = Vector3.new(-95, 48.8, 62), Face = Vector3.new(0, 0, -1) },
	{ Position = Vector3.new(95, 48.8, 62), Face = Vector3.new(0, 0, -1) },
	{ Position = Vector3.new(-152, 24.8, 60), Face = Vector3.new(1, 0, -1) },
	{ Position = Vector3.new(12, 26.8, 62), Face = Vector3.new(0, 0, -1) },
	{ Position = Vector3.new(0, 31.3, -75), Face = Vector3.new(0, 0, 1) },
	{ Position = Vector3.new(-60, 22, -75), Motion = "Strafe", Amount = 16, Speed = 0.2, Face = Vector3.new(0, 0, 1) },
	{ Position = Vector3.new(-90, 0.3, -47), Motion = "Bob", Amount = 9, Speed = 0.5, Face = Vector3.new(0, 0, 1) },
	{ Position = Vector3.new(150, 0.5, -100), Face = Vector3.new(-1, 0, 0) },
	{ Position = Vector3.new(30, 0.5, -112), Motion = "Strafe", Amount = 8, Speed = 0.4, Face = Vector3.new(0, 0, 1) },
	{ Position = Vector3.new(40, 0.5, 30), Face = Vector3.new(0, 0, -1) },
}

local function getPlayground()
	if not playground then
		playground = MapBuilder.BuildArena(Config.Match.MaxArenas + 2)
		playground.Model.Name = "Playground"
		DummyService.AddSpots(PLAYGROUND_DUMMIES, playground.Origin)
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
		inPlayground[p1] = nil
		inPlayground[p2] = nil
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
