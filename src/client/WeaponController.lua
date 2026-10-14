--[[
	WeaponController.lua  (Client.WeaponController)

	The sniper:
		Right mouse  scope (hold, or toggle in settings)
		Left mouse   fire

	When you fire, the client:
	  1. traces the bullet(s) locally with Ballistics (same code as the server)
	     so tracers appear instantly,
	  2. sends the shot + what it saw itself hit ("claims") to the server,
	  3. plays recoil, the bolt animation and sound.
	The SERVER decides the real damage (see CombatService).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Ballistics = require(Shared.Ballistics)
local Util = require(Shared.Util)
local Cosmetics = require(Shared.Cosmetics)
local ClientState = require(script.Parent.ClientState)
local Sfx = require(script.Parent.Sfx)
local Keybinds = require(script.Parent.Keybinds)

local W = Config.Weapon
local player = Players.LocalPlayer

local Weapon = {}
local Controllers

local scopeHeld = false
local scopeAlpha = 0
local boltReadyAt = 0

----------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------
function Weapon.GetScopeAlpha()
	return scopeAlpha
end

function Weapon.IsScoped()
	return scopeAlpha > 0.9
end

-- 0 = ready, 1 = just fired
function Weapon.GetBoltProgress()
	local stats = ClientState.Stats
	local remaining = boltReadyAt - os.clock()
	return math.clamp(remaining / stats.BoltTime, 0, 1)
end

----------------------------------------------------------------------------
-- Firing
----------------------------------------------------------------------------
local function canShoot()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return ClientState.CanShoot()
		and not ClientState.MenuOpen
		and humanoid
		and humanoid.Health > 0
		and not character:GetAttribute("Frozen")
end

-- Random direction inside a cone of `degrees` around `dir`.
local function applySpread(dir, degrees)
	if degrees <= 0 then
		return dir
	end
	local angle = math.rad(degrees) * math.sqrt(math.random())
	local spin = math.random() * math.pi * 2
	local cf = CFrame.lookAt(Vector3.zero, dir)
	return (cf * CFrame.Angles(0, 0, spin) * CFrame.Angles(angle, 0, 0)).LookVector
end

local function buildExclude()
	local list = { workspace.CurrentCamera }
	if player.Character then
		table.insert(list, player.Character)
	end
	local effects = workspace:FindFirstChild("Effects")
	if effects then
		table.insert(list, effects)
	end
	local decoys = workspace:FindFirstChild("Decoys")
	if decoys then
		for _, decoy in ipairs(decoys:GetChildren()) do
			if decoy:GetAttribute("OwnerUserId") == player.UserId then
				table.insert(list, decoy)
			end
		end
	end
	return list
end

local function fire()
	if not canShoot() or os.clock() < boltReadyAt then
		return
	end
	local camera = workspace.CurrentCamera
	local stats = ClientState.Stats
	local scoped = Weapon.IsScoped()

	local origin = camera.CFrame.Position
	local direction = applySpread(camera.CFrame.LookVector, scoped and W.ScopedSpreadDegrees or W.HipSpreadDegrees)

	local opponent = ClientState.GetOpponentPlayer()
	local opponentCharacter = opponent and opponent.Character
	local homingTargets = ClientState.GetHomingTargets()
	local exclude = buildExclude()

	local muzzle = Controllers.Viewmodel.GetMuzzlePosition()
	if scoped then
		-- tracer starts slightly below the screen centre when scoped
		muzzle = origin + camera.CFrame.LookVector * 1.5 - camera.CFrame.UpVector * 0.4
	end

	-- dense list (sparse arrays don't survive RemoteEvents): { {Index, Part, Point} }
	local claims = {}
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")

	for i, dir in ipairs(Ballistics.GetShotDirections(direction, stats.Bullets)) do
		local sim = Ballistics.Simulate({
			Origin = origin,
			Direction = dir,
			Stats = stats,
			Exclude = exclude,
			HomingTargets = homingTargets,
		})
		-- the enemy in a match, or a practice dummy in the lobby
		local hitModel = sim.Hit and sim.Hit.Model
		local hitEnemy = hitModel ~= nil
			and ((opponentCharacter ~= nil and hitModel == opponentCharacter) or hitModel:GetAttribute("Dummy") == true)
		if hitEnemy then
			table.insert(claims, { Index = i, Model = hitModel, Part = sim.Hit.Part.Name, Point = sim.Hit.Position })
		end
		Controllers.Effects.DrawShot(sim.Segments, sim.Passes, sim.EndPosition, sim.EndNormal, muzzle, {
			Explosive = stats.Explosive,
			HitPlayer = hitEnemy,
			Tracer = Cosmetics.TracerColor(player),
		})

		-- ROCKET JUMP: shooting near your own feet launches you
		if stats.RocketJump and i == 1 and root and sim.EndPosition then
			local offset = root.Position - sim.EndPosition
			local cfg = Config.PowerUps.RocketJump
			if offset.Magnitude <= cfg.Radius then
				local away = Util.safeUnit(Util.flat(offset))
				local power = stats.RocketJumpPower
				Controllers.Movement.ApplyImpulse((away * cfg.LaunchAway + Vector3.new(0, cfg.LaunchUp, 0)) * power)
				Controllers.Camera.Shake(3)
			end
		end
	end

	Remotes.Get("Fire"):FireServer(origin, direction, claims)
	Controllers.Effects.MuzzleFlash(Controllers.Viewmodel.GetMuzzlePosition(), camera.CFrame.LookVector)

	-- Bolt delay (Quickdraw is already in stats.BoltTime; Bullet Time speeds it up)
	local boltTime = stats.BoltTime
	if Controllers.Movement.IsBulletTime() then
		boltTime /= Config.PowerUps.BulletTime.BoltSpeedScale
	end
	boltReadyAt = os.clock() + boltTime

	Sfx.Play("Fire", { Pitch = 0.95 + math.random() * 0.1 })
	Controllers.Viewmodel.PlayFire(scoped)
	Controllers.Viewmodel.PlayBolt(boltTime)
	Controllers.Camera.AddRecoil(scoped and Config.Camera.ScopedRecoilPitch or Config.Camera.RecoilPitch)
	Controllers.Camera.Shake(scoped and 0.6 or 1.2)
end

----------------------------------------------------------------------------
-- Input
----------------------------------------------------------------------------
-- Roblox's own control scripts bind Space (and some mouse buttons) with
-- ContextActionService, which marks those inputs as "processed". So we only
-- ignore input while the player is typing in a text box (e.g. chat).
local function isTyping(processed)
	return processed and UserInputService:GetFocusedTextBox() ~= nil
end

local function onInputBegan(input, processed)
	if isTyping(processed) or ClientState.Weapon == "Knife" then
		return -- (KnifeController handles the knife)
	end
	if Keybinds.Matches("Fire", input) then
		fire()
	elseif Keybinds.Matches("Scope", input) then
		if ClientState.Settings.ToggleScope then
			scopeHeld = not scopeHeld
		else
			scopeHeld = true
		end
	end
end

local function onInputEnded(input)
	if Keybinds.Matches("Scope", input) then
		if not ClientState.Settings.ToggleScope then
			scopeHeld = false
		end
	end
end

local function update(dt)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local allowed = ClientState.HasGun() and not ClientState.MenuOpen and humanoid and humanoid.Health > 0
		and ClientState.Weapon ~= "Knife"
	if not allowed then
		scopeHeld = false
	end
	local target = scopeHeld and 1 or 0
	local scopeTime = ClientState.Stats.ScopeInTime
	scopeAlpha = Util.approach(scopeAlpha, target, dt / math.max(scopeTime, 0.01))
end

function Weapon.Init(controllers)
	Controllers = controllers
end

function Weapon.Start()
	-- HAIR TRIGGER power-up: the server tells us a hit re-chambered the rifle
	Remotes.Get("Buff").OnClientEvent:Connect(function(buff)
		if typeof(buff) == "table" and buff.Type == "Rechamber" then
			boltReadyAt = math.min(boltReadyAt, os.clock() + 0.1)
			Controllers.Viewmodel.PlayBolt(0.18)
		end
	end)

	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputEnded:Connect(onInputEnded)
	Keybinds.VirtualBegan:Connect(onInputBegan) -- on-screen buttons (mobile)
	Keybinds.VirtualEnded:Connect(onInputEnded)
	RunService:BindToRenderStep("SniperWeapon", Enum.RenderPriority.Input.Value + 1, update)
end

return Weapon
