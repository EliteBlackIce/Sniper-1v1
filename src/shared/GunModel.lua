--[[
	GunModel.lua  (ReplicatedStorage.Shared.GunModel)

	The sniper rifle ("VX-7"), described once as a list of flat-coloured
	parts and built twice:
	  * the first-person viewmodel (ViewmodelController, scale 1)
	  * the rifle other players see in your hands (CharacterService, smaller)

	Look: an angular two-tone rifle (light shell over dark metal) with
	glowing energy lines. The lines take the colour of your best power-up,
	and every power-up bolts its own attachment onto the rifle (see
	GunModel.Mods): coils, side barrels, a grenade canister, tesla coils,
	a blood vial... with its own effect (sparks, embers, a laser, a
	ghostly shimmer...). Stacking a power-up can add more of its parts.

	Gun space: the origin is where the right hand holds the pistol grip.
	+X = right, +Y = up, -Z = forward (down the barrel).

	Each part: { Name, Shape, Size, Position, Rotation(degrees), Color, Group, Extra }
	  Shape     "Block" | "Cylinder" | "Ball" | "Wedge"
	  Size      for a Cylinder: Vector3(length, diameter, diameter), and the
	            cylinder runs along Z (forward) unless Rotation is given
	            (UP = standing up, X = sideways)
	  Color     a key in Config.Palette, or a Color3. "GunGlow" parts glow
	            (Neon) in the rifle's glow colour.
	  Group     "Bolt" parts are animated by the viewmodel (Position is
	            relative to the bolt pivot)
	  Extra     optional { Neon = true, Transparency = n,
	                       Anim = "Pulse" | "Flicker" | "Spin" | "Ghost" | "Speed" }
	            (Anim is played by the viewmodel; see ViewmodelController)
]]

local Config = require(script.Parent.Config)
local PowerUps = require(script.Parent.PowerUps)

local GunModel = {}

local V = Vector3.new
local C3 = Color3.fromRGB

local X = V(0, 0, 0) -- "rotation given": a cylinder that stays along X (sideways)
local UP = V(0, 0, 90) -- a cylinder standing up (along Y)

local NEON = { Neon = true }

