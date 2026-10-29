--[[
	PowerFx.lua  (Client.PowerFx)

	A look for every power-up, drawn from the power-up's own IconColor.
	Works for everyone in view: the server writes each character's power-ups
	into its "PowerUps" attribute ("Id:stacks,Id:stacks"), so your game can
	draw your opponent's (and bots') effects too.

	SHOTS (Effects.DrawShot calls TracerColor + DecorateShot)
		Railgun      thick beam with rings travelling down it
		Frost        icy tracer, frost sparkles, ice shards where it lands
		Acid         green tracer that drips
		Serrated     red tracer with saw-tooth flecks
		Disruptor    glitchy blue squares along the path
		Static       crackling arcs along the shot
		Homing       a spiral of sparks around the path
		Ghost Round  after-images along the path
		Explosive    a smoke trail
		Impact       a heavy shock ring where it lands
		Shrapnel     extra spark spray on the wall
		Glass Cannon a burst of glass where it lands
		Marked / Executioner / Vampire   a target ring, a red X, blood flying back to the shooter
		Long Shot    a gold flare on far hits
		Double Tap   an echo tracer;  Deadeye  a gold charged beam
		Pinball      gold flashes on every bounce;  Split Shot  a spark per pellet
		Momentum / Sky Sniper / Last Stand / Quickdraw   muzzle rings, wings, a crimson glow, a white snap

	CHARACTERS (every frame, for every character in view)
		Overshield / Bloodlust   a shimmering bubble while the shield holds
		Regeneration             green sparkles while healing
		Adrenaline / Fight or Flight / Air Dash / Slingshot   a speed trail
		Kinetic Armor            plates orbit you while you move fast
		Last Stand               embers + a red glow at low health
		Glass Cannon             faint glass glints
		Featherweight            feathers while you fall
		Spring Legs / Double Jump / Thick Skin   coil rings, air-jump rings, heavy landings
		Keen Edge / Hunter's Knife   the knife hand glows
		Quickdraw                a flash when you swap weapons
		Phantom Step             a puff when they vanish / reappear
		Wall Runner / Magnetic Boots / Power Slide / Slingshot / Bullet Time
		    (your own movement): wall sparks, ceiling arcs, a fiery slide, a
		    slide-jump burst, slow-time ripples
		Rocket Jump  a blast under your feet;  Hair Trigger / Double Tap  a re-chamber spark
	(Blink, Grapple, Recall, Air Dash, Decoy, Smoke, Barrier, Sonar, Second
	Wind, Shockwave Landing, Wallhack Pulse, Marked and the round effects
	already have their own in EffectsController.)

	POWERING UP
		A character that gains a power-up (a card pick, a Lab pick) gets a
		beam, a rising helix of sparks and the power-up's name over its head.

	Everything respects Config.Effects (Particles, Lights) and hides on
	invisible characters (Phantom Step).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local PowerUps = require(Shared.PowerUps)
local ClientState = require(script.Parent.ClientState)
local Sfx = require(script.Parent.Sfx)

local Palette = Config.Palette
local FX = Config.Effects or {}
local PU = Config.PowerUps
local player = Players.LocalPlayer

local PowerFx = {}
local Controllers
local L -- Effects.Lib

local WHITE = Color3.new(1, 1, 1)
local GOLD = Color3.fromRGB(255, 205, 70)
local BLOOD = Color3.fromRGB(220, 30, 50)

local defs = {}
for _, def in ipairs(PowerUps.Definitions) do
	defs[def.Id] = def
end

local function colorOf(id)
	local def = defs[id]
	return def and def.IconColor or WHITE
end

local function bright(id, amount)
	return colorOf(id):Lerp(WHITE, amount or 0.25)
end

----------------------------------------------------------------------------
-- Who owns what
----------------------------------------------------------------------------
local ownedCache = setmetatable({}, { __mode = "k" }) -- [model] = { Text, Owned }

-- The power-ups on a character (from its "PowerUps" attribute), or nil.
function PowerFx.OwnedOf(model)
	if typeof(model) ~= "Instance" then
		return nil
	end
	local text = model:GetAttribute("PowerUps")
	if typeof(text) ~= "string" then
		return nil
	end
	local cached = ownedCache[model]
	if cached and cached.Text == text then
		return cached.Owned
	end
	local owned = {}
	for id, n in text:gmatch("([%w_]+):(%d+)") do
		owned[id] = tonumber(n)
	end
	ownedCache[model] = { Text = text, Owned = owned }
	return owned
end

local function has(owned, id)
	return owned ~= nil and (owned[id] or 0) > 0
end

----------------------------------------------------------------------------
-- Small helpers on top of Effects.Lib
----------------------------------------------------------------------------
local function particlesOn()
	return FX.Particles ~= false
end

-- A part that moves from a to b while fading (drips, blood, sparks).
local function flyer(a, b, color, size, time, shape)
	local part = L.FxPart(Vector3.one * size, CFrame.new(a), color, shape or Enum.PartType.Ball, true)
	TweenService:Create(part, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		CFrame = CFrame.new(b),
	}):Play()
	L.FadeOut(part, time * 1.1, { Size = Vector3.one * size * 0.4 })
	return part
