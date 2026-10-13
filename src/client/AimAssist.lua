--[[
	AimAssist.lua  (Client.AimAssist)

	Light aim assist for CONTROLLER players only (mouse users never get it).
	Two small effects, both only when the crosshair is already close to a
	target you can actually see:

	  1. Slowdown: your aim turns a bit slower while it's over / near the
	     target, so it's easier to stay on them.
	  2. Gentle pull: while you're moving or using the right stick, the aim
	     drifts slightly toward the target's body (never the head, so
	     headshots still take skill). Standing still with no input = no pull.

	Targets: the enemy in a match (not while invisible), the practice
	dummies in the lobby / playground. All numbers are in Config.AimAssist,
	and players can turn it off in the settings menu.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ClientState = require(script.Parent.ClientState)

local A = Config.AimAssist
local player = Players.LocalPlayer

local AimAssist = {}

local rightStick = Vector2.zero
local lastLook -- our look direction at the end of last frame

-- Controller and touch players get the assist (mouse players never do).
local function usingController()
	local last = UserInputService:GetLastInputType()
	return last.Name:find("Gamepad") ~= nil or last == Enum.UserInputType.Touch
end

-- Points we may assist toward: the enemy's torso, or the dummies' torsos.
local function getTargets()
	local list = {}
	if ClientState.InMatch() then
		if not ClientState.IsFighting() then
			return list
		end
		local opponent = ClientState.GetOpponentPlayer()
		local character = opponent and opponent.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 and not character:GetAttribute("Invisible") then
			local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
			if torso then
				table.insert(list, { Point = torso.Position, Model = character })
			end
		end
	else
		local folder = workspace:FindFirstChild("Dummies")
		for _, dummy in ipairs(folder and folder:GetChildren() or {}) do
			local torso = dummy:FindFirstChild("UpperTorso")
			if torso and not dummy:GetAttribute("Down") then
				table.insert(list, { Point = torso.Position, Model = dummy })
			end
		end
	end
	return list
end

local function canSee(origin, target)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = { workspace.CurrentCamera, target.Model }
	if player.Character then
		table.insert(exclude, player.Character)
	end
	for _, name in ipairs({ "Effects", "Decoys" }) do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(exclude, f)
		end
	end
	params.FilterDescendantsInstances = exclude
	return workspace:Raycast(origin, target.Point - origin, params) == nil
end

-- Angle in radians between two unit vectors.
local function angleBetween(a, b)
	return math.acos(math.clamp(a:Dot(b), -1, 1))
end

-- Rotates unit vector `from` toward `to` by at most `maxAngle` radians.
local function rotateToward(from, to, maxAngle)
	local angle = angleBetween(from, to)
	if angle < 1e-5 then
		return from
	end
	local t = math.min(1, maxAngle / angle)
	return from:Lerp(to, t).Unit
end

--[[
	Called by the CameraController every frame AFTER Roblox's camera has
	applied this frame's stick input and BEFORE recoil / roll.
	scopeAlpha: 0 = hip fire, 1 = fully scoped.
]]
function AimAssist.Update(camera, dt, scopeAlpha)
	local look = camera.CFrame.LookVector
	local enabled = A.Enabled
		and ClientState.Settings.AimAssist ~= false
		and usingController()
		and not ClientState.MenuOpen
		and ClientState.HasGun()
	if not enabled then
		lastLook = look
		return
	end

	local origin = camera.CFrame.Position
	-- the assist cone shrinks with the field of view (smaller when scoped)
	local cone = math.rad(A.ConeDegrees) * (camera.FieldOfView / Config.Camera.BaseFOV)

	-- closest visible target inside the cone
	local best, bestAngle, bestDir
	for _, target in ipairs(getTargets()) do
		local toTarget = target.Point - origin
		local distance = toTarget.Magnitude
		if distance > 1 and distance <= A.Range then
			local dir = toTarget / distance
			local angle = angleBetween(look, dir)
			if angle <= cone and (not best or angle < bestAngle) and canSee(origin, target) then
				best, bestAngle, bestDir = target, angle, dir
			end
		end
	end

	if best then
		local closeness = 1 - bestAngle / cone -- 1 = dead centre, 0 = edge of the cone

		-- 1) SLOWDOWN: undo part of this frame's turn while near the target
		if lastLook then
			local slow = A.Slowdown * closeness
			local turned = angleBetween(lastLook, look)
			if turned > 1e-5 and slow > 0 then
				look = rotateToward(look, lastLook, turned * slow)
			end
		end

		-- 2) PULL: a gentle drift toward the body, only while you're moving
		--    or actively aiming (never when idle)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local moving = humanoid and humanoid.MoveDirection.Magnitude > 0.1
		local aiming = rightStick.Magnitude > 0.15
		if moving or aiming then
			local strength = math.rad(A.PullDegreesPerSecond) * closeness * dt
			if scopeAlpha > 0.5 then
				strength *= A.ScopedPullMultiplier
			end
			look = rotateToward(look, bestDir, strength)
		end

		camera.CFrame = CFrame.lookAt(origin, origin + look)
	end
	lastLook = look
end

function AimAssist.Start()
	UserInputService.InputChanged:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Thumbstick2 then
			rightStick = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
end

return AimAssist
