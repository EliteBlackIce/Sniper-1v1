--[[
	CombatService.lua  (ServerScriptService.Server.CombatService)

	Everything that deals damage is decided HERE, on the server:

	FIRE VALIDATION (anti-exploit)
	  1. Arguments must be real, finite Vector3s.
	  2. The shooter must be alive, and either in a live round or practising
	     in the lobby (where only the dummies can be hurt).
	  3. Fire rate: shots faster than the (power-up adjusted) bolt time are rejected.
	  4. Origin: the shot must start near the shooter's head on the server.
	  5. The server re-traces every bullet with Ballistics.Simulate (the same
	     code the client uses) and decides what was hit.

	LAG COMPENSATION (client "claims")
	  The client also says what it saw itself hit. Because the enemy moves
	  between the client's frame and the server receiving the shot, the server
	  accepts a claim only if:
	    * the claimed point lies on the server's own bullet path (so walls
	      really didn't block it), and
	    * the claimed point is close to where that body part really is
	      on the server (with a small allowance for the victim's speed).

	DAMAGE (how power-ups stack)
	  bullet damage = base (head / body / limb)
	                x Glass Cannon multiplier
	                x (1 + Sky Sniper bonus, if you're airborne)
	                x (1 + Momentum Rounds bonus, from your speed)
	                x (1 + Pinball bonus x bounces/wall passes before the hit)
	                x (1 + Marked bonus, if the target is marked)
	                x Deadeye (fully charged scoped shot), Long Shot (distance)
	                x Last Stand (you're low), Executioner (they're low)
	  Headshots are always an instant kill.
	  Explosions, Shrapnel, Static Charge, Acid pools and Serrated bleed use
	  the same shot multiplier (Glass Cannon, Sky Sniper, Momentum, Deadeye)
	  and the Marked / Last Stand / Executioner bonuses.

	TAKING DAMAGE (CombatService.Damage)
	  Kinetic Armor (moving fast) reduces it, then the shield (the "Shield"
	  character attribute: Overshield / Bloodlust) soaks it, then health.
	  Second Wind saves you from a lethal hit.

	WAVE 2 POWER-UPS handled here: on-hit effects (Frost slow, Serrated
	bleed, Impact shove, Disruptor jam, Bloodlust shield), Acid pools,
	Double Tap, Deadeye, Sonar, Regeneration, and the actives Barrier Dome,
	Smoke Grenade, Recall and Air Dash.

	"Targets" are the enemy player in a match, or the practice dummies in the
	lobby, so every power-up works on the range too.

	KNIFE (onMelee): the client says what it swung at; the server checks the
	knife is out (and was drawn long enough ago), the swing timing, the
	range, that you were facing the target and could see it, then deals
	slash / stab damage. A hit from behind (backstab) is always a kill.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Ballistics = require(ReplicatedStorage.Shared.Ballistics)
local Util = require(ReplicatedStorage.Shared.Util)
local CharacterService = require(script.Parent.CharacterService)
local MatchService = require(script.Parent.MatchService)
local DummyService = require(script.Parent.DummyService)

local W = Config.Weapon
local PU = Config.PowerUps

local CombatService = {}

local lastFire = {} -- [player] = os.clock() of last accepted shot
local lastMelee = {} -- [player] = os.clock() of the last accepted swing
local cooldowns = {} -- [player] = { [abilityName] = os.clock() ready time }
local bulletTimeUntil = {} -- [player] = os.clock()
local markedUntil = {} -- [player or dummy model] = os.clock()
local lastShot = {} -- [player] = os.clock() of the last shot (Deadeye charge; Hair Trigger doesn't fake it)
local scopedSince = {} -- [player] = os.clock() they scoped in (Deadeye)
local quickShotReady = {} -- [player] = true while a Double Tap follow-up is available
local lastHurt = {} -- [player] = os.clock() they last took damage (Regeneration)
local history = {} -- [player] = { {T, Position, Health, Character} } the last few seconds (Recall)
local pools = {} -- Acid Rounds pools { Id, Owner, Match, Stats, Mult, Position, Radius, Until, NextTick }
local bleeds = {} -- [player or dummy model] = { Attacker, Match, Stats, Target, Left, Rate, NextTick }
local barriers = {} -- { Part, Owner, Match, Until }
local smokes = {} -- { Model, Owner, Match, Until, Fading }
local nextPoolId = 0

-- abilities Disruptor Rounds can jam (server cooldown names)
local DISRUPTABLE = { "Decoy", "BulletTime", "Blink", "PhantomDash", "Barrier", "Recall", "Smoke", "AirDash" }

local decoyFolder
local effectsFolder
local barrierFolder -- Barrier Dome shells (they stop bullets)
local smokeFolder -- Smoke Grenade clouds (bullets pass through)

----------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------
local function sendToMatch(match, remoteName, ...)
	local remote = Remotes.Get(remoteName)
	for _, player in ipairs(match.Players) do
		if player.Parent then
			remote:FireClient(player, ...)
		end
	end
end

-- Sends an effect to everyone who should see it: the match players, or
-- everyone in the lobby when `match` is nil (practice).
local function sendFx(match, data)
	if match then
		sendToMatch(match, "Effect", data)
		return
	end
	local remote = Remotes.Get("Effect")
	for _, other in ipairs(Players:GetPlayers()) do
		if not MatchService.GetMatch(other) then
			remote:FireClient(other, data)
		end
	end
end

-- Power-up stats for a player: their match stats, or their Power-Up Lab
-- picks when practising in the lobby.
local function getStats(player, match)
	if match then
		return match:GetStats(player)
	end
	return MatchService.GetPracticeStats(player)
end

-- Returns true (and starts the cooldown) if the ability is ready.
local function useCooldown(player, name, seconds)
	cooldowns[player] = cooldowns[player] or {}
	local now = os.clock()
	if (cooldowns[player][name] or 0) > now then
		return false
	end
	cooldowns[player][name] = now + seconds
	return true
end

-- Things a shooter's bullets ignore: their own body and their own decoys.
local function buildExclude(player)
	local list = { effectsFolder }
	if player.Character then
		table.insert(list, player.Character)
	end
	for _, decoy in ipairs(decoyFolder:GetChildren()) do
		if decoy:GetAttribute("OwnerUserId") == player.UserId then
			table.insert(list, decoy)
		end
	end
	return list
end

local function getTorso(model)
	return model
		and (
			model:FindFirstChild("UpperTorso")
			or model:FindFirstChild("Torso")
			or model:FindFirstChild("HumanoidRootPart")
		)
end

local function knockback(player, velocity)
	if Util.isBot(player) then
		-- the server simulates bots, so push them directly
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and not root.Anchored then
			root.AssemblyLinearVelocity += velocity * Config.Movement.KnockbackScale
			player:SetAttribute("KnockedUntil", os.clock() + 0.35) -- the AI stops steering for a moment
		end
	elseif player.Parent then
		Remotes.Get("Knockback"):FireClient(player, velocity * Config.Movement.KnockbackScale)
	end
end

local function popDecoy(decoy)
	if decoy.Parent then
		local owner = Players:GetPlayerByUserId(decoy:GetAttribute("OwnerUserId") or 0)
		local match = owner and MatchService.GetMatch(owner)
		sendFx(match, { Type = "DecoyPop", Position = decoy:GetPivot().Position })
		decoy:Destroy()
	end
end

-- Random direction within `degrees` of `dir`.
local function randomInCone(dir, degrees)
	local angle = math.rad(degrees) * math.sqrt(math.random())
	local spin = math.random() * math.pi * 2
	local cf = CFrame.lookAt(Vector3.zero, dir)
	return (cf * CFrame.Angles(0, 0, spin) * CFrame.Angles(angle, 0, 0)).LookVector
end

----------------------------------------------------------------------------
-- Targets: the enemy player in a match, or the dummies in the lobby
----------------------------------------------------------------------------
--[[
	A target record: { Player = Player?, Model = Model }
	(Player is nil for practice dummies.)
]]
local function getTargets(shooter, match)
	local list = {}
	if match then
		local opponent = match:GetOpponent(shooter)
		local humanoid, character = CharacterService.GetAliveHumanoid(opponent)
		if humanoid then
			table.insert(list, { Player = opponent, Model = character })
		end
	else
		for _, dummy in ipairs(DummyService.GetDummies()) do
			table.insert(list, { Model = dummy })
		end
	end
	return list
end

local function targetForModel(targets, model)
	for _, target in ipairs(targets) do
		if target.Model == model then
			return target
		end
	end
	return nil
end

local function markKey(target)
	return target.Player or target.Model
end

----------------------------------------------------------------------------
-- Damage to players
----------------------------------------------------------------------------

--[[
	Deals damage from `attacker` to the player `victim` inside `match`.
	info = { Headshot = bool, Splash = bool, Melee, Backstab, Position,
	         Dot = bool, DotSource = the bleed / acid pool record }
	Damage over time (Serrated bleed, Acid pool ticks) sets Dot: the
	HitConfirm / Damaged messages carry Dot = true so the client can keep
	the feedback subtle, and Fight or Flight only triggers once per DoT.
	Returns true if the victim died.
]]
function CombatService.Damage(match, attacker, victim, amount, info)
	info = info or {}
	if not match:IsFighting() then
		return false
	end
	local humanoid = CharacterService.GetAliveHumanoid(victim)
	if not humanoid then
		return false
	end

	local victimStats = match:GetStats(victim)
	local victimCharacter = victim.Character

	-- KINETIC ARMOR: less damage while moving fast
	if victimStats.KineticArmor > 0 then
		local victimRoot = victimCharacter and victimCharacter:FindFirstChild("HumanoidRootPart")
		if victimRoot and Util.flat(victimRoot.AssemblyLinearVelocity).Magnitude >= PU.KineticArmor.MinSpeed then
			amount *= 1 - victimStats.KineticArmor
		end
	end

	-- SHIELD (Overshield / Bloodlust) soaks damage before health
	local absorbed = 0
	local shield = victimCharacter and victimCharacter:GetAttribute("Shield") or 0
	if shield > 0 and amount > 0 then
		absorbed = math.min(shield, amount)
		amount -= absorbed
		victimCharacter:SetAttribute("Shield", shield - absorbed)
	end

	local before = humanoid.Health
	local after = before - amount

	-- SECOND WIND: survive lethal hits (one save per stack, each round)
	if after <= 0 then
		local used = match.SecondWindUsed[victim] or 0
		if used < victimStats.SecondWindCharges then
			match.SecondWindUsed[victim] = used + 1
			after = 1
			Remotes.Get("Buff"):FireClient(victim, {
				Type = "SpeedBoost",
				Multiplier = PU.SecondWind.SpeedMultiplier,
				Duration = PU.SecondWind.BoostTime,
			})
			local root = victim.Character and victim.Character:FindFirstChild("HumanoidRootPart")
			sendToMatch(match, "Effect", {
				Type = "SecondWind",
				UserId = victim.UserId,
				Position = root and root.Position or nil,
			})
		end
	end

	after = math.max(after, 0)
	local dealt = before - after + absorbed
	match:NoteHit(attacker, victim, info.Headshot == true)
	humanoid.Health = after
	if dealt > 0 then
		lastHurt[victim] = os.clock()
		-- FIGHT OR FLIGHT: getting hurt gives a burst of speed
		local boost = after > 0 and victimStats.HurtSpeedTime > 0
		if boost and info.Dot and info.DotSource then
			-- (once per bleed / pool, not on every tick)
			local boosted = info.DotSource.Boosted or {}
			info.DotSource.Boosted = boosted
			boost = not boosted[victim]
			boosted[victim] = true
		end
		if boost then
			Remotes.Get("Buff"):FireClient(victim, {
				Type = "SpeedBoost",
				Multiplier = victimStats.HurtSpeedBoost,
				Duration = victimStats.HurtSpeedTime,
			})
		end
	end

	if attacker and attacker.Parent then
		-- VAMPIRE: heal for a fraction of the damage dealt
		local attackerStats = match:GetStats(attacker)
		local attackerHumanoid = CharacterService.GetAliveHumanoid(attacker)
		if attackerStats.LifeSteal > 0 and attackerHumanoid then
			attackerHumanoid.Health =
				math.min(attackerHumanoid.MaxHealth, attackerHumanoid.Health + dealt * attackerStats.LifeSteal)
		end
		Remotes.Get("HitConfirm"):FireClient(attacker, {
			Headshot = info.Headshot == true,
			Killed = after <= 0,
			Damage = dealt,
			Splash = info.Splash == true,
			Position = info.Position,
			Melee = info.Melee == true,
			Backstab = info.Backstab == true,
			Dot = info.Dot == true, -- (bleed / acid tick: no full hitmarker + sound)
		})
	end

	-- kill effect: the body shatters (everyone in the match sees it)
	if after <= 0 then
		local root = victim.Character and victim.Character:FindFirstChild("HumanoidRootPart")
		if root then
			sendToMatch(match, "Effect", {
				Type = "Kill",
				Position = root.Position,
				Color = match:ColorFor(victim),
				Headshot = info.Headshot == true,
				KillFx = attacker and not Util.isBot(attacker) and attacker:GetAttribute("KillFx") or nil, -- (their kill effect cosmetic)
			})
		end
	end

	local attackerRoot = attacker and attacker.Character and attacker.Character:FindFirstChild("HumanoidRootPart")
	Remotes.Get("Damaged"):FireClient(victim, {
		From = attackerRoot and attackerRoot.Position or nil,
		Damage = dealt,
		Killed = after <= 0,
		Dot = info.Dot == true,
	})
	return after <= 0
end

--[[
	Damages any target (player or dummy) and handles Marked.
	info = { Headshot, Splash }
]]
local function healthFraction(target)
	if target.Player then
		local humanoid = CharacterService.GetAliveHumanoid(target.Player)
		return humanoid and humanoid.Health / math.max(humanoid.MaxHealth, 1) or 0
	end
	return (target.Model:GetAttribute("Health") or 0) / math.max(Config.Lobby.DummyHealth or 100, 1)
end

local function damageTarget(match, attacker, stats, target, amount, info)
	info = info or {}
	-- LAST STAND: more damage while you're low
	if stats.LastStandBonus > 0 and attacker then
		local attackerHumanoid = CharacterService.GetAliveHumanoid(attacker)
		if attackerHumanoid and attackerHumanoid.Health <= attackerHumanoid.MaxHealth * PU.LastStand.HealthFraction then
			amount *= 1 + stats.LastStandBonus
		end
	end
	-- EXECUTIONER: more damage against a target below half health
	if stats.ExecuteBonus > 0 and healthFraction(target) <= PU.Executioner.HealthFraction then
		amount *= 1 + stats.ExecuteBonus
	end
	-- MARKED: bonus damage against a target you hit recently
	local key = markKey(target)
	if stats.MarkBonus > 0 and (markedUntil[key] or 0) > os.clock() then
		amount *= 1 + stats.MarkBonus
	end

	if target.Player then
		CombatService.Damage(match, attacker, target.Player, amount, info)
	else
		local torso = getTorso(target.Model)
		local killed = DummyService.Damage(target.Model, amount)
		Remotes.Get("HitConfirm"):FireClient(attacker, {
			Headshot = info.Headshot == true,
			Killed = killed,
			Damage = amount,
			Splash = info.Splash == true,
			Position = info.Position,
			Melee = info.Melee == true,
			Backstab = info.Backstab == true,
			Dot = info.Dot == true, -- (bleed / acid tick: no full hitmarker + sound)
		})
		if killed and torso then
			sendFx(nil, {
				Type = "Kill",
				Position = torso.Position,
				Color = Config.Palette.PlayerB,
				Headshot = info.Headshot == true,
				KillFx = attacker and not Util.isBot(attacker) and attacker:GetAttribute("KillFx") or nil,
			})
		end
	end

	if stats.MarkBonus > 0 and not info.Dot then -- (a bleed / acid tick isn't a hit: it doesn't keep them marked)
		markedUntil[key] = os.clock() + PU.Marked.Duration
		Remotes.Get("Effect"):FireClient(attacker, {
			Type = "Mark",
			Target = target.Model,
			Duration = PU.Marked.Duration,
		})
	end
end

-- The part of the damage formula shared by everything a shot causes:
-- Glass Cannon x Sky Sniper (airborne) x Momentum Rounds (speed).
local function shotMultiplier(stats, shooterCharacter)
	local mult = stats.DamageMultiplier
	local root = shooterCharacter and shooterCharacter:FindFirstChild("HumanoidRootPart")
	if root then
		if stats.AirDamageBonus > 0 then
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { shooterCharacter, effectsFolder, decoyFolder, barrierFolder }
			local airborne = workspace:Raycast(root.Position, Vector3.new(0, -4.5, 0), params) == nil
			if airborne then
				mult *= 1 + stats.AirDamageBonus
			end
		end
		if stats.SpeedDamageBonus > 0 then
			local cfg = PU.MomentumRounds
			local speed = Util.flat(root.AssemblyLinearVelocity).Magnitude
			local bonus = math.clamp((speed - cfg.FreeSpeed) * cfg.BonusPerSpeed, 0, cfg.MaxBonus)
			mult *= 1 + bonus * stats.SpeedDamageBonus
		end
	end
	return mult
end

local function bulletDamage(part, hops, stats, mult, distance)
	local zone = Util.hitZone(part.Name)
	if zone == "Head" then
		return W.HeadDamage, true -- always an instant kill
	end
	local base = zone == "Body" and W.BodyDamage or W.LimbDamage
	-- LONG SHOT: more damage the further the bullet flew
	local longShot = 0
	if stats.LongShotBonus > 0 and distance then
		local cfg = PU.LongShot
		longShot = stats.LongShotBonus
			* math.clamp((distance - cfg.MinDistance) / math.max(cfg.FullDistance - cfg.MinDistance, 1), 0, 1)
	end
	-- PINBALL: more damage for every bounce / wall pass before the hit
	return base * mult * (1 + stats.HopDamageBonus * (hops or 0)) * (1 + longShot), false
end

----------------------------------------------------------------------------
-- Shot effects: explosions, shrapnel, static charge
----------------------------------------------------------------------------

-- EXPLOSIVE ROUNDS: splash damage + knockback around `position`.
-- `directModel` is the model the bullet hit directly (it doesn't take splash).
local function explode(match, attacker, stats, mult, targets, position, directModel)
	local radius = stats.ExplosionRadius
	local cfg = PU.ExplosiveRounds
	sendFx(match, { Type = "Explosion", Position = position, Radius = radius })

	for _, target in ipairs(targets) do
		local torso = getTorso(target.Model)
		if torso and target.Model ~= directModel then
			local offset = torso.Position - position
			local distance = offset.Magnitude
			if distance <= radius then
				local falloff = 1 - (distance / radius) * 0.5
				damageTarget(match, attacker, stats, target, stats.ExplosionDamage * falloff * mult, {
					Splash = true,
					Position = torso.Position,
				})
				if target.Player then
					local away = Util.safeUnit(offset + Vector3.new(0, 2, 0), Vector3.yAxis)
					knockback(target.Player, away * cfg.Knockback * falloff)
				end
			end
		end
	end

	-- self knockback (no self damage): explosive rocket jumps!
	local root = attacker.Character and attacker.Character:FindFirstChild("HumanoidRootPart")
	if root then
		local offset = root.Position - position
		if offset.Magnitude <= radius then
			local away = Util.safeUnit(offset + Vector3.new(0, 2, 0), Vector3.yAxis)
			knockback(attacker, away * cfg.SelfKnockback * (1 - (offset.Magnitude / radius) * 0.5))
		end
	end

	for _, decoy in ipairs(decoyFolder:GetChildren()) do
		if decoy:GetAttribute("OwnerUserId") ~= attacker.UserId then
			if (decoy:GetPivot().Position - position).Magnitude <= radius then
				popDecoy(decoy)
			end
		end
	end
end

-- SHRAPNEL: shards fly out of every surface a bullet touched.
-- Returns the shard segments for the visual effect.
local function shrapnel(match, attacker, stats, mult, targets, impacts, exclude, budget)
	local cfg = PU.Shrapnel
	local segments = {}
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude

	for _, impact in ipairs(impacts) do
		for _ = 1, stats.ShrapnelCount do
			if budget.Left <= 0 then
				return segments
			end
			budget.Left -= 1
			local dir = randomInCone(impact.Direction, cfg.SpreadDegrees)
			local start = impact.Position + impact.Normal * 0.1
			local ray = workspace:Raycast(start, dir * cfg.Range, params)
			local finish = ray and ray.Position or start + dir * cfg.Range
			table.insert(segments, { From = start, To = finish })
			if ray then
				local target = targetForModel(targets, Ballistics.FindTargetModel(ray.Instance))
				if target then
					damageTarget(match, attacker, stats, target, cfg.Damage * mult, { Splash = true, Position = ray.Position })
				end
			end
		end
	end
	return segments
end

-- STATIC CHARGE: a bullet that passes close to a target zaps it.
local function staticCharge(match, attacker, stats, mult, targets, sim, exclude, zapped)
	for _, target in ipairs(targets) do
		local torso = getTorso(target.Model)
		if torso and not zapped[target.Model] then
			local point, distance = Ballistics.ClosestOnPath(sim, torso.Position)
			if point and distance <= stats.StaticChargeRadius then
				-- needs a clear line from the bullet to the target
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				local list = table.clone(exclude)
				table.insert(list, target.Model)
				params.FilterDescendantsInstances = list
				if not workspace:Raycast(point, torso.Position - point, params) then
					zapped[target.Model] = true
					damageTarget(match, attacker, stats, target, stats.StaticChargeDamage * mult, {
						Splash = true,
						Position = torso.Position,
					})
					sendFx(match, { Type = "Zap", From = point, To = torso.Position })
				end
			end
		end
	end
end

----------------------------------------------------------------------------
-- Wave 2: shields, on-hit effects, acid pools, bleeds
----------------------------------------------------------------------------

-- Adds shield to a player's character (capped by their MaxShield).
local function addShield(player, stats, amount)
	local character = player and player.Character
	if not character or amount <= 0 or stats.MaxShield <= 0 then
		return
	end
	local current = character:GetAttribute("Shield") or 0
	character:SetAttribute("Shield", math.min(stats.MaxShield, current + amount))
end

-- True while effects owned by `owner` (pools, bleeds, domes...) should keep going.
local function stillActive(match, owner)
	if not owner or not owner.Parent then
		return false
	end
	if match then
		return match:IsFighting() and not match.Finished
	end
	return MatchService.GetMatch(owner) == nil -- still practising in the lobby
end

-- The target is still the same living body it was when the effect started.
local function targetAlive(target)
	if not target.Model.Parent then
		return false
	end
	if target.Player then
		local _, character = CharacterService.GetAliveHumanoid(target.Player)
		return character == target.Model
	end
	return (target.Model:GetAttribute("Health") or 0) > 0
end

-- FROST ROUNDS: slows the target (the client owns its movement, bots are server-side).
local function slowTarget(match, target, multiplier, duration)
	local victim = target.Player
	if victim then
		if Util.isBot(victim) then
			victim:SetAttribute("SlowedUntil", os.clock() + duration)
			victim:SetAttribute("SlowMultiplier", multiplier)
		else
			Remotes.Get("Buff"):FireClient(victim, { Type = "Slow", Multiplier = multiplier, Duration = duration })
		end
	end
	sendFx(match, { Type = "Frost", Target = target.Model, Duration = duration })
end

-- DISRUPTOR ROUNDS: jams every active ability for a moment.
local function disrupt(victim, duration)
	cooldowns[victim] = cooldowns[victim] or {}
	local untilTime = os.clock() + duration * 0.9
	for _, name in ipairs(DISRUPTABLE) do
		cooldowns[victim][name] = math.max(cooldowns[victim][name] or 0, untilTime)
	end
	if not Util.isBot(victim) then
		Remotes.Get("Buff"):FireClient(victim, { Type = "Disrupt", Duration = duration })
	end
end

-- SERRATED ROUNDS: damage over time (adds to a bleed you already caused).
local function startBleed(match, attacker, stats, target, amount)
	local cfg = PU.SerratedRounds
	local key = markKey(target)
	local bleed = bleeds[key]
	if bleed and bleed.Attacker == attacker and bleed.Target.Model == target.Model then
		bleed.Left += amount
		bleed.Rate = math.max(bleed.Rate, bleed.Left / cfg.Duration)
	else
		bleed = {
			Attacker = attacker,
			Match = match,
			Stats = stats,
			Target = target,
			Left = amount,
			Rate = amount / cfg.Duration,
			NextTick = os.clock() + cfg.TickInterval,
		}
		bleeds[key] = bleed
	end
	sendFx(match, { Type = "Bleed", Target = target.Model, Duration = bleed.Left / bleed.Rate })
end

-- Everything a DIRECT bullet hit does besides damage (once per target per shot).
local function onBulletHit(match, attacker, stats, mult, target, direction)
	if stats.ShieldOnHit > 0 then
		addShield(attacker, stats, stats.ShieldOnHit) -- BLOODLUST
	end
	if not targetAlive(target) then
		return -- (that hit was the kill)
	end
	if stats.SlowAmount > 0 then
		slowTarget(match, target, 1 - stats.SlowAmount, stats.SlowDuration)
	end
	if stats.BleedDamage > 0 then
		startBleed(match, attacker, stats, target, stats.BleedDamage * mult)
	end
	if target.Player then
		-- IMPACT ROUNDS: shove them along the bullet
		if stats.HitKnockback > 0 then
			local push = Util.safeUnit(Util.flat(direction), Vector3.zAxis) + Vector3.new(0, PU.ImpactRounds.Lift, 0)
			knockback(target.Player, push.Unit * stats.HitKnockback)
		end
		if stats.DisruptTime > 0 then
			disrupt(target.Player, stats.DisruptTime)
		end
	end
end

-- ACID ROUNDS: a damaging pool where the shot landed.
local function spawnPool(match, owner, stats, mult, position, targets)
	local cfg = PU.AcidRounds
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = buildExclude(owner)
	table.insert(exclude, barrierFolder)
	table.insert(exclude, smokeFolder)
	for _, target in ipairs(targets) do
		table.insert(exclude, target.Model)
	end
	params.FilterDescendantsInstances = exclude
	-- settle on the floor under the impact (a hit on a body drips to the ground)
	local floor = workspace:Raycast(position + Vector3.new(0, 1, 0), Vector3.new(0, -16, 0), params)
	local center = floor and floor.Position or position

	-- each player keeps only a few pools: the oldest dries up
	local mine = {}
	for i, pool in ipairs(pools) do
		if pool.Owner == owner then
			table.insert(mine, i)
		end
	end
	if #mine >= cfg.MaxPools then
		local oldest = table.remove(pools, mine[1])
		sendFx(oldest.Match, { Type = "AcidPoolEnd", Id = oldest.Id })
	end

	nextPoolId += 1
	table.insert(pools, {
		Id = nextPoolId,
		Owner = owner,
		Match = match,
		Stats = stats,
		Mult = mult,
		Position = center,
		Radius = stats.AcidRadius,
		Until = os.clock() + stats.AcidDuration,
		NextTick = os.clock() + cfg.TickInterval * 0.5,
	})
	sendFx(match, {
		Type = "AcidPool",
		Id = nextPoolId,
		Position = center,
		Radius = stats.AcidRadius,
		Duration = stats.AcidDuration,
	})
end

local function updatePools(now)
	local cfg = PU.AcidRounds
	for i = #pools, 1, -1 do
		local pool = pools[i]
		if now >= pool.Until or not stillActive(pool.Match, pool.Owner) then
			table.remove(pools, i)
			if now < pool.Until then
				sendFx(pool.Match, { Type = "AcidPoolEnd", Id = pool.Id })
			end
		elseif now >= pool.NextTick then
			pool.NextTick += cfg.TickInterval
			for _, target in ipairs(getTargets(pool.Owner, pool.Match)) do
				local torso = getTorso(target.Model)
				if torso then
					local offset = torso.Position - pool.Position
					if Util.flat(offset).Magnitude <= pool.Radius and offset.Y > -2 and offset.Y < cfg.Height then
						damageTarget(pool.Match, pool.Owner, pool.Stats, target, cfg.TickDamage * pool.Mult, {
							Splash = true,
							Position = torso.Position,
							Dot = true,
							DotSource = pool,
						})
					end
				end
			end
		end
	end
end

local function updateBleeds(now)
	local cfg = PU.SerratedRounds
	for key, bleed in pairs(bleeds) do
		if bleed.Left <= 0.01 or not stillActive(bleed.Match, bleed.Attacker) or not targetAlive(bleed.Target) then
			bleeds[key] = nil
		elseif now >= bleed.NextTick then
			bleed.NextTick += cfg.TickInterval
			local damage = math.min(bleed.Left, bleed.Rate * cfg.TickInterval)
			bleed.Left -= damage
			local torso = getTorso(bleed.Target.Model)
			damageTarget(bleed.Match, bleed.Attacker, bleed.Stats, bleed.Target, damage, {
				Splash = true,
				Position = torso and torso.Position or nil,
				Dot = true,
				DotSource = bleed,
			})
		end
	end
end

----------------------------------------------------------------------------
-- Fire
----------------------------------------------------------------------------

-- Checks a client's hit claim. Returns the target's BasePart if it's believable.
local function validateClaim(claim, model, worldPath, homing)
	if typeof(claim) ~= "table" or typeof(claim.Part) ~= "string" then
		return nil
	end
	if not Util.isFiniteVector3(claim.Point) then
		return nil
	end
	local part = model:FindFirstChild(claim.Part)
	if not part or not part:IsA("BasePart") then
		return nil
	end

	-- 1) the claimed point must be on the server's bullet path
	local pathTolerance = W.ClaimPathTolerance + (homing and 2 or 0)
	if Ballistics.DistanceToPath(worldPath, claim.Point) > pathTolerance then
		return nil
	end

	-- 2) and near where the body part actually is right now
	local root = model:FindFirstChild("HumanoidRootPart")
	local speed = root and root.AssemblyLinearVelocity.Magnitude or 0
	local targetTolerance = W.ClaimTargetTolerance + speed * W.ClaimSpeedAllowance + part.Size.Magnitude * 0.5
	if (claim.Point - part.Position).Magnitude > targetTolerance then
		return nil
	end
	return part
end

local function onFire(player, origin, direction, claims)
	-- 1) argument sanity
	if not Util.isFiniteVector3(origin) or not Util.isFiniteVector3(direction) then
		return
	end
	if direction.Magnitude < 0.5 or direction.Magnitude > 1.5 then
		return
	end
	-- client hit claims arrive as a list of { Index, Model, Part, Point }
	local claimByBullet = {}
	if typeof(claims) == "table" then
		for _, claim in ipairs(claims) do
			if typeof(claim) == "table" and typeof(claim.Index) == "number" then
				claimByBullet[claim.Index] = claim
			end
		end
	end

	-- 2) shooter state. No match = lobby practice range (dummies only).
	local match = MatchService.GetMatch(player)
	if match and not match:IsFighting() then
		return
	end
	local humanoid, character = CharacterService.GetAliveHumanoid(player)
	if not humanoid or character:GetAttribute("Frozen") then
		return
	end
	if character:GetAttribute("Weapon") == "Knife" then
		return -- the rifle is put away
	end
	local head = character:FindFirstChild("Head")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not head or not root then
		return
	end
	local stats = getStats(player, match)

	-- 3) fire rate
	local now = os.clock()
	local boltTime = stats.BoltTime
	if (bulletTimeUntil[player] or 0) > now then
		boltTime /= PU.BulletTime.BoltSpeedScale
	end
	-- DOUBLE TAP: a follow-up shot only needs the quick bolt
	local required = boltTime
	if stats.DoubleTap and quickShotReady[player] then
		required = math.min(required, PU.DoubleTap.QuickBolt)
	end
	local previous = lastFire[player]
	if previous and now - previous < required * W.FireRateTolerance then
		return
	end

	-- 4) origin must be near the head
	local tolerance = W.OriginTolerance + root.AssemblyLinearVelocity.Magnitude * W.OriginSpeedAllowance
	if (origin - head.Position).Magnitude > tolerance then
		if Config.Debug.LogRejectedShots then
			warn(("[Combat] rejected shot from %s: origin %.1f studs from head"):format(
				player.Name,
				(origin - head.Position).Magnitude
			))
		end
		return
	end
	lastFire[player] = now

	-- DEADEYE: scoped (and not firing) for the charge time = a charged shot
	local deadeye = 1
	if stats.DeadeyeBonus > 0 and scopedSince[player] then
		local chargedFrom = math.max(scopedSince[player], lastShot[player] or 0)
		-- (small fixed slack for network jitter: a % slack would let every
		-- full-cadence scoped shot count, as the bolt time is close to the charge time)
		if now - chargedFrom >= PU.Deadeye.ChargeTime - 0.1 then
			deadeye = 1 + stats.DeadeyeBonus
		end
	end
	lastShot[player] = now

	-- DOUBLE TAP: a full-bolt shot grants a quick follow-up; using it spends it
	local animBolt = boltTime
	if stats.DoubleTap then
		local wasQuick = previous ~= nil and now - previous < boltTime * W.FireRateTolerance
		if quickShotReady[player] and wasQuick then
			quickShotReady[player] = nil
		else
			quickShotReady[player] = true
			animBolt = PU.DoubleTap.QuickBolt
			Remotes.Get("Buff"):FireClient(player, { Type = "Rechamber", Quick = true })
		end
	end

	-- everyone's game plays the shot on your character (recoil + bolt)
	character:SetAttribute("BoltTime", animBolt)
	character:SetAttribute("Shot", ((character:GetAttribute("Shot") or 0) + 1) % 1000)

	-- 5) trace every bullet on the server
	local targets = getTargets(player, match)
	local homingTargets = {}
	for _, target in ipairs(targets) do
		local torso = getTorso(target.Model)
		if torso then
			table.insert(homingTargets, torso.Position)
		end
	end
	local exclude = buildExclude(player)
	local mult = shotMultiplier(stats, character) * deadeye
	local shardBudget = { Left = PU.Shrapnel.MaxShardsPerShot }
	local shardSegments = {}
	local zapped = {}
	local anyHit = false
	local hitOnce = {} -- [model] = true: on-hit effects apply once per target per shot

	local fx = {}
	for i, dir in ipairs(Ballistics.GetShotDirections(direction.Unit, stats.Bullets)) do
		local sim = Ballistics.Simulate({
			Origin = origin,
			Direction = dir,
			Stats = stats,
			Exclude = exclude,
			HomingTargets = homingTargets,
		})

		local hitTarget, hitPart, hitPos, hops
		if sim.Hit then
			local model = sim.Hit.Model
			if model:GetAttribute("Decoy") then
				popDecoy(model)
			else
				hitTarget = targetForModel(targets, model)
				if hitTarget then
					hitPart, hitPos, hops = sim.Hit.Part, sim.Hit.Position, sim.Hit.Hops
				end
			end
		end

		-- Lag compensation: trust a believable client claim over a server
		-- miss or body shot (never over a server headshot).
		local claim = claimByBullet[i]
		local claimTarget = claim and typeof(claim.Model) == "Instance" and targetForModel(targets, claim.Model)
		local worldPath
		if claimTarget and not (hitPart and Util.hitZone(hitPart.Name) == "Head") then
			worldPath = Ballistics.Simulate({
				Origin = origin,
				Direction = dir,
				Stats = stats,
				Exclude = exclude,
				HomingTargets = homingTargets,
				IgnoreTargets = true,
			})
			local claimed = validateClaim(claim, claimTarget.Model, worldPath, stats.Homing)
			if claimed then
				local _, _, claimHops = Ballistics.ClosestOnPath(worldPath, claim.Point)
				hitTarget, hitPart, hitPos, hops = claimTarget, claimed, claim.Point, claimHops
			end
		end

		if hitTarget then
			anyHit = true
			local damage, headshot = bulletDamage(hitPart, hops, stats, mult, (hitPos - origin).Magnitude)
			damageTarget(match, player, stats, hitTarget, damage, { Headshot = headshot, Position = hitPos })
			if not hitOnce[hitTarget.Model] then
				hitOnce[hitTarget.Model] = true
				onBulletHit(match, player, stats, mult, hitTarget, dir)
			end
		elseif stats.StaticChargeDamage > 0 then
			staticCharge(match, player, stats, mult, targets, sim, exclude, zapped)
		end

		if stats.Explosive then
			explode(match, player, stats, mult, targets, hitPos or sim.EndPosition, hitTarget and hitTarget.Model)
		end
		-- ACID ROUNDS: one pool per trigger pull, where the first bullet landed
		if stats.AcidPool and i == 1 then
			local landing = hitPos or sim.EndPosition
			if landing and (landing - origin).Magnitude < W.MaxRange - 1 then
				spawnPool(match, player, stats, mult, landing, targets)
			end
		end
		if stats.ShrapnelCount > 0 then
			for _, seg in ipairs(shrapnel(match, player, stats, mult, targets, sim.Impacts, exclude, shardBudget)) do
				table.insert(shardSegments, seg)
			end
		end

		table.insert(fx, {
			Segments = sim.Segments,
			Passes = sim.Passes,
			EndPosition = hitPos or sim.EndPosition,
			EndNormal = sim.EndNormal,
			HitPlayer = hitPart ~= nil,
		})
	end

	if #shardSegments > 0 then
		sendFx(match, { Type = "Shards", Segments = shardSegments })
	end

	-- HAIR TRIGGER: any hit re-chambers the rifle straight away
	if anyHit and stats.HairTrigger then
		lastFire[player] = now - boltTime
		Remotes.Get("Buff"):FireClient(player, { Type = "Rechamber" })
	end

	-- SONAR: the opponent sees where this shot came from, through walls
	if match then
		local opponent = match:GetOpponent(player)
		local opponentStats = match:GetStats(opponent)
		if opponent.Parent and opponentStats.SonarTime > 0 then
			Remotes.Get("Effect"):FireClient(opponent, {
				Type = "Reveal",
				Target = character,
				Position = head.Position,
				Duration = opponentStats.SonarTime,
			})
		end
	end

	-- Let others draw this shot (the shooter already drew it locally):
	-- the opponent in a match, everyone else in the lobby when practising.
	local shotFx = Remotes.Get("ShotFx")
	if match then
		local opponent = match:GetOpponent(player)
		if opponent.Parent then
			shotFx:FireClient(opponent, player.UserId, fx, stats.Explosive)
		end
	else
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player and not MatchService.GetMatch(other) then
				shotFx:FireClient(other, player.UserId, fx, stats.Explosive)
			end
		end
	end
