--[[
	Remotes.lua  (ReplicatedStorage.Shared.Remotes)

	One place that lists every RemoteEvent the game uses. The server creates
	them; clients wait for them. Use it like:

		local Remotes = require(ReplicatedStorage.Shared.Remotes)
		Remotes.Get("Fire"):FireServer(...)

	C->S = client to server, S->C = server to client
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

Remotes.Names = {
	"QueueToggle", -- C->S  join / leave the match queue
	"MatchState", -- S->C  full match/lobby state snapshot (phase, scores, power-ups, cards)
	"Fire", -- C->S  shot request (origin, direction, hit claims)
	"ShotFx", -- S->C  bullet paths for drawing the enemy's tracers
	"HitConfirm", -- S->C  tells the shooter what they hit (hitmarker / kill sound)
	"Damaged", -- S->C  tells the victim they were hit (and from where)
	"PickCard", -- C->S  the loser picks a power-up card by index
	"Ability", -- C->S  power-up abilities (Decoy, PhantomDash, Shockwave, Grapple visuals)
	"Knockback", -- S->C  push the local character (client owns its physics)
	"Buff", -- S->C  timed buffs, e.g. Second Wind speed boost
	"Effect", -- S->C  one-off visual effects (explosions, shockwaves, grapple ropes)
	"SettingsLoad", -- S->C  saved settings for this player
	"SettingsSave", -- C->S  save settings
	"Aim", -- C->S  where you're looking up/down (others see your aim pose)
	"Practice", -- C->S  lobby power-up lab: add / remove / clear practice power-ups
	"PlaygroundToggle", -- C->S  enter / leave Playground mode
	"AdminCommand", -- C->S  admin commands (e.g. "bot" starts a match vs a bot)
	"Notify", -- S->C  short toast message (admin command results etc.)
	"Duel", -- C->S  "Challenge" (userId) / "Accept" / "Decline" (userId) / "Rematch"
	"DuelInvite", -- S->C  someone challenged you / wants a rematch
	"CrateOpen", -- C->S  open a crate at the lobby altar
	"Crates", -- S->C  crate results + your keys / skins
	"SkinEquip", -- C->S  equip: kind ("Rifle" / "Knife" / "Tracer" / "KillFx" / "Pose" / "Title"), id (nil = default)
	"ShopBuy", -- C->S  buy with credits: ("Featured", skinId)
	"Equip", -- C->S  switch weapon: "Sniper" / "Knife"
	"Melee", -- C->S  knife swing: kind ("Slash" / "Stab"), what it hit, look direction
	"Anim", -- C->S  cosmetic animation events others should see ("Inspect", "Scope")
}

local FOLDER_NAME = "Remotes"

local folder

local function getFolder()
	if folder then
		return folder
	end
	if RunService:IsServer() then
		folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = FOLDER_NAME
			folder.Parent = ReplicatedStorage
		end
		for _, name in ipairs(Remotes.Names) do
			if not folder:FindFirstChild(name) then
				local remote = Instance.new("RemoteEvent")
				remote.Name = name
				remote.Parent = folder
			end
		end
	else
		folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	end
	return folder
end

-- On the server, Get returns a thin wrapper so FireClient quietly skips
-- bots (they're plain tables, not real Players, and have no client).
local wrappers = {}
local function wrap(remote)
	local wrapper = wrappers[remote]
	if not wrapper then
		wrapper = {
			Remote = remote,
			Name = remote.Name,
			OnServerEvent = remote.OnServerEvent,
			FireClient = function(_, player, ...)
				if typeof(player) == "Instance" and player.Parent then
					remote:FireClient(player, ...)
				end
			end,
			FireAllClients = function(_, ...)
				remote:FireAllClients(...)
			end,
		}
		wrappers[remote] = wrapper
	end
	return wrapper
end

-- Returns the RemoteEvent with this name (a bot-safe wrapper on the server).
function Remotes.Get(name)
	local f = getFolder()
	if RunService:IsServer() then
		local remote = f:FindFirstChild(name)
		return remote and wrap(remote)
	end
	return f:WaitForChild(name)
end

-- Server: call once at startup so every remote exists before clients ask.
function Remotes.Init()
	getFolder()
end

return Remotes