end

-- A ring standing across a direction (a cylinder's axis is its X).
local function crossRing(position, direction, color, radius, life, grow)
	if direction.Magnitude < 0.01 then
		return
	end
	local cf = CFrame.lookAt(position, position + direction) * CFrame.Angles(0, math.rad(90), 0)
	local disc = L.FxPart(Vector3.new(0.08, radius * 2, radius * 2), cf, color, Enum.PartType.Cylinder, true)
	disc.Transparency = 0.35
	L.FadeOut(disc, life, { Size = Vector3.new(0.04, radius * 2 * (grow or 1.8), radius * 2 * (grow or 1.8)) }, Enum.EasingStyle.Quint)
end

-- Calls fn(point, direction, index) every `step` studs along the shot.
local function alongPath(segments, startPos, step, maxPoints, fn)
	local count = 0
	local carry = step * 0.5
	for i, seg in ipairs(segments) do
		local a = (i == 1 and startPos) or seg.From
		local b = seg.To
		local d = b - a
		local length = d.Magnitude
		if length > 0.01 then
			local dir = d / length
			local t = carry
			while t < length do
				count += 1
				if count > maxPoints then
					return
				end
				fn(a + dir * t, dir, count)
				t += step
			end
			carry = t - length
		end
	end
end

local function pathLength(segments, startPos)
	local total = 0
	for i, seg in ipairs(segments) do
		total += (seg.To - ((i == 1 and startPos) or seg.From)).Magnitude
	end
	return total
end

local function rootOf(model)
	return model and model:FindFirstChild("HumanoidRootPart")
end

----------------------------------------------------------------------------
-- Shots
----------------------------------------------------------------------------
-- tracer colour priority (the first power-up owned wins)
local TRACER_ORDER = {
	"Railgun",
	"FrostRounds",
	"AcidRounds",
	"SerratedRounds",
	"DisruptorRounds",
	"StaticCharge",
	"HomingRounds",
	"GhostRound",
	"ImpactRounds",
}

function PowerFx.TracerColor(owned, options)
	if options and options.Charged then
		return GOLD
	end
	if options and options.Explosive then
		return nil -- explosive tracers keep their own orange
	end
	for _, id in ipairs(TRACER_ORDER) do
		if has(owned, id) then
			return bright(id, 0.2)
		end
	end
	return nil
end

function PowerFx.DecorateShot(segments, endPosition, endNormal, startPos, options)
	local owned = options.Owned
	if not L or not owned or not segments or #segments == 0 then
		return
	end
	startPos = startPos or segments[1].From
	local firstDir = segments[1].To - startPos
	firstDir = firstDir.Magnitude > 0.01 and firstDir.Unit or Vector3.new(0, 0, -1)
	local hitPlayer = options.HitPlayer == true
	local shooter = options.Shooter
	local shooterRoot = rootOf(shooter)

	-- RAILGUN: a thick beam with rings rushing down it
	if has(owned, "Railgun") then
		local color = colorOf("Railgun")
		for i, seg in ipairs(segments) do
			L.Tracer((i == 1 and startPos) or seg.From, seg.To, color, 0.45, 0.85)
		end
		alongPath(segments, startPos, 9, 30, function(p, dir, i)
			task.delay(i * 0.008, crossRing, p, dir, color, 0.7, 0.45, 2.2)
		end)
		L.LightFlash(startPos, color, 5, 18, 0.3)
		if endPosition then
			L.Puff(endPosition, color, 2.4, 0.4, true)
		end
	end

	-- FROST: frost sparkles down the path, ice shards on impact
	if has(owned, "FrostRounds") then
		local color = bright("FrostRounds", 0.4)
		alongPath(segments, startPos, 8, 20, function(p)
			L.Emit(p, "Sparks", color, 2)
		end)
		if endPosition then
			for _ = 1, 6 do
				local shard = L.FxPart(
					Vector3.new(0.18, 0.18, 0.9 + math.random() * 0.8),
					CFrame.new(endPosition) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6),
					color,
					nil,
					true
				)
				shard.Transparency = 0.2
				L.FadeOut(shard, 0.9, { Size = Vector3.new(0.05, 0.05, 0.3) })
			end
			L.Ring(endPosition, color, 3.5, 0.5, true)
		end
	end

	-- ACID: drips fall from the tracer
	if has(owned, "AcidRounds") then
		local color = colorOf("AcidRounds")
		alongPath(segments, startPos, 11, 14, function(p)
			flyer(p, p - Vector3.new(0, 3 + math.random() * 3, 0), color, 0.3, 0.55)
		end)
	end

	-- SERRATED: saw-tooth flecks flick off the path
	if has(owned, "SerratedRounds") then
		local color = colorOf("SerratedRounds")
		alongPath(segments, startPos, 7, 22, function(p, dir)
			local side = dir:Cross(Vector3.new(0, 1, 0))
			side = side.Magnitude > 0.01 and side.Unit or Vector3.new(1, 0, 0)
			local flick = (math.random() < 0.5 and side or -side) * (0.8 + math.random() * 0.8)
			local tooth = L.FxPart(Vector3.new(0.1, 0.1, 0.6), CFrame.lookAt(p, p + flick), color, nil, true)
			L.FadeOut(tooth, 0.35, { CFrame = CFrame.lookAt(p + flick, p + flick * 2) })
		end)
	end

	-- DISRUPTOR: glitching squares around the path
	if has(owned, "DisruptorRounds") then
		local color = colorOf("DisruptorRounds")
		alongPath(segments, startPos, 9, 18, function(p)
			local offset = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 1.4
			local bit = L.FxPart(Vector3.one * (0.2 + math.random() * 0.25), CFrame.new(p + offset), color, nil, true)
			task.delay(0.06 + math.random() * 0.1, function()
				if bit.Parent then
					bit.CFrame = CFrame.new(p - offset)
				end
			end)
			L.FadeOut(bit, 0.3)
		end)
	end

	-- STATIC CHARGE: little arcs crackle along the shot
	if has(owned, "StaticCharge") then
		local color = bright("StaticCharge", 0.3)
		alongPath(segments, startPos, 14, 10, function(p, dir)
			local last = p
			for _ = 1, 3 do
				local nextPoint = last + dir * 1.2 + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 1.3
				L.Tracer(last, nextPoint, color, 0.06, 0.18)
				last = nextPoint
			end
		end)
	end

	-- HOMING: a spiral of sparks wraps the path
	if has(owned, "HomingRounds") then
		local color = bright("HomingRounds", 0.2)
		alongPath(segments, startPos, 2.2, 40, function(p, dir, i)
			local up = math.abs(dir.Y) > 0.9 and Vector3.new(1, 0, 0) or Vector3.new(0, 1, 0)
			local right = dir:Cross(up).Unit
			local realUp = right:Cross(dir)
			local angle = i * 0.9
			local offset = (right * math.cos(angle) + realUp * math.sin(angle)) * 0.55
			local dot = L.FxPart(Vector3.one * 0.16, CFrame.new(p + offset), color, Enum.PartType.Ball, true)
			L.FadeOut(dot, 0.45)
		end)
	end

	-- GHOST ROUND: after-images of the bullet
	if has(owned, "GhostRound") then
		local color = colorOf("GhostRound")
		alongPath(segments, startPos, 16, 10, function(p, dir)
			local ghost = L.FxPart(Vector3.new(0.5, 0.5, 2.6), CFrame.lookAt(p, p + dir), color, nil, true)
			ghost.Transparency = 0.55
			L.FadeOut(ghost, 0.5, { Size = Vector3.new(0.1, 0.1, 3.4) })
		end)
	end

	-- EXPLOSIVE: a smoke trail
	if has(owned, "ExplosiveRounds") then
		alongPath(segments, startPos, 18, 8, function(p)
			L.Emit(p, "Smoke", Color3.fromRGB(120, 115, 110), 1)
		end)
	end

	-- PINBALL: gold flashes on every bounce
	if has(owned, "Pinball") then
		for i = 2, #segments do
			if segments[i].Kind == "Bounce" then
				L.Puff(segments[i].From, GOLD, 1.4, 0.35, true)
				L.Emit(segments[i].From, "Sparks", GOLD, 8)
			end
		end
	end

	-- DOUBLE TAP: an echo tracer just beside the real one
	if has(owned, "DoubleTap") then
		local side = firstDir:Cross(Vector3.new(0, 1, 0))
		side = side.Magnitude > 0.01 and side.Unit * 0.35 or Vector3.new(0.35, 0, 0)
		local color = colorOf("DoubleTap")
		task.delay(0.05, function()
			for i, seg in ipairs(segments) do
				L.Tracer(((i == 1 and startPos) or seg.From) + side, seg.To + side, color, 0.05, 0.3)
			end
		end)
	end

	-- DEADEYE (charged): a gold beam and a ring at the muzzle
	if options.Charged then
		for i, seg in ipairs(segments) do
			L.Tracer((i == 1 and startPos) or seg.From, seg.To, GOLD, 0.28, 0.7)
		end
		crossRing(startPos + firstDir * 1.5, firstDir, GOLD, 0.8, 0.4, 2.5)
		L.LightFlash(startPos, GOLD, 6, 16, 0.3)
	end

	-- MOMENTUM ROUNDS: speed rings off the muzzle when you shoot on the move
	if has(owned, "MomentumRounds") and shooterRoot then
		local v = shooterRoot.AssemblyLinearVelocity
		if Vector3.new(v.X, 0, v.Z).Magnitude > 30 then
			local color = colorOf("MomentumRounds")
			for k = 1, 3 do
				task.delay(k * 0.03, crossRing, startPos + firstDir * (k * 1.6), firstDir, color, 0.45, 0.3, 1.6)
			end
		end
	end

	-- SKY SNIPER: wings of light when you shoot in the air
	if has(owned, "SkySniper") and shooterRoot and math.abs(shooterRoot.AssemblyLinearVelocity.Y) > 6 then
		local color = colorOf("SkySniper")
		local right = firstDir:Cross(Vector3.new(0, 1, 0))
		if right.Magnitude > 0.01 then
			right = right.Unit
			for _, s in ipairs({ -1, 1 }) do
				local base = startPos - firstDir * 0.5
				local tip = base + right * s * 2.4 + Vector3.new(0, 0.9, 0) - firstDir * 1.2
				L.Tracer(base, tip, color, 0.12, 0.4)
				L.Tracer(base, tip - Vector3.new(0, 0.7, 0), color, 0.08, 0.35)
			end
		end
	end

	-- LAST STAND: a crimson glow on shots fired at low health
	if has(owned, "LastStand") and shooter then
		local humanoid = shooter:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health <= humanoid.MaxHealth * PU.LastStand.HealthFraction then
			for i, seg in ipairs(segments) do
				L.Tracer((i == 1 and startPos) or seg.From, seg.To, colorOf("LastStand"), 0.22, 0.5)
			end
		end
	end

	-- SPLIT SHOT: each pellet leaves the muzzle with its own spark
	if has(owned, "SplitShot") then
		L.Puff(startPos + firstDir * 1.2, colorOf("SplitShot"), 0.6, 0.15, true)
	end

	-- QUICKDRAW: a white snap at the muzzle
	if has(owned, "Quickdraw") then
		crossRing(startPos + firstDir * 0.8, firstDir, WHITE, 0.3, 0.18, 2.4)
	end

	if not endPosition then
		return
	end

	-- IMPACT ROUNDS: a heavy shock ring where it lands
	if has(owned, "ImpactRounds") then
		local color = colorOf("ImpactRounds")
		local normal = (typeof(endNormal) == "Vector3" and endNormal.Magnitude > 0.5) and endNormal or -firstDir
		crossRing(endPosition + normal * 0.1, normal, color, 1, 0.45, 3.2)
		L.Emit(endPosition, "Dust", Palette.Light, 8)
		L.LightFlash(endPosition, color, 4, 14, 0.25)
	end

	-- SHRAPNEL: extra spark spray on walls
	if has(owned, "Shrapnel") and not hitPlayer then
		L.Emit(endPosition, "Sparks", colorOf("Shrapnel"), 14, endNormal)
	end

	-- GLASS CANNON: a burst of glass where it lands
	if has(owned, "GlassCannon") then
		for _ = 1, 7 do
			local dir = Vector3.new(math.random() - 0.5, math.random() * 0.8, math.random() - 0.5).Unit
			local shard = L.FxPart(
				Vector3.new(0.05, 0.4 + math.random() * 0.4, 0.3),
				CFrame.new(endPosition) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6),
				Color3.fromRGB(220, 240, 255),
				nil,
				false
			)
			shard.Material = Enum.Material.Glass
			shard.Transparency = 0.3
			L.FadeOut(shard, 0.6, { CFrame = shard.CFrame + dir * (2 + math.random() * 3) })
		end
	end

	-- LONG SHOT: a gold flare on far hits
	if has(owned, "LongShot") and pathLength(segments, startPos) > 120 then
		L.Puff(endPosition, GOLD, 2, 0.4, true)
		L.Emit(endPosition, "Sparks", GOLD, 12)
	end

	if hitPlayer then
		-- MARKED: a target ring on the hit
		if has(owned, "Marked") then
			L.Ring(endPosition, colorOf("Marked"), 3, 0.45, true)
		end
		-- EXECUTIONER: a red X
		if has(owned, "Executioner") then
			local camera = workspace.CurrentCamera
			local facing = CFrame.lookAt(endPosition, camera.CFrame.Position)
			for _, angle in ipairs({ 45, -45 }) do
				local bar = L.FxPart(Vector3.new(0.25, 2.6, 0.05), facing * CFrame.Angles(0, 0, math.rad(angle)), colorOf("Executioner"), nil, true)
				L.FadeOut(bar, 0.5, { Size = Vector3.new(0.05, 3.4, 0.05) })
			end
		end
		-- VAMPIRE: blood flies back to the shooter
		if has(owned, "Vampire") and shooterRoot then
			local target = shooterRoot.Position
			for k = 1, 5 do
				task.delay(k * 0.05, function()
					local from = endPosition + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
					flyer(from, target, BLOOD, 0.35, 0.35 + math.random() * 0.15)
				end)
			end
		end
	end
