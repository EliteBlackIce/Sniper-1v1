--[[
	BattlePass.lua  (Client.ui.BattlePass)

	The battle pass screen (lobby, key J or the BATTLE PASS button): the
	season, your tier and XP, and a row of every tier with its Free reward
	on top and its Premium reward below. Reached tiers light up; Premium
	rewards are locked until you get the Premium pass (Game Pass,
	Config.Shop.Passes.BattlePass). Rewards are handed out by the server
	(PassService) the moment you reach a tier.
]]

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Skins = require(Shared.Skins)
local Cosmetics = require(Shared.Cosmetics)
local ClientState = require(script.Parent.Parent.ClientState)
local Sfx = require(script.Parent.Parent.Sfx)
local Keybinds = require(script.Parent.Parent.Keybinds)
local Theme = require(script.Parent.Theme)

local Palette = Config.Palette
local BP = Config.BattlePass
local player = Players.LocalPlayer

local BattlePass = {}

local W, H = 980, 560
local GOLD = Color3.fromRGB(255, 196, 60)
local gui, panel, unlocker, track, tierLabel, xpFill, xpLabel, premiumButton
local columns = {} -- [tier] = { Free = frame, Premium = frame, Number = label }
local isOpen = false
local progress = { XP = 0, Free = 0, Premium = 0, HasPremium = false }

local rarityColor = {}
for _, rarity in ipairs(Config.Crates.Rarities) do
	rarityColor[rarity.Id] = rarity.Color
end

-- Text + colour for a reward.
local function describe(reward)
	if reward.Keys then
		return tostring(reward.Keys), "KEYS", Palette.UIAccent
	elseif reward.Credits then
		return tostring(reward.Credits), "CREDITS", GOLD
	elseif reward.Skin then
		local skin = Skins.Get(reward.Skin)
		if skin then
			return string.upper(skin.Name), string.upper(skin.Weapon) .. " SKIN", rarityColor[skin.Rarity] or Palette.UIText
		end
	elseif reward.Cosmetic then
		local item = Cosmetics.Get(reward.Cosmetic)
		if item then
			local kind = ({ Tracer = "TRACER", KillFx = "KILL EFFECT", Pose = "POSE", Title = "TITLE" })[item.Kind]
			return string.upper(item.Name), kind, item.Color or rarityColor[item.Rarity] or Palette.UIText
		end
	end
	return "?", "", Palette.UIText
end

local function rewardCard(parent, reward, y, premium)
	local big, small, color = describe(reward)
	local frame = Theme.new("Frame", {
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.new(1, 0, 0, 150),
		BackgroundColor3 = Palette.UIPanelLight,
		Parent = parent,
	})
	Theme.corner(frame, 10)
	local stroke = Theme.stroke(frame, premium and GOLD or Palette.UIText, 1, 0.7)
	Theme.label({
		Position = UDim2.fromOffset(6, 40),
		Size = UDim2.new(1, -12, 0, 40),
		Text = big,
		TextScaled = true,
		TextColor3 = color,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = frame,
	})
	Theme.label({
		Position = UDim2.fromOffset(4, 86),
		Size = UDim2.new(1, -8, 0, 16),
		Text = small,
		TextSize = 11,
		TextWrapped = true,
		TextColor3 = Palette.UISubText,
		Parent = frame,
	})
	local status = Theme.label({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -6),
		Size = UDim2.new(1, 0, 0, 16),
		Text = "",
		TextSize = 11,
		Parent = frame,
	})
	return { Frame = frame, Stroke = stroke, Status = status }
end

