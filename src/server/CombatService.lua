--[[
	CombatService.lua  (ServerScriptService.Server.CombatService)

	Everything that deals damage is decided HERE, on the server:

	FIRE VALIDATION (anti-exploit)
	  1. Arguments must be real, finite Vector3s.
	  2. The shooter must be alive, in a match, and the round must be live.
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

	Also handles: explosions, Second Wind, Vampire, decoys, Phantom Dash,
	Shockwave Landing, Bullet Time bookkeeping and grapple visuals.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Ballistics = require(ReplicatedStorage.Shared.Ballistics)
local Util = require(ReplicatedStorage.Shared.Util)
local PowerUps = require(ReplicatedStorage.Shared.PowerUps)
local CharacterService = require(script.Parent.CharacterService)
local MatchService = require(script.Parent.MatchService)
local DummyService = require(script.Parent.DummyService)

local W = Config.Weapon
local PU = Config.PowerUps

local CombatService = {}

local lastFire = {} -- [player] = os.clock() of last accepted shot
local cooldowns = {} -- [player] = { [abilityName] = os.clock() ready time }
local bulletTimeUntil = {} -- [player] = os.clock()

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

local function getTorso(character)
	return character
		and (
			character:FindFirstChild("UpperTorso")
			or character:FindFirstChild("Torso")
			or character:FindFirstChild("HumanoidRootPart")
		)
end

local function knockback(player, velocity)
	if player.Parent then
		Remotes.Get("Knockback"):FireClient(player, velocity * Config.Movement.KnockbackScale)
	end
end

local function popDecoy(decoy)
	if decoy.Parent then
		local match = MatchService.GetMatch(Players:GetPlayerByUserId(decoy:GetAttribute("OwnerUserId") or 0))
		if match then
			sendToMatch(match, "Effect", { Type = "DecoyPop", Position = decoy:GetPivot().Position })
		end
		decoy:Destroy()
	end
end

----------------------------------------------------------------------------
-- Damage
----------------------------------------------------------------------------

--[[
	Deals damage from `attacker` to `victim` inside `match`.
	info = { Headshot = bool, Splash = bool }
]]
function CombatService.Damage(match, attacker, victim, amount, info)
	info = info or {}
	if not match:IsFighting() then
		return
	end
	local humanoid = CharacterService.GetAliveHumanoid(victim)
	if not humanoid then
		return
	end

	local before = humanoid.Health
	local after = before - amount

	-- SECOND WIND: survive the first lethal hit each round
	if after <= 0 then
		local victimStats = match:GetStats(victim)
		if victimStats.SecondWind and not match.SecondWindUsed[victim] then
			match.SecondWindUsed[victim] = true
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
		})
	end

	local attackerRoot = attacker and attacker.Character and attacker.Character:FindFirstChild("HumanoidRootPart")
	Remotes.Get("Damaged"):FireClient(victim, {
		From = attackerRoot and attackerRoot.Position or nil,
		Damage = dealt,
		Killed = after <= 0,
	})
end

local function damageForPart(part)
	local zone = Util.hitZone(part.Name)
	if zone == "Head" then
		return W.HeadDamage, true
	elseif zone == "Body" then
		return W.BodyDamage, false
	end
	return W.LimbDamage, false
end

-- EXPLOSIVE ROUNDS: splash damage + knockback around `position`.
local function explode(match, attacker, position, directVictim)
	local cfg = PU.ExplosiveRounds
	sendToMatch(match, "Effect", { Type = "Explosion", Position = position, Radius = cfg.Radius })

	for _, player in ipairs(match.Players) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			local offset = root.Position - position
			local distance = offset.Magnitude
			if distance <= cfg.Radius then
				local away = Util.safeUnit(offset + Vector3.new(0, 2, 0), Vector3.yAxis)
				local falloff = 1 - (distance / cfg.Radius) * 0.5
				if player == attacker then
					knockback(player, away * cfg.SelfKnockback * falloff) -- no self damage
				else
					if player ~= directVictim then
						CombatService.Damage(match, attacker, player, cfg.Damage * falloff, { Splash = true })
					end
					knockback(player, away * cfg.Knockback * falloff)
				end
			end
		end
	end

	for _, decoy in ipairs(decoyFolder:GetChildren()) do
		if decoy:GetAttribute("OwnerUserId") ~= attacker.UserId then
			if (decoy:GetPivot().Position - position).Magnitude <= cfg.Radius then
				popDecoy(decoy)
			end
		end
	end
