--[[
	CrateReveal.lua  (Client.ui.CrateReveal)

	The 2D half of the crate opening (CrateController does the 3D half):
	letterbox bars, a coloured edge glow, the rarity "climb" label, the
	white flash, and the reveal card: the rarity name slams in over spinning
	light rays, then the skin name, NEW / duplicate, keys left and the
	OPEN ANOTHER / CONTINUE buttons. Legendary rains confetti; Secret glitches.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Signal = require(Shared.Signal)
local Theme = require(script.Parent.Theme)
local Logo = require(Shared.Logo)

local P = Config.Palette
local CR = Config.Crates

local CrateReveal = {}
CrateReveal.Again = Signal.new()
CrateReveal.Done = Signal.new()

local gui, unlocker
local barTop, barBottom, black, flash
local edges = {}
local tierLabel, tierSub
local card, rays, titleLabel, glitchA, glitchB, skinLabel, infoLabel, keysLabel, badge
local buttons, againButton, doneButton
local confetti = {}
local rayAngle = 0
local glitchUntil = 0
local revealColor = Color3.new(1, 1, 1)
local RAY_COUNT = 9

local function font(weight)
	return Theme.Font(weight or Enum.FontWeight.Heavy)
end

----------------------------------------------------------------------------
-- Build
----------------------------------------------------------------------------
function CrateReveal.Start(playerGui)
	gui = Theme.screen("CrateReveal", 60, playerGui)
	gui.Enabled = false
	unlocker = Theme.mouseUnlocker(gui)

	-- edge glow: four soft gradients in the current tier colour
	for i, info in ipairs({
		{ UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.35), 90 },
		{ UDim2.fromScale(0, 0.65), UDim2.fromScale(1, 0.35), -90 },
		{ UDim2.fromScale(0, 0), UDim2.fromScale(0.25, 1), 0 },
		{ UDim2.fromScale(0.75, 0), UDim2.fromScale(0.25, 1), 180 },
	}) do
		local edge = Theme.new("Frame", {
			Position = info[1],
			Size = info[2],
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 1,
			Parent = gui,
		})
		Theme.new("UIGradient", {
			Rotation = info[3],
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }),
			Parent = edge,
		})
		edges[i] = edge
	end

	-- letterbox
	barTop = Theme.new("Frame", { Size = UDim2.fromScale(1, 0), BackgroundColor3 = Color3.new(0, 0, 0), ZIndex = 5, Parent = gui })
	barBottom = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		ZIndex = 5,
		Parent = gui,
	})

	-- the climb label (COMMON... UNCOMMON... RARE...) near the bottom
	tierLabel = Theme.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.8),
		Size = UDim2.fromScale(0.5, 0.075),
		TextScaled = true,
		FontFace = font(),
		TextTransparency = 1,
		ZIndex = 6,
		Parent = gui,
	})
	Theme.stroke(tierLabel, Color3.new(0, 0, 0), 3, 0.4).ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	tierSub = Theme.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.735),
		Size = UDim2.fromScale(0.4, 0.03),
		TextScaled = true,
		Text = "OPENING CRATE",
		FontFace = font(Enum.FontWeight.Bold),
		TextColor3 = P.UIText,
		TextTransparency = 1,
		ZIndex = 6,
		Parent = gui,
	})

	-- reveal card (no background: it floats over the 3D scene)
	card = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.74),
		Size = UDim2.fromScale(1, 0.4),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 7,
		Parent = gui,
	})
	rays = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, -0.55),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = card,
	})
	for _ = 1, RAY_COUNT do
		local ray = Theme.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, 46, 2.2, 0),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.55,
			ZIndex = 2,
			Parent = rays,
		})
		Theme.new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.42, 0.5),
				NumberSequenceKeypoint.new(0.5, 0.15),
				NumberSequenceKeypoint.new(0.58, 0.5),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = ray,
		})
	end
	local function title(z, color)
		local label = Theme.label({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.18),
			Size = UDim2.fromScale(0.8, 0.34),
			TextScaled = true,
			FontFace = font(),
			TextColor3 = color,
			ZIndex = z,
			Parent = card,
		})
		return label
	end
	glitchA = title(3, Color3.fromRGB(255, 30, 60))
	glitchB = title(3, Color3.fromRGB(40, 230, 255))
	titleLabel = title(5, Color3.new(1, 1, 1))
	Theme.stroke(titleLabel, Color3.new(0, 0, 0), 4, 0.2).ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	Theme.new("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200)),
		Rotation = 90,
		Parent = titleLabel,
	})
	skinLabel = Theme.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromScale(0.6, 0.13),
		TextScaled = true,
		FontFace = font(),
		ZIndex = 5,
		Parent = card,
	})
	Theme.stroke(skinLabel, Color3.new(0, 0, 0), 2, 0.4).ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	infoLabel = Theme.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.54),
		Size = UDim2.fromScale(0.6, 0.065),
		TextScaled = true,
		FontFace = font(Enum.FontWeight.Bold),
		TextColor3 = P.UIText,
		ZIndex = 5,
		Parent = card,
	})
	badge = Theme.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.03),
		Size = UDim2.fromOffset(84, 26),
		Text = "NEW!",
		TextSize = 18,
		FontFace = font(),
		TextColor3 = P.UIBackground,
		BackgroundTransparency = 0,
		BackgroundColor3 = P.AccentB,
		Rotation = -6,
		ZIndex = 6,
		Visible = false,
		Parent = card,
	})
	Theme.corner(badge, 8)

	-- buttons
	buttons = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.74),
		Size = UDim2.fromOffset(470, 50),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = card,
	})
	Theme.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 14),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = buttons,
	})
	againButton = Theme.button({
		Size = UDim2.fromOffset(240, 50),
		Text = "[X]  OPEN ANOTHER",
		TextSize = 19,
		LayoutOrder = 1,
		ZIndex = 6,
		Parent = buttons,
	})
	doneButton = Theme.button({
		Size = UDim2.fromOffset(200, 50),
		Text = "[SPACE]  CONTINUE",
		TextSize = 19,
		BackgroundColor3 = P.UIPanelLight,
		TextColor3 = P.UIText,
		LayoutOrder = 2,
		ZIndex = 6,
		Parent = buttons,
	})
	Theme.stroke(doneButton, P.UIText, 1.5, 0.7)
	keysLabel = Theme.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.9),
		Size = UDim2.fromScale(0.5, 0.05),
		TextScaled = true,
		FontFace = font(Enum.FontWeight.Bold),
		TextColor3 = P.UIText,
		TextTransparency = 0.25,
		ZIndex = 6,
		Parent = card,
	})
	againButton.Activated:Connect(function()
		CrateReveal.Again:Fire()
	end)
	doneButton.Activated:Connect(function()
		CrateReveal.Done:Fire()
	end)

	-- small logo in the corner so clips/screenshots carry the brand
	local corner = Theme.new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0.02, 0),
		Size = UDim2.fromOffset(190, 48),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = gui,
	})
	Logo.Make(corner, { Layout = "Inline", Color = P.UIText, Accent = P.AccentA })

	flash = Theme.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		ZIndex = 20,
		Parent = gui,
	})
	black = Theme.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		ZIndex = 30,
		Parent = gui,
	})
