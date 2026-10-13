--[[
	ArenaNuketown.lua  (ServerScriptService.Server.ArenaNuketown)

	"Nuketown": the classic 1960s test-site cul-de-sac, rebuilt 1:1 in layout
	with flat colours (no textures). Point-symmetric: the green house's side
	is the yellow house's side turned 180 degrees, so both spawns are fair.

	TOP VIEW (X = long axis, spawns in the backyards at the far left / right)

	   +------------------------------------------------------------------+
	   |   rocks / mannequins / test-site fence       [BUS]                 |
	   |  BACKYARD  |alley        | fence  street                 |GARAGE| |
	   |  (spawn)   [ YELLOW  ]    lawn                   lawn    [ GREEN ] |
	   |   shed     [ HOUSE   ] porch          car    porch    [ HOUSE ] (spawn)
	   |  table     |GARAGE|   driveway        car                    alley|
	   |                [TRUCK]          rocks / mannequins / fence        |
	   +------------------------------------------------------------------+

	  * Houses: two floors you can go into (front door, back door, door to the
	    garage), windows downstairs and upstairs (the upstairs bedrooms look
	    over the street), stairs, a pitched roof, furniture.
	  * Garages: open roller door onto the driveway, a door into the house.
	  * Backyards: fenced, with a patio, picnic table, swing set and a shed.
	  * Street: the school bus on one side, the box truck on the other, cars,
	    barriers, picket fences and front lawns.
	  * Map ends: rocks, the test-site fence and mannequins.

	Detail (trim, shutters, siding, furniture...) is decor: it doesn't collide.
]]

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local C = Config.MapPalette
local P = Config.Palette
local V = Vector3.new
local RGB = Color3.fromRGB
local rad = math.rad

local ArenaNuketown = {}

local DIRT = RGB(204, 184, 148)
local LAWN = RGB(150, 190, 112)
local YELLOW = { Wall = RGB(236, 206, 128), Trim = RGB(250, 246, 236), Roof = RGB(96, 104, 118), Door = RGB(176, 72, 60), Shutter = RGB(120, 150, 196) }
local GREEN = { Wall = RGB(160, 196, 156), Trim = RGB(250, 246, 236), Roof = RGB(112, 88, 82), Door = RGB(70, 110, 160), Shutter = RGB(196, 120, 96) }
local FENCE = RGB(244, 240, 230)
local WOOD = RGB(170, 128, 90)

