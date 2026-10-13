--[[
	PickScreen.lua  (Client.ui.PickScreen)

	Between rounds the player who DIED picks 1 of 5 power-up cards.

	CARD LAYOUT (top to bottom)
		rarity pill + "owned x1 > x2" badge
		icon on a glowing disc
		name, tag chips (Bullets / Damage / Movement ...)
		description
		STACKS footer: what another copy adds

	ANIMATION
		open     background fades in, title slides down
		deal     cards rise from below one after another, face down
		flip     each card flips over with a white flash; Legendary cards burst
		         with gold particles, a ring and a looping shine
		idle     cards float gently, glows breathe
		hover    lift + tilt toward the mouse + brighter glow (picker only)
		pick     chosen card flies to the centre with a burst; the rest fall away
		timer    bar drains, ticks and turns red in the last 5 seconds

	The winner sees the same cards but can't pick. The mouse is unlocked.
	Also used solo by the Power-Up Lab ("practice pick").
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local PowerUps = require(Shared.PowerUps)
local Remotes = require(Shared.Remotes)
local ClientState = require(script.Parent.Parent.ClientState)
local Sfx = require(script.Parent.Parent.Sfx)
local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.Icons)

local Palette = Config.Palette
local player = Players.LocalPlayer

local CARD_W, CARD_H = 210, 318
local GAP = 22

local PickScreen = {}

local gui, overlay, title, subtitle, timerTrack, timerFill, timerText, row, unlocker
local cards = {} -- card records
local isOpen = false
local isPicker = false
local pickedIndex = nil
local openToken = 0
local practiceCallback = nil -- set when opened from the Power-Up Lab (solo practice)
local lastTimerSecond = nil

----------------------------------------------------------------------------
-- Card construction
----------------------------------------------------------------------------
local function chip(parent, text, color)
	local c = Theme.new("Frame", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 18),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.82,
		Parent = parent,
	})
	Theme.corner(c, 9)
	Theme.new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = c })
	Theme.label({
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		Text = string.upper(text),
		TextSize = 10,
		TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.45),
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = c,
	})
	return c
end