GunModel.Parts = {
	-- SKELETON STOCK
	{ "StockTop", "Block", V(0.16, 0.1, 0.78), V(0, 0.06, 0.78), nil, "GunShell" },
	{ "StockGlow", "Block", V(0.168, 0.025, 0.6), V(0, 0.025, 0.8), nil, "GunGlow" },
	{ "CheekPad", "Block", V(0.18, 0.07, 0.42), V(0, 0.14, 0.86), nil, "GunMetal" },
	{ "StockStrut", "Block", V(0.1, 0.42, 0.1), V(0, -0.12, 0.58), V(-28, 0, 0), "GunMetalLight" },
	{ "StockBottom", "Block", V(0.13, 0.08, 0.66), V(0, -0.33, 0.9), V(-6, 0, 0), "GunMetal" },
	{ "StockRear", "Block", V(0.2, 0.58, 0.14), V(0, -0.12, 1.2), nil, "GunShell" },
	{ "ButtPad", "Block", V(0.22, 0.62, 0.07), V(0, -0.12, 1.3), nil, "GunMetal" },
	{ "StockRearGlow", "Block", V(0.205, 0.04, 0.145), V(0, 0.05, 1.2), nil, "GunGlow" },

	-- GRIP + TRIGGER
	{ "Grip", "Block", V(0.15, 0.4, 0.2), V(0, -0.27, 0.16), V(-18, 0, 0), "GunMetal" },
	{ "GripPanel", "Block", V(0.155, 0.26, 0.12), V(0, -0.27, 0.19), V(-18, 0, 0), "GunMetalLight" },
	{ "GripCap", "Block", V(0.16, 0.04, 0.22), V(0, -0.47, 0.22), V(-18, 0, 0), "GunShell" },
	{ "TriggerGuard", "Block", V(0.05, 0.04, 0.38), V(0, -0.27, -0.06), nil, "GunShell" },
	{ "TriggerGuardFront", "Block", V(0.05, 0.16, 0.04), V(0, -0.2, -0.24), nil, "GunShell" },
	{ "Trigger", "Block", V(0.03, 0.11, 0.03), V(0, -0.17, -0.04), V(15, 0, 0), "GunGlow" },

	-- RECEIVER (angular shell over a dark core)
	{ "Receiver", "Block", V(0.26, 0.26, 1.2), V(0, 0.02, -0.3), nil, "GunShell" },
	{ "ReceiverLower", "Block", V(0.24, 0.12, 0.92), V(0, -0.15, -0.36), nil, "GunMetal" },
	{ "ReceiverCover", "Block", V(0.2, 0.06, 1.1), V(0, 0.17, -0.3), nil, "GunMetal" },
	{ "ReceiverChamferL", "Wedge", V(0.05, 0.06, 1.1), V(-0.125, 0.17, -0.3), V(0, 0, 90), "GunShell" },
	{ "ReceiverChamferR", "Wedge", V(0.05, 0.06, 1.1), V(0.125, 0.17, -0.3), V(0, 0, -90), "GunShell" },
	{ "ReceiverGlowL", "Block", V(0.012, 0.04, 0.9), V(-0.133, 0.04, -0.34), nil, "GunGlow" },
	{ "ReceiverGlowR", "Block", V(0.012, 0.04, 0.6), V(0.133, 0.04, -0.5), nil, "GunGlow" },
	{ "EjectionPort", "Block", V(0.02, 0.1, 0.3), V(0.131, 0.07, -0.05), nil, "GunMetal" },
	{ "BoltShroud", "Cylinder", V(0.18, 0.16, 0.16), V(0, 0.07, 0.36), nil, "GunMetalLight" },
	{ "Rail", "Block", V(0.12, 0.04, 1.0), V(0, 0.22, -0.35), nil, "GunMetalLight" },
	-- energy cell on the left side (glows)
	{ "CellHousing", "Block", V(0.06, 0.16, 0.42), V(-0.15, -0.04, -0.2), nil, "GunMetal" },
	{ "Cell", "Cylinder", V(0.34, 0.1, 0.1), V(-0.18, -0.04, -0.2), nil, "GunGlow", nil, { Anim = "Pulse" } },
	{ "CellCapF", "Cylinder", V(0.04, 0.12, 0.12), V(-0.18, -0.04, -0.39), nil, "GunMetalLight" },
	{ "CellCapB", "Cylinder", V(0.04, 0.12, 0.12), V(-0.18, -0.04, -0.01), nil, "GunMetalLight" },

	-- MAGAZINE (with a glowing round counter)
	{ "Magazine", "Block", V(0.17, 0.34, 0.38), V(0, -0.31, -0.56), V(-10, 0, 0), "GunMetal" },
	{ "MagazineBase", "Block", V(0.19, 0.05, 0.42), V(0, -0.48, -0.59), V(-10, 0, 0), "GunShell" },
	{ "MagWindow", "Block", V(0.176, 0.16, 0.05), V(0, -0.29, -0.48), V(-10, 0, 0), "GunGlow" },

	-- HANDGUARD (angular vented shroud)
	{ "Handguard", "Block", V(0.3, 0.28, 1.4), V(0, 0, -1.6), nil, "GunShell" },
	{ "HandguardTop", "Block", V(0.22, 0.05, 1.42), V(0, 0.16, -1.6), nil, "GunMetal" },
	{ "HandguardBottom", "Block", V(0.2, 0.05, 1.1), V(0, -0.155, -1.7), nil, "GunMetal" },
	{ "HandguardGlowL", "Block", V(0.012, 0.03, 1.3), V(-0.152, -0.07, -1.6), nil, "GunGlow" },
	{ "HandguardGlowR", "Block", V(0.012, 0.03, 1.3), V(0.152, -0.07, -1.6), nil, "GunGlow" },
	{ "HandguardCap", "Block", V(0.32, 0.3, 0.06), V(0, 0, -2.31), nil, "GunMetal" },

	-- BARREL
	{ "Barrel", "Cylinder", V(1.6, 0.12, 0.12), V(0, 0.03, -3.05), nil, "GunMetal" },
	{ "BarrelRing1", "Cylinder", V(0.07, 0.17, 0.17), V(0, 0.03, -2.5), nil, "GunMetalLight" },
	{ "BarrelRing2", "Cylinder", V(0.07, 0.17, 0.17), V(0, 0.03, -2.95), nil, "GunMetalLight" },
	{ "BarrelRing3", "Cylinder", V(0.07, 0.17, 0.17), V(0, 0.03, -3.4), nil, "GunMetalLight" },

	-- MUZZLE BRAKE (big and angular)
	{ "Brake", "Block", V(0.22, 0.2, 0.44), V(0, 0.03, -4.06), nil, "GunMetal" },
	{ "BrakeFin", "Block", V(0.06, 0.08, 0.36), V(0, 0.16, -4.06), nil, "GunShell" },
	{ "BrakeTip", "Cylinder", V(0.05, 0.16, 0.16), V(0, 0.03, -4.29), nil, "GunGlow" },

	-- SCOPE
	{ "ScopeMountFront", "Block", V(0.1, 0.12, 0.12), V(0, 0.28, -0.75), nil, "GunMetal" },
	{ "ScopeMountRear", "Block", V(0.1, 0.12, 0.12), V(0, 0.28, -0.05), nil, "GunMetal" },
	{ "ScopeRingFront", "Cylinder", V(0.1, 0.18, 0.18), V(0, 0.36, -0.75), nil, "GunMetalLight" },
	{ "ScopeRingRear", "Cylinder", V(0.1, 0.18, 0.18), V(0, 0.36, -0.05), nil, "GunMetalLight" },
	{ "ScopeTube", "Cylinder", V(1.0, 0.14, 0.14), V(0, 0.36, -0.38), nil, "GunMetal" },
	{ "ScopeBody", "Block", V(0.17, 0.17, 0.46), V(0, 0.36, -0.4), nil, "GunShell" },
	{ "ScopeBodyGlow", "Block", V(0.175, 0.03, 0.3), V(0, 0.33, -0.4), nil, "GunGlow" },
	{ "ScopeTaper", "Cylinder", V(0.12, 0.19, 0.19), V(0, 0.36, -0.86), nil, "GunMetal" },
	{ "ScopeObjective", "Cylinder", V(0.34, 0.25, 0.25), V(0, 0.36, -1.05), nil, "GunMetal" },
	{ "ScopeHood", "Block", V(0.27, 0.04, 0.42), V(0, 0.5, -1.08), nil, "GunShell" },
	{ "ScopeObjectiveRing", "Cylinder", V(0.04, 0.27, 0.27), V(0, 0.36, -1.22), nil, "GunGlow" },
	{ "ScopeLensFront", "Cylinder", V(0.02, 0.21, 0.21), V(0, 0.36, -1.235), nil, "ScopeGlass" },
	{ "ScopeEyepiece", "Cylinder", V(0.26, 0.2, 0.2), V(0, 0.36, 0.24), nil, "GunMetal" },
	{ "ScopeEyepieceRing", "Cylinder", V(0.05, 0.215, 0.215), V(0, 0.36, 0.16), nil, "GunShell" },
	{ "ScopeLensRear", "Cylinder", V(0.02, 0.16, 0.16), V(0, 0.36, 0.385), nil, "ScopeGlass" },
	{ "ScopeTurretTop", "Cylinder", V(0.1, 0.12, 0.12), V(0, 0.48, -0.4), UP, "GunMetalLight" },
	{ "ScopeTurretTopCap", "Cylinder", V(0.03, 0.135, 0.135), V(0, 0.54, -0.4), UP, "GunGlow" },
	{ "ScopeTurretSide", "Cylinder", V(0.09, 0.11, 0.11), V(0.12, 0.36, -0.4), X, "GunMetalLight" },
	{ "Rangefinder", "Block", V(0.08, 0.08, 0.2), V(-0.14, 0.36, -0.55), nil, "GunMetal" },
	{ "RangefinderLens", "Block", V(0.06, 0.06, 0.02), V(-0.14, 0.36, -0.655), nil, "GunGlow" },

	-- BOLT (animated; positions are relative to GunModel.BoltPivot)
	{ "BoltHandle", "Block", V(0.26, 0.05, 0.05), V(0.13, 0, 0), nil, "GunMetalLight", "Bolt" },
	{ "BoltKnob", "Ball", V(0.12, 0.12, 0.12), V(0.27, 0, 0), nil, "GunShell", "Bolt" },
}