end

-- HAIR TRIGGER / DOUBLE TAP: the rifle re-chambers with a spark.
function PowerFx.Rechamber(quick)
	if not L then
		return
	end
	local muzzle = Controllers.Viewmodel and Controllers.Viewmodel.GetMuzzlePosition and Controllers.Viewmodel.GetMuzzlePosition()
	if typeof(muzzle) ~= "Vector3" then
		return
	end
	local color = quick and colorOf("DoubleTap") or colorOf("HairTrigger")
	L.Emit(muzzle, "Sparks", color, 8)
	L.LightFlash(muzzle, color, 3, 8, 0.15)
	Sfx.Play("Bolt", { Pitch = 1.6, Volume = 0.5 })
end

-- ROCKET JUMP: a blast under your feet.
function PowerFx.RocketJump(position)
	if not L or typeof(position) ~= "Vector3" then
		return
	end
	local color = colorOf("RocketJump")
	L.Puff(position, color, 2.5, 0.35, true)
	L.Ring(position, color, 6, 0.45, true)
	L.Emit(position, "Fire", color, 10)
	L.Emit(position, "Smoke", Color3.fromRGB(110, 110, 115), 6)
	L.LightFlash(position, color, 6, 18, 0.3)
	Sfx.PlayAt("Explosion", position, { Pitch = 1.4, Volume = 0.5 })