end

-- Players send where they're looking (up/down) so others see them aim.
local function onAim(player, pitch)
	if typeof(pitch) ~= "number" or pitch ~= pitch then
		return
	end
	local character = player.Character
	if character then
		character:SetAttribute("AimPitch", math.clamp(pitch, -1.4, 1.4))
	end
end

----------------------------------------------------------------------------
-- Abilities
----------------------------------------------------------------------------
local function spawnDecoy(player, match, direction)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local cfg = PU.Decoy

	character.Archivable = true
	local decoy = character:Clone()
	character.Archivable = false
	decoy.Name = "Decoy"
	decoy:SetAttribute("Decoy", true)
	decoy:SetAttribute("OwnerUserId", player.UserId)

	-- the decoy only holds what you're holding, and keeps the shape of your body
	local unused = decoy:FindFirstChild(character:GetAttribute("Weapon") == "Knife" and "WorldGun" or "WorldKnife")
	if unused then
		unused:Destroy()
	end
	for _, name in ipairs({ "HitboxHead", "HitboxTorso", "HitboxLegs" }) do
		local box = decoy:FindFirstChild(name)
		if box then
			box:Destroy() -- (the decoy's own body parts are what you can shoot)
		end
	end
	for _, item in ipairs(decoy:GetDescendants()) do
		if item:IsA("Script") or item:IsA("LocalScript") or item:IsA("Humanoid") or item:IsA("Constraint") then
			item:Destroy()
		end
	end
	for _, part in ipairs(decoy:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanTouch = false
			part.Material = Enum.Material.SmoothPlastic
			if part.Name ~= "HumanoidRootPart" and part.Name ~= "WeaponRoot" and part.Name ~= "BoltRoot" then
				part.Color = Config.Palette.Hologram
				part.Transparency = 0.3
				part.CanQuery = part.Parent == decoy -- body parts can be shot
			end
		end
	end
	decoy.Parent = decoyFolder

	local dir = Util.safeUnit(Util.flat(direction), Util.flat(root.CFrame.LookVector).Unit)
	local pivot = CFrame.lookAt(root.Position, root.Position + dir)
	decoy:PivotTo(pivot)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { decoyFolder, effectsFolder, character, barrierFolder } -- (decoys run through domes)

	local alive = 0
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		alive += dt
		local roundOver = match and (match.Finished or match.Phase ~= "Fight")
		local leftLobby = not match and MatchService.GetMatch(player) ~= nil
		if not decoy.Parent or alive > cfg.Lifetime or roundOver or leftLobby then
			connection:Disconnect()
			popDecoy(decoy)
			return
		end
		local position = pivot.Position
		-- stop at walls
		local wall = workspace:Raycast(position, dir * (cfg.Speed * dt + 1.5), params)
		if not wall then
			position += dir * cfg.Speed * dt
		end
		-- follow the floor (and fall off ledges)
		local floor = workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -40, 0), params)
		if floor then
			position = Vector3.new(position.X, floor.Position.Y + 3, position.Z)
		end
		local bob = math.abs(math.sin(alive * 12)) * 0.35
		pivot = CFrame.lookAt(position, position + dir)
		decoy:PivotTo(pivot + Vector3.new(0, bob, 0))
	end)
