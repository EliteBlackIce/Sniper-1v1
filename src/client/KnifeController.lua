--[[
	KnifeController.lua  (Client.KnifeController)

	Your second weapon: the combat knife (Config.Knife).
		1 / 2 / mouse wheel   switch rifle <-> knife (ButtonR1 on a controller)
		Left click            slash (alternates left / right, leaves a trail)
		Right click           stab: wind up, then a short lunge forward
		V                     inspect: look it over, toss it and catch it

	With the knife out you run a little faster (MovementController) and the
	rifle can't fire (WeaponController / the server both check).

	Hits: at the right moment in the swing we look for the enemy (or a
	practice dummy) in front of you, within range and in sight, and tell the
	server; the server re-checks everything (CombatService onMelee) and
	deals the damage. A hit from behind is a backstab: always a kill.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Util = require(Shared.Util)
local ClientState = require(script.Parent.ClientState)
local Keybinds = require(script.Parent.Keybinds)
local Sfx = require(script.Parent.Sfx)

local K = Config.Knife
local player = Players.LocalPlayer

local KnifeController = {}
local Controllers

local equippedAt = 0
local busyUntil = 0 -- no new swing before this
local pending = {} -- scheduled hit checks { At, Kind, Done }
local trailUntil = 0

----------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------
local function alive()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0 and not character:GetAttribute("Frozen")
end

local function canAttack()
	return K.Enabled
		and ClientState.Weapon == "Knife"
		and ClientState.CanShoot()
		and not ClientState.MenuOpen
		and alive()
		and os.clock() >= busyUntil
		and os.clock() - equippedAt >= K.EquipTime
end

local function setWeapon(name)
	if not K.Enabled then
		name = "Sniper"
	end
	if name == ClientState.Weapon then
		return
	end
	if name == "Knife" and not ClientState.HasGun() then
		return -- (between rounds / pick screen)
	end
	if ClientState.MenuOpen or not alive() or (Controllers.KillCam and Controllers.KillCam.IsPlaying()) then
		return -- menus, the crate cinematic, the kill cam
	end
	ClientState.Weapon = name
	equippedAt = os.clock()
	busyUntil = 0
	table.clear(pending)
	Controllers.Viewmodel.SetWeapon(name)
	Remotes.Get("Equip"):FireServer(name)
end

function KnifeController.Toggle()
	setWeapon(ClientState.Weapon == "Knife" and "Sniper" or "Knife")
end

function KnifeController.IsOut()
	return ClientState.Weapon == "Knife"
end

-- What's in front of us: the enemy in a match, the dummies in the lobby.
local function candidates()
	local list = {}
	if ClientState.InMatch() then
		local opponent = ClientState.GetOpponentPlayer()
		if opponent and opponent.Character then
			table.insert(list, opponent.Character)
		end
	else
		local folder = workspace:FindFirstChild("Dummies")
		for _, dummy in ipairs(folder and folder:GetChildren() or {}) do
			if not dummy:GetAttribute("Down") then
				table.insert(list, dummy)
			end
		end
	end
	return list
end

local function torsoOf(model)
	return model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso") or model:FindFirstChild("HumanoidRootPart")
end

local function excludeList()
	local list = { workspace.CurrentCamera }
	if player.Character then
		table.insert(list, player.Character)
	end
	local effects = workspace:FindFirstChild("Effects")
	if effects then
		table.insert(list, effects)
	end
	return list
end

-- The target the swing connects with (nearest in range + in the cone + in sight).
local function findTarget(kind)
	local camera = workspace.CurrentCamera
	local origin = camera.CFrame.Position
	local look = camera.CFrame.LookVector
	local range = kind == "Stab" and K.StabRange or K.SlashRange
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excludeList()
	local best, bestDist
	for _, model in ipairs(candidates()) do
		local torso = torsoOf(model)
		if torso then
			local offset = torso.Position - origin
			local dist = offset.Magnitude
			local inCone = dist < 2.5 or look:Dot(offset.Unit) >= math.cos(math.rad(K.HitAngle))
			if dist <= range and inCone then
				local hit = workspace:Raycast(origin, offset, params)
				if (not hit or hit.Instance:IsDescendantOf(model)) and (not bestDist or dist < bestDist) then
					best, bestDist = model, dist
				end
			end
		end
	end
	return best
end

----------------------------------------------------------------------------
-- Attacks
----------------------------------------------------------------------------
local function attack(kind)
	if not canAttack() then
		return
	end
	local now = os.clock()
	local length = kind == "Stab" and K.StabTime or K.SlashTime
	busyUntil = now + length
	Controllers.Viewmodel.PlayKnife(kind)
	table.insert(pending, { At = now + (kind == "Stab" and K.StabHitAt or K.SlashHitAt), Kind = kind })
	if kind == "Slash" then
		trailUntil = now + 0.3
		Sfx.Play("Dash", { Pitch = 1.5 + math.random() * 0.2, Volume = 0.9 })
	else
		-- wind up, then lunge
		task.delay(K.StabTime * 0.26, function()
			if ClientState.Weapon ~= "Knife" or not alive() then
				return
			end
			trailUntil = os.clock() + 0.2
			Sfx.Play("Dash", { Pitch = 1.15, Volume = 1.1 })
			local look = Util.flat(workspace.CurrentCamera.CFrame.LookVector)
			if look.Magnitude > 0.1 and Controllers.Movement.IsGrounded() then
				Controllers.Movement.ApplyImpulse(look.Unit * K.LungeSpeed)
			end
			Controllers.Camera.AddFovPunch(4)
		end)
	end
end

local function resolve(hitCheck)
	local camera = workspace.CurrentCamera
	local look = camera.CFrame.LookVector
	local target = findTarget(hitCheck.Kind)
	Remotes.Get("Melee"):FireServer(hitCheck.Kind, target, look)
	if target then
		local torso = torsoOf(target)
		Controllers.Effects.KnifeImpact(torso.Position - look * 0.6, -look, true)
		Controllers.Camera.Shake(hitCheck.Kind == "Stab" and 1.6 or 0.9)
		return
	end
	-- no body: did we hit a wall? (sparks + a clink)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excludeList()
	local reach = (hitCheck.Kind == "Stab" and K.StabRange or K.SlashRange) * 0.7
	local hit = workspace:Raycast(camera.CFrame.Position, look * reach, params)
	if hit then
		Controllers.Effects.KnifeImpact(hit.Position, hit.Normal, false)
		Sfx.PlayAt("Bolt", hit.Position, { Pitch = 1.8, Volume = 0.8 })
		Controllers.Camera.Shake(0.6)
	end
end

----------------------------------------------------------------------------
-- Slash trail: a thin glowing streak along the tip's path. The tip moves a
-- long way each frame mid-swing, so the streak follows a Catmull-Rom curve
-- through the last few tip positions (several short pieces per frame, one
-- frame behind) instead of one straight chord per frame: a smooth arc, not
-- a zig-zag.
----------------------------------------------------------------------------
local TRAIL_COLOR = Color3.fromRGB(235, 240, 255)
local TRAIL_WIDTH = 0.03
local TRAIL_LIFE = 0.14
local trailFolder
local history = {} -- the last 4 tip positions, oldest first

local function catmull(p0, p1, p2, p3, t)
	local t2, t3 = t * t, t * t * t
	return 0.5 * ((2 * p1) + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (3 * p1 - p0 - 3 * p2 + p3) * t3)
end

local function piece(a, c, born)
	local length = (c - a).Magnitude
	if length < 1e-3 then
		return
	end
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Shape = Enum.PartType.Cylinder
	part.Material = Enum.Material.Neon
	part.Color = TRAIL_COLOR
	part.Transparency = 0.4
	-- (a cylinder runs along X; a little longer than the gap so pieces overlap)
	part.Size = Vector3.new(length + TRAIL_WIDTH, TRAIL_WIDTH, TRAIL_WIDTH)
	part.CFrame = CFrame.lookAt((a + c) / 2, c) * CFrame.Angles(0, math.pi / 2, 0)
	part.Parent = trailFolder
	task.spawn(function()
		while part.Parent do
			local f = (os.clock() - born) / TRAIL_LIFE
			if f >= 1 then
				break
			end
			local w = TRAIL_WIDTH * (1 - f * 0.8)
			part.Size = Vector3.new(part.Size.X, w, w)
			part.Transparency = 0.4 + f * 0.6
			task.wait()
		end
		part:Destroy()
	end)
end

local function drawTrail()
	local tip = Controllers.Viewmodel.GetKnifeTip()
	if not (os.clock() < trailUntil and Config.Effects.NeonEffects) then
		table.clear(history)
		return
	end
	local last = history[#history]
	if last and (tip - last).Magnitude < 0.01 then
		return
	end
	table.insert(history, tip)
	if #history > 4 then
		table.remove(history, 1)
	end
	local n = #history
	if n < 3 then
		return
	end
	-- draw the piece before the newest point: p1 -> p2 (p0 and p3 bend it)
	local p1, p2, p3 = history[n - 2], history[n - 1], history[n]
	local p0 = history[n - 3] or (2 * p1 - p2)
	local steps = math.clamp(math.ceil((p2 - p1).Magnitude / 0.06), 1, 10)
	local now = os.clock()
	local prev = p1
	for k = 1, steps do
		local point = catmull(p0, p1, p2, p3, k / steps)
		piece(prev, point, now)
		prev = point
	end
end

----------------------------------------------------------------------------
-- Input
----------------------------------------------------------------------------
local function onInput(input, processed)
	if processed and UserInputService:GetFocusedTextBox() then
		return
	end
	local primary, knife = Keybinds.Matches("Primary", input), Keybinds.Matches("Knife", input)
	if primary and knife then
		KnifeController.Toggle() -- the same button for both (controller): toggle
		return
	elseif knife then
		setWeapon("Knife")
		return
	elseif primary then
		setWeapon("Sniper")
		return
	end
	if ClientState.Weapon ~= "Knife" then
		return
	end
	if Keybinds.Matches("Fire", input) then
		attack("Slash")
	elseif Keybinds.Matches("Scope", input) then
		attack("Stab")
	end
end

function KnifeController.Init(controllers)
	Controllers = controllers
end

function KnifeController.Start()
	trailFolder = Instance.new("Folder")
	trailFolder.Name = "KnifeTrail"
	trailFolder.Parent = workspace.CurrentCamera

	UserInputService.InputBegan:Connect(onInput)
	Keybinds.VirtualBegan:Connect(onInput)
	-- mouse wheel switches too
	local lastWheel = 0
	UserInputService.InputChanged:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseWheel and not processed and not ClientState.MenuOpen then
			if not Controllers.Weapon.IsScoped() and os.clock() - lastWheel > 0.3 then
				lastWheel = os.clock()
				KnifeController.Toggle()
			end
		end
	end)

	-- every life starts with the rifle
	local function reset()
		if ClientState.Weapon ~= "Sniper" then
			ClientState.Weapon = "Sniper"
			Controllers.Viewmodel.SetWeapon("Sniper")
			Remotes.Get("Equip"):FireServer("Sniper") -- in case a late switch reached the server
		end
		table.clear(pending)
		busyUntil = 0
	end
	player.CharacterAdded:Connect(reset)
	ClientState.Changed:Connect(function()
		if not ClientState.HasGun() then
			reset()
		end
	end)

	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		for i = #pending, 1, -1 do
			local check = pending[i]
			if now >= check.At then
				table.remove(pending, i)
				if ClientState.Weapon == "Knife" and alive() then
					resolve(check)
				end
			end
		end
		if ClientState.Weapon == "Knife" then
			drawTrail()
		else
			table.clear(history)
		end
	end)
end

return KnifeController