end

----------------------------------------------------------------------------
-- Powering up: a beam, a helix of sparks and the name over their head
----------------------------------------------------------------------------
local function powerUpBurst(model, id)
	local root = rootOf(model)
	local def = defs[id]
	if not root or not def or model:GetAttribute("Invisible") then
		return
	end
	local color = def.IconColor or WHITE
	local rarity = Config.Rarity[def.Rarity]
	local rarityColor = rarity and rarity.Color or WHITE
	local feet = root.Position - Vector3.new(0, 3, 0)

	-- beam
	local beam = L.FxPart(Vector3.new(14, 1.6, 1.6), CFrame.new(feet + Vector3.new(0, 7, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.PartType.Cylinder, true)
	beam.Transparency = 0.45
	L.FadeOut(beam, 0.9, { Size = Vector3.new(16, 0.1, 0.1) })
	L.Ring(feet + Vector3.new(0, 0.2, 0), color, 5, 0.6, true)
	task.delay(0.15, L.Ring, feet + Vector3.new(0, 0.2, 0), rarityColor, 7, 0.6, true)
	-- helix of sparks climbing the body
	for k = 1, 18 do
		task.delay(k * 0.025, function()
			if not root.Parent then
				return
			end
			local angle = k * 0.7
			local base = root.Position - Vector3.new(0, 3, 0)
			local from = base + Vector3.new(math.cos(angle) * 2, k * 0.15, math.sin(angle) * 2)
			local to = base + Vector3.new(math.cos(angle + 1.2) * 1.2, 2.5 + k * 0.25, math.sin(angle + 1.2) * 1.2)
			flyer(from, to, k % 3 == 0 and rarityColor or color, 0.28, 0.45)
		end)
	end
	L.LightFlash(root.Position, color, 5, 16, 0.6)
	if particlesOn() then
		task.delay(0.35, L.Emit, root.Position + Vector3.new(0, 2, 0), "Sparks", color, 18)
	end

	-- the name, rising over their head
	local head = model:FindFirstChild("Head")
	if head and model ~= player.Character then
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "PowerUpGained"
		billboard.Adornee = head
		billboard.AlwaysOnTop = true
		billboard.LightInfluence = 0
		billboard.Size = UDim2.fromOffset(220, 46)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.2, 0)
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.Text = "+ " .. string.upper(def.Name)
		label.TextColor3 = rarityColor
		label.Parent = billboard
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = Palette.UIBackground
		stroke.Parent = label
		billboard.Parent = player:FindFirstChildOfClass("PlayerGui")
		TweenService:Create(billboard, TweenInfo.new(1.8, Enum.EasingStyle.Quint), {
			StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0),
		}):Play()
		task.delay(1.2, function()
			TweenService:Create(label, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
			TweenService:Create(stroke, TweenInfo.new(0.6), { Transparency = 1 }):Play()
		end)
		Debris:AddItem(billboard, 2)
	end
	Sfx.PlayAt(def.Rarity == "Legendary" and "CardLegendary" or "CardPick", root.Position, { Volume = 0.8 })
end

----------------------------------------------------------------------------
-- Character auras
----------------------------------------------------------------------------
local records = {} -- [model] = record
local lastOwnedText = {} -- [key] = attribute text (so a respawn with a new pick is noticed)

local function keyOf(model)
	local owner = Players:GetPlayerFromCharacter(model)
	return owner and ("u" .. owner.UserId) or ("m" .. model.Name)
end

local function emitter(parent, color, props)
	local e = Instance.new("ParticleEmitter")
	e.Texture = FX.SparkTexture
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Enabled = false
	for k, v in pairs(props) do
		e[k] = v
	end
	e.Parent = parent
	return e
end

local function newRecord(model, root)
	local rec = { Model = model, Root = root, Instances = {}, Flags = {} }
	local function keep(inst)
		table.insert(rec.Instances, inst)
		return inst
	end
	local center = keep(Instance.new("Attachment"))
	center.Name = "PowerFxCenter"
	center.Parent = root
	rec.Center = center
	local top = keep(Instance.new("Attachment"))
	top.Name = "PowerFxTop"
	top.Position = Vector3.new(0, 1.2, 0)
	top.Parent = root
	local bottom = keep(Instance.new("Attachment"))
	bottom.Name = "PowerFxBottom"
	bottom.Position = Vector3.new(0, -1.6, 0)
	bottom.Parent = root

	rec.Regen = keep(emitter(center, Color3.fromRGB(90, 230, 140), {
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.6, 1),
		Speed = NumberRange.new(2, 4),
		Acceleration = Vector3.new(0, 6, 0),
		SpreadAngle = Vector2.new(180, 180),
		Rate = 14,
		Shape = Enum.ParticleEmitterShape.Cylinder,
	}))
	rec.Embers = keep(emitter(center, Color3.fromRGB(255, 70, 50), {
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(1, 3),
		Acceleration = Vector3.new(0, 9, 0),
		SpreadAngle = Vector2.new(180, 180),
		Rate = 18,
	}))
	rec.Glints = keep(emitter(center, Color3.fromRGB(220, 240, 255), {
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.3), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.4, 0.6),
		Speed = NumberRange.new(0, 0.5),
		SpreadAngle = Vector2.new(180, 180),
		Rate = 3,
		Shape = Enum.ParticleEmitterShape.Box,
	}))
	rec.Feathers = keep(emitter(top, WHITE, {
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0.15) }),
		Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(1, 2),
		Drag = 2,
		Acceleration = Vector3.new(0, 3, 0),
		SpreadAngle = Vector2.new(180, 180),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-90, 90),
		LightEmission = 0.3,
		Rate = 10,
	}))
	-- the knife hand glow
	local hand = model:FindFirstChild("RightHand") or model:FindFirstChild("Right Arm")
	if hand then
		local handAttach = keep(Instance.new("Attachment"))
		handAttach.Name = "PowerFxHand"
		handAttach.Parent = hand
		rec.Hand = handAttach
		rec.KnifeSparks = keep(emitter(handAttach, WHITE, {
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0) }),
			Lifetime = NumberRange.new(0.2, 0.4),
			Speed = NumberRange.new(1, 3),
			SpreadAngle = Vector2.new(180, 180),
			Rate = 16,
		}))
		if FX.Lights ~= false then
			local light = keep(Instance.new("PointLight"))
			light.Range = 6
			light.Brightness = 1.5
			light.Shadows = false
			light.Enabled = false
			light.Parent = handAttach
			rec.KnifeLight = light
		end
	end
	-- speed trail
	local trail = keep(Instance.new("Trail"))
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = 0.25
	trail.MinLength = 0.1
	trail.FaceCamera = true
	trail.LightEmission = 0.8
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) })
	trail.Enabled = false
	trail.Parent = root
	rec.Trail = trail
	-- low-health glow
	if FX.Lights ~= false then
		local glow = keep(Instance.new("PointLight"))
		glow.Color = Color3.fromRGB(255, 60, 50)
		glow.Range = 10
		glow.Brightness = 0
		glow.Shadows = false
		glow.Parent = center
		rec.Glow = glow
	end
	rec.LastHealth = nil
	rec.HealUntil = 0
	rec.LastVY = 0
	rec.Weapon = model:GetAttribute("Weapon")
	rec.Invisible = model:GetAttribute("Invisible") == true
	return rec