end

-- Several decoys fan out around the chosen direction (one per stack).
local function spawnDecoys(player, match, direction, count)
	for _, d in ipairs(decoyFolder:GetChildren()) do
		if d:GetAttribute("OwnerUserId") == player.UserId then
			d:Destroy()
		end
	end
	local spread = math.rad(PU.Decoy.SpreadDegrees)
	for i = 1, count do
		local offset = (i - (count + 1) / 2) * spread
		local dir = CFrame.fromAxisAngle(Vector3.yAxis, offset):VectorToWorldSpace(direction)
		spawnDecoy(player, match, dir)
	end
end

-- Shows an ability effect to everyone who should see it except its user
-- (they already drew it themselves).
local function sendFxToOthers(player, match, data)
	local remote = Remotes.Get("Effect")
	if match then
		local opponent = match:GetOpponent(player)
		if opponent.Parent then
			remote:FireClient(opponent, data)
		end
		return
	end
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and not MatchService.GetMatch(other) then
			remote:FireClient(other, data)
		end
	end
end

-- Everyone who can fight: real players and bots.
local function everyone()
	local list = Players:GetPlayers()
	for bot in pairs(CharacterService.Bots) do
		table.insert(list, bot)
	end
	return list
end

-- BARRIER DOME: a shell around you that stops every bullet (both ways)
-- for a few seconds. It's a plain queryable part, so the shared
-- Ballistics code treats it like a wall: Ghost Round passes it, Ricochet
-- bounces off it, explosions still splash through.
local function spawnBarrier(player, match, position, stats)
	for i = #barriers, 1, -1 do
		if barriers[i].Owner == player then
			barriers[i].Part:Destroy()
			table.remove(barriers, i)
		end
	end
	local radius = stats.BarrierRadius
	local dome = Instance.new("Part")
	dome.Name = "BarrierDome"
	dome.Shape = Enum.PartType.Ball
	dome.Size = Vector3.one * radius * 2
	dome.CFrame = CFrame.new(position)
	dome.Anchored = true
	dome.CanCollide = false -- you walk through it...
	dome.CanTouch = false
	dome.CanQuery = true -- ...bullets don't
	dome.CastShadow = false
	dome.Material = Enum.Material.ForceField
	dome.Color = match and match:ColorFor(player) or Config.Palette.Hologram
	dome:SetAttribute("OwnerUserId", player.UserId)
	dome.Parent = barrierFolder
	table.insert(barriers, { Part = dome, Owner = player, Match = match, Until = os.clock() + stats.BarrierDuration })
	sendFx(match, { Type = "Barrier", Position = position, Radius = radius, Duration = stats.BarrierDuration })
