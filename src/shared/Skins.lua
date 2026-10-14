--[[
	Skins.lua  (ReplicatedStorage.Shared.Skins)

	Paints a rifle or a knife in a skin (Config.Crates.Skins). The same
	model, new colours and finish: every part of a built weapon carries a
	"Paint" attribute (GunModel / KnifeModel set it: "Body", "Scope",
	"Bolt", "Blade", "Handle"...) and each group takes one of the skin's
	colours.

		Skins.Apply(weaponModel, skin)    -- after GunModel / KnifeModel.Build
		Skins.Get(id) -> skin or nil
		Skins.ForWeapon("Rifle" | "Knife") -> list

	Higher rarities add more:
		Rare       shiny finishes (metal, chrome, gold)
		Epic       the trims glow (rifle: bolt + stock trims, knife: the edge,
		           or the grip on the imported knife)
		Legendary  the glow pulses between two colours (clients animate parts
		           tagged "SkinPulse") and the weapon glitters
]]

local CollectionService = game and game:GetService("CollectionService")

local Config = require(script.Parent.Config)

local Skins = {}

local byId = {}
for _, skin in ipairs(Config.Crates.Skins) do
	byId[skin.Id] = skin
end

function Skins.Get(id)
	return id and byId[id] or nil
end

function Skins.ForWeapon(weapon)
	local list = {}
	for _, skin in ipairs(Config.Crates.Skins) do
		if skin.Weapon == weapon then
			table.insert(list, skin)
		end
	end
	return list
end

-- finish name -> { material, reflectance, transparency }
local FINISH = {
	Matte = { Enum.Material.SmoothPlastic, 0 },
	Gloss = { Enum.Material.SmoothPlastic, 0.12 },
	Pearl = { Enum.Material.SmoothPlastic, 0.3 },
	Metal = { Enum.Material.Metal, 0.05 },
	Chrome = { Enum.Material.Metal, 0.35 },
	Gold = { Enum.Material.Foil, 0.15 },
	Marble = { Enum.Material.Marble, 0.05 },
	Wood = { Enum.Material.Wood, 0 },
	Rust = { Enum.Material.CorrodedMetal, 0 },
	Tread = { Enum.Material.DiamondPlate, 0.1 },
	Frost = { Enum.Material.Ice, 0.05 },
	Stone = { Enum.Material.Slate, 0 },
	Crystal = { Enum.Material.Glass, 0.2, 0.25 },
	Hologram = { Enum.Material.ForceField, 0 },
}
Skins.Finishes = FINISH

local WHITE = Color3.new(1, 1, 1)

local function finish(part, name)
	local f = FINISH[name or "Matte"] or FINISH.Matte
	part.Material = f[1]
	part.Reflectance = f[2]
	if f[3] then
		part.Transparency = f[3]
	end
end

-- the metal parts: plain metal unless the skin gives them a finish (MetalFinish)
local function metal(part, skin)
	if skin and skin.MetalFinish then
		finish(part, skin.MetalFinish)
	else
		part.Material = Enum.Material.Metal
		part.Reflectance = 0
	end
end

-- Glowing trim: neon in the accent colour (pulsing for Legendary skins).
local function glow(part, skin)
	part.Color = skin.Accent
	part.Material = Enum.Material.Neon
	part.Reflectance = 0
	part.CastShadow = false
	if skin.Pulse then
		part:SetAttribute("PulseA", skin.Accent)
		part:SetAttribute("PulseB", skin.Pulse)
		if CollectionService then
			CollectionService:AddTag(part, "SkinPulse")
		end
	end
end

local RIFLE = {
	Body = function(part, skin)
		part.Color = skin.Body
		finish(part, skin.Finish)
	end,
	Stock = function(part, skin)
		part.Color = skin.Stock or skin.Body:Lerp(skin.Metal, 0.5)
		finish(part, skin.StockFinish or (skin.Finish == "Gold" and "Gloss" or skin.Finish))
	end,
	Metal = function(part, skin)
		part.Color = skin.Metal
		metal(part, skin)
	end,
	MetalLight = function(part, skin)
		part.Color = skin.Metal:Lerp(skin.Accent, 0.25)
		metal(part, skin)
	end,
	Trim = function(part, skin)
		if skin.Glow then
			glow(part, skin)
		else
			part.Color = skin.Accent
			metal(part, skin)
		end
	end,
}
-- paint group -> how to paint it (GunModel's mesh groups and part colours)
local RIFLE_GROUPS = {
	Body = RIFLE.Body,
	GunShell = RIFLE.Body,
	Stock = RIFLE.Stock,
	BodyMetal = RIFLE.Metal,
	GunMetal = RIFLE.Metal,
	Scope = RIFLE.Metal,
	Barrel = RIFLE.Metal,
	GunMetalLight = RIFLE.MetalLight,
	Bolt = RIFLE.Trim,
	StockDetail = RIFLE.Trim,
}

local KNIFE_GROUPS = {
	Blade = function(part, skin)
		part.Color = skin.Blade or skin.Metal
		finish(part, skin.Finish or "Metal")
	end,
	Edge = function(part, skin)
		if skin.Glow then
			glow(part, skin)
		else
			part.Color = (skin.Blade or skin.Metal):Lerp(WHITE, 0.35)
			finish(part, skin.Finish or "Metal")
		end
	end,
	Handle = function(part, skin)
		part.Color = skin.Body
		finish(part, skin.HandleFinish or (skin.Finish == "Gloss" and "Gloss" or "Matte"))
	end,
	Fittings = function(part, skin)
		part.Color = skin.Metal
		metal(part, skin)
	end,
}

local function sparkle(part, skin)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "SkinSparkle"
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(skin.Accent, skin.Pulse or skin.Accent)
	emitter.LightEmission = 1
	emitter.Lifetime = NumberRange.new(0.4, 0.8)
	emitter.Rate = 7
	emitter.Speed = NumberRange.new(0.2, 0.6)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new(0.1)
	emitter.LockedToPart = true
	emitter.Parent = part
end

-- Paints every part of a built weapon (anything with a "Paint" attribute).
function Skins.Apply(model, skin)
	if not skin then
		return
	end
	local groups = skin.Weapon == "Knife" and KNIFE_GROUPS or RIFLE_GROUPS
	local parts, hasEdge = {}, false
	for _, part in ipairs(model:GetDescendants()) do
		local key = part:IsA("BasePart") and part:GetAttribute("Paint")
		if key and groups[key] then
			table.insert(parts, part)
			hasEdge = hasEdge or key == "Edge"
		end
	end
	local biggest
	for _, part in ipairs(model:GetDescendants()) do
		-- the parts-built rifle (no imported mesh): its glow lines take the skin's glow
		if skin.Glow and skin.Weapon ~= "Knife" and part:IsA("BasePart") and part:GetAttribute("Paint") == "GunGlow" then
			glow(part, skin)
		end
	end
	for _, part in ipairs(parts) do
		local key = part:GetAttribute("Paint")
		if skin.Weapon == "Knife" and key == "Handle" and skin.Glow and not hasEdge then
			glow(part, skin) -- (the imported knife has no separate edge: its grip glows instead)
		else
			groups[key](part, skin)
		end
		local main = key == "Body" or key == "GunShell" or key == "Blade"
		if main and (not biggest or part.Size.Magnitude > biggest.Size.Magnitude) then
			biggest = part
		end
	end
	if skin.Sparkle and biggest then
		sparkle(biggest, skin)
	end
end

return Skins