local function makeCard(index, def, ownedStacks)
	local rarity = Config.Rarity[def.Rarity]
	local color = rarity.Color
	local rec = { Index = index, Def = def, Flipped = false, Phase = index * 0.9 }

	-- holder: fixed slot in the row layout
	local holder = Theme.new("Frame", {
		Name = "Card" .. index,
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		BackgroundTransparency = 1,
		LayoutOrder = index,
		Parent = row,
	})
	-- mover: everything that animates (position / rotation / scale)
	local mover = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 160),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = holder,
	})
	local scale = Theme.new("UIScale", { Parent = mover })

	-- soft glow (two layers) behind the card
	local glow = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 26, 1, 26),
		BackgroundColor3 = color,
		BackgroundTransparency = 1,
		Parent = mover,
	})
	Theme.corner(glow, 26)
	local glowInner = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 10, 1, 10),
		BackgroundColor3 = color,
		BackgroundTransparency = 1,
		Parent = mover,
	})
	Theme.corner(glowInner, 20)

	-- flipper: its width animates for the card flip
	local flipper = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = mover,
	})

	-- the card face (a CanvasGroup so it fades and clips as one piece)
	local card = Theme.new("CanvasGroup", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Palette.UIPanel,
		GroupTransparency = 1,
		Parent = flipper,
	})
	Theme.corner(card, 16)
	local stroke = Theme.stroke(card, color, 2.5, 0)

	-- FRONT -----------------------------------------------------------
	local front = Theme.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = card })
	-- colour wash from the top
	local wash = Theme.new("Frame", { Size = UDim2.new(1, 0, 0.55, 0), BackgroundColor3 = color, Parent = front })
	Theme.new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.72), NumberSequenceKeypoint.new(1, 1) }),
		Parent = wash,
	})
	-- rarity pill
	local pill = Theme.new("Frame", {
		Position = UDim2.fromOffset(12, 12),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
		BackgroundColor3 = color,
		Parent = front,
	})
	Theme.corner(pill, 10)
	Theme.new("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9), Parent = pill })
	Theme.label({
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		Text = string.upper(def.Rarity),
		TextSize = 11,
		TextColor3 = Palette.UIBackground,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = pill,
	})
	if ownedStacks > 0 then
		local badge = Theme.new("Frame", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 12),
			Size = UDim2.fromOffset(64, 20),
			BackgroundColor3 = Palette.UIBackground,
			BackgroundTransparency = 0.3,
			Parent = front,
		})
		Theme.corner(badge, 10)
		Theme.label({
			Size = UDim2.fromScale(1, 1),
			Text = ("x%d > x%d"):format(ownedStacks, ownedStacks + 1),
			TextSize = 11,
			TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.4),
			FontFace = Theme.Font(Enum.FontWeight.Heavy),
			Parent = badge,
		})
	end
	-- icon on a glowing disc
	local disc = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 44),
		Size = UDim2.fromOffset(112, 112),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.82,
		Parent = front,
	})
	Theme.corner(disc, UDim.new(0.5, 0))
	Theme.stroke(disc, color, 1.5, 0.55)
	local icon = Icons.Create(def, 74)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Parent = disc
	-- name
	Theme.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 166),
		Size = UDim2.new(1, -24, 0, 26),
		Text = def.Name,
		TextSize = 21,
		TextTruncate = Enum.TextTruncate.AtEnd,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = front,
	})
	-- tag chips
	local tags = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 194),
		Size = UDim2.new(1, -24, 0, 18),
		BackgroundTransparency = 1,
		Parent = front,
	}, {
		Theme.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 5),
		}),
	})
	for _, tag in ipairs(def.Tags or {}) do
		chip(tags, tag, color)
	end
	-- description
	Theme.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 220),
		Size = UDim2.new(1, -28, 0, 52),
		Text = def.Description,
		TextSize = 13,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Palette.UISubText,
		FontFace = Theme.Font(Enum.FontWeight.Medium),
		Parent = front,
	})
	-- stacking footer
	local footer = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = Palette.UIBackground,
		BackgroundTransparency = 0.35,
		Parent = front,
	})
	Theme.new("Frame", { Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = color, BackgroundTransparency = 0.5, Parent = footer })
	Theme.label({
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -24, 1, 0),
		Text = "STACKS  " .. (def.Stacking or "-"),
		TextSize = 11,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.35),
		FontFace = Theme.Font(Enum.FontWeight.Bold),
		Parent = footer,
	})

	-- BACK ------------------------------------------------------------
	local back = Theme.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color:Lerp(Palette.UIBackground, 0.7),
		Parent = card,
	})
	for i = -4, 4 do
		Theme.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, i * 34, 0.5, 0),
			Size = UDim2.new(0, 10, 1.6, 0),
			Rotation = 30,
			BackgroundColor3 = color,
			BackgroundTransparency = 0.85,
			Parent = back,
		})
	end
	local diamond = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(70, 70),
		Rotation = 45,
		BackgroundColor3 = color,
		BackgroundTransparency = 0.2,
		Parent = back,
	})
	Theme.corner(diamond, 12)
	Theme.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(60, 60),
		Text = "?",
		TextSize = 42,
		TextColor3 = Palette.UIBackground,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = back,
	})

	-- white flash layer used when the card flips / is picked
	local flash = Theme.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		ZIndex = 9,
		Parent = card,
	})

	local button = Theme.new("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 11,
		Parent = mover,
	})

	rec.Holder, rec.Mover, rec.Scale, rec.Glow, rec.GlowInner = holder, mover, scale, glow, glowInner
	rec.Flipper, rec.Card, rec.Stroke, rec.Front, rec.Back = flipper, card, stroke, front, back
	rec.Flash, rec.Button, rec.Color = flash, button, color
	rec.BaseGlow = def.Rarity == "Legendary" and 0.6 or def.Rarity == "Epic" and 0.72 or 0.82
	return rec
