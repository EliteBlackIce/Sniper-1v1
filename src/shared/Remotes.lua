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

-- Returns the RemoteEvent with this name.
function Remotes.Get(name)
	local f = getFolder()
	if RunService:IsServer() then
		return f:FindFirstChild(name)
	end
	return f:WaitForChild(name)
end

-- Server: call once at startup so every remote exists before clients ask.
function Remotes.Init()
	getFolder()
end

return Remotes