end

local function destroyRecord(rec)
	for _, inst in ipairs(rec.Instances) do
		inst:Destroy()
	end
	if rec.Bubble then
		rec.Bubble:Destroy()
	end
	for _, plate in ipairs(rec.Plates or {}) do
		plate:Destroy()
	end
end

-- the shield bubble (Overshield / Bloodlust)
local function setBubble(rec, on, color, t)
	if on and not rec.Bubble then
		local bubble = L.FxPart(Vector3.one * 6.6, rec.Root.CFrame, color, Enum.PartType.Ball, false)
		bubble.Material = Enum.Material.ForceField
		rec.Bubble = bubble
	elseif not on and rec.Bubble then
		local bubble = rec.Bubble
		rec.Bubble = nil
		L.FadeOut(bubble, 0.25, { Size = Vector3.one * 8 })
	end
	if rec.Bubble then
		rec.Bubble.Color = color
		rec.Bubble.CFrame = rec.Root.CFrame
		rec.Bubble.Transparency = 0.15 + (math.sin(t * 5) + 1) * 0.1
	end
end

-- Kinetic Armor plates orbiting the torso
local function setPlates(rec, on, color, t)
	if on and not rec.Plates then
		rec.Plates = {}
		for _ = 1, 3 do
			local plate = L.FxPart(Vector3.new(0.12, 1.1, 0.9), rec.Root.CFrame, color, nil, true)
			plate.Transparency = 0.25
			table.insert(rec.Plates, plate)
		end
	elseif not on and rec.Plates then
		for _, plate in ipairs(rec.Plates) do
			L.FadeOut(plate, 0.2)
		end
		rec.Plates = nil
	end
	if rec.Plates then
		local base = rec.Root.CFrame
		for i, plate in ipairs(rec.Plates) do
			local angle = t * 6 + i * (math.pi * 2 / 3)
			local offset = Vector3.new(math.cos(angle) * 2.1, 0.3, math.sin(angle) * 2.1)
			plate.CFrame = CFrame.lookAt(base.Position + offset, base.Position + offset * 2)
				* CFrame.Angles(0, math.rad(90), 0)
		end
	end
