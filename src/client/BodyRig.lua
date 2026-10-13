--[[
	BodyRig.lua  (Client.BodyRig)

	Bends a real R15 character (the one you spawn in) to hold a weapon: the
	maths only, no RunService, so it also runs in previews.

		local rig = BodyRig.Find(character)        -- nil if it isn't R15
		BodyRig.Solve(rig, view, anim, weights)    -- sets every Motor6D.Transform

	view   = where the eyes are and where they look (CFrame)
	anim   = WeaponAnim.Evaluate output (view-space weapon + hands + body)

	How it works:
	  1. Hips + waist + neck: twist / lean / dip from anim.Body, plus the aim
	     pitch shared between waist and neck.
	  2. Both arms: two-bone IK from the real shoulder to the hand target
	     (elbows bend out and down), then the wrist turns the hand to match.
	     Bone lengths come from the character's own joints, so any R15
	     avatar works.
	  3. The weapon is jointed to the right hand (Motor6D "WeaponGrip" made
	     by the server); its Transform puts it exactly where the animation
	     says, wherever the hand ended up.
	  4. Legs: only during a lunge (anim.Body.Step), blended over the walk.

	Motor6D maths: Part1 = Part0 * C0 * Transform * C1:Inverse().
]]

local BodyRig = {}

local V = Vector3.new
local rad = math.rad

local MOTORS = {
	Root = "LowerTorso",
	Waist = "UpperTorso",
	Neck = "Head",
	RightShoulder = "RightUpperArm",
	RightElbow = "RightLowerArm",
	RightWrist = "RightHand",
	LeftShoulder = "LeftUpperArm",
	LeftElbow = "LeftLowerArm",
	LeftWrist = "LeftHand",
	RightHip = "RightUpperLeg",
	RightKnee = "RightLowerLeg",
	LeftHip = "LeftUpperLeg",
	LeftKnee = "LeftLowerLeg",
}

-- The rig's joints, or nil if this isn't an R15 character.
function BodyRig.Find(character)
	local motors = {}
	for motorName, partName in pairs(MOTORS) do
		local part = character:FindFirstChild(partName)
		local motor = part and part:FindFirstChild(motorName)
		if not (motor and motor:IsA("Motor6D")) then
			return nil
		end
		motors[motorName] = motor
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local rig = { Character = character, Root = root, Motors = motors, Base = {}, Set = {} }
	local function length(a, b)
		return (a.C1.Position - b.C0.Position).Magnitude -- joint to joint inside one part
	end
	rig.Upper = length(motors.RightShoulder, motors.RightElbow)
	rig.Lower = length(motors.RightElbow, motors.RightWrist)
	rig.LeftUpper = length(motors.LeftShoulder, motors.LeftElbow)
	rig.LeftLower = length(motors.LeftElbow, motors.LeftWrist)
	return rig
end

-- The current weapon joint on the right hand (made by CharacterService).
function BodyRig.FindWeapon(rig, name)
	local model = rig.Character:FindFirstChild(name)
	local root = model and model:FindFirstChild("WeaponRoot")
	if not root then
		return nil
	end
	local grip = root:FindFirstChild("WeaponGrip")
	if not grip or not grip:IsA("Motor6D") then
		return nil
	end
	return {
		Model = model,
		Root = root,
		Grip = grip,
		GripToRoot = root:GetAttribute("GripToRoot") or CFrame.new(),
		Bolt = root:FindFirstChild("BoltJoint"),
	}
end

-- An orthonormal frame whose Y is `along` and whose X is as close to `x` as possible.
local function frame(along, x)
	local y = along.Unit
	local xx = x - y * x:Dot(y)
	if xx.Magnitude < 1e-4 then
		xx = math.abs(y.X) < 0.9 and V(1, 0, 0) or V(0, 0, 1)
		xx = xx - y * xx:Dot(y)
	end
	xx = xx.Unit
	return CFrame.fromMatrix(Vector3.zero, xx, y, xx:Cross(y))
end

-- Child part CFrame -> the motor Transform that puts it there.
local function place(motor, parentCF, childCF)
	motor.Transform = (parentCF * motor.C0):Inverse() * childCF * motor.C1
end
BodyRig.Place = place

-- World CFrame of a motor's Part1 given its Part0 CFrame and its Transform.
local function child(motor, parentCF, transform)
	return parentCF * motor.C0 * (transform or motor.Transform) * motor.C1:Inverse()
