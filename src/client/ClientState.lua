--[[
	ClientState.lua  (Client.ClientState)

	The client's copy of "what's going on": the latest match snapshot from the
	server, this player's power-up stats, and their settings. Other client
	modules read from here and listen to the Changed signals.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local PowerUps = require(Shared.PowerUps)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)

local player = Players.LocalPlayer

local ClientState = {}

ClientState.Snapshot = { Phase = "Lobby", InMatch = false }
ClientState.Stats = PowerUps.ComputeStats({})
ClientState.Settings = table.clone(Config.SettingsDefaults)
ClientState.MenuOpen = false -- true while a menu needs the mouse (settings / pick / victory)

ClientState.Changed = Signal.new() -- (newSnapshot, oldSnapshot)
ClientState.SettingsChanged = Signal.new() -- (settings)
ClientState.MenuChanged = Signal.new() -- (isOpen)

local menuReasons = {}

----------------------------------------------------------------------------
-- Queries
----------------------------------------------------------------------------
function ClientState.InMatch()
	return ClientState.Snapshot.InMatch == true
end

function ClientState.Phase()
	return ClientState.Snapshot.Phase
end

function ClientState.IsFighting()
	return ClientState.Snapshot.InMatch == true and ClientState.Snapshot.Phase == "Fight"
end

-- Phases where you are in the arena with your gun out.
function ClientState.IsInArena()
	local phase = ClientState.Snapshot.Phase
	return ClientState.Snapshot.InMatch == true
		and (phase == "Countdown" or phase == "Fight" or phase == "RoundEnd")
end

-- This player's entry in the snapshot's Players list.
function ClientState.GetMe()
	for _, entry in ipairs(ClientState.Snapshot.Players or {}) do
		if entry.UserId == player.UserId then
			return entry
		end
	end
	return nil
end

function ClientState.GetOpponentEntry()
	for _, entry in ipairs(ClientState.Snapshot.Players or {}) do
		if entry.UserId ~= player.UserId then
			return entry
		end
	end
	return nil
end

function ClientState.GetOpponentPlayer()
	local entry = ClientState.GetOpponentEntry()
	return entry and Players:GetPlayerByUserId(entry.UserId) or nil
end

function ClientState.GetSlotColor(slot)
	return slot == 1 and Config.Palette.PlayerA or Config.Palette.PlayerB
end

-- Seconds left in the current phase (based on the server clock).
function ClientState.TimeLeft()
	local endsAt = ClientState.Snapshot.PhaseEndsAt
	if not endsAt then
		return nil
	end
	return math.max(0, endsAt - workspace:GetServerTimeNow())
end

----------------------------------------------------------------------------
-- Menus (anything that needs a free mouse registers a reason here)
----------------------------------------------------------------------------
function ClientState.SetMenu(reason, open)
	menuReasons[reason] = open or nil
	local isOpen = next(menuReasons) ~= nil
	if isOpen ~= ClientState.MenuOpen then
		ClientState.MenuOpen = isOpen
		ClientState.MenuChanged:Fire(isOpen)
	end
end

----------------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------------
function ClientState.SetSetting(key, value)
	ClientState.Settings[key] = value
	ClientState.SettingsChanged:Fire(ClientState.Settings)
end

function ClientState.SaveSettings()
	Remotes.Get("SettingsSave"):FireServer(ClientState.Settings)
end

----------------------------------------------------------------------------
function ClientState.Init()
	Remotes.Get("MatchState").OnClientEvent:Connect(function(snapshot)
		local old = ClientState.Snapshot
		ClientState.Snapshot = snapshot
		local me = ClientState.GetMe()
		ClientState.Stats = PowerUps.ComputeStats(me and me.PowerUps or {})
		ClientState.Changed:Fire(snapshot, old)
	end)

	Remotes.Get("SettingsLoad").OnClientEvent:Connect(function(settings)
		for key, value in pairs(settings) do
			ClientState.Settings[key] = value
		end
		ClientState.SettingsChanged:Fire(ClientState.Settings)
	end)
end

return ClientState