-- Repeated details generated in loops (rail teeth, vents, brake ports)
for i = 0, 7 do
	table.insert(GunModel.Parts, { "RailTooth" .. i, "Block", V(0.13, 0.03, 0.05), V(0, 0.25, -0.7 + i * 0.11), nil, "GunMetal" })
end
for k = 0, 4 do
	table.insert(GunModel.Parts, { "Vent" .. k, "Block", V(0.305, 0.09, 0.07), V(0, 0.04, -1.42 - k * 0.2), nil, "GunMetal" })
end
for k = 0, 2 do
	table.insert(GunModel.Parts, { "BrakePort" .. k, "Block", V(0.23, 0.12, 0.05), V(0, 0.03, -3.95 - k * 0.1), nil, "GunMetalLight" })
end

-- Where the bolt handle rotates/slides from (gun space)
GunModel.BoltPivot = CFrame.new(0.07, 0.08, 0.1)
-- Tip of the barrel (gun space)
GunModel.Muzzle = CFrame.new(0, 0.03, -4.32)
-- Centre of the scope's rear lens (gun space); used to aim down the scope
GunModel.ScopeEye = Vector3.new(0, 0.36, 0.39)

----------------------------------------------------------------------------
-- POWER-UP MODS
----------------------------------------------------------------------------
--[[
	GunModel.Mods[powerUpId](stacks) -> parts, effects
	  parts   : extra part specs (same format as above)
	  effects : { { Part = name, Kind = "Sparks" | "Embers" | "Drips" | "Wisps" | "Glow", Color = Color3 } }
]]
local function ring(name, z, color, diameter, extra)
	return { name, "Cylinder", V(0.05, diameter or 0.2, diameter or 0.2), V(0, 0.03, z), nil, color, nil, extra }
