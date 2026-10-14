--[[
	Locker.lua  (Client.ui.Locker)

	Your skins. In the lobby press L (or the LOCKER button) to open it:
		* RIFLE / KNIFE tabs
		* every skin for that weapon: the ones you own in full colour, the
		  rest locked (open crates to get them)
		* the selected skin spins in a 3D preview; EQUIP puts it in your
		  hands (everyone sees it), DEFAULT goes back to the stock look
	The server checks you own a skin before equipping it (CrateService).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local GunModel = require(Shared.GunModel)
local KnifeModel = require(Shared.KnifeModel)
local Skins = require(Shared.Skins)
local Cosmetics = require(Shared.Cosmetics)
local ClientState = require(script.Parent.Parent.ClientState)
local Sfx = require(script.Parent.Parent.Sfx)
local Keybinds = require(script.Parent.Parent.Keybinds)
local Theme = require(script.Parent.Theme)

local Palette = Config.Palette
local CR = Config.Crates
local player = Players.LocalPlayer

local Locker = {}

local W, H = 900, 560
local gui, panel, unlocker, grid, tabs, viewport, worldModel, previewCam
local nameLabel, rarityLabel, statusLabel, equipButton, defaultButton
local isOpen = false
local weapon = "Rifle" -- the open tab
local selected -- skin id (nil = default) shown in the preview
local owned = ClientState.OwnedSkins -- { [id] = count }
local equipped = {} -- { Rifle = id, Knife = id, Tracer = id, ... } (your attributes)
local cosmeticPreview, cosmeticBar, cosmeticText -- the preview for tracers / effects / poses / titles

-- the tabs: two weapons, then the cosmetic kinds (Cosmetics.Kinds)
local TABS = { "Rifle", "Knife", "Tracer", "KillFx", "Pose", "Title" }
local TAB_NAMES = { Rifle = "RIFLE", Knife = "KNIFE", Tracer = "TRACER", KillFx = "KILL FX", Pose = "POSE", Title = "TITLE" }
local ATTRIBUTE = { Rifle = "RifleSkin", Knife = "KnifeSkin", Tracer = "Tracer", KillFx = "KillFx", Pose = "Pose", Title = "Title" }
local DESCRIBE = {
	Tracer = "The colour of your bullet trails. Everyone sees it.",
	KillFx = "What happens to the body when you get a kill.",
	Pose = "Your pose when the kill cam cuts to you after a win.",
	Title = "Shown under your name, over your head.",
}

local function isSkinTab()
	return weapon == "Rifle" or weapon == "Knife"
end

local function itemOf(id)
	if isSkinTab() then
		return Skins.Get(id)
	end
	return Cosmetics.Get(id)
end

local function owns(item)
	if not item then
		return true -- (the default)
	end
	if isSkinTab() then
		return (owned[item.Id] or 0) > 0
	end
	return item.Default == true or ClientState.OwnedCosmetics[item.Id] == true
end
local waiting -- { Weapon, Id }: an equip sent to the server, not confirmed yet
local tiles = {} -- [skin id or "Default"] = { Frame, Stroke, Tag }
local preview -- { Model, Built, IsKnife, Scale }
local spin = 0

local rarityOf, tierOf = {}, {}
for i, rarity in ipairs(CR.Rarities) do
	rarityOf[rarity.Id] = rarity
	tierOf[rarity.Id] = i
end

----------------------------------------------------------------------------
-- 3D preview
----------------------------------------------------------------------------
local function buildPreview()
	if preview then
		preview.Model:Destroy()
		preview = nil
	end
	viewport.Visible = isSkinTab()
	cosmeticPreview.Visible = not isSkinTab()
	if not isSkinTab() then
		local item = itemOf(selected) or Cosmetics.Default(weapon)
		cosmeticText.Text = weapon == "Title" and (item and item.Text ~= "" and item.Text or "(NO TITLE)") or string.upper(item and item.Name or "")
		cosmeticText.TextColor3 = item and item.Color or Palette.UIText
		cosmeticBar.Visible = weapon == "Tracer" or weapon == "KillFx"
		cosmeticBar.BackgroundColor3 = item and item.Color or Palette.Tracer
		cosmeticPreview.Description.Text = DESCRIBE[weapon] or ""
		return
	end
	local model = Instance.new("Model")
	local isKnife = weapon == "Knife"
	local scale = isKnife and 2.2 or 1
	local built = Skins.Build(weapon, model, Skins.Get(selected), { Scale = scale, Anchored = true, Effects = false })
	model.Parent = worldModel
	preview = { Model = model, Built = built, IsKnife = isKnife, Scale = scale }
end

local function placePreview(dt)
	if not preview then
		return
	end
	spin += dt * 0.6
	local cf = CFrame.Angles(0, math.pi / 2 + math.sin(spin) * 0.6, 0) * CFrame.Angles(0, 0, math.rad(4))
	if preview.IsKnife then
		KnifeModel.Place(preview.Built, cf * CFrame.new(0, 0, 0.47 * preview.Scale))
	else
		GunModel.Place(preview.Built, cf * CFrame.new(0, 0, 1.4), 1)
	end
	-- a slow pulse for Legendary glow (the game does this for real weapons)
	local skin = Skins.Get(selected)
	if skin and skin.Pulse then
		local k = (math.sin(os.clock() * 3) + 1) / 2
		for _, part in ipairs(preview.Model:GetDescendants()) do
			if part:IsA("BasePart") and part:GetAttribute("PulseA") then
				part.Color = part:GetAttribute("PulseA"):Lerp(part:GetAttribute("PulseB"), k)
			end
		end
	end
end

----------------------------------------------------------------------------
-- Tiles + details
----------------------------------------------------------------------------
local function skinsForTab()
	local list = isSkinTab() and Skins.ForWeapon(weapon) or {}
	if not isSkinTab() then
		for _, item in ipairs(Cosmetics.ForKind(weapon)) do
			if not item.Default then
				table.insert(list, item)
			end
		end
	end
	table.sort(list, function(a, b)
		local ta, tb = tierOf[a.Rarity] or 0, tierOf[b.Rarity] or 0
		if ta ~= tb then
			return ta < tb
		end
		return a.Name < b.Name
	end)
	return list
end

local function refreshDetails()
	local skin = itemOf(selected)
	local rarity = skin and rarityOf[skin.Rarity]
	local default = not isSkinTab() and Cosmetics.Default(weapon)
	nameLabel.Text = skin and string.upper(skin.Name) or (default and string.upper(default.Name) or "STANDARD ISSUE")
	rarityLabel.Text = rarity and rarity.Name or "DEFAULT"
	rarityLabel.TextColor3 = rarity and rarity.Color or Palette.UISubText
	local count = skin and (owns(skin) and math.max(owned[skin.Id] or 0, 1) or 0) or 0
	local isEquipped = equipped[weapon] == selected
	local isWaiting = waiting ~= nil and waiting.Weapon == weapon and waiting.Id == selected
	if isWaiting and not isEquipped then
		statusLabel.Text = "EQUIPPING..."
		statusLabel.TextColor3 = Palette.UISubText
	elseif isEquipped then
		statusLabel.Text = "EQUIPPED"
		statusLabel.TextColor3 = Palette.UIAccent
	elseif skin and count <= 0 then
		if not isSkinTab() then
			statusLabel.Text = skin.RankMin and ("LOCKED  -  REACH %d RATING IN RANKED"):format(skin.RankMin) or "LOCKED  -  BUY IT WHEN IT'S FEATURED IN THE SHOP"
		else
			statusLabel.Text = skin.Elite and "LOCKED  -  ONLY IN THE ELITE CRATE" or "LOCKED  -  OPEN CRATES (SHOP OR CRATE VAULT)"
		end
		statusLabel.TextColor3 = Palette.UISubText
	else
		statusLabel.Text = skin and (count > 1 and ("OWNED  x%d"):format(count) or "OWNED") or "ALWAYS AVAILABLE"
		statusLabel.TextColor3 = Palette.UIText
	end
	local canEquip = not isEquipped and (not skin or count > 0)
	equipButton.Text = isEquipped and "EQUIPPED" or (canEquip and "EQUIP" or "LOCKED")
	equipButton.AutoButtonColor = canEquip
	equipButton.BackgroundColor3 = canEquip and Palette.UIAccent or Palette.UIPanelLight
	equipButton.TextColor3 = canEquip and Palette.UIBackground or Palette.UISubText
end

local function refreshTiles()
	for id, tile in pairs(tiles) do
		local skinId = id ~= "Default" and id or nil
		local skin = itemOf(skinId)
		local have = owns(skin)
		local isEquipped = equipped[weapon] == skinId
		local isSelected = selected == skinId
		tile.Frame.BackgroundColor3 = isSelected and Palette.UIPanelLight or Palette.UIPanel
		tile.Stroke.Thickness = isSelected and 3 or 1
		tile.Stroke.Transparency = (isSelected or isEquipped) and 0 or 0.55
		tile.Tag.Text = isEquipped and "EQUIPPED" or (have and "" or "LOCKED")
		tile.Tag.TextColor3 = isEquipped and Palette.UIAccent or Palette.UISubText
		for _, swatch in ipairs(tile.Swatches) do
			swatch.BackgroundTransparency = have and 0 or 0.75
		end
		tile.Name.TextTransparency = have and 0 or 0.45
	end
	refreshDetails()
end

local function select(id)
	if selected == id and preview then
		return
	end
	selected = id
	buildPreview()
	refreshTiles()
end

local function makeTile(skin, order)
	local id = skin and skin.Id or "Default"
	local rarity = skin and rarityOf[skin.Rarity]
	local color = rarity and rarity.Color or Palette.UISubText
	local frame = Theme.new("TextButton", {
		Name = id,
		Text = "",
		AutoButtonColor = true,
		BackgroundColor3 = Palette.UIPanel,
		LayoutOrder = order,
		Parent = grid,
	})
	Theme.corner(frame, 10)
	local stroke = Theme.stroke(frame, color, 1, 0.55)
	-- rarity stripe on the left
	Theme.new("Frame", {
		Size = UDim2.new(0, 4, 1, -16),
		Position = UDim2.fromOffset(6, 8),
		BackgroundColor3 = color,
		Parent = frame,
	})
	-- colour swatches
	local swatches = {}
	local colors
	if not isSkinTab() then
		local item = skin or Cosmetics.Default(weapon)
		colors = { item and item.Color or Palette.UISubText }
	else
		colors = skin and { skin.Body, skin.Weapon == "Knife" and (skin.Blade or skin.Metal) or skin.Metal, skin.Accent }
			or { Color3.fromRGB(190, 164, 120), Color3.fromRGB(58, 60, 60), Color3.fromRGB(84, 86, 90) }
		if weapon == "Knife" and not skin then
			colors = { Color3.fromRGB(34, 36, 40), Color3.fromRGB(176, 182, 190), Color3.fromRGB(70, 74, 82) }
		end
	end
	for i, c in ipairs(colors) do
		local swatch = Theme.new("Frame", {
			Position = UDim2.fromOffset(18 + (i - 1) * 16, 10),
			Size = UDim2.fromOffset(13, 13),
			BackgroundColor3 = c,
			Parent = frame,
		})
		Theme.corner(swatch, 7)
		Theme.stroke(swatch, Color3.new(0, 0, 0), 1, 0.6)
		table.insert(swatches, swatch)
	end
	if skin and skin.Glow then
		Theme.label({
			Position = UDim2.fromOffset(70, 8),
			Size = UDim2.new(1, -78, 0, 16),
			Text = (skin.Elite and "ELITE  " or "") .. (skin.Pulse and "GLOW + FX" or "GLOW"),
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = color,
			Parent = frame,
		})
	end
	local name = Theme.label({
		Position = UDim2.fromOffset(18, 28),
		Size = UDim2.new(1, -26, 0, 20),
		Text = skin and skin.Name or (not isSkinTab() and Cosmetics.Default(weapon) and Cosmetics.Default(weapon).Name or "Default"),
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = frame,
	})
	Theme.label({
		Position = UDim2.fromOffset(18, 48),
		Size = UDim2.new(0.6, 0, 0, 14),
		Text = rarity and rarity.Name or "STANDARD",
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = color,
		Parent = frame,
	})
	local tag = Theme.label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 48),
		Size = UDim2.new(0.5, 0, 0, 14),
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = frame,
	})
	frame.Activated:Connect(function()
		Sfx.Play("CardHover")
		select(skin and skin.Id or nil)
	end)
	tiles[id] = { Frame = frame, Stroke = stroke, Tag = tag, Swatches = swatches, Name = name }
