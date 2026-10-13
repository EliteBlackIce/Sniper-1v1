--[[
	PowerUps.lua  (ReplicatedStorage.Shared.PowerUps)

	Every power-up is ONE data entry in the `Definitions` list below:

		Id          unique key (used in code and saved in match state)
		Name        shown on the card
		Description short text shown on the card
		Stacking    what each extra copy adds (shown on the card)
		Rarity      "Common" | "Rare" | "Epic" | "Legendary"  (see Config.Rarity)
		Tags        build categories shown on the card ("Bullets", "Damage", ...)
		IconColor   background colour of the flat icon
		Icon        list of simple shapes drawn on the icon (see "ICON SHAPES" below)
		MaxStacks   how many times a player can own it (cards for maxed power-ups
		            stop appearing). Picking it again adds a stack.
		Effect      function(stats, stacks) that changes the player's stat table.

	BUILDS
	Power-ups are designed to combine. Some examples:
	  * Pinball:    Ricochet + Pinball + Shrapnel   (every bounce adds damage AND shards)
	  * Demolition: Explosive Rounds + Shrapnel + Split Shot (a shower of blasts)
	  * Speedster:  Adrenaline + Momentum Rounds + Sky Sniper (bhop = more damage)
	  * Assassin:   Ghost Round + Wallhack Pulse + Marked (shoot through walls at marked targets)
	  * Gunslinger: Hair Trigger + Split Shot + Quickdraw (hits re-chamber instantly)
	  * Tank:       Thick Skin + Vampire + Second Wind
	  * Glass:      Glass Cannon x3 + Momentum Rounds (huge damage, 40 HP)

	HOW EFFECTS WORK
	All game systems (movement, sniper, server damage) read a single "stats"
	table built by PowerUps.ComputeStats(owned). A power-up's Effect just edits
	that table, e.g. Thick Skin does `stats.MaxHealth += 40 * stacks`.

	ADDING A NEW POWER-UP
	1. Add a new entry to Definitions.
	2. If it only changes numbers that already exist in baseStats() (health,
	   jumps, bolt time, bullets, bounces, damage multiplier...) you're done.
	3. If it needs brand new behaviour, add a new field to baseStats(), set it
	   in your Effect, and read that field where the behaviour lives
	   (MovementController / WeaponController / CombatService).

	ICON SHAPES (all positions/sizes are 0-1 of the icon square)
		{ "Circle", x, y, size }
		{ "Ring",   x, y, size, thickness(px) }
		{ "Rect",   x, y, width, height, rotationDegrees }
	Optional keys on any shape:
		A = 0.5        transparency (0 = solid, 1 = invisible)
		Dark = true    draw in the dark UI colour instead of white
		Round = 0.5    corner rounding for a Rect (0-0.5)
	Example: { "Rect", 0.5, 0.5, 0.2, 0.6, 0, A = 0.5 }
]]

local Config = require(script.Parent.Config)
local P = Config.PowerUps

local PowerUps = {}

