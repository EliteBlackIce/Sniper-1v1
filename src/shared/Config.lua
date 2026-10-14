--[[
	Config.lua  (ReplicatedStorage.Shared.Config)

	EVERY tunable number in the game lives here. Server and client both read
	this module, so changing a value here changes it everywhere.

	Units: distances are studs, speeds are studs/second, times are seconds,
	angles are degrees unless the name says otherwise.
]]

local Config = {}

----------------------------------------------------------------------------
-- COLOUR PALETTE
-- Flat look: every part in the game picks one of these colours. Change the
-- palette here and the map, viewmodel, characters and UI all follow.
----------------------------------------------------------------------------
Config.Palette = {
	-- Structures (soft whites and greys)
	Snow = Color3.fromRGB(246, 246, 243), -- main floor / big surfaces
	Light = Color3.fromRGB(230, 231, 234), -- walls
	Mid = Color3.fromRGB(204, 207, 213), -- trims, pillars
	Dark = Color3.fromRGB(150, 156, 168), -- deep accents, frames

	-- Accents (cover and highlights)
	AccentA = Color3.fromRGB(56, 199, 182), -- teal: cover blocks
	AccentB = Color3.fromRGB(255, 196, 77), -- mustard: ramps / jump pads / highlights

	-- Players (each player in a match gets one of these)
	PlayerA = Color3.fromRGB(90, 132, 255), -- blue
	PlayerB = Color3.fromRGB(232, 56, 64), -- red
	LobbyPlayer = Color3.fromRGB(205, 210, 220),

	-- Sniper + arms (viewmodel and the gun other players see)
	GunMetal = Color3.fromRGB(38, 41, 49), -- barrel, receiver, scope
	GunMetalLight = Color3.fromRGB(70, 75, 88), -- rails, bolt, small metal bits
	GunFurniture = Color3.fromRGB(84, 104, 78), -- (old rifle) stock + handguard
	GunShell = Color3.fromRGB(226, 229, 236), -- the rifle's light outer shell
	GunGlow = Color3.fromRGB(56, 199, 182), -- glowing energy lines (recoloured by power-ups)
	GunAccent = Color3.fromRGB(56, 199, 182), -- tiny highlights (matches AccentA)
	ScopeGlass = Color3.fromRGB(120, 220, 255),
	Glove = Color3.fromRGB(36, 38, 44),
	Sleeve = Color3.fromRGB(62, 70, 86),
	SleeveCuff = Color3.fromRGB(48, 54, 68),
	MuzzleFlash = Color3.fromRGB(255, 236, 170),

	-- Effects
	Tracer = Color3.fromRGB(255, 244, 214),
	TracerBounce = Color3.fromRGB(80, 255, 230),
	TracerExplosive = Color3.fromRGB(255, 140, 60),
	Explosion = Color3.fromRGB(255, 150, 70),
	Hologram = Color3.fromRGB(120, 230, 255),
	Grapple = Color3.fromRGB(255, 196, 77),

	-- UI
	UIBackground = Color3.fromRGB(18, 20, 26),
	UIPanel = Color3.fromRGB(30, 33, 42),
	UIPanelLight = Color3.fromRGB(44, 48, 60),
	UIText = Color3.fromRGB(245, 246, 250),
	UISubText = Color3.fromRGB(160, 167, 184),
	UIAccent = Color3.fromRGB(56, 199, 182),
	UIDanger = Color3.fromRGB(255, 84, 96),
	UIHitmarker = Color3.fromRGB(255, 255, 255),
	UIHeadshot = Color3.fromRGB(255, 70, 80),
}

-- City map colours (Downtown arena). Still flat, single-colour parts.
Config.MapPalette = {
	Asphalt = Color3.fromRGB(70, 74, 84),
	RoadLine = Color3.fromRGB(250, 214, 92),
	RoadWhite = Color3.fromRGB(236, 238, 242),
	Sidewalk = Color3.fromRGB(214, 214, 208),
	Curb = Color3.fromRGB(182, 184, 190),
	Concrete = Color3.fromRGB(196, 198, 204),
	BuildingA = Color3.fromRGB(236, 230, 218), -- warm white
	BuildingB = Color3.fromRGB(184, 198, 216), -- cool blue-grey
	BuildingC = Color3.fromRGB(222, 186, 158), -- sandstone
	BuildingD = Color3.fromRGB(160, 172, 188), -- slate (city skyline)
	BuildingE = Color3.fromRGB(205, 214, 200), -- sage
	Trim = Color3.fromRGB(122, 130, 144),
	Roof = Color3.fromRGB(150, 156, 168),
	Window = Color3.fromRGB(88, 118, 150),
	WindowLit = Color3.fromRGB(170, 205, 230),
	Metal = Color3.fromRGB(86, 92, 104),
	Dark = Color3.fromRGB(46, 50, 58),
	Grass = Color3.fromRGB(142, 196, 120),
	Foliage = Color3.fromRGB(104, 178, 110),
	FoliageDark = Color3.fromRGB(76, 150, 96),
	Trunk = Color3.fromRGB(128, 96, 72),
	Wood = Color3.fromRGB(184, 140, 96),
	Water = Color3.fromRGB(110, 196, 232),
	LampLight = Color3.fromRGB(255, 240, 200),
	Glass = Color3.fromRGB(126, 164, 198),
	FrameDark = Color3.fromRGB(70, 76, 88),
	Brick = Color3.fromRGB(190, 112, 92),
	Stone = Color3.fromRGB(228, 222, 208),
	Soil = Color3.fromRGB(104, 82, 64),
	FoliageLight = Color3.fromRGB(140, 202, 118),
	Tire = Color3.fromRGB(34, 36, 42),
	Rim = Color3.fromRGB(202, 206, 214),
	TailLight = Color3.fromRGB(230, 60, 60),
	SignalGreen = Color3.fromRGB(80, 230, 140),
	Hydrant = Color3.fromRGB(226, 76, 64),
	CarColors = {
		Color3.fromRGB(235, 92, 76),
		Color3.fromRGB(72, 140, 230),
		Color3.fromRGB(244, 244, 244),
		Color3.fromRGB(56, 199, 182),
		Color3.fromRGB(60, 64, 74),
	},
	Bus = Color3.fromRGB(255, 196, 77),
	Train = Color3.fromRGB(56, 199, 182),
	Awning = { Color3.fromRGB(235, 92, 76), Color3.fromRGB(72, 140, 230), Color3.fromRGB(255, 196, 77) },
}

-- Rarity colours (card borders, icons in the HUD) and draw weights.
-- Weight = relative chance a card of this rarity is drawn. Higher rarities
-- have lower weights so they appear less often.
Config.Rarity = {
	Common = { Color = Color3.fromRGB(176, 182, 194), Weight = 55, Order = 1 },
	Rare = { Color = Color3.fromRGB(64, 152, 255), Weight = 28, Order = 2 },
	Epic = { Color = Color3.fromRGB(172, 92, 255), Weight = 13, Order = 3 },
	Legendary = { Color = Color3.fromRGB(255, 196, 60), Weight = 4, Order = 4 },
}

----------------------------------------------------------------------------
-- BODY: your real character holds and animates the weapons (BodyAnimator).
-- In first person you see your own forearms and hands; everyone else sees
-- the same animation on your whole character.
----------------------------------------------------------------------------
Config.Body = {
	GunScale = 0.85, -- the rifle's size in your hands
	RifleHip = Vector3.new(0.42, -0.78, -0.85), -- where the rifle's grip sits, from your eyes
	RifleLeftHold = -0.55, -- how far up the rifle the left hand holds (studs, gun space)
	CameraBack = 0, -- extra distance the first-person camera sits behind your eyes (Roblox already keeps it 0.5 back)
	-- Seen from outside, the same animation is played lower and a little
	-- further out (weapons at chest / waist height, not up by the face).
	ThirdPersonOffset = CFrame.new(0, -0.5, -0.15),
	-- First person: slim copies of your avatar's arms (skin, shirt and all)
	-- and of your weapon, drawn on the camera. Everyone else sees your real
	-- character doing the same moves.
	FirstPerson = {
		ArmThickness = 0.4, -- how wide the copied arms are (your real arms are about 1)
		HandWidth = 0.34,
		UpperLength = 1.15, -- shoulder to elbow
		LowerLength = 1.1, -- elbow to wrist
		Shoulder = Vector3.new(0.95, -1.3, 0.25), -- the right shoulder, from your eyes (the left is mirrored)
	},
	MaxDistance = 300, -- other characters further away than this aren't animated
	PitchSmoothing = 14, -- how quickly other players' aim follows their updates
}

----------------------------------------------------------------------------
-- KNIFE (your second weapon: press 2 / scroll, or ButtonR1 on a controller)
--   Left click  slash (alternates left / right)
--   Right click heavy stab with a short lunge
--   V           inspect: toss it up and catch it
-- Hits are checked on the server (range, facing, line of sight, timing).
-- A hit from behind (backstab) is always a kill.
----------------------------------------------------------------------------
Config.Knife = {
	Enabled = true,
	SlashDamage = 40,
	StabDamage = 70,
	BackstabDamage = 1000, -- from behind = always a kill
	BackstabAngle = 65, -- degrees either side of straight behind the victim
	SlashRange = 7, -- studs from you to the target's body
	StabRange = 8.5, -- (the lunge carries you a little further)
	SlashTime = 0.42, -- seconds per slash (also the cooldown)
	StabTime = 0.85,
	SlashHitAt = 0.14, -- when in the swing the hit lands
	StabHitAt = 0.3,
	HitAngle = 55, -- the target must be within this many degrees of where you look
	LungeSpeed = 34, -- forward push on a stab
	EquipTime = 0.4, -- seconds after switching before you can attack
	MoveSpeedMultiplier = 1.08, -- knife out = you run a bit faster
	-- imported knife mesh (assets: CombatKnife.glb, see README)
	UseImportedKnife = true,
	MeshTemplate = "CombatKnife",
	MeshYaw = nil,
	MeshPaint = "Always", -- "Always" = flat steel blade + dark handle, "Auto" = keep imported textures
	WorldScale = 1.05, -- the knife's size in your hand (you and everyone else see the same one)
}

