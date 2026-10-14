--[[
	Cosmetics.lua  (ReplicatedStorage.Shared.Cosmetics)

	Looks up the cosmetics in Config.Cosmetics (tracers, kill effects,
	victory poses, titles). Every item gets a Kind:
		"Tracer" | "KillFx" | "Pose" | "Title"
	Players wear them through attributes of the same name (the item's Id),
	set by the server (CrateService) when they equip one in the Locker.

		Cosmetics.Get(id)           -> item or nil
		Cosmetics.ForKind(kind)     -> list (the free default first)
		Cosmetics.Worn(player, kind) -> the item they have on (or the default)
		Cosmetics.TracerColor(player) -> Color3
]]

local Config = require(script.Parent.Config)

local Cosmetics = {}

Cosmetics.Kinds = { "Tracer", "KillFx", "Pose", "Title" }
local LISTS = { Tracer = "Tracers", KillFx = "KillEffects", Pose = "Poses", Title = "Titles" }

local byId, byKind, defaults = {}, {}, {}
for kind, listName in pairs(LISTS) do
	byKind[kind] = {}
	for _, item in ipairs(Config.Cosmetics[listName]) do
		item.Kind = kind
		byId[item.Id] = item
		table.insert(byKind[kind], item)
		if item.Default then
			defaults[kind] = item
		end
	end
end

function Cosmetics.Get(id)
	return id and byId[id] or nil
end

function Cosmetics.ForKind(kind)
	return byKind[kind] or {}
end

function Cosmetics.Default(kind)
	return defaults[kind]
end

-- The item a player (or a player-like table) has on, or the free default.
function Cosmetics.Worn(player, kind)
	local id = player and typeof(player) == "Instance" and player:GetAttribute(kind)
	local item = Cosmetics.Get(id)
	if item and item.Kind == kind then
		return item
	end
	return defaults[kind]
end

function Cosmetics.TracerColor(player)
	local item = Cosmetics.Worn(player, "Tracer")
	return item and item.Color or Config.Palette.Tracer
end

return Cosmetics
