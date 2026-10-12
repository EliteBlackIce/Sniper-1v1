--[[
	Main  (ServerScriptService.Server.Main)

	Server entry point. Starts every service in order.

	Server layout:
		LightingSetup     lighting + post effects from Config.Lighting
		MapBuilder        builds the lobby and arenas from parts
		CharacterService  spawning, flat styling, freeze, invisibility, void
		SettingsService   saves mouse sensitivity settings (DataStore)
		Match             one 1v1 match: rounds, scoring, power-up picks
		MatchService      lobby, queue, matchmaking
		CombatService     server-side hit validation, damage, abilities
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
Remotes.Init() -- create every RemoteEvent before anything else

local LightingSetup = require(script.Parent.LightingSetup)
local CharacterService = require(script.Parent.CharacterService)
local SettingsService = require(script.Parent.SettingsService)
local MatchService = require(script.Parent.MatchService)
local CombatService = require(script.Parent.CombatService)

LightingSetup.Apply()
CharacterService.Init()
SettingsService.Init()
CombatService.Init()
MatchService.Init()

print("[Sniper Duel] server ready")