end

----------------------------------------------------------------------------
-- Fire
----------------------------------------------------------------------------

-- Checks a client's hit claim. Returns the victim's BasePart if it's believable.
local function validateClaim(claim, victimCharacter, worldPath, homing)
	if typeof(claim) ~= "table" or typeof(claim.Part) ~= "string" then
		return nil
	end
	if not Util.isFiniteVector3(claim.Point) then
		return nil
	end
	local part = victimCharacter:FindFirstChild(claim.Part)
	if not part or not part:IsA("BasePart") then
		return nil
	end

	-- 1) the claimed point must be on the server's bullet path
	local pathTolerance = W.ClaimPathTolerance + (homing and 2 or 0)
	if Ballistics.DistanceToPath(worldPath, claim.Point) > pathTolerance then
		return nil
	end

	-- 2) and near where the body part actually is right now
	local root = victimCharacter:FindFirstChild("HumanoidRootPart")
	local speed = root and root.AssemblyLinearVelocity.Magnitude or 0
	local targetTolerance = W.ClaimTargetTolerance + speed * W.ClaimSpeedAllowance + part.Size.Magnitude * 0.5
	if (claim.Point - part.Position).Magnitude > targetTolerance then
		return nil
	end
	return part
end

local PRACTICE_STATS = PowerUps.ComputeStats({}) -- lobby practice: no power-ups

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
	local practice = match == nil
	if match and not match:IsFighting() then
		return
	end
	local humanoid, character = CharacterService.GetAliveHumanoid(player)
	if not humanoid or character:GetAttribute("Frozen") then
		return
	end
	local head = character:FindFirstChild("Head")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not head or not root then
		return
	end
	local stats = practice and PRACTICE_STATS or match:GetStats(player)

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
	local opponent = match and match:GetOpponent(player)
	local victimCharacter = opponent and opponent.Character
	local victimTorso = getTorso(victimCharacter)
	local homingTargets = victimTorso and { victimTorso.Position } or {}
	local exclude = buildExclude(player)

	-- what this shooter is allowed to damage
	local function isTarget(model)
		if typeof(model) ~= "Instance" or not model:IsDescendantOf(workspace) then
			return false
		end
		if practice then
			return model:GetAttribute("Dummy") == true and not model:GetAttribute("Down")
		end
		return model == victimCharacter
	end

	local fx = {}
	for i, dir in ipairs(Ballistics.GetShotDirections(direction.Unit, stats.Bullets)) do
		local sim = Ballistics.Simulate({
			Origin = origin,
			Direction = dir,
			Stats = stats,
			Exclude = exclude,
			HomingTargets = homingTargets,
		})

		local hitModel, hitPart, hitPos
		if sim.Hit then
			local model = sim.Hit.Model
			if model:GetAttribute("Decoy") then
				popDecoy(model)
			elseif isTarget(model) then
				hitModel, hitPart, hitPos = model, sim.Hit.Part, sim.Hit.Position
			end
		end

		-- Lag compensation: trust a believable client claim over a server
		-- miss or body shot (never over a server headshot).
		local claim = claimByBullet[i]
		if claim and isTarget(claim.Model) and not (hitPart and Util.hitZone(hitPart.Name) == "Head") then
			local worldPath = Ballistics.Simulate({
				Origin = origin,
				Direction = dir,
				Stats = stats,
				Exclude = exclude,
				HomingTargets = homingTargets,
				IgnoreTargets = true,
			})
			local claimed = validateClaim(claim, claim.Model, worldPath, stats.Homing)
			if claimed then
				hitModel, hitPart, hitPos = claim.Model, claimed, claim.Point
			end
		end

		if hitPart then
			local damage, headshot = damageForPart(hitPart)
			if practice then
				local killed = DummyService.Damage(hitModel, damage)
				Remotes.Get("HitConfirm"):FireClient(player, {
					Headshot = headshot,
					Killed = killed,
					Damage = damage,
				})
			else
				CombatService.Damage(match, player, opponent, damage, { Headshot = headshot })
			end
		end
		if stats.Explosive and match then
			explode(match, player, hitPos or sim.EndPosition, hitPart and opponent or nil)
		end

		table.insert(fx, {
			Segments = sim.Segments,
			Passes = sim.Passes,
			EndPosition = hitPos or sim.EndPosition,
			EndNormal = sim.EndNormal,
			HitPlayer = hitPart ~= nil,
		})
	end

	-- Let others draw this shot (the shooter already drew it locally):
	-- the opponent in a match, everyone else in the lobby when practising.
	local shotFx = Remotes.Get("ShotFx")
	if match then
		if opponent.Parent then
			shotFx:FireClient(opponent, player.UserId, fx, stats.Explosive)
		end
	else
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player and not MatchService.GetMatch(other) then
				shotFx:FireClient(other, player.UserId, fx, false)
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

	-- clean old decoys from this player
	for _, d in ipairs(decoyFolder:GetChildren()) do
		if d:GetAttribute("OwnerUserId") == player.UserId then
			d:Destroy()
		end
	end

	character.Archivable = true
	local decoy = character:Clone()
	character.Archivable = false
	decoy.Name = "Decoy"
	decoy:SetAttribute("Decoy", true)
	decoy:SetAttribute("OwnerUserId", player.UserId)

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
		if not decoy.Parent or alive > cfg.Lifetime or match.Finished or match.Phase ~= "Fight" then
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