end

-- is there ground right under this root?
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
local function nearGround(rec)
	groundParams.FilterDescendantsInstances = { rec.Model, workspace.CurrentCamera }
	return workspace:Raycast(rec.Root.Position, Vector3.new(0, -4.2, 0), groundParams) ~= nil
end

local function onEvents(rec, owned, isMe, vy, wasVY)
	local feet = rec.Root.Position - Vector3.new(0, 3, 0)
	-- launches: a big jump in upward speed
	if vy - wasVY > 28 and vy > 20 then
		local grounded = nearGround(rec)
		if not grounded and has(owned, "DoubleJump") then
			local color = colorOf("DoubleJump")
			L.Ring(feet, color, 3.5, 0.4, true)
			L.Puff(feet, color, 1.4, 0.25, true)
		elseif grounded and has(owned, "SpringLegs") then
			local color = colorOf("SpringLegs")
			for k = 0, 2 do
				task.delay(k * 0.05, L.Ring, feet + Vector3.new(0, k * 0.6, 0), color, 1.6 + k * 0.6, 0.35, true)
			end
		end
	end
	-- heavy landings
	if wasVY < -45 and vy > -8 and has(owned, "ThickSkin") then
		local color = colorOf("ThickSkin")
		L.Ring(feet + Vector3.new(0, 0.2, 0), color, 6, 0.4, false)
		L.Emit(feet, "Dust", Palette.Light, 10)
	end
