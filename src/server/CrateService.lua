--[[
	CrateService.lua  (ServerScriptService.Server.CrateService)

	Crates in the lobby's crate vault (see Config.Crates):
	  * Every player has Keys (the "Keys" attribute on the Player). New
	    players start with Config.Crates.StartingKeys; finishing a match
	    gives KeysPerWin / KeysPerLoss.
	  * Opening a crate (the altar's "Open Crate" prompt, the SHOP, or the
	    reveal screen's OPEN ANOTHER button: the "CrateOpen" remote) costs
	    that crate's price. The server checks you're in the lobby, can pay
	    and aren't spamming, then rolls the rarity (the crate's Odds) and a
	    skin of that rarity.
	  * The result goes to the client over the "Crates" remote, which plays
	    the opening animation (CrateController).
	  * Equipping: the "SkinEquip" remote (the lobby LOCKER) picks one owned
	    skin per weapon. It's saved, shown to everyone (player attributes
	    RifleSkin / KnifeSkin) and the weapons in your hands are rebuilt.
	  * Two crates (Config.Crates.Types): Standard for Keys, Elite for Credits
	    (better odds, the Elite-only skins and the Secrets).
	  * Robux: Credit / Key packs (Developer Products, Config.Shop) are
	    granted in ProcessReceipt, once each (purchase ids are kept in the
	    save) and only reported as granted after the save went through.
	    The VIP pass (2x keys) is checked on join.
	  * Keys, credits, owned skins and equipped skins are saved in a DataStore. In Studio that needs
	    Game Settings > Security > "Enable Studio Access to API Services";
	    without it everything works for the session, it just isn't saved.
]]

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
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

-- [player] = { Keys, Credits, Skins = { [skinId] = count }, Opened, Equipped = { Rifle, Knife }, Receipts = { purchaseId... } }
local data = {}
local loaded = {} -- [player] = true once their save has loaded
local loadFailed = {} -- [player] = true if the DataStore read failed (never overwrite their save)
local lastOpen = {} -- [player] = os.clock()
local dirty = {} -- [player] = true when there are unsaved changes
local rng = Random.new()

-- the skins each crate can drop, by rarity (Elite-only skins only in the Elite crate)
local pools = {} -- [crateType][rarity] = { skins }
for typeName, crateType in pairs(CR.Types) do
	pools[typeName] = {}
	for _, skin in ipairs(CR.Skins) do
		if (crateType.Odds[skin.Rarity] or 0) > 0 and (crateType.EliteSkins or not skin.Elite) then
			pools[typeName][skin.Rarity] = pools[typeName][skin.Rarity] or {}
			table.insert(pools[typeName][skin.Rarity], skin)
		end
	end
end
local rarityById = {}
for _, rarity in ipairs(CR.Rarities) do
	rarityById[rarity.Id] = rarity
end

local function notify(player, text)
	Remotes.Get("Notify"):FireClient(player, text)
end

local function sendInventory(player)
	local d = data[player]
	if d then
		Remotes.Get("Crates"):FireClient(player, { Type = "Inventory", Keys = d.Keys, Credits = d.Credits, Skins = d.Skins, Equipped = d.Equipped })
	end
end

local function setKeys(player, keys)
	local d = data[player]
	d.Keys = math.max(0, math.floor(keys))
	player:SetAttribute("Keys", d.Keys)
	dirty[player] = true
end

-- Keys bought with Robux (part of Keys) can't be wagered; spending keys on
-- crates uses them up first.
local function spendKeys(player, amount)
	local d = data[player]
	d.PaidKeys = math.max(0, (d.PaidKeys or 0) - amount)
	setKeys(player, d.Keys - amount)
	player:SetAttribute("WagerKeys", d.Keys - d.PaidKeys)
end

local function setCredits(player, credits)
	local d = data[player]
	d.Credits = math.max(0, math.floor(credits))
	player:SetAttribute("Credits", d.Credits)
	dirty[player] = true
end