----------------------------------------------------------------------------
-- BASE STATS: what a player has with zero power-ups.
----------------------------------------------------------------------------
local function baseStats()
	return {
		-- body
		MaxHealth = Config.Player.MaxHealth,
		LifeSteal = 0, -- fraction of damage healed
		SecondWindCharges = 0, -- lethal hits survived per round

		-- rifle
		BoltTime = Config.Weapon.BoltTime,
		ScopeInTime = Config.Weapon.ScopeInTime,
		Bullets = 1,
		HairTrigger = false, -- a hit re-chambers instantly

		-- bullet path
		GhostWalls = 0, -- walls a bullet can pass through
		Bounces = 0, -- ricochets per bullet
		Homing = false,
		HomingTurn = 0, -- degrees per step
		HomingRadius = 0,
		Explosive = false,
		ExplosionRadius = 0,
		ExplosionDamage = 0,
		ShrapnelCount = 0, -- shards per bounce / wall pass / impact
		StaticChargeDamage = 0, -- near misses zap the enemy
		StaticChargeRadius = 0,

		-- damage
		DamageMultiplier = 1,
		AirDamageBonus = 0, -- extra damage while you're airborne
		SpeedDamageBonus = 0, -- multiplier on the Momentum Rounds bonus
		HopDamageBonus = 0, -- extra damage per bounce / wall pass before the hit
		MarkBonus = 0, -- extra damage against a target you hit recently

		-- movement
		AirJumps = Config.Movement.AirJumps,
		MoveSpeedMultiplier = 1,
		GravityScale = 1,
		JumpMultiplier = 1,
		RocketJump = false,
		RocketJumpPower = 1,
		Grapple = false,
		GrappleCooldown = Config.Movement.GrappleCooldown,
		GrapplePull = 1,
		Blink = false,
		BlinkDistance = 0,
		BlinkCooldown = 0,
		PhantomDash = false,
		PhantomTime = 0,
		InfiniteWallRun = false,
		CeilingRun = false,
		ShockwaveLanding = false,
		ShockwaveRadius = 0,
		ShockwaveKnockback = 0,
		ShockwaveDamage = 0,

		-- utility
		BulletTime = false,
		BulletTimeDuration = 0,
		WallhackPulse = false,
		WallhackInterval = 0,
		WallhackDuration = 0,
		Decoy = false,
		DecoyCount = 0,
	}
end

