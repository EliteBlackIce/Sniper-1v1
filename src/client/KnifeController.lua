--[[
	KnifeController.lua  (Client.KnifeController)

	Your second weapon: the combat knife (Config.Knife).
		1 / 2 / mouse wheel   switch rifle <-> knife (ButtonR1 on a controller)
		Left click            slash (alternates left / right, leaves a trail)
		Right click           stab: wind up, then a short lunge forward
		V                     inspect: toss it up and catch it, or twirl it

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
local lastTip

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
-- Slash trail: thin glowing streaks along the tip's path
----------------------------------------------------------------------------
local trailFolder
local function drawTrail()
	local tip = Controllers.Viewmodel.GetKnifeTip()
	if os.clock() < trailUntil and lastTip and (tip - lastTip).Magnitude > 0.02 and Config.Effects.NeonEffects then
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Color = Color3.fromRGB(235, 240, 255)
		part.Transparency = 0.45
		part.Size = Vector3.new(0.025, 0.025, (tip - lastTip).Magnitude)
		part.CFrame = CFrame.lookAt((tip + lastTip) / 2, tip)
		part.Parent = trailFolder
		task.spawn(function()
			for i = 1, 6 do
				task.wait(0.02)
				part.Transparency = 0.45 + i * 0.09
				part.Size = Vector3.new(0.025 * (1 - i / 7), 0.025 * (1 - i / 7), part.Size.Z)
			end
			part:Destroy()
		end)
	end
	lastTip = tip
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
	UserInputService.InputChanged:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseWheel and not processed and not ClientState.MenuOpen then
			if not Controllers.Weapon.IsScoped() then
				KnifeController.Toggle()
			end
		end
	end)

	-- every life starts with the rifle
	local function reset()
		if ClientState.Weapon ~= "Sniper" then
			ClientState.Weapon = "Sniper"
			Controllers.Viewmodel.SetWeapon("Sniper")
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
			lastTip = nil
		end
	end)
end

return KnifeController
