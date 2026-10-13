--[[
	PickScreen.lua  (Client.ui.PickScreen)

	Between rounds the player who DIED picks 1 of 5 power-up cards.
		* cards flip in one after another
		* glowing border in the rarity colour, flat icon, name, description
		* Legendary cards shimmer and play a special sound when they flip
		* hover = lift + glow, click = pick animation
		* the winner sees the same cards but can't pick
		* 15 second timer (server picks randomly if it runs out)
		* the mouse is unlocked while this screen is open
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
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

local CARD_W, CARD_H = 196, 290

local PickScreen = {}

local gui, overlay, title, subtitle, timerTrack, timerFill, timerText, row, unlocker
local cards = {} -- list of card records
local isOpen = false
local isPicker = false
local pickedIndex = nil
local openToken = 0
local practiceCallback = nil -- set when opened from the Power-Up Lab (solo practice)

----------------------------------------------------------------------------
-- Card construction
----------------------------------------------------------------------------
local function makeCard(index, def, ownedStacks)
	local rarity = Config.Rarity[def.Rarity]
	local rec = { Index = index, Def = def, Flipped = false }

	local holder = Theme.new("Frame", {
		Name = "Card" .. index,
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		BackgroundTransparency = 1,
		LayoutOrder = index,
		Parent = row,
	})

	-- soft glow behind the card
	local glow = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, CARD_H + 18),
		BackgroundColor3 = rarity.Color,
		BackgroundTransparency = 0.82,
		Parent = holder,
	})
	Theme.corner(glow, 22)

	local card = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, CARD_H), -- width 0 = not flipped in yet
		BackgroundColor3 = Palette.UIPanel,
		ClipsDescendants = true,
		Parent = holder,
	})
	Theme.corner(card, 14)
	local stroke = Theme.stroke(card, rarity.Color, 3, 0)
	local scale = Theme.new("UIScale", { Parent = card })

	-- FRONT
	local front = Theme.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = card,
	})
	-- rarity tint strip at the top
	local strip = Theme.new("Frame", {
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.new(1, -16, 0, 26),
		BackgroundColor3 = rarity.Color,
		BackgroundTransparency = 0.75,
		Parent = front,
	})
	Theme.corner(strip, 8)
	Theme.label({
		Size = UDim2.fromScale(1, 1),
		Text = string.upper(def.Rarity),
		TextSize = 13,
		TextColor3 = rarity.Color:Lerp(Color3.new(1, 1, 1), 0.35),
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = strip,
	})
	local icon = Icons.Create(def, 86)
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, 54)
	icon.Parent = front
	Theme.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 152),
		Size = UDim2.new(1, -20, 0, 26),
		Text = def.Name,
		TextSize = 21,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = front,
	})
	Theme.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 182),
		Size = UDim2.new(1, -26, 0, 54),
		Text = def.Description,
		TextSize = 14,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Palette.UISubText,
		FontFace = Theme.Font(Enum.FontWeight.Medium),
		Parent = front,
	})
	-- what picking this again would add (power-ups are built to stack)
	if def.Stacking then
		Theme.label({
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -30),
			Size = UDim2.new(1, -20, 0, 28),
			Text = "STACKS: " .. def.Stacking,
			TextSize = 11,
			TextWrapped = true,
			TextColor3 = rarity.Color:Lerp(Color3.new(1, 1, 1), 0.3),
			FontFace = Theme.Font(Enum.FontWeight.Bold),
			Parent = front,
		})
	end
	if ownedStacks > 0 then
		Theme.label({
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -10),
			Size = UDim2.new(1, 0, 0, 18),
			Text = ("OWNED x%d  >  x%d"):format(ownedStacks, ownedStacks + 1),
			TextSize = 12,
			TextColor3 = rarity.Color,
			Parent = front,
		})
	end

	-- Legendary shimmer: a bright diagonal band sliding across the card
	if def.Rarity == "Legendary" then
		local shimmer = Theme.new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = 3,
			Parent = front,
		})
		Theme.corner(shimmer, 14)
		local gradient = Theme.new("UIGradient", {
			Rotation = 25,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.42, 1),
				NumberSequenceKeypoint.new(0.5, 0.55),
				NumberSequenceKeypoint.new(0.58, 1),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Offset = Vector2.new(-1, 0),
			Parent = shimmer,
		})
		rec.Shimmer = TweenService:Create(
			gradient,
			TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, false, 0.5),
			{ Offset = Vector2.new(1, 0) }
		)
	end

	-- BACK (shown during the first half of the flip)
	local back = Theme.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = rarity.Color:Lerp(Palette.UIBackground, 0.55),
		Parent = card,
	})
	Theme.corner(back, 14)
	Theme.label({
		Size = UDim2.fromScale(1, 1),
		Text = "?",
		TextSize = 64,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		TextColor3 = rarity.Color,
		Parent = back,
	})

	-- dim layer used when another card is picked
	local dim = Theme.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Palette.UIBackground,
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = card,
	})
	Theme.corner(dim, 14)

	local button = Theme.new("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 5,
		Parent = card,
	})

	rec.Holder, rec.Card, rec.Glow, rec.Stroke, rec.Scale = holder, card, glow, stroke, scale
	rec.Front, rec.Back, rec.Dim, rec.Button = front, back, dim, button
	return rec
