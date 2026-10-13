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
ClientState.Owned = {} -- { [powerUpId] = stacks } you have right now (match or Power-Up Lab)
ClientState.Settings = table.clone(Config.SettingsDefaults)
ClientState.MenuOpen = false -- true while a menu needs the mouse (settings / pick / victory)
ClientState.Weapon = "Sniper" -- what's in your hands: "Sniper" or "Knife" (KnifeController)

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

-- True when you should be holding your sniper: in the lobby (practice range)
-- or in the arena during a round.
function ClientState.HasGun()
	return not ClientState.Snapshot.InMatch or ClientState.IsInArena()
end

-- True when shots are allowed: practice in the lobby, or a live round.
function ClientState.CanShoot()
	return not ClientState.Snapshot.InMatch or ClientState.IsFighting()
end

-- Positions bullets may home in on: the enemy's torso, or the practice dummies.
function ClientState.GetHomingTargets()
	if ClientState.Snapshot.InMatch then
		local opponent = ClientState.GetOpponentPlayer()
		local character = opponent and opponent.Character
		local torso = character and (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso"))
		return torso and { torso.Position } or {}
	end
	local targets = {}
	local folder = workspace:FindFirstChild("Dummies")
	for _, dummy in ipairs(folder and folder:GetChildren() or {}) do
		local torso = dummy:FindFirstChild("UpperTorso")
		if torso and not dummy:GetAttribute("Down") then
			table.insert(targets, torso.Position)
		end
	end
	return targets
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

-- The Player with this UserId, or for a bot (server AI, not a real Player)
-- a stand-in table { UserId, Name, DisplayName, Character, IsBot }.
function ClientState.FindPlayer(userId)
	local real = Players:GetPlayerByUserId(userId)
	if real then
		return real
	end
	for _, entry in ipairs(ClientState.Snapshot.Players or {}) do
		if entry.UserId == userId and entry.IsBot then
			local bots = workspace:FindFirstChild("Bots")
			return {
				UserId = entry.UserId,
				Name = entry.Name,
				DisplayName = entry.Name,
				IsBot = true,
				Character = bots and entry.CharacterName and bots:FindFirstChild(entry.CharacterName) or nil,
			}
		end
	end
	return nil
end

-- Your opponent (a Player, or a bot stand-in - see FindPlayer).
function ClientState.GetOpponentPlayer()
	local entry = ClientState.GetOpponentEntry()
	return entry and ClientState.FindPlayer(entry.UserId) or nil
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
		-- in a match: your match power-ups; in the lobby: your Power-Up Lab picks
		local me = ClientState.GetMe()
		local owned = snapshot.InMatch and (me and me.PowerUps) or snapshot.PowerUps
		ClientState.Owned = owned or {}
		ClientState.Stats = PowerUps.ComputeStats(ClientState.Owned)
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