----------------------------------------------------------------------------
-- Saving
----------------------------------------------------------------------------
-- Returns false only if a write was needed and couldn't happen.
local function save(player)
	local d = data[player]
	if loadFailed[player] then
		return false -- (never overwrite a save we couldn't read)
	end
	if not store or not d or not loaded[player] or not dirty[player] then
		return true
	end
	dirty[player] = nil
	local ok, err = pcall(function()
		store:SetAsync("u" .. player.UserId, {
			Keys = d.Keys,
			Credits = d.Credits,
			PaidKeys = d.PaidKeys,
			Skins = d.Skins,
			Opened = d.Opened,
			Equipped = d.Equipped,
			Receipts = d.Receipts,
		})
	end)
	if not ok then
		dirty[player] = true
		warn("[CrateService] save failed for", player.Name, err)
	end
	return ok
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
	local d = { Keys = CR.StartingKeys, PaidKeys = 0, Credits = 0, Skins = {}, Opened = 0, Equipped = {}, Receipts = {} }
	if typeof(saved) == "table" then
		if typeof(saved.Keys) == "number" then
			d.Keys = math.max(0, math.floor(saved.Keys))
		end
		if typeof(saved.Credits) == "number" then
			d.Credits = math.max(0, math.floor(saved.Credits))
		end
		if typeof(saved.PaidKeys) == "number" then
			d.PaidKeys = math.clamp(math.floor(saved.PaidKeys), 0, d.Keys)
		end
		if typeof(saved.Receipts) == "table" then
			for _, id in ipairs(saved.Receipts) do
				if typeof(id) == "string" then
					table.insert(d.Receipts, id)
				end
			end
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
	player:SetAttribute("Credits", d.Credits)
	player:SetAttribute("WagerKeys", d.Keys - d.PaidKeys)
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
-- A rarity by the crate's odds (only rarities it has skins for), then a skin of it.
local function rollSkin(typeName)
	local crateType = CR.Types[typeName]
	local pool = pools[typeName]
	local total = 0
	for _, rarity in ipairs(CR.Rarities) do
		if pool[rarity.Id] then
			total += crateType.Odds[rarity.Id] or 0
		end
	end
	local pick = rng:NextNumber() * total
	for _, rarity in ipairs(CR.Rarities) do
		local list = pool[rarity.Id]
		if list then
			pick -= crateType.Odds[rarity.Id] or 0
			if pick <= 0 then
				return rarity, list[rng:NextInteger(1, #list)]
			end
		end
	end
	local skin = CR.Skins[1]
	return rarityById[skin.Rarity], skin
end

local function isFree()
	return CR.FreeInStudio and RunService:IsStudio()
end

local function canOpen(player, typeName)
	local d = data[player]
	local crateType = CR.Types[typeName]
	if not d then
		return false, "Your crates are still loading"
	end
	if not crateType then
		return false, nil
	end
	if MatchService.GetMatch(player) then
		return false, nil -- in a match: ignore quietly
	end
	if lastOpen[player] and os.clock() - lastOpen[player] < CR.Cooldown then
		return false, nil
	end
	if not isFree() and (d[crateType.Currency] or 0) < crateType.Cost then
		if crateType.Currency == "Keys" then
			return false, ("You need %d keys - win matches to earn more (or get keys in the SHOP)"):format(crateType.Cost)
		end
		return false, ("You need %d credits - get them in the SHOP"):format(crateType.Cost)
	end
	return true
end

-- typeName: "Standard" (keys) or "Elite" (credits)
function CrateService.Open(player, typeName)
	typeName = CR.Types[typeName] and typeName or "Standard"
	local ok, reason = canOpen(player, typeName)
	if not ok then
		if reason then
			notify(player, reason)
		end
		-- lets the reveal screen give the view back straight away
		Remotes.Get("Crates"):FireClient(player, { Type = "Denied", Reason = reason, CrateType = typeName })
		return
	end
	lastOpen[player] = os.clock()
	local d = data[player]
	local crateType = CR.Types[typeName]
	if not isFree() then
		if crateType.Currency == "Credits" then
			setCredits(player, d.Credits - crateType.Cost)
		else
			spendKeys(player, crateType.Cost)
		end
	end
	local rarity, skin = rollSkin(typeName)
	local isNew = (d.Skins[skin.Id] or 0) == 0
	d.Skins[skin.Id] = (d.Skins[skin.Id] or 0) + 1
	d.Opened += 1
	dirty[player] = true
	Remotes.Get("Crates"):FireClient(player, {
		Type = "Result",
		CrateType = typeName,
		Equipped = d.Equipped,
		Rarity = rarity.Id,
		Skin = skin.Id,
		New = isNew,
		Count = d.Skins[skin.Id],
		Keys = d.Keys,
		Credits = d.Credits,
		Free = isFree(),
		CanAgain = isFree() or (d[crateType.Currency] or 0) >= crateType.Cost,
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
-- Robux: credit / key packs (Developer Products) and the VIP pass
----------------------------------------------------------------------------
local products = {} -- [productId] = { Credits = n } or { Keys = n }
for _, pack in ipairs(Config.Shop.CreditPacks) do
	if pack.Id ~= 0 then
		products[pack.Id] = { Credits = pack.Credits }
	end
end
for _, pack in ipairs(Config.Shop.KeyPacks) do
	if pack.Id ~= 0 then
		products[pack.Id] = { Keys = pack.Keys }
	end
end

-- Roblox calls this for every purchase (again and again until we say it's
-- granted, so it must never give the same purchase twice).
local function processReceipt(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	local d = player and data[player]
	local product = products[info.ProductId]
	if not player or not d or not loaded[player] or loadFailed[player] or not product then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- (try again when they're back / loaded)
	end
	if not table.find(d.Receipts, info.PurchaseId) then
		if product.Credits then
			setCredits(player, d.Credits + product.Credits)
		end
		if product.Keys then
			d.PaidKeys = (d.PaidKeys or 0) + product.Keys
			setKeys(player, d.Keys + product.Keys)
			player:SetAttribute("WagerKeys", d.Keys - d.PaidKeys)
		end
		table.insert(d.Receipts, info.PurchaseId)
		while #d.Receipts > 50 do
			table.remove(d.Receipts, 1)
		end
		dirty[player] = true
		notify(player, product.Credits and ("+%d CREDITS"):format(product.Credits) or ("+%d KEYS"):format(product.Keys))
		sendInventory(player)
	end
	-- only tell Roblox it's done once it's saved
	if save(player) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

local function checkVip(player)
	local pass = Config.Shop.Passes.VIP
	if pass.Id == 0 then
		return
	end
	local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.Id)
	if ok and owns then
		player:SetAttribute("VIP", true)
	end
end

----------------------------------------------------------------------------
-- Duel wagers (MatchService): stakes are taken when the duel starts and
-- paid out (or refunded) when it ends
----------------------------------------------------------------------------
-- Keys a player can wager: the ones they earned (bought keys can't be bet).
function CrateService.GetKeys(player)
	local d = data[player]
	return d and loaded[player] and (d.Keys - (d.PaidKeys or 0)) or 0
end

-- Takes `amount` earned keys for a wager; false (and nothing taken) if they don't have them.
function CrateService.TakeKeys(player, amount)
	local d = data[player]
	if not d or not loaded[player] or d.Keys - (d.PaidKeys or 0) < amount then
		return false
	end
	setKeys(player, d.Keys - amount)
	player:SetAttribute("WagerKeys", d.Keys - d.PaidKeys)
	scheduleSave(player)
	return true
end

-- Gives earned keys (wager winnings / refunds).
function CrateService.GiveKeys(player, amount)
	local d = data[player]
	if not d or not player.Parent then
		return false
	end
	setKeys(player, d.Keys + amount)
	player:SetAttribute("WagerKeys", d.Keys - (d.PaidKeys or 0))
	scheduleSave(player)
	return true
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
			if player:GetAttribute("VIP") then
				gain *= 2 -- (the VIP pass)
			end
			if gain > 0 then
				setKeys(player, data[player].Keys + gain)
				player:SetAttribute("WagerKeys", data[player].Keys - (data[player].PaidKeys or 0))
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

	Remotes.Get("CrateOpen").OnServerEvent:Connect(function(player, typeName)
		CrateService.Open(player, typeName)
	end)

	local lobby = MatchService.GetLobby()
	local prompt = lobby and lobby.CrateAltar and lobby.CrateAltar:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Triggered:Connect(function(player)
			CrateService.Open(player, "Standard")
		end)
	end

	MatchService.MatchFinished:Connect(onMatchFinished)

	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, bought)
		if bought and passId == Config.Shop.Passes.VIP.Id then
			player:SetAttribute("VIP", true)
			notify(player, "VIP UNLOCKED  -  2x keys from every match")
		end
	end)
	Players.PlayerAdded:Connect(checkVip)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(checkVip, player)
	end

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
