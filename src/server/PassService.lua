--[[
	PassService.lua  (ServerScriptService.Server.PassService)

	The battle pass (Config.BattlePass):
	  * Finishing a player-vs-player or bot match gives XP (more for a win,
	    plus some per round won). Every XPPerTier XP is a tier.
	  * Reaching a tier gives its Free reward straight away, and its Premium
	    reward too if you own the Premium pass (Game Pass
	    Config.Shop.Passes.BattlePass). Buying Premium later hands out every
	    Premium reward you've already passed.
	  * Progress lives in the player's save (CrateService profile, .Pass) and
	    resets when Config.BattlePass.Season changes.
	  * Ranked titles: reaching a rating with a title (Config.Cosmetics.Titles
	    RankMin) unlocks it.
	The client hears about progress on the "Pass" remote (ui/BattlePass).
]]

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Util = require(ReplicatedStorage.Shared.Util)

local BP = Config.BattlePass
local PassService = {}

local CrateService
local premium = {} -- [player] = true if they own the Premium pass

local function notify(player, text)
	Remotes.Get("Notify"):FireClient(player, text)
end

-- This season's progress in the player's profile (created / reset as needed).
local function progressOf(player)
	local profile = CrateService.GetProfile(player)
	if not profile then
		return nil
	end
	local pass = profile.Pass
	if typeof(pass) ~= "table" or pass.Season ~= BP.Season then
		pass = { Season = BP.Season, XP = 0, Free = 0, Premium = 0 }
		profile.Pass = pass
	end
	pass.XP = tonumber(pass.XP) or 0
	pass.Free = tonumber(pass.Free) or 0
	pass.Premium = tonumber(pass.Premium) or 0
	return pass
end

local function send(player)
	local pass = progressOf(player)
	if pass then
		Remotes.Get("Pass"):FireClient(player, {
			Season = pass.Season,
			XP = pass.XP,
			Free = pass.Free,
			Premium = pass.Premium,
			HasPremium = premium[player] == true,
		})
	end
end

-- Hands out every reward up to the current tier that hasn't been given yet.
local function grantRewards(player)
	local pass = progressOf(player)
	if not pass then
		return
	end
	local tier = math.min(math.floor(pass.XP / BP.XPPerTier), #BP.Tiers)
	local given = {}
	while pass.Free < tier do
		pass.Free += 1
		local text = CrateService.Grant(player, BP.Tiers[pass.Free].Free)
		if text then
			table.insert(given, text)
		end
	end
	if premium[player] then
		while pass.Premium < tier do
			pass.Premium += 1
			local text = CrateService.Grant(player, BP.Tiers[pass.Premium].Premium)
			if text then
				table.insert(given, text)
			end
		end
	end
	if #given > 0 then
		notify(player, ("TIER %d!  %s"):format(tier, table.concat(given, "  -  ")))
	end
	CrateService.Changed(player)
	send(player)
end

function PassService.AddXP(player, amount)
	local pass = progressOf(player)
	if not pass or amount <= 0 then
		return
	end
	pass.XP = math.min(pass.XP + amount, #BP.Tiers * BP.XPPerTier)
	notify(player, ("+%d BATTLE PASS XP"):format(amount))
	grantRewards(player)
end

local function onMatchFinished(match)
	if match.Aborted and not match.ForfeitWinner then
		return -- cancelled
	end
	local winner = match.MatchWinner or match.ForfeitWinner
	for _, player in ipairs(match.Players) do
		if not Util.isBot(player) and player.Parent then
			local won = player == winner
			local rounds = match.Wins and match.Wins[player] or 0
			PassService.AddXP(player, (won and BP.XPWin or BP.XPLoss) + rounds * BP.XPPerRound)
		end
	end
end

local function checkPremium(player)
	local passInfo = Config.Shop.Passes.BattlePass
	if passInfo.Id ~= 0 then
		local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, passInfo.Id)
		premium[player] = ok and owns or nil
	end
	-- wait for the save to load, then catch up on rewards
	for _ = 1, 30 do
		if not player.Parent or CrateService.GetProfile(player) then
			break
		end
		task.wait(1)
	end
	if player.Parent and CrateService.GetProfile(player) then
		grantRewards(player)
		PassService.CheckRankTitles(player)
	end
end

-- Unlocks the ranked titles (Config.Cosmetics.Titles with RankMin) a player's rating has reached.
function PassService.CheckRankTitles(player)
	local rating = tonumber(player:GetAttribute("Rating"))
	local profile = CrateService.GetProfile(player)
	if not rating or not profile then
		return
	end
	for _, title in ipairs(Config.Cosmetics.Titles) do
		if title.RankMin and rating >= title.RankMin and not profile.Cosmetics[title.Id] then
			local text = CrateService.Grant(player, { Cosmetic = title.Id })
			if text then
				notify(player, "TITLE UNLOCKED  -  " .. text)
			end
		end
	end
end

function PassService.Init(matchService, crateService)
	CrateService = crateService
	matchService.MatchFinished:Connect(onMatchFinished)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, bought)
		if bought and passId == Config.Shop.Passes.BattlePass.Id then
			premium[player] = true
			notify(player, "PREMIUM PASS UNLOCKED")
			grantRewards(player)
		end
	end)
	Remotes.Get("Pass").OnServerEvent:Connect(function(player)
		send(player) -- (the client asks when it opens the pass screen)
	end)
	Players.PlayerAdded:Connect(function(player)
		task.spawn(checkPremium, player)
		player:GetAttributeChangedSignal("Rating"):Connect(function()
			PassService.CheckRankTitles(player)
		end)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(checkPremium, player)
		player:GetAttributeChangedSignal("Rating"):Connect(function()
			PassService.CheckRankTitles(player)
		end)
	end
	Players.PlayerRemoving:Connect(function(player)
		premium[player] = nil
	end)
end

return PassService
