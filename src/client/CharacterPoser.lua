--[[
	CharacterPoser.lua  (Client.CharacterPoser)

	Third-person "holding a sniper" pose for every OTHER player you can see:
	arms raised holding the rifle, pointing where that player is looking (up
	or down), head and chest following the aim. Legs keep Roblox's normal
	run / jump / fall animations.

	How: each frame, after Roblox's Animator has posed the character, we
	override the arm / neck / waist Motor6D.Transform values (R15 rigs).
	Your own look pitch is sent to the server a few times a second and stored
	as the character attribute "AimPitch", so everyone sees it.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Remotes)
local ClientState = require(script.Parent.ClientState)

local player = Players.LocalPlayer
local rad = math.rad

local CharacterPoser = {}

local SEND_INTERVAL = 0.1
local cache = {} -- [character] = { motors }

local function getMotors(character)
	local motors = cache[character]
	if motors then
		return motors
	end
	local function find(partName, motorName)
		local part = character:FindFirstChild(partName)
		return part and part:FindFirstChild(motorName)
	end
	motors = {
		RightShoulder = find("RightUpperArm", "RightShoulder"),
		RightElbow = find("RightLowerArm", "RightElbow"),
		LeftShoulder = find("LeftUpperArm", "LeftShoulder"),
		LeftElbow = find("LeftLowerArm", "LeftElbow"),
		Waist = find("UpperTorso", "Waist"),
		Neck = find("Head", "Neck"),
	}
	if not motors.RightShoulder then
		return nil -- not an R15 rig (yet)
	end
	cache[character] = motors
	character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			cache[character] = nil
		end
	end)
	return motors
end

local function pose(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or not character:FindFirstChild("WorldGun") then
		return
	end
	local motors = getMotors(character)
	if not motors then
		return
	end
	local pitch = character:GetAttribute("AimPitch") or 0
	local armPitch = pitch * 0.75 -- the waist adds the rest

	-- right arm: straight forward holding the grip
	motors.RightShoulder.Transform = CFrame.Angles(0, rad(12), 0) * CFrame.Angles(rad(90) + armPitch, 0, 0)
	if motors.RightElbow then
		motors.RightElbow.Transform = CFrame.Angles(rad(12), 0, 0)
	end
	-- left arm: reaches across to hold the handguard
	if motors.LeftShoulder then
		motors.LeftShoulder.Transform = CFrame.Angles(0, rad(-42), 0) * CFrame.Angles(rad(96) + armPitch, 0, 0)
	end
	if motors.LeftElbow then
		motors.LeftElbow.Transform = CFrame.Angles(rad(28), 0, 0)
	end
	if motors.Waist then
		motors.Waist.Transform = CFrame.Angles(pitch * 0.25, 0, 0)
	end
	if motors.Neck then
		motors.Neck.Transform = CFrame.Angles(pitch * 0.5, 0, 0)
	end
end

function CharacterPoser.Init() end

function CharacterPoser.Start()
	-- override the animation pose every frame (Stepped runs after the Animator)
	RunService.Stepped:Connect(function()
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player and other.Character then
				pose(other.Character)
			end
		end
		-- and the bot, if you're fighting one
		local opponent = ClientState.Snapshot.InMatch and ClientState.GetOpponentPlayer()
		if typeof(opponent) == "table" and opponent.Character then
			pose(opponent.Character)
		end
	end)

	-- send our own look pitch
	local aim = Remotes.Get("Aim")
	local lastSent = 0
	task.spawn(function()
		while true do
			task.wait(SEND_INTERVAL)
			local camera = workspace.CurrentCamera
			if camera and player.Character then
				local pitch = math.asin(math.clamp(camera.CFrame.LookVector.Y, -1, 1))
				if math.abs(pitch - lastSent) > 0.03 then
					lastSent = pitch
					aim:FireServer(pitch)
				end
			end
		end
	end)
end

return CharacterPoser