end

local function updateRecord(rec, t, dt)
	local model, root = rec.Model, rec.Root
	local owned = PowerFx.OwnedOf(model) or {}
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local alive = humanoid ~= nil and humanoid.Health > 0
	local isMe = model == player.Character
	local invisible = model:GetAttribute("Invisible") == true

	-- Phantom Step: a puff when they vanish or come back (never shows where they are mid-step)
	if invisible ~= rec.Invisible then
		rec.Invisible = invisible
		if not isMe then
			L.Emit(root.Position, "Smoke", colorOf("PhantomDash"), 6)
			L.Puff(root.Position, colorOf("PhantomDash"), 2.5, 0.3, true)
		end
	end
	local show = alive and not invisible

	local v = root.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	local health = humanoid and humanoid.Health or 0
	local maxHealth = humanoid and math.max(humanoid.MaxHealth, 1) or 100

	-- REGENERATION: green sparkles while healing
	if rec.LastHealth and health > rec.LastHealth + 0.01 and health < maxHealth then
		rec.HealUntil = t + 0.4
	end
	rec.LastHealth = health
	rec.Regen.Enabled = particlesOn() and show and has(owned, "Regeneration") and t < rec.HealUntil

	-- LAST STAND: embers + a red glow at low health
	local low = has(owned, "LastStand") and health <= maxHealth * PU.LastStand.HealthFraction
	rec.Embers.Enabled = particlesOn() and show and low
	if rec.Glow then
		rec.Glow.Brightness = (show and low and not isMe) and (1.2 + math.sin(t * 7) * 0.8) or 0
	end

	-- GLASS CANNON: faint glints
	rec.Glints.Enabled = particlesOn() and show and has(owned, "GlassCannon") and not isMe

	-- FEATHERWEIGHT: feathers while falling
	rec.Feathers.Enabled = particlesOn() and show and has(owned, "Featherweight") and v.Y < -8

	-- SHIELD BUBBLE (Overshield / Bloodlust): others only (it would fill your own view)
	local shield = model:GetAttribute("Shield") or 0
	local shieldOn = show and not isMe and shield > 0 and (has(owned, "Overshield") or has(owned, "Bloodlust"))
	setBubble(rec, shieldOn, has(owned, "Bloodlust") and colorOf("Bloodlust") or colorOf("Overshield"), t)

	-- KINETIC ARMOR: plates orbit while moving fast
	setPlates(rec, show and not isMe and has(owned, "KineticArmor") and speed >= PU.KineticArmor.MinSpeed, colorOf("KineticArmor"), t)

	-- SPEED TRAIL
	local trailId
	for _, id in ipairs({ "Adrenaline", "FightOrFlight", "AirDash", "Slingshot", "MomentumRounds" }) do
		if has(owned, id) then
			trailId = id
			break
		end
	end
	rec.Trail.Enabled = show and trailId ~= nil and speed > 30
	if trailId then
		local c = colorOf(trailId)
		rec.Trail.Color = ColorSequence.new(c:Lerp(WHITE, 0.4), c)
	end

	-- KNIFE GLOW (Keen Edge / Hunter's Knife)
	local weapon = model:GetAttribute("Weapon")
	local knifeId = has(owned, "HuntersKnife") and "HuntersKnife" or (has(owned, "KeenEdge") and "KeenEdge" or nil)
	local knifeOn = show and weapon == "Knife" and knifeId ~= nil
	if rec.KnifeSparks then
		rec.KnifeSparks.Enabled = particlesOn() and knifeOn and not isMe
		if knifeId then
			rec.KnifeSparks.Color = ColorSequence.new(bright(knifeId, 0.3))
		end
	end
	if rec.KnifeLight then
		rec.KnifeLight.Enabled = knifeOn
		if knifeId then
			rec.KnifeLight.Color = colorOf(knifeId)
		end
	end

	-- QUICKDRAW: a flash on every weapon swap
	if weapon ~= rec.Weapon then
		rec.Weapon = weapon
		if show and has(owned, "Quickdraw") and rec.Hand then
			L.Puff(rec.Hand.WorldPosition, WHITE, 1.2, 0.2, true)
			L.Emit(rec.Hand.WorldPosition, "Sparks", colorOf("Quickdraw"), 8)
		end
	end

	-- jumps / landings
	if show then
		onEvents(rec, owned, isMe, v.Y, rec.LastVY)
	end
	rec.LastVY = v.Y

	-- POWERING UP: a new power-up since this player's last character
	local text = model:GetAttribute("PowerUps")
	if typeof(text) == "string" and text ~= rec.OwnedText then
		local key = keyOf(model)
		local previous = lastOwnedText[key]
		rec.OwnedText = text
		lastOwnedText[key] = text
		if previous ~= nil and previous ~= text and alive then
			local before = {}
			for id, n in previous:gmatch("([%w_]+):(%d+)") do
				before[id] = tonumber(n)
			end
			for id, n in pairs(owned) do
				if n > (before[id] or 0) then
					powerUpBurst(model, id)
					break -- (one at a time: picks come one per round)
				end
			end
		end
	end
end

-- Your own movement (only your game knows your movement mode).
local slideTimer = 0
local bulletTimer = 0
local lastMode
local function updateOwnMovement(dt)
	local movement = Controllers.Movement
	local character = player.Character
	local root = rootOf(character)
	if not movement or not root then
		return
	end
	local owned = ClientState.Owned or {}
	local mode = movement.GetMode()
	local feet = root.Position - Vector3.new(0, 3, 0)
	slideTimer += dt
	if slideTimer >= 0.05 then
		slideTimer = 0
		-- POWER SLIDE: a fiery slide
		if mode == "Slide" and has(owned, "PowerSlide") then
			L.Emit(feet, "Fire", colorOf("PowerSlide"), 1)
			L.Emit(feet, "Sparks", bright("PowerSlide", 0.3), 2)
		end
		-- WALL RUNNER: sparks scrape off the wall
		if mode == "WallRun" and has(owned, "WallRunner") then
			local side = movement.GetWallSide and movement.GetWallSide() or 0
			local cf = root.CFrame
			L.Emit(root.Position + cf.RightVector * (typeof(side) == "number" and side or 0) * 1.5, "Sparks", colorOf("WallRunner"), 2)
		end
		-- MAGNETIC BOOTS: arcs under your feet on walls and ceilings
		if (mode == "Ceiling" or mode == "WallRun") and has(owned, "MagneticBoots") then
			local up = root.CFrame.UpVector
			local a = root.Position + up * 2.8
			L.Tracer(a, a + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 1.6, colorOf("MagneticBoots"), 0.05, 0.12)
		end
	end
	-- BULLET TIME: slow ripples spread from you while time is slowed
	bulletTimer -= dt
	if movement.IsBulletTime and movement.IsBulletTime() and bulletTimer <= 0 then
		bulletTimer = 0.35
		L.Ring(feet + Vector3.new(0, 0.3, 0), colorOf("BulletTime"), 9, 0.6, true)
	end

	-- SLINGSHOT: jumping out of a slide
	if lastMode == "Slide" and mode == "Air" and has(owned, "Slingshot") then
		local v = root.AssemblyLinearVelocity
		local dir = Vector3.new(v.X, 0, v.Z)
		if dir.Magnitude > 1 then
			crossRing(root.Position, dir.Unit, colorOf("Slingshot"), 1.2, 0.35, 2.4)
		end
		L.Emit(feet, "Dust", Palette.Light, 6)
	end
	lastMode = mode
end

local function characters()
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	local bots = workspace:FindFirstChild("Bots")
	if bots then
		for _, model in ipairs(bots:GetChildren()) do
			if model:IsA("Model") then
				table.insert(list, model)
			end
		end
	end
	return list
end

local scanTimer = 0
local function step(dt)
	if not L then
		return
	end
	local t = os.clock()
	-- refresh who's around a few times a second
	scanTimer -= dt
	if scanTimer <= 0 then
		scanTimer = 0.5
		local seen = {}
		for _, model in ipairs(characters()) do
			local root = rootOf(model)
			if root and typeof(model:GetAttribute("PowerUps")) == "string" then
				seen[model] = true
				local rec = records[model]
				if rec and rec.Root ~= root then
					destroyRecord(rec)
					rec = nil
				end
				if not rec then
					records[model] = newRecord(model, root)
				end
			end
		end
		for model, rec in pairs(records) do
			if not seen[model] or not model.Parent then
				destroyRecord(rec)
				records[model] = nil
			end
		end
	end
	for model, rec in pairs(records) do
		if rec.Root.Parent then
			local ok, err = pcall(updateRecord, rec, t, dt)
			if not ok then
				warn("[PowerFx]", err)
				destroyRecord(rec)
				records[model] = nil
			end
		end
	end
	updateOwnMovement(dt)
end

function PowerFx.Init(controllers)
	Controllers = controllers
end

function PowerFx.Start()
	L = Controllers.Effects and Controllers.Effects.Lib
	RunService.Heartbeat:Connect(step)
end

return PowerFx