----------------------------------------------------------------------------
-- One side of the map (house, garage, yards, a vehicle). `xf` places it:
-- identity for the yellow side, turned 180 degrees for the green side.
----------------------------------------------------------------------------
local function buildSide(b, xf, colors, vehicle)
	local function at(x, y, z)
		return xf * CFrame.new(x, y, z)
	end
	local function box(size, x, y, z, color, rot)
		return b.part(size, at(x, y, z) * (rot or CFrame.identity), color)
	end
	local function ramp(low, dir, length, height, width, color)
		return b.ramp((xf * CFrame.new(low)).Position, xf:VectorToWorldSpace(dir), length, height, width, color)
	end

	-- A wall at x = `x` running along Z from z1 to z2 (y1..y2) with openings
	-- { a, b, bottom, top } (z range, y range). outSign = which way is outside.
	local function wallZ(x, z1, z2, y1, y2, color, openings, outSign)
		table.sort(openings, function(p, q)
			return p[1] < q[1]
		end)
		local cursor = z1
		local function piece(za, zb, ya, yb)
			if zb - za > 0.05 and yb - ya > 0.05 then
				box(V(1, yb - ya, zb - za), x, (ya + yb) / 2, (za + zb) / 2, color)
			end
		end
		for _, o in ipairs(openings) do
			piece(cursor, o[1], y1, y2)
			piece(o[1], o[2], y1, o[3])
			piece(o[1], o[2], o[4], y2)
			cursor = o[2]
		end
		piece(cursor, z2, y1, y2)
		-- frames + shutters on the outside
		if outSign then
			b.decor(function()
				for _, o in ipairs(openings) do
					local fx = x + outSign * 0.6
					local zc, w, yc, h = (o[1] + o[2]) / 2, o[2] - o[1], (o[3] + o[4]) / 2, o[4] - o[3]
					box(V(0.3, 0.5, w + 1), fx, o[4] + 0.25, zc, colors.Trim)
					box(V(0.3, h, 0.4), fx, yc, o[1] - 0.2, colors.Trim)
					box(V(0.3, h, 0.4), fx, yc, o[2] + 0.2, colors.Trim)
					if o[3] > y1 + 0.5 then -- a window: sill + shutters
						box(V(0.6, 0.4, w + 1.2), fx + outSign * 0.15, o[3] - 0.2, zc, colors.Trim)
						box(V(0.2, h, 1.6), fx, yc, o[1] - 1.3, colors.Shutter)
						box(V(0.2, h, 1.6), fx, yc, o[2] + 1.3, colors.Shutter)
					end
				end
			end)
		end
	end
	-- Same, for a wall at z = `z` running along X from x1 to x2.
	local function wallX(z, x1, x2, y1, y2, color, openings, outSign)
		table.sort(openings, function(p, q)
			return p[1] < q[1]
		end)
		local cursor = x1
		local function piece(xa, xb, ya, yb)
			if xb - xa > 0.05 and yb - ya > 0.05 then
				box(V(xb - xa, yb - ya, 1), (xa + xb) / 2, (ya + yb) / 2, z, color)
			end
		end
		for _, o in ipairs(openings) do
			piece(cursor, o[1], y1, y2)
			piece(o[1], o[2], y1, o[3])
			piece(o[1], o[2], o[4], y2)
			cursor = o[2]
		end
		piece(cursor, x2, y1, y2)
		if outSign then
			b.decor(function()
				for _, o in ipairs(openings) do
					local fz = z + outSign * 0.6
					local xc, w, yc, h = (o[1] + o[2]) / 2, o[2] - o[1], (o[3] + o[4]) / 2, o[4] - o[3]
					box(V(w + 1, 0.5, 0.3), xc, o[4] + 0.25, fz, colors.Trim)
					box(V(0.4, h, 0.3), o[1] - 0.2, yc, fz, colors.Trim)
					box(V(0.4, h, 0.3), o[2] + 0.2, yc, fz, colors.Trim)
					if o[3] > y1 + 0.5 then
						box(V(w + 1.2, 0.4, 0.6), xc, o[3] - 0.2, fz + outSign * 0.15, colors.Trim)
						box(V(1.6, h, 0.2), o[1] - 1.3, yc, fz, colors.Shutter)
						box(V(1.6, h, 0.2), o[2] + 1.3, yc, fz, colors.Shutter)
					end
				end
			end)
		end
	end

	------------------------------------------------------------------------
	-- THE HOUSE (front faces +X at x = -38; back at x = -64; z from -18 to 12)
	------------------------------------------------------------------------
	box(V(26, 1, 30), -51, 0.5, -3, C.Concrete) -- ground floor
	-- outer walls: ground floor (y 1-11) and upstairs (y 11-21)
	wallZ(-38.5, -18, 12, 1, 11, colors.Wall, { { -6, -1, 1, 8 }, { 3, 9, 4, 8 } }, 1) -- front: door + window
	wallZ(-38.5, -18, 12, 11, 21, colors.Wall, { { -14, -8, 14, 18 }, { 2, 8, 14, 18 } }, 1) -- bedrooms over the street
	wallZ(-63.5, -18, 12, 1, 11, colors.Wall, { { -14, -8, 4, 8 }, { 4, 9, 1, 8 } }, -1) -- back: window + back door
	wallZ(-63.5, -18, 12, 11, 21, colors.Wall, { { -6, 0, 14, 18 } }, -1)
	wallX(-17.5, -63, -39, 1, 11, colors.Wall, { { -58, -54, 1, 8 }, { -46, -41, 4, 8 } }) -- south: door to the garage
	wallX(-17.5, -63, -39, 11, 21, colors.Wall, { { -56, -50, 14, 18 } }, -1)
	wallX(11.5, -63, -39, 1, 11, colors.Wall, { { -58, -52, 4, 8 }, { -47, -42, 4, 8 } }, 1) -- north (side alley)
	wallX(11.5, -63, -39, 11, 21, colors.Wall, { { -52, -46, 14, 18 } }, 1)
	-- upstairs floor (with a hole over the stairs) + stairs along the north wall
	box(V(26, 1, 24.5), -51, 11.5, -5.75, C.Concrete)
	box(V(8, 1, 5.5), -60, 11.5, 9.25, C.Concrete)
	box(V(3, 1, 5.5), -39.5, 11.5, 9.25, C.Concrete)
	ramp(V(-42, 1, 9), V(-1, 0, 0), 14, 11, 4, WOOD)
	-- upstairs wall between the two bedrooms (with a doorway)
	wallX(-4, -63, -46, 12, 21, colors.Wall, { { -50, -47, 12, 19 } })
	-- roof: two slopes, ridge along Z, eaves overhanging
	ramp(V(-36.5, 21, -3), V(-1, 0, 0), 14.5, 7, 33, colors.Roof)
	ramp(V(-65.5, 21, -3), V(1, 0, 0), 14.5, 7, 33, colors.Roof)
	box(V(3, 9, 3), -58, 25.5, 6, RGB(150, 90, 76)) -- chimney

	-- house detail
	b.decor(function()
		-- siding lines + corner boards + base trim
		for y = 2.5, 20, 1.5 do
			box(V(0.12, 0.12, 30), -37.94, y, -3, colors.Trim)
			box(V(0.12, 0.12, 30), -64.06, y, -3, colors.Trim)
		end
		for _, z in ipairs({ -18.2, 12.2 }) do
			box(V(26.6, 0.8, 0.5), -51, 11, z, colors.Trim) -- floor band
			for _, x in ipairs({ -38.2, -63.8 }) do
				box(V(0.6, 20, 0.6), x, 11, z, colors.Trim)
			end
		end
		box(V(0.5, 0.8, 30.6), -37.9, 11, -3, colors.Trim)
		box(V(0.5, 0.8, 30.6), -64.1, 11, -3, colors.Trim)
		box(V(27, 0.8, 31), -51, 1.1, -3, RGB(140, 140, 136)) -- foundation band
		-- roof: fascia, gutters, ridge cap, antenna
		box(V(0.5, 0.8, 33.4), -36.3, 21, -3, colors.Trim)
		box(V(0.5, 0.8, 33.4), -65.7, 21, -3, colors.Trim)
		box(V(1.2, 0.6, 33.4), -51, 28.1, -3, colors.Roof)
		box(V(0.3, 7, 0.3), -48, 31.5, -10, C.Metal)
		box(V(4, 0.2, 0.2), -48, 34, -10, C.Metal)
		box(V(3, 0.2, 0.2), -48, 33, -10, C.Metal)
		-- front door + porch light
		box(V(0.3, 7, 5), -38, 4.5, -3.5, colors.Door)
		box(V(0.4, 0.4, 0.4), -37.7, 4.5, -2, C.Rim)
		b.material(box(V(0.5, 0.7, 0.5), -37.6, 8.7, -7, C.LampLight), Enum.Material.Neon)
		-- INSIDE (ground floor): couch, TV, table + chairs, kitchen counter, fridge
		box(V(3, 2, 8), -61, 2, -10, RGB(150, 70, 60))
		box(V(3, 3, 8), -62.3, 2.5, -10, RGB(130, 60, 52))
		box(V(1.2, 2.4, 3), -45, 2.2, -10, C.Dark)
		box(V(1, 1.6, 2.8), -44.5, 4.2, -10, C.Glass)
		box(V(5, 0.3, 4), -53, 3.6, 2, WOOD)
		for _, o in ipairs({ { -55.5, 2 }, { -50.5, 2 }, { -53, 0 }, { -53, 4 } }) do
			box(V(1.4, 2.2, 1.4), o[1], 2.1, o[2], WOOD)
		end
		box(V(2.4, 3.4, 10), -62.4, 2.7, 4, RGB(220, 216, 206)) -- kitchen counter
		box(V(2.6, 0.3, 10.2), -62.4, 4.5, 4, C.Stone)
		box(V(2.6, 7, 3), -62.2, 4.5, -2, RGB(206, 226, 222)) -- fridge
		-- UPSTAIRS: beds, dresser, lamp; stair rail
		for _, z in ipairs({ -12, 4 }) do
			box(V(7, 1.6, 5), -59, 12.8, z, RGB(236, 236, 240))
			box(V(1, 3, 5), -62.6, 13.5, z, WOOD)
			box(V(2.4, 3.4, 1.4), -45, 13.7, z - 4, WOOD)
		end
		box(V(15, 0.3, 0.3), -48.5, 15, 6.4, WOOD)
		for x = -55, -42, 3.25 do
			box(V(0.25, 3, 0.25), x, 13.5, 6.4, WOOD)
		end
	end)

	------------------------------------------------------------------------
	-- GARAGE (south of the house, open onto the driveway)
	------------------------------------------------------------------------
	box(V(16, 1, 14), -54, 0.5, -25, C.Concrete)
	wallZ(-61.5, -32, -18, 1, 11, colors.Wall, {}, -1)
	wallX(-31.5, -62, -46, 1, 11, colors.Wall, { { -58, -53, 4, 8 } }, -1)
	wallZ(-46.5, -32, -18, 1, 11, colors.Wall, { { -30.5, -19.5, 1, 9 } }, 1) -- roller door opening
	box(V(17, 1, 15), -54, 11.5, -25, colors.Roof)
	b.decor(function()
		box(V(1.4, 1.6, 11), -46.5, 9.6, -25, RGB(200, 200, 196)) -- rolled-up door
		box(V(17.4, 0.5, 15.4), -54, 12.1, -25, colors.Trim)
		box(V(2.4, 3.2, 8), -60, 2.6, -25, WOOD) -- workbench
		box(V(1, 5, 6), -60.8, 7.5, -25, WOOD) -- shelves
		for k = 0, 2 do
			b.cylinder(1, 2.4, nil, C.Tire, nil, at(-49, 1.6 + k * 1, -30.5) * CFrame.Angles(0, 0, rad(90)))
		end
		box(V(12, 0.12, 11), -40, 0.06, -25, C.Concrete) -- driveway
		box(V(3, 0.12, 4), -36, 0.06, -3.5, C.Concrete) -- front walk
	end)

	------------------------------------------------------------------------
	-- FRONT YARD: porch, picket fence, lawn, bushes, mailbox
	------------------------------------------------------------------------
	box(V(4, 1, 9), -36, 0.5, -3.5, C.Concrete) -- porch
	b.decor(function()
		box(V(7, 0.06, 30), -34.5, 0.03, -3, LAWN)
		for _, z in ipairs({ -7.6, 0.6 }) do
			box(V(0.5, 8, 0.5), -34.3, 5, z, colors.Trim) -- porch posts
		end
		box(V(5, 0.4, 10), -35.8, 9, -3.5, colors.Roof, CFrame.Angles(0, 0, rad(-12)))
		b.soft(function()
			for _, z in ipairs({ -15, -11, 5, 9 }) do
				b.ball(3, at(-37, 1.2, z).Position, C.FoliageDark)
			end
		end)
		box(V(0.3, 3.4, 0.3), -31, 1.7, 8, C.Metal) -- mailbox
		box(V(1.2, 0.9, 0.8), -31, 3.6, 8, colors.Shutter)
	end)
	-- picket fence (low: hop over it), gaps at the walk and the driveway
	for _, seg in ipairs({ { -18, -5 }, { -2, 13 } }) do
		local z1, z2 = seg[1], seg[2]
		box(V(0.4, 2.4, z2 - z1), -31.5, 1.2, (z1 + z2) / 2, FENCE)
		b.decor(function()
			for z = z1 + 0.5, z2 - 0.4, 1 do
				box(V(0.5, 0.6, 0.5), -31.5, 2.6, z, FENCE, CFrame.Angles(rad(45), 0, 0))
			end
		end)
	end
	box(V(0.4, 2.4, 2), -31.5, 1.2, -33, FENCE)

	------------------------------------------------------------------------
	-- SIDE ALLEY + BACKYARD (spawn)
	------------------------------------------------------------------------
	box(V(0.8, 7, 54), -92, 3.5, -7, WOOD) -- back fence
	box(V(54, 7, 0.8), -65, 3.5, 20, WOOD) -- north fence (alley + yard)
	box(V(46, 7, 0.8), -69, 3.5, -34, WOOD) -- south fence
	box(V(8, 8, 8), -86, 4, 13, colors.Roof) -- shed
	box(V(4, 2.4, 7), -76, 1.2, 8, WOOD) -- picnic table
	box(V(3, 4, 3), -88, 2, -28, C.Concrete) -- rock pile cover
	b.decor(function()
		box(V(28, 0.06, 54), -78, 0.03, -7, LAWN)
		box(V(10, 0.3, 12), -69, 0.15, 0, C.Concrete) -- patio
		for z = -33, 19, 2 do
			box(V(1, 7.6, 0.3), -92, 3.8, z, RGB(150, 110, 78)) -- fence boards
		end
		box(V(8.4, 1, 8.4), -86, 8.5, 13, colors.Trim)
		box(V(0.2, 5, 3), -81.9, 3.5, 13, colors.Door) -- shed door
		for _, z in ipairs({ 6, 10 }) do
			box(V(4, 0.4, 1.4), -76, 1.6, z, WOOD) -- benches
		end
		-- swing set
		for _, z in ipairs({ -24, -14 }) do
			b.part(V(0.3, 9, 0.3), at(-83, 4.3, z) * CFrame.Angles(0, 0, rad(12)), C.Metal)
			b.part(V(0.3, 9, 0.3), at(-79, 4.3, z) * CFrame.Angles(0, 0, rad(-12)), C.Metal)
		end
		box(V(0.3, 0.3, 11), -81, 8.6, -19, C.Metal)
		for _, z in ipairs({ -21, -17 }) do
			box(V(0.1, 5, 0.1), -81, 6, z - 0.8, C.Dark)
			box(V(0.1, 5, 0.1), -81, 6, z + 0.8, C.Dark)
			box(V(1, 0.2, 1.8), -81, 3.5, z, P.AccentB)
		end
		-- grill + trash cans
		b.cylinder(1, 2.2, at(-70, 3, -10).Position, C.Dark)
		box(V(0.2, 2.6, 0.2), -70, 1.3, -10, C.Dark)
		for _, z in ipairs({ 16, 17.8 }) do
			b.cylinder(2.6, 1.6, at(-62, 1.3, z).Position, C.Metal)
		end
	end)

	------------------------------------------------------------------------
	-- STREET SIDE: sidewalk, a car, a barrier, the bus or the truck
	------------------------------------------------------------------------
	b.decor(function()
		box(V(3, 0.2, 116), -29.5, 0.1, 0, C.Sidewalk)
		box(V(0.6, 0.3, 116), -27.8, 0.15, 0, C.Curb)
		box(V(0.4, 0.06, 6), 0, 0.07, -50, C.RoadLine) -- dashes (the other side adds the rest)
		for z = -42, -6, 9 do
			box(V(0.4, 0.06, 5), 0, 0.07, z, C.RoadLine)
		end
		b.cylinder(2, 1, at(-30, 1, 14).Position, C.Hydrant) -- hydrant
	end)
	-- car by the driveway
	local carCf = at(-20, 0, -14) * CFrame.Angles(0, rad(75), 0)
	b.part(V(4.6, 1.6, 10), carCf * CFrame.new(0, 1.6, 0), colors.Shutter)
	b.invisible(b.part(V(4.1, 1.8, 5), carCf * CFrame.new(0, 3.3, 0.6), colors.Shutter))
	b.decor(function()
		b.part(V(4.2, 1.6, 5.2), carCf * CFrame.new(0, 3.3, 0.6), C.Glass)
		b.part(V(4.3, 0.3, 5.2), carCf * CFrame.new(0, 4.2, 0.6), colors.Shutter)
		b.part(V(4.8, 0.6, 0.5), carCf * CFrame.new(0, 1.2, -5.2), C.Rim)
		b.part(V(4.8, 0.6, 0.5), carCf * CFrame.new(0, 1.2, 5.2), C.Rim)
		for _, o in ipairs({ V(2.1, 1.1, 3.2), V(-2.1, 1.1, 3.2), V(2.1, 1.1, -3.2), V(-2.1, 1.1, -3.2) }) do
			b.cylinder(0.9, 2.2, nil, C.Tire, nil, carCf * CFrame.new(o))
			b.cylinder(0.95, 1.2, nil, C.Rim, nil, carCf * CFrame.new(o))
		end
		b.part(V(1, 0.4, 0.1), carCf * CFrame.new(1.6, 2, -5.05), C.LampLight)
		b.part(V(1, 0.4, 0.1), carCf * CFrame.new(-1.6, 2, -5.05), C.LampLight)
	end)
	-- concrete barrier in mid
	box(V(8, 1.4, 2.4), -4, 0.7, 12, C.Concrete)
	box(V(8, 1.8, 1.3), -4, 2.3, 12, C.Concrete)

	if vehicle == "Bus" then
		local bx, bz = -6, 30
		box(V(30, 8.6, 9), bx - 2, 5.5, bz, RGB(244, 190, 60)) -- body
		box(V(5, 4.4, 8.6), bx + 15.5, 3.4, bz, RGB(244, 190, 60)) -- hood
		b.decor(function()
			b.material(box(V(26, 2.6, 9.1), bx - 1, 6.8, bz, C.Glass), Enum.Material.SmoothPlastic, 0.15)
			for x = -14, 12, 2.8 do
				box(V(0.4, 2.7, 9.2), bx + x, 6.8, bz, RGB(244, 190, 60))
			end
			box(V(30.1, 0.5, 9.1), bx - 2, 4.6, bz, C.Dark)
			box(V(30.1, 0.5, 9.1), bx - 2, 3.4, bz, C.Dark)
			box(V(0.2, 3, 8), bx + 13.05, 7, bz, C.Glass) -- windscreen
			box(V(5.2, 0.8, 9), bx + 15.5, 1.6, bz, C.Dark) -- bumper
			box(V(0.2, 6, 2.8), bx + 10, 4.8, bz - 4.55, C.Dark) -- door
			box(V(6, 1, 2), bx - 2, 10.3, bz, P.PlayerB) -- roof light bar
			for _, x in ipairs({ -12, 8, 15 }) do
				for _, z in ipairs({ -4, 4 }) do
					b.cylinder(1, 2.8, nil, C.Tire, nil, at(bx + x, 1.4, bz + z) * CFrame.Angles(0, rad(90), 0))
				end
			end
		end)
	else -- the moving truck
		local tx, tz = -10, 30
		box(V(22, 11, 9), tx, 6.8, tz, RGB(240, 240, 236)) -- cargo box
		box(V(8, 7, 8.6), tx + 15, 4.6, tz, RGB(200, 64, 56)) -- cab
		b.decor(function()
			box(V(22.1, 3, 9.1), tx, 8, tz, RGB(200, 64, 56)) -- stripe
			box(V(0.3, 9, 8), tx - 11.1, 6.8, tz, RGB(200, 200, 196)) -- rear door
			b.material(box(V(0.2, 3, 7.6), tx + 19.05, 6, tz, C.Glass), Enum.Material.SmoothPlastic, 0.15)
			box(V(8.2, 0.8, 8.8), tx + 15, 1.4, tz, C.Dark)
			for _, x in ipairs({ -7, 0, 15 }) do
				for _, z in ipairs({ -4, 4 }) do
					b.cylinder(1, 2.8, nil, C.Tire, nil, at(tx + x, 1.4, tz + z) * CFrame.Angles(0, rad(90), 0))
				end
			end
		end)
	end

	------------------------------------------------------------------------
	-- MAP END (this side's half): rocks, test-site fence, mannequins
	------------------------------------------------------------------------
	for i, pos in ipairs({ V(-40, 0, 52), V(-22, 0, 56), V(14, 0, 54), V(32, 0, 50), V(46, 0, 56), V(-58, 0, 48) }) do
		b.ball(5 + (i % 3) * 2, at(pos.X, 1.5, pos.Z).Position, RGB(170, 150, 120))
	end
	b.decor(function()
		box(V(196, 8, 0.2), 0, 4, 60, C.Metal) -- chain-link fence
		for x = -96, 96, 8 do
			box(V(0.4, 9, 0.4), x, 4.5, 60, C.Dark)
		end
		-- mannequins standing around
		for _, pos in ipairs({ V(-26, 0, 44), V(10, 0, 46), V(-44, 0, 40) }) do
			box(V(1.6, 2.4, 1), pos.X, 4.4, pos.Z, RGB(230, 210, 190))
			box(V(0.7, 2.8, 0.7), pos.X - 0.45, 1.4, pos.Z, RGB(80, 100, 140))
			box(V(0.7, 2.8, 0.7), pos.X + 0.45, 1.4, pos.Z, RGB(80, 100, 140))
			b.ball(1.4, at(pos.X, 6.4, pos.Z).Position, RGB(230, 210, 190))
		end
	end)
end

function ArenaNuketown.Build(b)
	-- ground (desert dirt), street, invisible boundary
	b.block(V(240, 4, 160), V(0, -2, 0), DIRT)
	b.decor(function()
		b.block(V(55, 0.06, 116), V(0, 0.03, 0), C.Asphalt)
	end)
	for _, wall in ipairs({ { V(4, 80, 130), V(98, 40, 0) }, { V(200, 80, 4), V(0, 40, 62) } }) do
		local parts = b.block(wall[1], wall[2], C.Metal, wall[1].X < 10 and "X" or "Z")
		b.invisible(parts)
	end

	buildSide(b, CFrame.identity, YELLOW, "Bus")
	buildSide(b, CFrame.Angles(0, math.pi, 0), GREEN, "Truck")

	-- the sign (once)
	local signPart = b.block(V(16, 5, 0.6), V(0, 8, -54), RGB(250, 246, 236))[1]
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = signPart
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Text = "NUKETOWN  -  POPULATION 40"
	text.TextScaled = true
	text.FontFace = Font.new(Config.UI.FontFamily, Enum.FontWeight.Heavy)
	text.TextColor3 = RGB(200, 64, 56)
	text.Parent = gui
	b.decor(function()
		b.block(V(0.5, 8, 0.5), V(-6, 4, -54), C.Metal)
		b.block(V(0.5, 8, 0.5), V(6, 4, -54), C.Metal)
	end)

	local spawnHeight = 3.2
	local spawns = {
		CFrame.lookAt(V(-82, spawnHeight, -6), V(0, spawnHeight, -6)),
		CFrame.lookAt(V(82, spawnHeight, 6), V(0, spawnHeight, 6)),
	}
	local dummies = {
		{ Position = V(-51, 12, -8), Face = V(1, 0, 0) },
		{ Position = V(51, 12, 8), Face = V(-1, 0, 0) },
		{ Position = V(-8, 9.8, 30), Face = V(0, 0, -1) },
		{ Position = V(0, 0, 0), Motion = "Strafe", Amount = 10, Speed = 0.3, Face = V(-1, 0, 0) },
		{ Position = V(-54, 1, -25), Face = V(1, 0, 0) },
		{ Position = V(54, 1, 25), Face = V(-1, 0, 0) },
		{ Position = V(-76, 0, -14), Motion = "Bob", Amount = 6, Speed = 0.5, Face = V(1, 0, 0) },
		{ Position = V(20, 0, -40), Motion = "Strafe", Amount = 8, Speed = 0.3, Face = V(0, 0, 1) },
	}
	return spawns, dummies
end

return ArenaNuketown