local function refresh()
	local tier = math.floor(progress.XP / BP.XPPerTier)
	local into = progress.XP - tier * BP.XPPerTier
	local maxed = tier >= #BP.Tiers
	tierLabel.Text = ("TIER %d / %d"):format(math.min(tier, #BP.Tiers), #BP.Tiers)
	xpFill.Size = UDim2.fromScale(maxed and 1 or into / BP.XPPerTier, 1)
	xpLabel.Text = maxed and "MAXED OUT" or ("%d / %d XP  -  win a match: +%d, lose: +%d"):format(into, BP.XPPerTier, BP.XPWin, BP.XPLoss)
	premiumButton.Text = progress.HasPremium and "PREMIUM OWNED" or ("GET PREMIUM  -  R$ %d"):format(Config.Shop.Passes.BattlePass.Robux)
	premiumButton.AutoButtonColor = not progress.HasPremium
	for i, column in pairs(columns) do
		local reached = i <= tier
		column.Number.TextColor3 = reached and Palette.UIAccent or Palette.UISubText
		column.Free.Stroke.Transparency = reached and 0 or 0.7
		column.Free.Status.Text = reached and "CLAIMED" or ""
		column.Free.Status.TextColor3 = Palette.UIAccent
		column.Premium.Stroke.Transparency = (reached and progress.HasPremium) and 0 or 0.7
		column.Premium.Status.Text = not progress.HasPremium and "PREMIUM" or (reached and "CLAIMED" or "")
		column.Premium.Status.TextColor3 = progress.HasPremium and GOLD or Palette.UISubText
		column.Premium.Frame.BackgroundTransparency = progress.HasPremium and 0 or 0.45
	end
end

function BattlePass.Open()
	if isOpen or ClientState.InMatch() or ClientState.MenuOpen then
		return
	end
	isOpen = true
	gui.Enabled = true
	unlocker.Visible = true
	ClientState.SetMenu("BattlePass", true)
	Remotes.Get("Pass"):FireServer() -- (fresh progress)
	refresh()
	-- scroll to your tier
	local tier = math.floor(progress.XP / BP.XPPerTier)
	track.CanvasPosition = Vector2.new(math.max(0, (tier - 2) * 128), 0)
	panel.Size = UDim2.fromOffset(W - 40, H - 40)
	Theme.tween(panel, 0.2, { Size = UDim2.fromOffset(W, H) }, Enum.EasingStyle.Back)
	Sfx.Play("CardPick", { Pitch = 1.05, Volume = 0.6 })
end

function BattlePass.Close()
	if not isOpen then
		return
	end
	isOpen = false
	gui.Enabled = false
	unlocker.Visible = false
	ClientState.SetMenu("BattlePass", false)
end

function BattlePass.Toggle()
	if isOpen then
		BattlePass.Close()
	else
		BattlePass.Open()
	end
end

function BattlePass.Init() end

function BattlePass.Start(playerGui)
	gui = Theme.screen("BattlePass", 9, playerGui)
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
		Size = UDim2.new(0.6, 0, 0, 34),
		Text = BP.Name,
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = panel,
	})
	tierLabel = Theme.label({
		Position = UDim2.fromOffset(0, 38),
		Size = UDim2.new(0.3, 0, 0, 22),
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Palette.UIAccent,
		Parent = panel,
	})
	local bar = Theme.new("Frame", {
		Position = UDim2.new(0.22, 0, 0, 44),
		Size = UDim2.new(0.42, 0, 0, 10),
		BackgroundColor3 = Palette.UIPanelLight,
		Parent = panel,
	})
	Theme.corner(bar, 5)
	xpFill = Theme.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Palette.UIAccent, Parent = bar })
	Theme.corner(xpFill, 5)
	xpLabel = Theme.label({
		Position = UDim2.new(0.22, 0, 0, 58),
		Size = UDim2.new(0.5, 0, 0, 16),
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Palette.UISubText,
		Parent = panel,
	})
	premiumButton = Theme.button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(270, 46),
		TextSize = 17,
		BackgroundColor3 = GOLD,
		Parent = panel,
	})
	premiumButton.Activated:Connect(function()
		local pass = Config.Shop.Passes.BattlePass
		if progress.HasPremium then
			return
		end
		if pass.Id == 0 then
			premiumButton.Text = "NOT SET UP (Config.Shop)"
			return
		end
		MarketplaceService:PromptGamePassPurchase(player, pass.Id)
	end)

	-- labels for the two tracks
	for i, name in ipairs({ "FREE", "PREMIUM" }) do
		Theme.label({
			Position = UDim2.fromOffset(0, 112 + (i - 1) * 160 + 60),
			Size = UDim2.fromOffset(70, 30),
			Text = name,
			TextSize = 14,
			TextColor3 = i == 2 and GOLD or Palette.UIText,
			Parent = panel,
		})
	end
	track = Theme.new("ScrollingFrame", {
		Position = UDim2.fromOffset(76, 86),
		Size = UDim2.new(1, -76, 1, -146),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Palette.UISubText,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		Parent = panel,
	}, {
		Theme.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	for i, tier in ipairs(BP.Tiers) do
		local column = Theme.new("Frame", {
			Size = UDim2.new(0, 120, 1, -10),
			BackgroundTransparency = 1,
			LayoutOrder = i,
			Parent = track,
		})
		local number = Theme.label({
			Size = UDim2.new(1, 0, 0, 22),
			Text = tostring(i),
			TextSize = 18,
			FontFace = Theme.Font(Enum.FontWeight.Heavy),
			Parent = column,
		})
		columns[i] = {
			Number = number,
			Free = rewardCard(column, tier.Free, 26, false),
			Premium = rewardCard(column, tier.Premium, 186, true),
		}
	end

	local done = Theme.button({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromOffset(160, 42),
		Text = "DONE",
		TextSize = 18,
		Parent = panel,
	})
	done.Activated:Connect(BattlePass.Close)

	Remotes.Get("Pass").OnClientEvent:Connect(function(data)
		if typeof(data) == "table" then
			progress.XP = tonumber(data.XP) or 0
			progress.Free = tonumber(data.Free) or 0
			progress.Premium = tonumber(data.Premium) or 0
			progress.HasPremium = data.HasPremium == true
			refresh()
		end
	end)
	refresh()

	ClientState.Changed:Connect(function(snapshot)
		if snapshot.InMatch then
			BattlePass.Close()
		end
	end)
	local function onActionInput(input, processed)
		if processed and UserInputService:GetFocusedTextBox() then
			return
		end
		if require(script.Parent.SettingsMenu).IsOpen() then
			return
		end
		if Keybinds.Matches("BattlePass", input) then
			BattlePass.Toggle()
		end
	end
	UserInputService.InputBegan:Connect(onActionInput)
	Keybinds.VirtualBegan:Connect(onActionInput)
end

return BattlePass
