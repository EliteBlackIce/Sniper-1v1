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
local pendingSave = {} -- [player] = the latest settings that arrived inside the rate-limit window
local MAX_BINDS = 64 -- per device (there are ~25 actions)

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
	if typeof(data.InvertY) == "boolean" then
		clean.InvertY = data.InvertY
	end
	-- key binds: { Keyboard = { Action = "KeyName" }, Gamepad = { ... } }
	if typeof(data.Binds) == "table" then
		local binds = {}
		for _, device in ipairs({ "Keyboard", "Gamepad" }) do
			local list = data.Binds[device]
			if typeof(list) == "table" then
				binds[device] = {}
				local count = 0
				for action, key in pairs(list) do
					if count >= MAX_BINDS then
						break -- (no padding the save with junk entries)
					end
					if typeof(action) == "string" and typeof(key) == "string" and #action <= 32 and #key <= 32 then
						if key:match("^%w+$") and action:match("^%w+$") then
							binds[device][action] = key
							count += 1
						end
					end
				end
			end
		end
		clean.Binds = binds
	end
	return clean
end

local function load(player)
	local data
	if store then
		-- a few tries: a failed load would send defaults, and the player's
		-- next save would then overwrite their real settings with them
		for attempt = 1, 3 do
			local ok, result = pcall(function()
				return store:GetAsync("u" .. player.UserId)
			end)
			if ok then
				data = result
				break
			end
			warn("[Settings] load failed for", player.Name, result)
			if attempt < 3 then
				task.wait(attempt * 2)
			end
			if not player.Parent then
				return
			end
		end
	end
	Remotes.Get("SettingsLoad"):FireClient(player, sanitize(data))
end

local function save(player, data)
	local clean = sanitize(data)
	task.spawn(function()
		local ok, err = pcall(function()
			store:SetAsync("u" .. player.UserId, clean)
		end)
		if not ok then
			warn("[Settings] save failed for", player.Name, err)
		end
	end)
end

function SettingsService.Init()
	Players.PlayerAdded:Connect(load)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(load, player)
	end

	Remotes.Get("SettingsSave").OnServerEvent:Connect(function(player, data)
		-- simple rate limit: one save every 3 seconds per player
		-- (a save inside the window isn't dropped: the latest one is written
		-- when the window ends, so the last change always sticks)
		if not store or typeof(data) ~= "table" then
			return
		end
		local now = os.clock()
		if lastSave[player] and now - lastSave[player] < 3 then
			local waiting = pendingSave[player] ~= nil
			pendingSave[player] = data
			if not waiting then
				task.delay(3 - (now - lastSave[player]), function()
					local latest = pendingSave[player]
					pendingSave[player] = nil
					if latest ~= nil and player.Parent then
						lastSave[player] = os.clock()
						save(player, latest)
					end
				end)
			end
			return
		end
		lastSave[player] = now
		save(player, data)
	end)

	Players.PlayerRemoving:Connect(function(player)
		-- a change still waiting out the rate limit is saved now
		local latest = pendingSave[player]
		pendingSave[player] = nil
		lastSave[player] = nil
		if latest ~= nil and store then
			save(player, latest)
		end
	end)
end

return SettingsService