end

local GHOST = C3(170, 130, 255)
local TEAL = C3(60, 220, 210)
local ORANGE = C3(255, 130, 50)
local CYAN = C3(110, 220, 255)
local PINK = C3(255, 90, 170)
local RED = C3(235, 50, 70)
local GOLD = C3(255, 205, 80)
local GREEN = C3(90, 230, 130)

GunModel.Mods = {
	-- phase fins: see-through purple blades along the barrel that shimmer
	GhostRound = function()
		return {
			{ "GhostFinL", "Block", V(0.02, 0.18, 0.9), V(-0.1, 0.03, -3.0), nil, GHOST, nil, { Neon = true, Transparency = 0.45, Anim = "Ghost" } },
			{ "GhostFinR", "Block", V(0.02, 0.18, 0.9), V(0.1, 0.03, -3.0), nil, GHOST, nil, { Neon = true, Transparency = 0.45, Anim = "Ghost" } },
			{ "GhostFinT", "Block", V(0.18, 0.02, 0.9), V(0, 0.13, -3.0), nil, GHOST, nil, { Neon = true, Transparency = 0.45, Anim = "Ghost" } },
		}, { { Part = "GhostFinT", Kind = "Wisps", Color = GHOST } }
	end,
	-- bouncy coils around the barrel: one more per stack
	Ricochet = function(stacks)
		local parts = {}
		for k = 1, math.min(stacks + 1, 5) do
			table.insert(parts, ring("RicochetCoil" .. k, -2.55 - k * 0.16, TEAL, 0.21, { Neon = true, Anim = "Pulse" }))
		end
		return parts
	end,
	-- two extra short barrels on the sides
	SplitShot = function()
		local parts = {}
		for _, s in ipairs({ -1, 1 }) do
			local n = s < 0 and "L" or "R"
			table.insert(parts, { "SplitBarrel" .. n, "Cylinder", V(1.0, 0.07, 0.07), V(s * 0.13, -0.06, -2.85), nil, "GunMetal" })
			table.insert(parts, { "SplitMount" .. n, "Block", V(0.1, 0.06, 0.12), V(s * 0.08, -0.05, -2.45), nil, "GunMetalLight" })
			table.insert(parts, { "SplitTip" .. n, "Cylinder", V(0.05, 0.1, 0.1), V(s * 0.13, -0.06, -3.36), nil, C3(255, 90, 90), nil, NEON })
		end
		return parts
	end,
	-- a seeker module bolted on the scope + a short tracking laser
	HomingRounds = function()
		return {
			{ "SeekerBox", "Block", V(0.1, 0.12, 0.22), V(0.16, 0.42, -0.9), nil, "GunMetal" },
			{ "SeekerEye", "Ball", V(0.08, 0.08, 0.08), V(0.16, 0.42, -1.02), nil, PINK, nil, { Neon = true, Anim = "Pulse" } },
			{ "SeekerAntenna", "Cylinder", V(0.22, 0.02, 0.02), V(0.18, 0.56, -0.86), UP, "GunMetalLight" },
			{ "SeekerLaser", "Block", V(0.015, 0.015, 3), V(0.16, 0.42, -2.55), nil, PINK, nil, { Neon = true, Transparency = 0.35 } },
		}, { { Part = "SeekerEye", Kind = "Glow", Color = PINK } }
	end,
	-- a grenade canister slung under the barrel, hazard stripes, embers at the muzzle
	ExplosiveRounds = function(stacks)
		local parts = {
			{ "Canister", "Cylinder", V(0.55, 0.15, 0.15), V(0, -0.13, -2.75), nil, "GunMetal" },
			{ "CanisterBand1", "Cylinder", V(0.06, 0.16, 0.16), V(0, -0.13, -2.6), nil, ORANGE, nil, NEON },
			{ "CanisterBand2", "Cylinder", V(0.06, 0.16, 0.16), V(0, -0.13, -2.9), nil, ORANGE, nil, NEON },
			{ "CanisterCap", "Ball", V(0.15, 0.15, 0.15), V(0, -0.13, -3.03), nil, ORANGE, nil, { Neon = true, Anim = "Pulse" } },
		}
		if stacks >= 2 then
			table.insert(parts, { "Canister2", "Cylinder", V(0.4, 0.12, 0.12), V(0.12, -0.12, -2.4), nil, ORANGE, nil, NEON })
		end
		return parts, { { Part = "BrakeTip", Kind = "Embers", Color = ORANGE } }
	end,
	-- spikes around the muzzle brake that spin
	Shrapnel = function()
		local parts = {}
		for k = 0, 5 do
			local a = k * 60
			local r = math.rad(a)
			table.insert(parts, {
				"ShrapnelSpike" .. k, "Wedge", V(0.04, 0.12, 0.12),
				V(math.cos(r) * 0.15, 0.03 + math.sin(r) * 0.15, -4.12), V(0, 0, a - 90), C3(230, 160, 70), nil, { Anim = "Spin" },
			})
		end
		return parts
	end,
	-- tesla coils on the handguard that crackle
	StaticCharge = function(stacks)
		local parts = {}
		for k = 1, math.min(stacks + 1, 3) do
			local z = -1.25 - k * 0.32
			table.insert(parts, { "TeslaCoil" .. k, "Cylinder", V(0.16, 0.05, 0.05), V(0, 0.27, z), UP, "GunMetalLight" })
			table.insert(parts, { "TeslaWind" .. k, "Cylinder", V(0.08, 0.08, 0.08), V(0, 0.24, z), UP, C3(200, 120, 60) })
			table.insert(parts, { "TeslaBall" .. k, "Ball", V(0.09, 0.09, 0.09), V(0, 0.37, z), nil, CYAN, nil, { Neon = true, Anim = "Flicker" } })
		end
		return parts, { { Part = "TeslaBall1", Kind = "Sparks", Color = CYAN } }
	end,
	-- pink bumper rings on the handguard
	Pinball = function(stacks)
		local parts = {}
		for k = 1, math.min(stacks + 1, 3) do
			table.insert(parts, { "Bumper" .. k, "Cylinder", V(0.06, 0.34, 0.34), V(0, 0, -1.95 - k * 0.1), nil, PINK, nil, { Neon = true, Anim = "Pulse" } })
		end
		return parts
	end,
	-- fins on the stock that glow brighter the faster you move
	MomentumRounds = function()
		return {
			{ "MomentumFinL", "Wedge", V(0.02, 0.16, 0.4), V(-0.09, 0.15, 0.95), nil, ORANGE, nil, { Neon = true, Anim = "Speed" } },
			{ "MomentumFinR", "Wedge", V(0.02, 0.16, 0.4), V(0.09, 0.15, 0.95), nil, ORANGE, nil, { Neon = true, Anim = "Speed" } },
		}
	end,
	-- little wings on the scope
	SkySniper = function()
		return {
			{ "WingL", "Wedge", V(0.02, 0.1, 0.3), V(-0.15, 0.42, -0.25), V(0, 0, 60), C3(150, 210, 255), nil, NEON },
			{ "WingR", "Wedge", V(0.02, 0.1, 0.3), V(0.15, 0.42, -0.25), V(0, 0, -60), C3(150, 210, 255), nil, NEON },
		}, { { Part = "WingL", Kind = "Wisps", Color = C3(200, 230, 255) } }
	end,
	-- a white-hot barrel in a glass sleeve
	GlassCannon = function()
		return {
			{ "GlassSleeve", "Cylinder", V(1.3, 0.22, 0.22), V(0, 0.03, -3.0), nil, C3(220, 240, 255), nil, { Transparency = 0.6 } },
			{ "HotCore", "Cylinder", V(1.25, 0.13, 0.13), V(0, 0.03, -3.0), nil, C3(255, 235, 200), nil, { Neon = true, Anim = "Pulse" } },
		}
	end,
	-- red laser sight under the handguard
	Marked = function()
		return {
			{ "LaserBox", "Block", V(0.1, 0.08, 0.2), V(0, -0.22, -2.0), nil, "GunMetal" },
			{ "LaserLens", "Block", V(0.05, 0.05, 0.02), V(0, -0.22, -2.11), nil, RED, nil, NEON },
			{ "LaserBeam", "Block", V(0.012, 0.012, 3), V(0, -0.22, -3.62), nil, RED, nil, { Neon = true, Transparency = 0.3 } },
		}
	end,
	-- gold trigger, gold bolt knob
	HairTrigger = function()
		return {
			{ "GoldTrigger", "Block", V(0.035, 0.12, 0.035), V(0, -0.17, -0.04), V(15, 0, 0), GOLD, nil, NEON },
			{ "GoldGuard", "Block", V(0.055, 0.045, 0.385), V(0, -0.27, -0.06), nil, GOLD },
		}
	end,
	-- a blood vial on the stock that drips
	Vampire = function()
		return {
			{ "VialGlass", "Cylinder", V(0.36, 0.11, 0.11), V(0.11, -0.05, 0.85), nil, C3(240, 220, 225), nil, { Transparency = 0.5 } },
			{ "VialBlood", "Cylinder", V(0.3, 0.08, 0.08), V(0.11, -0.05, 0.85), nil, RED, nil, { Neon = true, Anim = "Pulse" } },
			{ "VialCapF", "Cylinder", V(0.04, 0.12, 0.12), V(0.11, -0.05, 0.66), nil, "GunMetalLight" },
			{ "VialCapB", "Cylinder", V(0.04, 0.12, 0.12), V(0.11, -0.05, 1.04), nil, "GunMetalLight" },
		}, { { Part = "VialBlood", Kind = "Drips", Color = RED } }
	end,
	-- a clock dial on the receiver
	BulletTime = function()
		return {
			{ "ClockFace", "Cylinder", V(0.02, 0.2, 0.2), V(0.135, 0.02, -0.55), X, GOLD, nil, NEON },
			{ "ClockHand", "Block", V(0.015, 0.08, 0.025), V(0.15, 0.02, -0.55), nil, "GunMetal", nil, { Anim = "Tick" } },
		}
	end,
	-- yellow grip tape
	Quickdraw = function()
		return {
			{ "GripTape", "Block", V(0.16, 0.2, 0.21), V(0, -0.27, 0.16), V(-18, 0, 0), C3(250, 200, 70) },
		}
	end,
	-- a little radar dish on the scope
	WallhackPulse = function()
		return {
			{ "RadarStem", "Cylinder", V(0.1, 0.03, 0.03), V(-0.12, 0.52, -0.2), UP, "GunMetalLight" },
			{ "RadarDish", "Cylinder", V(0.02, 0.16, 0.16), V(-0.12, 0.58, -0.2), V(0, 0, 70), CYAN, nil, { Neon = true, Anim = "Turn" } },
		}
	end,
	-- armour plates on the handguard
	ThickSkin = function(stacks)
		local parts = {}
		for k = 1, math.min(stacks, 3) do
			table.insert(parts, { "ArmorL" .. k, "Block", V(0.03, 0.24, 0.3), V(-0.17, 0, -1.4 - k * 0.32), nil, C3(120, 130, 150) })
			table.insert(parts, { "ArmorR" .. k, "Block", V(0.03, 0.24, 0.3), V(0.17, 0, -1.4 - k * 0.32), nil, C3(120, 130, 150) })
		end
		return parts
	end,
	-- a green heart cell on the stock
	SecondWind = function()
		return {
			{ "HeartCell", "Ball", V(0.14, 0.14, 0.14), V(-0.12, -0.08, 0.95), nil, GREEN, nil, { Neon = true, Anim = "Pulse" } },
			{ "HeartClamp", "Block", V(0.04, 0.18, 0.06), V(-0.1, -0.08, 0.95), nil, "GunMetalLight" },
		}
	end,
	-- grappling hook launcher under the barrel
	GrappleHook = function()
		return {
			{ "HookTube", "Cylinder", V(0.5, 0.1, 0.1), V(0, -0.13, -2.65), nil, "GunMetal" },
			{ "HookClawL", "Wedge", V(0.03, 0.1, 0.12), V(-0.05, -0.13, -2.95), V(0, 0, 90), C3(230, 120, 60) },
			{ "HookClawR", "Wedge", V(0.03, 0.1, 0.12), V(0.05, -0.13, -2.95), V(0, 0, -90), C3(230, 120, 60) },
			{ "HookSpool", "Cylinder", V(0.06, 0.08, 0.08), V(0.07, -0.13, -2.45), X, C3(230, 120, 60) },
		}
	end,
	-- a mini rocket on the side
	RocketJump = function()
		return {
			{ "RocketBody", "Cylinder", V(0.4, 0.08, 0.08), V(0.17, -0.02, -1.0), nil, C3(240, 240, 245) },
			{ "RocketNose", "Ball", V(0.08, 0.08, 0.08), V(0.17, -0.02, -1.2), nil, C3(255, 120, 80), nil, NEON },
		}, { { Part = "RocketBody", Kind = "Embers", Color = C3(255, 150, 80) } }
	end,
	-- a hologram emitter (Decoy)
	Decoy = function()
		return {
			{ "HoloBase", "Cylinder", V(0.03, 0.12, 0.12), V(-0.15, 0.25, -0.75), UP, "GunMetal" },
			{ "HoloFigure", "Block", V(0.05, 0.12, 0.03), V(-0.15, 0.34, -0.75), nil, C3(100, 220, 240), nil, { Neon = true, Transparency = 0.4, Anim = "Ghost" } },
		}
	end,
	-- a purple orb (Blink)
	Blink = function()
		return {
			{ "BlinkOrb", "Ball", V(0.1, 0.1, 0.1), V(0.15, 0.1, -0.85), nil, C3(170, 120, 255), nil, { Neon = true, Anim = "Pulse" } },
		}, { { Part = "BlinkOrb", Kind = "Wisps", Color = C3(170, 120, 255) } }
	end,
}

