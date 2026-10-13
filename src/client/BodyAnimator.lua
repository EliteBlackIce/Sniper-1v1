--[[
	BodyAnimator.lua  (Client.BodyAnimator)

	Your real character holds and animates the weapons. No separate
	viewmodel: in first person you see your own forearms and hands (copied
	from nothing; they're your character's actual parts), and everyone else
	sees the same animation on your whole character.

	Every frame (RunService.Stepped, right after Roblox's walk / run
	animations) for every character near you:
	  1. work out where its eyes are and where it's looking
	       you            the camera (first person)
	       other players  their head + the "AimPitch" they send (smoothed)
	  2. WeaponAnim says where the weapon, the hands and the body go
	  3. BodyRig twists the torso, bends the real arms (IK) and puts the
	     weapon (jointed to the right hand) exactly in place
	Other players' shots, knife swings, inspects and weapon switches come in
	as character attributes (set by the server), so everyone plays the same
	moves at the same time.

	This module also keeps the old Controllers.Viewmodel API (PlayFire,
	PlayBolt, SetWeapon, PlayKnife, GetMuzzlePosition, SetHidden...).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local GunModel = require(Shared.GunModel)
local KnifeModel = require(Shared.KnifeModel)
local Remotes = require(Shared.Remotes)
local Util = require(Shared.Util)
local ClientState = require(script.Parent.ClientState)
local Spring = require(script.Parent.Spring)
local Sfx = require(script.Parent.Sfx)
local Keybinds = require(script.Parent.Keybinds)
local WeaponAnim = require(script.Parent.WeaponAnim)
local BodyRig = require(script.Parent.BodyRig)

local B = Config.Body
local VM = Config.Viewmodel
local player = Players.LocalPlayer
local rad = math.rad

local BodyAnimator = {}
local Controllers

local entries = setmetatable({}, { __mode = "k" }) -- [character] = entry
local extra = {} -- extra models to animate (the kill cam's copy of you)
local hiddenBy = {} -- [reason] = true: hide your first-person arms + weapon
local localState = WeaponAnim.New()
local puppet -- { Character, State } while the kill cam plays through someone's eyes

local swaySpring = Spring.new(140, 16)
local bobTime, sprintAlpha = 0, 0
local lastScoped = false

----------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------
local function now()
	return os.clock()
end

local function getEntry(model)
	local entry = entries[model]
	if entry then
		return entry
	end
	local rig = BodyRig.Find(model)
	if not rig then
		return nil
	end
	entry = { Rig = rig, State = WeaponAnim.New(), Pitch = 0, Seen = {}, Weapons = {} }
	entry.State.EquipStart = -10
	entries[model] = entry
	return entry
end

local function weaponFor(entry, name)
	local cached = entry.Weapons[name]
	if cached and cached.Model.Parent and cached.Root.Parent then
		return cached
	end
	cached = BodyRig.FindWeapon(entry.Rig, name)
	entry.Weapons[name] = cached
	return cached
end

local function profileFor(entry)
	local gun = weaponFor(entry, "WorldGun")
	local kind = gun and gun.Root:GetAttribute("Profile")
	return kind == "Mesh" and GunModel.MeshProfile or GunModel.PartsProfile
end

local function stateFor(model)
	if puppet and model == puppet.Character then
		return puppet.State
	end
	if model == player.Character then
		return localState
	end
	local entry = entries[model]
	return entry and entry.State
end

-- The state the API calls act on: the kill cam's puppet, or you.
local function activeState()
	return puppet and puppet.State or localState
end

-- Shots, swings, inspects and switches of OTHER characters, from attributes.
local function syncEvents(entry, model, t)
	local state = entry.State
	local seen = entry.Seen
	local weapon = model:GetAttribute("Weapon") or "Sniper"
	if seen.Weapon == nil then
		state.Weapon = weapon == "Knife" and "Knife" or "Sniper"
	elseif weapon ~= seen.Weapon then
		WeaponAnim.SetWeapon(state, weapon, t)
	end
	seen.Weapon = weapon

	local swing = model:GetAttribute("Swing")
	if seen.Swing ~= nil and swing ~= seen.Swing and state.Weapon == "Knife" then
		local kind = model:GetAttribute("SwingKind") or "Slash"
		WeaponAnim.Knife(state, kind, t, (swing or 0) % 2 == 0 and 1 or -1)
	end
	seen.Swing = swing

	local shot = model:GetAttribute("Shot")
	if seen.Shot ~= nil and shot ~= seen.Shot then
		WeaponAnim.Fire(state, t)
		local bolt = model:GetAttribute("BoltTime") or 1
		WeaponAnim.Bolt(state, t + 0.12, math.max(bolt - 0.12, 0.2))
	end
	seen.Shot = shot

	local inspect = model:GetAttribute("Inspect")
	if seen.Inspect ~= nil and inspect ~= seen.Inspect then
		WeaponAnim.Inspect(state, t)
	end
	seen.Inspect = inspect
end

-- Eyes looking the way a character's root faces, pitched by its aim.
local function headView(rig, pitch)
	local root = rig.Root.CFrame
	local look = root.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	return CFrame.new(root.Position + root.UpVector * 1.5) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
end

local function isAlive(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

----------------------------------------------------------------------------
-- Per frame: pose every character
----------------------------------------------------------------------------
local function animate(model, dt, t, camera)
	local entry = getEntry(model)
	if not entry then
		return
	end
	local rig = entry.Rig
	local isLocal = model == player.Character
	local isPuppet = puppet ~= nil and model == puppet.Character
	local state = stateFor(model)
	if not isLocal and not isPuppet then
		syncEvents(entry, model, t)
	end

	local view, pitch
	local ctx = { Profile = profileFor(entry) }
	local firstPerson = isLocal and Controllers.Camera.IsFirstPerson() and not puppet
	if firstPerson or isPuppet then
		local cam = camera.CFrame
		pitch = math.asin(math.clamp(cam.LookVector.Y, -1, 1))
		view = cam * CFrame.new(0, 0, -(B.CameraBack or 0)) -- the eyes, in front of the camera
		if firstPerson then
			-- face exactly where you look (before physics, so arms and camera agree)
			local root = rig.Root
			local look = Util.flat(cam.LookVector)
			if look.Magnitude > 0.05 then
				root.CFrame = CFrame.lookAt(root.Position, root.Position + look)
			end
			-- sway (lags behind the mouse) and walk bob
			local movement = Controllers.Movement
			local delta = UserInputService:GetMouseDelta()
			local scope = Controllers.Weapon.GetScopeAlpha()
			local swayScale = (1 - scope * 0.9) * VM.SwayAmount
			swaySpring.Target = Vector3.new(
				math.clamp(-delta.Y * swayScale, -5, 5),
				math.clamp(-delta.X * swayScale, -5, 5),
				math.clamp(-delta.X * swayScale * 0.7, -4, 4)
			)
			local sway = swaySpring:Update(dt)
			local speed = movement.GetSpeed()
			local running = movement.IsGrounded() and speed > 2 and movement.GetMode() == "Ground"
			if running then
				bobTime += dt * (7 + speed * 0.2)
			end
			local bob = running and math.clamp(speed / Config.Movement.RunSpeed, 0, 1.4) * (1 - scope) * VM.BobAmount or 0
			sprintAlpha = Util.lerp(sprintAlpha, movement.IsSprinting() and scope < 0.1 and 1 or 0, Util.smooth(10, dt))
			view = view
				* CFrame.new(math.sin(bobTime) * 0.05 * bob, math.sin(bobTime * 2) * 0.035 * bob, 0)
				* CFrame.Angles(rad(sway.X), rad(sway.Y), rad(sway.Z) + math.sin(bobTime) * rad(2) * bob)
			ctx.Sprint = sprintAlpha
			ctx.Scope = scope
		end
	else
		-- seen from outside: the aim they send, smoothed
		local target = model:GetAttribute("AimPitch") or 0
		entry.Pitch = Util.lerp(entry.Pitch, target, Util.smooth(B.PitchSmoothing, dt))
		pitch = entry.Pitch
		view = headView(rig, pitch) * B.ThirdPersonOffset
		local vel = rig.Root.AssemblyLinearVelocity
		local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
		entry.Sprint = Util.lerp(entry.Sprint or 0, speed > Config.Movement.RunSpeed * 1.08 and 1 or 0, Util.smooth(6, dt))
		ctx.Sprint = entry.Sprint
		ctx.Scope = model:GetAttribute("Scoped") and 1 or 0
	end

	local anim = WeaponAnim.Evaluate(state, t, ctx)
	local weapon = weaponFor(entry, state.Weapon == "Knife" and "WorldKnife" or "WorldGun")
	BodyRig.Solve(rig, view, anim, { Pitch = pitch, Weapon = weapon })
end

local function step(dt)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local t = now()
	local done = {}
	local function try(model)
		if not model or done[model] or not model.Parent then
			return
		end
		done[model] = true
		if not isAlive(model) and not extra[model] then
			return
		end
		local root = model:FindFirstChild("HumanoidRootPart")
		if not root or (root.Position - camera.CFrame.Position).Magnitude > B.MaxDistance then
			return
		end
		local ok, err = pcall(animate, model, dt, t, camera)
		if not ok then
			warn("[BodyAnimator]", err)
		end
	end
	for _, other in ipairs(Players:GetPlayers()) do
		try(other.Character)
	end
	local opponent = ClientState.Snapshot.InMatch and ClientState.GetOpponentPlayer()
	if typeof(opponent) == "table" then
		try(opponent.Character) -- a bot
	end
	for model in pairs(extra) do
		try(model)
	end
end

-- First person: show your own forearms, hands and weapon (Roblox hides your
-- whole character in first person); hide them while scoped or in menus.
local ARM_PARTS = { "RightLowerArm", "RightHand", "LeftLowerArm", "LeftHand" }
local UPPER_ARMS = { "RightUpperArm", "LeftUpperArm" }
local function showArms(model, shown)
	local value = shown and 0 or 1
	for _, name in ipairs(ARM_PARTS) do
		local part = model:FindFirstChild(name)
		if part then
			part.LocalTransparencyModifier = value
		end
	end
	if B.ShowUpperArms then
		for _, name in ipairs(UPPER_ARMS) do
			local part = model:FindFirstChild(name)
			if part then
				part.LocalTransparencyModifier = value
			end
		end
	end
	local state = stateFor(model)
	local weaponName = state and state.Weapon == "Knife" and "WorldKnife" or "WorldGun"
	for _, name in ipairs({ "WorldGun", "WorldKnife" }) do
		local weapon = model:FindFirstChild(name)
		for _, part in ipairs(weapon and weapon:GetDescendants() or {}) do
			if part:IsA("BasePart") then
				part.LocalTransparencyModifier = (shown and name == weaponName) and 0 or 1
			end
		end
	end
end

local function updateVisibility()
	local character = player.Character
	if puppet and puppet.Character and puppet.Character.Parent then
		showArms(puppet.Character, next(hiddenBy) == nil)
	end
	if not character then
		return
	end
	local firstPerson = Controllers.Camera.IsFirstPerson() and not puppet
	if firstPerson then
		local scope = Controllers.Weapon.GetScopeAlpha()
		local shown = isAlive(character) and next(hiddenBy) == nil and scope < 0.92 and ClientState.HasGun()
		showArms(character, shown)
	end
	-- tell everyone when you're aiming down the scope
	local scoped = Controllers.Weapon.GetScopeAlpha() > 0.5
	if scoped ~= lastScoped then
		lastScoped = scoped
		Remotes.Get("Anim"):FireServer("Scope", scoped)
	end
end

----------------------------------------------------------------------------
-- API (the old Viewmodel API, so everything else keeps working)
----------------------------------------------------------------------------
function BodyAnimator.SetHidden(reason, hidden)
	hiddenBy[reason] = hidden or nil
end

function BodyAnimator.PlayFire()
	WeaponAnim.Fire(activeState(), now())
end

function BodyAnimator.PlayBolt(duration)
	local delay = math.min(0.12, duration * 0.3)
	WeaponAnim.Bolt(activeState(), now() + delay, math.max(duration - delay, 0.15))
end

function BodyAnimator.PlayEquip()
	local state = activeState()
	if state.Weapon ~= "Knife" then
		state.EquipStart = now()
	end
end

function BodyAnimator.PlayKill() end

function BodyAnimator.SetWeapon(name)
	local state = activeState()
	if WeaponAnim.SetWeapon(state, name, now()) and not puppet then
		if state.Weapon == "Knife" then
			Sfx.Play("CardPick", { Pitch = 1.15, Volume = 0.7 }) -- unsheathe
			task.delay(0.15, Sfx.Play, "CardFlip", { Pitch = 1.3, Volume = 0.5 }) -- the flip
			task.delay(0.39, Sfx.Play, "Bolt", { Pitch = 1.6, Volume = 0.5 }) -- caught
		else
			Sfx.Play("Bolt", { Pitch = 1.3, Volume = 0.6 })
		end
	end
end

function BodyAnimator.GetWeapon()
	return activeState().Weapon
end

-- "Slash", "Stab" or "Inspect"
function BodyAnimator.PlayKnife(kind)
	local state = activeState()
	local t = now()
	if kind == "Inspect" then
		if WeaponAnim.Inspect(state, t) and not puppet then
			local length = WeaponAnim.Clips.Inspect.Length
			Sfx.Play("CardHover", { Pitch = 0.8, Volume = 1.2 })
			task.delay(length * 0.29, Sfx.Play, "CardFlip", { Pitch = 1.1, Volume = 0.8 })
			task.delay(length * 0.5, Sfx.Play, "Bolt", { Pitch = 1.5, Volume = 0.7 })
			task.delay(length * 0.62, Sfx.Play, "CardFlip", { Pitch = 1.5, Volume = 0.5 })
		end
		return
	end
	WeaponAnim.Knife(state, kind, t)
end

local function weaponRootOf(model, name)
	local weapon = model and model:FindFirstChild(name)
	return weapon and weapon:FindFirstChild("WeaponRoot")
end

function BodyAnimator.GetKnifeTip()
	local root = weaponRootOf(puppet and puppet.Character or player.Character, "WorldKnife")
	if root then
		return (root.CFrame * CFrame.new(KnifeModel.Tip * Config.Knife.WorldScale)).Position
	end
	return workspace.CurrentCamera.CFrame.Position
end

function BodyAnimator.GetMuzzlePosition()
	local model = puppet and puppet.Character or player.Character
	local gun = model and model:FindFirstChild("WorldGun")
	local barrel = gun and gun:FindFirstChild("Barrel")
	local muzzle = barrel and barrel:FindFirstChild("Muzzle")
	if muzzle then
		return muzzle.WorldPosition
	end
	return workspace.CurrentCamera.CFrame.Position
end

function BodyAnimator.GetLeftHandPosition()
	local hand = player.Character and player.Character:FindFirstChild("LeftHand")
	return hand and hand.Position or workspace.CurrentCamera.CFrame.Position
end

-- Kill cam: play through someone's eyes, their real arms in view.
-- info = { Character = Model, Owned = {...} } or nil to stop.
function BodyAnimator.SetPuppet(info)
	if puppet and puppet.Character and puppet.Character.Parent then
		showArms(puppet.Character, false)
	end
	if info and info.Character then
		local state = WeaponAnim.New()
		state.Weapon = info.Character:GetAttribute("Weapon") == "Knife" and "Knife" or "Sniper"
		puppet = { Character = info.Character, State = state }
	else
		puppet = nil
	end
end

function BodyAnimator.SetPuppetSpeed() end

-- Animate an extra model (e.g. the kill cam's copy of you). It reads its
-- "AimPitch" / "Weapon" attributes like any other character.
function BodyAnimator.Track(model)
	extra[model] = true
end

function BodyAnimator.Untrack(model)
	extra[model] = nil
	entries[model] = nil
end

function BodyAnimator.Init(controllers)
	Controllers = controllers
end

function BodyAnimator.Start()
	-- after Roblox's Animator has posed everyone this frame
	RunService.Stepped:Connect(step)
	-- after the camera (and its first-person hiding) each frame
	RunService:BindToRenderStep("BodyFirstPerson", Enum.RenderPriority.Camera.Value + 5, updateVisibility)

	-- inspect (V): the rifle or the knife; everyone sees it
	local function onInput(input, processed)
		if processed and UserInputService:GetFocusedTextBox() then
			return
		end
		if Keybinds.Matches("Inspect", input) and not puppet and not ClientState.MenuOpen and ClientState.HasGun() then
			local state = localState
			if state.Weapon == "Knife" then
				BodyAnimator.PlayKnife("Inspect")
				Remotes.Get("Anim"):FireServer("Inspect", "Knife")
			elseif WeaponAnim.Inspect(state, now()) then
				Sfx.Play("CardHover", { Pitch = 0.8, Volume = 1.2 })
				Remotes.Get("Anim"):FireServer("Inspect", "Rifle")
			end
		end
	end
	UserInputService.InputBegan:Connect(onInput)
	Keybinds.VirtualBegan:Connect(onInput)

	-- a new life: rifle out, equip from the hip
	player.CharacterAdded:Connect(function()
		localState = WeaponAnim.New()
		localState.EquipStart = now()
	end)
end

return BodyAnimator