end

local function buildTab()
	for _, tile in pairs(tiles) do
		tile.Frame:Destroy()
	end
	table.clear(tiles)
	makeTile(nil, 0)
	for i, skin in ipairs(skinsForTab()) do
		makeTile(skin, i)
	end
	for name, button in pairs(tabs) do
		local on = name == weapon
		button.BackgroundColor3 = on and Palette.UIAccent or Palette.UIPanelLight
		button.TextColor3 = on and Palette.UIBackground or Palette.UIText
	end
	selected = equipped[weapon]
	buildPreview()
	refreshTiles()
end

----------------------------------------------------------------------------
-- Open / close
----------------------------------------------------------------------------
function Locker.Open()
	if isOpen or ClientState.InMatch() or ClientState.MenuOpen then
		return
	end
	isOpen = true
	gui.Enabled = true
	unlocker.Visible = true
	ClientState.SetMenu("Locker", true)
	buildTab()
	panel.Size = UDim2.fromOffset(W - 40, H - 40)
	Theme.tween(panel, 0.2, { Size = UDim2.fromOffset(W, H) }, Enum.EasingStyle.Back)
	Sfx.Play("CardPick", { Pitch = 1.1, Volume = 0.6 })
end

function Locker.Close()
	if not isOpen then
		return
	end
	isOpen = false
	gui.Enabled = false
	unlocker.Visible = false
	ClientState.SetMenu("Locker", false)
	if preview then
		preview.Model:Destroy()
		preview = nil
	end
