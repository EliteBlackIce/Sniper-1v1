--[[
	Shop.lua  (Client.ui.Shop)

	The SHOP (lobby, key M or the SHOP button):
		CRATES    the Standard crate (Keys, earned by playing) and the Elite
		          crate (Credits: better odds, Elite-only skins, Secrets).
		          OPEN plays the opening at the crate vault.
		FEATURED  three skins a day to buy outright with Credits
		CREDITS   Credit packs (and a Key pack) for Robux
		VIP       the VIP pass (2x keys)
	Purchases are Roblox prompts; the server grants them (CrateService).
	Product ids live in Config.Shop (0 = not set up yet).
]]

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local ClientState = require(script.Parent.Parent.ClientState)
local Sfx = require(script.Parent.Parent.Sfx)
local Keybinds = require(script.Parent.Parent.Keybinds)
local Theme = require(script.Parent.Theme)

local Palette = Config.Palette
local CR = Config.Crates
local SHOP = Config.Shop
local player = Players.LocalPlayer

local Shop = {}

local W, H = 920, 580
local GOLD = Color3.fromRGB(255, 196, 60)
local gui, panel, unlocker, pages, tabs, balance
local isOpen = false
local current = "Crates"

local rarityById = {}
for _, rarity in ipairs(CR.Rarities) do
	rarityById[rarity.Id] = rarity
end

local function notSetUp()
	Sfx.Play("CardHover", { Pitch = 0.6 })
	local note = panel:FindFirstChild("Note")
	if note then
		note.Text = "This item isn't set up yet: add its id in Config.Shop (Creator Hub > Monetization)."
		note.TextTransparency = 0
		task.delay(3, function()
			Theme.tween(note, 0.4, { TextTransparency = 1 })
		end)
	end
end

local function refreshBalance()
	if balance then
		balance.Text = ("%d KEYS    %d CREDITS%s"):format(
			player:GetAttribute("Keys") or 0,
			player:GetAttribute("Credits") or 0,
			player:GetAttribute("VIP") and "    VIP" or ""
		)
	end
end

----------------------------------------------------------------------------
-- Pages
----------------------------------------------------------------------------
local function card(parent, props)
	local frame = Theme.new("Frame", {
		BackgroundColor3 = Palette.UIPanelLight,
		Position = props.Position,
		Size = props.Size,
		Parent = parent,
	})
	Theme.corner(frame, 14)
	Theme.stroke(frame, props.Color or Palette.UIText, props.Color and 2 or 1, props.Color and 0.2 or 0.85)
	Theme.padding(frame, 16)
	return frame
end

local function oddsLines(odds)
	local lines = {}
	for _, rarity in ipairs(CR.Rarities) do
		local chance = odds[rarity.Id]
		if chance and chance > 0 then
			table.insert(lines, ('<font color="#%s">%s</font>  %s%%'):format(rarity.Color:ToHex(), rarity.Name, tostring(chance)))
		end
	end
	return table.concat(lines, "\n")
end

local function crateCard(parent, typeName, x, color, blurb)
	local crateType = CR.Types[typeName]
	local frame = card(parent, {
		Position = UDim2.new(x, x > 0 and 8 or 0, 0, 0),
		Size = UDim2.new(0.5, -8, 1, 0),
		Color = color,
	})
	Theme.label({
		Size = UDim2.new(1, 0, 0, 34),
		Text = crateType.Name,
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = color,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = frame,
	})
	Theme.label({
		Position = UDim2.fromOffset(0, 38),
		Size = UDim2.new(1, 0, 0, 40),
		Text = blurb,
		TextSize = 14,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Palette.UISubText,
		FontFace = Theme.Font(Enum.FontWeight.Medium),
		Parent = frame,
	})
	Theme.label({
		Position = UDim2.fromOffset(0, 90),
		Size = UDim2.new(1, 0, 0, 150),
		RichText = true,
		Text = oddsLines(crateType.Odds),
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		LineHeight = 1.25,
		Parent = frame,
	})
	local open = Theme.button({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 52),
		Text = ("OPEN  -  %d %s"):format(crateType.Cost, string.upper(crateType.Currency)),
		TextSize = 20,
		BackgroundColor3 = color,
		Parent = frame,
	})
	open.Activated:Connect(function()
		local have = player:GetAttribute(crateType.Currency) or 0
		local free = CR.FreeInStudio and RunService:IsStudio()
		if not free and have < crateType.Cost then
			Sfx.Play("CardHover", { Pitch = 0.6 })
			if crateType.Currency == "Credits" then
				Shop.Show("Credits") -- (get some credits first)
			end
			return
		end
		Sfx.Play("CardPick", { Pitch = 1.1 })
		Shop.Close()
		Remotes.Get("CrateOpen"):FireServer(typeName)
	end)