-- Movement power-ups without their own attachment get a small charm.
local CHARMS = {
	DoubleJump = C3(160, 120, 255),
	Adrenaline = C3(255, 120, 90),
	Featherweight = C3(170, 220, 200),
	SpringLegs = C3(140, 230, 120),
	PhantomDash = C3(110, 120, 150),
	MagneticBoots = C3(200, 70, 90),
	ShockwaveLanding = C3(240, 170, 40),
}
local charmIds = {}
for id in pairs(CHARMS) do
	table.insert(charmIds, id)
end
table.sort(charmIds)
for i, id in ipairs(charmIds) do
	-- each charm hangs in its own spot along the right side
	local z = -0.62 - (i - 1) * 0.1
	local color = CHARMS[id]
	GunModel.Mods[id] = function()
		return {
			{ id .. "CharmCord", "Block", V(0.015, 0.12, 0.015), V(0.11, -0.24, z), nil, "GunMetal" },
			{ id .. "Charm", "Ball", V(0.07, 0.07, 0.07), V(0.11, -0.31, z), nil, color, nil, NEON },
		}
	end
end

-- The glow colour for a set of power-ups: the colour of the rarest one
-- (ties: the one with more stacks). No power-ups = Palette.GunGlow.
function GunModel.GlowColor(owned)
	local best, bestScore = nil, -1
	for id, stacks in pairs(owned or {}) do
		local def = PowerUps.Get(id)
		if def and stacks > 0 then
			local rarity = Config.Rarity[def.Rarity]
			local score = (rarity and rarity.Order or 0) * 10 + stacks
			if score > bestScore then
				best, bestScore = def, score
			end
		end
	end
	return best and best.IconColor or Config.Palette.GunGlow