----------------------------------------------------------------------------
-- CRATES (lobby crate vault + the SHOP). Each crate unlocks a rifle or knife
-- skin. Rarities are listed lowest to highest; each crate type has its odds.
----------------------------------------------------------------------------
Config.Crates = {
	StartingKeys = 10, -- keys a brand-new player starts with (one free crate)
	KeysPerWin = 3, -- keys for winning a match
	KeysPerLoss = 1, -- keys for finishing a match you lost
	FreeInStudio = true, -- opening is free when testing in Studio
	Cooldown = 1.5, -- seconds between opens (stops spam; the animation is longer)
	-- The two crates (open them at the crate vault's altar or from the SHOP):
	--   Standard  paid with Keys you earn by playing
	--   Elite     paid with Credits (bought with Robux in the SHOP). Better
	--             odds, and the only place the Elite-only skins and the
	--             Secrets drop.
	-- Odds are percentages per rarity.
	Types = {
		Standard = {
			Name = "STANDARD CRATE",
			Currency = "Keys",
			Cost = 10,
			Odds = { Common = 50, Uncommon = 26, Rare = 15, Epic = 7, Legendary = 2 },
			EliteSkins = false,
		},
		Elite = {
			Name = "ELITE CRATE",
			Currency = "Credits",
			Cost = 100,
			Odds = { Rare = 45, Epic = 30, Legendary = 19, Secret = 6 },
			EliteSkins = true,
		},
	},
	Rarities = {
		{ Id = "Common", Name = "COMMON", Color = Color3.fromRGB(176, 182, 192) },
		{ Id = "Uncommon", Name = "UNCOMMON", Color = Color3.fromRGB(82, 214, 104) },
		{ Id = "Rare", Name = "RARE", Color = Color3.fromRGB(60, 146, 255) },
		{ Id = "Epic", Name = "EPIC", Color = Color3.fromRGB(176, 84, 255) },
		{ Id = "Legendary", Name = "LEGENDARY", Color = Color3.fromRGB(255, 192, 46) },
		{ Id = "Secret", Name = "SECRET", Color = Color3.fromRGB(255, 38, 56) },
	},
	-- Skins for the rifle and the knife (see Skins.lua for how they're
	-- painted). Equip them in the LOCKER (lobby, key L).
	--   Weapon    "Rifle" or "Knife"
	--   Body      rifle: the main body        knife: the handle
	--   Metal     rifle: barrel, scope, metal  knife: guard + pommel
	--   Accent    rifle: bolt + stock trims   knife: (glow colour)
	--   Blade     knife: the blade
	--   Stock     rifle: the stock colour (default: between Body and Metal)
	--   Finish    the body / blade: "Matte" | "Gloss" | "Pearl" | "Metal" |
	--             "Chrome" | "Gold" | "Marble" | "Wood" | "Rust" | "Tread" |
	--             "Frost" | "Stone" | "Crystal" (see-through) | "Hologram"
	--   StockFinish / MetalFinish / HandleFinish   the same for those parts
	--   Glow      true: the trims glow (Epic and up)
	--   Pulse     a second colour the glow pulses to (Legendary)
	--   Sparkle   true: glittering particles (Legendary)
	--   Elite     true: only drops from the Elite crate
	--   Aura      true: a flickering aura of particles round the weapon
	--   Template  Secret skins: the name of a model in Workspace.SecretWeapons
	--             (moved to ReplicatedStorage at start) to use instead of
	--             the normal rifle / knife. Until it's there, the skin's
	--             colours and effects are used on the normal model.
	Skins = {
		-- RIFLE
		{ Id = "FieldGrey", Name = "Field Grey", Weapon = "Rifle", Rarity = "Common", Body = Color3.fromRGB(128, 132, 136), Metal = Color3.fromRGB(52, 54, 58), Accent = Color3.fromRGB(190, 194, 198) },
		{ Id = "Sandstorm", Name = "Sandstorm", Weapon = "Rifle", Rarity = "Common", Body = Color3.fromRGB(196, 170, 120), Metal = Color3.fromRGB(70, 64, 54), Accent = Color3.fromRGB(230, 214, 176) },
		{ Id = "Woodland", Name = "Woodland", Weapon = "Rifle", Rarity = "Common", Body = Color3.fromRGB(92, 110, 70), Metal = Color3.fromRGB(46, 50, 42), Accent = Color3.fromRGB(150, 128, 88) },
		{ Id = "Midnight", Name = "Midnight", Weapon = "Rifle", Rarity = "Common", Body = Color3.fromRGB(44, 46, 52), Metal = Color3.fromRGB(26, 27, 30), Accent = Color3.fromRGB(120, 124, 132) },
		{ Id = "Arctic", Name = "Arctic", Weapon = "Rifle", Rarity = "Uncommon", Body = Color3.fromRGB(226, 234, 240), Metal = Color3.fromRGB(96, 110, 124), Accent = Color3.fromRGB(150, 200, 230), Finish = "Gloss" },
		{ Id = "Viper", Name = "Viper", Weapon = "Rifle", Rarity = "Uncommon", Body = Color3.fromRGB(64, 150, 70), Metal = Color3.fromRGB(30, 36, 32), Accent = Color3.fromRGB(190, 240, 90), Finish = "Gloss" },
		{ Id = "Cobalt", Name = "Cobalt", Weapon = "Rifle", Rarity = "Rare", Body = Color3.fromRGB(40, 92, 200), Metal = Color3.fromRGB(28, 32, 48), Accent = Color3.fromRGB(110, 190, 255), Finish = "Metal" },
		{ Id = "DeepSea", Name = "Deep Sea", Weapon = "Rifle", Rarity = "Rare", Body = Color3.fromRGB(20, 110, 130), Metal = Color3.fromRGB(16, 30, 40), Accent = Color3.fromRGB(80, 230, 220), Finish = "Metal" },
		{ Id = "Chrome", Name = "Chrome", Weapon = "Rifle", Rarity = "Rare", Body = Color3.fromRGB(196, 202, 210), Metal = Color3.fromRGB(60, 64, 72), Accent = Color3.fromRGB(240, 244, 250), Finish = "Chrome" },
		{ Id = "Amethyst", Name = "Amethyst", Weapon = "Rifle", Rarity = "Epic", Body = Color3.fromRGB(120, 60, 200), Metal = Color3.fromRGB(34, 24, 52), Accent = Color3.fromRGB(230, 150, 255), Finish = "Metal", Glow = true },
		{ Id = "Synthwave", Name = "Synthwave", Weapon = "Rifle", Rarity = "Epic", Body = Color3.fromRGB(40, 24, 70), Metal = Color3.fromRGB(20, 16, 32), Accent = Color3.fromRGB(255, 70, 200), Finish = "Gloss", Glow = true },
		{ Id = "GoldenEagle", Name = "Golden Eagle", Weapon = "Rifle", Rarity = "Legendary", Body = Color3.fromRGB(232, 182, 60), Metal = Color3.fromRGB(60, 46, 24), Accent = Color3.fromRGB(255, 240, 170), Finish = "Gold", Glow = true, Pulse = Color3.fromRGB(255, 170, 40), Sparkle = true },
		{ Id = "SolarFlare", Name = "Solar Flare", Weapon = "Rifle", Rarity = "Legendary", Body = Color3.fromRGB(255, 120, 30), Metal = Color3.fromRGB(50, 30, 20), Accent = Color3.fromRGB(255, 220, 90), Finish = "Gloss", Glow = true, Pulse = Color3.fromRGB(255, 60, 30), Sparkle = true },

		{ Id = "Gunmetal", Name = "Gunmetal", Weapon = "Rifle", Rarity = "Common", Body = Color3.fromRGB(92, 96, 104), Metal = Color3.fromRGB(40, 42, 46), Accent = Color3.fromRGB(150, 156, 166), Finish = "Metal" },
		{ Id = "OliveDrab", Name = "Olive Drab", Weapon = "Rifle", Rarity = "Common", Body = Color3.fromRGB(96, 104, 64), Metal = Color3.fromRGB(44, 46, 36), Accent = Color3.fromRGB(160, 150, 110) },
		{ Id = "Coyote", Name = "Coyote", Weapon = "Rifle", Rarity = "Common", Body = Color3.fromRGB(150, 120, 84), Metal = Color3.fromRGB(56, 48, 40), Accent = Color3.fromRGB(200, 180, 140) },
		{ Id = "Urban", Name = "Urban", Weapon = "Rifle", Rarity = "Common", Body = Color3.fromRGB(210, 212, 216), Stock = Color3.fromRGB(60, 62, 68), Metal = Color3.fromRGB(48, 50, 56), Accent = Color3.fromRGB(120, 124, 132) },
		{ Id = "Navy", Name = "Navy", Weapon = "Rifle", Rarity = "Common", Body = Color3.fromRGB(40, 56, 96), Metal = Color3.fromRGB(26, 30, 40), Accent = Color3.fromRGB(140, 160, 200) },
		{ Id = "Cherry", Name = "Cherry", Weapon = "Rifle", Rarity = "Uncommon", Body = Color3.fromRGB(200, 30, 44), Metal = Color3.fromRGB(30, 26, 28), Accent = Color3.fromRGB(255, 210, 210), Finish = "Gloss" },
		{ Id = "Tangerine", Name = "Tangerine", Weapon = "Rifle", Rarity = "Uncommon", Body = Color3.fromRGB(255, 130, 40), Metal = Color3.fromRGB(40, 34, 30), Accent = Color3.fromRGB(255, 230, 190), Finish = "Gloss" },
		{ Id = "Mint", Name = "Mint", Weapon = "Rifle", Rarity = "Uncommon", Body = Color3.fromRGB(140, 226, 190), Metal = Color3.fromRGB(50, 70, 66), Accent = Color3.fromRGB(230, 255, 245), Finish = "Gloss" },
		{ Id = "Bubblegum", Name = "Bubblegum", Weapon = "Rifle", Rarity = "Uncommon", Body = Color3.fromRGB(255, 140, 200), Metal = Color3.fromRGB(70, 50, 66), Accent = Color3.fromRGB(255, 235, 245), Finish = "Gloss" },
		{ Id = "Walnut", Name = "Walnut", Weapon = "Rifle", Rarity = "Uncommon", Body = Color3.fromRGB(110, 70, 40), Stock = Color3.fromRGB(92, 58, 34), Metal = Color3.fromRGB(40, 40, 42), Accent = Color3.fromRGB(180, 150, 110), Finish = "Wood" },
		{ Id = "TwoTone", Name = "Two-Tone", Weapon = "Rifle", Rarity = "Uncommon", Body = Color3.fromRGB(30, 30, 34), Stock = Color3.fromRGB(236, 236, 240), Metal = Color3.fromRGB(24, 24, 28), Accent = Color3.fromRGB(236, 236, 240), Finish = "Gloss", StockFinish = "Gloss" },
		{ Id = "Marble", Name = "Marble", Weapon = "Rifle", Rarity = "Rare", Body = Color3.fromRGB(236, 234, 230), Stock = Color3.fromRGB(70, 70, 76), Metal = Color3.fromRGB(40, 40, 44), Accent = Color3.fromRGB(232, 190, 90), Finish = "Marble", MetalFinish = "Gold" },
		{ Id = "Rustbucket", Name = "Rustbucket", Weapon = "Rifle", Rarity = "Rare", Body = Color3.fromRGB(150, 84, 50), Metal = Color3.fromRGB(80, 60, 48), Accent = Color3.fromRGB(200, 140, 90), Finish = "Rust", MetalFinish = "Rust" },
		{ Id = "DiamondPlate", Name = "Diamond Plate", Weapon = "Rifle", Rarity = "Rare", Body = Color3.fromRGB(196, 200, 208), Metal = Color3.fromRGB(80, 84, 92), Accent = Color3.fromRGB(230, 234, 240), Finish = "Tread" },
		{ Id = "Frostbite", Name = "Frostbite", Weapon = "Rifle", Rarity = "Rare", Body = Color3.fromRGB(170, 214, 240), Metal = Color3.fromRGB(70, 96, 120), Accent = Color3.fromRGB(220, 245, 255), Finish = "Frost" },
		{ Id = "Obsidian", Name = "Obsidian", Weapon = "Rifle", Rarity = "Rare", Body = Color3.fromRGB(20, 20, 24), Metal = Color3.fromRGB(10, 10, 12), Accent = Color3.fromRGB(200, 206, 216), Finish = "Chrome", MetalFinish = "Chrome" },
		{ Id = "NeonTiger", Name = "Neon Tiger", Weapon = "Rifle", Rarity = "Epic", Body = Color3.fromRGB(255, 120, 20), Stock = Color3.fromRGB(24, 24, 26), Metal = Color3.fromRGB(22, 22, 24), Accent = Color3.fromRGB(255, 200, 40), Finish = "Gloss", Glow = true },
		{ Id = "ToxicWaste", Name = "Toxic Waste", Weapon = "Rifle", Rarity = "Epic", Body = Color3.fromRGB(44, 52, 40), Metal = Color3.fromRGB(24, 28, 22), Accent = Color3.fromRGB(140, 255, 60), Finish = "Rust", Glow = true },
		{ Id = "IceQueen", Name = "Ice Queen", Weapon = "Rifle", Rarity = "Epic", Body = Color3.fromRGB(200, 232, 250), Metal = Color3.fromRGB(110, 140, 170), Accent = Color3.fromRGB(90, 220, 255), Finish = "Frost", Glow = true },
		{ Id = "CrimsonEdge", Name = "Crimson Edge", Weapon = "Rifle", Rarity = "Epic", Body = Color3.fromRGB(28, 24, 26), Metal = Color3.fromRGB(16, 14, 16), Accent = Color3.fromRGB(255, 40, 56), Finish = "Chrome", Glow = true },
		{ Id = "Electric", Name = "Electric", Weapon = "Rifle", Rarity = "Epic", Body = Color3.fromRGB(30, 34, 52), Metal = Color3.fromRGB(18, 20, 30), Accent = Color3.fromRGB(255, 236, 60), Finish = "Metal", Glow = true },
		{ Id = "Hologram", Name = "Hologram", Weapon = "Rifle", Rarity = "Legendary", Body = Color3.fromRGB(80, 220, 255), Stock = Color3.fromRGB(80, 220, 255), Metal = Color3.fromRGB(30, 60, 90), Accent = Color3.fromRGB(140, 240, 255), Pulse = Color3.fromRGB(200, 120, 255), Finish = "Hologram", StockFinish = "Hologram", Glow = true, Sparkle = true },
		{ Id = "Crystal", Name = "Crystal", Weapon = "Rifle", Rarity = "Legendary", Body = Color3.fromRGB(190, 230, 255), Stock = Color3.fromRGB(170, 210, 250), Metal = Color3.fromRGB(120, 150, 190), Accent = Color3.fromRGB(240, 250, 255), Pulse = Color3.fromRGB(150, 200, 255), Finish = "Crystal", StockFinish = "Crystal", MetalFinish = "Chrome", Glow = true, Sparkle = true },
		{ Id = "Aurora", Name = "Aurora", Weapon = "Rifle", Rarity = "Legendary", Body = Color3.fromRGB(24, 40, 60), Metal = Color3.fromRGB(16, 24, 36), Accent = Color3.fromRGB(80, 255, 170), Pulse = Color3.fromRGB(190, 90, 255), Finish = "Pearl", Glow = true, Sparkle = true },
		{ Id = "Midas", Name = "Midas", Weapon = "Rifle", Rarity = "Legendary", Body = Color3.fromRGB(240, 190, 70), Stock = Color3.fromRGB(230, 176, 60), Metal = Color3.fromRGB(200, 150, 50), Accent = Color3.fromRGB(255, 244, 190), Pulse = Color3.fromRGB(255, 190, 60), Finish = "Gold", StockFinish = "Gold", MetalFinish = "Gold", Glow = true, Sparkle = true },

		{ Id = "Slate", Name = "Slate", Weapon = "Rifle", Rarity = "Common", Body = Color3.fromRGB(110, 116, 124), Metal = Color3.fromRGB(46, 48, 54), Accent = Color3.fromRGB(170, 176, 186), Finish = "Stone" },
		{ Id = "Tundra", Name = "Tundra", Weapon = "Rifle", Rarity = "Common", Body = Color3.fromRGB(196, 200, 190), Metal = Color3.fromRGB(70, 74, 70), Accent = Color3.fromRGB(230, 232, 226) },
		{ Id = "Crimson", Name = "Crimson", Weapon = "Rifle", Rarity = "Common", Body = Color3.fromRGB(130, 30, 36), Metal = Color3.fromRGB(36, 30, 32), Accent = Color3.fromRGB(200, 170, 170) },
		{ Id = "Lime", Name = "Lime", Weapon = "Rifle", Rarity = "Uncommon", Body = Color3.fromRGB(170, 230, 60), Stock = Color3.fromRGB(40, 44, 40), Metal = Color3.fromRGB(30, 34, 30), Accent = Color3.fromRGB(230, 255, 170), Finish = "Gloss" },
		{ Id = "Royal", Name = "Royal", Weapon = "Rifle", Rarity = "Uncommon", Body = Color3.fromRGB(60, 40, 140), Stock = Color3.fromRGB(220, 190, 90), Metal = Color3.fromRGB(30, 26, 50), Accent = Color3.fromRGB(230, 200, 110), Finish = "Gloss" },
		{ Id = "Sunset", Name = "Sunset", Weapon = "Rifle", Rarity = "Uncommon", Body = Color3.fromRGB(255, 110, 90), Stock = Color3.fromRGB(110, 50, 130), Metal = Color3.fromRGB(40, 26, 40), Accent = Color3.fromRGB(255, 200, 120), Finish = "Gloss" },
		{ Id = "Copper", Name = "Copper", Weapon = "Rifle", Rarity = "Rare", Body = Color3.fromRGB(196, 110, 64), Metal = Color3.fromRGB(80, 50, 36), Accent = Color3.fromRGB(255, 190, 140), Finish = "Metal", MetalFinish = "Metal" },
		{ Id = "Granite", Name = "Granite", Weapon = "Rifle", Rarity = "Rare", Body = Color3.fromRGB(120, 116, 112), Stock = Color3.fromRGB(60, 58, 56), Metal = Color3.fromRGB(30, 30, 32), Accent = Color3.fromRGB(220, 90, 60), Finish = "Stone" },
		{ Id = "Glacier", Name = "Glacier", Weapon = "Rifle", Rarity = "Rare", Body = Color3.fromRGB(120, 200, 240), Stock = Color3.fromRGB(240, 250, 255), Metal = Color3.fromRGB(60, 90, 120), Accent = Color3.fromRGB(240, 250, 255), Finish = "Frost", StockFinish = "Pearl" },
		{ Id = "Ghost", Name = "Ghost", Weapon = "Rifle", Rarity = "Epic", Body = Color3.fromRGB(230, 236, 244), Metal = Color3.fromRGB(140, 150, 166), Accent = Color3.fromRGB(160, 230, 255), Finish = "Pearl", Glow = true },
		{ Id = "Venom", Name = "Venom", Weapon = "Rifle", Rarity = "Epic", Body = Color3.fromRGB(20, 24, 20), Stock = Color3.fromRGB(70, 160, 40), Metal = Color3.fromRGB(14, 16, 14), Accent = Color3.fromRGB(170, 255, 60), Finish = "Gloss", Glow = true },
		{ Id = "Magma", Name = "Magma", Weapon = "Rifle", Rarity = "Legendary", Body = Color3.fromRGB(40, 22, 18), Metal = Color3.fromRGB(26, 16, 14), Accent = Color3.fromRGB(255, 110, 20), Pulse = Color3.fromRGB(255, 40, 10), Finish = "Stone", Glow = true, Sparkle = true, Aura = true },
		{ Id = "Galaxy", Name = "Galaxy", Weapon = "Rifle", Rarity = "Epic", Body = Color3.fromRGB(40, 20, 90), Stock = Color3.fromRGB(20, 10, 50), Metal = Color3.fromRGB(14, 10, 30), Accent = Color3.fromRGB(190, 120, 255), Finish = "Hologram", StockFinish = "Pearl", Glow = true, Sparkle = true, Elite = true },
		{ Id = "Plasma", Name = "Plasma", Weapon = "Rifle", Rarity = "Epic", Body = Color3.fromRGB(20, 30, 60), Metal = Color3.fromRGB(10, 14, 30), Accent = Color3.fromRGB(60, 200, 255), Finish = "Chrome", Glow = true, Elite = true, Aura = true },
		{ Id = "Diamond", Name = "Diamond", Weapon = "Rifle", Rarity = "Legendary", Body = Color3.fromRGB(235, 245, 255), Stock = Color3.fromRGB(220, 235, 250), Metal = Color3.fromRGB(200, 210, 225), Accent = Color3.fromRGB(255, 255, 255), Pulse = Color3.fromRGB(150, 220, 255), Finish = "Crystal", StockFinish = "Crystal", MetalFinish = "Chrome", Glow = true, Sparkle = true, Elite = true },
		{ Id = "Glitch", Name = "Glitch", Weapon = "Rifle", Rarity = "Legendary", Body = Color3.fromRGB(10, 10, 14), Stock = Color3.fromRGB(255, 40, 180), Metal = Color3.fromRGB(10, 10, 14), Accent = Color3.fromRGB(40, 255, 230), Pulse = Color3.fromRGB(255, 40, 180), Finish = "Hologram", StockFinish = "Hologram", Glow = true, Sparkle = true, Elite = true, Aura = true },
		{ Id = "Phoenix", Name = "Phoenix", Weapon = "Rifle", Rarity = "Legendary", Body = Color3.fromRGB(255, 140, 30), Stock = Color3.fromRGB(200, 40, 20), Metal = Color3.fromRGB(60, 20, 10), Accent = Color3.fromRGB(255, 220, 80), Pulse = Color3.fromRGB(255, 60, 20), Finish = "Gold", Glow = true, Sparkle = true, Elite = true, Aura = true },
		{ Id = "SecretDragonfire", Name = "Dragonfire", Weapon = "Rifle", Rarity = "Secret", Body = Color3.fromRGB(30, 10, 8), Stock = Color3.fromRGB(120, 20, 10), Metal = Color3.fromRGB(20, 8, 6), Accent = Color3.fromRGB(255, 90, 20), Pulse = Color3.fromRGB(255, 30, 10), Finish = "Stone", Template = "Dragonfire", Glow = true, Sparkle = true, Elite = true, Aura = true },
		{ Id = "SecretVoidReaper", Name = "Void Reaper", Weapon = "Rifle", Rarity = "Secret", Body = Color3.fromRGB(8, 6, 14), Stock = Color3.fromRGB(40, 10, 70), Metal = Color3.fromRGB(4, 4, 8), Accent = Color3.fromRGB(170, 60, 255), Pulse = Color3.fromRGB(60, 0, 140), Finish = "Hologram", StockFinish = "Hologram", Template = "VoidReaper", Glow = true, Sparkle = true, Elite = true, Aura = true },
		{ Id = "SecretCelestial", Name = "Celestial", Weapon = "Rifle", Rarity = "Secret", Body = Color3.fromRGB(250, 248, 240), Stock = Color3.fromRGB(255, 220, 120), Metal = Color3.fromRGB(230, 200, 120), Accent = Color3.fromRGB(255, 250, 220), Pulse = Color3.fromRGB(140, 200, 255), Finish = "Pearl", StockFinish = "Gold", MetalFinish = "Gold", Template = "Celestial", Glow = true, Sparkle = true, Elite = true, Aura = true },

		-- KNIFE
		{ Id = "KnifeStonewash", Name = "Stonewash", Weapon = "Knife", Rarity = "Common", Blade = Color3.fromRGB(150, 154, 160), Body = Color3.fromRGB(58, 60, 64), Metal = Color3.fromRGB(90, 92, 96), Accent = Color3.fromRGB(200, 200, 200) },
		{ Id = "KnifeDesert", Name = "Desert", Weapon = "Knife", Rarity = "Common", Blade = Color3.fromRGB(170, 166, 156), Body = Color3.fromRGB(176, 150, 106), Metal = Color3.fromRGB(96, 84, 64), Accent = Color3.fromRGB(230, 214, 176) },
		{ Id = "KnifeBlackout", Name = "Blackout", Weapon = "Knife", Rarity = "Uncommon", Blade = Color3.fromRGB(40, 42, 46), Body = Color3.fromRGB(22, 22, 24), Metal = Color3.fromRGB(60, 62, 66), Accent = Color3.fromRGB(140, 140, 150), Finish = "Gloss" },
		{ Id = "KnifeJungle", Name = "Jungle", Weapon = "Knife", Rarity = "Uncommon", Blade = Color3.fromRGB(176, 182, 190), Body = Color3.fromRGB(70, 110, 60), Metal = Color3.fromRGB(40, 50, 36), Accent = Color3.fromRGB(170, 220, 90) },
		{ Id = "KnifeMirror", Name = "Mirror", Weapon = "Knife", Rarity = "Rare", Blade = Color3.fromRGB(220, 226, 234), Body = Color3.fromRGB(30, 32, 38), Metal = Color3.fromRGB(180, 186, 196), Accent = Color3.fromRGB(240, 244, 250), Finish = "Chrome" },
		{ Id = "KnifeSapphire", Name = "Sapphire", Weapon = "Knife", Rarity = "Rare", Blade = Color3.fromRGB(70, 120, 220), Body = Color3.fromRGB(24, 30, 52), Metal = Color3.fromRGB(150, 170, 210), Accent = Color3.fromRGB(110, 190, 255), Finish = "Metal" },
		{ Id = "KnifeToxic", Name = "Toxic", Weapon = "Knife", Rarity = "Epic", Blade = Color3.fromRGB(40, 44, 40), Body = Color3.fromRGB(26, 28, 26), Metal = Color3.fromRGB(60, 70, 60), Accent = Color3.fromRGB(130, 255, 80), Finish = "Gloss", Glow = true },
		{ Id = "KnifeNeon", Name = "Neon Edge", Weapon = "Knife", Rarity = "Epic", Blade = Color3.fromRGB(46, 30, 70), Body = Color3.fromRGB(20, 16, 32), Metal = Color3.fromRGB(80, 60, 110), Accent = Color3.fromRGB(255, 70, 200), Finish = "Gloss", Glow = true },
		{ Id = "KnifeGold", Name = "Gilded", Weapon = "Knife", Rarity = "Legendary", Blade = Color3.fromRGB(240, 190, 70), Body = Color3.fromRGB(40, 30, 20), Metal = Color3.fromRGB(255, 220, 120), Accent = Color3.fromRGB(255, 240, 170), Finish = "Gold", Glow = true, Pulse = Color3.fromRGB(255, 170, 40), Sparkle = true },
		{ Id = "KnifeInferno", Name = "Inferno", Weapon = "Knife", Rarity = "Legendary", Blade = Color3.fromRGB(60, 24, 18), Body = Color3.fromRGB(24, 14, 12), Metal = Color3.fromRGB(120, 50, 30), Accent = Color3.fromRGB(255, 120, 30), Finish = "Gloss", Glow = true, Pulse = Color3.fromRGB(255, 40, 20), Sparkle = true },
		{ Id = "KnifeField", Name = "Field", Weapon = "Knife", Rarity = "Common", Blade = Color3.fromRGB(150, 154, 160), Body = Color3.fromRGB(96, 104, 64), Metal = Color3.fromRGB(60, 64, 48), Accent = Color3.fromRGB(200, 200, 180) },
		{ Id = "KnifeNight", Name = "Night", Weapon = "Knife", Rarity = "Common", Blade = Color3.fromRGB(70, 72, 78), Body = Color3.fromRGB(28, 30, 34), Metal = Color3.fromRGB(46, 48, 52), Accent = Color3.fromRGB(150, 150, 160) },
		{ Id = "KnifeSand", Name = "Sand", Weapon = "Knife", Rarity = "Common", Blade = Color3.fromRGB(176, 172, 164), Body = Color3.fromRGB(200, 176, 130), Metal = Color3.fromRGB(120, 104, 80), Accent = Color3.fromRGB(230, 214, 176) },
		{ Id = "KnifeUrban", Name = "Urban", Weapon = "Knife", Rarity = "Common", Blade = Color3.fromRGB(190, 194, 200), Body = Color3.fromRGB(210, 212, 216), Metal = Color3.fromRGB(70, 72, 78), Accent = Color3.fromRGB(240, 240, 240) },
		{ Id = "KnifeCherry", Name = "Cherry", Weapon = "Knife", Rarity = "Uncommon", Blade = Color3.fromRGB(200, 206, 214), Body = Color3.fromRGB(200, 30, 44), Metal = Color3.fromRGB(40, 36, 38), Accent = Color3.fromRGB(255, 210, 210), Finish = "Gloss" },
		{ Id = "KnifeWalnut", Name = "Walnut", Weapon = "Knife", Rarity = "Uncommon", Blade = Color3.fromRGB(176, 182, 190), Body = Color3.fromRGB(110, 70, 40), Metal = Color3.fromRGB(150, 120, 80), Accent = Color3.fromRGB(230, 210, 170), HandleFinish = "Wood" },
		{ Id = "KnifeArctic", Name = "Arctic", Weapon = "Knife", Rarity = "Uncommon", Blade = Color3.fromRGB(220, 230, 240), Body = Color3.fromRGB(236, 242, 248), Metal = Color3.fromRGB(140, 160, 180), Accent = Color3.fromRGB(170, 220, 250), Finish = "Gloss" },
		{ Id = "KnifeBubblegum", Name = "Bubblegum", Weapon = "Knife", Rarity = "Uncommon", Blade = Color3.fromRGB(255, 200, 230), Body = Color3.fromRGB(255, 140, 200), Metal = Color3.fromRGB(120, 80, 110), Accent = Color3.fromRGB(255, 235, 245), Finish = "Gloss" },
		{ Id = "KnifeDamascus", Name = "Damascus", Weapon = "Knife", Rarity = "Rare", Blade = Color3.fromRGB(140, 144, 152), Body = Color3.fromRGB(40, 30, 26), Metal = Color3.fromRGB(170, 140, 90), Accent = Color3.fromRGB(210, 214, 220), Finish = "Marble", HandleFinish = "Wood" },
		{ Id = "KnifeRust", Name = "Rust", Weapon = "Knife", Rarity = "Rare", Blade = Color3.fromRGB(150, 90, 56), Body = Color3.fromRGB(60, 46, 36), Metal = Color3.fromRGB(110, 70, 46), Accent = Color3.fromRGB(200, 140, 90), Finish = "Rust" },
		{ Id = "KnifeObsidian", Name = "Obsidian", Weapon = "Knife", Rarity = "Rare", Blade = Color3.fromRGB(22, 22, 26), Body = Color3.fromRGB(14, 14, 16), Metal = Color3.fromRGB(190, 196, 206), Accent = Color3.fromRGB(200, 206, 216), Finish = "Chrome" },
		{ Id = "KnifeFrost", Name = "Frost", Weapon = "Knife", Rarity = "Rare", Blade = Color3.fromRGB(180, 220, 245), Body = Color3.fromRGB(90, 120, 150), Metal = Color3.fromRGB(150, 190, 220), Accent = Color3.fromRGB(220, 245, 255), Finish = "Frost" },
		{ Id = "KnifeElectric", Name = "Electric", Weapon = "Knife", Rarity = "Epic", Blade = Color3.fromRGB(40, 44, 64), Body = Color3.fromRGB(20, 22, 32), Metal = Color3.fromRGB(60, 64, 90), Accent = Color3.fromRGB(255, 236, 60), Finish = "Metal", Glow = true },
		{ Id = "KnifeCrimson", Name = "Crimson Edge", Weapon = "Knife", Rarity = "Epic", Blade = Color3.fromRGB(30, 26, 28), Body = Color3.fromRGB(16, 14, 16), Metal = Color3.fromRGB(80, 30, 36), Accent = Color3.fromRGB(255, 40, 56), Finish = "Chrome", Glow = true },
		{ Id = "KnifeIce", Name = "Ice Queen", Weapon = "Knife", Rarity = "Epic", Blade = Color3.fromRGB(200, 232, 250), Body = Color3.fromRGB(110, 140, 170), Metal = Color3.fromRGB(160, 200, 230), Accent = Color3.fromRGB(90, 220, 255), Finish = "Frost", Glow = true },
		{ Id = "KnifeHologram", Name = "Hologram", Weapon = "Knife", Rarity = "Legendary", Blade = Color3.fromRGB(80, 220, 255), Body = Color3.fromRGB(30, 60, 90), Metal = Color3.fromRGB(80, 220, 255), Accent = Color3.fromRGB(140, 240, 255), Pulse = Color3.fromRGB(200, 120, 255), Finish = "Hologram", Glow = true, Sparkle = true },
		{ Id = "KnifeCrystal", Name = "Crystal", Weapon = "Knife", Rarity = "Legendary", Blade = Color3.fromRGB(190, 230, 255), Body = Color3.fromRGB(120, 150, 190), Metal = Color3.fromRGB(220, 235, 250), Accent = Color3.fromRGB(240, 250, 255), Pulse = Color3.fromRGB(150, 200, 255), Finish = "Crystal", MetalFinish = "Chrome", Glow = true, Sparkle = true },
		{ Id = "KnifeAurora", Name = "Aurora", Weapon = "Knife", Rarity = "Legendary", Blade = Color3.fromRGB(40, 60, 90), Body = Color3.fromRGB(20, 28, 40), Metal = Color3.fromRGB(80, 255, 170), Accent = Color3.fromRGB(80, 255, 170), Pulse = Color3.fromRGB(190, 90, 255), Finish = "Pearl", Glow = true, Sparkle = true },
		{ Id = "KnifeMidas", Name = "Midas", Weapon = "Knife", Rarity = "Legendary", Blade = Color3.fromRGB(240, 190, 70), Body = Color3.fromRGB(200, 150, 50), Metal = Color3.fromRGB(255, 220, 120), Accent = Color3.fromRGB(255, 244, 190), Pulse = Color3.fromRGB(255, 190, 60), Finish = "Gold", MetalFinish = "Gold", HandleFinish = "Gold", Glow = true, Sparkle = true },
		{ Id = "KnifeSlate", Name = "Slate", Weapon = "Knife", Rarity = "Common", Blade = Color3.fromRGB(120, 124, 130), Body = Color3.fromRGB(110, 116, 124), Metal = Color3.fromRGB(60, 62, 68), Accent = Color3.fromRGB(180, 180, 190), HandleFinish = "Stone" },
		{ Id = "KnifeCrimsonGrip", Name = "Crimson Grip", Weapon = "Knife", Rarity = "Common", Blade = Color3.fromRGB(176, 182, 190), Body = Color3.fromRGB(130, 30, 36), Metal = Color3.fromRGB(60, 40, 42), Accent = Color3.fromRGB(220, 180, 180) },
		{ Id = "KnifeLime", Name = "Lime", Weapon = "Knife", Rarity = "Uncommon", Blade = Color3.fromRGB(200, 206, 214), Body = Color3.fromRGB(170, 230, 60), Metal = Color3.fromRGB(40, 44, 40), Accent = Color3.fromRGB(230, 255, 170), Finish = "Gloss" },
		{ Id = "KnifeRoyal", Name = "Royal", Weapon = "Knife", Rarity = "Uncommon", Blade = Color3.fromRGB(220, 200, 120), Body = Color3.fromRGB(60, 40, 140), Metal = Color3.fromRGB(220, 190, 90), Accent = Color3.fromRGB(240, 220, 140), Finish = "Gloss" },
		{ Id = "KnifeCopper", Name = "Copper", Weapon = "Knife", Rarity = "Rare", Blade = Color3.fromRGB(196, 110, 64), Body = Color3.fromRGB(40, 30, 26), Metal = Color3.fromRGB(160, 90, 50), Accent = Color3.fromRGB(255, 190, 140), Finish = "Metal" },
		{ Id = "KnifeGlacier", Name = "Glacier", Weapon = "Knife", Rarity = "Rare", Blade = Color3.fromRGB(150, 215, 245), Body = Color3.fromRGB(240, 250, 255), Metal = Color3.fromRGB(120, 170, 210), Accent = Color3.fromRGB(240, 250, 255), Finish = "Frost", HandleFinish = "Pearl" },
		{ Id = "KnifeGhost", Name = "Ghost", Weapon = "Knife", Rarity = "Epic", Blade = Color3.fromRGB(230, 236, 244), Body = Color3.fromRGB(200, 210, 224), Metal = Color3.fromRGB(160, 170, 186), Accent = Color3.fromRGB(160, 230, 255), Finish = "Pearl", Glow = true },
		{ Id = "KnifeMagma", Name = "Magma", Weapon = "Knife", Rarity = "Legendary", Blade = Color3.fromRGB(40, 22, 18), Body = Color3.fromRGB(26, 16, 14), Metal = Color3.fromRGB(80, 30, 16), Accent = Color3.fromRGB(255, 110, 20), Pulse = Color3.fromRGB(255, 40, 10), Finish = "Stone", Glow = true, Sparkle = true, Aura = true },
		{ Id = "KnifeGalaxy", Name = "Galaxy", Weapon = "Knife", Rarity = "Epic", Blade = Color3.fromRGB(60, 30, 120), Body = Color3.fromRGB(20, 10, 50), Metal = Color3.fromRGB(120, 80, 200), Accent = Color3.fromRGB(190, 120, 255), Finish = "Hologram", Glow = true, Sparkle = true, Elite = true },
		{ Id = "KnifeDiamond", Name = "Diamond", Weapon = "Knife", Rarity = "Legendary", Blade = Color3.fromRGB(235, 245, 255), Body = Color3.fromRGB(200, 210, 225), Metal = Color3.fromRGB(255, 255, 255), Accent = Color3.fromRGB(255, 255, 255), Pulse = Color3.fromRGB(150, 220, 255), Finish = "Crystal", MetalFinish = "Chrome", Glow = true, Sparkle = true, Elite = true },
		{ Id = "KnifeGlitch", Name = "Glitch", Weapon = "Knife", Rarity = "Legendary", Blade = Color3.fromRGB(10, 10, 14), Body = Color3.fromRGB(255, 40, 180), Metal = Color3.fromRGB(40, 255, 230), Accent = Color3.fromRGB(40, 255, 230), Pulse = Color3.fromRGB(255, 40, 180), Finish = "Hologram", HandleFinish = "Hologram", Glow = true, Sparkle = true, Elite = true, Aura = true },
		{ Id = "KnifePhoenix", Name = "Phoenix", Weapon = "Knife", Rarity = "Legendary", Blade = Color3.fromRGB(255, 140, 30), Body = Color3.fromRGB(200, 40, 20), Metal = Color3.fromRGB(255, 200, 80), Accent = Color3.fromRGB(255, 220, 80), Pulse = Color3.fromRGB(255, 60, 20), Finish = "Gold", Glow = true, Sparkle = true, Elite = true, Aura = true },
		{ Id = "SecretKarambit", Name = "Shadow Karambit", Weapon = "Knife", Rarity = "Secret", Blade = Color3.fromRGB(20, 16, 30), Body = Color3.fromRGB(8, 6, 12), Metal = Color3.fromRGB(120, 40, 200), Accent = Color3.fromRGB(170, 60, 255), Pulse = Color3.fromRGB(60, 0, 140), Finish = "Hologram", Template = "ShadowKarambit", Glow = true, Sparkle = true, Elite = true, Aura = true },
		{ Id = "SecretBloodfang", Name = "Bloodfang", Weapon = "Knife", Rarity = "Secret", Blade = Color3.fromRGB(120, 10, 16), Body = Color3.fromRGB(20, 8, 8), Metal = Color3.fromRGB(60, 10, 12), Accent = Color3.fromRGB(255, 30, 40), Pulse = Color3.fromRGB(120, 0, 10), Finish = "Chrome", Template = "Bloodfang", Glow = true, Sparkle = true, Elite = true, Aura = true },
		{ Id = "SecretStarforged", Name = "Starforged", Weapon = "Knife", Rarity = "Secret", Blade = Color3.fromRGB(250, 248, 240), Body = Color3.fromRGB(255, 220, 120), Metal = Color3.fromRGB(230, 200, 120), Accent = Color3.fromRGB(255, 250, 220), Pulse = Color3.fromRGB(140, 200, 255), Finish = "Pearl", MetalFinish = "Gold", HandleFinish = "Gold", Template = "Starforged", Glow = true, Sparkle = true, Elite = true, Aura = true },
	},
}

----------------------------------------------------------------------------
-- SHOP (Robux). Create the products on the Roblox website (Creator Hub >
-- your experience > Monetization > Developer Products / Passes) and paste
-- their ids here. Id 0 = not set up yet (the shop shows it, but can't sell).
----------------------------------------------------------------------------
Config.Shop = {
	-- Credit packs (Developer Products): Credits open Elite crates
	CreditPacks = {
		{ Id = 0, Credits = 100, Robux = 79, Name = "HANDFUL" },
		{ Id = 0, Credits = 550, Robux = 399, Name = "STACK", Tag = "+10%" },
		{ Id = 0, Credits = 1200, Robux = 799, Name = "CRATE LOAD", Tag = "+20%" },
		{ Id = 0, Credits = 2600, Robux = 1499, Name = "VAULT", Tag = "BEST VALUE" },
	},
	-- Key packs for people who'd rather not grind (Developer Products)
	KeyPacks = {
		{ Id = 0, Keys = 30, Robux = 49, Name = "KEY RING" },
	},
	-- Game Passes
	Passes = {
		VIP = { Id = 0, Robux = 299, Name = "VIP", Perks = "2x keys from every match and a gold VIP tag over your head" },
	},
}

----------------------------------------------------------------------------
-- RANKED (RankService): every player-vs-player match moves your rating
-- (Elo: beating someone rated above you is worth more). Matches against
-- the bot don't count. The lobby's leaderboard wall shows the top players.
----------------------------------------------------------------------------
Config.Rank = {
	StartRating = 1000,
	K = 32, -- the most a normal match can move your rating
	PlacementK = 48, -- (bigger swings for your first PlacementMatches matches)
	PlacementMatches = 5,
	LeaderboardSize = 10,
	LeaderboardRefresh = 60, -- seconds between leaderboard updates
	-- tiers by rating (the highest Min you reach)
	Tiers = {
		{ Name = "BRONZE", Min = 0, Color = Color3.fromRGB(196, 128, 82) },
		{ Name = "SILVER", Min = 900, Color = Color3.fromRGB(190, 198, 210) },
		{ Name = "GOLD", Min = 1100, Color = Color3.fromRGB(255, 196, 60) },
		{ Name = "PLATINUM", Min = 1300, Color = Color3.fromRGB(90, 220, 200) },
		{ Name = "DIAMOND", Min = 1500, Color = Color3.fromRGB(110, 170, 255) },
		{ Name = "CHAMPION", Min = 1700, Color = Color3.fromRGB(255, 80, 110) },
	},
}

-- The tier for a rating.
function Config.RankTier(rating)
	local best = Config.Rank.Tiers[1]
	for _, tier in ipairs(Config.Rank.Tiers) do
		if (rating or 0) >= tier.Min then
			best = tier
		end
	end
	return best
end

----------------------------------------------------------------------------
-- MATCH FLOW
----------------------------------------------------------------------------
Config.Match = {
	RoundsToWin = 5, -- first to 5 round wins (best of 9)
	CountdownTime = 3, -- "3, 2, 1, GO"
	RoundEndTime = 6.5, -- pause after a kill before the pick screen (the loser watches the kill cam + victory pose)
	PickTime = 15, -- seconds the loser has to pick a card
	PickRevealTime = 1.6, -- how long the chosen card is shown before the next round
	VictoryTime = 7, -- victory screen length before returning to lobby
	MaxRoundTime = 150, -- if nobody dies, higher health % wins the round (tie = replay)
	CardsPerPick = 5,
	-- a random map each match (never the same twice in a row); false = always use Map
	Maps = { "Polygon", "Crossfire", "Nuketown", "Canyon", "Pillars", "Bridges", "Ziggurat", "Quarry" },
	Map = "Polygon", -- "Polygon" (compact Rivals-style arena, lots of cover), "Nuketown" (the classic cul-de-sac), "Crossfire" (compact Rivals-style), "Simple" (open ramps arena), "Downtown" (detailed city) or "Classic"
	MaxArenas = 4, -- how many matches can run at the same time in one server
	ArenaSpacing = 2000, -- distance between arena copies
	VoidDepth = 80, -- falling this far below the arena floor kills you
	InviteTime = 20, -- seconds a duel challenge / rematch request stays open
	RematchWindow = 45, -- seconds after a match you can still ask for a rematch
}

-- KILL CAM: when you're killed, replay the last few seconds through your
-- killer's eyes (their aim, their shot), ending in slow motion.
Config.KillCam = {
	Enabled = true,
	Delay = 0.35, -- seconds after the kill before it starts
	Length = 2.6, -- seconds of replay
	SlowMoTime = 0.55, -- the last part plays in slow motion...
	SlowMoSpeed = 0.35, -- ...at this speed
	FieldOfView = 70,
	VictoryTime = 1.7, -- then the camera cuts to the winner striking a victory pose
}

----------------------------------------------------------------------------
-- LOBBY PRACTICE RANGE
----------------------------------------------------------------------------
Config.Lobby = {
	QueueKey = Enum.KeyCode.F, -- press in the lobby to find a match
	DummyHealth = 100,
	DummyRespawnTime = 1.2,
}

----------------------------------------------------------------------------
-- ADMIN + BOT
-- Admins start a match against a bot with N (controller: RB) in the lobby,
-- or by chatting "/bot", "/bot easy" or "/bot hard". "/endbot" ends it.
----------------------------------------------------------------------------
Config.Admin = {
	UserIds = {}, -- extra admins, e.g. { 12345678 }
	AllowEveryoneInStudio = true, -- anyone can use admin commands when testing in Studio
	BotForEveryone = false, -- true = every player can start a bot match
}

-- How the bot plays at each difficulty.
--   ReactionTime    seconds it needs to see you before it shoots
--   AimError        degrees of aim wobble (shrinks the longer it tracks you)
--   HeadshotChance  how often it aims for the head
--   ExtraShotDelay  extra seconds between shots on top of the bolt time
--   WalkSpeed       how fast it runs around
Config.Bot = {
	DefaultDifficulty = "Normal",
	Difficulties = {
		Easy = { ReactionTime = 0.95, AimError = 3.4, HeadshotChance = 0.06, ExtraShotDelay = 1.3, WalkSpeed = 22 },
		Normal = { ReactionTime = 0.6, AimError = 1.8, HeadshotChance = 0.18, ExtraShotDelay = 0.6, WalkSpeed = 27 },
		Hard = { ReactionTime = 0.32, AimError = 0.8, HeadshotChance = 0.38, ExtraShotDelay = 0.2, WalkSpeed = 32 },
	},
	PathInterval = 1.4, -- seconds between path recomputes
	StrafeTime = { 0.5, 1.3 }, -- seconds per strafe direction while fighting
	JumpChance = 0.18, -- chance to hop each strafe change
}

----------------------------------------------------------------------------
-- PLAYER / HEALTH
----------------------------------------------------------------------------
Config.Player = {
	MaxHealth = 100,
	-- Play as your own Roblox avatar (always loaded at the standard body
	-- size so hitboxes are fair). false = the flat one-colour characters.
	UseAvatars = true,
}

----------------------------------------------------------------------------
-- CAMERA
----------------------------------------------------------------------------
Config.Camera = {
	BaseFOV = 82,
	ScopeFOV = 22, -- field of view while fully scoped
	FOVLerpSpeed = 12, -- how quickly FOV follows its target
	SprintFOVKick = 5,
	SlideFOVKick = 9,
	BlinkFOVKick = 18,
	WallRunFOVKick = 6,
	SpeedFOVPerStud = 0.22, -- extra FOV per stud/s above sprint speed
	MaxSpeedFOV = 14,

	WallRunTilt = 11, -- camera roll while wall running
	SlideTilt = 5,
	StrafeTilt = 1.2, -- tiny roll when strafing
	TiltLerpSpeed = 10,

	SlideCameraDrop = 1.7, -- studs the camera lowers while sliding
	CameraDropLerpSpeed = 14,

	RecoilPitch = 2.4, -- degrees the aim kicks up per shot (hipfire)
	ScopedRecoilPitch = 1.2,

	FirstPersonInLobby = true, -- lobby is first person too (you can practise there)
	HeadBob = 0.07, -- studs of camera bob while running (0 = off)
	LandingDip = 0.012, -- camera dip per stud/s of landing speed
	MaxLandingDip = 0.9,
}

-- Viewmodel (first-person arms + gun) animation
Config.Viewmodel = {
	EquipTime = 0.45, -- gun raise animation when you spawn
	SwayAmount = 0.06, -- how much the gun lags behind the mouse
	BobAmount = 1.0, -- walk bob strength
	InspectKey = Enum.KeyCode.V, -- admire your rifle
	-- Imported rifle mesh (assets/SniperRifle.glb, see README). When a model
	-- with this name is in ReplicatedStorage (or Workspace), it replaces the
	-- flat-part rifle for everyone.
	UseImportedRifle = true,
	MeshTemplate = "SniperRifle",
	MeshYaw = nil, -- force the model's turn in degrees (0/90/180/270) if it imports facing the wrong way
	-- "Always" = paint the rifle in flat colours (tan body, black scope, dark
	-- stock...). "Auto" = keep the imported textures if they came through.
	MeshPaint = "Always",
	-- First-person arms are a copy of your avatar's arms (skin colour, shirt).
	-- false = the plain gloved arms.
	UseAvatarArms = true,
	ArmThickness = 0.3, -- avatar arms are scaled down to this so they fit the rifle
}

-- Defaults for the settings menu (players can change and save these).
Config.SettingsDefaults = {
	-- mouse / keyboard
	Sensitivity = 1.0, -- normal look sensitivity multiplier
	ScopedSensitivity = 0.45, -- multiplier used while scoped
	-- controller
	ControllerSensitivity = 1.0,
	ControllerScopedSensitivity = 0.5,
	ControllerDeadzone = 0.15, -- right stick inputs smaller than this are ignored
	InvertY = false, -- controller / touch: push up to look down
	-- touch (phones / tablets)
	TouchSensitivity = 1.0,
	TouchScopedSensitivity = 0.4,
	-- general
	FieldOfView = 82, -- your normal field of view
	ToggleScope = false, -- false = hold to scope, true = press to toggle
	AimAssist = true, -- controller aim assist on/off (players can change it)
	-- Binds = { Keyboard = { [action] = "KeyName" }, Gamepad = { ... } } (see Client/Keybinds.lua)
}
Config.SettingsLimits = {
	Sensitivity = { Min = 0.1, Max = 3.0 },
	ScopedSensitivity = { Min = 0.05, Max = 2.0 },
	ControllerSensitivity = { Min = 0.1, Max = 3.0 },
	ControllerScopedSensitivity = { Min = 0.05, Max = 2.0 },
	ControllerDeadzone = { Min = 0.02, Max = 0.4 },
	TouchSensitivity = { Min = 0.1, Max = 3.0 },
	TouchScopedSensitivity = { Min = 0.05, Max = 2.0 },
	FieldOfView = { Min = 65, Max = 105 },
}

-- Controller look speed (right stick), before the sensitivity setting.
-- Touch screens: dragging on the right side of the screen looks around.
Config.Touch = {
	DegreesPerPixel = 0.28, -- at sensitivity 1
	FireButtonSize = 104, -- pixels (scaled down on small screens)
}

Config.Controller = {
	TurnSpeed = 260, -- degrees per second at full stick, sensitivity 1
	VerticalScale = 0.75, -- looking up/down is a bit slower than turning
	ResponseCurve = 1.7, -- >1 = finer control near the centre of the stick
}

----------------------------------------------------------------------------
-- AIM ASSIST (controller only, deliberately subtle)
----------------------------------------------------------------------------
Config.AimAssist = {
	Enabled = true, -- master switch (players can also turn it off in settings)
	ConeDegrees = 4.5, -- only helps when the crosshair is this close to a target (at normal FOV)
	Slowdown = 0.3, -- aim turns up to 30% slower right on top of a target
	PullDegreesPerSecond = 3.5, -- max gentle drift toward the body while moving / aiming
	ScopedPullMultiplier = 0.6, -- less pull while scoped
	Range = 900, -- studs
}

----------------------------------------------------------------------------
-- MOVEMENT
----------------------------------------------------------------------------
Config.Movement = {
	Gravity = 185, -- workspace gravity (default Roblox is 196.2). Higher = snappier jumps

	-- Movement uses the same model as Source games (CS / TF2 / Titanfall):
	-- ground friction + acceleration, and "air strafing" in the air, which is
	-- what makes bunny hopping work.
	RunSpeed = 22, -- normal top speed on the ground
	SprintSpeed = 28, -- top speed while holding Shift on the ground
	GroundAccel = 15, -- how quickly you reach top speed (higher = snappier)
	Friction = 7, -- ground friction (higher = stop faster)
	StopSpeed = 10, -- below this speed friction acts as if you were going this fast

	-- BUNNY HOPPING
	-- Hold Space: you jump again the instant you land, and the landing frame
	-- skips friction, so you keep all your speed. Hold A or D and turn the
	-- mouse the same way in the air to GAIN speed (air strafing).
	AutoBhop = true, -- true = holding Space re-jumps on landing
	JumpBuffer = 0.15, -- a jump pressed this long before landing still counts
	CoyoteTime = 0.12, -- you can still jump this long after leaving the ground
	AirAccel = 14, -- air strafe strength (Source uses 10-12)
	AirSpeedCap = 4.2, -- small cap per frame = the classic strafe gain (Source: 30 units)
	AirControlSpeed = 22, -- wish speed used in the air
	AirSteer = 4.5, -- holding W in the air turns your momentum toward your aim (per second)
	AirMinSpeed = 19, -- in the air you can always accelerate up to this speed...
	AirLowSpeedAccel = 7, -- ...this quickly (so standing jumps aren't stuck)
	MaxSpeed = 85, -- hard limit on horizontal speed

	JumpPower = 55,
	AirJumps = 0, -- no double jump by default (the Double Jump power-up adds one)
	AirJumpVelocity = 53,
	AirJumpMinSpeed = 22, -- a double jump re-aims you toward your keys at least this fast

	-- Slide
	SlideKey = Enum.KeyCode.C, -- LeftControl also works
	SlideHold = false, -- false = tap C to slide (press again to stop), true = hold C
	SlideMinSpeed = 14, -- need at least this speed to start a slide
	SlideBoost = 9, -- speed added when the slide starts...
	SlideBoostCap = 40, -- ...but only up to this speed (no infinite slide boosting)
	SlideFriction = 0.55, -- slide friction (much lower than running)
	SlideEndSpeed = 12, -- slide ends below this speed
	SlideSteer = 2.2, -- how much you can steer a slide
	SlideCooldown = 0.25,
	SlideJumpBoost = 4, -- extra speed for jumping out of a slide (up to SlideBoostCap)

	-- Wall run: only with the Wall Runner power-up (or Magnetic Boots), and
	-- deliberately weak: short, no speed boost, you sink fast, one per jump
	-- (touch the ground to recharge) plus a cooldown. Duration comes from
	-- Config.PowerUps.WallRunner.
	WallCheckDistance = 3.4,
	WallRunMinSpeed = 14,
	WallRunMaxSpeed = 24, -- you never go faster than this on a wall
	WallRunDrag = 0.5, -- fraction of speed lost per second on the wall
	WallRunStartLift = 3, -- small upward pop when you latch on
	WallRunGravity = 45, -- how quickly you sink while wall running
	WallRunCooldown = 2.5, -- seconds before you can wall run again
	WallJumpOut = 22, -- push away from wall
	WallJumpUp = 38,
	WallReattachDelay = 0.3,

	-- Grapple Hook power-up (press E)
	GrappleRange = 220,
	GrapplePullSpeed = 95,
	GrappleAccel = 260,
	GrappleMaxTime = 1.6,
	GrappleReleaseDistance = 7,
	GrappleCooldown = 3,

	-- Knockback received from explosions / shockwaves is multiplied by this
	KnockbackScale = 1.0,
}

----------------------------------------------------------------------------
-- SNIPER
----------------------------------------------------------------------------
Config.Weapon = {
	HeadDamage = 1000, -- headshot = instant kill
	BodyDamage = 72, -- torso / root
	LimbDamage = 55, -- arms / legs
	BoltTime = 1.05, -- seconds between shots (bolt-action delay)
	ScopeInTime = 0.22, -- seconds to fully scope in
	MaxRange = 2500,
	HipSpreadDegrees = 1.4, -- random spread when NOT scoped (0 = perfect hipfire)
	ScopedSpreadDegrees = 0,

	-- Server-side validation (anti-exploit)
	FireRateTolerance = 0.82, -- shots faster than BoltTime * this are rejected
	OriginTolerance = 7, -- shot origin must be this close to the server's head position...
	OriginSpeedAllowance = 0.3, -- ...plus (shooter speed * this) to allow for latency
	ClaimPathTolerance = 2.5, -- claimed hit must be this close to the server's bullet path
	ClaimTargetTolerance = 5, -- and this close to where the victim really is...
	ClaimSpeedAllowance = 0.25, -- ...plus (victim speed * this)
}

----------------------------------------------------------------------------
-- POWER-UP STRENGTHS
-- The power-up definitions themselves live in PowerUps.lua; the numbers
-- they use live here.
----------------------------------------------------------------------------
Config.PowerUps = {
	-- Most numbers below are "per stack": picking the same card again makes it stronger.

	-- BULLET PATH
	GhostRound = { WallsPerStack = 1 },
	Ricochet = { BouncesPerStack = 1 },
	SplitShot = { BulletsPerStack = 2, SpreadDegrees = 1.6 }, -- 1 + 2 = 3 bullets, 5 at 2 stacks
	HomingRounds = { Radius = 9, RadiusPerStack = 3, TurnDegreesPerStack = 5, StepLength = 18 },
	ExplosiveRounds = {
		Radius = 13,
		RadiusPerStack = 4, -- extra stacks
		Damage = 45,
		DamagePerStack = 15, -- extra stacks
		Knockback = 70,
		SelfKnockback = 55,
	},
	Shrapnel = { ShardsPerStack = 2, Damage = 16, Range = 60, SpreadDegrees = 40, MaxShardsPerShot = 14 },
	StaticCharge = { Damage = 20, Radius = 7, RadiusPerStack = 2 }, -- near misses zap the enemy

	-- DAMAGE
	Pinball = { BonusPerHop = 0.35 }, -- +35% damage per bounce / wall pass, per stack
	MomentumRounds = { BonusPerSpeed = 0.012, MaxBonus = 0.6, FreeSpeed = 30 }, -- per stack
	SkySniper = { AirBonus = 0.2 }, -- per stack
	GlassCannon = { DamageBonus = 0.3, HealthCost = 20 }, -- per stack
	Marked = { Duration = 4, BonusPerStack = 0.25 },
	HairTrigger = {}, -- a hit re-chambers your rifle instantly
	Vampire = { HealFraction = 0.5 }, -- per stack (of damage dealt)

	-- MOVEMENT
	DoubleJump = { ExtraJumpsPerStack = 1 },
	WallRunner = { Duration = 0.55, DurationPerStack = 0.2, CooldownScalePerStack = 0.85 },
	Adrenaline = { SpeedPerStack = 0.08 },
	Featherweight = { GravityReductionPerStack = 0.18 },
	SpringLegs = { JumpPerStack = 0.15 },
	Blink = { Distance = 28, DistancePerStack = 8, Cooldown = 6 }, -- cooldown is divided by stacks
	Grapple = { CooldownDividedByStacks = true, PullPerStack = 0.2 },
	MagneticBoots = { WallRunTime = 1.0 },
	RocketJump = { Radius = 9, LaunchUp = 88, LaunchAway = 28, PowerPerStack = 0.25 },
	PhantomDash = { InvisibleTime = 0.5, TimePerStack = 0.35 },
	ShockwaveLanding = {
		MinFallHeight = 20,
		Radius = 24,
		RadiusPerStack = 6,
		Knockback = 90,
		KnockbackPerStack = 20,
		DamagePerExtraStack = 20, -- stacks 2+ also deal damage
		Cooldown = 2,
	},

	-- UTILITY / DEFENCE
	BulletTime = {
		Duration = 2,
		DurationPerStack = 1, -- extra stacks
		Cooldown = 6,
		GravityScale = 0.15, -- fall speed multiplier while active
		MoveScale = 0.45, -- horizontal momentum multiplier while active
		SensitivityScale = 0.6,
		BoltSpeedScale = 2, -- bolt cycles this many times faster while active
	},
	Quickdraw = { SpeedPerStack = 0.4 }, -- 40% faster bolt + scope (multiplies per stack)
	ThickSkin = { HealthPerStack = 40 },
	SecondWind = { SpeedMultiplier = 1.35, BoostTime = 3 }, -- one save per stack, each round
	WallhackPulse = { Interval = 10, IntervalScalePerStack = 0.7, Duration = 1, DurationPerStack = 0.25 },
	Decoy = { Cooldown = 8, Lifetime = 4, Speed = 26, SpreadDegrees = 30 }, -- one decoy per stack
}

----------------------------------------------------------------------------
-- SOUNDS
-- These use sounds that ship with the Roblox client (rbxasset://). If one
-- doesn't play on your machine, swap it for any rbxassetid://<id> from the
-- Creator Store.
----------------------------------------------------------------------------
Config.Sounds = {
	Fire = { Id = "rbxasset://sounds/Rocket shot.wav", Volume = 0.6, Pitch = 1.6 },
	Bolt = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.6, Pitch = 0.8 },
	Hit = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.5, Pitch = 1.4 },
	Headshot = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.7, Pitch = 1.9 },
	Kill = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.9, Pitch = 0.75 },
	HitTick = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.55, Pitch = 2.3 }, -- the crisp tick layered on every hit
	Ding = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.55, Pitch = 2.7 }, -- headshots ring
	KillThump = { Id = "rbxasset://sounds/collide.wav", Volume = 0.6, Pitch = 0.55 }, -- the low punch under a kill
	Hurt = { Id = "rbxasset://sounds/swordslash.wav", Volume = 0.5, Pitch = 0.7 },
	Dash = { Id = "rbxasset://sounds/swordlunge.wav", Volume = 0.45, Pitch = 1.2 },
	Jump = { Id = "rbxasset://sounds/action_jump.mp3", Volume = 0.35, Pitch = 1.1 },
	Land = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 0.35, Pitch = 1 },
	Explosion = { Id = "rbxasset://sounds/collide.wav", Volume = 0.7, Pitch = 0.9 },
	CardFlip = { Id = "rbxasset://sounds/swordlunge.wav", Volume = 0.35, Pitch = 1.8 },
	CardLegendary = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.8, Pitch = 0.6 },
	CardHover = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.25, Pitch = 1.6 },
	CardPick = { Id = "rbxasset://sounds/unsheath.wav", Volume = 0.6, Pitch = 1.2 },
	Countdown = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.6, Pitch = 1 },
	Go = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.6, Pitch = 1.2 },
	Victory = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.8, Pitch = 0.5 },
	Ability = { Id = "rbxasset://sounds/swordlunge.wav", Volume = 0.4, Pitch = 0.8 },
}