end
BodyRig.Child = child

--[[
	Two-bone IK for one arm. Returns the hand's world CFrame.
	torso: UpperTorso CFrame; target: where the hand should be (world);
	pole: which way the elbow should point (world direction).
]]
local function solveArm(torso, shoulder, elbow, wrist, upperLen, lowerLen, target, pole)
	local S = (torso * shoulder.C0).Position
	local W = (target * wrist.C1).Position -- where the wrist joint has to be
	local toW = W - S
	local d = math.clamp(toW.Magnitude, math.abs(upperLen - lowerLen) + 0.01, upperLen + lowerLen - 0.002)
	local dir = toW.Magnitude > 1e-4 and toW.Unit or V(0, -1, 0)
	local cosA = math.clamp((upperLen * upperLen + d * d - lowerLen * lowerLen) / (2 * upperLen * d), -1, 1)
	local sinA = math.sqrt(1 - cosA * cosA)
	local side = pole - dir * pole:Dot(dir)
	side = side.Magnitude > 1e-4 and side.Unit or V(0, -1, 0)
	local E = S + dir * upperLen * cosA + side * upperLen * sinA
	local Wr = E + (S + dir * d - E).Unit * lowerLen -- the wrist we can actually reach

	-- the elbow hinges round each arm part's X axis: positive bends the forearm forward
	local upperDir = (E - S).Unit
	local lowerDir = (Wr - E).Unit
	local hinge = upperDir:Cross(lowerDir)
	if hinge.Magnitude < 1e-3 then
		hinge = upperDir:Cross(pole)
	end
	hinge = hinge.Magnitude > 1e-4 and hinge.Unit or V(1, 0, 0)

	-- upper arm: its shoulder->elbow line along upperDir, X along the hinge
	local boneU = elbow.C0.Position - shoulder.C1.Position -- (upper arm space)
	local R1 = frame(-upperDir, hinge) * frame(-boneU, V(1, 0, 0)):Inverse()
	local upperCF = CFrame.new(S) * R1 * CFrame.new(-shoulder.C1.Position)
	place(shoulder, torso, upperCF)

	-- lower arm
	local Ea = (upperCF * elbow.C0).Position
	local boneL = wrist.C0.Position - elbow.C1.Position
	local R2 = frame(-lowerDir, hinge) * frame(-boneL, V(1, 0, 0)):Inverse()
	local lowerCF = CFrame.new(Ea) * R2 * CFrame.new(-elbow.C1.Position)
	place(elbow, upperCF, lowerCF)

	-- hand: the target's rotation, hung from the wrist we reached
	local Wa = (lowerCF * wrist.C0).Position
	local handCF = CFrame.new(Wa) * target.Rotation * CFrame.new(-wrist.C1.Position)
	place(wrist, lowerCF, handCF)
	return handCF
end

-- What the walk / idle animation wants for a joint this frame. (If nothing
-- animated it since we last wrote it, that's still our own value, so use the
-- base we saved instead of stacking on top of ourselves.)
local function base(rig, name)
	local motor = rig.Motors[name]
	if rig.Set[name] and motor.Transform == rig.Set[name] then
		return rig.Base[name]
	end
	rig.Base[name] = motor.Transform
	return motor.Transform
end

local function set(rig, name, transform)
	rig.Motors[name].Transform = transform
	rig.Set[name] = transform
end