end

-- Total stacks owned (used for "how charged" the rifle looks).
function GunModel.PowerLevel(owned)
	local total = 0
	for _, stacks in pairs(owned or {}) do
		total += stacks
	end
	return total
end

----------------------------------------------------------------------------
-- BUILDING
----------------------------------------------------------------------------

-- The local CFrame of a part spec (cylinders are turned to run along Z).
local function specCFrame(spec, scale)
	local rot = spec[5] or Vector3.zero
	local cf = CFrame.new(spec[4] * scale)
		* CFrame.Angles(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z))
	if spec[2] == "Cylinder" and not spec[5] then
		cf *= CFrame.Angles(0, math.rad(90), 0) -- Roblox cylinders run along X
	end
	return cf
end

local EFFECT_TEXTURES = {
	Sparks = "rbxasset://textures/particles/sparkles_main.dds",
	Embers = "rbxasset://textures/particles/sparkles_main.dds",
	Drips = "rbxasset://textures/particles/sparkles_main.dds",
	Wisps = "rbxasset://textures/particles/smoke_main.dds",
}

local function addEffect(part, effect, scale, lightsOn)
	if effect.Kind == "Glow" then
		if lightsOn then
			local light = Instance.new("PointLight")
			light.Color = effect.Color
			light.Range = 4 * scale
			light.Brightness = 1.5
			light.Shadows = false
			light.Parent = part
		end
		return
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "ModEffect"
	emitter.Texture = EFFECT_TEXTURES[effect.Kind] or EFFECT_TEXTURES.Sparks
	emitter.Color = ColorSequence.new(effect.Color)
	emitter.LightEmission = 1
	emitter.LockedToPart = effect.Kind ~= "Drips" and effect.Kind ~= "Embers"
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.12 * scale),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.SpreadAngle = Vector2.new(180, 180)
	if effect.Kind == "Sparks" then
		emitter.Rate = 14
		emitter.Lifetime = NumberRange.new(0.08, 0.2)
		emitter.Speed = NumberRange.new(1.5 * scale, 3 * scale)
	elseif effect.Kind == "Embers" then
		emitter.Rate = 6
		emitter.Lifetime = NumberRange.new(0.4, 0.8)
		emitter.Speed = NumberRange.new(0.3 * scale, 0.8 * scale)
		emitter.Acceleration = Vector3.new(0, 2 * scale, 0)
	elseif effect.Kind == "Drips" then
		emitter.Rate = 2
		emitter.Lifetime = NumberRange.new(0.4, 0.6)
		emitter.Speed = NumberRange.new(0, 0.1)
		emitter.SpreadAngle = Vector2.new(5, 5)
		emitter.Acceleration = Vector3.new(0, -6 * scale, 0)
	else -- Wisps
		emitter.Rate = 5
		emitter.Lifetime = NumberRange.new(0.4, 0.8)
		emitter.Speed = NumberRange.new(0.2 * scale, 0.5 * scale)
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.05 * scale),
			NumberSequenceKeypoint.new(1, 0.25 * scale),
		})
	end
	emitter.Parent = part