end

-- SMOKE GRENADE: a cloud of solid puffs (they hide you, and highlights,
-- like walls do) that bullets pass straight through (CanQuery = false).
local function spawnSmoke(owner, match, center, radius, duration)
	local cloud = Instance.new("Model")
	cloud.Name = "SmokeCloud"
	local rng = Random.new()
	local count = 12
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + rng:NextNumber(0, 0.6)
		local distance = i <= 2 and rng:NextNumber(0, radius * 0.2) or radius * rng:NextNumber(0.35, 0.75)
		local size = radius * (i <= 2 and 1.5 or rng:NextNumber(0.8, 1.2))
		local height = size * 0.38 + rng:NextNumber(0, radius * 0.35)
		local puff = Instance.new("Part")
		puff.Name = "Puff"
		puff.Shape = Enum.PartType.Ball
		puff.Size = Vector3.one * 2
		puff.CFrame = CFrame.new(center + Vector3.new(math.cos(angle) * distance, height, math.sin(angle) * distance))
		puff.Anchored = true
		puff.CanCollide = false
		puff.CanQuery = false -- bullets fly straight through smoke
		puff.CanTouch = false
		puff.CastShadow = false
		puff.Material = Enum.Material.SmoothPlastic
		puff.Color = Color3.fromRGB(206, 210, 218):Lerp(Color3.fromRGB(240, 242, 246), rng:NextNumber())
		puff.Parent = cloud
		TweenService:Create(puff, TweenInfo.new(rng:NextNumber(0.5, 0.9), Enum.EasingStyle.Quint), {
			Size = Vector3.one * size,
		}):Play()
	end
	cloud:SetAttribute("OwnerUserId", owner.UserId)
	cloud.Parent = smokeFolder
	table.insert(smokes, { Model = cloud, Owner = owner, Match = match, Until = os.clock() + duration })
