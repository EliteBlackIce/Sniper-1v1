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
		BotService        computer opponent for admin "/bot" matches
		CrateService      crate keys, opening (server-side rolls), owned skins (DataStore)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
Remotes.Init() -- create every RemoteEvent before anything else

-- The imported rifle (Studio's 3D Importer drops it in the Workspace):
-- keep it in ReplicatedStorage where the server and every client can clone it.
local Config = require(ReplicatedStorage.Shared.Config)
local rifleName = Config.Viewmodel.MeshTemplate or "SniperRifle"
local importedRifle = workspace:FindFirstChild(rifleName)
if importedRifle and not ReplicatedStorage:FindFirstChild(rifleName) then
	importedRifle.Parent = ReplicatedStorage
end
local knifeName = Config.Knife.MeshTemplate or "CombatKnife" -- same for the imported knife
local importedKnife = workspace:FindFirstChild(knifeName)
if importedKnife and not ReplicatedStorage:FindFirstChild(knifeName) then
	importedKnife.Parent = ReplicatedStorage
end

local LightingSetup = require(script.Parent.LightingSetup)
local CharacterService = require(script.Parent.CharacterService)
local SettingsService = require(script.Parent.SettingsService)
local MatchService = require(script.Parent.MatchService)
local CombatService = require(script.Parent.CombatService)
local BotService = require(script.Parent.BotService)
local CrateService = require(script.Parent.CrateService)

LightingSetup.Apply()
CharacterService.Init()
SettingsService.Init()
CombatService.Init()
BotService.Init(CombatService)
MatchService.Init()
CrateService.Init(MatchService)

print("[Sniper Duel] server ready")