----------------------------------------------------------------------------
-- VISUAL EFFECTS (client). Turn things off here if you want a calmer look
-- or better performance.
----------------------------------------------------------------------------
Config.Effects = {
	NeonEffects = true, -- tracers, flashes and explosions glow (Neon + bloom)
	Particles = true, -- sparks / smoke / dust (Roblox's built-in particle textures)
	Lights = true, -- muzzle, impact and explosion light flashes
	KillShatter = true, -- bodies burst into shards on a kill
	DamageNumbers = true, -- floating numbers where your shots land
	SpeedLines = true, -- streaks at the screen edges when you're fast
	SpeedLinesFrom = 44, -- speed (u/s) where speed lines start
	SparkTexture = "rbxasset://textures/particles/sparkles_main.dds",
	SmokeTexture = "rbxasset://textures/particles/smoke_main.dds",
}

----------------------------------------------------------------------------
-- LIGHTING (applied by the server at startup, see LightingSetup.lua)
----------------------------------------------------------------------------
Config.Lighting = {
	-- The base values are the ARENA (outdoors). The sun sits fairly high so the
	-- tall walls don't throw half the map into shade, and the shade itself is
	-- lifted (OutdoorAmbient / EnvironmentDiffuseScale) so you can still see
	-- someone standing in it.
	ClockTime = 14.2,
	GeographicLatitude = 30,
	Brightness = 2.6,
	Ambient = Color3.fromRGB(96, 100, 110),
	OutdoorAmbient = Color3.fromRGB(168, 172, 184),
	EnvironmentDiffuseScale = 0.85,
	EnvironmentSpecularScale = 0.2,
	ShadowSoftness = 0.2,

	Atmosphere = {
		Density = 0.22,
		Offset = 0.1,
		Color = Color3.fromRGB(205, 218, 235),
		Decay = Color3.fromRGB(130, 148, 180),
		Glare = 0.05,
		Haze = 0.6,
	},
	Bloom = { Intensity = 0.2, Size = 20, Threshold = 2 }, -- only real lights glow, not light walls
	ColorCorrection = {
		Brightness = 0,
		Contrast = 0.06,
		Saturation = 0.08,
		TintColor = Color3.fromRGB(255, 253, 248),
	},
	SunRays = { Intensity = 0.03, Spread = 0.5 },
	-- soft 3D clouds (workspace.Terrain.Clouds)
	Clouds = { Cover = 0.52, Density = 0.62, Color = Color3.fromRGB(255, 255, 255) },

	-- The LOBBY is indoors (a roofed rotunda with a skylight), so it gets its own
	-- profile: a dimmer sun through the skylight, warmer fill light, less haze.
	-- The client blends between the two when you enter or leave a match.
	-- Only the values listed here change; everything else uses the arena's.
	Lobby = {
		ClockTime = 13,
		Brightness = 1.6,
		Ambient = Color3.fromRGB(112, 104, 96),
		OutdoorAmbient = Color3.fromRGB(150, 146, 140),
		EnvironmentDiffuseScale = 0.5,
		ShadowSoftness = 0.35,
		Atmosphere = { Density = 0.1, Haze = 0.2, Glare = 0 },
		Bloom = { Intensity = 0.15, Threshold = 1.8 },
		ColorCorrection = { Contrast = 0.04, Saturation = 0.05, TintColor = Color3.fromRGB(255, 247, 236) },
		SunRays = { Intensity = 0.01 },
	},
	BlendTime = 1.2, -- seconds to blend from one profile to the other
}

----------------------------------------------------------------------------
-- UI
----------------------------------------------------------------------------
Config.UI = {
	FontFamily = "rbxasset://fonts/families/GothamSSm.json",
	CornerRadius = 10,
	SettingsKey = Enum.KeyCode.P,
}

----------------------------------------------------------------------------
-- DEBUG
----------------------------------------------------------------------------
Config.Debug = {
	LogRejectedShots = true, -- print a warning when the server rejects a shot
}

return Config