end

local function throwSmoke(player, match, character, direction, stats)
	local head = character:FindFirstChild("Head")
	if not head then
		return
	end
	local cfg = PU.SmokeGrenade
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = buildExclude(player)
	table.insert(exclude, barrierFolder)
	table.insert(exclude, smokeFolder)
	for _, target in ipairs(getTargets(player, match)) do
		table.insert(exclude, target.Model)
	end
	params.FilterDescendantsInstances = exclude
	local from = head.Position
	local ray = workspace:Raycast(from, direction * cfg.Range, params)
	local landing = ray and (ray.Position + ray.Normal * 1.5) or (from + direction * cfg.Range)
	local floor = workspace:Raycast(landing + Vector3.new(0, 1, 0), Vector3.new(0, -60, 0), params)
	local center = floor and floor.Position or landing
	sendFx(match, { Type = "SmokeThrow", From = from, To = center })
	local radius, duration = stats.SmokeRadius, stats.SmokeDuration
	task.delay(0.4, function()
		if stillActive(match, player) then
			spawnSmoke(player, match, center, radius, duration)
		end
	end)
end

-- RECALL: the client rewinds itself (it owns its character); the server
-- checks you really were there a moment ago and heals back what you lost.
local function recall(player, match, character, humanoid, root, data, stats)
	local cfg = PU.Recall
	local now = os.clock()
	-- the past sample closest to where the client says it went (it must be a
	-- real, not-too-recent position). Its health is what the recall restores,
	-- so claiming a recent spot can't heal back what you lost 3s ago.
	local past, bestDistance = nil, cfg.PositionTolerance
	for _, sample in ipairs(history[player] or {}) do
		if sample.Character == character and now - sample.T >= 0.3 then
			local distance = (sample.Position - data.To).Magnitude
			-- (oldest first: a newer sample only wins if clearly closer, so
			-- recalling to a spot you stood on for a while picks the old one)
			if (not past and distance <= bestDistance) or (past and distance < bestDistance - 1) then
				past, bestDistance = sample, distance
			end
		end
	end
	if not past then
		return
	end
	if past and past.Health > humanoid.Health then
		local heal = math.min(past.Health - humanoid.Health, stats.RecallHealCap)
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + heal)
	end
	local from = Util.isFiniteVector3(data.From) and data.From or root.Position
	sendFxToOthers(player, match, { Type = "Recall", From = from, To = data.To, UserId = player.UserId })