--[[
	view: eye CFrame (world); anim: WeaponAnim output; opts:
	  Pitch       aim pitch (radians) shared out to the waist and neck
	  Weapon      BodyRig.FindWeapon result for the weapon in hand (or nil)
	  LegWeight   0..1 how much the lunge pose replaces the walk (default anim.Body.Step)
	Returns { RightHand = CFrame, LeftHand = CFrame, Weapon = CFrame }
]]
function BodyRig.Solve(rig, view, anim, opts)
	opts = opts or {}
	local m = rig.Motors
	local body = anim.Body or {}
	local pitch = opts.Pitch or 0
	local rootCF = rig.Root.CFrame

	-- hips: dip, push forward, lean (on top of the walk animation)
	local step = math.clamp(body.Step or 0, 0, 1)
	local rootT = base(rig, "Root")
		* CFrame.new(0, -(body.Dip or 0), -(body.Forward or 0))
		* CFrame.Angles(-rad(body.Lean or 0) * 0.5, 0, 0)
	set(rig, "Root", rootT)
	local lower = child(m.Root, rootCF, rootT)

	-- waist: twist (+Yaw = turn right), lean forward, and part of the aim pitch
	local waistT = CFrame.Angles(pitch * 0.35 - rad(body.Lean or 0) * 0.5 + rad(body.Pitch or 0), -rad(body.Yaw or 0), rad(body.Roll or 0))
	m.Waist.Transform = waistT
	local torso = child(m.Waist, lower, waistT)

	-- neck: the rest of the pitch, turned back against the waist twist
	local neckT = CFrame.Angles(pitch * 0.45 + rad(body.NeckPitch or 0), rad(body.Yaw or 0) * 0.7 + rad(body.NeckYaw or 0), -rad(body.Roll or 0) * 0.7)
	m.Neck.Transform = neckT

	-- arms
	local rightTarget = view * anim.Right
	local leftTarget = view * anim.Left
	local down = -view.UpVector
	local rightPole = (view.RightVector * 0.7 + down - view.LookVector * 0.15).Unit
	local leftPole = (-view.RightVector * 0.7 + down - view.LookVector * 0.15).Unit
	local rightHand = solveArm(torso, m.RightShoulder, m.RightElbow, m.RightWrist, rig.Upper, rig.Lower, rightTarget, rightPole)
	local leftHand = solveArm(torso, m.LeftShoulder, m.LeftElbow, m.LeftWrist, rig.LeftUpper, rig.LeftLower, leftTarget, leftPole)

	-- the weapon, exactly where the animation wants it
	local weaponCF = view * anim.Weapon
	local weapon = opts.Weapon
	if weapon then
		local rootCFW = weaponCF * weapon.GripToRoot
		weapon.Grip.Transform = (rightHand * weapon.Grip.C0):Inverse() * rootCFW * weapon.Grip.C1
		if weapon.Bolt then
			weapon.Bolt.Transform = anim.Bolt or CFrame.new()
		end
	end

	-- legs: step into a lunge (front leg forward and bent, back leg trailing)
	local legs = {
		RightHip = CFrame.Angles(rad(38), 0, 0),
		RightKnee = CFrame.Angles(rad(-40), 0, 0),
		LeftHip = CFrame.Angles(rad(-28), 0, 0),
		LeftKnee = CFrame.Angles(rad(-25), 0, 0),
	}
	for name, pose in pairs(legs) do
		if step > 0.01 then
			set(rig, name, base(rig, name):Lerp(pose, step * (opts.LegWeight or 1)))
		elseif rig.Set[name] then
			-- lunge over: hand the leg back to the walk animation
			m[name].Transform = base(rig, name)
			rig.Set[name] = nil
		end
	end

	return { RightHand = rightHand, LeftHand = leftHand, Weapon = weaponCF, Torso = torso, Lower = lower }
end

-- Every part's world CFrame from the root and the current Transforms
-- (for previews; Roblox does this itself in game).
function BodyRig.Pose(rig)
	local out = { HumanoidRootPart = rig.Root.CFrame }
	local m = rig.Motors
	local order = {
		{ "Root", "HumanoidRootPart", "LowerTorso" },
		{ "Waist", "LowerTorso", "UpperTorso" },
		{ "Neck", "UpperTorso", "Head" },
		{ "RightShoulder", "UpperTorso", "RightUpperArm" },
		{ "RightElbow", "RightUpperArm", "RightLowerArm" },
		{ "RightWrist", "RightLowerArm", "RightHand" },
		{ "LeftShoulder", "UpperTorso", "LeftUpperArm" },
		{ "LeftElbow", "LeftUpperArm", "LeftLowerArm" },
		{ "LeftWrist", "LeftLowerArm", "LeftHand" },
		{ "RightHip", "LowerTorso", "RightUpperLeg" },
		{ "RightKnee", "RightUpperLeg", "RightLowerLeg" },
		{ "LeftHip", "LowerTorso", "LeftUpperLeg" },
		{ "LeftKnee", "LeftUpperLeg", "LeftLowerLeg" },
	}
	for _, j in ipairs(order) do
		out[j[3]] = child(m[j[1]], out[j[2]])
	end
	return out
end

return BodyRig