end

function Locker.IsOpen()
	return isOpen
end

function Locker.Toggle()
	if isOpen then
		Locker.Close()
	else
		Locker.Open()
	end
end

function Locker.Init() end

function Locker.Start(playerGui)
	gui = Theme.screen("Locker", 9, playerGui)
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
		ClipsDescendants = true,
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
		Size = UDim2.new(0.5, 0, 0, 34),
		Text = "LOCKER",
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = panel,
	})
	Theme.label({
		Position = UDim2.fromOffset(0, 36),
		Size = UDim2.new(0.6, 0, 0, 20),
		Text = "Skins, tracers, kill effects, poses and titles. Everyone sees them.  L: close",
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Palette.UISubText,
		FontFace = Theme.Font(Enum.FontWeight.Medium),
		Parent = panel,
	})

	-- tabs
	tabs = {}
	for i, name in ipairs(TABS) do
		local button = Theme.button({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -(#TABS - i) * 88, 0, 4),
			Size = UDim2.fromOffset(84, 34),
			Text = TAB_NAMES[name],
			TextSize = 13,
			Parent = panel,
		})
		button.Activated:Connect(function()
			if weapon ~= name then
				weapon = name
				Sfx.Play("CardHover", { Pitch = 1.2 })
				buildTab()
			end
		end)
		tabs[name] = button
	end

	-- left: the preview + details
	local left = Theme.new("Frame", {
		Position = UDim2.fromOffset(0, 70),
		Size = UDim2.new(0.46, -8, 1, -70),
		BackgroundColor3 = Palette.UIBackground,
		Parent = panel,
	})
	Theme.corner(left, 12)
	viewport = Theme.new("ViewportFrame", {
		Size = UDim2.new(1, 0, 1, -128),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(150, 155, 170),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-0.4, -1, -0.6),
		Parent = left,
	})
	worldModel = Instance.new("WorldModel")
	worldModel.Parent = viewport
	previewCam = Instance.new("Camera")
	previewCam.FieldOfView = 30
	previewCam.CFrame = CFrame.lookAt(Vector3.new(0, 1.2, 9.5), Vector3.new(0, 0, 0))
	previewCam.Parent = viewport
	viewport.CurrentCamera = previewCam

	-- (tracers / kill effects / poses / titles: a colour bar + the name)
	cosmeticPreview = Theme.new("Frame", {
		Size = UDim2.new(1, 0, 1, -128),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = left,
	})
	cosmeticBar = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.38),
		Size = UDim2.new(0.8, 0, 0, 10),
		Parent = cosmeticPreview,
	})
	Theme.corner(cosmeticBar, 5)
	cosmeticText = Theme.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.new(0.9, 0, 0, 44),
		TextSize = 34,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = cosmeticPreview,
	})
	Theme.label({
		Name = "Description",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.7),
		Size = UDim2.new(0.85, 0, 0, 40),
		TextSize = 13,
		TextWrapped = true,
		TextColor3 = Palette.UISubText,
		FontFace = Theme.Font(Enum.FontWeight.Medium),
		Parent = cosmeticPreview,
	})

	nameLabel = Theme.label({
		Position = UDim2.new(0, 16, 1, -124),
		Size = UDim2.new(1, -32, 0, 30),
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = left,
	})
	rarityLabel = Theme.label({
		Position = UDim2.new(0, 16, 1, -94),
		Size = UDim2.new(0.5, 0, 0, 18),
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = left,
	})
	statusLabel = Theme.label({
		Position = UDim2.new(0, 16, 1, -74),
		Size = UDim2.new(1, -32, 0, 16),
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.Font(Enum.FontWeight.Medium),
		Parent = left,
	})
	equipButton = Theme.button({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -12),
		Size = UDim2.new(1, -32, 0, 42),
		Text = "EQUIP",
		TextSize = 18,
		Parent = left,
	})
	equipButton.Activated:Connect(function()
		local skin = itemOf(selected)
		if equipped[weapon] == selected or not owns(skin) then
			return
		end
		if waiting and waiting.Weapon == weapon and waiting.Id == selected then
			return
		end
		Sfx.Play("CardPick", { Pitch = 1.2 })
		Theme.pop(equipButton, 0.06)
		-- shown as EQUIPPING until the server confirms (our RifleSkin / KnifeSkin attribute changes)
		local request = { Weapon = weapon, Id = selected }
		waiting = request
		Remotes.Get("SkinEquip"):FireServer(weapon, selected)
		refreshTiles()
		task.delay(3, function()
			if waiting == request then
				waiting = nil -- (refused or lost: show what we really have on)
				refreshTiles()
			end
		end)
	end)

	-- right: every skin for this weapon
	grid = Theme.new("ScrollingFrame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 70),
		Size = UDim2.new(0.54, 0, 1, -122),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Palette.UISubText,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = panel,
	}, {
		Theme.new("UIGridLayout", {
			CellSize = UDim2.new(0.5, -6, 0, 68),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Theme.new("UIPadding", { PaddingRight = UDim.new(0, 8) }),
	})

	defaultButton = Theme.button({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromOffset(160, 42),
		Text = "DONE",
		TextSize = 18,
		Parent = panel,
	})
	defaultButton.Activated:Connect(Locker.Close)

	-- what you own (CrateController hears it from the server) and have on
	ClientState.SkinsChanged:Connect(function()
		owned = ClientState.OwnedSkins
		if isOpen then
			refreshTiles()
		end
	end)
	for _, name in ipairs(TABS) do
		equipped[name] = player:GetAttribute(ATTRIBUTE[name])
		player:GetAttributeChangedSignal(ATTRIBUTE[name]):Connect(function()
			equipped[name] = player:GetAttribute(ATTRIBUTE[name])
			if waiting and waiting.Weapon == name and waiting.Id == equipped[name] then
				waiting = nil
			end
			if isOpen then
				refreshTiles()
			end
		end)
	end

	RunService.RenderStepped:Connect(function(dt)
		if isOpen then
			placePreview(dt)
		end
	end)

	ClientState.Changed:Connect(function(snapshot)
		if snapshot.InMatch then
			Locker.Close()
		end
	end)

	local function onActionInput(input, processed)
		if processed and UserInputService:GetFocusedTextBox() then
			return
		end
		if require(script.Parent.SettingsMenu).IsOpen() then
			return
		end
		if Keybinds.Matches("Locker", input) then
			if isOpen then
				Locker.Close()
			elseif not ClientState.InMatch() then
				Locker.Open()
			end
		end
	end
	UserInputService.InputBegan:Connect(onActionInput)
	Keybinds.VirtualBegan:Connect(onActionInput)
end

return Locker