local function onAbility(player, name, data)
	if typeof(name) ~= "string" then
		return
	end
	if typeof(data) ~= "table" then
		data = {}
	end
	local match = MatchService.GetMatch(player)
	if not match or not match:IsFighting() then
		return
	end
	local humanoid, character = CharacterService.GetAliveHumanoid(player)
	if not humanoid then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local stats = match:GetStats(player)

	if name == "PhantomDash" and stats.PhantomDash then
		if useCooldown(player, name, Config.Movement.DashCooldown * 0.8) then
			CharacterService.MakeInvisible(player, PU.PhantomDash.InvisibleTime)
		end
	elseif name == "Decoy" and stats.Decoy then
		if Util.isFiniteVector3(data.Direction) and useCooldown(player, name, PU.Decoy.Cooldown * 0.95) then
			spawnDecoy(player, match, data.Direction)
		end
	elseif name == "BulletTime" and stats.BulletTime then
		if useCooldown(player, name, PU.BulletTime.Cooldown * 0.9) then
			bulletTimeUntil[player] = os.clock() + PU.BulletTime.Duration + 0.25
		end
	elseif name == "Shockwave" and stats.ShockwaveLanding and root then
		if useCooldown(player, name, PU.ShockwaveLanding.Cooldown * 0.9) then
			local cfg = PU.ShockwaveLanding
			sendToMatch(match, "Effect", { Type = "Shockwave", Position = root.Position, Radius = cfg.Radius })
			local opponent = match:GetOpponent(player)
			local oppRoot = opponent.Character and opponent.Character:FindFirstChild("HumanoidRootPart")
			if oppRoot then
				local offset = oppRoot.Position - root.Position
				if offset.Magnitude <= cfg.Radius then
					local away = Util.safeUnit(Util.flat(offset), Vector3.xAxis)
					knockback(opponent, (away + Vector3.new(0, 0.7, 0)).Unit * cfg.Knockback)
				end
			end
		end
	elseif name == "GrappleStart" and stats.Grapple and root then
		if Util.isFiniteVector3(data.Point) and (data.Point - root.Position).Magnitude < Config.Movement.GrappleRange + 30 then
			local opponent = match:GetOpponent(player)
			if opponent.Parent then
				Remotes.Get("Effect"):FireClient(opponent, { Type = "Grapple", UserId = player.UserId, Point = data.Point })
			end
		end
	elseif name == "GrappleEnd" then
		local opponent = match:GetOpponent(player)
		if opponent.Parent then
			Remotes.Get("Effect"):FireClient(opponent, { Type = "GrappleEnd", UserId = player.UserId })
		end
	end
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

	Players.PlayerRemoving:Connect(function(player)
		lastFire[player] = nil
		cooldowns[player] = nil
		bulletTimeUntil[player] = nil
		for _, d in ipairs(decoyFolder:GetChildren()) do
			if d:GetAttribute("OwnerUserId") == player.UserId then
				d:Destroy()
			end
		end
	end)
end

return CombatService
