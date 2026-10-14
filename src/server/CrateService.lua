--[[
	CrateService.lua  (ServerScriptService.Server.CrateService)

	Crates in the lobby's crate vault (see Config.Crates):
	  * Every player has Keys (the "Keys" attribute on the Player). New
	    players start with Config.Crates.StartingKeys; finishing a match
	    gives KeysPerWin / KeysPerLoss.
	  * Opening a crate (the altar's "Open Crate" prompt, or the "CrateOpen"
	    remote from the reveal screen's OPEN ANOTHER button) costs a key. The
	    server checks you're in the lobby, near the altar and not spamming,
	    then rolls the rarity (Chance %) and a skin of that rarity.
	  * The result goes to the client over the "Crates" remote, which plays
	    the opening animation (CrateController).
	  * Equipping: the "SkinEquip" remote (the lobby LOCKER) picks one owned
	    skin per weapon. It's saved, shown to everyone (player attributes
	    RifleSkin / KnifeSkin) and the weapons in your hands are rebuilt.
	  * Secret skins will be their own models; until there are any, crates
	    only roll the rarities that have skins.
	  * Keys, owned skins and equipped skins are saved in a DataStore. In Studio that needs
	    Game Settings > Security > "Enable Studio Access to API Services";
	    without it everything works for the session, it just isn't saved.
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Util = require(ReplicatedStorage.Shared.Util)
local Skins = require(ReplicatedStorage.Shared.Skins)

local CrateService = {}

local CR = Config.Crates
local MatchService
local CharacterService

local store
pcall(function()
	store = DataStoreService:GetDataStore("Crates_v1")
end)

local data = {} -- [player] = { Keys = n, Skins = { [skinId] = count }, Opened = n, Equipped = { Rifle = id, Knife = id } }
local loaded = {} -- [player] = true once their save has loaded
local loadFailed = {} -- [player] = true if the DataStore read failed (never overwrite their save)
local lastOpen = {} -- [player] = os.clock()
local dirty = {} -- [player] = true when there are unsaved changes
local rng = Random.new()

local skinsByRarity = {}
for _, skin in ipairs(CR.Skins) do
	skinsByRarity[skin.Rarity] = skinsByRarity[skin.Rarity] or {}
	table.insert(skinsByRarity[skin.Rarity], skin)
end

local function notify(player, text)
	Remotes.Get("Notify"):FireClient(player, text)
end

local function sendInventory(player)
	local d = data[player]
	if d then
		Remotes.Get("Crates"):FireClient(player, { Type = "Inventory", Keys = d.Keys, Skins = d.Skins, Equipped = d.Equipped })
	end
end

local function setKeys(player, keys)
	local d = data[player]
	d.Keys = math.max(0, math.floor(keys))
	player:SetAttribute("Keys", d.Keys)
	dirty[player] = true
end

----------------------------------------------------------------------------
-- Saving
----------------------------------------------------------------------------
local function save(player)
	local d = data[player]
	if not store or not d or not loaded[player] or loadFailed[player] or not dirty[player] then
		return
	end
	dirty[player] = nil
	local ok, err = pcall(function()
		store:SetAsync("u" .. player.UserId, { Keys = d.Keys, Skins = d.Skins, Opened = d.Opened, Equipped = d.Equipped })
	end)
	if not ok then
		dirty[player] = true
		warn("[CrateService] save failed for", player.Name, err)
	end
end

local function load(player)
	local saved
	if store then
		local ok, result
		for attempt = 1, 3 do
			ok, result = pcall(function()
				return store:GetAsync("u" .. player.UserId)
			end)
			if ok then
				break
			end
			task.wait(attempt)
		end
		if ok then
			saved = result
		else
			-- play on defaults for this session, but don't write them over the real save
			loadFailed[player] = true
			warn("[CrateService] couldn't load crates for", player.Name, result)
		end
	end
	if not player.Parent then
		return
	end
	local d = { Keys = CR.StartingKeys, Skins = {}, Opened = 0, Equipped = {} }
	if typeof(saved) == "table" then
		if typeof(saved.Keys) == "number" then
			d.Keys = math.max(0, math.floor(saved.Keys))
		end
		if typeof(saved.Opened) == "number" then
			d.Opened = saved.Opened
		end
		if typeof(saved.Skins) == "table" then
			for id, count in pairs(saved.Skins) do
				if typeof(id) == "string" and typeof(count) == "number" then
					d.Skins[id] = count
				end
			end
		end
	end
	if typeof(saved) == "table" and typeof(saved.Equipped) == "table" then
		for _, weapon in ipairs({ "Rifle", "Knife" }) do
			local id = saved.Equipped[weapon]
			local skin = typeof(id) == "string" and Skins.Get(id)
			if skin and skin.Weapon == weapon and (d.Skins[id] or 0) > 0 then
				d.Equipped[weapon] = id
			end
		end
	end
	data[player] = d
	loaded[player] = true
	player:SetAttribute("Keys", d.Keys)
	player:SetAttribute("RifleSkin", d.Equipped.Rifle)
	player:SetAttribute("KnifeSkin", d.Equipped.Knife)
	if d.Equipped.Rifle or d.Equipped.Knife then
		CharacterService.RefreshSkins(player)
	end
	sendInventory(player)
end

-- One save a few seconds from now (several changes in a row = one write,
-- well inside the DataStore's limits).
local saveScheduled = {} -- [player] = true
local function scheduleSave(player)
	if saveScheduled[player] then
		return
	end
	saveScheduled[player] = true
	task.delay(8, function()
		saveScheduled[player] = nil
		if player.Parent then
			save(player)
		end
	end)
end

----------------------------------------------------------------------------
-- Opening
----------------------------------------------------------------------------
-- (only rarities that have skins: no Secret until its models are in)
local function rollRarity()
	local total = 0
	for _, rarity in ipairs(CR.Rarities) do
		if skinsByRarity[rarity.Id] then
			total += rarity.Chance
		end
	end
	local pick = rng:NextNumber() * total
	for _, rarity in ipairs(CR.Rarities) do
		if skinsByRarity[rarity.Id] then
			pick -= rarity.Chance
			if pick <= 0 then
				return rarity
			end
		end
	end
	return CR.Rarities[1]
end

local function rollSkin()
	-- re-roll the (very unlikely) case of a rarity with no skins
	for _ = 1, 10 do
		local rarity = rollRarity()
		local list = skinsByRarity[rarity.Id]
		if list and #list > 0 then
			return rarity, list[rng:NextInteger(1, #list)]
		end
	end
	local skin = CR.Skins[1]
	for _, rarity in ipairs(CR.Rarities) do
		if rarity.Id == skin.Rarity then
			return rarity, skin
		end
	end
	return CR.Rarities[1], skin
end

local function isFree()
	return CR.FreeInStudio and RunService:IsStudio()
end

local function canOpen(player)
	local d = data[player]
	if not d then
		return false, "Your crates are still loading"
	end
	if MatchService.GetMatch(player) then
		return false, nil -- in a match: ignore quietly
	end
	if lastOpen[player] and os.clock() - lastOpen[player] < CR.Cooldown then
		return false, nil
	end
	local lobby = MatchService.GetLobby()
	local altar = lobby and lobby.CrateAltar
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not altar or not root or (root.Position - altar.Position).Magnitude > CR.MaxDistance then
		return false, "Go to the crate vault to open crates"
	end
	if not isFree() and d.Keys < CR.Cost then
		return false, "No keys left - play matches to earn more"
	end
	return true
end

function CrateService.Open(player)
	local ok, reason = canOpen(player)
	if not ok then
		if reason then
			notify(player, reason)
		end
		-- lets the reveal screen give the view back straight away
		Remotes.Get("Crates"):FireClient(player, { Type = "Denied", Reason = reason })
		return
	end
	lastOpen[player] = os.clock()
	local d = data[player]
	if not isFree() then
		setKeys(player, d.Keys - CR.Cost)
	end
	local rarity, skin = rollSkin()
	local isNew = (d.Skins[skin.Id] or 0) == 0
	d.Skins[skin.Id] = (d.Skins[skin.Id] or 0) + 1
	d.Opened += 1
	dirty[player] = true
	Remotes.Get("Crates"):FireClient(player, {
		Type = "Result",
		Equipped = d.Equipped,
		Rarity = rarity.Id,
		Skin = skin.Id,
		New = isNew,
		Count = d.Skins[skin.Id],
		Keys = d.Keys,
		Free = isFree(),
		Skins = d.Skins,
	})
	scheduleSave(player) -- (opening several in a row = one save)
end

----------------------------------------------------------------------------
-- Equipping
----------------------------------------------------------------------------
-- weapon: "Rifle" / "Knife"; id: an owned skin for it, or nil for the default look
function CrateService.Equip(player, weapon, id)
	local d = data[player]
	if not d or (weapon ~= "Rifle" and weapon ~= "Knife") then
		return
	end
	if id ~= nil then
		local skin = typeof(id) == "string" and Skins.Get(id)
		if not skin or skin.Weapon ~= weapon or (d.Skins[id] or 0) <= 0 then
			return
		end
	end
	if d.Equipped[weapon] == id then
		return
	end
	d.Equipped[weapon] = id
	dirty[player] = true
	player:SetAttribute(weapon .. "Skin", id)
	if not MatchService.GetMatch(player) then
		CharacterService.RefreshSkins(player) -- (in a match: from the next round)
	end
	sendInventory(player)
	scheduleSave(player)
end

----------------------------------------------------------------------------
-- Keys for playing
----------------------------------------------------------------------------
local function onMatchFinished(match)
	local winner = match.MatchWinner
	if not winner or match.Aborted then
		return -- cancelled, or someone left (no keys for forfeits: they could be farmed)
	end
	for _, player in ipairs(match.Players) do
		if not Util.isBot(player) and player.Parent and data[player] then
			local gain = player == winner and CR.KeysPerWin or CR.KeysPerLoss
			if gain > 0 then
				setKeys(player, data[player].Keys + gain)
				notify(player, ("+%d KEY%s  -  open crates in the crate vault"):format(gain, gain == 1 and "" or "S"))
				task.spawn(save, player)
			end
		end
	end
end

function CrateService.Init(matchService, characterService)
	MatchService = matchService
	CharacterService = characterService

	-- equips are applied at most every EQUIP_GAP seconds (each one rebuilds
	-- the weapons); requests in between wait and the latest one wins
	local EQUIP_GAP = 0.6
	local lastEquip, pendingEquip = {}, {}
	local function applyPending(player)
		local pending = pendingEquip[player]
		pendingEquip[player] = nil
		lastEquip[player] = os.clock()
		for weapon, choice in pairs(pending or {}) do
			CrateService.Equip(player, weapon, choice.Id)
		end
	end
	Remotes.Get("SkinEquip").OnServerEvent:Connect(function(player, weapon, id)
		if weapon ~= "Rifle" and weapon ~= "Knife" then
			return
		end
		local waiting = pendingEquip[player] ~= nil
		pendingEquip[player] = pendingEquip[player] or {}
		pendingEquip[player][weapon] = { Id = id }
		if waiting then
			return -- (already scheduled)
		end
		local since = os.clock() - (lastEquip[player] or 0)
		if since >= EQUIP_GAP then
			applyPending(player)
		else
			task.delay(EQUIP_GAP - since, function()
				if player.Parent then
					applyPending(player)
				end
			end)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastEquip[player] = nil
		pendingEquip[player] = nil
		saveScheduled[player] = nil
	end)

	Remotes.Get("CrateOpen").OnServerEvent:Connect(function(player)
		CrateService.Open(player)
	end)

	local lobby = MatchService.GetLobby()
	local prompt = lobby and lobby.CrateAltar and lobby.CrateAltar:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Triggered:Connect(function(player)
			CrateService.Open(player)
		end)
	end

	MatchService.MatchFinished:Connect(onMatchFinished)

	Players.PlayerAdded:Connect(load)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(load, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		save(player)
		data[player] = nil
		loaded[player] = nil
		loadFailed[player] = nil
		lastOpen[player] = nil
		dirty[player] = nil
	end)
	game:BindToClose(function()
		local pending = 0
		for _, player in ipairs(Players:GetPlayers()) do
			pending += 1
			task.spawn(function()
				save(player)
				pending -= 1
			end)
		end
		local waited = 0
		while pending > 0 and waited < 25 do
			waited += task.wait(0.2)
		end
	end)
end

return CrateService