end

local function cardCenter(rec)
	local p, s = rec.Mover.AbsolutePosition, rec.Mover.AbsoluteSize
	return p + s / 2
end

----------------------------------------------------------------------------
-- Animations
----------------------------------------------------------------------------
local function dealAndFlip(rec, delay, token)
	task.delay(delay, function()
		if token ~= openToken then
			return
		end
		rec.Mover.Rotation = (rec.Index % 2 == 0) and 6 or -6
		-- 1) rise in, face down
		Theme.tween(rec.Card, 0.35, { GroupTransparency = 0 })
		Theme.tween(rec.Mover, 0.5, { Position = UDim2.fromScale(0.5, 0.5), Rotation = 0 }, Enum.EasingStyle.Back)
		Sfx.Play("CardHover", { Pitch = 0.7 + rec.Index * 0.08, Volume = 1.2 })
		task.wait(0.55)
		if token ~= openToken then
			return
		end
		-- 2) flip: squash to edge-on...
		Theme.tween(rec.Flipper, 0.12, { Size = UDim2.fromScale(0, 1) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.wait(0.12)
		if token ~= openToken then
			return
		end
		-- ...swap faces and open up with a flash
		rec.Back.Visible = false
		rec.Front.Visible = true
		rec.Flash.BackgroundTransparency = 0.2
		Theme.tween(rec.Flash, 0.45, { BackgroundTransparency = 1 })
		Theme.tween(rec.Flipper, 0.24, { Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Back)
		rec.Flipped = true
		rec.GlowInner.BackgroundTransparency = 0.4
		Theme.tween(rec.GlowInner, 0.6, { BackgroundTransparency = rec.BaseGlow })

		local rarity = rec.Def.Rarity
		if rarity == "Legendary" then
			Sfx.Play("CardLegendary")
			task.wait(0.05)
			local center = cardCenter(rec)
			Theme.burst(gui, center, rec.Color, 22, 200, 9)
			Theme.ring(gui, center, rec.Color, 380, 8)
			Theme.shine(rec.Card, 1.4, true, 0.4)
			Theme.pop(rec.Mover, 0.1)
		elseif rarity == "Epic" then
			Sfx.Play("CardFlip", { Pitch = 1.25 })
			Theme.burst(gui, cardCenter(rec), rec.Color, 10, 130, 7)
			Theme.shine(rec.Card, 0.7, false, 0.35)
		else
			Sfx.Play("CardFlip", { Pitch = 1 + Config.Rarity[rarity].Order * 0.08 })
			Theme.shine(rec.Card, 0.6, false, 0.25)
		end
	end)
end

local function setHover(rec, hovered)
	if not isPicker or pickedIndex or not rec.Flipped then
		return
	end
	rec.Hovered = hovered
	if hovered then
		Sfx.Play("CardHover")
		Theme.tween(rec.Mover, 0.18, { Position = UDim2.new(0.5, 0, 0.5, -20) }, Enum.EasingStyle.Back)
		Theme.tween(rec.Scale, 0.18, { Scale = 1.07 }, Enum.EasingStyle.Back)
		Theme.tween(rec.Stroke, 0.18, { Thickness = 4.5 })
		Theme.tween(rec.Glow, 0.18, { BackgroundTransparency = 0.7 })
	else
		Theme.tween(rec.Mover, 0.2, { Position = UDim2.fromScale(0.5, 0.5), Rotation = 0 })
		Theme.tween(rec.Scale, 0.2, { Scale = 1 })
		Theme.tween(rec.Stroke, 0.2, { Thickness = 2.5 })
		Theme.tween(rec.Glow, 0.2, { BackgroundTransparency = 1 })
	end
end

local function playPickAnimation(index)
	if pickedIndex == index and cards[index] and cards[index].Animated then
		return
	end
	pickedIndex = index
	local chosen = cards[index]
	if not chosen then
		return
	end
	chosen.Animated = true
	Sfx.Play("CardPick")

	-- the chosen card flies to the centre of the screen
	local viewport = workspace.CurrentCamera.ViewportSize
	local center = cardCenter(chosen)
	local rowScale = row:FindFirstChildOfClass("UIScale")
	local s = rowScale and rowScale.Scale or 1
	local dx = (viewport.X / 2 - center.X) / s
	chosen.Back.Visible = false
	chosen.Front.Visible = true
	chosen.Card.GroupTransparency = 0
	chosen.Flipper.Size = UDim2.fromScale(1, 1)
	chosen.Holder.ZIndex = 5
	Theme.tween(chosen.Mover, 0.45, { Position = UDim2.new(0.5, dx, 0.5, -10), Rotation = 0 }, Enum.EasingStyle.Quint)
	chosen.Scale.Scale = 1.3
	Theme.tween(chosen.Scale, 0.5, { Scale = 1.18 }, Enum.EasingStyle.Back)
	Theme.tween(chosen.Stroke, 0.2, { Thickness = 5, Color = Color3.new(1, 1, 1) })
	chosen.Flash.BackgroundTransparency = 0
	Theme.tween(chosen.Flash, 0.5, { BackgroundTransparency = 1 })
	chosen.Glow.BackgroundTransparency = 0.35
	Theme.tween(chosen.Glow, 0.8, { BackgroundTransparency = 0.6 })
	task.delay(0.3, function()
		if not chosen.Mover.Parent then
			return
		end
		local c = cardCenter(chosen)
		Theme.burst(gui, c, chosen.Color, 26, 260, 10)
		Theme.burst(gui, c, Color3.new(1, 1, 1), 12, 180, 6)
		Theme.ring(gui, c, chosen.Color, 520, 10)
		Theme.tween(chosen.Stroke, 0.4, { Color = chosen.Color })
		Theme.shine(chosen.Card, 0.6, false, 0.5)
	end)

	-- the others fall away
	for i, rec in ipairs(cards) do
		if i ~= index then
			task.delay(math.abs(i - index) * 0.05, function()
				Theme.tween(rec.Mover, 0.55, {
					Position = UDim2.new(0.5, 0, 0.5, 420),
					Rotation = (i < index) and -18 or 18,
				}, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
				Theme.tween(rec.Card, 0.45, { GroupTransparency = 1 })
				Theme.tween(rec.Glow, 0.3, { BackgroundTransparency = 1 })
				Theme.tween(rec.GlowInner, 0.3, { BackgroundTransparency = 1 })
			end)
		end
	end

	local def = chosen.Def
	if isPicker then
		title.Text = "YOU PICKED " .. string.upper(def.Name)
	else
		local opp = ClientState.GetOpponentEntry()
		title.Text = (opp and string.upper(opp.Name) or "OPPONENT") .. " PICKED " .. string.upper(def.Name)
	end
	title.TextColor3 = chosen.Color
	Theme.pop(title, 0.2)
	subtitle.Text = "STACKS  " .. (def.Stacking or "")
end

----------------------------------------------------------------------------
-- Open / close
----------------------------------------------------------------------------
local function clearCards()
	for _, rec in ipairs(cards) do
		rec.Holder:Destroy()
	end
	table.clear(cards)
end

local function open(snapshot)
	openToken += 1
	local token = openToken
	clearCards()
	isOpen = true
	pickedIndex = nil
	lastTimerSecond = nil
	isPicker = snapshot.PickerUserId == player.UserId

	gui.Enabled = true
	unlocker.Visible = true
	ClientState.SetMenu("Pick", true)
	overlay.BackgroundTransparency = 1
	Theme.tween(overlay, 0.35, { BackgroundTransparency = 0.3 })
	-- title slides down
	title.Position = UDim2.new(0.5, 0, 0.1, -40)
	title.TextTransparency = 1
	subtitle.TextTransparency = 1
	Theme.tween(title, 0.5, { Position = UDim2.fromScale(0.5, 0.1), TextTransparency = 0 }, Enum.EasingStyle.Quint)
	Theme.tween(subtitle, 0.6, { TextTransparency = 0 })

	if isPicker then
		title.Text = "PICK A POWER-UP"
		title.TextColor3 = Palette.UIText
		subtitle.Text = "You lost the round. Choose one card - it stacks for the rest of the match."
	else
		local opp = ClientState.GetOpponentEntry()
		title.Text = (opp and string.upper(opp.Name) or "OPPONENT") .. " IS CHOOSING"
		title.TextColor3 = Palette.UISubText
		subtitle.Text = "You won the round. Here's what they could get..."
	end

	-- whose power-ups are we showing stacks for?
	local pickerEntry
	for _, entry in ipairs(snapshot.Players or {}) do
		if entry.UserId == snapshot.PickerUserId then
			pickerEntry = entry
		end
	end
	local owned = pickerEntry and pickerEntry.PowerUps or {}

	for i, id in ipairs(snapshot.Cards or {}) do
		local def = PowerUps.Get(id)
		if def then
			local rec = makeCard(i, def, owned[id] or 0)
			table.insert(cards, rec)
			rec.Button.MouseEnter:Connect(function()
				setHover(rec, true)
			end)
			rec.Button.MouseLeave:Connect(function()
				setHover(rec, false)
			end)
			rec.Button.Activated:Connect(function()
				if isPicker and not pickedIndex and rec.Flipped then
					if practiceCallback then
						local callback = practiceCallback
						playPickAnimation(i)
						callback(id)
						task.delay(1.8, function()
							if practiceCallback == callback then
								PickScreen.Close()
							end
						end)
					else
						Remotes.Get("PickCard"):FireServer(i)
						playPickAnimation(i)
					end
				end
			end)
			dealAndFlip(rec, 0.2 + (i - 1) * 0.16, token)
		end
	end
end

local function close()
	if not isOpen then
		return
	end
	practiceCallback = nil
	isOpen = false
	openToken += 1
	local token = openToken
	unlocker.Visible = false
	ClientState.SetMenu("Pick", false)
	Theme.tween(overlay, 0.3, { BackgroundTransparency = 1 })
	Theme.tween(title, 0.25, { TextTransparency = 1 })
	Theme.tween(subtitle, 0.25, { TextTransparency = 1 })
	for _, rec in ipairs(cards) do
		Theme.tween(rec.Card, 0.25, { GroupTransparency = 1 })
		Theme.tween(rec.Scale, 0.25, { Scale = 0.85 })
		Theme.tween(rec.Glow, 0.2, { BackgroundTransparency = 1 })
		Theme.tween(rec.GlowInner, 0.2, { BackgroundTransparency = 1 })
	end
	task.delay(0.35, function()
		if token == openToken then
			clearCards()
			gui.Enabled = false
		end
	end)
end

function PickScreen.Close()
	close()
end

function PickScreen.IsPracticeOpen()
	return isOpen and practiceCallback ~= nil
end

--[[
	Opens the real pick screen with `cardIds` for solo practice (from the
	Power-Up Lab). `onPick(id)` is called with the chosen power-up.
]]
function PickScreen.OpenPractice(cardIds, owned, onPick)
	open({
		Cards = cardIds,
		PickerUserId = player.UserId,
		Players = { { UserId = player.UserId, PowerUps = owned or {} } },
	})
	practiceCallback = onPick
	title.Text = "PICK A POWER-UP"
	title.TextColor3 = Palette.UIText
	subtitle.Text = "Practice pick - the card gets added to your Power-Up Lab.  (B to close)"
end

function PickScreen.OnState(snapshot, old)
	if practiceCallback then
		if not snapshot.InMatch then
			return -- practice pick stays open in the lobby
		end
		close()
	end
	local phase = snapshot.Phase
	if phase == "Pick" then
		if not isOpen or old.Phase ~= "Pick" then
			open(snapshot)
		end
	elseif phase == "PickReveal" then
		local wasOpen = isOpen
		if not wasOpen then
			open(snapshot)
		end
		if snapshot.PickedIndex then
			-- wait for the deal + flip if we opened late
			task.delay(wasOpen and 0 or 1.6, function()
				playPickAnimation(snapshot.PickedIndex)
			end)
		end
	elseif isOpen then
		close()
	end
end

----------------------------------------------------------------------------
-- Per-frame: idle float, hover tilt, timer
----------------------------------------------------------------------------
local function update()
	if not isOpen then
		return
	end
	local t = os.clock()
	local mouse = UserInputService:GetMouseLocation()
	for _, rec in ipairs(cards) do
		if rec.Flipped and not pickedIndex then
			-- gentle float + breathing glow
			local bob = UDim2.new(0.5, 0, 0.5, math.sin(t * 2 + rec.Phase) * 3)
			rec.Flipper.Position = bob
			rec.Glow.Position = bob
			rec.GlowInner.Position = bob
			rec.GlowInner.BackgroundTransparency = rec.BaseGlow + math.sin(t * 2.4 + rec.Phase) * 0.06
			-- tilt toward the mouse while hovered
			if rec.Hovered then
				local center = cardCenter(rec)
				local dx = math.clamp((mouse.X - center.X) / (CARD_W / 2), -1, 1)
				rec.Mover.Rotation = dx * 3
			end
		end
	end

	local snapshot = ClientState.Snapshot
	if snapshot.Phase == "Pick" and not practiceCallback then
		local left = ClientState.TimeLeft() or 0
		timerTrack.Visible = true
		timerFill.Size = UDim2.fromScale(math.clamp(left / Config.Match.PickTime, 0, 1), 1)
		local urgent = left < 5
		timerFill.BackgroundColor3 = urgent and Palette.UIDanger or Palette.UIAccent
		local second = math.ceil(left)
		timerText.Text = tostring(second)
		timerText.TextColor3 = urgent and Palette.UIDanger or Palette.UIText
		if second ~= lastTimerSecond then
			lastTimerSecond = second
			if urgent and not pickedIndex then
				Theme.pop(timerText, 0.35)
				Sfx.Play("Countdown", { Pitch = 1.4, Volume = 0.5 })
			end
		end
	else
		timerTrack.Visible = false
		timerText.Text = ""
	end
end

function PickScreen.Start(playerGui)
	gui = Theme.screen("PickScreen", 5, playerGui)
	gui.Enabled = false

	overlay = Theme.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Palette.UIBackground,
		BackgroundTransparency = 1,
		Parent = gui,
	})
	unlocker = Theme.mouseUnlocker(gui)

	title = Theme.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.1),
		Size = UDim2.fromOffset(1000, 56),
		TextSize = 46,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = gui,
	})
	subtitle = Theme.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.1, 58),
		Size = UDim2.fromOffset(1000, 24),
		TextSize = 17,
		TextColor3 = Palette.UISubText,
		FontFace = Theme.Font(Enum.FontWeight.Medium),
		Parent = gui,
	})

	row = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.54),
		Size = UDim2.fromOffset(5 * CARD_W + 4 * GAP, CARD_H + 80),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		Theme.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, GAP),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	-- shrink the cards on small screens
	local rowScale = Theme.new("UIScale", { Parent = row })
	local function fit()
		local viewport = workspace.CurrentCamera.ViewportSize
		rowScale.Scale = math.min(1, (viewport.X - 40) / row.Size.X.Offset, (viewport.Y * 0.62) / row.Size.Y.Offset)
	end
	fit()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)

	timerTrack = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.88),
		Size = UDim2.fromOffset(460, 6),
		BackgroundColor3 = Palette.UIPanelLight,
		Parent = gui,
	})
	Theme.corner(timerTrack, 3)
	timerFill = Theme.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Palette.UIAccent,
		Parent = timerTrack,
	})
	Theme.corner(timerFill, 3)
	timerText = Theme.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.88, 12),
		Size = UDim2.fromOffset(80, 30),
		TextSize = 26,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = gui,
	})

	RunService.RenderStepped:Connect(update)
end

return PickScreen
