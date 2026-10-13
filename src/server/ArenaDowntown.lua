--[[
	ArenaDowntown.lua  (ServerScriptService.Server.ArenaDowntown)

	"Downtown": a detailed city block built from flat-coloured parts.
	The map is mirrored across X = 0, so both spawns are identical.

	LAYOUT (top view, X = long axis, spawns at the far left / right)

	        N  skyline (perimeter buildings)
	   [Apartments]-catwalk-[Office tower]   [CITY HALL + clock tower]   (mirrored)
	   ==== sidewalk / lamps / trees ==========================================
	   SPAWN  >>>  bus, cars, barriers  >>>  PLAZA + FOUNTAIN  <<<  ...  SPAWN
	   ==== sidewalk ===========================================================
	   [park + billboard]                                     [park]
	   ===== ELEVATED TRAIN TRACK (parked train in the middle) =====  (stairs up at both ends)
	   [parking lot]   [market stalls]   [shop]
	        S  skyline

	Sightlines: the avenue (long, broken up by the bus/cars/fountain), the
	train deck (long, broken by the train), rooftops (high ground).
	Verticality: steel fire escapes up the apartments (24), office tower (48)
	and city hall (26), the clock tower (55), the train deck (22) and the
	train roof. Wall runs: building faces, the bus, the train, billboards.

	DETAIL vs COLLISION
	  Buildings are a solid box; pilasters, window frames, glass, cornices,
	  storefronts and signs are detail parts (builder.decor) that don't
	  collide or stop bullets, so walls stay flat and clean to wall run on
	  and nothing snags you. Fire escapes and stairs are an invisible smooth
	  ramp under the visible steps, with invisible railing walls so you
	  can't fall off the landings. Car bodies collide; their trim doesn't.
	  Tree leaves (builder.soft) block bullets and sight but not movement.

	Colours come from Config.MapPalette.
]]

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local C = Config.MapPalette
local P = Config.Palette
local V = Vector3.new
local rad = math.rad

local ArenaDowntown = {}

----------------------------------------------------------------------------
-- SMALL HELPERS
----------------------------------------------------------------------------

-- A bar from point a to point c (w wide, h tall), e.g. a handrail.
local function bar(b, a, c, w, h, color, m)
	return b.part(V(w, h, (c - a).Magnitude), CFrame.lookAt((a + c) / 2, c), color, m)
end

-- Invisible wall that only blocks players (not bullets, not raycasts).
local function playerWall(b, size, pos, m)
	local parts = b.invisible(b.block(size, pos, C.Metal, m))
	for _, part in ipairs(parts) do
		part.CanQuery = false
	end
	return parts
end

local function neon(b, parts)
	return b.material(parts, Enum.Material.Neon)
end

local function glass(b, parts)
	return b.material(parts, Enum.Material.SmoothPlastic, 0.18)
end

----------------------------------------------------------------------------
-- STAIRS (concrete or steel): an invisible ramp you walk on + real steps
----------------------------------------------------------------------------
--[[
	lowPoint: centre of the bottom edge (on the ground), dir: the way it
	climbs, length/height/width in studs.
	options.Solid   concrete steps filled down to the ground (default: steel treads)
	options.Rails   handrails on both sides (default true)
]]
local function stairs(b, lowPoint, dir, length, height, width, color, m, options)
	options = options or {}
	dir = V(dir.X, 0, dir.Z).Unit
	local side = V(-dir.Z, 0, dir.X)
	b.invisible(b.ramp(lowPoint, dir, length, height, width, color, m))

	local count = math.max(3, math.floor(height / 0.8 + 0.5))
	local run, rise = length / count, height / count
	local look = CFrame.lookAt(Vector3.zero, dir)
	b.decor(function()
		for j = 0, count - 1 do
			local along = lowPoint + dir * ((j + 0.5) * run)
			if options.Solid then
				local h = (j + 1) * rise
				b.part(V(width, h, run + 0.02), CFrame.new(along + V(0, h / 2, 0)) * look, color, m)
				b.part(V(width + 0.02, 0.12, 0.3), CFrame.new(along + dir * (run / 2 - 0.15) + V(0, h - 0.06, 0)) * look, C.Trim, m) -- nosing
			else
				local top = (j + 1) * rise
				b.part(V(width - 0.3, 0.25, run + 0.05), CFrame.new(along + V(0, top - 0.125, 0)) * look, color, m)
			end
		end
		local top = lowPoint + dir * length + V(0, height, 0)
		for _, s in ipairs({ -1, 1 }) do
			local edge = side * s * (width / 2)
			-- side stringer / cheek wall
			bar(b, lowPoint + edge + V(0, 0.1, 0), top + edge + V(0, 0.1, 0), 0.3, options.Solid and 1.4 or 0.9, options.Solid and C.Concrete or C.Dark, m)
			if options.Rails ~= false then
				local railLow = lowPoint + edge + V(0, 3.2, 0)
				local railTop = top + edge + V(0, 3.2, 0)
				bar(b, railLow, railTop, 0.22, 0.22, C.Dark, m)
				for t = 0, 1, 0.5 do
					local post = lowPoint:Lerp(top, t) + edge
					b.block(V(0.2, 3.2, 0.2), post + V(0, 1.6, 0), C.Dark, m)
				end
			end
		end
	end)
end

----------------------------------------------------------------------------
-- BUILDINGS
----------------------------------------------------------------------------

-- Position on a building face. u = along the face, out = distance out from the wall.
local function facePos(bd, face, u, y, out)
	if face == "N" then
		return V(bd.cx + u, y, bd.cz + bd.d / 2 + out)
	elseif face == "S" then
		return V(bd.cx + u, y, bd.cz - bd.d / 2 - out)
	elseif face == "E" then
		return V(bd.cx + bd.w / 2 + out, y, bd.cz + u)
	end
	return V(bd.cx - bd.w / 2 - out, y, bd.cz + u)
end

-- Size of a slab on a face: `along` the face, `height` tall, `thick` out from it.
local function faceSize(face, along, height, thick)
	if face == "N" or face == "S" then
		return V(along, height, thick)
	end
	return V(thick, height, along)
end

local function faceNormal(face)
	return ({ N = V(0, 0, 1), S = V(0, 0, -1), E = V(1, 0, 0), W = V(-1, 0, 0) })[face]
end

