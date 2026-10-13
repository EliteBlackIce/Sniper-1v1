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
	  Headshots are always an instant kill.
	  Explosions, Shrapnel and Static Charge use the same shot multiplier
	  (Glass Cannon, Sky Sniper, Momentum) and the Marked bonus.

	"Targets" are the enemy player in a match, or the practice dummies in the
	lobby, so every power-up works on the range too.

	KNIFE (onMelee): the client says what it swung at; the server checks the
	knife is out (and was drawn long enough ago), the swing timing, the
	range, that you were facing the target and could see it, then deals
	slash / stab damage. A hit from behind (backstab) is always a kill.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
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

local decoyFolder
local effectsFolder

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
	info = { Headshot = bool, Splash = bool }
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

	local before = humanoid.Health
	local after = before - amount

	-- SECOND WIND: survive lethal hits (one save per stack, each round)
	if after <= 0 then
		local victimStats = match:GetStats(victim)
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
	local dealt = before - after
	match:NoteHit(attacker, victim, info.Headshot == true)
	humanoid.Health = after

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
			})
		end
	end

	local attackerRoot = attacker and attacker.Character and attacker.Character:FindFirstChild("HumanoidRootPart")
	Remotes.Get("Damaged"):FireClient(victim, {
		From = attackerRoot and attackerRoot.Position or nil,
		Damage = dealt,
		Killed = after <= 0,
	})
	return after <= 0
end

--[[
	Damages any target (player or dummy) and handles Marked.
	info = { Headshot, Splash }
]]
local function damageTarget(match, attacker, stats, target, amount, info)
	info = info or {}
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
		})
		if killed and torso then
			sendFx(nil, { Type = "Kill", Position = torso.Position, Color = Config.Palette.PlayerB, Headshot = info.Headshot == true })
		end
	end

	if stats.MarkBonus > 0 then
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
			params.FilterDescendantsInstances = { shooterCharacter, effectsFolder, decoyFolder }
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

local function bulletDamage(part, hops, stats, mult)
	local zone = Util.hitZone(part.Name)
	if zone == "Head" then
		return W.HeadDamage, true -- always an instant kill
	end
	local base = zone == "Body" and W.BodyDamage or W.LimbDamage
	-- PINBALL: more damage for every bounce / wall pass before the hit
	return base * mult * (1 + stats.HopDamageBonus * (hops or 0)), false
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
	if lastFire[player] and now - lastFire[player] < boltTime * W.FireRateTolerance then
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
	local mult = shotMultiplier(stats, character)
	local shardBudget = { Left = PU.Shrapnel.MaxShardsPerShot }
	local shardSegments = {}
	local zapped = {}
	local anyHit = false

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
			local damage, headshot = bulletDamage(hitPart, hops, stats, mult)
			damageTarget(match, player, stats, hitTarget, damage, { Headshot = headshot, Position = hitPos })
		elseif stats.StaticChargeDamage > 0 then
			staticCharge(match, player, stats, mult, targets, sim, exclude, zapped)
		end

		if stats.Explosive then
			explode(match, player, stats, mult, targets, hitPos or sim.EndPosition, hitTarget and hitTarget.Model)
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

	-- the decoy only holds what you're holding
	local unused = decoy:FindFirstChild(character:GetAttribute("Weapon") == "Knife" and "WorldGun" or "WorldKnife")
	if unused then
		unused:Destroy()
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
			if part.Name ~= "HumanoidRootPart" then
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
	params.FilterDescendantsInstances = { decoyFolder, effectsFolder, character }

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
	-- everyone sees the swing (CharacterPoser animates the arm)
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
	local damage = backstab and K.BackstabDamage or (kind == "Stab" and K.StabDamage or K.SlashDamage)
	local stats = getStats(player, match)
	damageTarget(match, player, stats, target, damage, {
		Position = torso.Position,
		Melee = true,
		Backstab = backstab,
	})
end

local lastEquip = {}
local function onEquip(player, weapon)
	local now = os.clock()
	if typeof(weapon) == "string" and now - (lastEquip[player] or 0) > 0.1 then
		lastEquip[player] = now
		CharacterService.SetWeapon(player, weapon)
	end
end

function CombatService.Forget(player)
	lastMelee[player] = nil
	lastFire[player] = nil
	cooldowns[player] = nil
	bulletTimeUntil[player] = nil
	markedUntil[player] = nil
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

	Remotes.Get("Fire").OnServerEvent:Connect(onFire)
	Remotes.Get("Ability").OnServerEvent:Connect(onAbility)
	Remotes.Get("Aim").OnServerEvent:Connect(onAim)
	Remotes.Get("Melee").OnServerEvent:Connect(onMelee)
	Remotes.Get("Equip").OnServerEvent:Connect(onEquip)

	Players.PlayerRemoving:Connect(function(player)
		lastEquip[player] = nil
		lastMelee[player] = nil
		lastFire[player] = nil
		cooldowns[player] = nil
		bulletTimeUntil[player] = nil
		markedUntil[player] = nil
		for _, d in ipairs(decoyFolder:GetChildren()) do
			if d:GetAttribute("OwnerUserId") == player.UserId then
				d:Destroy()
			end
		end
	end)
end

return CombatService