end

----------------------------------------------------------------------------
-- Animations
----------------------------------------------------------------------------
local function flipIn(rec, delay, token)
	task.delay(delay, function()
		if token ~= openToken then
			return
		end
		local rarity = rec.Def.Rarity
		-- back face grows in...
		Theme.tween(rec.Card, 0.14, { Size = UDim2.fromOffset(CARD_W, CARD_H) })
		Theme.tween(rec.Glow, 0.14, { Size = UDim2.fromOffset(CARD_W + 18, CARD_H + 18) })
		task.wait(0.2)
		-- ...flips edge-on...
		Theme.tween(rec.Card, 0.1, { Size = UDim2.fromOffset(0, CARD_H) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.wait(0.1)
		if token ~= openToken then
			return
		end
		-- ...and the front flips open
		rec.Back.Visible = false
		rec.Front.Visible = true
		Theme.tween(rec.Card, 0.22, { Size = UDim2.fromOffset(CARD_W, CARD_H) }, Enum.EasingStyle.Back)
		rec.Flipped = true
		if rarity == "Legendary" then
			Sfx.Play("CardLegendary")
			if rec.Shimmer then
				rec.Shimmer:Play()
			end
			-- pulse the glow
			rec.Glow.BackgroundTransparency = 0.35
			Theme.tween(rec.Glow, 0.8, { BackgroundTransparency = 0.7 })
		else
			Sfx.Play("CardFlip", { Pitch = 1 + Config.Rarity[rarity].Order * 0.08 })
		end
	end)
end

local function setHover(rec, hovered)
	if not isPicker or pickedIndex or not rec.Flipped then
		return
	end
	if hovered then
		Sfx.Play("CardHover")
		Theme.tween(rec.Card, 0.15, { Position = UDim2.new(0.5, 0, 0.5, -16) }, Enum.EasingStyle.Back)
		Theme.tween(rec.Glow, 0.15, { Position = UDim2.new(0.5, 0, 0.5, -16), BackgroundTransparency = 0.5 })
		Theme.tween(rec.Scale, 0.15, { Scale = 1.05 })
		Theme.tween(rec.Stroke, 0.15, { Thickness = 5 })
	else
		Theme.tween(rec.Card, 0.15, { Position = UDim2.fromScale(0.5, 0.5) })
		Theme.tween(rec.Glow, 0.15, { Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 0.82 })
		Theme.tween(rec.Scale, 0.15, { Scale = 1 })
		Theme.tween(rec.Stroke, 0.15, { Thickness = 3 })
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

	for i, rec in ipairs(cards) do
		if i == index then
			rec.Back.Visible = false
			rec.Front.Visible = true
			rec.Card.Size = UDim2.fromOffset(CARD_W, CARD_H)
			Theme.tween(rec.Card, 0.2, { Position = UDim2.new(0.5, 0, 0.5, -26) }, Enum.EasingStyle.Back)
			Theme.tween(rec.Glow, 0.2, {
				Position = UDim2.new(0.5, 0, 0.5, -26),
				Size = UDim2.fromOffset(CARD_W + 40, CARD_H + 40),
				BackgroundTransparency = 0.3,
			})
			rec.Scale.Scale = 1.25
			Theme.tween(rec.Scale, 0.35, { Scale = 1.12 }, Enum.EasingStyle.Back)
			Theme.tween(rec.Stroke, 0.2, { Thickness = 6, Color = Color3.new(1, 1, 1) })
			task.delay(0.25, function()
				if rec.Stroke.Parent then
					Theme.tween(rec.Stroke, 0.4, { Color = Config.Rarity[rec.Def.Rarity].Color })
				end
			end)
		else
			Theme.tween(rec.Scale, 0.3, { Scale = 0.86 })
			Theme.tween(rec.Dim, 0.3, { BackgroundTransparency = 0.35 })
			Theme.tween(rec.Glow, 0.3, { BackgroundTransparency = 1 })
			Theme.tween(rec.Card, 0.3, { Position = UDim2.new(0.5, 0, 0.5, 12) })
		end
	end

	local def = chosen.Def
	if isPicker then
		title.Text = "YOU PICKED " .. string.upper(def.Name)
	else
		local opp = ClientState.GetOpponentEntry()
		title.Text = (opp and string.upper(opp.Name) or "OPPONENT") .. " PICKED " .. string.upper(def.Name)
	end
	title.TextColor3 = Config.Rarity[def.Rarity].Color
	subtitle.Text = "Stacks for the rest of the match"
end

----------------------------------------------------------------------------
-- Open / close
----------------------------------------------------------------------------
local function clearCards()
	for _, rec in ipairs(cards) do
		if rec.Shimmer then
			rec.Shimmer:Cancel()
		end
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
	isPicker = snapshot.PickerUserId == player.UserId

	gui.Enabled = true
	unlocker.Visible = true
	ClientState.SetMenu("Pick", true)
	overlay.BackgroundTransparency = 1
	Theme.tween(overlay, 0.3, { BackgroundTransparency = 0.25 })

	if isPicker then
		title.Text = "PICK A POWER-UP"
		title.TextColor3 = Palette.UIText
		subtitle.Text = "You lost the round - choose one card. It stacks for the rest of the match."
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
						task.delay(1.6, function()
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
			flipIn(rec, 0.25 + (i - 1) * 0.22, token)
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
	Theme.tween(overlay, 0.25, { BackgroundTransparency = 1 })
	for _, rec in ipairs(cards) do
		Theme.tween(rec.Scale, 0.2, { Scale = 0 })
	end
	task.delay(0.3, function()
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
	Opens the real pick screen with `cards` for solo practice (from the
	Power-Up Lab). `onPick(id)` is called with the chosen power-up.
]]
function PickScreen.OpenPractice(cards, owned, onPick)
	open({
		Cards = cards,
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
			-- wait for the flip-ins if we opened late
			task.delay(wasOpen and 0 or 1.4, function()
				playPickAnimation(snapshot.PickedIndex)
			end)
		end
	elseif isOpen then
		close()
	end
end

local function update()
	if not isOpen then
		return
	end
	local snapshot = ClientState.Snapshot
	if snapshot.Phase == "Pick" then
		local left = ClientState.TimeLeft() or 0
		timerTrack.Visible = true
		timerFill.Size = UDim2.fromScale(math.clamp(left / Config.Match.PickTime, 0, 1), 1)
		timerFill.BackgroundColor3 = left < 5 and Palette.UIDanger or Palette.UIAccent
		timerText.Text = tostring(math.ceil(left))
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
		Position = UDim2.fromScale(0.5, 0.12),
		Size = UDim2.fromOffset(900, 56),
		TextSize = 46,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = overlay,
	})
	subtitle = Theme.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.12, 58),
		Size = UDim2.fromOffset(900, 24),
		TextSize = 17,
		TextColor3 = Palette.UISubText,
		FontFace = Theme.Font(Enum.FontWeight.Medium),
		Parent = overlay,
	})

	row = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.53),
		Size = UDim2.fromOffset(5 * CARD_W + 4 * 20, CARD_H + 60),
		BackgroundTransparency = 1,
		Parent = overlay,
	}, {
		Theme.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 20),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	-- shrink the cards on small screens
	local rowScale = Theme.new("UIScale", { Parent = row })
	local function fit()
		local viewport = workspace.CurrentCamera.ViewportSize
		rowScale.Scale = math.min(1, (viewport.X - 40) / row.Size.X.Offset, (viewport.Y * 0.6) / row.Size.Y.Offset)
	end
	fit()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)

	timerTrack = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.86),
		Size = UDim2.fromOffset(420, 8),
		BackgroundColor3 = Palette.UIPanelLight,
		Parent = overlay,
	})
	Theme.corner(timerTrack, 4)
	timerFill = Theme.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Palette.UIAccent,
		Parent = timerTrack,
	})
	Theme.corner(timerFill, 4)
	timerText = Theme.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.86, 14),
		Size = UDim2.fromOffset(80, 30),
		TextSize = 26,
		FontFace = Theme.Font(Enum.FontWeight.Heavy),
		Parent = overlay,
	})

	RunService.RenderStepped:Connect(update)
end

return PickScreen