end

local function buildCrates(page)
	crateCard(page, "Standard", 0, Palette.UIAccent,
		("Earn keys by playing: %d for a win, %d for a loss. Every rarity up to Legendary."):format(CR.KeysPerWin, CR.KeysPerLoss))
	local elite = {}
	for _, skin in ipairs(CR.Skins) do
		if skin.Elite and skin.Rarity ~= "Secret" and #elite < 6 then
			table.insert(elite, skin.Name)
		end
	end
	crateCard(page, "Elite", 0.5, GOLD,
		"Rare and up only, and the only crate with Elite-only skins (" .. table.concat(elite, ", ") .. "...) and the SECRETS.")
end

-- FEATURED: today's skins to buy outright with Credits
local featuredPage
local function buildFeatured()
	local page = featuredPage
	for _, child in ipairs(page:GetChildren()) do
		child:Destroy()
	end
	local Skins = require(Shared.Skins)
	local ids = ClientState.Featured or {}
	local count = math.max(#ids, 1)
	for i, id in ipairs(ids) do
		local skin = Skins.Get(id)
		if skin then
			local rarity = rarityById[skin.Rarity]
			local frame = card(page, {
				Position = UDim2.new((i - 1) / count, 6, 0, 0),
				Size = UDim2.new(1 / count, -12, 1, 0),
				Color = rarity and rarity.Color,
			})
			Theme.label({
				Size = UDim2.new(1, 0, 0, 18),
				Text = (rarity and rarity.Name or "") .. "  -  " .. string.upper(skin.Weapon),
				TextSize = 13,
				TextColor3 = rarity and rarity.Color or Palette.UIText,
				Parent = frame,
			})
			Theme.label({
				Position = UDim2.fromOffset(0, 26),
				Size = UDim2.new(1, 0, 0, 34),
				Text = string.upper(skin.Name),
				TextSize = 26,
				TextScaled = false,
				FontFace = Theme.Font(Enum.FontWeight.Heavy),
				Parent = frame,
			})
			for k, color in ipairs({ skin.Body, skin.Blade or skin.Metal, skin.Accent }) do
				local swatch = Theme.new("Frame", {
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, (k - 2) * 46, 0, 84),
					Size = UDim2.fromOffset(38, 38),
					BackgroundColor3 = color,
					Parent = frame,
				})
				Theme.corner(swatch, 19)
			end
			Theme.label({
				Position = UDim2.fromOffset(0, 140),
				Size = UDim2.new(1, 0, 0, 20),
				Text = (skin.Finish and string.upper(skin.Finish) .. " FINISH" or "") .. (skin.Glow and "  +  GLOW" or ""),
				TextSize = 13,
				TextColor3 = Palette.UISubText,
				Parent = frame,
			})
			local price = Config.Featured.Prices[skin.Rarity] or 0
			local have = (ClientState.OwnedSkins[id] or 0) > 0
			local button = Theme.button({
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.new(1, 0, 0, 44),
				Text = have and "OWNED" or ("BUY  -  %d CREDITS"):format(price),
				TextSize = 16,
				BackgroundColor3 = have and Palette.UIPanel or GOLD,
				AutoButtonColor = not have,
				Parent = frame,
			})
			button.Activated:Connect(function()
				if have then
					return
				end
				if (player:GetAttribute("Credits") or 0) < price then
					Sfx.Play("CardHover", { Pitch = 0.6 })
					Shop.Show("Credits")
					return
				end
				Sfx.Play("CardPick", { Pitch = 1.2 })
				Remotes.Get("ShopBuy"):FireServer("Featured", id)
			end)
		end
	end
	Theme.label({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 28),
		Size = UDim2.new(1, 0, 0, 20),
		Text = "New featured skins every day.",
		TextSize = 13,
		TextColor3 = Palette.UISubText,
		Parent = page,
	})
end

local function buyButton(parent, text, price, onBuy)
	local button = Theme.button({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 44),
		Text = ("%s  -  R$ %d"):format(text, price),
		TextSize = 17,
		BackgroundColor3 = GOLD,
		Parent = parent,
	})
	button.Activated:Connect(onBuy)
	return button