----------------------------------------------------------------------------
-- DEFINITIONS
----------------------------------------------------------------------------
PowerUps.Definitions = {
	-------------------------------------------------------------- BULLETS
	{
		Id = "GhostRound",
		Name = "Ghost Round",
		Description = "Bullets pass through a wall before hitting.",
		Stacking = "+1 wall per stack",
		Rarity = "Epic",
		Tags = { "Bullets" },
		IconColor = Color3.fromRGB(150, 110, 255),
		MaxStacks = 3,
		Icon = {
			{ "Rect", 0.5, 0.5, 0.12, 0.7, 0 },
			{ "Circle", 0.22, 0.5, 0.16, A = 0.45 },
			{ "Circle", 0.78, 0.5, 0.16 },
		},
		Effect = function(s, n)
			s.GhostWalls += P.GhostRound.WallsPerStack * n
		end,
	},
	{
		Id = "Ricochet",
		Name = "Ricochet",
		Description = "Bullets bounce off surfaces.",
		Stacking = "+1 bounce per stack",
		Rarity = "Rare",
		Tags = { "Bullets" },
		IconColor = Color3.fromRGB(40, 190, 200),
		MaxStacks = 4,
		Icon = {
			{ "Rect", 0.36, 0.45, 0.12, 0.55, -30 },
			{ "Rect", 0.64, 0.45, 0.12, 0.55, 30 },
			{ "Rect", 0.5, 0.82, 0.7, 0.08, 0 },
		},
		Effect = function(s, n)
			s.Bounces += P.Ricochet.BouncesPerStack * n
		end,
	},
	{
		Id = "SplitShot",
		Name = "Split Shot",
		Description = "Every shot fires 3 bullets in a tight spread.",
		Stacking = "+2 bullets per stack",
		Rarity = "Legendary",
		Tags = { "Bullets" },
		IconColor = Color3.fromRGB(255, 90, 90),
		MaxStacks = 2,
		Icon = {
			{ "Rect", 0.5, 0.5, 0.08, 0.7, 0 },
			{ "Rect", 0.36, 0.52, 0.08, 0.66, -18 },
			{ "Rect", 0.64, 0.52, 0.08, 0.66, 18 },
		},
		Effect = function(s, n)
			s.Bullets += P.SplitShot.BulletsPerStack * n
		end,
	},
	{
		Id = "HomingRounds",
		Name = "Homing Rounds",
		Description = "Bullets curve toward the enemy when they pass close by.",
		Stacking = "Stronger and wider curve per stack",
		Rarity = "Legendary",
		Tags = { "Bullets" },
		IconColor = Color3.fromRGB(255, 70, 140),
		MaxStacks = 3,
		Icon = {
			{ "Ring", 0.5, 0.5, 0.74, 4 },
			{ "Ring", 0.5, 0.5, 0.42, 4 },
			{ "Circle", 0.5, 0.5, 0.14 },
		},
		Effect = function(s, n)
			local cfg = P.HomingRounds
			s.Homing = true
			s.HomingTurn = cfg.TurnDegreesPerStack * n
			s.HomingRadius = cfg.Radius + cfg.RadiusPerStack * (n - 1)
		end,
	},
	{
		Id = "ExplosiveRounds",
		Name = "Explosive Rounds",
		Description = "Bullets explode on impact with splash damage and knockback.",
		Stacking = "Bigger, harder blasts per stack",
		Rarity = "Epic",
		Tags = { "Bullets", "Damage" },
		IconColor = Color3.fromRGB(255, 120, 50),
		MaxStacks = 3,
		Icon = {
			{ "Rect", 0.5, 0.5, 0.5, 0.5, 0 },
			{ "Rect", 0.5, 0.5, 0.5, 0.5, 45 },
			{ "Circle", 0.5, 0.5, 0.24, Dark = true },
		},
		Effect = function(s, n)
			local cfg = P.ExplosiveRounds
			s.Explosive = true
			s.ExplosionRadius = cfg.Radius + cfg.RadiusPerStack * (n - 1)
			s.ExplosionDamage = cfg.Damage + cfg.DamagePerStack * (n - 1)
		end,
	},
	{
		Id = "Shrapnel",
		Name = "Shrapnel",
		Description = "Every bounce, wall pass and impact sprays 2 damaging shards.",
		Stacking = "+2 shards per stack. Great with Ricochet",
		Rarity = "Epic",
		Tags = { "Bullets", "Damage" },
		IconColor = Color3.fromRGB(230, 150, 60),
		MaxStacks = 3,
		Icon = {
			{ "Rect", 0.5, 0.82, 0.7, 0.08, 0 },
			{ "Rect", 0.32, 0.45, 0.07, 0.42, -35 },
			{ "Rect", 0.5, 0.4, 0.07, 0.5, 0 },
			{ "Rect", 0.68, 0.45, 0.07, 0.42, 35 },
		},
		Effect = function(s, n)
			s.ShrapnelCount += P.Shrapnel.ShardsPerStack * n
		end,
	},
	{
		Id = "StaticCharge",
		Name = "Static Charge",
		Description = "Near misses zap the enemy for 20 damage.",
		Stacking = "+20 damage and wider zap per stack",
		Rarity = "Rare",
		Tags = { "Bullets", "Damage" },
		IconColor = Color3.fromRGB(80, 200, 255),
		MaxStacks = 3,
		Icon = {
			{ "Rect", 0.56, 0.28, 0.1, 0.36, 25 },
			{ "Rect", 0.5, 0.5, 0.4, 0.1, -10 },
			{ "Rect", 0.44, 0.72, 0.1, 0.36, 25 },
			{ "Ring", 0.5, 0.5, 0.86, 2, A = 0.5 },
		},
		Effect = function(s, n)
			local cfg = P.StaticCharge
			s.StaticChargeDamage += cfg.Damage * n
			s.StaticChargeRadius = cfg.Radius + cfg.RadiusPerStack * (n - 1)
		end,
	},

	-------------------------------------------------------------- DAMAGE
	{
		Id = "Pinball",
		Name = "Pinball",
		Description = "Bullets deal +35% damage for every bounce or wall they went through.",
		Stacking = "+35% per hop per stack. Needs Ricochet or Ghost Round",
		Rarity = "Rare",
		Tags = { "Damage" },
		IconColor = Color3.fromRGB(255, 110, 200),
		MaxStacks = 2,
		Icon = {
			{ "Circle", 0.3, 0.3, 0.2 },
			{ "Circle", 0.7, 0.45, 0.2, A = 0.35 },
			{ "Circle", 0.4, 0.72, 0.2, A = 0.6 },
			{ "Rect", 0.5, 0.38, 0.4, 0.06, 20 },
			{ "Rect", 0.55, 0.6, 0.06, 0.32, 40 },
		},
		Effect = function(s, n)
			s.HopDamageBonus += P.Pinball.BonusPerHop * n
		end,
	},
	{
		Id = "MomentumRounds",
		Name = "Momentum Rounds",
		Description = "The faster you move, the harder you hit (up to +60%).",
		Stacking = "Bonus doubles, triples... per stack. Bunny hop!",
		Rarity = "Rare",
		Tags = { "Damage", "Movement" },
		IconColor = Color3.fromRGB(255, 170, 60),
		MaxStacks = 3,
		Icon = {
			{ "Rect", 0.35, 0.3, 0.4, 0.08, 0, A = 0.5 },
			{ "Rect", 0.3, 0.5, 0.4, 0.08, 0, A = 0.3 },
			{ "Rect", 0.35, 0.7, 0.4, 0.08, 0, A = 0.5 },
			{ "Circle", 0.68, 0.5, 0.3 },
		},
		Effect = function(s, n)
			s.SpeedDamageBonus += n
		end,
	},
	{
		Id = "SkySniper",
		Name = "Sky Sniper",
		Description = "+20% damage while you're in the air.",
		Stacking = "+20% per stack",
		Rarity = "Common",
		Tags = { "Damage", "Movement" },
		IconColor = Color3.fromRGB(110, 190, 255),
		MaxStacks = 3,
		Icon = {
			{ "Circle", 0.5, 0.35, 0.3 },
			{ "Rect", 0.5, 0.75, 0.7, 0.06, 0, A = 0.4 },
			{ "Rect", 0.5, 0.35, 0.06, 0.5, 0, Dark = true },
			{ "Rect", 0.5, 0.35, 0.5, 0.06, 0, Dark = true },
		},
		Effect = function(s, n)
			s.AirDamageBonus += P.SkySniper.AirBonus * n
		end,
	},
	{
		Id = "GlassCannon",
		Name = "Glass Cannon",
		Description = "+30% damage, but -20 max health.",
		Stacking = "+30% damage / -20 health per stack",
		Rarity = "Common",
		Tags = { "Damage" },
		IconColor = Color3.fromRGB(200, 230, 255),
		MaxStacks = 3,
		Icon = {
			{ "Rect", 0.5, 0.5, 0.42, 0.42, 45, A = 0.3 },
			{ "Rect", 0.42, 0.42, 0.04, 0.36, 30, Dark = true },
			{ "Rect", 0.58, 0.58, 0.04, 0.3, -20, Dark = true },
		},
		Effect = function(s, n)
			s.DamageMultiplier *= 1 + P.GlassCannon.DamageBonus * n
			s.MaxHealth -= P.GlassCannon.HealthCost * n
		end,
	},
	{
		Id = "Marked",
		Name = "Marked",
		Description = "Hitting the enemy marks them for 4s: they glow for you and take +25% damage.",
		Stacking = "+25% damage per stack",
		Rarity = "Rare",
		Tags = { "Damage" },
		IconColor = Color3.fromRGB(255, 80, 80),
		MaxStacks = 3,
		Icon = {
			{ "Ring", 0.5, 0.5, 0.62, 4 },
			{ "Rect", 0.5, 0.14, 0.06, 0.2, 0 },
			{ "Rect", 0.5, 0.86, 0.06, 0.2, 0 },
			{ "Rect", 0.14, 0.5, 0.2, 0.06, 0 },
			{ "Rect", 0.86, 0.5, 0.2, 0.06, 0 },
		},
		Effect = function(s, n)
			s.MarkBonus += P.Marked.BonusPerStack * n
		end,
	},
	{
		Id = "HairTrigger",
		Name = "Hair Trigger",
		Description = "Hitting the enemy instantly re-chambers your rifle.",
		Stacking = "Doesn't stack. Amazing with Split Shot",
		Rarity = "Epic",
		Tags = { "Rifle" },
		IconColor = Color3.fromRGB(240, 200, 80),
		MaxStacks = 1,
		Icon = {
			{ "Rect", 0.5, 0.36, 0.5, 0.14, 0 },
			{ "Rect", 0.62, 0.62, 0.12, 0.36, -15 },
			{ "Ring", 0.38, 0.62, 0.26, 3 },
		},
		Effect = function(s)
			s.HairTrigger = true
		end,
	},
	{
		Id = "Vampire",
		Name = "Vampire",
		Description = "Hitting the enemy heals you for half the damage dealt.",
		Stacking = "+50% of damage healed per stack",
		Rarity = "Rare",
		Tags = { "Defence" },
		IconColor = Color3.fromRGB(190, 40, 70),
		MaxStacks = 3,
		Icon = {
			{ "Rect", 0.5, 0.42, 0.36, 0.36, 45 },
			{ "Circle", 0.5, 0.6, 0.42 },
		},
		Effect = function(s, n)
			s.LifeSteal += P.Vampire.HealFraction * n
		end,
	},

	-------------------------------------------------------------- MOVEMENT
	{
		Id = "DoubleJump",
		Name = "Double Jump",
		Description = "Gain a mid-air jump.",
		Stacking = "+1 air jump per stack",
		Rarity = "Common",
		Tags = { "Movement" },
		IconColor = Color3.fromRGB(120, 170, 255),
		MaxStacks = 3,
		Icon = {
			{ "Rect", 0.4, 0.34, 0.09, 0.28, -45 },
			{ "Rect", 0.6, 0.34, 0.09, 0.28, 45 },
			{ "Rect", 0.4, 0.64, 0.09, 0.28, -45, A = 0.4 },
			{ "Rect", 0.6, 0.64, 0.09, 0.28, 45, A = 0.4 },
		},
		Effect = function(s, n)
			s.AirJumps += P.DoubleJump.ExtraJumpsPerStack * n
		end,
	},
	{
		Id = "Adrenaline",
		Name = "Adrenaline",
		Description = "+8% movement speed (running, air strafing and top speed).",
		Stacking = "+8% per stack",
		Rarity = "Common",
		Tags = { "Movement" },
		IconColor = Color3.fromRGB(255, 120, 90),
		MaxStacks = 3,
		Icon = {
			{ "Rect", 0.42, 0.5, 0.12, 0.42, 30 },
			{ "Rect", 0.62, 0.5, 0.12, 0.42, 30, A = 0.4 },
			{ "Rect", 0.5, 0.5, 0.7, 0.06, 0, A = 0.6 },
		},
		Effect = function(s, n)
			s.MoveSpeedMultiplier *= 1 + P.Adrenaline.SpeedPerStack * n
		end,
	},
	{
		Id = "Featherweight",
		Name = "Featherweight",
		Description = "You fall 18% slower. Longer hops, longer air strafes.",
		Stacking = "-18% gravity per stack",
		Rarity = "Common",
		Tags = { "Movement" },
		IconColor = Color3.fromRGB(170, 220, 200),
		MaxStacks = 3,
		Icon = {
			{ "Rect", 0.5, 0.5, 0.26, 0.66, 30, Round = 0.5 },
			{ "Rect", 0.48, 0.52, 0.04, 0.6, 30, Dark = true },
		},
		Effect = function(s, n)
			s.GravityScale *= math.max(0.2, 1 - P.Featherweight.GravityReductionPerStack * n)
		end,
	},
	{
		Id = "SpringLegs",
		Name = "Spring Legs",
		Description = "You jump 15% higher.",
		Stacking = "+15% per stack",
		Rarity = "Common",
		Tags = { "Movement" },
		IconColor = Color3.fromRGB(140, 230, 120),
		MaxStacks = 3,
		Icon = {
			{ "Rect", 0.5, 0.2, 0.5, 0.08, 0 },
			{ "Rect", 0.5, 0.35, 0.4, 0.07, 20 },
			{ "Rect", 0.5, 0.5, 0.4, 0.07, -20 },
			{ "Rect", 0.5, 0.65, 0.4, 0.07, 20 },
			{ "Rect", 0.5, 0.8, 0.5, 0.08, 0 },
		},
		Effect = function(s, n)
			s.JumpMultiplier *= 1 + P.SpringLegs.JumpPerStack * n
		end,
	},
	{
		Id = "Blink",
		Name = "Blink",
		Description = "Press R to teleport 28 studs where you're looking. Keeps your speed.",
		Stacking = "Further and more often per stack",
		Rarity = "Epic",
		Tags = { "Movement" },
		IconColor = Color3.fromRGB(160, 120, 255),
		MaxStacks = 3,
		Icon = {
			{ "Circle", 0.25, 0.5, 0.22, A = 0.6 },
			{ "Rect", 0.5, 0.5, 0.3, 0.06, 0, A = 0.4 },
			{ "Circle", 0.75, 0.5, 0.28 },
		},
		Effect = function(s, n)
			local cfg = P.Blink
			s.Blink = true
			s.BlinkDistance = cfg.Distance + cfg.DistancePerStack * (n - 1)
			s.BlinkCooldown = cfg.Cooldown / n
		end,
	},
	{
		Id = "GrappleHook",
		Name = "Grapple Hook",
		Description = "Press E to fire a hook that yanks you to any surface.",
		Stacking = "Shorter cooldown, faster pull per stack",
		Rarity = "Epic",
		Tags = { "Movement" },
		IconColor = Color3.fromRGB(230, 120, 60),
		MaxStacks = 2,
		Icon = {
			{ "Rect", 0.45, 0.55, 0.08, 0.62, 45 },
			{ "Rect", 0.7, 0.24, 0.3, 0.08, 0 },
			{ "Rect", 0.78, 0.38, 0.08, 0.26, 0 },
		},
		Effect = function(s, n)
			s.Grapple = true
			s.GrappleCooldown = Config.Movement.GrappleCooldown / n
			s.GrapplePull = 1 + P.Grapple.PullPerStack * (n - 1)
		end,
	},
	{
		Id = "RocketJump",
		Name = "Rocket Jump",
		Description = "Shoot at your feet to launch into the air. No self-damage.",
		Stacking = "+25% launch power per stack",
		Rarity = "Rare",
		Tags = { "Movement" },
		IconColor = Color3.fromRGB(255, 140, 70),
		MaxStacks = 2,
		Icon = {
			{ "Rect", 0.38, 0.36, 0.08, 0.32, -45 },
			{ "Rect", 0.62, 0.36, 0.08, 0.32, 45 },
			{ "Rect", 0.5, 0.62, 0.08, 0.36, 0 },
			{ "Rect", 0.5, 0.86, 0.6, 0.06, 0, A = 0.4 },
		},
		Effect = function(s, n)
			s.RocketJump = true
			s.RocketJumpPower = 1 + P.RocketJump.PowerPerStack * (n - 1)
		end,
	},
	{
		Id = "PhantomDash",
		Name = "Phantom Step",
		Description = "Sliding or wall jumping makes you invisible for 0.5 seconds.",
		Stacking = "+0.35s invisible per stack",
		Rarity = "Rare",
		Tags = { "Movement", "Defence" },
		IconColor = Color3.fromRGB(110, 120, 150),
		MaxStacks = 3,
		Icon = {
			{ "Rect", 0.6, 0.3, 0.5, 0.09, 0 },
			{ "Rect", 0.5, 0.5, 0.6, 0.09, 0, A = 0.35 },
			{ "Rect", 0.4, 0.7, 0.5, 0.09, 0, A = 0.65 },
		},
		Effect = function(s, n)
			local cfg = P.PhantomDash
			s.PhantomDash = true
			s.PhantomTime = cfg.InvisibleTime + cfg.TimePerStack * (n - 1)
		end,
	},
	{
		Id = "MagneticBoots",
		Name = "Magnetic Boots",
		Description = "Wall runs last forever and you can run on ceilings (hold Space).",
		Stacking = "Doesn't stack",
		Rarity = "Rare",
		Tags = { "Movement" },
		IconColor = Color3.fromRGB(200, 70, 90),
		MaxStacks = 1,
		Icon = {
			{ "Rect", 0.3, 0.45, 0.14, 0.5, 0 },
			{ "Rect", 0.7, 0.45, 0.14, 0.5, 0 },
			{ "Rect", 0.5, 0.74, 0.54, 0.14, 0 },
		},
		Effect = function(s)
			s.InfiniteWallRun = true
			s.CeilingRun = true
		end,
	},
	{
		Id = "ShockwaveLanding",
		Name = "Shockwave Landing",
		Description = "Landing from a big height knocks back a nearby enemy.",
		Stacking = "Bigger blast per stack, and it deals damage from 2 stacks",
		Rarity = "Epic",
		Tags = { "Movement", "Damage" },
		IconColor = Color3.fromRGB(130, 100, 255),
		MaxStacks = 3,
		Icon = {
			{ "Rect", 0.5, 0.8, 0.8, 0.08, 0 },
			{ "Ring", 0.5, 0.62, 0.36, 3 },
			{ "Ring", 0.5, 0.62, 0.66, 3, A = 0.5 },
			{ "Rect", 0.5, 0.3, 0.08, 0.3, 0 },
		},
		Effect = function(s, n)
			local cfg = P.ShockwaveLanding
			s.ShockwaveLanding = true
			s.ShockwaveRadius = cfg.Radius + cfg.RadiusPerStack * (n - 1)
			s.ShockwaveKnockback = cfg.Knockback + cfg.KnockbackPerStack * (n - 1)
			s.ShockwaveDamage = cfg.DamagePerExtraStack * (n - 1)
		end,
	},

	-------------------------------------------------------------- UTILITY / DEFENCE
	{
		Id = "BulletTime",
		Name = "Bullet Time",
		Description = "Scope in mid-air to slow time for yourself for 2 seconds.",
		Stacking = "+1 second per stack",
		Rarity = "Legendary",
		Tags = { "Rifle", "Movement" },
		IconColor = Color3.fromRGB(240, 170, 40),
		MaxStacks = 2,
		Icon = {
			{ "Ring", 0.5, 0.5, 0.72, 4 },
			{ "Rect", 0.5, 0.38, 0.08, 0.26, 0 },
			{ "Rect", 0.6, 0.55, 0.08, 0.2, -60 },
		},
		Effect = function(s, n)
			local cfg = P.BulletTime
			s.BulletTime = true
			s.BulletTimeDuration = cfg.Duration + cfg.DurationPerStack * (n - 1)
		end,
	},
	{
		Id = "Quickdraw",
		Name = "Quickdraw",
		Description = "Bolt cycle and scope-in are 40% faster.",
		Stacking = "Another 40% faster per stack",
		Rarity = "Common",
		Tags = { "Rifle" },
		IconColor = Color3.fromRGB(250, 200, 70),
		MaxStacks = 3,
		Icon = {
			{ "Rect", 0.56, 0.3, 0.1, 0.38, 25 },
			{ "Rect", 0.5, 0.5, 0.36, 0.1, 0 },
			{ "Rect", 0.44, 0.7, 0.1, 0.38, 25 },
		},
		Effect = function(s, n)
			local mult = (1 - P.Quickdraw.SpeedPerStack) ^ n
			s.BoltTime *= mult
			s.ScopeInTime *= mult
		end,
	},
	{
		Id = "ThickSkin",
		Name = "Thick Skin",
		Description = "+40 max health.",
		Stacking = "+40 per stack",
		Rarity = "Common",
		Tags = { "Defence" },
		IconColor = Color3.fromRGB(90, 200, 150),
		MaxStacks = 5,
		Icon = {
			{ "Rect", 0.5, 0.46, 0.46, 0.46, 45 },
			{ "Rect", 0.5, 0.3, 0.66, 0.2, 0 },
		},
		Effect = function(s, n)
			s.MaxHealth += P.ThickSkin.HealthPerStack * n
		end,
	},
	{
		Id = "SecondWind",
		Name = "Second Wind",
		Description = "The first time you'd die each round, survive with 1 HP and a speed boost.",
		Stacking = "+1 save per round per stack",
		Rarity = "Epic",
		Tags = { "Defence" },
		IconColor = Color3.fromRGB(70, 200, 120),
		MaxStacks = 2,
		Icon = {
			{ "Rect", 0.5, 0.5, 0.16, 0.6, 0 },
			{ "Rect", 0.5, 0.5, 0.6, 0.16, 0 },
		},
		Effect = function(s, n)
			s.SecondWindCharges += n
		end,
	},
	{
		Id = "WallhackPulse",
		Name = "Wallhack Pulse",
		Description = "Every 10 seconds the enemy flashes through walls for 1 second.",
		Stacking = "Pulses more often and for longer per stack",
		Rarity = "Rare",
		Tags = { "Utility" },
		IconColor = Color3.fromRGB(80, 210, 255),
		MaxStacks = 3,
		Icon = {
			{ "Rect", 0.5, 0.5, 0.74, 0.36, 0, Round = 0.5 },
			{ "Circle", 0.5, 0.5, 0.22, Dark = true },
		},
		Effect = function(s, n)
			local cfg = P.WallhackPulse
			s.WallhackPulse = true
			s.WallhackInterval = cfg.Interval * cfg.IntervalScalePerStack ^ (n - 1)
			s.WallhackDuration = cfg.Duration + cfg.DurationPerStack * (n - 1)
		end,
	},
	{
		Id = "Decoy",
		Name = "Decoy",
		Description = "Press Q to drop a hologram of yourself that runs in a straight line.",
		Stacking = "+1 hologram per stack (they fan out)",
		Rarity = "Epic",
		Tags = { "Utility" },
		IconColor = Color3.fromRGB(100, 220, 240),
		MaxStacks = 3,
		Icon = {
			{ "Circle", 0.36, 0.3, 0.2 },
			{ "Rect", 0.36, 0.64, 0.24, 0.36, 0 },
			{ "Circle", 0.66, 0.3, 0.2, A = 0.55 },
			{ "Rect", 0.66, 0.64, 0.24, 0.36, 0, A = 0.55 },
		},
		Effect = function(s, n)
			s.Decoy = true
			s.DecoyCount = n
		end,
	},
}