end

--[[
	Builds the gun into `parent`.
	options:
		Scale      size multiplier (default 1)
		Anchored   anchor the parts (viewmodel) or leave them free to weld
		CastShadow
		PowerUps   { [id] = stacks }: adds each power-up's attachment + effects
		           and tints the glow lines
		Effects    false to skip particles / lights
	Returns {
		Parts = {[name] = part}, Offsets = {[name] = CFrame}, Bolt = {[name] = true},
		Anims = {[name] = "Pulse" | ...}, Glow = { glowing parts }, GlowColor = Color3,
		BaseTransparency = {[name] = number}
	}
	Offsets of "Bolt" parts are relative to BoltPivot; all others to the grip.
]]
function GunModel.Build(parent, options)
	options = options or {}
	local scale = options.Scale or 1
	local owned = options.PowerUps or {}
	local glowColor = GunModel.GlowColor(owned)
	local result = {
		Parts = {},
		Offsets = {},
		Bolt = {},
		Anims = {},
		Glow = {},
		GlowColor = glowColor,
		BaseTransparency = {},
	}

	local specs = table.clone(GunModel.Parts)
	local effects = {}
	local ids = {}
	for id in pairs(owned) do
		table.insert(ids, id)
	end
	table.sort(ids) -- same build order every time
	for _, id in ipairs(ids) do
		local mod = GunModel.Mods[id]
		if mod and owned[id] > 0 then
			local modParts, modEffects = mod(owned[id])
			for _, spec in ipairs(modParts or {}) do
				table.insert(specs, spec)
			end
			for _, effect in ipairs(modEffects or {}) do
				table.insert(effects, effect)
			end
		end
	end

	for _, spec in ipairs(specs) do
		local name, shape, size = spec[1], spec[2], spec[3]
		local extra = spec[8] or {}
		local part
		if shape == "Wedge" then
			part = Instance.new("WedgePart")
		else
			part = Instance.new("Part")
			if shape == "Cylinder" then
				part.Shape = Enum.PartType.Cylinder
			elseif shape == "Ball" then
				part.Shape = Enum.PartType.Ball
			end
		end
		local colorKey = spec[6]
		local isGlow = colorKey == "GunGlow"
		part.Name = name
		part.Size = size * scale
		if typeof(colorKey) == "Color3" then
			part.Color = colorKey
		elseif isGlow then
			part.Color = glowColor
		else
			part.Color = Config.Palette[colorKey] or Color3.new(1, 0, 1)
		end
		part.Material = (isGlow or extra.Neon) and Enum.Material.Neon or Enum.Material.SmoothPlastic
		part.Transparency = extra.Transparency or 0
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Anchored = options.Anchored == true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.CastShadow = options.CastShadow == true and not isGlow and not extra.Neon
		part.Parent = parent

		result.Parts[name] = part
		result.Offsets[name] = specCFrame(spec, scale)
		result.BaseTransparency[name] = part.Transparency
		if spec[7] == "Bolt" then
			result.Bolt[name] = true
		end
		if extra.Anim then
			result.Anims[name] = extra.Anim
		end
		if isGlow then
			table.insert(result.Glow, part)
		end
	end

	if options.Effects ~= false then
		local lightsOn = Config.Effects == nil or Config.Effects.Lights ~= false
		for _, effect in ipairs(effects) do
			local part = result.Parts[effect.Part]
			if part then
				addEffect(part, effect, scale, lightsOn)
			end
		end
		-- a charged rifle (lots of power-ups) shimmers along the handguard
		if GunModel.PowerLevel(owned) >= 5 and result.Parts.HandguardGlowL then
			addEffect(result.Parts.HandguardGlowL, { Kind = "Sparks", Color = glowColor }, scale * 0.6, lightsOn)
			addEffect(result.Parts.HandguardGlowR, { Kind = "Sparks", Color = glowColor }, scale * 0.6, lightsOn)
		end
	end
	return result
end

-- CFrame of every part for a given grip CFrame (bolt closed). Handy for
-- placing the gun once before welding it.
function GunModel.Place(built, grip, scale)
	scale = scale or 1
	local boltPivot = grip * CFrame.new(GunModel.BoltPivot.Position * scale)
	for name, part in pairs(built.Parts) do
		local base = built.Bolt[name] and boltPivot or grip
		part.CFrame = base * built.Offsets[name]
	end
end

return GunModel
