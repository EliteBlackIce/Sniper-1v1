--[[
	KnifeAnim.lua  (Client.KnifeAnim)

	The knife's first-person animation maths, used by ViewmodelController:
	poses in camera space for idle / sprint / equip / slash / stab / inspect
	(toss and catch, or twirl), and a two-bone IK solve for the arms. Pure
	CFrame maths (no instances), so it can be previewed outside Roblox.

	Knife space: origin = the middle of the handle, blade toward -Z, edge -Y.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local KnifeModel = require(Shared.KnifeModel)

local KnifeAnim = {}

local rad = math.rad
local KN = Config.Knife

local function easeOutBack(t)
	local c1, c3 = 1.4, 2.4
	return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

local function smoothstep(t)
	return t * t * (3 - 2 * t)
end

-- A knife pose from where the handle is, which way the blade points and
-- which way the cutting edge faces (camera space: +X right, +Y up, -Z ahead).
local function knifeCF(pos, blade, edge)
	local z = -blade.Unit -- knife -Z = blade
	local y = -(edge - z * edge:Dot(z)).Unit -- knife -Y = edge, made square to the blade
	local x = y:Cross(z)
	return CFrame.fromMatrix(pos, x, y, z)
end
local V = Vector3.new

local KNIFE_IDLE = knifeCF(V(0.62, -0.55, -1.3), V(-0.5, 0.42, -0.75), V(-0.25, -1, 0))
local KNIFE_SPRINT = knifeCF(V(0.55, -0.85, -1.0), V(-0.35, -0.15, -0.9), V(0, -1, 0))
local KNIFE_EQUIP = knifeCF(V(0.6, -1.5, -0.6), V(0, -1, 0.2), V(-1, 0, 0))
local SLASH_KEYS = {
	-- right to left, edge first, the blade lying across your view
	[1] = {
		knifeCF(V(1.0, -0.15, -1.05), V(0.2, 0.65, -0.75), V(-1, 0, 0)),
		knifeCF(V(0.1, -0.35, -1.5), V(-0.75, 0.25, -0.6), V(-1, -0.2, 0.3)),
		knifeCF(V(-0.7, -0.7, -1.0), V(-0.6, -0.45, -0.6), V(-1, -0.5, 0)),
	},
	-- backhand, left to right
	[-1] = {
		knifeCF(V(-0.35, -0.25, -1.1), V(-0.6, 0.45, -0.65), V(1, 0, 0)),
		knifeCF(V(0.2, -0.35, -1.5), V(0.7, 0.2, -0.7), V(1, -0.2, 0.3)),
		knifeCF(V(0.95, -0.7, -0.95), V(0.6, -0.45, -0.6), V(1, -0.5, 0)),
	},
}
local STAB_BACK = knifeCF(V(0.75, -0.4, -0.75), V(-0.15, 0.3, -1), V(0, -1, 0))
local STAB_OUT = knifeCF(V(0.2, -0.3, -2.0), V(-0.25, 0.12, -1), V(0, -1, 0))
local TOSS_HOLD = knifeCF(V(0.32, -0.62, -1.3), V(-0.1, 1, -0.25), V(-1, 0, 0)) -- blade up, flat side to you
local ADMIRE = knifeCF(V(0.12, -0.42, -1.15), V(-1, 0.15, -0.2), V(0, -1, 0)) -- blade across, side on
local HAND_ON_KNIFE = KnifeModel.Grip * CFrame.Angles(rad(100), 0, 0) -- hand +Y points back to the wrist
local LEFT_GUARD = CFrame.new(-0.72, -1.02, -1.0) * CFrame.Angles(rad(60), rad(-15), rad(25))
local R_SHOULDER = Vector3.new(0.95, -1.25, 0.55)
local L_SHOULDER = Vector3.new(-0.95, -1.25, 0.55)
local UPPER, LOWER = 1.05, 1.0

local function lerpKeys(a, b, c, x)
	if x < 0.5 then
		return a:Lerp(b, x * 2)
	end
	return b:Lerp(c, (x - 0.5) * 2)
end

-- Two-bone IK: the elbow for a shoulder S reaching wrist W, bending toward `pole`.
function KnifeAnim.SolveElbow(S, W, pole)
	local toW = W - S
	local d = math.clamp(toW.Magnitude, 0.05, UPPER + LOWER - 0.01)
	local dir = toW.Unit
	local cosA = math.clamp((UPPER * UPPER + d * d - LOWER * LOWER) / (2 * UPPER * d), -1, 1)
	local sinA = math.sqrt(1 - cosA * cosA)
	local side = pole - dir * pole:Dot(dir)
	side = side.Magnitude > 1e-3 and side.Unit or Vector3.new(0, -1, 0)
	return S + dir * UPPER * cosA + side * UPPER * sinA
end

-- Knife pose (camera space) for animation state `a` at time t. Returns
-- knifeCF, handCF, free (knife in the air). onEvent(name) fires for sounds.
function KnifeAnim.Pose(a, t, base, onEvent)
	onEvent = onEvent or function() end
	local u = t - a.Start
	if a.Kind == "Equip" then
		local e = math.clamp(u / KN.EquipTime, 0, 1)
		local pose = KNIFE_EQUIP:Lerp(base, easeOutBack(e)) * CFrame.Angles((1 - smoothstep(e)) * math.pi * 2, 0, 0)
		return pose, pose * HAND_ON_KNIFE, false
	elseif a.Kind == "Slash" then
		local x = u / KN.SlashTime
		local k = SLASH_KEYS[a.Side or 1]
		local pose
		if x < 0.18 then
			pose = base:Lerp(k[1], smoothstep(x / 0.18))
		elseif x < 0.48 then
			pose = lerpKeys(k[1], k[2], k[3], smoothstep((x - 0.18) / 0.3))
		elseif x < 1 then
			pose = k[3]:Lerp(base, smoothstep((x - 0.48) / 0.52))
		else
			a.Kind = "Idle"
			pose = base
		end
		return pose, pose * HAND_ON_KNIFE, false
	elseif a.Kind == "Stab" then
		local x = u / KN.StabTime
		local pose
		if x < 0.26 then
			pose = base:Lerp(STAB_BACK, smoothstep(x / 0.26))
		elseif x < 0.4 then
			local y = (x - 0.26) / 0.14
			pose = STAB_BACK:Lerp(STAB_OUT, 1 - (1 - y) * (1 - y))
		elseif x < 0.53 then
			pose = STAB_OUT * CFrame.new(0, 0, math.sin((x - 0.4) / 0.13 * math.pi) * 0.04)
		elseif x < 1 then
			pose = STAB_OUT:Lerp(base, smoothstep((x - 0.53) / 0.47))
		else
			a.Kind = "Idle"
			pose = base
		end
		return pose, pose * HAND_ON_KNIFE, false
	elseif a.Kind == "Inspect" and a.Variant == "Toss" then
		a.Length = 2.2
		local hold = TOSS_HOLD
		if u < 0.25 then
			local pose = base:Lerp(hold, smoothstep(u / 0.25))
			return pose, pose * HAND_ON_KNIFE, false
		elseif u < 0.95 then
			-- up it goes, flipping end over end twice; the hand waits to catch it
			if not a.Tossed then
				a.Tossed = true
				onEvent("Toss")
			end
			local f = (u - 0.25) / 0.7
			local height = 4 * 1.15 * f * (1 - f)
			local pose = CFrame.new(hold.Position + Vector3.new(0, height, 0))
				* hold.Rotation
				* CFrame.Angles(-f * math.pi * 4, f * rad(20), 0)
			local hand = hold * CFrame.new(0, -0.08 * math.sin(f * math.pi), 0) * HAND_ON_KNIFE
			return pose, hand, true
		elseif u < 1.1 then
			if not a.Caught then
				a.Caught = true
				onEvent("Catch")
			end
			local pose = hold * CFrame.new(0, -0.12 * math.sin((u - 0.95) / 0.15 * math.pi), 0)
			return pose, pose * HAND_ON_KNIFE, false
		elseif u < 1.9 then
			local f = (u - 1.1) / 0.8
			local pose = hold:Lerp(ADMIRE, smoothstep(math.min(f * 2, 1))) * CFrame.Angles(0, 0, math.pi * smoothstep(f))
			return pose, pose * HAND_ON_KNIFE, false
		elseif u < 2.2 then
			local pose = (ADMIRE * CFrame.Angles(0, 0, math.pi)):Lerp(base, smoothstep((u - 1.9) / 0.3))
			return pose, pose * HAND_ON_KNIFE, false
		end
		a.Kind = "Idle"
		return base, base * HAND_ON_KNIFE, false
	elseif a.Kind == "Inspect" then
		-- twirl: three quick spins round the grip, then a flip into the hand
		a.Length = 1.6
		if u < 1.6 then
			local w = math.sin(math.clamp(u / 1.6, 0, 1) * math.pi)
			local spin = smoothstep(math.clamp((u - 0.15) / 1.1, 0, 1)) * math.pi * 6
			local lift = CFrame.new(-0.15 * w, 0.18 * w, 0.1 * w) * CFrame.Angles(0, rad(-25) * w, 0)
			local pose = base * lift * CFrame.new(KnifeModel.Grip.Position) * CFrame.Angles(-spin, 0, 0)
				* CFrame.new(-KnifeModel.Grip.Position)
			if not a.Tossed and u > 0.2 then
				a.Tossed = true
				onEvent("Twirl")
			end
			return pose, base * lift * HAND_ON_KNIFE, false
		end
		a.Kind = "Idle"
		return base, base * HAND_ON_KNIFE, false
	end
	return base, base * HAND_ON_KNIFE, false
end

KnifeAnim.Idle = KNIFE_IDLE
KnifeAnim.Sprint = KNIFE_SPRINT
KnifeAnim.HandOnKnife = HAND_ON_KNIFE
KnifeAnim.LeftGuard = LEFT_GUARD
KnifeAnim.RightShoulder = R_SHOULDER
KnifeAnim.LeftShoulder = L_SHOULDER

return KnifeAnim