----------------------------------------------------------------------------
-- LOOKUP + HELPERS
----------------------------------------------------------------------------
PowerUps.ById = {}
for _, def in ipairs(PowerUps.Definitions) do
	assert(Config.Rarity[def.Rarity], "Unknown rarity on power-up " .. def.Id)
	assert(not PowerUps.ById[def.Id], "Duplicate power-up id " .. def.Id)
	PowerUps.ById[def.Id] = def
end

function PowerUps.Get(id)
	return PowerUps.ById[id]
end

-- Builds the stat table for a player from their owned power-ups.
-- `owned` is a dictionary { [powerUpId] = stacks }.
function PowerUps.ComputeStats(owned)
	local stats = baseStats()
	if owned then
		for _, def in ipairs(PowerUps.Definitions) do
			local stacks = owned[def.Id]
			if stacks and stacks > 0 then
				def.Effect(stats, stacks)
			end
		end
	end
	stats.MaxHealth = math.max(stats.MaxHealth, 20) -- Glass Cannon can't kill you outright
	return stats
end

-- Draws `count` DIFFERENT random power-ups for a player, weighted by rarity.
-- Power-ups the player already has at MaxStacks are never offered.
-- `rng` is an optional Random object.
function PowerUps.DrawCards(owned, count, rng)
	rng = rng or Random.new()
	owned = owned or {}

	local pool = {}
	for _, def in ipairs(PowerUps.Definitions) do
		if (owned[def.Id] or 0) < (def.MaxStacks or 1) then
			table.insert(pool, def)
		end
	end

	local cards = {}
	while #cards < count and #pool > 0 do
		local total = 0
		for _, def in ipairs(pool) do
			total += Config.Rarity[def.Rarity].Weight
		end
		local roll = rng:NextNumber() * total
		local chosenIndex = #pool
		for i, def in ipairs(pool) do
			roll -= Config.Rarity[def.Rarity].Weight
			if roll <= 0 then
				chosenIndex = i
				break
			end
		end
		-- remove from the pool so the same card can't appear twice
		table.insert(cards, table.remove(pool, chosenIndex).Id)
	end
	return cards
end

return PowerUps