end

local function buildCredits(page)
	local packs = {}
	for _, pack in ipairs(SHOP.CreditPacks) do
		table.insert(packs, { Pack = pack, Amount = pack.Credits, Unit = "CREDITS" })
	end
	-- (in countries where paid random items aren't allowed, keys can't be
	-- bought: crates are then earn-only)
	if not player:GetAttribute("PaidRandomBlocked") then
		for _, pack in ipairs(SHOP.KeyPacks) do
			table.insert(packs, { Pack = pack, Amount = pack.Keys, Unit = "KEYS" })
		end
	end
	local count = #packs
	for i, entry in ipairs(packs) do
		local pack = entry.Pack
		local frame = card(page, {
			Position = UDim2.new((i - 1) / count, 6, 0, 0),
			Size = UDim2.new(1 / count, -12, 1, 0),
			Color = entry.Unit == "KEYS" and Palette.UIAccent or GOLD,
		})
		Theme.label({
			Size = UDim2.new(1, 0, 0, 22),
			Text = pack.Name,
			TextSize = 15,
			TextColor3 = Palette.UISubText,
			Parent = frame,
		})
		Theme.label({
			Position = UDim2.fromOffset(0, 40),
			Size = UDim2.new(1, 0, 0, 60),
			Text = tostring(entry.Amount),
			TextSize = 52,
			TextColor3 = entry.Unit == "KEYS" and Palette.UIAccent or GOLD,
			FontFace = Theme.Font(Enum.FontWeight.Heavy),
			Parent = frame,
		})
		Theme.label({
			Position = UDim2.fromOffset(0, 100),
			Size = UDim2.new(1, 0, 0, 20),
			Text = entry.Unit,
			TextSize = 15,
			Parent = frame,
		})
		if pack.Tag then
			local tag = Theme.label({
				Position = UDim2.fromOffset(0, 140),
				Size = UDim2.new(1, 0, 0, 26),
				Text = pack.Tag,
				TextSize = 14,
				TextColor3 = Palette.UIBackground,
				BackgroundColor3 = GOLD,
				BackgroundTransparency = 0,
				Parent = frame,
			})
			Theme.corner(tag, 8)
		end
		buyButton(frame, "BUY", pack.Robux, function()
			if pack.Id == 0 then
				notSetUp()
				return
			end
			MarketplaceService:PromptProductPurchase(player, pack.Id)
		end)
	end
end

local function buildVip(page)
	local pass = SHOP.Passes.VIP
	local frame = card(page, {
		Position = UDim2.fromScale(0.2, 0),
		Size = UDim2.fromScale(0.6, 1),
		Color = GOLD,
	})
	Theme.label({
		Size = UDim2.new(1, 0, 0, 60),
		Text = "VIP",
		TextSize = 56,
		TextColor3 = GOLD,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = frame,
	})
	Theme.label({
		Position = UDim2.fromOffset(0, 80),
		Size = UDim2.new(1, 0, 0, 120),
		Text = pass.Perks,
		TextSize = 20,
		TextWrapped = true,
		FontFace = Theme.Font(Enum.FontWeight.Medium),
		Parent = frame,
	})
	local button = buyButton(frame, "GET VIP", pass.Robux, function()
		if player:GetAttribute("VIP") then
			return
		end
		if pass.Id == 0 then
			notSetUp()
			return
		end
		MarketplaceService:PromptGamePassPurchase(player, pass.Id)
	end)
	local function refresh()
		if player:GetAttribute("VIP") then
			button.Text = "OWNED"
			button.AutoButtonColor = false
		end
	end
	refresh()
	player:GetAttributeChangedSignal("VIP"):Connect(refresh)
end

----------------------------------------------------------------------------
-- Open / close
----------------------------------------------------------------------------
function Shop.Show(name)
	current = name
	for pageName, page in pairs(pages) do
		page.Visible = pageName == name
	end
	for tabName, button in pairs(tabs) do
		local on = tabName == name
		button.BackgroundColor3 = on and Palette.UIAccent or Palette.UIPanelLight
		button.TextColor3 = on and Palette.UIBackground or Palette.UIText
	end
end