end

local function onAbility(player, name, data)
	if typeof(name) ~= "string" then
		return
	end
	if typeof(data) ~= "table" then
		data = {}
	end
	-- abilities work in a live round, or in the lobby with Power-Up Lab picks
	local match = MatchService.GetMatch(player)
	if match and not match:IsFighting() then
		return
	end
	local humanoid, character = CharacterService.GetAliveHumanoid(player)
	if not humanoid then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local stats = getStats(player, match)
	local opponent = match and match:GetOpponent(player)

	if name == "PhantomDash" and stats.PhantomDash then
		if useCooldown(player, name, 0.5) then
			CharacterService.MakeInvisible(player, stats.PhantomTime)
		end
	elseif name == "Decoy" and stats.Decoy then
		if Util.isFiniteVector3(data.Direction) and useCooldown(player, name, PU.Decoy.Cooldown * 0.95) then
			spawnDecoys(player, match, Util.safeUnit(Util.flat(data.Direction), Vector3.zAxis), stats.DecoyCount)
		end
	elseif name == "BulletTime" and stats.BulletTime then
		if useCooldown(player, name, PU.BulletTime.Cooldown * 0.9) then
			bulletTimeUntil[player] = os.clock() + stats.BulletTimeDuration + 0.25
		end
	elseif name == "Shockwave" and stats.ShockwaveLanding and root then
		if useCooldown(player, name, PU.ShockwaveLanding.Cooldown * 0.9) then
			local radius = stats.ShockwaveRadius
			sendFx(match, { Type = "Shockwave", Position = root.Position, Radius = radius })
			for _, target in ipairs(getTargets(player, match)) do
				local torso = getTorso(target.Model)
				if torso then
					local offset = torso.Position - root.Position
					if offset.Magnitude <= radius then
						if stats.ShockwaveDamage > 0 then
							damageTarget(match, player, stats, target, stats.ShockwaveDamage * stats.DamageMultiplier, {
								Splash = true,
								Position = torso.Position,
							})
						end
						if target.Player then
							local away = Util.safeUnit(Util.flat(offset), Vector3.xAxis)
							knockback(target.Player, (away + Vector3.new(0, 0.7, 0)).Unit * stats.ShockwaveKnockback)
						end
					end
				end
			end
		end
	elseif name == "Blink" and stats.Blink and root then
		-- the client moves itself (it owns its character); we just check it's
		-- plausible and show the effect to everyone else
		if Util.isFiniteVector3(data.From) and Util.isFiniteVector3(data.To) then
			if (data.To - data.From).Magnitude <= stats.BlinkDistance + 12 and useCooldown(player, name, stats.BlinkCooldown * 0.85) then
				local fxData = { Type = "Blink", From = data.From, To = data.To, UserId = player.UserId }
				if match then
					if opponent.Parent then
						Remotes.Get("Effect"):FireClient(opponent, fxData)
					end
				else
					sendFx(nil, fxData)
				end
			end
		end
	elseif name == "AirDash" and stats.AirDash and root then
		if useCooldown(player, name, PU.AirDash.Cooldown * 0.5) then
			sendFxToOthers(player, match, { Type = "Dash", Position = root.Position, UserId = player.UserId })
		end
	elseif name == "Barrier" and stats.Barrier and root then
		if useCooldown(player, name, PU.BarrierDome.Cooldown * 0.9) then
			spawnBarrier(player, match, root.Position, stats)
		end
	elseif name == "Smoke" and stats.Smoke and root then
		local dir = data.Direction
		if Util.isFiniteVector3(dir) and dir.Magnitude > 0.5 and useCooldown(player, name, stats.SmokeCooldown * 0.9) then
			throwSmoke(player, match, character, dir.Unit, stats)
		end
	elseif name == "Recall" and stats.Recall and root then
		if Util.isFiniteVector3(data.To) and useCooldown(player, name, stats.RecallCooldown * 0.85) then
			recall(player, match, character, humanoid, root, data, stats)
		end
	elseif name == "GrappleStart" and stats.Grapple and root then
		if Util.isFiniteVector3(data.Point) and (data.Point - root.Position).Magnitude < Config.Movement.GrappleRange + 30 then
			if opponent and opponent.Parent then
				Remotes.Get("Effect"):FireClient(opponent, { Type = "Grapple", UserId = player.UserId, Point = data.Point })
			end
		end
	elseif name == "GrappleEnd" then
		if opponent and opponent.Parent then
			Remotes.Get("Effect"):FireClient(opponent, { Type = "GrappleEnd", UserId = player.UserId })
		end
	end
