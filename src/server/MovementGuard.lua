--[[
	MovementGuard.lua  (ServerScriptService.Server.MovementGuard)

	Server anti-cheat for movement. Clients own their characters' physics
	(that's what makes bunny hopping feel good), so a cheater could teleport
	or speed-hack. Every Config.AntiCheat.Interval seconds this checks how
	far each character moved since the last check:

	  * further sideways than MaxSpeed (+ Slack) allows, or
	  * further UP than MaxRise allows
	  -> after half a second (an ability event can arrive just after the
	     client moved) the character is put back where it last was legit,
	     and the player gets a strike (logged in the server output).
	     StrikesToKick strikes within StrikeWindow seconds kicks them.

	It's deliberately generous: real movement never comes close. Abilities
	that teleport or launch (Blink, Recall, Air Dash, grapple, knockback...)
	and every respawn call MovementGuard.Grace(player), which skips the
	checks for a moment.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Util = require(ReplicatedStorage.Shared.Util)

local MovementGuard = {}

local AC = Config.AntiCheat or {}
local state = {} -- [player] = { Character, Position, Time, GraceUntil, Strikes = { times } }

local function stateOf(player)
	local s = state[player]
	if not s then
		s = { Strikes = {}, GraceUntil = 0 }
		state[player] = s
	end
	return s
end

-- Skip the checks for a moment (teleporting abilities, knockback, respawns).
function MovementGuard.Grace(player, seconds)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return -- (bots are moved by the server)
	end
	local s = stateOf(player)
	local now = os.clock()
	s.GraceUntil = math.max(s.GraceUntil, now + (seconds or AC.Grace or 0.8))
	s.LastGrace = now
end

local function strike(player, s, reason)
	local now = os.clock()
	table.insert(s.Strikes, now)
	while s.Strikes[1] and now - s.Strikes[1] > (AC.StrikeWindow or 60) do
		table.remove(s.Strikes, 1)
	end
	warn(("[MovementGuard] %s (%d): %s  (%d strikes)"):format(player.Name, player.UserId, reason, #s.Strikes))
	local limit = AC.StrikesToKick or 0
	if limit > 0 and #s.Strikes >= limit then
		player:Kick("Movement checks failed too many times. If this was a mistake, just rejoin.")
	end
end

local function putBack(character, root, position)
	root.AssemblyLinearVelocity = Vector3.zero
	character:PivotTo(CFrame.new(position) * (root.CFrame - root.CFrame.Position))
end

local function check(player, now)
	local s = stateOf(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		s.Position, s.Pending = nil, nil
		return
	end
	if character ~= s.Character then
		s.Character = character
		s.Position, s.Pending = nil, nil
		s.GraceUntil = math.max(s.GraceUntil, now + (AC.Grace or 0.8))
	end
	local position = root.Position
	if now < s.GraceUntil or character:GetAttribute("Frozen") or not s.Position then
		s.Position, s.Time, s.Pending = position, now, nil
		return
	end

	-- a jump we're waiting to judge: an ability event (Recall, Blink...) can
	-- arrive a moment AFTER the client already moved
	local pending = s.Pending
	if pending then
		if (s.LastGrace or 0) >= pending.At - 0.6 then
			s.Position, s.Time, s.Pending = position, now, nil
		elseif now - pending.At >= 0.5 then
			s.Pending = nil
			putBack(character, root, pending.Back)
			s.Position, s.Time = pending.Back, now
			strike(player, s, pending.Reason)
		end
		return
	end

	local moved = position - s.Position
	if moved.Magnitude < 0.01 then
		-- no new position from their client yet (lag): let the time budget
		-- build up a little, so a catch-up burst isn't a false alarm
		if now - s.Time > 1.5 then
			s.Time = now - 1.5
		end
		return
	end
	local dt = math.clamp(now - s.Time, 1 / 60, 1.5)
	local sideways = Util.flat(moved).Magnitude
	local rise = moved.Y
	local slack = AC.Slack or 12
	local maxSide = (AC.MaxSpeed or 160) * dt + slack
	local maxRise = (AC.MaxRise or 140) * dt + slack
	if sideways > maxSide or rise > maxRise then
		s.Pending = {
			Back = s.Position,
			At = now,
			Reason = ("moved %.0f studs sideways / %.0f up in %.2fs"):format(sideways, rise, dt),
		}
		return
	end
	s.Position, s.Time = position, now
end

function MovementGuard.Init()
	if AC.Enabled == false then
		return
	end
	Players.PlayerRemoving:Connect(function(player)
		state[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(AC.Interval or 0.25)
			local now = os.clock()
			for _, player in ipairs(Players:GetPlayers()) do
				local ok, err = pcall(check, player, now)
				if not ok then
					warn("[MovementGuard]", err)
				end
			end
		end
	end)
end

return MovementGuard