end

----------------------------------------------------------------------------
-- Pieces the controller drives
----------------------------------------------------------------------------
function CrateReveal.Show()
	gui.Enabled = true
	card.Visible = false
	unlocker.Visible = false
	tierLabel.TextTransparency = 1
	tierSub.TextTransparency = 1
	for _, edge in ipairs(edges) do
		edge.BackgroundTransparency = 1
	end
	Theme.tween(barTop, 0.6, { Size = UDim2.fromScale(1, 0.1) }, Enum.EasingStyle.Quint)
	Theme.tween(barBottom, 0.6, { Size = UDim2.fromScale(1, 0.1) }, Enum.EasingStyle.Quint)
	Theme.tween(tierSub, 0.5, { TextTransparency = 0.3 })
end

function CrateReveal.Hide()
	gui.Enabled = false
	unlocker.Visible = false
	barTop.Size = UDim2.fromScale(1, 0)
	barBottom.Size = UDim2.fromScale(1, 0)
	card.Visible = false
	for _, bit in ipairs(confetti) do
		bit.Frame:Destroy()
	end
	table.clear(confetti)
end

-- One step of the rarity climb.
function CrateReveal.Tier(rarity, final)
	tierLabel.Text = rarity.Name
	tierLabel.TextColor3 = rarity.Color
	tierLabel.TextTransparency = 0
	Theme.pop(tierLabel, final and 0.45 or 0.25)
	for _, edge in ipairs(edges) do
		edge.BackgroundColor3 = rarity.Color
		edge.BackgroundTransparency = final and 0.15 or 0.4
		Theme.tween(edge, 0.45, { BackgroundTransparency = final and 0.55 or 0.75 })
	end
