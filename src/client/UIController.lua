--[[
	UIController.lua  (Client.UIController)
	Creates every screen and forwards match-state changes to them.

	Screens (Client/ui):
		HUD           crosshair, scope, scoreboard, health, banners, hitmarkers
		PickScreen    power-up cards between rounds
		VictoryScreen end of match
		LobbyUI       find match / playground / bot buttons
		SettingsMenu  sliders + keybinds for mouse and controller (P)
		PowerUpLab    try power-ups solo in the lobby (B)
		Locker        pick your rifle and knife skins (L)
		Shop          crates, featured skins, credit packs, VIP (M)
		BattlePass    the season's battle pass (J)
		Toast         short server messages (admin commands)
		DuelUI        challenge a player, duel / rematch invites
		MobileControls on-screen buttons + look pad for touch screens
]]

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local ClientState = require(script.Parent.ClientState)
local ui = script.Parent:WaitForChild("ui")
local HUD = require(ui.HUD)
local PickScreen = require(ui.PickScreen)
local VictoryScreen = require(ui.VictoryScreen)
local LobbyUI = require(ui.LobbyUI)
local SettingsMenu = require(ui.SettingsMenu)
local PowerUpLab = require(ui.PowerUpLab)
local Locker = require(ui.Locker)
local Shop = require(ui.Shop)
local BattlePass = require(ui.BattlePass)
local Toast = require(ui.Toast)
local DuelUI = require(ui.DuelUI)
local MobileControls = require(ui.MobileControls)

local UIController = {}

UIController.HUD = HUD
UIController.Settings = SettingsMenu

function UIController.Init(controllers)
	controllers.HUD = HUD
	controllers.Settings = SettingsMenu
	controllers.Duel = DuelUI
	controllers.Locker = Locker
	controllers.Shop = Shop
	controllers.BattlePass = BattlePass
	MobileControls.Init(controllers)
	HUD.Init(controllers)
	LobbyUI.Init(controllers)
	SettingsMenu.Init(controllers)
	VictoryScreen.Init(controllers)
end

function UIController.Start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- No reset button (dying on purpose would skip rounds) and a clean screen
	task.spawn(function()
		for _ = 1, 10 do
			local ok = pcall(function()
				StarterGui:SetCore("ResetButtonCallback", false)
			end)
			if ok then
				break
			end
			task.wait(1)
		end
	end)
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)

	HUD.Start(playerGui)
	PickScreen.Start(playerGui)
	VictoryScreen.Start(playerGui)
	LobbyUI.Start(playerGui)
	SettingsMenu.Start(playerGui)
	PowerUpLab.Start(playerGui)
	Locker.Start(playerGui)
	Shop.Start(playerGui)
	BattlePass.Start(playerGui)
	Toast.Start(playerGui)
	DuelUI.Start(playerGui)
	MobileControls.Start(playerGui)

	ClientState.Changed:Connect(function(snapshot, old)
		HUD.OnState(snapshot, old)
		PickScreen.OnState(snapshot, old)
		VictoryScreen.OnState(snapshot, old)
		LobbyUI.OnState(snapshot, old)
	end)
end

return UIController
