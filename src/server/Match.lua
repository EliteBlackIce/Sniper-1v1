--[[
	Match.lua  (ServerScriptService.Server.Match)

	One 1v1 match between two players in one arena. Runs the whole flow:

		Countdown -> Fight -> RoundEnd -> Pick -> PickReveal -> (next round)
		                                  \-> Victory (someone reached 4 wins)

	State is sent to both players as a "snapshot" table on every phase change
	(see Match:Snapshot). The client UI is drawn purely from that snapshot.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PowerUps = require(ReplicatedStorage.Shared.PowerUps)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Util = require(ReplicatedStorage.Shared.Util)
local CharacterService = require(script.Parent.CharacterService)

local Match = {}
Match.__index = Match

local nextMatchId = 0

function Match.new(p1, p2, arena, onFinished)
	nextMatchId += 1
	local self = setmetatable({}, Match)
	self.Id = nextMatchId
	self.Players = { p1, p2 }
	self.Arena = arena
	self.OnFinished = onFinished

	self.Wins = { [p1] = 0, [p2] = 0 }
	self.Owned = { [p1] = {}, [p2] = {} } -- { [player] = { [powerUpId] = stacks } }
	self.StatsCache = {}
	self.SecondWindUsed = {} -- reset every round
	self.LastHit = {} -- [victim] = { Attacker, Headshot }
	-- the end-of-match numbers (victory screen)
	self.Tally = {
		[p1] = { Shots = 0, Hits = 0, Headshots = 0, Damage = 0, Longest = 0, Kills = 0, KnifeKills = 0, LongHits = 0 },
		[p2] = { Shots = 0, Hits = 0, Headshots = 0, Damage = 0, Longest = 0, Kills = 0, KnifeKills = 0, LongHits = 0 },
	}
	-- power-up telemetry: [id] = times offered / picked this match (ProfileService)
	self.CardLog = { Offered = {}, Picked = {} }
	-- [player] = { RatingDelta, Rating, Tier, TierChange, Keys, Wager } (filled
	-- in by the services that pay out, when the result is decided)
	self.Results = { [p1] = {}, [p2] = {} }

	self.Phase = "Starting"
	self.Round = 0
	self.PhaseEndsAt = nil
	self.Message = nil
	self.Aborted = false
	self.Finished = false
	return self
end

----------------------------------------------------------------------------
-- Queries used by other services
----------------------------------------------------------------------------
function Match:GetSlot(player)
	return self.Players[1] == player and 1 or 2
end

function Match:GetOpponent(player)
	return self.Players[1] == player and self.Players[2] or self.Players[1]
end

function Match:IsFighting()
	return self.Phase == "Fight" and not self.Aborted
end

-- Power-up stats for a player (cached until they pick a new card).
function Match:GetStats(player)
	local stats = self.StatsCache[player]
	if not stats then
		stats = PowerUps.ComputeStats(self.Owned[player])
		self.StatsCache[player] = stats
	end
	return stats
end

function Match:ColorFor(player)
	return self:GetSlot(player) == 1 and Config.Palette.PlayerA or Config.Palette.PlayerB
end

----------------------------------------------------------------------------
-- Networking
----------------------------------------------------------------------------
function Match:Snapshot()
	local players = {}
	for slot, player in ipairs(self.Players) do
		players[slot] = {
			UserId = player.UserId,
			Name = player.DisplayName,
			Slot = slot,
			Wins = self.Wins[player],
			PowerUps = table.clone(self.Owned[player]),
			-- bots aren't real Players, so clients find their body by name
			IsBot = Util.isBot(player) or nil,
			CharacterName = Util.isBot(player) and player.Character and player.Character.Name or nil,
		}
		if self.Phase == "Victory" then
			players[slot].Tally = self.Tally[player]
			players[slot].Result = self.Results[player]
		end
	end
	return {
		InMatch = true,
		MatchId = self.Id,
		MapName = self.Arena and self.Arena.MapName, -- (rotates every match)
		Phase = self.Phase,
		Round = self.Round,
		RoundsToWin = Config.Match.RoundsToWin,
		PhaseEndsAt = self.PhaseEndsAt,
		Players = players,
		Cards = self.Cards,
		PickerUserId = self.Picker and self.Picker.UserId or nil,
		PickedIndex = self.PickedIndex,
		RoundWinnerUserId = self.RoundWinner and self.RoundWinner.UserId or nil,
		MatchWinnerUserId = self.MatchWinner and self.MatchWinner.UserId or nil,
		Message = self.Message,
	}
end

function Match:Broadcast()
	local snapshot = self:Snapshot()
	local remote = Remotes.Get("MatchState")
	for _, player in ipairs(self.Players) do
		if player.Parent then
			remote:FireClient(player, snapshot)
		end
	end
	-- lobby players watching this match (MatchService spectating)
	local watch = Remotes.Get("SpectateState")
	for watcher in pairs(self.Spectators or {}) do
		if watcher.Parent then
			watch:FireClient(watcher, snapshot)
		end
	end
end

function Match:SetPhase(phase, duration, message)
	self.Phase = phase
	self.Message = message
	self.PhaseEndsAt = duration and (workspace:GetServerTimeNow() + duration) or nil
	self:Broadcast()
end

-- Waits up to `seconds`, returning early if `stopWhen()` becomes true.
-- Returns false if the match was aborted (someone left).
function Match:Wait(seconds, stopWhen)
	local deadline = os.clock() + seconds
	while os.clock() < deadline do
		if self.Aborted then
			return false
		end
		if stopWhen and stopWhen() then
			break
		end
		task.wait(0.05)
	end
	return not self.Aborted
end

----------------------------------------------------------------------------
-- Spawning
----------------------------------------------------------------------------
function Match:SpawnPlayers()
	local done = 0
	for slot, player in ipairs(self.Players) do
		task.spawn(function()
			local stats = self:GetStats(player)
			CharacterService.Spawn(player, self.Arena.Spawns[slot], {
				Color = self:ColorFor(player),
				MaxHealth = stats.MaxHealth,
				Frozen = true,
				KillY = self.Arena.FloorY - Config.Match.VoidDepth,
				PowerUps = self.Owned[player],
				Shield = stats.StartShield, -- Overshield: a fresh shield every round
			})
			done += 1
			-- a slow spawn (avatar download) can finish after the round started
			if self.Phase == "Fight" and not self.Aborted then
				CharacterService.SetFrozen(player, false)
			end
		end)
	end
	-- wait for both LoadCharacter calls (with a safety timeout)
	self:Wait(6, function()
		return done >= #self.Players
	end)
end

function Match:SetAllFrozen(frozen)
	for _, player in ipairs(self.Players) do
		CharacterService.SetFrozen(player, frozen)
	end
end

----------------------------------------------------------------------------
-- Events from other services
----------------------------------------------------------------------------
function Match:OnPlayerDied(player)
	if self.Phase == "Fight" and not self.RoundLoser then
		self.RoundLoser = player
	end
end

function Match:OnPlayerLeft(player)
	if self.Finished then
		return
	end
	self.Aborted = true
	self.ForfeitWinner = self:GetOpponent(player)
end

function Match:NoteHit(attacker, victim, headshot)
	self.LastHit[victim] = { Attacker = attacker, Headshot = headshot }
end

-- One trigger pull: did any bullet hit them, was one a headshot, how far.
function Match:NoteShot(player, hit, headshot, distance)
	local tally = self.Tally[player]
	if not tally or not self:IsFighting() then
		return
	end
	tally.Shots += 1
	if hit then
		tally.Hits += 1
		tally.Longest = math.max(tally.Longest, math.floor(distance or 0))
		if (distance or 0) >= (Config.Challenges and Config.Challenges.LongHitDistance or 300) then
			tally.LongHits += 1
		end
	end
	if headshot then
		tally.Headshots += 1
	end
end

-- Damage that landed (after shields, capped at the health they had).
function Match:NoteDamage(attacker, amount)
	local tally = attacker and self.Tally[attacker]
	if tally and amount > 0 then
		tally.Damage += amount
	end
end

-- A killing blow (knife = a melee kill).
function Match:NoteKill(attacker, knife)
	local tally = attacker and self.Tally[attacker]
	if tally then
		tally.Kills += 1
		if knife then
			tally.KnifeKills += 1
		end
	end
end

-- Lets a service add to the result shown on the victory screen.
function Match:SetResult(player, key, value)
	local result = self.Results[player]
	if result then
		result[key] = value
	end
end

-- Ends the match straight away with no winner (e.g. "/endbot").
function Match:Cancel()
	if not self.Finished then
		self.Aborted = true
		self.ForfeitWinner = nil
	end
end

function Match:OnPickCard(player, index)
	if self.Phase ~= "Pick" or player ~= self.Picker or self.PickedIndex then
		return
	end
	if typeof(index) ~= "number" or index ~= math.floor(index) then
		return
	end
	if index < 1 or index > #self.Cards then
		return
	end
	self.PickedIndex = index
end

----------------------------------------------------------------------------
-- Main loop
----------------------------------------------------------------------------
function Match:Start()
	for _, player in ipairs(self.Players) do
		player.CameraMode = Enum.CameraMode.LockFirstPerson
		player:SetAttribute("InMatch", true)
	end
	task.spawn(function()
		local ok, err = pcall(function()
			self:Run()
		end)
		if not ok then
			warn("[Match] error:", err)
		end
		self:Finish()
	end)
end

function Match:Run()
	while true do
		self.Round += 1
		self.RoundLoser = nil
		self.RoundWinner = nil
		self.Cards = nil
		self.Picker = nil
		self.PickedIndex = nil
		self.SecondWindUsed = {}
		self.LastHit = {}

		-- COUNTDOWN (frozen at spawns)
		self:SpawnPlayers()
		if self.Aborted then
			return
		end
		self:SetPhase("Countdown", Config.Match.CountdownTime)
		if not self:Wait(Config.Match.CountdownTime) then
			return
		end

		-- FIGHT
		self:SetAllFrozen(false)
		self:SetPhase("Fight", Config.Match.MaxRoundTime)
		if not self:Wait(Config.Match.MaxRoundTime, function()
			return self.RoundLoser ~= nil
		end) then
			return
		end

		local loser = self.RoundLoser
		local message
		if not loser then
			-- Time ran out: higher health percentage wins.
			local fractions = {}
			for _, player in ipairs(self.Players) do
				local humanoid = CharacterService.GetAliveHumanoid(player)
				fractions[player] = humanoid and (humanoid.Health / humanoid.MaxHealth) or 0
			end
			local a, b = self.Players[1], self.Players[2]
			if math.abs(fractions[a] - fractions[b]) < 0.001 then
				self:SetAllFrozen(true)
				self:SetPhase("RoundEnd", Config.Match.RoundEndTime, "DRAW - REPLAYING ROUND")
				if not self:Wait(Config.Match.RoundEndTime) then
					return
				end
				self.Round -= 1
				continue
			end
			loser = fractions[a] < fractions[b] and a or b
			message = "TIME - MORE HEALTH WINS"
		else
			local hit = self.LastHit[loser]
			if hit and hit.Headshot then
				message = "HEADSHOT"
			end
		end

		local winner = self:GetOpponent(loser)
		self.RoundWinner = winner
		self.Wins[winner] += 1
		CharacterService.SetFrozen(winner, true)
		self:SetPhase("RoundEnd", Config.Match.RoundEndTime, message)
		if not self:Wait(Config.Match.RoundEndTime) then
			return
		end

		if self.Wins[winner] >= Config.Match.RoundsToWin then
			self.MatchWinner = winner
			return
		end

		-- POWER-UP PICK: the player who died picks 1 of 5
		local cards = PowerUps.DrawCards(self.Owned[loser], Config.Match.CardsPerPick)
		if not Util.isBot(loser) then
			for _, id in ipairs(cards) do
				self.CardLog.Offered[id] = (self.CardLog.Offered[id] or 0) + 1
			end
		end
		if #cards > 0 then
			self.Cards = cards
			self.Picker = loser
			self.PickedIndex = nil
			self:SetPhase("Pick", Config.Match.PickTime)
			if Util.isBot(loser) then
				-- bots "think" for a moment, then take the rarest card
				task.delay(1.5 + math.random() * 1.5, function()
					if self.Picker == loser and not self.PickedIndex and self.Phase == "Pick" then
						self:OnPickCard(loser, loser:ChooseCard(cards))
					end
				end)
			end
			if not self:Wait(Config.Match.PickTime + 0.3, function()
				return self.PickedIndex ~= nil
			end) then
				return
			end
			if not self.PickedIndex then
				self.PickedIndex = math.random(1, #cards) -- timer ran out
			end
			local id = cards[self.PickedIndex]
			self.Owned[loser][id] = (self.Owned[loser][id] or 0) + 1
			if not Util.isBot(loser) then
				self.CardLog.Picked[id] = (self.CardLog.Picked[id] or 0) + 1
			end
			self.StatsCache[loser] = nil
			self:SetPhase("PickReveal", Config.Match.PickRevealTime)
			if not self:Wait(Config.Match.PickRevealTime) then
				return
			end
		end
	end
end

-- Victory screen, then everyone back to the lobby.
function Match:Finish()
	if self.Finished then
		return
	end
	if self.Aborted and self.ForfeitWinner then
		self.MatchWinner = self.ForfeitWinner
	end
	self.Finished = true
	-- the result is in: pay out now, before the victory screen (someone might leave during it)
	if self.OnDecided then
		local ok, err = pcall(self.OnDecided, self)
		if not ok then
			warn("[Match] OnDecided:", err)
		end
	end

	if self.MatchWinner then
		self:SetAllFrozen(true)
		self:SetPhase("Victory", Config.Match.VictoryTime, self.Aborted and "OPPONENT LEFT" or nil)
		task.wait(Config.Match.VictoryTime)
	end

	for _, player in ipairs(self.Players) do
		if player.Parent == Players then
			player:SetAttribute("InMatch", false)
		end
	end
	if self.OnFinished then
		self.OnFinished(self)
	end
end

return Match