end

-- Forget everything about a player / bot (bots aren't in PlayerRemoving).
----------------------------------------------------------------------------
-- Knife
----------------------------------------------------------------------------
local function flatUnit(v)
	local flat = Vector3.new(v.X, 0, v.Z)
	return flat.Magnitude > 1e-3 and flat.Unit or nil
end

local function onMelee(player, kind, targetModel, look)
	local K = Config.Knife
	if not K.Enabled or (kind ~= "Slash" and kind ~= "Stab") then
		return
	end
	if not Util.isFiniteVector3(look) or look.Magnitude < 0.5 or look.Magnitude > 1.5 then
		return
	end
	look = look.Unit
	local match = MatchService.GetMatch(player)
	if match and not match:IsFighting() then
		return
	end
	local humanoid, character = CharacterService.GetAliveHumanoid(player)
	if not humanoid or character:GetAttribute("Frozen") or character:GetAttribute("Weapon") ~= "Knife" then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local head = character:FindFirstChild("Head")
	if not root or not head then
		return
	end
	-- the knife has to have been out for a moment
	local since = character:GetAttribute("WeaponSince") or 0
	if workspace:GetServerTimeNow() - since < K.EquipTime * 0.6 then
		return
	end
	-- swing rate: the client reports each swing at its hit moment, so the gap
	-- between two reports is (previous swing's length - its hit time + this hit time)
	local now = os.clock()
	local function hitAt(k)
		return k == "Stab" and K.StabHitAt or K.SlashHitAt
	end
	local last = lastMelee[player]
	if last then
		local prevLength = last.Kind == "Stab" and K.StabTime or K.SlashTime
		if now - last.Time < (prevLength - hitAt(last.Kind) + hitAt(kind)) * 0.75 then
			return
		end
	end
	lastMelee[player] = { Time = now, Kind = kind }
	-- everyone sees the swing (BodyAnimator plays it on your character)
	character:SetAttribute("SwingKind", kind)
	character:SetAttribute("Swing", ((character:GetAttribute("Swing") or 0) + 1) % 1000)

	if typeof(targetModel) ~= "Instance" then
		return -- a miss
	end
	local target = targetForModel(getTargets(player, match), targetModel)
	local torso = target and getTorso(target.Model)
	if not torso then
		return
	end
	-- the client's look must roughly match where the character faces
	local facing = flatUnit(root.CFrame.LookVector)
	local flatLook = flatUnit(look)
	if facing and flatLook and facing:Dot(flatLook) < 0.4 then
		return
	end
	-- range (with an allowance for both of you moving)
	local victimRoot = target.Model:FindFirstChild("HumanoidRootPart") or torso
	local range = (kind == "Stab" and K.StabRange or K.SlashRange)
		+ 2
		+ math.min(root.AssemblyLinearVelocity.Magnitude, 60) * 0.12 -- capped: clients own their physics
		+ math.min(victimRoot.AssemblyLinearVelocity.Magnitude, 60) * 0.12
	local offset = torso.Position - head.Position
	if offset.Magnitude > range then
		return
	end
	-- facing it
	if offset.Magnitude > 2 and look:Dot(offset.Unit) < math.cos(math.rad(K.HitAngle + 15)) then
		return
	end
	-- nothing solid in between
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = buildExclude(player)
	local hit = workspace:Raycast(head.Position, offset, params)
	if hit and not hit.Instance:IsDescendantOf(target.Model) then
		return
	end
	-- backstab: you're behind them
	local backstab = false
	local victimFacing = flatUnit(victimRoot.CFrame.LookVector)
	local fromVictim = flatUnit(root.Position - victimRoot.Position)
	if victimFacing and fromVictim and victimFacing:Dot(fromVictim) < -math.cos(math.rad(K.BackstabAngle)) then
		backstab = true
	end
	local stats = getStats(player, match)
	-- KEEN EDGE: sharper knife
	local damage = backstab and K.BackstabDamage
		or (kind == "Stab" and K.StabDamage or K.SlashDamage) * stats.KnifeDamageMultiplier
	damageTarget(match, player, stats, target, damage, {
		Position = torso.Position,
		Melee = true,
		Backstab = backstab,
	})
	-- BLOODLUST: knife hits give shield too
	if stats.ShieldOnHit > 0 then
		addShield(player, stats, stats.ShieldOnHit)
	end
	-- HUNTER'S KNIFE: a knife hit = a burst of speed
	if stats.KnifeHitBoost then
		Remotes.Get("Buff"):FireClient(player, {
			Type = "SpeedBoost",
			Multiplier = PU.HuntersKnife.BoostMultiplier,
			Duration = PU.HuntersKnife.BoostTime,
		})
	end
end

-- Cosmetic animation events everyone should see on your character:
-- "Inspect" (with the variant) and "Scope" (true / false).
local lastAnim = {}
local INSPECT_VARIANTS = { Rifle = true, Knife = true }
local function onAnim(player, kind, value, variant)
	local character = player.Character
	if not character or typeof(kind) ~= "string" then
		return
	end
	if kind == "Scope" then
		-- a state, not an event: always take the latest (it's only sent on change)
		if typeof(value) == "boolean" then
			character:SetAttribute("Scoped", value)
			-- DEADEYE charges while you stay scoped
			scopedSince[player] = value and (scopedSince[player] or os.clock()) or nil
		end
		return
	end
	local now = os.clock()
	lastAnim[player] = lastAnim[player] or {}
	if now - (lastAnim[player][kind] or 0) < 0.25 then
		return
	end
	lastAnim[player][kind] = now
	if kind == "Inspect" and INSPECT_VARIANTS[value] then
		-- which rifle inspect (1-3): set before the counter so others read it with it
		local ok = typeof(variant) == "number" and variant == variant -- (not NaN)
		character:SetAttribute("InspectVariant", ok and math.clamp(math.floor(variant), 1, 3) or 1)
		character:SetAttribute("Inspect", ((character:GetAttribute("Inspect") or 0) + 1) % 1000)
	end
end

local lastEquip = {}
local function onEquip(player, weapon)
	local now = os.clock()
	if typeof(weapon) == "string" and now - (lastEquip[player] or 0) > 0.1 then
		lastEquip[player] = now
		CharacterService.SetWeapon(player, weapon)
	end
end

-- Wave 2 per-player state (shared by Forget and PlayerRemoving).
local function forgetWave2(player)
	lastShot[player] = nil
	scopedSince[player] = nil
	quickShotReady[player] = nil
	lastHurt[player] = nil
	history[player] = nil
	bleeds[player] = nil
	for key, bleed in pairs(bleeds) do
		if bleed.Attacker == player then
			bleeds[key] = nil
		end
	end
	for i = #barriers, 1, -1 do
		if barriers[i].Owner == player then
			barriers[i].Part:Destroy()
			table.remove(barriers, i)
		end
	end
	for i = #smokes, 1, -1 do
		if smokes[i].Owner == player then
			smokes[i].Model:Destroy()
			table.remove(smokes, i)
		end
	end
	-- (acid pools stop by themselves once their owner is gone)
end

function CombatService.Forget(player)
	lastMelee[player] = nil
	lastFire[player] = nil
	cooldowns[player] = nil
	bulletTimeUntil[player] = nil
	markedUntil[player] = nil
	forgetWave2(player)
end

----------------------------------------------------------------------------
-- Wave 2 per-frame upkeep: acid pools, bleeds, domes, smoke, regeneration,
-- and the short position/health history Recall checks against.
----------------------------------------------------------------------------
local nextHistory = 0

local function updateBarriers(now)
	for i = #barriers, 1, -1 do
		local barrier = barriers[i]
		if now >= barrier.Until or not barrier.Part.Parent or not stillActive(barrier.Match, barrier.Owner) then
			table.remove(barriers, i)
			local part = barrier.Part
			if part.Parent then
				part.CanQuery = false -- stops blocking straight away
				TweenService:Create(part, TweenInfo.new(0.25), { Size = Vector3.one * 0.5 }):Play()
				task.delay(0.3, function()
					part:Destroy()
				end)
			end
		end
	end
end

local function updateSmokes(now)
	for i = #smokes, 1, -1 do
		local cloud = smokes[i]
		if not cloud.Fading and (now >= cloud.Until - 1 or not stillActive(cloud.Match, cloud.Owner)) then
			cloud.Fading = true
			cloud.Until = math.min(cloud.Until, now + 1)
			for _, puff in ipairs(cloud.Model:GetChildren()) do
				if puff:IsA("BasePart") then
					TweenService:Create(puff, TweenInfo.new(1), { Transparency = 1 }):Play()
				end
			end
		end
		if now >= cloud.Until then
			table.remove(smokes, i)
			cloud.Model:Destroy()
		end
	end
end

local function updatePlayers(now, dt)
	local sample = now >= nextHistory
	if sample then
		nextHistory = now + 0.1
	end
	for _, player in ipairs(everyone()) do
		local match = MatchService.GetMatch(player)
		if match or not Util.isBot(player) then
			local stats = getStats(player, match)
			local humanoid, character = CharacterService.GetAliveHumanoid(player)

			-- REGENERATION (live rounds, or the lobby)
			if humanoid and stats.RegenRate > 0 and (not match or match:IsFighting()) then
				if now - (lastHurt[player] or 0) >= stats.RegenDelay and humanoid.Health < humanoid.MaxHealth then
					humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + stats.RegenRate * dt)
				end
			end

			-- RECALL history
			if sample then
				local list = history[player]
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if stats.Recall and root then
					list = list or {}
					history[player] = list
					table.insert(list, { T = now, Position = root.Position, Health = humanoid.Health, Character = character })
				end
				if list then
					while list[1] and now - list[1].T > PU.Recall.Rewind + 1.5 do
						table.remove(list, 1)
					end
					if not stats.Recall then
						history[player] = nil
					end
				end
			end
		end
	end
end

local function upkeep(dt)
	local now = os.clock()
	updatePools(now)
	updateBleeds(now)
	updateBarriers(now)
	updateSmokes(now)
	updatePlayers(now, dt)
end

-- Bots shoot through the exact same validation and damage code as players.
function CombatService.BotFire(bot, origin, direction)
	onFire(bot, origin, direction, nil)
end

-- Seconds a shooter must wait between shots (their power-ups included).
function CombatService.GetBoltTime(player, match)
	return getStats(player, match).BoltTime
end

----------------------------------------------------------------------------
-- Init
----------------------------------------------------------------------------
function CombatService.Init()
	effectsFolder = Instance.new("Folder")
	effectsFolder.Name = "Effects"
	effectsFolder.Parent = workspace

	decoyFolder = Instance.new("Folder")
	decoyFolder.Name = "Decoys"
	decoyFolder.Parent = workspace

	barrierFolder = Instance.new("Folder")
	barrierFolder.Name = "Barriers"
	barrierFolder.Parent = workspace

	smokeFolder = Instance.new("Folder")
	smokeFolder.Name = "Smoke"
	smokeFolder.Parent = workspace

	RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(upkeep, dt)
		if not ok then
			warn("[Combat] upkeep:", err)
		end
	end)

	Remotes.Get("Fire").OnServerEvent:Connect(onFire)
	Remotes.Get("Ability").OnServerEvent:Connect(onAbility)
	Remotes.Get("Aim").OnServerEvent:Connect(onAim)
	Remotes.Get("Melee").OnServerEvent:Connect(onMelee)
	Remotes.Get("Equip").OnServerEvent:Connect(onEquip)
	Remotes.Get("Anim").OnServerEvent:Connect(onAnim)

	Players.PlayerRemoving:Connect(function(player)
		lastAnim[player] = nil
		lastEquip[player] = nil
		lastMelee[player] = nil
		lastFire[player] = nil
		cooldowns[player] = nil
		bulletTimeUntil[player] = nil
		markedUntil[player] = nil
		forgetWave2(player)
		for _, d in ipairs(decoyFolder:GetChildren()) do
			if d:GetAttribute("OwnerUserId") == player.UserId then
				d:Destroy()
			end
		end
	end)
end

return CombatService
