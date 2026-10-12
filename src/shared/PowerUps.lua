--[[
	PowerUps.lua  (ReplicatedStorage.Shared.PowerUps)

	Every power-up is ONE data entry in the `Definitions` list below:

		Id          unique key (used in code and saved in match state)
		Name        shown on the card
		Description short text shown on the card
		Rarity      "Common" | "Rare" | "Epic" | "Legendary"  (see Config.Rarity)
		IconColor   background colour of the flat icon
		Icon        list of simple shapes drawn on the icon (see "ICON SHAPES" below)
		MaxStacks   how many times a player can own it (cards for maxed power-ups
		            stop appearing). Picking it again adds a stack.
		Effect      function(stats, stacks) that changes the player's stat table.

	HOW EFFECTS WORK
	All game systems (movement, sniper, server damage) read a single "stats"
	table built by PowerUps.ComputeStats(owned). A power-up's Effect just edits
	that table, e.g. Thick Skin does `stats.MaxHealth += 40 * stacks`.

	ADDING A NEW POWER-UP
	1. Add a new entry to Definitions.
	2. If it only changes numbers that already exist in BaseStats (health, jumps,
	   bolt time, bullets, bounces...) you're done.
	3. If it needs brand new behaviour, add a new field to BaseStats, set it in
	   your Effect, and read that field where the behaviour lives
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
		MaxHealth = Config.Player.MaxHealth,
		AirJumps = Config.Movement.AirJumps,
		BoltTime = Config.Weapon.BoltTime,
		ScopeInTime = Config.Weapon.ScopeInTime,
		Bullets = 1,
		GhostWalls = 0, -- walls a bullet can pass through
		Bounces = 0, -- ricochets per bullet
		Homing = false,
		Explosive = false,
		RocketJump = false,
		LifeSteal = 0, -- fraction of damage healed
		SecondWind = false,
		BulletTime = false,
		Grapple = false,
		PhantomDash = false,
		WallhackPulse = false,
		Decoy = false,
		InfiniteWallRun = false,
		CeilingRun = false,
		ShockwaveLanding = false,
	}
end

----------------------------------------------------------------------------
-- DEFINITIONS
----------------------------------------------------------------------------
PowerUps.Definitions = {
	{
		Id = "GhostRound",
		Name = "Ghost Round",
		Description = "Bullets pass through one wall before hitting.",
		Rarity = "Epic",
		IconColor = Color3.fromRGB(150, 110, 255),
		MaxStacks = 2,
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
		Description = "Bullets bounce off surfaces once.",
		Rarity = "Rare",
		IconColor = Color3.fromRGB(40, 190, 200),
		MaxStacks = 3,
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
		Id = "BulletTime",
		Name = "Bullet Time",
		Description = "Scope in mid-air to slow time for 2 seconds.",
		Rarity = "Legendary",
		IconColor = Color3.fromRGB(240, 170, 40),
		MaxStacks = 1,
		Icon = {
			{ "Ring", 0.5, 0.5, 0.72, 4 },
			{ "Rect", 0.5, 0.38, 0.08, 0.26, 0 },
			{ "Rect", 0.6, 0.55, 0.08, 0.2, -60 },
		},
		Effect = function(s)
			s.BulletTime = true
		end,
	},
	{
		Id = "GrappleHook",
		Name = "Grapple Hook",
		Description = "Press E to fire a hook that yanks you to any surface.",
		Rarity = "Epic",
		IconColor = Color3.fromRGB(230, 120, 60),
		MaxStacks = 1,
		Icon = {
			{ "Rect", 0.45, 0.55, 0.08, 0.62, 45 },
			{ "Rect", 0.7, 0.24, 0.3, 0.08, 0 },
			{ "Rect", 0.78, 0.38, 0.08, 0.26, 0 },
		},
		Effect = function(s)
			s.Grapple = true
		end,
	},
	{
		Id = "PhantomDash",
		Name = "Phantom Dash",
		Description = "Your air dash makes you invisible for 0.5 seconds.",
		Rarity = "Rare",
		IconColor = Color3.fromRGB(110, 120, 150),
		MaxStacks = 1,
		Icon = {
			{ "Rect", 0.6, 0.3, 0.5, 0.09, 0 },
			{ "Rect", 0.5, 0.5, 0.6, 0.09, 0, A = 0.35 },
			{ "Rect", 0.4, 0.7, 0.5, 0.09, 0, A = 0.65 },
		},
		Effect = function(s)
			s.PhantomDash = true
		end,
	},
	{
		Id = "SplitShot",
		Name = "Split Shot",
		Description = "Every shot fires 3 bullets in a tight spread.",
		Rarity = "Legendary",
		IconColor = Color3.fromRGB(255, 90, 90),
		MaxStacks = 1,
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
		Id = "RocketJump",
		Name = "Rocket Jump",
		Description = "Shoot at your feet to launch into the air. No self-damage.",
		Rarity = "Rare",
		IconColor = Color3.fromRGB(255, 140, 70),
		MaxStacks = 1,
		Icon = {
			{ "Rect", 0.38, 0.36, 0.08, 0.32, -45 },
			{ "Rect", 0.62, 0.36, 0.08, 0.32, 45 },
			{ "Rect", 0.5, 0.62, 0.08, 0.36, 0 },
			{ "Rect", 0.5, 0.86, 0.6, 0.06, 0, A = 0.4 },
		},
		Effect = function(s)
			s.RocketJump = true
		end,
	},
	{
		Id = "SecondWind",
		Name = "Second Wind",
		Description = "The first time you'd die each round, survive with 1 HP and a speed boost.",
		Rarity = "Epic",
		IconColor = Color3.fromRGB(70, 200, 120),
		MaxStacks = 1,
		Icon = {
			{ "Rect", 0.5, 0.5, 0.16, 0.6, 0 },
			{ "Rect", 0.5, 0.5, 0.6, 0.16, 0 },
		},
		Effect = function(s)
			s.SecondWind = true
		end,
	},
	{
		Id = "HomingRounds",
		Name = "Homing Rounds",
		Description = "Bullets curve toward the enemy when they pass close by.",
		Rarity = "Legendary",
		IconColor = Color3.fromRGB(255, 70, 140),
		MaxStacks = 1,
		Icon = {
			{ "Ring", 0.5, 0.5, 0.74, 4 },
			{ "Ring", 0.5, 0.5, 0.42, 4 },
			{ "Circle", 0.5, 0.5, 0.14 },
		},
		Effect = function(s)
			s.Homing = true
		end,
	},
	{
		Id = "TripleJump",
		Name = "Triple Jump",
		Description = "One extra mid-air jump.",
		Rarity = "Common",
		IconColor = Color3.fromRGB(120, 170, 255),
		MaxStacks = 3,
		Icon = {
			{ "Rect", 0.4, 0.25, 0.08, 0.25, -45 },
			{ "Rect", 0.6, 0.25, 0.08, 0.25, 45 },
			{ "Rect", 0.4, 0.5, 0.08, 0.25, -45, A = 0.3 },
			{ "Rect", 0.6, 0.5, 0.08, 0.25, 45, A = 0.3 },
			{ "Rect", 0.4, 0.75, 0.08, 0.25, -45, A = 0.6 },
			{ "Rect", 0.6, 0.75, 0.08, 0.25, 45, A = 0.6 },
		},
		Effect = function(s, n)
			s.AirJumps += P.TripleJump.ExtraJumpsPerStack * n
		end,
	},
	{
		Id = "Quickdraw",
		Name = "Quickdraw",
		Description = "Bolt cycle and scope-in are 40% faster.",
		Rarity = "Common",
		IconColor = Color3.fromRGB(250, 200, 70),
		MaxStacks = 2,
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
		Rarity = "Common",
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
		Id = "WallhackPulse",
		Name = "Wallhack Pulse",
		Description = "Every 10 seconds the enemy flashes through walls for 1 second.",
		Rarity = "Rare",
		IconColor = Color3.fromRGB(80, 210, 255),
		MaxStacks = 1,
		Icon = {
			{ "Rect", 0.5, 0.5, 0.74, 0.36, 0, Round = 0.5 },
			{ "Circle", 0.5, 0.5, 0.22, Dark = true },
		},
		Effect = function(s)
			s.WallhackPulse = true
		end,
	},
	{
		Id = "Decoy",
		Name = "Decoy",
		Description = "Press Q to drop a hologram of yourself that runs in a straight line.",
		Rarity = "Epic",
		IconColor = Color3.fromRGB(100, 220, 240),
		MaxStacks = 1,
		Icon = {
			{ "Circle", 0.36, 0.3, 0.2 },
			{ "Rect", 0.36, 0.64, 0.24, 0.36, 0 },
			{ "Circle", 0.66, 0.3, 0.2, A = 0.55 },
			{ "Rect", 0.66, 0.64, 0.24, 0.36, 0, A = 0.55 },
		},
		Effect = function(s)
			s.Decoy = true
		end,
	},
	{
		Id = "ExplosiveRounds",
		Name = "Explosive Rounds",
		Description = "Bullets explode on impact with splash damage and knockback.",
		Rarity = "Epic",
		IconColor = Color3.fromRGB(255, 120, 50),
		MaxStacks = 1,
		Icon = {
			{ "Rect", 0.5, 0.5, 0.5, 0.5, 0 },
			{ "Rect", 0.5, 0.5, 0.5, 0.5, 45 },
			{ "Circle", 0.5, 0.5, 0.24, Dark = true },
		},
		Effect = function(s)
			s.Explosive = true
		end,
	},
	{
		Id = "MagneticBoots",
		Name = "Magnetic Boots",
		Description = "Wall runs last forever and you can run on ceilings (hold Space).",
		Rarity = "Rare",
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
		Id = "Vampire",
		Name = "Vampire",
		Description = "Hitting the enemy heals you for half the damage dealt.",
		Rarity = "Rare",
		IconColor = Color3.fromRGB(190, 40, 70),
		MaxStacks = 2,
		Icon = {
			{ "Rect", 0.5, 0.42, 0.36, 0.36, 45 },
			{ "Circle", 0.5, 0.6, 0.42 },
		},
		Effect = function(s, n)
			s.LifeSteal += P.Vampire.HealFraction * n
		end,
	},
	{
		Id = "ShockwaveLanding",
		Name = "Shockwave Landing",
		Description = "Landing from a big height knocks back a nearby enemy.",
		Rarity = "Epic",
		IconColor = Color3.fromRGB(130, 100, 255),
		MaxStacks = 1,
		Icon = {
			{ "Rect", 0.5, 0.8, 0.8, 0.08, 0 },
			{ "Ring", 0.5, 0.62, 0.36, 3 },
			{ "Ring", 0.5, 0.62, 0.66, 3, A = 0.5 },
			{ "Rect", 0.5, 0.3, 0.08, 0.3, 0 },
		},
		Effect = function(s)
			s.ShockwaveLanding = true
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
