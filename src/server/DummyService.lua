--[[
	DummyService.lua  (ServerScriptService.Server.DummyService)

	Practice dummies on the lobby shooting range, so you can test the sniper
	and your aim on your own. Some stand still, some strafe left and right,
	one bobs up and down like a player bunny hopping.

	Dummies are simple flat-coloured models with the attribute Dummy = true,
	and body parts named like a real character (Head, UpperTorso, ...) so
	headshots and body shots work exactly the same as on a player.
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Palette = Config.Palette
local DummyService = {}

local folder
local dummies = {} -- { Model, Base = CFrame, Motion, Amount, Speed, Phase }

-- name, size, position (relative to the feet, facing +Z)
local BODY = {
	{ "LeftUpperLeg", Vector3.new(0.9, 2, 0.9), Vector3.new(-0.5, 1, 0) },
	{ "RightUpperLeg", Vector3.new(0.9, 2, 0.9), Vector3.new(0.5, 1, 0) },
	{ "LowerTorso", Vector3.new(2, 0.6, 1), Vector3.new(0, 2.3, 0) },
	{ "UpperTorso", Vector3.new(2, 1.6, 1), Vector3.new(0, 3.4, 0) },
	{ "LeftUpperArm", Vector3.new(0.8, 2, 0.8), Vector3.new(-1.45, 3.2, 0) },
	{ "RightUpperArm", Vector3.new(0.8, 2, 0.8), Vector3.new(1.45, 3.2, 0) },
	{ "Head", Vector3.new(1.15, 1.15, 1.15), Vector3.new(0, 4.85, 0) },
}

local function makeDummy(base)
	local model = Instance.new("Model")
	model.Name = "Dummy"
	model:SetAttribute("Dummy", true)
	model:SetAttribute("Health", Config.Lobby.DummyHealth)

	for _, spec in ipairs(BODY) do
		local part = Instance.new("Part")
		part.Name = spec[1]
		part.Size = spec[2]
		part.CFrame = base * CFrame.new(spec[3])
		part.Color = spec[1] == "Head" and Palette.PlayerB:Lerp(Color3.new(1, 1, 1), 0.25) or Palette.PlayerB
		part:SetAttribute("BaseColor", part.Color)
		part.Material = Enum.Material.SmoothPlastic
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.Parent = model
	end
	model.WorldPivot = base

	-- health bar
	local bar = Instance.new("BillboardGui")
	bar.Name = "HealthBar"
	bar.Size = UDim2.fromScale(3.2, 0.32)
	bar.StudsOffsetWorldSpace = Vector3.new(0, 6.2, 0)
	bar.Adornee = model.Head
	bar.Parent = model
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Palette.UIBackground
	back.BorderSizePixel = 0
	back.Parent = bar
	Instance.new("UICorner").Parent = back
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Palette.UIText
	fill.BorderSizePixel = 0
	fill.Parent = back
	Instance.new("UICorner").Parent = fill

	model.Parent = folder
	return model
end

local function setHealth(model, health)
	model:SetAttribute("Health", health)
	local fill = model:FindFirstChild("HealthBar") and model.HealthBar:FindFirstChild("Fill", true)
	if fill then
		local fraction = math.clamp(health / Config.Lobby.DummyHealth, 0, 1)
		fill.Size = UDim2.fromScale(fraction, 1)
		fill.BackgroundColor3 = fraction < 0.35 and Palette.UIDanger or Palette.UIText
	end
end

local function setShown(model, shown)
	for _, part in ipairs(model:GetChildren()) do
		if part:IsA("BasePart") then
			part.Transparency = shown and 0 or 1
			part.CanQuery = shown
		end
	end
	if model:FindFirstChild("HealthBar") then
		model.HealthBar.Enabled = shown
	end
end

-- Deals damage to a dummy. Returns true if this hit "killed" it.
function DummyService.Damage(model, amount)
	if not model:GetAttribute("Dummy") or model:GetAttribute("Down") then
		return false
	end
	local health = (model:GetAttribute("Health") or Config.Lobby.DummyHealth) - amount
	setHealth(model, math.max(health, 0))

	-- flash white
	for _, part in ipairs(model:GetChildren()) do
		if part:IsA("BasePart") then
			part.Color = Color3.new(1, 1, 1)
			TweenService:Create(part, TweenInfo.new(0.2), { Color = part:GetAttribute("BaseColor") }):Play()
		end
	end

	if health <= 0 then
		model:SetAttribute("Down", true)
		setShown(model, false)
		task.delay(Config.Lobby.DummyRespawnTime, function()
			if model.Parent then
				model:SetAttribute("Down", false)
				setHealth(model, Config.Lobby.DummyHealth)
				setShown(model, true)
			end
		end)
		return true
	end
	return false
end

--[[
	spots: list of { Position = Vector3 (feet), Motion = "Static"|"Strafe"|"Bob",
	                 Amount = studs, Speed = cycles per second }
	Dummies face +Z (toward the lobby).
]]
function DummyService.Init(spots)
	folder = Instance.new("Folder")
	folder.Name = "Dummies"
	folder.Parent = workspace

	for i, spot in ipairs(spots or {}) do
		local base = CFrame.lookAt(spot.Position, spot.Position + Vector3.new(0, 0, 1))
		table.insert(dummies, {
			Model = makeDummy(base),
			Base = base,
			Motion = spot.Motion or "Static",
			Amount = spot.Amount or 0,
			Speed = spot.Speed or 0.5,
			Phase = i * 1.3,
		})
	end

	RunService.Heartbeat:Connect(function()
		local t = os.clock()
		for _, d in ipairs(dummies) do
			if d.Motion ~= "Static" and d.Model.Parent then
				local wave = math.sin(t * d.Speed * math.pi * 2 + d.Phase)
				local offset = d.Motion == "Strafe" and Vector3.new(wave * d.Amount, 0, 0)
					or Vector3.new(0, (wave + 1) * 0.5 * d.Amount, 0)
				d.Model:PivotTo(d.Base + offset)
			end
		end
	end)
end

return DummyService