-- Shop fronts across the ground floor of one face: big glass windows, a
-- door, a sign band with "lettering" and striped awnings.
local function storefront(b, bd, face, count, start, spacing, m, seed)
	local n = faceNormal(face)
	local span = (count) * spacing
	b.block(faceSize(face, span + 1, 1.8, 0.7), facePos(bd, face, 0, 9.4, 0.35), C.Dark, m) -- sign band
	for i = 0, count - 1 do
		local u = start + i * spacing
		local isDoor = i == math.floor(count / 2)
		b.block(faceSize(face, spacing - 1.1, 6.6, 0.16), facePos(bd, face, u, 4.9, 0.08), C.FrameDark, m) -- frame
		if isDoor then
			b.block(faceSize(face, 3.4, 6.2, 0.3), facePos(bd, face, u, 4.7, 0.15), C.Dark, m)
			glass(b, b.block(faceSize(face, 2.6, 4, 0.34), facePos(bd, face, u, 5.2, 0.17), C.Glass, m))
			b.block(faceSize(face, 0.25, 0.9, 0.5), facePos(bd, face, u + 0.9, 4.2, 0.4), C.Rim, m) -- handle
		else
			glass(b, b.block(faceSize(face, spacing - 1.8, 5.6, 0.2), facePos(bd, face, u, 4.9, 0.14), C.Glass, m))
			b.block(faceSize(face, spacing - 1.8, 0.25, 0.3), facePos(bd, face, u, 6.3, 0.2), C.FrameDark, m) -- transom bar
			b.block(faceSize(face, spacing - 1, 0.6, 0.9), facePos(bd, face, u, 1.9, 0.45), C.Stone, m) -- stall riser
		end
		-- awning (sloping down and out)
		local awning = C.Awning[((seed + i) % #C.Awning) + 1]
		local pos = facePos(bd, face, u, 8.1, 1.7)
		local frame = CFrame.lookAt(pos, pos + n) * CFrame.Angles(rad(-22), 0, 0)
		b.part(V(spacing - 1.2, 0.3, 3.6), frame, awning, m)
		b.part(V(spacing - 1.2, 0.8, 0.15), frame * CFrame.new(0, -0.45, -1.8), C.RoadWhite, m) -- valance
		-- lettering on the sign band
		local letters = 2 + (seed + i) % 3
		for k = 1, letters do
			local lu = u - (letters - 1) * 0.8 + (k - 1) * 1.6
			neon(b, b.block(faceSize(face, 1.1, 0.9, 0.2), facePos(bd, face, lu, 9.4, 0.75), k == 1 and awning or C.LampLight, m))
		end
	end
end

-- Windows, pilasters and ledges on one face.
local function facade(b, bd, face, h, accent, m, options)
	local span = (face == "N" or face == "S") and bd.w or bd.d
	local spacing = options.WindowSpacing or 7
	local fh = options.FloorHeight or 8
	local count = math.floor((span - 6) / spacing)
	if count < 1 then
		return
	end
	local start = -(count - 1) * spacing / 2
	local floors = math.floor((h - 6) / fh)
	local shop = options.Storefront and table.find(options.Storefront, face) ~= nil
	local frameColor = C.FrameDark

	-- pilasters between the window bays (they give the wall its depth)
	for j = 0, count do
		local u = start + (j - 0.5) * spacing
		b.block(faceSize(face, 1.3, h - 1.6, 0.9), facePos(bd, face, u, 1.6 + (h - 1.6) / 2, 0.45), accent, m)
	end

	if shop then
		storefront(b, bd, face, count, start, spacing, m, math.floor(bd.cx + bd.cz) % 3)
	end

	for f = shop and 1 or 0, floors - 1 do
		local y = 6 + f * fh
		-- ledge under each floor of windows
		b.block(faceSize(face, count * spacing + 1.6, 0.5, 0.7), facePos(bd, face, 0, y - 2.5, 0.35), accent, m)
		if options.Simple then
			-- far buildings: one ribbon of glass per floor
			glass(b, b.block(faceSize(face, count * spacing - 0.4, 4, 0.2), facePos(bd, face, 0, y, 0.1), C.Window, m))
		else
			for i = 0, count - 1 do
				local u = start + i * spacing
				local lit = ((i * 7 + f * 3 + #face) % 5) == 0
				b.block(faceSize(face, 3.7, 4.7, 0.12), facePos(bd, face, u, y, 0.06), frameColor, m) -- frame
				glass(b, b.block(faceSize(face, 3.1, 4.1, 0.12), facePos(bd, face, u, y, 0.12), lit and C.WindowLit or C.Window, m))
				b.block(faceSize(face, 0.22, 4.1, 0.12), facePos(bd, face, u, y, 0.22), frameColor, m) -- mullion
				b.block(faceSize(face, 4.3, 0.5, 0.45), facePos(bd, face, u, y + 2.6, 0.22), accent, m) -- lintel
				b.block(faceSize(face, 4, 0.3, 0.8), facePos(bd, face, u, y - 2.25, 0.4), accent, m) -- sill
			end
		end
	end
end

--[[
	A building: solid box + roof + parapet (all collide), plus detail.
	faces: which faces ("N","S","E","W") get windows.
	options: WindowSpacing, FloorHeight, NoParapet, Simple (ribbon windows),
	         Storefront = { faces with shops on the ground floor }
]]
local function building(b, cx, cz, w, d, h, color, faces, m, options)
	options = options or {}
	local bd = { cx = cx, cz = cz, w = w, d = d }
	local accent = color:Lerp(C.Stone, 0.35)

	-- SOLID
	b.block(V(w, h, d), V(cx, h / 2, cz), color, m)
	b.block(V(w + 0.8, 0.8, d + 0.8), V(cx, h + 0.4, cz), C.Roof, m)
	if not options.NoParapet then
		b.block(V(w + 0.8, 1.6, 0.8), V(cx, h + 1.6, cz + d / 2), color, m)
		b.block(V(w + 0.8, 1.6, 0.8), V(cx, h + 1.6, cz - d / 2), color, m)
		b.block(V(0.8, 1.6, d - 0.8), V(cx + w / 2, h + 1.6, cz), color, m)
		b.block(V(0.8, 1.6, d - 0.8), V(cx - w / 2, h + 1.6, cz), color, m)
	end

	-- DETAIL
	b.decor(function()
		b.block(V(w + 1, 1.6, d + 1), V(cx, 0.8, cz), C.Trim, m) -- plinth
		-- two-step cornice under the roof edge
		b.block(V(w + 2.2, 0.7, d + 2.2), V(cx, h - 0.35, cz), accent, m)
		b.block(V(w + 1.4, 0.6, d + 1.4), V(cx, h - 1.0, cz), C.Trim, m)
		if not options.NoParapet then
			b.block(V(w + 1.3, 0.3, 1.3), V(cx, h + 2.55, cz + d / 2), C.Stone, m) -- coping
			b.block(V(w + 1.3, 0.3, 1.3), V(cx, h + 2.55, cz - d / 2), C.Stone, m)
			b.block(V(1.3, 0.3, d - 1.3), V(cx + w / 2, h + 2.55, cz), C.Stone, m)
			b.block(V(1.3, 0.3, d - 1.3), V(cx - w / 2, h + 2.55, cz), C.Stone, m)
		end
		-- belt courses every few floors
		for y = 18, h - 8, 24 do
			b.block(V(w + 1.2, 0.7, d + 1.2), V(cx, y, cz), C.Trim, m)
		end
		for _, face in ipairs(faces or {}) do
			facade(b, bd, face, h, accent, m, options)
		end
	end)
end

-- Rooftop clutter: stair bulkhead with a door, vents and pipes.
local function rooftop(b, x, z, h, m, flip)
	local s = flip and -1 or 1
	b.block(V(7, 5, 6), V(x, h + 3.3, z), C.Concrete, m) -- bulkhead (solid cover)
	b.decor(function()
		b.block(V(7.6, 0.5, 6.6), V(x, h + 6, z), C.Roof, m)
		b.block(V(2.8, 4, 0.2), V(x, h + 2.8, z + s * 3.05), C.Dark, m) -- door
		b.cylinder(3, 1, V(x + 6, h + 2.3, z - 2), C.Metal, m) -- vent stack
		b.cylinder(0.4, 1.6, V(x + 6, h + 3.9, z - 2), C.Dark, m)
		b.cylinder(1.6, 0.8, V(x - 5.5, h + 1.6, z + 3), C.Metal, m)
		b.block(V(10, 0.5, 0.5), V(x + 1, h + 1.25, z - 4.5), C.Metal, m) -- pipe run
	end)
end

local function acUnit(b, pos, m)
	b.block(V(4, 2.4, 3), pos + V(0, 1.2, 0), C.Metal, m)
	b.decor(function()
		b.cylinder(0.3, 2.2, pos + V(0, 2.55, 0), C.Dark, m)
		for k = -1, 1 do
			b.block(V(4.05, 0.15, 3.05), pos + V(0, 1.2 + k * 0.5, 0), C.Trim, m) -- grille slats
		end
	end)
end

local function waterTower(b, pos, m)
	b.decor(function()
		for _, o in ipairs({ V(2.6, 0, 2.6), V(-2.6, 0, 2.6), V(2.6, 0, -2.6), V(-2.6, 0, -2.6) }) do
			b.block(V(0.6, 8, 0.6), pos + o + V(0, 4, 0), C.Dark, m)
		end
		bar(b, pos + V(-2.6, 1, 2.6), pos + V(2.6, 7, 2.6), 0.3, 0.3, C.Dark, m) -- cross bracing
		bar(b, pos + V(-2.6, 1, -2.6), pos + V(2.6, 7, -2.6), 0.3, 0.3, C.Dark, m)
		b.cylinder(0.3, 7.6, pos + V(0, 8, 0), C.Dark, m)
	end)
	b.cylinder(7, 7.5, pos + V(0, 11.5, 0), C.Wood, m)
	b.decor(function()
		for y = 9, 14, 2.5 do
			b.cylinder(0.25, 7.7, pos + V(0, y, 0), C.Dark, m) -- hoops
		end
		b.cylinder(0.6, 8.2, pos + V(0, 15.3, 0), C.Trim, m)
		b.cylinder(1.2, 4, pos + V(0, 16.2, 0), C.Trim, m)
	end)
end

local function antenna(b, pos, height, m)
	b.decor(function()
		b.cylinder(height, 0.4, pos + V(0, height / 2, 0), C.Metal, m)
		b.block(V(3, 0.2, 0.2), pos + V(0, height * 0.7, 0), C.Metal, m)
		b.block(V(0.2, 0.2, 2.4), pos + V(0, height * 0.55, 0), C.Metal, m)
		neon(b, b.ball(0.9, pos + V(0, height, 0), P.PlayerB, m))
	end)
end

----------------------------------------------------------------------------
-- FIRE ESCAPE (steel switchback stairs on the side of a building)
----------------------------------------------------------------------------
--[[
	origin  : point on the wall (Y ignored) where it starts
	outward : unit vector away from the wall
	lateral : unit vector along the wall (the direction it extends)
	levels  : number of landings above the ground; rise = height per level

	Two lanes 3 studs wide sit side by side out from the wall. Flights
	alternate lanes (outer going +lateral, inner coming back), each landing
	has a hole above the flight that arrives there, so you can always run
	straight up. options.Extend lengthens the landings; options.Gap =
	{ Level, Center, Width } leaves an opening in the outer railing (for the
	catwalk between buildings).
]]
local function fireEscape(b, origin, outward, lateral, levels, rise, m, options)
	options = options or {}
	local run = rise * 1.3
	local length = run + 4 + (options.Extend or 0)
	local base = V(origin.X, 0, origin.Z)
	local alongX = math.abs(lateral.X) > 0.5
	local INNER, OUTER = 1.5, 4.5

	local function at(s, d, y)
		return base + lateral * s + outward * d + V(0, y, 0)
	end
	-- a box `sl` long along the wall, `h` tall, `sd` deep out from the wall
	local function size(sl, h, sd)
		return alongX and V(sl, h, sd) or V(sd, h, sl)
	end
	local function plate(s0, s1, lane, y)
		if s1 - s0 > 0.05 then
			b.block(size(s1 - s0, 0.4, 3), at((s0 + s1) / 2, lane, y - 0.2), C.Metal, m)
		end
	end

	for i = 0, levels - 1 do
		local y0 = rise * i
		local outerLane = i % 2 == 0
		local lane = outerLane and OUTER or INNER
		local s0 = outerLane and 2 or 2 + run
		local dir = outerLane and lateral or -lateral
		b.invisible(b.ramp(at(s0, lane, y0), dir, run, rise, 3, C.Metal, m))

		-- steel treads + stringers + handrail you actually see
		b.decor(function()
			local count = math.max(5, math.floor(rise / 0.75 + 0.5))
			for j = 0, count - 1 do
				local s = s0 + (outerLane and 1 or -1) * (j + 0.5) * run / count
				b.block(size(run / count + 0.04, 0.22, 2.7), at(s, lane, y0 + (j + 1) * rise / count - 0.11), C.Metal, m)
			end
			local sTop = s0 + (outerLane and run or -run)
			for _, d in ipairs({ lane - 1.45, lane + 1.45 }) do
				bar(b, at(s0, d, y0 - 0.1), at(sTop, d, y0 + rise - 0.1), 0.2, 0.8, C.Dark, m)
			end
			local railSide = outerLane and OUTER + 1.45 or INNER + 1.45
			bar(b, at(s0, railSide, y0 + 3), at(sTop, railSide, y0 + rise + 3), 0.18, 0.18, C.Dark, m)
			b.block(V(0.18, 3, 0.18), at(s0, railSide, y0 + 1.5), C.Dark, m)
		end)
	end

	for k = 1, levels do
		local y = rise * k
		-- the flight that arrives here needs a hole above it
		local arrivingOuter = (k - 1) % 2 == 0
		for _, lane in ipairs({ INNER, OUTER }) do
			if (lane == OUTER) == arrivingOuter then
				plate(0, 2, lane, y)
				plate(2 + run, length, lane, y)
			else
				plate(0, length, lane, y)
			end
		end

		-- railings: invisible walls you can't fall through + visible rails
		local gap = options.Gap and options.Gap.Level == k and options.Gap or nil
		local segments = { { 0, length } }
		if gap then
			segments = { { 0, gap.Center - gap.Width / 2 }, { gap.Center + gap.Width / 2, length } }
		end
		for _, seg in ipairs(segments) do
			local s0, s1 = seg[1], seg[2]
			if s1 - s0 > 0.2 then
				playerWall(b, size(s1 - s0, 3.4, 0.3), at((s0 + s1) / 2, 6.15, y + 1.7), m)
				b.decor(function()
					b.block(size(s1 - s0, 0.2, 0.2), at((s0 + s1) / 2, 6.1, y + 3.2), C.Dark, m)
					b.block(size(s1 - s0, 0.15, 0.15), at((s0 + s1) / 2, 6.1, y + 1.7), C.Dark, m)
					for s = s0, s1 + 0.01, 2.4 do
						b.block(V(0.18, 3.2, 0.18), at(s, 6.1, y + 1.6), C.Dark, m)
					end
				end)
			end
		end
		for _, s in ipairs({ -0.15, length + 0.15 }) do
			playerWall(b, size(0.3, 3.4, 6), at(s, 3, y + 1.7), m)
			b.decor(function()
				b.block(size(0.2, 0.2, 6), at(s, 3, y + 3.2), C.Dark, m)
			end)
		end

		-- brackets bolting the landing to the wall + an edge band
		b.decor(function()
			for _, s in ipairs({ 1, length - 1 }) do
				bar(b, at(s, 0.2, y - 3.2), at(s, 5.6, y - 0.45), 0.3, 0.3, C.Dark, m)
			end
			b.block(size(length, 0.5, 0.15), at(length / 2, 6.0, y - 0.2), C.Dark, m)
		end)
	end
end

----------------------------------------------------------------------------
-- STREET PROPS
----------------------------------------------------------------------------

-- Billboard on two legs (the board is solid: wall-runnable).
local function billboard(b, pos, width, height, legHeight, color, m)
	b.block(V(0.8, legHeight, 0.8), pos + V(-width / 2 + 2, legHeight / 2, 0), C.Metal, m)
	b.block(V(0.8, legHeight, 0.8), pos + V(width / 2 - 2, legHeight / 2, 0), C.Metal, m)
	b.block(V(width, height, 1.2), pos + V(0, legHeight + height / 2, 0), C.Dark, m)
	b.decor(function()
		b.block(V(width - 1.6, height - 1.6, 1.4), pos + V(0, legHeight + height / 2, 0), color, m)
		b.block(V(width * 0.5, 1.2, 1.5), pos + V(-width * 0.12, legHeight + height * 0.62, 0), C.RoadWhite, m)
		b.block(V(width * 0.3, 1.2, 1.5), pos + V(-width * 0.22, legHeight + height * 0.38, 0), C.RoadWhite, m)
		b.ball(height * 0.45, pos + V(width * 0.3, legHeight + height / 2, 0), C.RoadWhite, m)
		-- catwalk + spot lamps along the bottom
		b.block(V(width, 0.3, 2), pos + V(0, legHeight - 0.1, 0), C.Metal, m)
		for x = -width / 2 + 3, width / 2 - 3, (width - 6) / 3 do
			b.block(V(0.3, 1.2, 0.3), pos + V(x, legHeight + 0.5, -1.2), C.Dark, m)
			neon(b, b.block(V(0.8, 0.4, 0.5), pos + V(x, legHeight + 1.2, -1.4), C.LampLight, m))
		end
	end)
end

local function lamp(b, pos, armDir, m, banner)
	b.cylinder(13, 0.5, pos + V(0, 6.5, 0), C.Metal, m)
	b.decor(function()
		b.cylinder(1.4, 1.2, pos + V(0, 0.7, 0), C.Dark, m) -- base
		b.cylinder(0.3, 0.8, pos + V(0, 1.5, 0), C.Metal, m)
		b.cylinder(0.5, 0.7, pos + V(0, 13.1, 0), C.Dark, m)
		local root = pos + V(0, 12.7, 0)
		local tip = root + armDir * 3.4 + V(0, 0.5, 0)
		bar(b, root, tip, 0.25, 0.25, C.Metal, m)
		b.part(V(1.7, 0.5, 2.6), CFrame.lookAt(tip + armDir * 0.6, tip + armDir * 2), C.Dark, m)
		neon(b, b.part(V(1.2, 0.15, 2), CFrame.lookAt(tip + armDir * 0.6 - V(0, 0.3, 0), tip + armDir * 2), C.LampLight, m))
		if banner then
			local bp = pos + V(0, 9, 0) + armDir * 0.85
			b.part(V(0.12, 3, 1.3), CFrame.lookAt(bp, bp + armDir) * CFrame.Angles(0, rad(90), 0), banner, m)
		end
	end)
end

-- Variety for trees: rotate the leaf clusters by a stable per-tree angle.
local LEAVES = {
	{ V(0, 9.6, 0), 7.6, "Foliage" },
	{ V(2.7, 8.4, 1.3), 5.6, "FoliageDark" },
	{ V(-2.6, 8.7, -1.5), 5.8, "Foliage" },
	{ V(1.2, 11.4, -1.9), 5.2, "FoliageLight" },
	{ V(-1.5, 11.2, 1.9), 4.9, "FoliageLight" },
	{ V(0.3, 12.8, 0.2), 4.2, "FoliageLight" },
	{ V(-3, 7.4, 1.9), 4.4, "FoliageDark" },
	{ V(3, 7.3, -2.1), 4.2, "FoliageDark" },
}

local function tree(b, pos, scale, m)
	scale = scale or 1
	local spin = CFrame.Angles(0, (pos.X * 0.37 + pos.Z * 0.61) % (math.pi * 2), 0)
	b.block(V(5, 1.2, 5), pos + V(0, 0.6, 0), C.Curb, m) -- planter
	b.cylinder(6 * scale, 1.2 * scale, pos + V(0, 1.2 + 3 * scale, 0), C.Trunk, m) -- trunk
	b.decor(function()
		b.block(V(4.3, 0.2, 4.3), pos + V(0, 1.25, 0), C.Soil, m)
		b.block(V(5.3, 0.3, 5.3), pos + V(0, 1.15, 0), C.Concrete, m) -- planter lip
		b.cylinder(3.5 * scale, 0.85 * scale, pos + V(0, 1.2 + 7.5 * scale, 0), C.Trunk, m)
		-- branches
		for k = 0, 2 do
			local a = k * 2.1
			local from = pos + V(0, 1.2 + 5.2 * scale, 0)
			local to = from + (spin * CFrame.Angles(0, a, 0)).LookVector * 2.6 * scale + V(0, 2.6 * scale, 0)
			bar(b, from, to, 0.45 * scale, 0.45 * scale, C.Trunk, m)
		end
	end)
	b.soft(function()
		for _, leaf in ipairs(LEAVES) do
			local offset = (spin * CFrame.new(leaf[1])).Position * scale
			b.ball(leaf[2] * scale, pos + offset, C[leaf[3]], m)
		end
	end)
end

local function wheel(b, cf, diameter, width, m)
	b.cylinder(width, diameter, nil, C.Tire, m, cf)
	b.cylinder(width + 0.06, diameter * 0.55, nil, C.Rim, m, cf)
	b.cylinder(width + 0.1, diameter * 0.18, nil, C.Trim, m, cf)
end

-- A parked car. cf = position on the ground + facing (the front is -Z).
-- style: nil (sedan) or "Taxi" (roof sign).
local function car(b, cf, color, m, style)
	local function at(x, y, z)
		return cf * CFrame.new(x, y, z)
	end
	-- SOLID: lower body + cabin
	b.part(V(4.6, 1.5, 10.2), at(0, 1.55, 0), color, m)
	b.invisible(b.part(V(4.1, 1.8, 4.8), at(0, 3.2, 0.5), color, m))

	b.decor(function()
		-- shape: hood and trunk lids, rocker panels, bumpers
		b.part(V(4.4, 0.25, 3.1), at(0, 2.4, -3.6), color, m)
		b.part(V(4.4, 0.25, 2.3), at(0, 2.4, 4), color, m)
		b.part(V(4.7, 0.4, 7.6), at(0, 0.95, 0), C.Dark, m)
		b.part(V(4.8, 0.6, 0.5), at(0, 1.2, -5.2), C.Trim, m)
		b.part(V(4.8, 0.6, 0.5), at(0, 1.2, 5.2), C.Trim, m)
		b.part(V(2.2, 0.5, 0.1), at(0, 1.9, -5.12), C.Dark, m) -- grille
		b.part(V(1.3, 0.45, 0.08), at(0, 1.2, -5.47), C.RoadWhite, m) -- plates
		b.part(V(1.3, 0.45, 0.08), at(0, 1.2, 5.47), C.RoadWhite, m)
		for _, x in ipairs({ -1.65, 1.65 }) do
			neon(b, b.part(V(1.05, 0.4, 0.1), at(x, 1.95, -5.12), C.LampLight, m))
			neon(b, b.part(V(1.1, 0.4, 0.1), at(x, 1.95, 5.12), C.TailLight, m))
		end
		-- cabin: sloped windscreen + rear window, roof, side glass, pillar
		glass(b, b.place("WedgePart", V(4, 1.6, 1.5), at(0, 3.1, -2.05), C.Glass, m))
		glass(b, b.place("WedgePart", V(4, 1.6, 1.3), at(0, 3.1, 2.95) * CFrame.Angles(0, math.pi, 0), C.Glass, m))
		b.part(V(4.1, 0.3, 3.6), at(0, 4.05, 0.5), color, m)
		glass(b, b.part(V(4.12, 1.45, 3.6), at(0, 3.15, 0.5), C.Glass, m))
		b.part(V(4.2, 1.5, 0.35), at(0, 3.15, 0.45), color, m)
		-- door seams, handles, mirrors
		for _, z in ipairs({ -1.25, 2.1 }) do
			b.part(V(4.64, 1.2, 0.08), at(0, 1.65, z), C.Dark, m)
		end
		for _, z in ipairs({ -0.4, 2.6 }) do
			b.part(V(4.66, 0.15, 0.55), at(0, 2.05, z), C.Rim, m)
		end
		for _, x in ipairs({ -2.45, 2.45 }) do
			b.part(V(0.45, 0.35, 0.5), at(x, 2.75, -1.7), color, m)
		end
		-- wheels with rims and dark wheel arches
		for _, o in ipairs({ V(2.05, 1.15, 3.3), V(-2.05, 1.15, 3.3), V(2.05, 1.15, -3.3), V(-2.05, 1.15, -3.3) }) do
			b.part(V(0.2, 1.4, 2.9), at(o.X > 0 and 2.31 or -2.31, 1.75, o.Z), C.Dark, m)
			wheel(b, at(o.X, o.Y, o.Z), 2.3, 0.9, m)
		end
		if style == "Taxi" then
			b.part(V(1.6, 0.6, 0.8), at(0, 4.5, 0.5), C.RoadWhite, m)
			b.part(V(4.66, 0.4, 7), at(0, 1.6, 0), C.Dark, m) -- checker stripe
		end
	end)
end

-- A city bus (big cover, and a wall to run along).
local function bus(b, cf, m)
	local function at(x, y, z)
		return cf * CFrame.new(x, y, z)
	end
	b.part(V(8.5, 7.6, 30), at(0, 4.7, 0), C.Bus, m)
	b.decor(function()
		-- window band with pillars
		glass(b, b.part(V(8.62, 2.6, 26), at(0, 6.1, 1.4), C.Glass, m))
		for z = -11.4, 14.4, 2.6 do
			b.part(V(8.7, 2.7, 0.35), at(0, 6.1, z), C.Bus, m)
		end
		b.part(V(8.64, 0.7, 30.04), at(0, 3.7, 0), C.RoadWhite, m) -- stripe
		b.part(V(8.64, 0.3, 30.04), at(0, 4.2, 0), P.AccentA, m)
		-- front: windscreen, destination sign, lights, bumper
		glass(b, b.part(V(7.6, 3.6, 0.2), at(0, 5.9, -15.05), C.Glass, m))
		neon(b, b.part(V(5.4, 0.8, 0.15), at(0, 8.1, -15.08), C.LampLight, m))
		b.part(V(0.3, 3.6, 0.25), at(0, 5.9, -15.12), C.Dark, m) -- wiper divider
		for _, x in ipairs({ -3.2, 3.2 }) do
			neon(b, b.part(V(1.2, 0.6, 0.12), at(x, 2.5, -15.08), C.LampLight, m))
			neon(b, b.part(V(1.2, 0.8, 0.12), at(x, 2.8, 15.08), C.TailLight, m))
			b.part(V(0.3, 0.3, 1.6), at(x * 1.42, 7.2, -15.5), C.Dark, m) -- mirror arms
			b.part(V(0.5, 1.2, 0.3), at(x * 1.45, 6.6, -16.2), C.Dark, m)
		end
		b.part(V(8.7, 0.9, 0.6), at(0, 1.5, -15.2), C.Dark, m)
		b.part(V(8.7, 0.9, 0.6), at(0, 1.5, 15.2), C.Dark, m)
		-- doors (curb side) + roof unit + rear engine grille
		for _, z in ipairs({ -11, 2 }) do
			b.part(V(0.2, 5.8, 3.4), at(4.3, 3.9, z), C.Dark, m)
			glass(b, b.part(V(0.25, 4, 1.4), at(4.32, 4.6, z - 0.8), C.Glass, m))
			glass(b, b.part(V(0.25, 4, 1.4), at(4.32, 4.6, z + 0.8), C.Glass, m))
		end
		b.part(V(6.6, 1, 9), at(0, 9, 5), C.Trim, m)
		b.part(V(5, 1.4, 0.15), at(0, 3, 15.08), C.Dark, m)
		for _, z in ipairs({ -9.5, 9.5 }) do
			for _, x in ipairs({ 3.95, -3.95 }) do
				b.part(V(0.3, 2, 3.6), at(x > 0 and 4.3 or -4.3, 2.4, z), C.Dark, m)
				wheel(b, at(x, 1.4, z), 2.8, 0.9, m)
			end
		end
	end)
end

-- Concrete jersey barrier.
local function barrier(b, cf, m)
	b.part(V(2.4, 1.4, 8), cf * CFrame.new(0, 0.7, 0), C.Concrete, m)
	b.part(V(1.3, 1.8, 8), cf * CFrame.new(0, 2.3, 0), C.Concrete, m)
	b.decor(function()
		b.part(V(1.35, 0.5, 8.05), cf * CFrame.new(0, 2.6, 0), P.AccentB, m)
		for _, z in ipairs({ -2.5, 2.5 }) do
			b.part(V(1.6, 0.4, 0.4), cf * CFrame.new(0, 2, z), C.RoadWhite, m) -- reflectors
		end
	end)
end

local function bench(b, cf, m)
	b.decor(function()
		for k = -1, 1 do
			b.part(V(5, 0.22, 0.45), cf * CFrame.new(0, 1.45, k * 0.55), C.Wood, m)
		end
		b.part(V(5, 0.4, 0.2), cf * CFrame.new(0, 2.2, 0.8), C.Wood, m)
		b.part(V(5, 0.4, 0.2), cf * CFrame.new(0, 2.8, 0.8), C.Wood, m)
		for _, x in ipairs({ -2.1, 2.1 }) do
			b.part(V(0.25, 1.4, 1.6), cf * CFrame.new(x, 0.7, 0), C.Dark, m)
			b.part(V(0.25, 1.6, 0.25), cf * CFrame.new(x, 2.1, 0.8), C.Dark, m)
		end
	end)
end

local function crates(b, pos, m)
	b.block(V(4, 4, 4), pos + V(0, 2, 0), C.Wood, m)
	b.block(V(4, 4, 4), pos + V(4.2, 2, 0.5), C.Wood, m)
	b.block(V(3.6, 3.6, 3.6), pos + V(2, 5.8, 0.2), P.AccentB, m)
	b.decor(function()
		for _, o in ipairs({ V(0, 2, 0), V(4.2, 2, 0.5) }) do
			b.block(V(4.1, 0.4, 4.1), pos + o + V(0, 1.5, 0), C.Trunk, m) -- slats
			b.block(V(4.1, 0.4, 4.1), pos + o + V(0, -1.5, 0), C.Trunk, m)
			b.block(V(0.4, 4.1, 4.12), pos + o, C.Trunk, m)
		end
	end)
end

-- Market stall with a striped canopy.
local function stall(b, pos, color, m)
	b.block(V(10, 3.4, 4), pos + V(0, 1.7, 0), C.Wood, m)
	b.decor(function()
		b.block(V(10.4, 0.4, 4.4), pos + V(0, 3.6, 0), C.Trim, m)
		for _, x in ipairs({ -4.6, 4.6 }) do
			b.block(V(0.4, 8, 0.4), pos + V(x, 4, -1.8), C.Metal, m)
			b.block(V(0.4, 8, 0.4), pos + V(x, 4, 1.8), C.Metal, m)
		end
		for k = -2, 2 do -- striped canopy
			b.block(V(2.2, 0.5, 5.6), pos + V(k * 2.2, 8.2, 0), k % 2 == 0 and color or C.RoadWhite, m)
		end
		b.block(V(11, 1, 0.3), pos + V(0, 7.6, -2.8), C.RoadWhite, m)
		for k = -3, 3 do -- produce on the counter
			b.ball(0.9, pos + V(k * 1.3, 4.2, -0.8), C.Awning[(k % 3) + 1], m)
			b.ball(0.9, pos + V(k * 1.3 + 0.6, 4.2, 0.6), C.FoliageLight, m)
		end
	end)
end

local function hydrant(b, pos, m)
	b.decor(function()
		b.cylinder(2, 0.9, pos + V(0, 1, 0), C.Hydrant, m)
		b.cylinder(0.4, 1.1, pos + V(0, 2.1, 0), C.Hydrant, m)
		b.ball(0.9, pos + V(0, 2.3, 0), C.Hydrant, m)
		b.cylinder(1.4, 0.4, nil, C.Hydrant, m, CFrame.new(pos + V(0, 1.4, 0)))
	end)
end

local function trashCan(b, pos, m)
	b.decor(function()
		b.cylinder(2.4, 1.6, pos + V(0, 1.2, 0), C.Metal, m)
		b.cylinder(0.3, 1.8, pos + V(0, 2.5, 0), C.Dark, m)
		b.cylinder(0.12, 1.65, pos + V(0, 1.6, 0), P.AccentB, m)
	end)
end

-- Traffic light on a corner. faceDir = the way the lights face.
local function trafficLight(b, pos, faceDir, armDir, m)
	b.cylinder(12, 0.6, pos + V(0, 6, 0), C.Dark, m)
	b.decor(function()
		local top = pos + V(0, 11.4, 0)
		local tip = top + armDir * 8
		bar(b, top, tip, 0.35, 0.35, C.Dark, m)
		local head = tip - V(0, 1.8, 0)
		local frame = CFrame.lookAt(head, head + faceDir)
		b.part(V(1.3, 3.6, 1), frame, C.Dark, m)
		local lights = { { 1.1, C.TailLight }, { 0, P.AccentB }, { -1.1, C.SignalGreen } }
		for k, light in ipairs(lights) do
			local part = b.part(V(0.75, 0.75, 0.2), frame * CFrame.new(0, light[1], -0.55), k == 3 and light[2] or light[2]:Lerp(C.Dark, 0.65), m)
			if k == 3 then
				neon(b, part)
			end
		end
		-- pedestrian button + street sign
		b.block(V(0.5, 0.7, 0.5), pos + V(0, 3.6, 0) + faceDir * 0.4, P.AccentB, m)
		b.part(V(3.4, 0.7, 0.12), CFrame.lookAt(pos + V(0, 9.2, 0), pos + V(0, 9.2, 0) + faceDir) * CFrame.Angles(0, rad(90), 0), C.SignalGreen:Lerp(C.Dark, 0.4), m)
	end)
end

-- Practice dummies for the Playground (rooftops, train, avenue, park)
local PLAYGROUND_DUMMIES = {
	{ Position = V(-120, 0.5, 5), Motion = "Strafe", Amount = 10, Speed = 0.3, Face = V(1, 0, 0) },
	{ Position = V(60, 0.5, -5), Motion = "Strafe", Amount = 12, Speed = 0.25, Face = V(-1, 0, 0) },
	{ Position = V(-95, 48.8, 62), Face = V(0, 0, -1) },
	{ Position = V(95, 48.8, 62), Face = V(0, 0, -1) },
	{ Position = V(-152, 24.8, 60), Face = V(1, 0, -1) },
	{ Position = V(12, 26.8, 62), Face = V(0, 0, -1) },
	{ Position = V(0, 31.3, -75), Face = V(0, 0, 1) },
	{ Position = V(-60, 22, -75), Motion = "Strafe", Amount = 16, Speed = 0.2, Face = V(0, 0, 1) },
	{ Position = V(-90, 0.3, -47), Motion = "Bob", Amount = 9, Speed = 0.5, Face = V(0, 0, 1) },
	{ Position = V(150, 0.5, -100), Face = V(-1, 0, 0) },
	{ Position = V(30, 0.5, -112), Motion = "Strafe", Amount = 8, Speed = 0.4, Face = V(0, 0, 1) },
	{ Position = V(40, 0.5, 30), Face = V(0, 0, -1) },
}

----------------------------------------------------------------------------
-- BUILD
----------------------------------------------------------------------------
function ArenaDowntown.Build(b)
	local X = "X"
	local XZ = "XZ"

	-- GROUND ----------------------------------------------------------------
	b.block(V(460, 4, 320), V(0, -2, 0), C.Asphalt)
	b.decor(function()
		-- avenue centre dashes + edge lines
		for x = -200, -54, 14 do
			b.block(V(7, 0.08, 0.6), V(x, 0.04, 0), C.RoadLine, X)
		end
		b.block(V(150, 0.08, 0.5), V(-128, 0.04, 15.5), C.RoadWhite, XZ)
		-- crosswalks + stop lines at the plaza
		for z = -13, 13, 4 do
			b.block(V(6, 0.08, 2), V(-52, 0.04, z), C.RoadWhite, X)
		end
		b.block(V(0.8, 0.08, 15), V(-57, 0.04, -7.5), C.RoadWhite, X)
		-- manholes + drains
		for _, x in ipairs({ -176, -122, -92 }) do
			b.cylinder(0.1, 3, V(x, 0.05, -6), C.Dark, X)
			b.cylinder(0.12, 2.4, V(x, 0.06, -6), C.Metal, X)
			b.block(V(2.4, 0.08, 0.8), V(x + 10, 0.04, 16.8), C.Dark, XZ)
		end
	end)
	-- sidewalks + curbs (north and south of the avenue)
	b.block(V(158, 0.5, 12), V(-125, 0.25, 24), C.Sidewalk, XZ)
	b.block(V(158, 0.6, 0.6), V(-125, 0.3, 17.8), C.Curb, XZ)
	b.block(V(158, 0.5, 14), V(-125, 0.25, 37), C.Sidewalk, X) -- forecourt in front of the north buildings
	b.decor(function()
		for x = -200, -50, 6 do -- paving joints
			b.block(V(0.15, 0.04, 12), V(x, 0.52, 24), C.Curb, XZ)
		end
	end)

	-- CENTRAL PLAZA + FOUNTAIN ----------------------------------------------
	b.block(V(92, 0.5, 92), V(0, 0.25, 0), C.Sidewalk)
	b.decor(function()
		for i = -40, 40, 10 do
			b.block(V(92, 0.06, 0.3), V(0, 0.53, i), C.Curb)
			b.block(V(0.3, 0.06, 92), V(i, 0.53, 0), C.Curb)
		end
		b.cylinder(0.08, 40, V(0, 0.54, 0), C.Stone) -- ring of paving around the fountain
		b.cylinder(0.1, 34, V(0, 0.56, 0), C.Sidewalk)
	end)
	b.cylinder(2.6, 26, V(0, 1.8, 0), C.Stone)
	b.cylinder(7, 3, V(0, 6, 0), C.Stone)
	b.decor(function()
		glass(b, b.cylinder(0.4, 23.5, V(0, 3, 0), C.Water))
		b.cylinder(0.9, 10, V(0, 9.4, 0), C.Stone)
		glass(b, b.cylinder(0.3, 9, V(0, 9.9, 0), C.Water))
		b.cylinder(3, 1.6, V(0, 11.3, 0), C.Stone)
		b.cylinder(0.6, 5, V(0, 12.8, 0), C.Stone)
		neon(b, b.ball(1.8, V(0, 13.6, 0), C.Water))
		for k = 0, 5 do -- little jets in the basin
			local a = k * math.pi / 3
			local p = V(math.cos(a) * 8, 3.6, math.sin(a) * 8)
			neon(b, b.cylinder(1.6, 0.35, p + V(0, 0.6, 0), C.Water))
		end
	end)
	bench(b, CFrame.new(-30, 0.5, -30) * CFrame.Angles(0, rad(45), 0), XZ)
	tree(b, V(-38, 0.5, -38), 1, XZ)
	tree(b, V(-38, 0.5, 38), 1, X)
	lamp(b, V(-44, 0.5, -22), V(1, 0, 0), XZ, C.Awning[2])
	trafficLight(b, V(-48, 0.5, 20), V(-1, 0, 0), V(0, 0, -1), X)
	trafficLight(b, V(-48, 0.5, -20), V(-1, 0, 0), V(0, 0, 1), X)

	-- CITY HALL (north of the plaza, centred) --------------------------------
	building(b, 0, 72, 46, 32, 26, C.BuildingA, { "S", "E", "W" }, nil, { WindowSpacing = 8 })
	b.block(V(48, 2, 8), V(0, 1, 52), C.Stone) -- porch floor
	stairs(b, V(0, 0, 44.4), V(0, 0, 1), 3.6, 2, 40, C.Stone, nil, { Solid = true, Rails = false })
	for x = -18, 18, 7.2 do
		b.cylinder(20, 2.4, V(x, 12, 50), C.BuildingA)
		b.decor(function()
			b.block(V(3.4, 1, 3.4), V(x, 2.5, 50), C.Stone) -- column base + capital
			b.block(V(3.6, 1, 3.6), V(x, 21.5, 50), C.Stone)
			for k = 0, 3 do -- fluting
				local a = k * math.pi / 4
				b.part(V(0.3, 18, 2.5), CFrame.new(x, 12, 50) * CFrame.Angles(0, a, 0), C.Stone, nil)
			end
		end)
	end
	b.block(V(50, 1.6, 9), V(0, 22.8, 51.5), C.BuildingA) -- porch roof
	b.decor(function()
		b.block(V(50, 0.6, 9.4), V(0, 21.8, 51.5), C.Trim)
		-- pediment (triangle) above the porch
		b.place("WedgePart", V(1.4, 5, 25), CFrame.new(-12.5, 26.1, 47.6) * CFrame.Angles(0, rad(90), 0), C.Stone)
		b.place("WedgePart", V(1.4, 5, 25), CFrame.new(12.5, 26.1, 47.6) * CFrame.Angles(0, rad(-90), 0), C.Stone)
		b.block(V(30, 1.2, 1.2), V(0, 23.8, 47.4), C.Trim)
		b.block(V(10, 7, 0.4), V(0, 5.5, 55.9), C.Dark) -- doors
		b.block(V(0.3, 7, 0.5), V(0, 5.5, 55.75), C.Trim)
		glass(b, b.block(V(9, 2, 0.45), V(0, 10.2, 55.9), C.Glass))
		b.block(V(16, 1.6, 0.4), V(0, 17, 55.8), C.Dark) -- name plate
		for x = -6, 6, 2 do
			b.block(V(1.2, 0.8, 0.2), V(x, 17, 55.5), C.Rim)
		end
	end)
	-- clock tower
	b.block(V(12, 26, 12), V(0, 39, 74), C.BuildingA)
	b.decor(function()
		for _, x in ipairs({ -5.6, 5.6 }) do
			b.block(V(1.2, 26, 12.6), V(x, 39, 74), C.Stone, nil) -- corner pilasters
		end
		b.block(V(13, 0.8, 13), V(0, 46, 74), C.Trim)
		b.cylinder(0.4, 8, nil, C.RoadWhite, nil, CFrame.new(0, 40, 67.8) * CFrame.Angles(0, rad(90), 0))
		b.cylinder(0.3, 8.8, nil, C.Trim, nil, CFrame.new(0, 40, 67.85) * CFrame.Angles(0, rad(90), 0))
		for k = 0, 11 do -- hour marks
			local a = k * math.pi / 6
			b.part(V(0.3, 0.8, 0.15), CFrame.new(math.sin(a) * 3.3, 40 + math.cos(a) * 3.3, 67.5) * CFrame.Angles(0, 0, -a), C.Dark)
		end
		b.part(V(0.45, 2.8, 0.15), CFrame.new(0, 41.2, 67.4), C.Dark)
		b.part(V(2.2, 0.45, 0.15), CFrame.new(1, 40, 67.35), C.Dark)
		for x = -3, 3, 1.5 do -- belfry louvres
			b.block(V(0.6, 4, 0.3), V(x, 49.5, 67.9), C.Dark)
		end
	end)
	b.block(V(14, 1.2, 14), V(0, 52.6, 74), C.Roof)
	b.block(V(9, 4, 9), V(0, 55.2, 74), C.BuildingA)
	b.block(V(5, 4, 5), V(0, 59.2, 74), C.Roof)
	antenna(b, V(0, 61.2, 74), 6)
	-- fire escapes on both sides up to the roof
	fireEscape(b, V(-23, 0, 58), V(-1, 0, 0), V(0, 0, 1), 3, 26 / 3, X)
	acUnit(b, V(-14, 26.8, 84), X)
	rooftop(b, 10, 82, 26.8, nil, false)

	-- OFFICE TOWER (north, mirrored) ------------------------------------------
	building(b, -95, 69, 34, 46, 48, C.BuildingB, { "S", "E", "W" }, X)
	fireEscape(b, V(-112, 0, 50), V(-1, 0, 0), V(0, 0, 1), 6, 8, X, {
		Extend = 5,
		Gap = { Level = 3, Center = 2 + 10.4 + 4, Width = 4.4 },
	})
	acUnit(b, V(-102, 48.8, 80), X)
	acUnit(b, V(-88, 48.8, 82), X)
	antenna(b, V(-84, 48.8, 58), 14, X)
	rooftop(b, -100, 86, 48.8, X, true)
	-- rooftop sniper nest
	b.block(V(10, 2.4, 1.6), V(-95, 50, 48.6), P.AccentA, X)
	b.block(V(1.6, 2.4, 6), V(-80.6, 50, 52), P.AccentA, X)
	b.decor(function()
		b.block(V(10.2, 0.3, 1.8), V(-95, 51.3, 48.6), C.Dark, X)
		b.block(V(1.8, 0.3, 6.2), V(-80.6, 51.3, 52), C.Dark, X)
		-- office lobby: glass doors with a canopy
		glass(b, b.block(V(10, 7, 0.3), V(-95, 5.1, 45.8), C.Glass, X))
		b.block(V(14, 0.8, 4), V(-95, 9.2, 44), C.Dark, X)
		b.block(V(0.3, 7, 0.4), V(-95, 5.1, 45.7), C.Rim, X)
	end)

	-- APARTMENTS (north-west, mirrored) + catwalk to the office tower ---------
	building(b, -152.5, 72, 45, 56, 24, C.Brick, { "S", "E" }, X, { Storefront = { "S" } })
	fireEscape(b, V(-130, 0, 50), V(1, 0, 0), V(0, 0, 1), 3, 8, X, {
		Extend = 5,
		Gap = { Level = 3, Center = 2 + 10.4 + 4, Width = 4.4 },
	})
	-- catwalk between the two fire escapes (24 studs up)
	local catZ = 50 + 2 + 10.4 + 4
	b.block(V(6.4, 0.4, 4), V(-121, 23.8, catZ), C.Metal, X)
	playerWall(b, V(6, 3.4, 0.3), V(-121, 25.7, catZ + 2.1), X)
	playerWall(b, V(6, 3.4, 0.3), V(-121, 25.7, catZ - 2.1), X)
	b.decor(function()
		for _, dz in ipairs({ -2, 2 }) do
			b.block(V(6.4, 0.2, 0.2), V(-121, 27.2, catZ + dz), C.Dark, X)
			b.block(V(6.4, 0.15, 0.15), V(-121, 25.6, catZ + dz), C.Dark, X)
			for x = -124, -118, 2 do
				b.block(V(0.18, 3.2, 0.18), V(x, 25.6, catZ + dz), C.Dark, X)
			end
		end
		bar(b, V(-124, 20, catZ), V(-121, 23.6, catZ), 0.3, 0.3, C.Dark, X) -- braces
		bar(b, V(-118, 20, catZ), V(-121, 23.6, catZ), 0.3, 0.3, C.Dark, X)
	end)
	waterTower(b, V(-165, 24.8, 88), X)
	acUnit(b, V(-145, 24.8, 92), X)
	billboard(b, V(-152, 24.8, 99), 30, 10, 4, P.PlayerA, X)
	-- balconies on the apartment's east side
	for _, y in ipairs({ 14, 22 }) do
		for _, z in ipairs({ 78, 92 }) do
			b.block(V(3, 0.5, 7), V(-128.5, y - 4.3, z), C.Concrete, X)
			b.decor(function()
				b.block(V(0.2, 3, 7), V(-127.1, y - 2.6, z), C.Dark, X)
				b.block(V(3, 3, 0.2), V(-128.5, y - 2.6, z - 3.4), C.Dark, X)
				b.block(V(3, 3, 0.2), V(-128.5, y - 2.6, z + 3.4), C.Dark, X)
				b.block(V(0.3, 0.3, 7.2), V(-127.1, y - 1, z), C.Rim, X)
			end)
		end
	end

	-- SKYLINE (perimeter buildings, windows face the arena) -------------------
	local sideBlocks = {
		{ -132, 66, 70, C.BuildingD },
		{ -66, 66, 62, C.BuildingE },
		{ 0, 66, 78, C.BuildingD },
		{ 66, 66, 64, C.Stone },
		{ 132, 66, 72, C.BuildingD },
	}
	for _, seg in ipairs(sideBlocks) do
		building(b, -230, seg[1], 24, seg[2], seg[3], seg[4], { "E" }, X, {
			WindowSpacing = 9,
			FloorHeight = 9,
			NoParapet = true,
			Simple = true,
		})
	end
	local north = { { -189, 58, 76, C.BuildingD }, { -122, 76, 54, C.BuildingE }, { -42, 84, 66, C.Stone } }
	for _, seg in ipairs(north) do
		building(b, seg[1], 160, seg[2], 24, seg[3], seg[4], { "S" }, X, { WindowSpacing = 8, FloorHeight = 9, NoParapet = true, Simple = true })
	end
	local south = { { -189, 58, 58, C.BuildingE }, { -122, 76, 72, C.BuildingD }, { -42, 84, 50, C.Brick } }
	for _, seg in ipairs(south) do
		building(b, seg[1], -160, seg[2], 24, seg[3], seg[4], { "N" }, X, { WindowSpacing = 8, FloorHeight = 9, NoParapet = true, Simple = true })
	end
	waterTower(b, V(-122, 54.8, 165), X)
	waterTower(b, V(-189, 58.8, -165), X)
	antenna(b, V(-42, 66.8, 165), 16, X)
	antenna(b, V(-230, 78.8, 0), 18, X)

	-- SPAWN: TRANSIT STATIONS (mirrored) -------------------------------------
	b.block(V(30, 4, 40), V(-192, 2, 0), C.Concrete, X)
	b.block(V(30.4, 0.4, 40.4), V(-192, 4.2, 0), C.Sidewalk, X)
	stairs(b, V(-165, 0, 0), V(-1, 0, 0), 12, 4, 16, C.Concrete, X, { Solid = true })
	for _, z in ipairs({ -16, 16 }) do
		b.block(V(1, 10, 1), V(-182, 9.4, z), C.Metal, X)
		b.block(V(1, 10, 1), V(-202, 9.4, z), C.Metal, X)
	end
	b.block(V(26, 1, 38), V(-192, 14.9, 0), P.AccentA, X) -- canopy (ceiling to run on)
	b.decor(function()
		b.block(V(1.2, 0.1, 40), V(-178, 4.45, 0), P.AccentB, X) -- platform edge line
		for z = -18, 18, 1.5 do
			b.block(V(0.8, 0.12, 0.6), V(-179.2, 4.46, z), C.RoadLine, X) -- tactile strip
		end
		b.block(V(26.6, 0.6, 38.6), V(-192, 14.2, 0), C.Dark, X) -- canopy fascia
		for z = -14, 14, 7 do
			neon(b, b.block(V(18, 0.2, 0.6), V(-192, 14.3, z), C.LampLight, X)) -- strip lights
		end
		b.block(V(10, 4, 1), V(-192, 13, 19.2), C.Dark, X) -- station sign
		neon(b, b.block(V(8, 2, 1.1), V(-192, 13, 19.2), P.PlayerA, X))
		bench(b, CFrame.new(-198, 4.4, -12) * CFrame.Angles(0, rad(90), 0), X)
		bench(b, CFrame.new(-198, 4.4, 12) * CFrame.Angles(0, rad(90), 0), X)
		-- ticket machines
		b.block(V(2, 5, 1.6), V(-204, 6.9, -6), C.Metal, X)
		neon(b, b.block(V(1.4, 1.2, 0.2), V(-204, 7.8, -5.15), C.Glass, X))
	end)
	barrier(b, CFrame.new(-172, 0, 14), X)
	barrier(b, CFrame.new(-172, 0, -14), X)

	-- AVENUE COVER (mirrored) -----------------------------------------------
	bus(b, CFrame.new(-82, 0, -6) * CFrame.Angles(0, rad(90), 0), X)
	car(b, CFrame.new(-140, 0, 9) * CFrame.Angles(0, rad(90), 0), C.CarColors[1], X)
	car(b, CFrame.new(-118, 0, -9) * CFrame.Angles(0, rad(65), 0), P.AccentB, X, "Taxi")
	car(b, CFrame.new(-60, 0, 10) * CFrame.Angles(0, rad(100), 0), C.CarColors[3], X)
	barrier(b, CFrame.new(-47, 0, 9), X)
	barrier(b, CFrame.new(-47, 0, -9), X)
	-- street furniture along the sidewalks
	for i, x in ipairs({ -190, -155, -120, -85 }) do
		lamp(b, V(x, 0.5, 26), V(0, 0, -1), X, C.Awning[(i % 3) + 1])
		lamp(b, V(x, 0.5, -26), V(0, 0, 1), X, C.Awning[((i + 1) % 3) + 1])
	end
	for _, x in ipairs({ -172, -103, -68 }) do
		tree(b, V(x, 0.5, -26), 0.9, X)
	end
	tree(b, V(-160, 0.5, 26), 0.9, X)
	trashCan(b, V(-150, 0.5, -27), X)
	trashCan(b, V(-96, 0.5, 27), X)
	hydrant(b, V(-128, 0.5, 20), X)
	hydrant(b, V(-76, 0.5, -20), X)
	b.decor(function()
		for _, x in ipairs({ -134, -112 }) do -- parking meters
			b.cylinder(3, 0.25, V(x, 2, -19.5), C.Metal, X)
			b.block(V(0.6, 0.9, 0.5), V(x, 3.8, -19.5), C.Dark, X)
		end
		for x = -56, -44, 3 do -- bollards at the plaza
			b.cylinder(2.2, 0.7, V(x, 1.6, 19), C.Dark, X)
		end
	end)

	-- PARK (south of the avenue, mirrored) ------------------------------------
	b.block(V(84, 0.3, 26), V(-92, 0.15, -47), C.Grass, X)
	b.decor(function()
		b.block(V(84.6, 0.5, 0.4), V(-92, 0.25, -34), C.Curb, X) -- edging
		b.block(V(6, 0.32, 26), V(-108, 0.16, -47), C.Sidewalk, X) -- footpath
		for k = 0, 5 do -- flowers
			b.ball(0.8, V(-130 + k * 1.3, 0.6, -58), C.Awning[(k % 3) + 1], X)
		end
	end)
	for _, p in ipairs({ V(-120, 0.3, -42), V(-78, 0.3, -54), V(-58, 0.3, -40) }) do
		tree(b, p, 1.15, X)
	end
	b.block(V(16, 2.6, 2.4), V(-100, 1.3, -38), C.FoliageDark, X) -- hedges (cover)
	b.block(V(2.4, 2.6, 12), V(-66, 1.3, -50), C.FoliageDark, X)
	b.decor(function()
		b.block(V(16.3, 0.5, 2.7), V(-100, 2.4, -38), C.Foliage, X)
		b.block(V(2.7, 0.5, 12.3), V(-66, 2.4, -50), C.Foliage, X)
	end)
	bench(b, CFrame.new(-90, 0.3, -56), X)
	billboard(b, V(-92, 0, -33), 34, 12, 4, P.PlayerB, X) -- wall-runnable

	-- ELEVATED TRAIN TRACK (south, along the whole map) -----------------------
	b.block(V(440, 2, 14), V(0, 21, -75), C.Concrete)
	b.block(V(440, 0.6, 15), V(0, 20, -75), C.Trim)
	-- low walls with gaps where the stairs arrive (x = +-150)
	b.block(V(440, 1.6, 0.8), V(0, 22.8, -81.6), C.Curb)
	b.block(V(56, 1.6, 0.8), V(-182, 22.8, -68.4), C.Curb, X)
	b.block(V(292, 1.6, 0.8), V(0, 22.8, -68.4), C.Curb)
	b.decor(function()
		-- rails + sleepers
		b.block(V(440, 0.3, 0.4), V(0, 22.2, -77), C.Metal)
		b.block(V(440, 0.3, 0.4), V(0, 22.2, -73), C.Metal)
		for x = -216, -4, 4 do
			b.block(V(1, 0.15, 6), V(x, 22.05, -75), C.Trunk, X)
		end
		-- catenary masts + wire
		for x = -200, -20, 45 do
			b.block(V(0.6, 10, 0.6), V(x, 27, -81), C.Dark, X)
			b.block(V(0.4, 0.4, 7), V(x, 31.6, -77.8), C.Dark, X)
		end
		b.block(V(440, 0.12, 0.12), V(0, 31.2, -75), C.Dark)
		b.block(V(440, 1, 0.4), V(0, 20.3, -82.3), C.Dark) -- deck edge band
		b.block(V(440, 1, 0.4), V(0, 20.3, -67.7), C.Dark)
	end)
	-- pillars
	for _, x in ipairs({ -20, -70, -120, -170 }) do
		b.block(V(4, 20, 8), V(x, 10, -75), C.Concrete, X)
		b.decor(function()
			b.block(V(6, 1.5, 12), V(x, 19.25, -75), C.Trim, X)
			b.block(V(4.6, 1, 8.6), V(x, 0.5, -75), C.Trim, X)
			b.block(V(4.2, 0.4, 8.2), V(x, 12, -75), C.Curb, X)
		end)
	end
	-- stairs up (from the south sidewalk side), on steel supports
	stairs(b, V(-150, 0, -34), V(0, 0, -1), 34, 22, 6, C.Concrete, X)
	b.decor(function()
		for _, t in ipairs({ 0.3, 0.6, 0.85 }) do
			local z = -34 - 34 * t
			local h = 22 * t
			b.block(V(0.5, h, 0.5), V(-152.6, h / 2, z), C.Dark, X)
			b.block(V(0.5, h, 0.5), V(-147.4, h / 2, z), C.Dark, X)
		end
	end)
	-- the parked train (cover in the middle of the deck; stand on its roof)
	b.block(V(44, 8.5, 9), V(0, 26.5, -75), C.Train)
	b.decor(function()
		glass(b, b.block(V(44.2, 2.4, 9.2), V(0, 27.5, -75), C.Glass))
		for x = -20, 20, 4 do
			b.block(V(0.5, 2.5, 9.3), V(x, 27.5, -75), C.Train) -- window pillars
		end
		b.block(V(44.2, 0.6, 9.2), V(0, 24.4, -75), C.RoadWhite)
		b.block(V(44.2, 0.3, 9.2), V(0, 25.2, -75), P.AccentA)
		b.block(V(42, 0.6, 7), V(0, 31, -75), C.Trim)
		b.block(V(6, 1, 4), V(-10, 31.8, -75), C.Metal) -- roof units
		b.block(V(6, 1, 4), V(10, 31.8, -75), C.Metal)
		b.block(V(1.4, 2.4, 0.3), V(-14, 32.8, -75), C.Dark) -- pantograph
		for _, x in ipairs({ -8, 8 }) do -- doors
			b.block(V(3.2, 6.4, 9.3), V(x, 26, -75), C.Dark)
			glass(b, b.block(V(1.2, 2.4, 9.35), V(x - 0.8, 27.4, -75), C.Glass))
			glass(b, b.block(V(1.2, 2.4, 9.35), V(x + 0.8, 27.4, -75), C.Glass))
		end
		for _, x in ipairs({ -22.1, 22.1 }) do -- ends: doors + lights
			b.block(V(0.3, 6, 3), V(x, 25.4, -75), C.Dark)
			neon(b, b.block(V(0.3, 0.6, 1.2), V(x * 1.003, 24.4, -78), C.LampLight))
			neon(b, b.block(V(0.3, 0.6, 1.2), V(x * 1.003, 24.4, -72), C.LampLight))
		end
		for _, x in ipairs({ -15, 15 }) do -- bogies
			b.block(V(8, 1.2, 7), V(x, 22.6, -75), C.Dark)
			for _, dx in ipairs({ -2.5, 2.5 }) do
				for _, z in ipairs({ -78.3, -71.7 }) do
					wheel(b, CFrame.new(x + dx, 22.9, z) * CFrame.Angles(0, rad(90), 0), 1.8, 0.4, nil)
				end
			end
		end
	end)

	-- MARKET + SHOP (south, mirrored) -----------------------------------------
	stall(b, V(-62, 0, -100), C.Awning[1], X)
	stall(b, V(-34, 0, -100), C.Awning[2], X)
	stall(b, V(-34, 0, -116), C.Awning[3], X)
	crates(b, V(-50, 0, -110), X)
	building(b, -112, -122, 34, 26, 14, C.BuildingE, { "N", "E" }, X, { Storefront = { "N" } })
	crates(b, V(-92, 0, -112), X) -- climb onto the shop roof
	b.block(V(4, 8, 4), V(-91, 4, -118), C.Wood, X)
	acUnit(b, V(-118, 14.8, -128), X)

	-- SHIPPING CONTAINERS (climbable cover, mirrored): crate -> container -> stacked container
	local function container(cf, color)
		b.part(V(8, 8.5, 20), cf * CFrame.new(0, 4.25, 0), color, X)
		b.decor(function()
			for k = -3, 3 do
				b.part(V(8.1, 7.5, 0.4), cf * CFrame.new(0, 4.25, k * 2.6), C.Dark:Lerp(color, 0.6), X) -- ribs
			end
			b.part(V(8.1, 0.5, 20.1), cf * CFrame.new(0, 8.3, 0), C.Trim, X)
			b.part(V(8.1, 0.5, 20.1), cf * CFrame.new(0, 0.25, 0), C.Trim, X)
			b.part(V(7.4, 7.6, 0.2), cf * CFrame.new(0, 4.25, 10.05), C.Dark:Lerp(color, 0.4), X) -- doors
			for _, x in ipairs({ -1.2, 1.2 }) do
				b.part(V(0.2, 7.4, 0.3), cf * CFrame.new(x, 4.25, 10.15), C.Metal, X) -- lock bars
			end
		end)
	end
	container(CFrame.new(-150, 0, -98), C.Awning[1])
	container(CFrame.new(-140, 0, -98), C.Awning[2])
	container(CFrame.new(-145, 8.5, -101) * CFrame.Angles(0, rad(12), 0), C.Awning[3])
	crates(b, V(-158, 0, -88), X)

	-- WAREHOUSE (south, mirrored)
	building(b, -62, -132, 34, 20, 18, C.BuildingA, { "N" }, X, { WindowSpacing = 8 })
	b.decor(function()
		b.block(V(12, 10, 0.4), V(-62, 5, -121.9), C.Metal, X) -- roller door
		for y = 1, 9, 1.4 do
			b.block(V(12.1, 0.2, 0.5), V(-62, y, -121.8), C.Trim, X)
		end
		b.block(V(14, 1, 0.8), V(-62, 10.5, -121.6), P.AccentB, X)
		b.block(V(16, 0.4, 3), V(-62, 11.4, -120.6), C.Dark, X) -- loading canopy
	end)

	-- STATUE PLAZA (south centre)
	b.block(V(36, 0.5, 30), V(0, 0.25, -112), C.Sidewalk)
	b.block(V(8, 3, 8), V(0, 1.5, -112), C.Stone)
	b.decor(function()
		b.block(V(6, 0.6, 6), V(0, 3.3, -112), C.Trim)
		b.block(V(8.4, 0.4, 8.4), V(0, 0.7, -112), C.Trim)
		b.part(V(2.4, 9, 2.4), CFrame.new(0, 8, -112) * CFrame.Angles(0, rad(45), rad(12)), P.AccentA)
		b.ball(3.4, V(0.9, 12.8, -112), P.AccentB)
		b.block(V(4, 1, 0.2), V(0, 1.8, -107.9), C.Rim) -- plaque
	end)
	tree(b, V(-14, 0.5, -122), 0.9, X)
	tree(b, V(-14, 0.5, -102), 0.9, X)
	bench(b, CFrame.new(-8, 0.5, -125) * CFrame.Angles(0, rad(180), 0), X)

	-- PARKING LOT (south-west, mirrored) --------------------------------------
	b.decor(function()
		for i = 0, 4 do
			b.block(V(0.4, 0.08, 12), V(-198 + i * 8, 0.04, -112), C.RoadWhite, X)
		end
		for i = 0, 3 do -- wheel stops
			b.block(V(4, 0.4, 0.8), V(-194 + i * 8, 0.2, -117.5), C.Concrete, X)
		end
	end)
	car(b, CFrame.new(-194, 0, -112), C.CarColors[4], X)
	car(b, CFrame.new(-178, 0, -112), C.CarColors[5], X)
	car(b, CFrame.new(-170, 0, -96) * CFrame.Angles(0, rad(90), 0), C.CarColors[2], X)

	-- Spawns (on the station platforms, facing the city)
	local spawnHeight = 4.4 + 3.2
	return {
		CFrame.lookAt(V(-192, spawnHeight, 0), V(0, spawnHeight, 0)),
		CFrame.lookAt(V(192, spawnHeight, 0), V(0, spawnHeight, 0)),
	}, PLAYGROUND_DUMMIES
end

return ArenaDowntown