end

-- The climb stalls (Secret fake-out): everything dims.
function CrateReveal.Stall()
	Theme.tween(tierLabel, 0.5, { TextTransparency = 0.7 })
	for _, edge in ipairs(edges) do
		Theme.tween(edge, 0.5, { BackgroundTransparency = 1 })
	end
end

function CrateReveal.Flash(color, time)
	flash.BackgroundColor3 = color or Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 0
	Theme.tween(flash, time or 0.7, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
end

function CrateReveal.Black(alpha, time)
	return Theme.tween(black, time or 0.25, { BackgroundTransparency = 1 - alpha })
end

local function spawnConfetti(colors, count)
	local size = gui.AbsoluteSize
	for _ = 1, count do
		local frame = Theme.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(math.random(6, 12), math.random(10, 18)),
			BackgroundColor3 = colors[math.random(1, #colors)],
			ZIndex = 8,
			Parent = gui,
		})
		table.insert(confetti, {
			Frame = frame,
			Pos = Vector2.new(size.X * (0.5 + (math.random() - 0.5) * 0.2), size.Y * 0.45),
			Vel = Vector2.new((math.random() - 0.5) * size.X * 1.4, -size.Y * (0.5 + math.random() * 0.7)),
			Spin = (math.random() - 0.5) * 900,
			Age = 0,
		})
	end
end

-- The big moment. info = { Rarity, Skin, New, Count, Keys, Free, CanAgain }
function CrateReveal.Reveal(info)
	local rarity, skin = info.Rarity, info.Skin
	revealColor = rarity.Color
	tierLabel.TextTransparency = 1
	tierSub.TextTransparency = 1
	card.Visible = true
	titleLabel.Text = rarity.Name
	glitchA.Text = rarity.Name
	glitchB.Text = rarity.Name
	titleLabel.TextColor3 = rarity.Color
	glitchA.Visible = rarity.Id == "Secret"
	glitchB.Visible = rarity.Id == "Secret"
	glitchUntil = rarity.Id == "Secret" and os.clock() + 1.6 or 0
	for _, ray in ipairs(rays:GetChildren()) do
		ray.BackgroundColor3 = rarity.Color
	end
	rays.Visible = true

	-- title slams in
	local scale = Theme.scaleOf(titleLabel)
	scale.Scale = 2.6
	titleLabel.TextTransparency = 0
	Theme.tween(scale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)

	skinLabel.Text = string.upper(skin.Name)
	skinLabel.TextColor3 = P.UIText
	skinLabel.TextTransparency = 1
	local kind = skin.Weapon == "Knife" and "KNIFE SKIN" or "RIFLE SKIN"
	infoLabel.Text = info.New and (kind .. "  -  EQUIP IT IN THE LOCKER [L]")
		or ("%s  -  DUPLICATE  x%d"):format(kind, info.Count or 2)
	infoLabel.TextTransparency = 1
	badge.Visible = false
	buttons.Visible = false
	keysLabel.Text = info.Free and "FREE OPENS IN STUDIO" or ("%d KEY%s LEFT"):format(info.Keys or 0, info.Keys == 1 and "" or "S")
	keysLabel.TextTransparency = 1

	task.delay(0.35, function()
		Theme.tween(skinLabel, 0.35, { TextTransparency = 0 })
		Theme.pop(skinLabel, 0.2)
	end)
	task.delay(0.6, function()
		Theme.tween(infoLabel, 0.35, { TextTransparency = 0.1 })
		if info.New then
			badge.Visible = true
			Theme.pop(badge, 0.5)
		end
	end)
	task.delay(1.1, function()
		if not card.Visible then
			return
		end
		buttons.Visible = true
		againButton.Visible = info.CanAgain
		Theme.pop(buttons, 0.12)
		Theme.tween(keysLabel, 0.35, { TextTransparency = 0.25 })
		unlocker.Visible = true
	end)

	local tier = 1
	for i, r in ipairs(CR.Rarities) do
		if r.Id == rarity.Id then
			tier = i
		end
	end
	if tier >= 5 then
		spawnConfetti({ rarity.Color, Color3.new(1, 1, 1), rarity.Color:Lerp(Color3.new(1, 1, 1), 0.5) }, rarity.Id == "Secret" and 90 or 70)
	elseif tier >= 3 then
		spawnConfetti({ rarity.Color, Color3.new(1, 1, 1) }, 26)
	end
end

function CrateReveal.HideCard()
	card.Visible = false
	unlocker.Visible = false
end

function CrateReveal.IsShowingButtons()
	return card.Visible and buttons.Visible
end

-- True when OPEN ANOTHER is offered (you have a key, or it's free).
function CrateReveal.CanAgain()
	return CrateReveal.IsShowingButtons() and againButton.Visible
end

function CrateReveal.Update(dt)
	if not gui or not gui.Enabled then
		return
	end
	-- rays
	rayAngle += dt * 22
	for i, ray in ipairs(rays:GetChildren()) do
		ray.Rotation = rayAngle + (i - 1) * 180 / RAY_COUNT
		ray.BackgroundTransparency = 0.55 + math.sin(os.clock() * 3 + i) * 0.08
	end
	-- secret glitch: RGB-split copies jitter, the title flickers
	if os.clock() < glitchUntil then
		local j = 9
		glitchA.Position = UDim2.new(0.5, math.random(-j, j), 0.18, math.random(-j, j) * 0.5)
		glitchB.Position = UDim2.new(0.5, math.random(-j, j), 0.18, math.random(-j, j) * 0.5)
		titleLabel.TextTransparency = math.random() < 0.12 and 0.6 or 0
		titleLabel.Position = UDim2.new(0.5, math.random(-3, 3), 0.18, 0)
	elseif glitchA.Visible then
		glitchA.Visible = false
		glitchB.Visible = false
		titleLabel.TextTransparency = 0
		titleLabel.Position = UDim2.fromScale(0.5, 0.18)
	end
	-- confetti
	for i = #confetti, 1, -1 do
		local bit = confetti[i]
		bit.Age += dt
		bit.Vel = Vector2.new(bit.Vel.X * (1 - 1.2 * dt), bit.Vel.Y + gui.AbsoluteSize.Y * 1.1 * dt)
		bit.Pos += bit.Vel * dt
		bit.Frame.Position = UDim2.fromOffset(bit.Pos.X, bit.Pos.Y)
		bit.Frame.Rotation += bit.Spin * dt
		bit.Frame.BackgroundTransparency = math.clamp((bit.Age - 2.2) / 0.8, 0, 1)
		if bit.Age > 3 then
			bit.Frame:Destroy()
			table.remove(confetti, i)
		end
	end
end

return CrateReveal