function Shop.Open(page)
	if ClientState.InMatch() or (ClientState.MenuOpen and not isOpen) then
		return
	end
	if not isOpen then
		isOpen = true
		gui.Enabled = true
		unlocker.Visible = true
		ClientState.SetMenu("Shop", true)
		panel.Size = UDim2.fromOffset(W - 40, H - 40)
		Theme.tween(panel, 0.2, { Size = UDim2.fromOffset(W, H) }, Enum.EasingStyle.Back)
		Sfx.Play("CardPick", { Pitch = 1.05, Volume = 0.6 })
	end
	refreshBalance()
	Shop.Show(page or current)
end

function Shop.Close()
	if not isOpen then
		return
	end
	isOpen = false
	gui.Enabled = false
	unlocker.Visible = false
	ClientState.SetMenu("Shop", false)
end

function Shop.Toggle()
	if isOpen then
		Shop.Close()
	else
		Shop.Open()
	end
end

function Shop.IsOpen()
	return isOpen
end

function Shop.Init() end

function Shop.Start(playerGui)
	gui = Theme.screen("Shop", 9, playerGui)
	gui.Enabled = false
	Theme.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Palette.UIBackground,
		BackgroundTransparency = 0.35,
		Parent = gui,
	})
	unlocker = Theme.mouseUnlocker(gui)
	panel = Theme.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(W, H),
		BackgroundTransparency = 0,
		Parent = gui,
	})
	Theme.padding(panel, 20)
	local scale = Theme.new("UIScale", { Parent = panel })
	local function fit()
		local view = workspace.CurrentCamera.ViewportSize
		scale.Scale = math.min(1, (view.X - 40) / W, (view.Y - 40) / H)
	end
	fit()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)

	Theme.label({
		Size = UDim2.new(0.4, 0, 0, 34),
		Text = "SHOP",
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = panel,
	})
	balance = Theme.label({
		Position = UDim2.fromOffset(0, 36),
		Size = UDim2.new(0.6, 0, 0, 20),
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = GOLD,
		Parent = panel,
	})
	tabs = {}
	local names = { "Crates", "Featured", "Credits", "VIP" }
	for i, name in ipairs(names) do
		local button = Theme.button({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -(#names - i) * 128, 0, 4),
			Size = UDim2.fromOffset(120, 36),
			Text = string.upper(name),
			TextSize = 16,
			Parent = panel,
		})
		button.Activated:Connect(function()
			Sfx.Play("CardHover", { Pitch = 1.2 })
			Shop.Show(name)
		end)
		tabs[name] = button
	end
	pages = {}
	for _, name in ipairs(names) do
		pages[name] = Theme.new("Frame", {
			Position = UDim2.fromOffset(0, 72),
			Size = UDim2.new(1, 0, 1, -130),
			BackgroundTransparency = 1,
			Visible = false,
			Parent = panel,
		})
	end
	buildCrates(pages.Crates)
	featuredPage = pages.Featured
	buildFeatured()
	ClientState.SkinsChanged:Connect(buildFeatured) -- (owned / today's list changed)
	buildCredits(pages.Credits)
	player:GetAttributeChangedSignal("PaidRandomBlocked"):Connect(function()
		for _, child in ipairs(pages.Credits:GetChildren()) do
			child:Destroy()
		end
		buildCredits(pages.Credits)
	end)
	buildVip(pages.VIP)

	Theme.label({
		Name = "Note",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -8),
		Size = UDim2.new(1, -180, 0, 32),
		Text = "",
		TextSize = 13,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Palette.UISubText,
		Parent = panel,
	})
	local done = Theme.button({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromOffset(160, 42),
		Text = "DONE",
		TextSize = 18,
		Parent = panel,
	})
	done.Activated:Connect(Shop.Close)
	Shop.Show("Crates")

	for _, name in ipairs({ "Keys", "Credits", "VIP" }) do
		player:GetAttributeChangedSignal(name):Connect(refreshBalance)
	end
	ClientState.Changed:Connect(function(snapshot)
		if snapshot.InMatch then
			Shop.Close()
		end
	end)

	local function onActionInput(input, processed)
		if processed and UserInputService:GetFocusedTextBox() then
			return
		end
		if require(script.Parent.SettingsMenu).IsOpen() then
			return
		end
		if Keybinds.Matches("Shop", input) then
			if isOpen then
				Shop.Close()
			elseif not ClientState.InMatch() then
				Shop.Open()
			end
		end
	end
	UserInputService.InputBegan:Connect(onActionInput)
	Keybinds.VirtualBegan:Connect(onActionInput)
end

return Shop
