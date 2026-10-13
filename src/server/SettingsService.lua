--[[
	SettingsService.lua  (ServerScriptService.Server.SettingsService)

	Saves each player's settings (mouse sensitivity, scoped sensitivity,
	hold/toggle scope) in a DataStore so they persist between sessions.

	In Studio, DataStores only work if you enable:
	Game Settings > Security > "Enable Studio Access to API Services".
	If they're disabled, settings still work for the session, they just
	won't be saved.
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local SettingsService = {}

local store
pcall(function()
	store = DataStoreService:GetDataStore("PlayerSettings_v1")
end)

local lastSave = {}

-- Only accept known keys with sane values from the client.
local function sanitize(data)
	local clean = table.clone(Config.SettingsDefaults)
	if typeof(data) ~= "table" then
		return clean
	end
	for key, limits in pairs(Config.SettingsLimits) do
		local value = data[key]
		if typeof(value) == "number" and value == value then
			clean[key] = math.clamp(value, limits.Min, limits.Max)
		end
	end
	if typeof(data.ToggleScope) == "boolean" then
		clean.ToggleScope = data.ToggleScope
	end
	if typeof(data.AimAssist) == "boolean" then
		clean.AimAssist = data.AimAssist
	end
	return clean
end

local function load(player)
	local data
	if store then
		local ok, result = pcall(function()
			return store:GetAsync("u" .. player.UserId)
		end)
		if ok then
			data = result
		end
	end
	Remotes.Get("SettingsLoad"):FireClient(player, sanitize(data))
end

function SettingsService.Init()
	Players.PlayerAdded:Connect(load)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(load, player)
	end

	Remotes.Get("SettingsSave").OnServerEvent:Connect(function(player, data)
		-- simple rate limit: one save every 3 seconds per player
		local now = os.clock()
		if lastSave[player] and now - lastSave[player] < 3 then
			return
		end
		lastSave[player] = now
		if not store then
			return
		end
		local clean = sanitize(data)
		task.spawn(function()
			pcall(function()
				store:SetAsync("u" .. player.UserId, clean)
			end)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastSave[player] = nil
	end)
end

return SettingsService
