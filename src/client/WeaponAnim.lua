--[[
	WeaponAnim.lua  (Client.WeaponAnim)

	Every weapon animation, as pure maths (no instances), so the SAME motion
	plays on your character in first person and on everyone else's screen.

	For a moment in time it returns, in "view space" (the eye: +X right,
	+Y up, -Z where you look):
		Weapon     where the rifle's grip / the knife's handle is
		Right      where the right hand goes (nil = on the weapon's grip)
		Left       where the left hand goes
		Body       { Yaw, Pitch, Roll (degrees, the waist), Lean (degrees),
		             Dip / Forward (studs, the hips), Step (0-1, lunge legs) }
		Bolt       the bolt's offset (rifle)
	BodyAnimator then bends your real arms (IK), twists your torso and puts
	the weapon there.

	Knife moves are keyframed and played back on smooth splines (positions
	and rotations both), so they flow instead of stopping at each pose.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local KnifeModel = require(Shared.KnifeModel)

local WeaponAnim = {}

local rad = math.rad
local V = Vector3.new
local KN = Config.Knife
local B = Config.Body

----------------------------------------------------------------------------
-- Maths helpers
----------------------------------------------------------------------------
local function clamp01(x)
	return math.clamp(x, 0, 1)
end
local function smoothstep(t)
	t = clamp01(t)
	return t * t * (3 - 2 * t)
end
local function easeOutBack(t)
	t = clamp01(t)
	local c1, c3 = 1.5, 2.5
	return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end
local function seg(t, a, b)
	return clamp01((t - a) / (b - a))
end

-- A pose from where the handle is, which way the blade (or barrel) points
-- and which way the edge (or the gun's underside) faces.
local function aim(pos, forward, down)
	local z = -forward.Unit
	local y = -(down - z * down:Dot(z)).Unit
	return CFrame.fromMatrix(pos, y:Cross(z), y, z)
end
WeaponAnim.Aim = aim

-- quaternion helpers for smooth rotation splines
local function toQuat(cf)
	local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	local trace = r00 + r11 + r22
	local w, x, y, z
	if trace > 0 then
		local s = math.sqrt(trace + 1) * 2
		w, x, y, z = 0.25 * s, (r21 - r12) / s, (r02 - r20) / s, (r10 - r01) / s
	elseif r00 > r11 and r00 > r22 then
		local s = math.sqrt(1 + r00 - r11 - r22) * 2
		w, x, y, z = (r21 - r12) / s, 0.25 * s, (r01 + r10) / s, (r02 + r20) / s
	elseif r11 > r22 then
		local s = math.sqrt(1 + r11 - r00 - r22) * 2
		w, x, y, z = (r02 - r20) / s, (r01 + r10) / s, 0.25 * s, (r12 + r21) / s
	else
		local s = math.sqrt(1 + r22 - r00 - r11) * 2
		w, x, y, z = (r10 - r01) / s, (r02 + r20) / s, (r12 + r21) / s, 0.25 * s
	end
	return { w, x, y, z }
end

local function catmull(p0, p1, p2, p3, t)
	local t2, t3 = t * t, t * t * t
	-- (scalars on the right so it works for numbers and Vector3s alike)
	return (p1 * 2 + (p2 - p0) * t + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 + (p1 * 3 - p0 - p2 * 3 + p3) * t3) * 0.5
end

-- Smooth curve through a list of CFrames (Catmull-Rom on position and on
-- the rotation's quaternion), at u = 0..1 between key i and key i + 1.
local function splineCF(cfs, i, u)
	local n = #cfs
	local a, b, c, d = cfs[math.max(i - 1, 1)], cfs[i], cfs[math.min(i + 1, n)], cfs[math.min(i + 2, n)]
	local pos = catmull(a.Position, b.Position, c.Position, d.Position, u)
	local q = { toQuat(a), toQuat(b), toQuat(c), toQuat(d) }
	for k = 2, 4 do -- keep every quaternion on the same side as the one before
		local dot = 0
		for j = 1, 4 do
			dot += q[k][j] * q[k - 1][j]
		end
		if dot < 0 then
			for j = 1, 4 do
				q[k][j] = -q[k][j]
			end
		end
	end
	local out, len = {}, 0
	for j = 1, 4 do
		out[j] = catmull(q[1][j], q[2][j], q[3][j], q[4][j], u)
		len += out[j] * out[j]
	end
	len = math.sqrt(len)
	if len < 1e-6 then
		return b:Lerp(c, u)
	end
	return CFrame.new(pos.X, pos.Y, pos.Z, out[2] / len, out[3] / len, out[4] / len, out[1] / len)
end

local BODY_KEYS = { "Yaw", "Pitch", "Roll", "Lean", "Dip", "Forward", "Step", "NeckYaw", "NeckPitch" }

-- Plays a clip: keys = { { T, Weapon = CFrame | "BASE", Left = CFrame?, Body = {...}, Ease? } }
-- Returns weaponCF, leftCF (or nil), body table.
local function playClip(clip, u, base, baseLeft)
	local keys = clip.Keys
	local n = #keys
	local i = 1
	while i < n - 1 and u > keys[i + 1].T do
		i += 1
	end
	local k1, k2 = keys[i], keys[i + 1]
	local x = clamp01((u - k1.T) / math.max(k2.T - k1.T, 1e-4))
	if k2.Ease == "Snap" then
		x = 1 - (1 - x) ^ 2.6 -- fast start, soft landing (strikes)
	elseif k2.Ease == "Wind" then
		x = x * x * (2 - x) * 0.5 + x * 0.5
	end
	local weapons, lefts = {}, {}
	for k, key in ipairs(keys) do
		weapons[k] = key.Weapon == "BASE" and base or key.Weapon
		lefts[k] = key.Left or baseLeft
	end
	local weapon = splineCF(weapons, i, x)
	local left = splineCF(lefts, i, x)
	local body = {}
	for _, name in ipairs(BODY_KEYS) do
		local function at(k)
			local key = keys[math.clamp(k, 1, n)]
			return key.Body and key.Body[name] or 0
		end
		body[name] = catmull(at(i - 1), at(i), at(i + 1), at(i + 2), x)
	end
	return weapon, left, body
end

----------------------------------------------------------------------------
-- RIFLE (gun space: origin = right hand on the grip, -Z = the barrel)
----------------------------------------------------------------------------
local G = B.GunScale
local RIFLE_HIP = CFrame.new(B.RifleHip)
local RIFLE_SPRINT = RIFLE_HIP * CFrame.new(-0.12, -0.22, 0.2) * CFrame.Angles(rad(-18), rad(40), rad(16))
local RIFLE_EQUIP = RIFLE_HIP * CFrame.new(0.15, -1.1, 0.4) * CFrame.Angles(rad(-55), rad(25), rad(20))
-- the pistol grip goes through the fist; the forearm comes from behind it
local RIGHT_ON_GRIP = CFrame.new(0, -0.18 * G, 0.12 * G) * CFrame.Angles(rad(70), 0, 0)
local LEFT_GUARD_KNIFE = aim(V(-0.75, -1.15, -0.95), V(0.35, 0.55, -0.75), V(0.2, -0.2, 0.9))

local function rifleLeft(profile)
	-- (R15 arms are short for their shoulder width, so the left hand holds
	-- just ahead of the trigger guard, where it can actually reach)
	return CFrame.new(0, profile.LeftHold.Position.Y * G - 0.04, B.RifleLeftHold) * CFrame.Angles(0, 0, rad(95))
end

-- bolt cycle: reach (0-.15) lift (.15-.3) pull (.3-.5) push (.5-.68) lower (.68-.8) back (.8-1)
local function boltState(profile, t)
	local lift = smoothstep(seg(t, 0.15, 0.3)) - smoothstep(seg(t, 0.68, 0.8))
	local pull = smoothstep(seg(t, 0.3, 0.5)) - smoothstep(seg(t, 0.5, 0.68))
	local bolt = CFrame.new(0, 0, pull * profile.BoltTravel * G) * CFrame.Angles(0, 0, rad(profile.BoltLift) * lift)
	local pivot = CFrame.new(profile.BoltPivot.Position * G) * bolt
	local knob = pivot * CFrame.new(profile.KnobHold.Position * G) * CFrame.Angles(rad(60), 0, rad(-25))
	local reach = smoothstep(seg(t, 0, 0.15))
	local back = smoothstep(seg(t, 0.8, 1))
	local hand
	if t <= 0 or t >= 1 then
		hand = RIGHT_ON_GRIP
	elseif t < 0.15 then
		hand = RIGHT_ON_GRIP:Lerp(knob, reach)
	elseif t < 0.8 then
		hand = knob
	else
		hand = knob:Lerp(RIGHT_ON_GRIP, back)
	end
	local roll = math.sin(clamp01(t) * math.pi) * rad(18)
	return bolt, hand, roll
end

-- Rifle inspects (V): 1 show it off, 2 scope check, 3 chamber check.
local RIFLE_INSPECT_TIME = 2.4
WeaponAnim.RifleInspects = 3

local function rifle(state, t, ctx)
	local profile = ctx.Profile
	local base = RIFLE_HIP:Lerp(RIFLE_SPRINT, ctx.Sprint or 0)
	-- equip: swings up into view
	local e = clamp01((t - state.EquipStart) / (Config.Viewmodel.EquipTime or 0.35))
	local pose = RIFLE_EQUIP:Lerp(base, easeOutBack(e))
	-- recoil: a sharp kick up and back that settles
	local f = t - state.FireStart
	if f >= 0 and f < 0.6 then
		local kick = math.exp(-f * 11) * (1 - math.exp(-f * 90))
		pose = pose * CFrame.new(0, 0.03 * kick, 0.28 * kick) * CFrame.Angles(rad(12) * kick, 0, rad(3) * kick)
	end
	-- inspect (V): one of RIFLE_INSPECTS
	local body = { Yaw = -8, Pitch = 0 }
	local bolt, hand, roll = CFrame.new(), RIGHT_ON_GRIP, 0
	local left = rifleLeft(profile)
	local it = (t - state.InspectStart) / RIFLE_INSPECT_TIME
	if it >= 0 and it < 1 and state.InspectKind == "Rifle" then
		local w = math.sin(it * math.pi) ^ 0.7
		local variant = state.InspectVariant or 1
		if variant == 2 then
			-- scope check: tip it toward you, tap the scope twice
			pose = pose * CFrame.new(-0.25 * w, 0.22 * w, 0.25 * w) * CFrame.Angles(rad(8) * w, rad(32) * w, rad(-38) * w)
			local eye = profile.ScopeEye * G
			local tap = CFrame.new(0.02, eye.Y + 0.11 + math.max(0, math.sin(seg(it, 0.4, 0.7) * math.pi * 4)) * 0.05, eye.Z - 0.55)
				* CFrame.Angles(0, 0, rad(90))
			left = left:Lerp(tap, smoothstep(seg(it, 0.25, 0.38)) - smoothstep(seg(it, 0.72, 0.86)))
			body.NeckPitch = -6 * w
			body.NeckYaw = 8 * w
		elseif variant == 3 then
			-- chamber check: lift the bolt, ease it half open, look in, close it
			pose = pose * CFrame.new(-0.12 * w, 0.12 * w, 0.1 * w) * CFrame.Angles(rad(6) * w, rad(10) * w, rad(-24) * w)
			local lift = smoothstep(seg(it, 0.15, 0.28)) - smoothstep(seg(it, 0.74, 0.84))
			local pull = (smoothstep(seg(it, 0.28, 0.42)) - smoothstep(seg(it, 0.62, 0.74))) * 0.55
			bolt = CFrame.new(0, 0, pull * profile.BoltTravel * G) * CFrame.Angles(0, 0, rad(profile.BoltLift) * lift)
			local knob = CFrame.new(profile.BoltPivot.Position * G) * bolt * CFrame.new(profile.KnobHold.Position * G)
				* CFrame.Angles(rad(60), 0, rad(-25))
			hand = RIGHT_ON_GRIP:Lerp(knob, smoothstep(seg(it, 0.04, 0.15)) - smoothstep(seg(it, 0.84, 0.96)))
			body.NeckPitch = -8 * w
			body.NeckYaw = 10 * w
		else
			-- show it off: turn it to show both sides
			local turn = math.sin(it * math.pi * 2)
			pose = pose * CFrame.new(-0.35 * w, 0.2 * w, 0.3 * w) * CFrame.Angles(rad(12) * w, rad(60) * turn * w, rad(-30) * w)
			body.NeckPitch = -8 * w
		end
	end
	-- bolt
	local bt = state.BoltLength > 0 and (t - state.BoltStart) / state.BoltLength or 1
	if bt >= 0 and bt < 1 then
		bolt, hand, roll = boltState(profile, bt)
		pose = pose * CFrame.Angles(0, 0, -roll)
	end
	-- scope: bring the scope up to your eye
	local scope = ctx.Scope or 0
	if scope > 0 then
		local eye = profile.ScopeEye * G
		local ads = CFrame.new(-eye.X, -eye.Y, -eye.Z - 0.35)
		pose = pose:Lerp(ads, smoothstep(scope))
	end
	if f >= 0 and f < 0.25 then
		body.Pitch = 3 * math.exp(-f * 12)
	end
	return {
		Weapon = pose,
		Right = pose * hand,
		Left = pose * left,
		Body = body,
		Bolt = bolt,
	}
end

----------------------------------------------------------------------------
-- KNIFE (knife space: origin = middle of the handle, blade -Z, edge -Y)
----------------------------------------------------------------------------
local KS = KN.WorldScale
local KNIFE_IDLE = aim(V(0.5, -0.88, -1.05), V(-0.35, 0.5, -0.8), V(-0.35, -0.8, 0.3))
local KNIFE_SPRINT = aim(V(0.6, -1.15, -0.8), V(-0.2, -0.1, -1), V(0, -1, 0.1))
-- the fist closes round the handle, the thumb on the spine side; the
-- forearm runs back from the pommel, angled a little toward the edge (like
-- a real wrist), so turning the knife never twists the arm round
local HAND_ON_KNIFE = CFrame.new(KnifeModel.Grip.Position * KS) * CFrame.Angles(rad(125), 0, 0)

-- left hand: up in a guard, fist loose
local GUARD = LEFT_GUARD_KNIFE
local GUARD_OUT = aim(V(-1.0, -0.95, -0.85), V(0.2, 0.6, -0.8), V(0.3, -0.2, 0.9))
local GUARD_BACK = aim(V(-0.6, -1.25, -0.5), V(0.4, 0.4, -0.8), V(0.2, -0.3, 0.9))

local CLIPS = {}

-- Draw: up from the hip, a full flip in the air, caught into the grip.
CLIPS.Equip = {
	Length = 0.75,
	Toss = { From = 0.2, To = 0.52, Height = 0.55, Spins = -1, Catch = 3 },
	Keys = {
		{ T = 0, Weapon = aim(V(0.75, -1.7, -0.45), V(0, -1, 0.3), V(-1, 0, 0)), Left = GUARD_BACK },
		{ T = 0.2, Weapon = aim(V(0.55, -0.85, -1.05), V(-0.1, 0.25, -1), V(0, -1, 0)), Body = { Yaw = 8, NeckPitch = -6 } },
		{ T = 0.52, Weapon = aim(V(0.5, -0.62, -1.2), V(-0.3, 0.5, -0.8), V(-0.3, -0.8, 0.3)), Body = { Yaw = 4, NeckPitch = -4 } },
		{ T = 0.75, Weapon = "BASE" },
	},
}

-- Slash, forehand: a short cock back to the right shoulder, then one fast,
-- clean diagonal swipe across in front of you (edge first), a follow
-- through low on the left and straight back to the guard.
CLIPS.SlashA = {
	Length = KN.SlashTime,
	Keys = {
		{ T = 0, Weapon = "BASE" },
		{ T = 0.18, Weapon = aim(V(0.85, -0.3, -0.9), V(0.45, 0.6, -0.65), V(-0.9, 0.1, -0.1)), Left = GUARD_OUT, Ease = "Wind",
			Body = { Yaw = 12, Roll = -3 } },
		{ T = 0.34, Weapon = aim(V(0.1, -0.45, -1.35), V(-0.85, 0.15, -0.55), V(-0.5, -0.8, 0.2)), Ease = "Snap",
			Body = { Yaw = -6, Lean = 4, Dip = 0.05 } },
		{ T = 0.48, Weapon = aim(V(-0.75, -0.8, -1.05), V(-0.92, -0.25, -0.3), V(-0.3, -0.95, 0.1)), Left = GUARD_BACK,
			Body = { Yaw = -16, Roll = 3, Lean = 6, Dip = 0.08 } },
		{ T = 0.64, Weapon = aim(V(-0.8, -0.88, -0.95), V(-0.88, -0.3, -0.35), V(-0.3, -0.95, 0.15)),
			Body = { Yaw = -17, Roll = 3, Lean = 5, Dip = 0.07 } },
		{ T = 1, Weapon = "BASE" },
	},
}

-- Slash, backhand: the same swipe the other way, from the left of your
-- chest out to the right.
CLIPS.SlashB = {
	Length = KN.SlashTime,
	Keys = {
		{ T = 0, Weapon = "BASE" },
		{ T = 0.18, Weapon = aim(V(-0.3, -0.35, -0.95), V(-0.55, 0.55, -0.6), V(0.9, 0.1, -0.1)), Left = GUARD_BACK, Ease = "Wind",
			Body = { Yaw = -12, Roll = 3 } },
		{ T = 0.34, Weapon = aim(V(0.4, -0.45, -1.35), V(0.85, 0.15, -0.55), V(0.5, -0.8, 0.2)), Ease = "Snap",
			Body = { Yaw = 6, Lean = 4, Dip = 0.05 } },
		{ T = 0.48, Weapon = aim(V(1.15, -0.8, -1.0), V(0.92, -0.25, -0.3), V(0.3, -0.95, 0.1)), Left = GUARD_OUT,
			Body = { Yaw = 15, Roll = -3, Lean = 5, Dip = 0.07 } },
		{ T = 0.64, Weapon = aim(V(1.2, -0.88, -0.9), V(0.88, -0.3, -0.35), V(0.3, -0.95, 0.15)),
			Body = { Yaw = 16, Roll = -3, Lean = 4, Dip = 0.06 } },
		{ T = 1, Weapon = "BASE" },
	},
}

-- Stab: draw it back by the shoulder, lunge and drive it straight in,
-- twist, rip it out, recover.
CLIPS.Stab = {
	Length = KN.StabTime,
	Keys = {
		{ T = 0, Weapon = "BASE" },
		{ T = 0.24, Weapon = aim(V(0.95, -0.6, -0.9), V(-0.05, 0.3, -1), V(0, -1, 0)), Left = GUARD_OUT, Ease = "Wind",
			Body = { Yaw = 22, Lean = -8, Dip = 0.05 } },
		{ T = 0.37, Weapon = aim(V(0.12, -0.25, -2.25), V(-0.12, 0.04, -1), V(0, -1, 0)), Left = GUARD_BACK, Ease = "Snap",
			Body = { Yaw = -14, Lean = 22, Dip = 0.5, Forward = 0.6, Step = 1 } },
		{ T = 0.5, Weapon = aim(V(0.14, -0.28, -2.2), V(-0.12, 0.04, -1), V(-1, -0.4, 0)),
			Body = { Yaw = -16, Lean = 22, Dip = 0.5, Forward = 0.6, Step = 1 } },
		{ T = 0.64, Weapon = aim(V(0.45, -0.4, -1.4), V(-0.2, 0.25, -1), V(-0.4, -1, 0)),
			Body = { Yaw = -6, Lean = 10, Dip = 0.25, Forward = 0.3, Step = 0.5 } },
		{ T = 1, Weapon = "BASE" },
	},
}

-- Inspect: just handling it. Bring it up and look along the flat, tip it
-- up to check the edge, a little toss (the knife turns over once in the
-- air, not your wrist), catch, and back down. Every turn of the hand stays
-- within what a real wrist does.
local SHOW = aim(V(0.25, -0.45, -1.15), V(-1, 0.25, -0.3), V(0, -1, 0.15))
local SHOW_TILT = aim(V(0.22, -0.4, -1.12), V(-1, 0.35, -0.2), V(0, -0.85, 0.5))
local SHOW_EDGE = aim(V(0.32, -0.42, -1.15), V(-0.2, 1, -0.2), V(-0.45, 0, 0.9))
local TOSS_HOLD = aim(V(0.35, -0.6, -1.2), V(-0.1, 1, -0.25), V(-1, 0, 0.3))
CLIPS.Inspect = {
	Length = 2.6,
	Toss = { From = 0.42, To = 0.6, Height = 0.9, Spins = -1, Catch = 7 },
	Keys = {
		{ T = 0, Weapon = "BASE" },
		{ T = 0.12, Weapon = SHOW, Body = { NeckPitch = -10, NeckYaw = 6 } },
		{ T = 0.22, Weapon = SHOW_TILT, Body = { NeckPitch = -11, NeckYaw = 8 } },
		{ T = 0.32, Weapon = SHOW_EDGE, Body = { NeckPitch = -8, NeckYaw = 4 } },
		{ T = 0.38, Weapon = TOSS_HOLD * CFrame.new(0, -0.12, 0), Body = { NeckPitch = -4 } },
		{ T = 0.42, Weapon = TOSS_HOLD, Body = { NeckPitch = 4 } },
		{ T = 0.6, Weapon = TOSS_HOLD, Body = { NeckPitch = 6 } },
		{ T = 0.67, Weapon = TOSS_HOLD * CFrame.new(0, -0.14, 0), Body = { NeckPitch = -2, Dip = 0.05 } },
		{ T = 0.84, Weapon = KNIFE_IDLE * CFrame.Angles(rad(-18), 0, 0) },
		{ T = 1, Weapon = "BASE" },
	},
}

-- The knife airborne between Toss.From and Toss.To (key index Toss.Catch
-- is where it's caught): rises and falls, spinning end over end.
local function tossPose(clip, u, launch, catch)
	local toss = clip.Toss
	local f = seg(u, toss.From, toss.To)
	local pos = launch.Position:Lerp(catch.Position, f) + V(0, 4 * toss.Height * f * (1 - f), 0)
	local rot = launch.Rotation:Lerp(catch.Rotation, f) * CFrame.Angles(toss.Spins * math.pi * 2 * smoothstep(f), 0, 0)
	return CFrame.new(pos) * rot
end

local function knife(state, t, ctx)
	local base = KNIFE_IDLE:Lerp(KNIFE_SPRINT, ctx.Sprint or 0)
		* CFrame.new(0, math.sin(t * 1.6) * 0.012, 0)
		* CFrame.Angles(rad(math.sin(t * 1.1) * 1.5), 0, rad(math.sin(t * 0.8) * 1.2))
	local action = state.Action
	local clip = action and CLIPS[action.Clip]
	local weapon, left, body = base, GUARD, {}
	local right
	if clip then
		local u = (t - action.Start) / clip.Length
		if u >= 1 then
			state.Action = nil
		else
			weapon, left, body = playClip(clip, u, base, GUARD)
			local toss = clip.Toss
			if toss and u > toss.From and u < toss.To then
				-- in the air: the hand waits at the catch point
				local launchKey, catchKey
				for _, key in ipairs(clip.Keys) do
					if math.abs(key.T - toss.From) < 1e-6 then
						launchKey = key
					end
				end
				catchKey = clip.Keys[toss.Catch]
				local launch = launchKey and launchKey.Weapon ~= "BASE" and launchKey.Weapon or base
				local catch = catchKey.Weapon ~= "BASE" and catchKey.Weapon or base
				right = catch * HAND_ON_KNIFE * CFrame.new(0, -0.06 * math.sin(seg(u, toss.From, toss.To) * math.pi), 0)
				weapon = tossPose(clip, u, launch, catch)
			end
		end
	end
	-- the knife is held a little higher with the weapon out of a sprint
	return {
		Weapon = weapon,
		Right = right or weapon * HAND_ON_KNIFE,
		Left = left,
		Body = body,
	}
end

----------------------------------------------------------------------------
-- VICTORY: the round winner's pose at the end of the kill cam. The rifle
-- swings up onto the shoulder (or the knife comes up blade-high) and the
-- free hand punches the air.
----------------------------------------------------------------------------
local VICTORY_RIFLE = aim(V(1.0, -0.95, 0.05), V(0.22, 1, 0.3), V(0.2, -0.3, -1))
local VICTORY_KNIFE = aim(V(1.15, -0.55, -0.55), V(0.35, 1, -0.2), V(-1, 0, 0.1))
local FIST_UP = CFrame.new(-1.2, 2.1, 0.15) * CFrame.Angles(0, 0, math.pi) * CFrame.Angles(0, rad(90), 0)

local function victory(anim, state, t)
	local v = t - state.VictoryStart
	if v < 0 or v > 6 then
		return anim
	end
	local w = easeOutBack(seg(v, 0, 0.45))
	local pump = easeOutBack(seg(v, 0.25, 0.6)) - 0.12 * math.sin(seg(v, 0.6, 1.4) * math.pi * 2)
	local knifeOut = state.Weapon == "Knife"
	local weapon = anim.Weapon:Lerp(knifeOut and VICTORY_KNIFE or VICTORY_RIFLE, w)
	return {
		Weapon = weapon,
		Right = weapon * (knifeOut and HAND_ON_KNIFE or RIGHT_ON_GRIP),
		Left = anim.Left:Lerp(FIST_UP, pump),
		Body = { Yaw = 12 * w, Lean = -7 * w, NeckPitch = -10 * w, NeckYaw = -8 * w },
		Bolt = CFrame.new(),
	}
end

----------------------------------------------------------------------------
-- State + public API
----------------------------------------------------------------------------
function WeaponAnim.New()
	return {
		Weapon = "Sniper",
		EquipStart = -10,
		FireStart = -10,
		BoltStart = -10,
		BoltLength = 0,
		InspectStart = -10,
		InspectKind = nil,
		InspectVariant = nil, -- which rifle inspect (1-3)
		VictoryStart = -10,
		Action = nil, -- knife clip { Clip, Start }
		SwingSide = 1,
	}
end

function WeaponAnim.SetWeapon(state, weapon, t)
	if weapon ~= "Knife" then
		weapon = "Sniper"
	end
	if state.Weapon == weapon then
		return false
	end
	state.Weapon = weapon
	state.EquipStart = t
	state.InspectStart = -10
	state.Action = weapon == "Knife" and { Clip = "Equip", Start = t } or nil
	return true
end

function WeaponAnim.Fire(state, t)
	state.FireStart = t
	state.InspectStart = -10
end

function WeaponAnim.Bolt(state, t, length)
	state.BoltStart = t
	state.BoltLength = length
end

-- kind: "Slash" (alternates forehand / backhand) or "Stab"; side forces a slash direction
function WeaponAnim.Knife(state, kind, t, side)
	if kind == "Slash" then
		state.SwingSide = side or -state.SwingSide
		state.Action = { Clip = state.SwingSide > 0 and "SlashA" or "SlashB", Start = t }
	elseif kind == "Stab" then
		state.Action = { Clip = "Stab", Start = t }
	end
end

-- Returns false if something else is playing. variant: which rifle inspect
-- (1-3); nil picks one at random (never the same twice in a row).
-- Returns true and the variant played.
function WeaponAnim.Inspect(state, t, variant)
	if state.Weapon == "Knife" then
		if state.Action then
			return false
		end
		state.Action = { Clip = "Inspect", Start = t }
	else
		if t - state.InspectStart < RIFLE_INSPECT_TIME or t - state.BoltStart < state.BoltLength then
			return false
		end
		if not variant and state.InspectVariant then
			variant = math.random(1, WeaponAnim.RifleInspects - 1)
			if variant >= state.InspectVariant then
				variant += 1 -- (skip the one you just did)
			end
		end
		variant = variant or math.random(1, WeaponAnim.RifleInspects)
		state.InspectStart = t
		state.InspectKind = "Rifle"
		state.InspectVariant = math.clamp(math.floor(variant), 1, WeaponAnim.RifleInspects)
	end
	return true, state.InspectVariant
end

-- The victory pose (holds until the state is reset).
function WeaponAnim.Victory(state, t)
	state.VictoryStart = t
	state.Action = nil
	state.BoltLength = 0
end

function WeaponAnim.IsBusy(state, t)
	return state.Action ~= nil or t - state.BoltStart < state.BoltLength
end

-- ctx: { Sprint = 0..1, Scope = 0..1, Profile = gun profile }
function WeaponAnim.Evaluate(state, t, ctx)
	local anim = state.Weapon == "Knife" and knife(state, t, ctx) or rifle(state, t, ctx)
	return victory(anim, state, t)
end

-- (for previews / tests)
WeaponAnim.Clips = CLIPS
WeaponAnim.KnifeIdle = KNIFE_IDLE

return WeaponAnim
