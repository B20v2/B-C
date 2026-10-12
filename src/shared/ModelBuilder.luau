--[[
	ModelBuilder
	Builds every asset in the game out of plain parts: a consistent, clean,
	low-poly style with zero external asset IDs. Used by the server (real
	buildings / units), and by the client (placement ghosts, build-menu
	thumbnails, projectiles, fuel trucks).

	Conventions
	  * Models are built at the origin, unrotated, footprint centered on X/Z,
	    ground at Y = 0. Width (w) runs along X, depth (d) along Z.
	  * Front of vehicles / launchers faces -Z (the CFrame LookVector).
	  * PrimaryPart is "Base" (buildings) or "Root" (units/projectiles).
	  * Animated sub-models carry attributes the client animator reads:
	      Spin = rad/s around the sub-model's local axis given by SpinAxis
	      Rock = amplitude (radians) for pump jacks
]]

local Config = require(script.Parent.Config)
local AssetLibrary = require(script.Parent.AssetLibrary)

local ModelBuilder = {}

local CELL = Config.CellSize
local G = 0.4 -- foundation slab height

local rgb = Color3.fromRGB
local C = {
	concrete = rgb(206, 206, 200),
	pad = rgb(186, 186, 180),
	wall = rgb(234, 233, 228),
	wallWarm = rgb(226, 216, 196),
	wallCool = rgb(214, 218, 222),
	panel = rgb(218, 214, 206),
	terracotta = rgb(180, 90, 66),
	slate = rgb(90, 98, 112),
	roofGrey = rgb(150, 152, 156),
	glass = rgb(72, 96, 120),
	window = rgb(64, 74, 88),
	metal = rgb(168, 172, 176),
	darkMetal = rgb(78, 82, 88),
	steel = rgb(120, 126, 132),
	olive = rgb(92, 102, 66),
	oliveDark = rgb(70, 78, 50),
	eastern = rgb(74, 94, 60),
	european = rgb(170, 156, 118),
	sand = rgb(178, 162, 120),
	red = rgb(192, 58, 48),
	orange = rgb(222, 132, 44),
	yellow = rgb(226, 182, 52),
	grass = rgb(104, 142, 80),
	leaf = rgb(80, 122, 62),
	leafLight = rgb(110, 150, 70),
	trunk = rgb(110, 84, 60),
	asphalt = rgb(74, 76, 80),
	line = rgb(226, 224, 214),
	water = rgb(86, 150, 196),
	white = rgb(245, 245, 242),
	black = rgb(30, 32, 36),
	brick = rgb(168, 104, 84),
	blue = rgb(70, 120, 200),
	solar = rgb(38, 58, 96),
}
ModelBuilder.Colors = C

---------------------------------------------------------------------------
-- Primitive helpers (operate on the model currently being built)
---------------------------------------------------------------------------
local M: Model

local function finish(p: BasePart, color: Color3, material: Enum.Material?)
	p.Anchored = true
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanTouch = false
	p.Parent = M
end

-- Box with its BOTTOM at y (easy stacking).
local function blk(sx: number, sy: number, sz: number, x: number, y: number, z: number, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Size = Vector3.new(sx, sy, sz)
	p.CFrame = CFrame.new(x, y + sy / 2, z)
	finish(p, color, material)
	return p
end

-- Box at an arbitrary center CFrame.
local function plank(sx: number, sy: number, sz: number, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Size = Vector3.new(sx, sy, sz)
	p.CFrame = cf
	finish(p, color, material)
	return p
end

-- Vertical cylinder, bottom at y.
local function cyl(h: number, d: number, x: number, y: number, z: number, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(h, d, d)
	p.CFrame = CFrame.new(x, y + h / 2, z) * CFrame.Angles(0, 0, math.rad(90))
	finish(p, color, material)
	return p
end

-- Cylinder whose axis is the X axis of cf.
local function axleCyl(len: number, d: number, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(len, d, d)
	p.CFrame = cf
	finish(p, color, material)
	return p
end

local function ball(d: number, x: number, y: number, z: number, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(d, d, d)
	p.CFrame = CFrame.new(x, y, z)
	finish(p, color, material)
	return p
end

local function noCollide(p: BasePart)
	p.CanCollide = false
	return p
end

-- Window pane: glows at night (see NightLights on the client).
local function lit(p: BasePart): BasePart
	p.CanCollide = false
	p:SetAttribute("Window", true)
	return p
end

-- Window bands around a box (centered x,z; floors stacked from y0).
local function windows(w: number, d: number, x: number, z: number, y0: number, floors: number, floorH: number, color: Color3?, gaps: boolean?)
	local col = color or C.window
	for f = 0, floors - 1 do
		local y = y0 + f * floorH + floorH * 0.32
		local h = floorH * 0.42
		lit(blk(w - 1, h, 0.2, x, y, z - d / 2 - 0.05, col))
		lit(blk(w - 1, h, 0.2, x, y, z + d / 2 + 0.05, col))
		lit(blk(0.2, h, d - 1, x - w / 2 - 0.05, y, z, col))
		lit(blk(0.2, h, d - 1, x + w / 2 + 0.05, y, z, col))
	end
	if gaps then
		-- vertical mullions so long facades read as individual windows
		local step = 3
		local n = math.floor((w - 1) / step)
		for i = 1, n - 1 do
			local px = x - (w - 1) / 2 + i * step
			noCollide(blk(0.35, floors * floorH - 0.6, 0.3, px, y0 + 0.3, z - d / 2 - 0.08, C.panel))
			noCollide(blk(0.35, floors * floorH - 0.6, 0.3, px, y0 + 0.3, z + d / 2 + 0.08, C.panel))
		end
	end
end

-- Gable roof built from two tilted planks; ridge runs along Z.
local function gableRoof(w: number, d: number, x: number, y: number, z: number, color: Color3, pitch: number?)
	local a = math.rad(pitch or 28)
	local half = w / 2
	local rise = half * math.tan(a)
	local len = half / math.cos(a) + 0.5
	plank(len, 0.4, d + 0.6, CFrame.new(x + half / 2, y + rise / 2, z) * CFrame.Angles(0, 0, -a), color)
	plank(len, 0.4, d + 0.6, CFrame.new(x - half / 2, y + rise / 2, z) * CFrame.Angles(0, 0, a), color)
	-- gable infill so the roof never looks hollow (kept inside the slopes)
	blk(w * 0.42, rise * 0.55, d - 0.2, x, y, z, C.wall)
	return rise
end

local function tree(x: number, z: number, s: number?)
	local k = s or 1
	noCollide(cyl(2.2 * k, 0.5 * k, x, G, z, C.trunk))
	noCollide(ball(3 * k, x, G + 3 * k, z, C.leaf))
	noCollide(ball(2 * k, x + 0.6 * k, G + 4 * k, z - 0.3 * k, C.leafLight))
end

local function wheelPair(x: number, y: number, z: number, track: number, d: number)
	axleCyl(0.7, d, CFrame.new(x - track / 2, y, z), C.black)
	axleCyl(0.7, d, CFrame.new(x + track / 2, y, z), C.black)
end

local function base(w: number, d: number, color: Color3?, h: number?): Part
	local p = blk(w, h or G, d, 0, 0, 0, color or C.concrete)
	p.Name = "Base"
	M.PrimaryPart = p
	return p
end

local function spinGroup(name: string, speed: number, axis: string): Model
	local sub = Instance.new("Model")
	sub.Name = name
	sub:SetAttribute("Spin", speed)
	sub:SetAttribute("SpinAxis", axis)
	sub.Parent = M
	return sub
end

-- Run fn with M temporarily pointing at a sub-model.
local function into(sub: Model, fn: () -> ())
	local prev = M
	M = sub
	fn()
	M = prev
end

---------------------------------------------------------------------------
-- Facade helpers: framed windows, doors and trims on any side of a box
---------------------------------------------------------------------------
-- A facade: centre (ox, oz), outward normal (nx, nz), along-facade axis (ax, az).
type Face = { ox: number, oz: number, nx: number, nz: number, ax: number, az: number }

local function faceOf(bw: number, bd: number, cx: number, cz: number, side: string): Face
	if side == "front" then
		return { ox = cx, oz = cz - bd / 2, nx = 0, nz = -1, ax = 1, az = 0 }
	elseif side == "back" then
		return { ox = cx, oz = cz + bd / 2, nx = 0, nz = 1, ax = -1, az = 0 }
	elseif side == "left" then
		return { ox = cx - bw / 2, oz = cz, nx = -1, nz = 0, ax = 0, az = -1 }
	end
	return { ox = cx + bw / 2, oz = cz, nx = 1, nz = 0, ax = 0, az = 1 }
end

-- Box stuck on a facade: `along` the wall, bottom at y, `out` from the wall.
local function onFace(f: Face, along: number, y: number, sa: number, sy: number, out: number, depth: number, color: Color3, material: Enum.Material?): Part
	local x = f.ox + f.ax * along + f.nx * (out + depth / 2)
	local z = f.oz + f.az * along + f.nz * (out + depth / 2)
	local sx = math.abs(f.ax) * sa + math.abs(f.nx) * depth
	local sz = math.abs(f.az) * sa + math.abs(f.nz) * depth
	local p = blk(sx, sy, sz, x, y, z, color, material)
	p.CanCollide = false
	return p
end

-- Window with a frame, a sill and optional shutters; the glass glows at night.
local function framedWindow(f: Face, along: number, y: number, ww: number, wh: number, frameC: Color3, shutterC: Color3?)
	onFace(f, along, y - 0.15, ww + 0.36, wh + 0.3, -0.02, 0.1, frameC)
	lit(onFace(f, along, y, ww, wh, 0.06, 0.06, C.window))
	onFace(f, along, y + wh / 2 - 0.05, ww, 0.1, 0.1, 0.04, frameC) -- transom bar
	onFace(f, along, y - 0.32, ww + 0.6, 0.18, 0, 0.32, frameC)
	if shutterC then
		for _, s in { -1, 1 } do
			onFace(f, along + s * (ww / 2 + 0.42), y, 0.5, wh, 0.02, 0.1, shutterC)
		end
	end
end

-- Front door with frame and a step.
local function door(f: Face, along: number, y: number, dw: number, dh: number, color: Color3, frameC: Color3)
	onFace(f, along, y, dw + 0.4, dh + 0.25, -0.02, 0.1, frameC)
	onFace(f, along, y, dw, dh, 0.06, 0.08, color)
	onFace(f, along + dw * 0.32, y + dh * 0.45, 0.14, 0.14, 0.12, 0.08, C.yellow) -- handle
	onFace(f, along, y - 0.25, dw + 0.8, 0.25, 0, 0.9, C.pad) -- step
end

-- Glowing ribbon of glass across a facade with mullions every `step` studs.
local function ribbon(f: Face, length: number, y: number, h: number, step: number, frameC: Color3)
	lit(onFace(f, 0, y, length, h, 0.02, 0.06, C.glass))
	local n = math.max(1, math.floor(length / step))
	for i = 1, n - 1 do
		onFace(f, -length / 2 + i * (length / n), y, 0.22, h, 0.06, 0.1, frameC)
	end
end

local function hedge(x: number, z: number, sx: number, sz: number)
	noCollide(blk(sx, 0.9, sz, x, G, z, C.leaf, Enum.Material.Grass))
end

local function picketFence(x0: number, x1: number, z: number)
	noCollide(blk(x1 - x0, 0.12, 0.12, (x0 + x1) / 2, G + 0.75, z, C.white))
	noCollide(blk(x1 - x0, 0.12, 0.12, (x0 + x1) / 2, G + 0.35, z, C.white))
	local n = math.max(2, math.floor((x1 - x0) / 1.6))
	for i = 0, n do
		noCollide(blk(0.16, 1.05, 0.16, x0 + (x1 - x0) * i / n, G, z, C.white))
	end
end

-- Low parapet ring around a flat roof.
local function parapet(bw: number, bd: number, cx: number, cz: number, y: number, color: Color3)
	blk(bw + 0.2, 0.7, 0.3, cx, y, cz - bd / 2 + 0.05, color)
	blk(bw + 0.2, 0.7, 0.3, cx, y, cz + bd / 2 - 0.05, color)
	blk(0.3, 0.7, bd, cx - bw / 2 + 0.05, y, cz, color)
	blk(0.3, 0.7, bd, cx + bw / 2 - 0.05, y, cz, color)
end

local function rooftopKit(bw: number, bd: number, cx: number, cz: number, y: number)
	blk(2.4, 1.4, 2, cx - bw * 0.25, y, cz + bd * 0.15, C.metal) -- AC unit
	noCollide(blk(1.6, 0.2, 1.6, cx - bw * 0.25, y + 1.4, cz + bd * 0.15, C.darkMetal))
	blk(2.6, 2.4, 2.6, cx + bw * 0.22, y, cz - bd * 0.1, C.wallCool) -- stair housing
	noCollide(cyl(2.2, 2.2, cx + bw * 0.3, y + 0.4, cz + bd * 0.25, C.brick)) -- water tank
	noCollide(blk(0.3, 0.4, 2.4, cx + bw * 0.3, y, cz + bd * 0.25, C.darkMetal))
end

local WALLS = { rgb(236, 226, 206), rgb(214, 196, 170), rgb(196, 214, 222), rgb(226, 206, 196), rgb(206, 220, 196) }
local SHUTTERS = { rgb(64, 92, 72), rgb(58, 84, 120), rgb(120, 60, 52), rgb(90, 90, 96) }

---------------------------------------------------------------------------
-- Building styles
---------------------------------------------------------------------------
local Styles: { [string]: (w: number, d: number, p: { [string]: any }) -> () } = {}

-- Suburban house: lawn, path, porch, framed windows with shutters, chimney,
-- picket fence and a tree. `long` adds a garage on the side.
Styles.house = function(w, d, p)
	local b = M.PrimaryPart :: BasePart
	b.Color = C.grass
	b.Material = Enum.Material.Grass
	local long = p.long == true
	local slate = p.roof == "slate"
	local bw = long and w - 2.6 or w - 2
	local bd = long and d - 5.6 or d - 3
	local cx = long and -0.6 or 0
	local cz = long and 1.4 or 0.8
	local wallC = slate and WALLS[3] or WALLS[1]
	local trim = C.white
	local shutter = slate and SHUTTERS[2] or SHUTTERS[1]
	local wallH = 4.6
	blk(bw + 0.4, 0.45, bd + 0.4, cx, G, cz, C.pad) -- foundation
	blk(bw, wallH, bd, cx, G + 0.45, cz, wallC)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			noCollide(blk(0.28, wallH, 0.28, cx + sx * bw / 2, G + 0.45, cz + sz * bd / 2, trim))
		end
	end
	noCollide(blk(bw + 0.3, 0.3, bd + 0.3, cx, G + 0.45 + wallH - 0.3, cz, trim)) -- eaves band
	local roofC = slate and C.slate or C.terracotta
	local top = G + 0.45 + wallH
	gableRoof(bw + 1.1, bd + 1, cx, top, cz, roofC, 34)
	-- chimney
	blk(0.9, 3.4, 0.9, cx + bw * 0.28, top, cz + bd * 0.2, C.brick)
	noCollide(blk(1.1, 0.25, 1.1, cx + bw * 0.28, top + 3.4, cz + bd * 0.2, C.darkMetal))
	-- front: door, porch roof, windows
	local front = faceOf(bw, bd, cx, cz, "front")
	door(front, 0, G + 0.45, 1.2, 2.4, slate and SHUTTERS[3] or C.trunk, trim)
	noCollide(plank(2.6, 0.18, 1.5, CFrame.new(cx, G + 3.25, cz - bd / 2 - 0.7) * CFrame.Angles(math.rad(-14), 0, 0), roofC))
	for _, s in { -1, 1 } do
		noCollide(blk(0.18, 2.8, 0.18, cx + s * 1.15, G + 0.45, cz - bd / 2 - 1.3, trim))
	end
	for _, s in { -1, 1 } do
		framedWindow(front, s * bw * 0.29, G + 1.55, 1.1, 1.3, trim, shutter)
	end
	-- attic window in the gable
	lit(onFace(front, 0, top + 0.6, 0.8, 0.8, 0.06, 0.06, C.window))
	for _, side in { "left", "right" } do
		local f = faceOf(bw, bd, cx, cz, side)
		framedWindow(f, -bd * 0.2, G + 1.55, 1.0, 1.3, trim, nil)
		framedWindow(f, bd * 0.22, G + 1.55, 1.0, 1.3, trim, nil)
	end
	framedWindow(faceOf(bw, bd, cx, cz, "back"), 0, G + 1.55, 1.6, 1.3, trim, nil)
	-- garden: path, fence, hedge, tree, mailbox
	local frontEdge = -d / 2 + 0.3
	noCollide(blk(1.1, 0.06, (cz - bd / 2) - frontEdge, cx, G, (frontEdge + cz - bd / 2) / 2, rgb(206, 196, 176)))
	picketFence(-w / 2 + 0.3, cx - 0.8, frontEdge)
	picketFence(cx + 0.8, w / 2 - 0.3, frontEdge)
	hedge(cx - bw * 0.3, cz - bd / 2 - 1.1, bw * 0.3, 0.7)
	tree(w / 2 - 1.2, d / 2 - 1.2, 0.75)
	noCollide(blk(0.14, 1.1, 0.14, cx + 1.4, G, frontEdge + 0.4, C.darkMetal))
	noCollide(blk(0.4, 0.3, 0.6, cx + 1.4, G + 1.1, frontEdge + 0.4, C.blue))
	if long then
		-- single garage on the right with its own little roof
		local gx = cx + bw / 2 + 1.25
		blk(2.3, 3, bd * 0.6, gx, G + 0.45, cz - bd * 0.2, wallC)
		noCollide(blk(2.6, 0.3, bd * 0.6 + 0.4, gx, G + 3.45, cz - bd * 0.2, roofC))
		noCollide(blk(1.9, 2.3, 0.1, gx, G + 0.45, cz - bd * 0.2 - bd * 0.3 - 0.05, C.wallCool))
		noCollide(blk(1.6, 0.06, cz - bd * 0.5 - frontEdge, gx, G, (frontEdge + cz - bd * 0.5) / 2, C.asphalt))
	end
end

-- Terrace of distinct homes: colours, stoops, bay windows, two floors.
Styles.townhouse = function(w, d, p)
	local n = p.count or 3
	local each = w / n
	local bd = d - 2.2
	local cz = 0.7
	local floors = 2
	local fh = 3.3
	for i = 1, n do
		local x = -w / 2 + each * (i - 0.5)
		local bw = each - 0.15
		local wallC = WALLS[(i + 1) % #WALLS + 1]
		local trim = C.white
		blk(bw, floors * fh + 0.5, bd, x, G, cz, wallC)
		noCollide(blk(bw + 0.1, 0.35, bd + 0.1, x, G + floors * fh, cz, trim)) -- cornice
		local roofC = i % 2 == 0 and C.slate or C.terracotta
		gableRoof(bw + 0.2, bd + 0.6, x, G + floors * fh + 0.5, cz, roofC, 30)
		blk(0.7, 2.4, 0.7, x + bw * 0.3, G + floors * fh + 1.2, cz + bd * 0.25, C.brick)
		local front = faceOf(bw, bd, x, cz, "front")
		local doorAt = (i % 2 == 0) and -bw * 0.25 or bw * 0.25
		door(front, doorAt, G + 0.6, 1.1, 2.4, SHUTTERS[(i % #SHUTTERS) + 1], trim)
		onFace(front, doorAt, G, 1.8, 0.6, 0, 1.1, C.pad) -- stoop
		-- ground-floor bay window
		local bayAt = -doorAt
		onFace(front, bayAt, G + 0.5, 2.2, 2.4, 0, 0.9, wallC)
		lit(onFace(front, bayAt, G + 1.1, 1.8, 1.5, 0.9, 0.06, C.window))
		noCollide(onFace(front, bayAt, G + 2.9, 2.4, 0.2, 0, 1.0, trim))
		-- upper windows
		framedWindow(front, -bw * 0.25, G + fh + 1.1, 1.1, 1.4, trim, nil)
		framedWindow(front, bw * 0.25, G + fh + 1.1, 1.1, 1.4, trim, nil)
		local back = faceOf(bw, bd, x, cz, "back")
		ribbon(back, bw - 1.2, G + 1.3, 1.3, 1.5, trim)
		ribbon(back, bw - 1.2, G + fh + 1.3, 1.3, 1.5, trim)
		hedge(x, -d / 2 + 0.6, bw - 1.2, 0.6)
	end
end

-- Mid-rise apartments: base storey, coloured body, window grid, balconies,
-- entrance canopies and a busy flat roof.
Styles.apartment = function(w, d, p)
	local floors = p.floors or 4
	local fh = 3.2
	local bw, bd = w - 1.6, d - 1.8
	local bodyC = WALLS[(math.floor(w) % #WALLS) + 1]
	local trim = rgb(240, 238, 230)
	blk(bw, fh, bd, 0, G, 0, rgb(170, 168, 162)) -- ground floor
	blk(bw, (floors - 1) * fh, bd, 0, G + fh, 0, bodyC)
	local top = G + floors * fh
	noCollide(blk(bw + 0.4, 0.4, bd + 0.4, 0, G + fh - 0.2, 0, trim)) -- floor band
	parapet(bw, bd, 0, 0, top, trim)
	local front = faceOf(bw, bd, 0, 0, "front")
	local back = faceOf(bw, bd, 0, 0, "back")
	local bays = math.max(2, math.floor(bw / 5))
	local bayW = bw / bays
	for f = 1, floors - 1 do
		local y = G + f * fh + 0.9
		ribbon(front, bw - 1, y, 1.5, bayW / 2, trim)
		ribbon(back, bw - 1, y, 1.5, bayW / 2, trim)
		-- balconies on alternating bays
		for i = 1, bays do
			if (i + f) % 2 == 0 then
				local along = -bw / 2 + (i - 0.5) * bayW
				onFace(front, along, y - 0.95, bayW * 0.8, 0.25, 0, 1.3, trim)
				lit(onFace(front, along, y - 0.7, bayW * 0.8, 0.9, 1.25, 0.06, rgb(150, 190, 210)))
			end
		end
	end
	for _, side in { "left", "right" } do
		local f = faceOf(bw, bd, 0, 0, side)
		for fl = 1, floors - 1 do
			framedWindow(f, 0, G + fl * fh + 0.9, 1.1, 1.5, trim, nil)
		end
	end
	-- ground floor: glass lobby per stairwell + canopy
	local doors = math.max(1, math.floor(bw / 12))
	for i = 1, doors do
		local along = -bw / 2 + (i - 0.5) * (bw / doors)
		lit(onFace(front, along, G + 0.3, 2.6, 2.5, 0.02, 0.06, C.glass))
		onFace(front, along, G + 2.9, 3.6, 0.25, 0, 1.6, C.darkMetal)
		onFace(front, along, G, 3.4, 0.3, 0, 1.8, C.pad)
	end
	ribbon(back, bw - 1, G + 0.9, 1.4, 2.5, trim)
	rooftopKit(bw, bd, 0, 0, top)
end

-- Residential highrise: podium, slim shaft with corner balconies, crown.
Styles.tower = function(w, d, p)
	local floors = p.floors or 14
	local fh = 3.1
	local pw, pd = w - 0.8, d - 0.8
	blk(pw, 4.2, pd, 0, G, 0, rgb(120, 126, 132)) -- podium
	lit(onFace(faceOf(pw, pd, 0, 0, "front"), 0, G + 0.4, pw - 2, 3, 0.02, 0.06, C.glass))
	noCollide(blk(pw + 0.3, 0.4, pd + 0.3, 0, G + 4.2, 0, rgb(236, 236, 230)))
	local bw, bd = w - 3, d - 3
	local base = G + 4.6
	blk(bw, floors * fh, bd, 0, base, 0, rgb(232, 230, 222))
	for _, side in { "front", "back", "left", "right" } do
		local f = faceOf(bw, bd, 0, 0, side)
		for fl = 0, floors - 1 do
			ribbon(f, bw - 1.2, base + fl * fh + 0.8, 1.6, bw / 3, rgb(210, 210, 204))
		end
		-- vertical accent fin down the middle
		onFace(f, 0, base, 0.5, floors * fh, 0, 0.5, rgb(64, 96, 132))
	end
	-- corner balconies every other floor
	for fl = 1, floors - 1, 2 do
		for _, sx in { -1, 1 } do
			noCollide(blk(2.2, 0.25, 2.2, sx * (bw / 2 - 0.6), base + fl * fh, -bd / 2 - 0.5, rgb(236, 236, 230)))
		end
	end
	local top = base + floors * fh
	blk(bw - 1.4, 2.6, bd - 1.4, 0, top, 0, rgb(64, 96, 132)) -- crown
	noCollide(blk(bw + 0.2, 0.4, bd + 0.2, 0, top, 0, rgb(236, 236, 230)))
	noCollide(cyl(6, 0.3, 0, top + 2.6, 0, C.metal))
	local beacon = noCollide(ball(0.7, 0, top + 8.8, 0, C.red, Enum.Material.Neon))
	beacon.Name = "Beacon"
end

Styles.road = function(w, d, _p)
	local p = blk(w, 0.3, d, 0, 0, 0, C.asphalt)
	p.Name = "Base"
	M.PrimaryPart = p
end

Styles.plaza = function(w, d, _p)
	local b = M.PrimaryPart :: BasePart
	b.Color = rgb(196, 190, 176)
	cyl(0.8, 6, 0, G, 0, C.pad)
	cyl(0.85, 5, 0, G, 0, C.water, Enum.Material.Glass).Transparency = 0.2
	noCollide(cyl(2.4, 0.6, 0, G, 0, C.pad))
	tree(-w / 2 + 2, -d / 2 + 2, 0.8)
	tree(w / 2 - 2, d / 2 - 2, 0.8)
	tree(w / 2 - 2, -d / 2 + 2, 0.8)
	tree(-w / 2 + 2, d / 2 - 2, 0.8)
end

Styles.windTurbine = function(_w, _d, _p)
	cyl(1, 2.4, 0, G, 0, C.pad)
	cyl(30, 1.1, 0, G + 1, 0, C.white)
	local top = G + 31
	blk(1.6, 1.6, 3.2, 0, top - 0.4, 0.2, C.white)
	local rotor = spinGroup("Rotor", 1.6, "X")
	into(rotor, function()
		local hubCF = CFrame.new(0, top + 0.4, -1.7)
		local hub = axleCyl(0.8, 1.2, hubCF * CFrame.Angles(0, math.rad(90), 0), C.white)
		hub.Name = "Hub"
		rotor.PrimaryPart = hub
		for k = 0, 2 do
			noCollide(plank(0.7, 12, 0.25, hubCF * CFrame.Angles(0, 0, math.rad(k * 120)) * CFrame.new(0, 6.2, 0), C.white))
		end
	end)
end

Styles.solarFarm = function(w, d, _p)
	local rows = math.floor((d - 2) / 4)
	for r = 0, rows - 1 do
		local z = -d / 2 + 2.5 + r * 4
		for _, x in { -w / 4, w / 4 } do
			noCollide(blk(0.3, 1.2, 0.3, x, G, z, C.metal))
		end
		local panel = plank(w - 2, 0.2, 2.8, CFrame.new(0, G + 1.6, z) * CFrame.Angles(math.rad(-25), 0, 0), C.solar)
		panel.Reflectance = 0.15
	end
end

local function stripedChimney(x: number, z: number, h: number, dia: number)
	local seg = h / 6
	for i = 0, 5 do
		cyl(seg, dia, x, G + i * seg, z, i % 2 == 0 and C.white or C.red)
	end
end

local function coolingTower(x: number, z: number, scale: number)
	local s = scale
	cyl(5 * s, 14 * s, x, G, z, C.wallCool)
	cyl(5 * s, 12.5 * s, x, G + 5 * s, z, C.wallCool)
	cyl(4 * s, 11.5 * s, x, G + 10 * s, z, C.wallCool)
	cyl(4 * s, 12.2 * s, x, G + 14 * s, z, C.wallCool)
	cyl(0.8 * s, 12.5 * s, x, G + 17.4 * s, z, C.red)
	-- dark interior so the top reads as hollow
	noCollide(cyl(0.2, 10.5 * s, x, G + 18.1 * s, z, C.darkMetal))
end

Styles.coalPlant = function(w, d, _p)
	blk(w * 0.55, 12, d * 0.62, -w * 0.18, G, -d * 0.12, C.wallCool)
	windows(w * 0.55, d * 0.62, -w * 0.18, -d * 0.12, G + 2, 3, 3.4, C.window)
	blk(w * 0.25, 18, d * 0.35, -w * 0.3, G, d * 0.28, C.metal)
	stripedChimney(-w * 0.08, d * 0.32, 34, 2.6)
	stripedChimney(-w * 0.18, d * 0.32, 34, 2.6)
	coolingTower(w * 0.28, -d * 0.12, 1)
	-- coal pile
	local pile = cyl(2.5, 9, w * 0.3, G, d * 0.3, C.black)
	pile.Material = Enum.Material.Slate
end

Styles.nuclearPlant = function(w, d, _p)
	coolingTower(-w * 0.26, -d * 0.2, 1.45)
	coolingTower(w * 0.02, -d * 0.24, 1.45)
	-- reactor
	cyl(10, 14, w * 0.3, G, d * 0.18, C.wall)
	ball(14, w * 0.3, G + 10, d * 0.18, C.wall)
	-- turbine hall
	blk(w * 0.5, 9, d * 0.28, -w * 0.15, G, d * 0.3, C.wallCool)
	windows(w * 0.5, d * 0.28, -w * 0.15, d * 0.3, G + 1.5, 2, 3.4)
	blk(w * 0.5, 0.5, 1.2, -w * 0.15, G + 9, d * 0.3, C.red)
	-- switchyard
	for i = 0, 3 do
		noCollide(blk(0.5, 6, 0.5, w * 0.42, G, -d * 0.4 + i * 4, C.metal))
	end
end

Styles.waterTower = function(_w, _d, _p)
	for _, o in { Vector3.new(-1.6, 0, -1.6), Vector3.new(1.6, 0, -1.6), Vector3.new(-1.6, 0, 1.6), Vector3.new(1.6, 0, 1.6) } do
		blk(0.5, 14, 0.5, o.X, G, o.Z, C.metal)
	end
	cyl(14, 1, 0, G, 0, C.metal)
	ball(7.5, 0, G + 17, 0, C.white)
	cyl(1, 7.6, 0, G + 16.3, 0, C.white)
end

Styles.pumpStation = function(w, d, _p)
	blk(w * 0.45, 6, d * 0.4, -w * 0.22, G, -d * 0.22, C.wallWarm)
	gableRoof(w * 0.45, d * 0.4, -w * 0.22, G + 6, -d * 0.22, C.slate, 18)
	for _, x in { w * 0.18, -w * 0.18 } do
		cyl(1.2, d * 0.36, x, G, d * 0.22, C.pad)
		cyl(1.25, d * 0.3, x, G, d * 0.22, C.water, Enum.Material.Glass).Transparency = 0.15
	end
	axleCyl(w * 0.5, 0.8, CFrame.new(w * 0.12, G + 1.4, -d * 0.22), C.blue)
end

Styles.oilPump = function(w, d, _p)
	blk(2.4, 0.6, d - 1, 0, G, 0, C.darkMetal)
	-- A-frame
	plank(0.4, 5.2, 0.4, CFrame.new(-0.7, G + 2.8, 0) * CFrame.Angles(0, 0, math.rad(-8)), C.darkMetal)
	plank(0.4, 5.2, 0.4, CFrame.new(0.7, G + 2.8, 0) * CFrame.Angles(0, 0, math.rad(8)), C.darkMetal)
	blk(1, 1.2, 1.4, 0, G + 0.6, d / 2 - 1.6, C.darkMetal) -- motor
	local beam = Instance.new("Model")
	beam.Name = "Beam"
	beam:SetAttribute("Rock", math.rad(16))
	beam.Parent = M
	into(beam, function()
		local pivot = plank(0.6, 0.6, 0.6, CFrame.new(0, G + 5.4, 0), C.darkMetal)
		pivot.Name = "Pivot"
		beam.PrimaryPart = pivot
		plank(0.6, 0.7, d - 1.4, CFrame.new(0, G + 5.6, 0), C.orange)
		plank(0.9, 2.2, 1, CFrame.new(0, G + 5.2, -d / 2 + 1), C.orange) -- horse head
		plank(1, 1.2, 1, CFrame.new(0, G + 5.2, d / 2 - 1.2), C.darkMetal)
	end)
	noCollide(blk(0.2, 4.5, 0.2, 0, G, -d / 2 + 0.9, C.black)) -- polished rod
	local _ = w
end

Styles.oilTank = function(w, d, _p)
	for _, o in { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(1, 1) } do
		local x, z = o.X * w / 4, o.Y * d / 4
		cyl(5, w / 2 - 1, x, G, z, C.white)
		cyl(0.3, w / 2 - 0.9, x, G + 5, z, C.metal)
	end
end

Styles.refinery = function(w, d, p)
	local s = p.scale or 1
	-- control building
	blk(w * 0.3, 5, d * 0.25, -w * 0.3, G, -d * 0.33, C.wall)
	windows(w * 0.3, d * 0.25, -w * 0.3, -d * 0.33, G + 1, 1, 3.4)
	-- storage tanks
	local tankD = math.min(w, d) * 0.22
	local tanks = { Vector2.new(-0.28, 0.18), Vector2.new(-0.28, -0.05) }
	if s >= 2 then
		table.insert(tanks, Vector2.new(0.32, 0.3))
	end
	if s >= 3 then
		table.insert(tanks, Vector2.new(0.32, 0.05))
	end
	for _, t in tanks do
		cyl(4 + s, tankD, t.X * w, G, t.Y * d, C.white)
		cyl(0.3, tankD + 0.1, t.X * w, G + 4 + s, t.Y * d, C.metal)
	end
	-- distillation columns
	for i = 0, s do
		local x = w * (0.02 + i * 0.09)
		cyl(14 + s * 4 - i * 2, 1.8, x, G, -d * 0.12, C.metal)
		cyl(0.6, 2.1, x, G + 6, -d * 0.12, C.darkMetal)
	end
	-- pipe rack
	blk(w * 0.7, 0.5, 1.2, 0, G + 3, d * 0.05, C.steel)
	for i = 0, 4 do
		noCollide(blk(0.4, 3, 0.4, -w * 0.35 + i * w * 0.175, G, d * 0.05, C.steel))
	end
	-- flare stack
	cyl(16 + s * 4, 0.8, w * 0.4, G, -d * 0.38, C.metal)
	cyl(1.2, 1, w * 0.4, G + 16 + s * 4, -d * 0.38, C.red)
end

Styles.steelMill = function(w, d, _p)
	blk(w * 0.7, 12, d * 0.65, -w * 0.1, G, 0, C.steel)
	blk(w * 0.7 + 0.2, 1, d * 0.65 + 0.2, -w * 0.1, G + 8, 0, C.orange)
	gableRoof(w * 0.7, d * 0.65, -w * 0.1, G + 12, 0, C.darkMetal, 14)
	for i = 0, 2 do
		cyl(26, 1.8, w * 0.36, G, -d * 0.3 + i * d * 0.3, C.darkMetal)
		cyl(1, 2, w * 0.36, G + 22, -d * 0.3 + i * d * 0.3, C.orange)
	end
	plank(w * 0.4, 0.6, 1.2, CFrame.new(w * 0.15, G + 6, -d * 0.4) * CFrame.Angles(0, 0, math.rad(-18)), C.darkMetal)
end

Styles.warehouse = function(w, d, _p)
	blk(w - 1.2, 7, d - 1.2, 0, G, 0, C.wallCool)
	gableRoof(w - 1.2, d - 1.2, 0, G + 7, 0, C.roofGrey, 12)
	local doors = math.max(2, math.floor(w / 8))
	for i = 1, doors do
		local x = -w / 2 + (i - 0.5) * (w / doors)
		noCollide(blk(3, 4.5, 0.25, x, G, -d / 2 + 0.5, C.darkMetal))
	end
end

Styles.factory = function(w, d, p)
	local military = p.tint == "military"
	local wallC = military and rgb(150, 154, 132) or C.wallWarm
	local roofC = military and C.oliveDark or C.roofGrey
	local bw, bd = w - 1.6, d - 1.6
	local h = p.large and 10 or 8
	blk(bw, h, bd, 0, G, 0, wallC)
	-- sawtooth roof
	local teeth = math.max(2, math.floor(bd / 6))
	local step = bd / teeth
	for i = 0, teeth - 1 do
		local z = -bd / 2 + (i + 0.5) * step
		plank(bw, 0.4, step / math.cos(math.rad(30)), CFrame.new(0, G + h + step * 0.29, z) * CFrame.Angles(math.rad(-30), 0, 0), roofC)
		noCollide(blk(bw - 0.4, step * 0.55, 0.2, 0, G + h, z + step / 2 - 0.15, C.glass))
	end
	lit(blk(bw - 2, 1.4, 0.2, 0, G + 3, -bd / 2 - 0.1, C.window))
	for i = 1, (p.large and 3 or 2) do
		noCollide(blk(3.4, 4.4, 0.3, -bw / 2 + i * bw / ((p.large and 3 or 2) + 1), G, bd / 2 + 0.1, C.darkMetal))
	end
	cyl(h + 10, 1.6, bw / 2 - 2, G, -bd / 2 + 2, military and C.oliveDark or C.brick)
	if military then
		blk(4, 0.2, 4, -bw / 2 + 3, G + h + 0.1, -bd / 2 + 3, C.red).CanCollide = false
	end
end

-- Corner shop: brick, big display windows, striped awning, sign and bins.
Styles.shop = function(w, d, p)
	local bw, bd = w - 1.6, d - 1.8
	local cz = 0.3
	local brick = rgb(176, 104, 78)
	blk(bw, 5, bd, 0, G, cz, brick)
	noCollide(blk(bw + 0.4, 0.5, bd + 0.4, 0, G + 5, cz, rgb(236, 230, 214))) -- cornice
	local front = faceOf(bw, bd, 0, cz, "front")
	-- display windows either side of the door
	for _, s in { -1, 1 } do
		onFace(front, s * bw * 0.27, G + 0.5, bw * 0.36 + 0.3, 2.9, -0.02, 0.1, rgb(48, 54, 52))
		lit(onFace(front, s * bw * 0.27, G + 0.65, bw * 0.36, 2.6, 0.06, 0.06, C.glass))
	end
	door(front, 0, G, 1.3, 2.8, rgb(48, 54, 52), rgb(48, 54, 52))
	-- striped awning
	local stripes = 6
	for i = 1, stripes do
		local along = -bw / 2 + (i - 0.5) * (bw / stripes)
		local x = along
		noCollide(plank(bw / stripes, 0.15, 1.7, CFrame.new(x, G + 3.75, cz - bd / 2 - 0.75) * CFrame.Angles(math.rad(20), 0, 0), i % 2 == 0 and C.white or rgb(196, 58, 52)))
	end
	-- sign board with a name
	local board = noCollide(onFace(front, 0, G + 4.05, bw * 0.7, 0.85, 0, 0.2, rgb(34, 58, 52)))
	board.Name = "ShopSign"
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(300, 50)
	gui.LightInfluence = 0.3
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = rgb(250, 226, 160)
	label.TextScaled = true
	label.FontFace = Font.new("rbxasset://fonts/families/Sarpanch.json", Enum.FontWeight.Bold)
	label.Text = p.label or "CORNER SHOP"
	label.Parent = gui
	-- side window, roof unit, bins
	framedWindow(faceOf(bw, bd, 0, cz, "right"), 0, G + 1.4, 1.6, 1.4, rgb(236, 230, 214), nil)
	blk(2.2, 1.2, 1.6, -bw * 0.2, G + 5.5, cz + bd * 0.15, C.metal)
	for i = 0, 1 do
		noCollide(blk(0.8, 1.1, 0.8, -w / 2 + 1 + i * 1, G, d / 2 - 0.8, i == 0 and rgb(58, 110, 70) or C.darkMetal))
	end
end

Styles.park = function(w, d, _p)
	local b = M.PrimaryPart :: BasePart
	b.Color = C.grass
	b.Material = Enum.Material.Grass
	noCollide(blk(w - 0.5, 0.06, 1.2, 0, G, 0, rgb(214, 200, 168)))
	noCollide(blk(1.2, 0.06, d - 0.5, 0, G, 0, rgb(214, 200, 168)))
	tree(-w / 4, -d / 4, 1)
	tree(w / 4, d / 4, 1.2)
	tree(w / 4, -d / 4, 0.9)
	cyl(0.15, w / 3, -w / 4, G, d / 4, C.water, Enum.Material.Glass).CanCollide = false
	noCollide(blk(1.6, 0.5, 0.5, 2, G + 0.3, -1.2, C.trunk))
end

-- Office block: glass curtain wall with spandrels and mullions, a recessed
-- double-height lobby with columns, plant room and a rooftop sign.
Styles.office = function(w, d, p)
	local floors = p.floors or 8
	local fh = 3.3
	local bw, bd = w - 2, d - 2
	local lobbyH = fh * 1.4
	-- lobby: recessed glass box behind columns
	lit(blk(bw - 1.6, lobbyH, bd - 1.6, 0, G, 0, C.glass, Enum.Material.Glass))
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			blk(0.9, lobbyH, 0.9, sx * (bw / 2 - 0.45), G, sz * (bd / 2 - 0.45), rgb(206, 208, 210))
		end
		blk(0.8, lobbyH, 0.8, sx * bw * 0.18, G, -bd / 2 + 0.45, rgb(206, 208, 210))
	end
	noCollide(blk(bw * 0.5, 0.3, 2.2, 0, G + lobbyH - 1.1, -bd / 2 - 0.6, C.darkMetal)) -- entrance canopy
	local base = G + lobbyH
	local bodyH = (floors - 1) * fh
	lit(blk(bw, bodyH, bd, 0, base, 0, rgb(58, 84, 108), Enum.Material.Glass))
	for f = 0, floors - 1 do
		noCollide(blk(bw + 0.25, 0.55, bd + 0.25, 0, base + f * fh, 0, rgb(214, 218, 222)))
	end
	for _, side in { "front", "back", "left", "right" } do
		local f = faceOf(bw, bd, 0, 0, side)
		local n = math.max(2, math.floor(bw / 2.6))
		for i = 1, n - 1 do
			onFace(f, -bw / 2 + i * bw / n, base, 0.18, bodyH, 0, 0.18, rgb(176, 182, 188))
		end
	end
	local top = base + bodyH
	noCollide(blk(bw + 0.4, 0.6, bd + 0.4, 0, top, 0, rgb(214, 218, 222)))
	blk(bw * 0.55, 3, bd * 0.5, 0, top + 0.6, bd * 0.1, rgb(160, 166, 172)) -- plant room
	for i = -1, 1 do
		noCollide(blk(1.4, 0.8, 1.4, i * bw * 0.18, top + 3.6, bd * 0.1, C.darkMetal))
	end
	local sign = noCollide(blk(bw * 0.5, 1.4, 0.3, 0, top + 1.1, -bd / 2 + 0.6, rgb(255, 180, 54), Enum.Material.Neon))
	sign.Name = "Sign"
	sign:SetAttribute("Window", true)
end

Styles.school = function(w, d, _p)
	blk(w * 0.9, 7, d * 0.35, 0, G, -d * 0.28, C.brick)
	windows(w * 0.9, d * 0.35, 0, -d * 0.28, G + 0.8, 2, 3.2, C.window)
	blk(w * 0.9 + 0.3, 0.5, d * 0.35 + 0.3, 0, G + 7, -d * 0.28, C.roofGrey)
	-- sports field
	noCollide(blk(w * 0.7, 0.08, d * 0.45, 0, G, d * 0.2, C.grass, Enum.Material.Grass))
	noCollide(blk(0.2, 0.1, d * 0.45, 0, G, d * 0.2, C.line))
	noCollide(cyl(9, 0.25, w * 0.42, G, d * 0.42, C.metal))
	noCollide(blk(0.1, 1.4, 2.2, w * 0.42, G + 7.4, d * 0.42 - 1.1, C.blue))
end

Styles.hospital = function(w, d, _p)
	blk(w * 0.8, 10, d * 0.45, 0, G, -d * 0.18, C.white)
	windows(w * 0.8, d * 0.45, 0, -d * 0.18, G + 0.8, 3, 3.1, C.glass)
	blk(w * 0.35, 6, d * 0.35, -w * 0.2, G, d * 0.25, C.white)
	local top = G + 10
	noCollide(blk(5, 0.15, 1.4, 0, top, -d * 0.18, C.red))
	noCollide(blk(1.4, 0.15, 5, 0, top, -d * 0.18, C.red))
	noCollide(cyl(0.1, 6, w * 0.25, G, d * 0.25, C.darkMetal))
	noCollide(blk(2.4, 0.12, 0.4, w * 0.25, G + 0.1, d * 0.25, C.line))
end

Styles.billboard = function(w, _d, _p)
	blk(0.4, 6, 0.4, -w / 3, G, 0, C.darkMetal)
	blk(0.4, 6, 0.4, w / 3, G, 0, C.darkMetal)
	local board = blk(w - 0.2, 4.2, 0.4, 0, G + 5, 0, C.white)
	board.Name = "Board"
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.CanvasSize = Vector2.new(400, 110)
		gui.LightInfluence = 0.2
		gui.Parent = board
		local label = Instance.new("TextLabel")
		label.Name = "Message"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = rgb(250, 248, 240)
		label.TextColor3 = rgb(28, 34, 46)
		label.TextScaled = true
		label.FontFace = Font.new("rbxasset://fonts/families/TitilliumWeb.json", Enum.FontWeight.Bold)
		label.Text = "YOUR AD HERE"
		label.Parent = gui
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 12)
		pad.PaddingRight = UDim.new(0, 12)
		pad.Parent = label
	end
end

Styles.researchLab = function(w, d, _p)
	blk(w * 0.8, 6, d * 0.6, 0, G, -d * 0.1, C.white)
	windows(w * 0.8, d * 0.6, 0, -d * 0.1, G + 0.8, 1, 4, C.glass)
	ball(5.5, w * 0.15, G + 6, -d * 0.1, C.wallCool)
	noCollide(cyl(5, 0.25, -w * 0.25, G + 6, -d * 0.2, C.metal))
	noCollide(blk(w * 0.8, 0.06, d * 0.25, 0, G, d * 0.32, C.grass, Enum.Material.Grass))
end

Styles.university = function(w, d, _p)
	blk(w * 0.85, 9, d * 0.5, 0, G, d * 0.05, C.wallWarm)
	windows(w * 0.85, d * 0.5, 0, d * 0.05, G + 1, 2, 3.6, C.window)
	blk(w * 0.4, 1.2, 3, 0, G, -d * 0.25, C.pad)
	for i = 0, 5 do
		cyl(8, 0.9, -w * 0.17 + i * w * 0.068, G + 1.2, -d * 0.25, C.white)
	end
	blk(w * 0.42, 1.4, 3.4, 0, G + 9, -d * 0.25, C.white)
	ball(7, 0, G + 9, d * 0.05, rgb(120, 160, 150))
end

Styles.milResearch = function(w, d, _p)
	blk(w * 0.75, 5, d * 0.5, -w * 0.05, G, -d * 0.12, rgb(140, 146, 124))
	blk(w * 0.75 + 0.3, 0.5, d * 0.5 + 0.3, -w * 0.05, G + 5, -d * 0.12, C.oliveDark)
	windows(w * 0.75, d * 0.5, -w * 0.05, -d * 0.12, G + 1, 1, 3.4)
	for i, x in { -w * 0.25, w * 0.05 } do
		noCollide(cyl(1.6, 0.8, x, G, d * 0.3, C.metal))
		plank(5 - i, 0.3, 5 - i, CFrame.new(x, G + 3, d * 0.3) * CFrame.Angles(math.rad(-35), 0, 0), C.white)
	end
	noCollide(cyl(16, 0.35, w * 0.35, G, d * 0.3, C.metal))
	noCollide(ball(0.6, w * 0.35, G + 16.2, d * 0.3, C.red, Enum.Material.Neon))
end

Styles.depot = function(w, d, _p)
	blk(w - 1.4, 6, d * 0.55, 0, G, d * 0.15, rgb(150, 154, 132))
	blk(w - 1.2, 0.5, d * 0.55 + 0.2, 0, G + 6, d * 0.15, C.oliveDark)
	local doors = 4
	for i = 1, doors do
		local x = -w / 2 + 0.7 + (i - 0.5) * ((w - 1.4) / doors)
		noCollide(blk(((w - 1.4) / doors) - 1, 4.6, 0.25, x, G, d * 0.15 - d * 0.275 - 0.1, C.darkMetal))
	end
	noCollide(blk(w - 1, 0.06, d * 0.35, 0, G, -d * 0.28, C.asphalt))
end

Styles.radar = function(_w, _d, _p)
	blk(3, 3, 3, 0, G, 0, rgb(150, 154, 132))
	cyl(8, 1.2, 0, G + 3, 0, C.metal)
	local dish = spinGroup("Dish", 1.2, "Y")
	into(dish, function()
		local hub = plank(1, 1, 1, CFrame.new(0, G + 11.5, 0), C.metal)
		hub.Name = "Hub"
		dish.PrimaryPart = hub
		plank(7, 3, 0.3, CFrame.new(0, G + 12.2, 0) * CFrame.Angles(math.rad(-15), 0, 0), C.white)
	end)
end

local function factionColor(p: { [string]: any }): Color3
	if p.eastern then
		return C.eastern
	elseif p.european then
		return C.european
	elseif p.tint == "sand" then
		return C.sand
	elseif p.tint == "dark" then
		return rgb(66, 70, 74)
	elseif p.tint == "eastern" then
		return C.eastern
	elseif p.tint == "european" then
		return C.european
	end
	return C.olive
end

Styles.ciws = function(_w, _d, p)
	local col = factionColor(p)
	cyl(1, 6, 0, G, 0, C.pad)
	cyl(2, 2.6, 0, G + 1, 0, col)
	blk(2.6, 1.8, 2.6, 0, G + 3, 0, col)
	axleCyl(3.4, 0.5, CFrame.new(0, G + 3.9, -2.6) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, math.rad(20)), C.darkMetal)
	ball(2.2, 0, G + 5.4, 0.4, C.white)
end

local function launcherTruck(len: number, col: Color3)
	blk(3.2, 1.2, len, 0, G + 0.9, 0, col)
	blk(3.2, 2.2, 2.6, 0, G + 0.9, -len / 2 + 1.3, col) -- cab
	lit(blk(2.8, 0.8, 0.15, 0, G + 2.2, -len / 2 - 0.02, C.window))
	local axles = math.max(2, math.floor(len / 2.6))
	for i = 0, axles - 1 do
		wheelPair(0, G + 0.75, -len / 2 + 1.2 + i * ((len - 2.4) / (axles - 1)), 3.3, 1.5)
	end
end

Styles.sam = function(w, d, p)
	local col = factionColor(p)
	local count = p.large and 2 or 1
	for i = 1, count do
		local x = count == 1 and -w * 0.12 or (-w * 0.3 + (i - 1) * w * 0.32)
		local len = d * 0.7
		local unit = Instance.new("Model")
		unit.Name = "Launcher" .. i
		unit.Parent = M
		into(unit, function()
			launcherTruck(len, col)
			local tubeCF = CFrame.new(0, G + 4, len * 0.12) * CFrame.Angles(math.rad(50), 0, 0)
			for tx = -1, 1, 2 do
				plank(1.2, 1.2, len * 0.55, tubeCF * CFrame.new(tx * 0.7, 0.6, 0), col)
				plank(1.2, 1.2, len * 0.55, tubeCF * CFrame.new(tx * 0.7, -0.6, 0), col)
			end
		end)
		unit:TranslateBy(Vector3.new(x, 0, 0))
	end
	-- radar truck
	local rx = w * 0.32
	blk(2.6, 1.2, d * 0.45, rx, G + 0.6, d * 0.1, col)
	plank(3.6, 3.2, 0.4, CFrame.new(rx, G + 4, d * 0.1) * CFrame.Angles(math.rad(-20), 0, 0), C.white)
end

Styles.laser = function(_w, _d, _p)
	cyl(1.2, 8, 0, G, 0, C.pad)
	cyl(3, 3.6, 0, G + 1.2, 0, C.metal)
	blk(3.4, 2.8, 3.4, 0, G + 4.2, 0, C.wall)
	local lens = axleCyl(1.6, 2.2, CFrame.new(0, G + 5.6, -2) * CFrame.Angles(0, math.rad(90), 0), rgb(120, 200, 255), Enum.Material.Neon)
	lens.Name = "Lens"
end

Styles.launcher = function(w, d, p)
	local col = factionColor(p)
	local len = d - 1.2
	launcherTruck(len, col)
	if p.kind == "box" then
		local boxCF = CFrame.new(0, G + 3.6, len * 0.12) * CFrame.Angles(math.rad(25), 0, 0)
		plank(3, 2.4, len * 0.62, boxCF, col)
		for ix = -1, 1, 2 do
			for iy = -1, 1, 2 do
				noCollide(plank(0.9, 0.9, 0.2, boxCF * CFrame.new(ix * 0.7, iy * 0.55, -len * 0.31 - 0.05), C.black))
			end
		end
	else
		local h = p.big and 18 or 14
		local z = len * 0.22
		-- erector frame
		blk(0.4, h * 0.85, 0.4, -1.3, G + 2, z + 1.2, C.darkMetal)
		blk(0.4, h * 0.85, 0.4, 1.3, G + 2, z + 1.2, C.darkMetal)
		cyl(h, p.big and 1.9 or 1.5, 0, G + 2, z, rgb(220, 222, 214))
		ball(p.big and 1.9 or 1.5, 0, G + 2 + h, z, C.darkMetal)
		cyl(1.2, (p.big and 1.9 or 1.5) + 0.1, 0, G + 2 + h * 0.55, z, col)
	end
	local _ = w
end

local function deltaDrone(cf: CFrame, s: number, color: Color3)
	plank(0.5 * s, 0.4 * s, 3.2 * s, cf, color)
	plank(4.2 * s, 0.15 * s, 1.2 * s, cf * CFrame.new(0, 0, 0.6 * s) * CFrame.Angles(0, math.rad(25), 0), color)
	plank(4.2 * s, 0.15 * s, 1.2 * s, cf * CFrame.new(0, 0, 0.6 * s) * CFrame.Angles(0, math.rad(-25), 0), color)
end

Styles.droneRack = function(w, d, p)
	local n = p.big and 4 or 2
	blk(w - 1, 1, d - 1, 0, G, 0, C.oliveDark)
	for i = 1, n do
		local x = -w / 2 + 0.5 + (i - 0.5) * ((w - 1) / n)
		local cf = CFrame.new(x, G + 3.2, 0) * CFrame.Angles(math.rad(30), 0, 0)
		plank(0.6, 0.3, d - 2, cf * CFrame.new(0, -0.4, 0), C.darkMetal)
		deltaDrone(cf, 0.8, rgb(170, 172, 164))
		noCollide(blk(0.3, 2.4, 0.3, x, G + 1, d / 2 - 2, C.darkMetal))
	end
end

Styles.droneRamp = function(w, d, p)
	local col = p.tint == "european" and C.european or C.olive
	plank(2.6, 0.5, d - 1.5, CFrame.new(0, G + 2.4, 0) * CFrame.Angles(math.rad(14), 0, 0), C.darkMetal)
	blk(1, 2, 1, 0, G, d / 2 - 1.5, C.darkMetal)
	local cf = CFrame.new(0, G + 3.4, -d * 0.1) * CFrame.Angles(math.rad(14), 0, 0)
	axleCyl(5, 1.1, cf * CFrame.Angles(0, math.rad(90), 0), col)
	plank(6, 0.2, 1.6, cf * CFrame.new(0, 0, 0.4), col)
	plank(2.2, 0.2, 0.8, cf * CFrame.new(0, 0, 2.2), col)
	blk(w * 0.3, 3, 4, w * 0.3, G, d * 0.3, rgb(150, 154, 132))
end

---------------------------------------------------------------------------
-- Public: buildings
---------------------------------------------------------------------------
-- Kit vehicles get an invisible Root (physics / selection) sized to the model.
---------------------------------------------------------------------------
-- Farms
---------------------------------------------------------------------------
local SOIL = rgb(112, 82, 58)
local SOIL_DARK = rgb(86, 62, 44)
local WOOD = rgb(150, 112, 76)

local function postFence(w: number, d: number, gate: number)
	local h = 1.4
	local function rail(x: number, z: number, sx: number, sz: number)
		noCollide(blk(sx, 0.16, sz, x, G + 0.55, z, WOOD))
		noCollide(blk(sx, 0.16, sz, x, G + 1.1, z, WOOD))
	end
	local hw, hd = w / 2 - 0.3, d / 2 - 0.3
	rail(0, hd, w - 0.6, 0.16)
	rail(-hw, 0, 0.16, d - 0.6)
	rail(hw, 0, 0.16, d - 0.6)
	local side = (w - 0.6 - gate) / 2
	rail(-hw + side / 2, -hd, side, 0.16)
	rail(hw - side / 2, -hd, side, 0.16)
	for _, c in { { -hw, -hd }, { hw, -hd }, { -hw, hd }, { hw, hd }, { -gate / 2, -hd }, { gate / 2, -hd }, { 0, hd }, { -hw, 0 }, { hw, 0 } } do
		noCollide(blk(0.3, h, 0.3, c[1], G, c[2], WOOD))
	end
end

-- Ploughed field with ridges and a post-and-rail fence. Crops are added on
-- top by ModelBuilder.crops as the field grows.
Styles.farmField = function(w, d, _p)
	local b = M.PrimaryPart :: BasePart
	b.Color = SOIL
	b.Material = Enum.Material.Ground
	local rows = math.max(3, math.floor((w - 3) / 4))
	local span = d - 4
	for i = 1, rows do
		local x = -w / 2 + 1.5 + (i - 0.5) * ((w - 3) / rows)
		local ridge = noCollide(blk(1.6, 0.35, span, x, G, 0.4, SOIL_DARK, Enum.Material.Ground))
		ridge.Name = "Ridge"
	end
	postFence(w, d, 4)
	-- scarecrow
	noCollide(blk(0.25, 3.4, 0.25, w / 2 - 2.2, G, -d / 2 + 2.2, WOOD))
	noCollide(blk(2.4, 0.22, 0.22, w / 2 - 2.2, G + 2.6, -d / 2 + 2.2, WOOD))
	noCollide(ball(0.8, w / 2 - 2.2, G + 3.6, -d / 2 + 2.2, rgb(214, 178, 120)))
	noCollide(cyl(0.2, 1.4, w / 2 - 2.2, G + 3.95, -d / 2 + 2.2, rgb(176, 140, 70)))
end

-- Crop rows for a field at growth stage 0-3 (rebuilt as the crop grows).
function ModelBuilder.crops(field: Model, crop: any?, stage: number): Model
	local old = field:FindFirstChild("Crops")
	if old then
		old:Destroy()
	end
	local holder = Instance.new("Model")
	holder.Name = "Crops"
	local prev = M
	M = holder
	local base = field.PrimaryPart
	local pivot = field:GetPivot()
	if crop and stage > 0 and base then
		local w, d = base.Size.X + 0.2, base.Size.Z + 0.2
		local rows = math.max(3, math.floor((w - 3) / 4))
		local span = d - 5
		local frac = stage == 1 and 0.2 or (stage == 2 and 0.62 or 1)
		local h = math.max(0.25, crop.height * frac)
		local ripe = stage == 3
		local clumps = 6
		local gap = 0.7
		local clumpLen = span / clumps - gap
		local function noQuery(p: BasePart): BasePart
			p.CanCollide = false
			p.CanQuery = false
			return p
		end
		for i = 1, rows do
			local x = -w / 2 + 1.5 + (i - 0.5) * ((w - 3) / rows)
			for k = 1, clumps do
				local z = 0.4 - span / 2 + (k - 0.5) * (span / clumps)
				local jitter = ((i * 7 + k * 13) % 5) * 0.06 -- slight height variety
				local hh = h * (0.92 + jitter)
				if crop.id == "wheat" then
					-- dense golden carpet with a lighter top
					local col = ripe and crop.ripe or crop.green
					noQuery(blk(stage == 1 and 1 or 2.6, hh, clumpLen + gap * 0.6, x, G + 0.35, z, col, Enum.Material.Grass))
					if ripe then
						noQuery(blk(2.7, 0.25, clumpLen + gap * 0.6, x, G + 0.35 + hh, z, rgb(242, 214, 130), Enum.Material.Fabric))
					end
				elseif crop.id == "potatoes" then
					-- low leafy mounds with pale flowers when ripe
					noQuery(blk(stage == 1 and 0.8 or 1.9, hh, clumpLen, x, G + 0.35, z, ripe and crop.ripe or crop.green, Enum.Material.Grass))
					if ripe then
						noQuery(ball(0.4, x - 0.4, G + 0.45 + hh, z - clumpLen * 0.2, rgb(220, 204, 240)))
						noQuery(ball(0.4, x + 0.4, G + 0.45 + hh, z + clumpLen * 0.2, rgb(220, 204, 240)))
					end
				else
					-- corn / sunflowers: tall stalks, cobs or flower heads on top
					local stalkC = ripe and crop.green:Lerp(crop.ripe, 0.3) or crop.green
					local thick = stage == 1 and 0.5 or 0.9
					noQuery(blk(thick, hh, clumpLen, x, G + 0.35, z, stalkC, Enum.Material.Grass))
					if stage >= 2 then
						noQuery(blk(1.6, hh * 0.35, clumpLen * 0.8, x, G + 0.35 + hh * 0.3, z, stalkC:Lerp(rgb(60, 110, 50), 0.3), Enum.Material.Grass)) -- leaves
					end
					if ripe and crop.id == "corn" then
						noQuery(blk(0.45, 1.1, 0.45, x + 0.6, G + 0.35 + hh * 0.5, z - clumpLen * 0.25, rgb(236, 202, 92)))
						noQuery(blk(0.45, 1.1, 0.45, x - 0.6, G + 0.35 + hh * 0.6, z + clumpLen * 0.25, rgb(236, 202, 92)))
						noQuery(blk(0.3, 0.6, clumpLen * 0.6, x, G + 0.35 + hh, z, rgb(200, 170, 96))) -- tassels
					elseif ripe then
						for _, dz in { -clumpLen * 0.28, clumpLen * 0.28 } do
							local disc = noQuery(plank(1.5, 1.5, 0.3, CFrame.new(x, G + 0.35 + hh + 0.5, z + dz) * CFrame.Angles(math.rad(-20), 0, 0), crop.ripe))
							disc.Shape = Enum.PartType.Cylinder
							disc.Size = Vector3.new(0.3, 1.5, 1.5)
							disc.CFrame = CFrame.new(x, G + 0.35 + hh + 0.5, z + dz - 0.3) * CFrame.Angles(0, math.rad(90), math.rad(20))
							noQuery(ball(0.55, x, G + 0.35 + hh + 0.5, z + dz - 0.55, rgb(96, 62, 30)))
						end
					end
				end
			end
		end
	end
	for _, part in holder:GetDescendants() do
		if part:IsA("BasePart") then
			part.CFrame = pivot * part.CFrame
			part.CastShadow = false
		end
	end
	M = prev
	holder.Parent = field
	return holder
end

-- White farmhouse with a wrap-around porch.
Styles.farmhouse = function(w, d, _p)
	local b = M.PrimaryPart :: BasePart
	b.Color = C.grass
	b.Material = Enum.Material.Grass
	local bw, bd = w - 4, d - 5
	local cz = 1
	local wallC = rgb(240, 236, 224)
	local wallH = 6.4
	blk(bw + 0.4, 0.6, bd + 0.4, 0, G, cz, rgb(150, 140, 130))
	blk(bw, wallH, bd, 0, G + 0.6, cz, wallC)
	local top = G + 0.6 + wallH
	gableRoof(bw + 1.2, bd + 1, 0, top, cz, rgb(150, 54, 48), 38)
	blk(1, 3.6, 1, -bw * 0.25, top, cz + bd * 0.2, C.brick)
	-- porch: deck, posts, roof
	noCollide(blk(bw + 2.6, 0.4, 2.4, 0, G, cz - bd / 2 - 1.2, WOOD))
	for i = 0, 4 do
		noCollide(blk(0.25, 3.2, 0.25, -bw / 2 - 1 + i * (bw + 2) / 4, G + 0.4, cz - bd / 2 - 2.2, C.white))
	end
	noCollide(plank(bw + 2.8, 0.2, 2.8, CFrame.new(0, G + 3.8, cz - bd / 2 - 1.2) * CFrame.Angles(math.rad(-10), 0, 0), rgb(150, 54, 48)))
	local front = faceOf(bw, bd, 0, cz, "front")
	door(front, 0, G + 0.6, 1.3, 2.6, rgb(120, 60, 46), C.white)
	for _, s in { -1, 1 } do
		framedWindow(front, s * bw * 0.3, G + 1.8, 1.2, 1.6, C.white, rgb(64, 92, 72))
		framedWindow(front, s * bw * 0.3, G + 4.6, 1.1, 1.3, C.white, rgb(64, 92, 72))
	end
	for _, side in { "left", "right", "back" } do
		framedWindow(faceOf(bw, bd, 0, cz, side), 0, G + 2, 1.2, 1.5, C.white, nil)
	end
	-- water pump + tree
	noCollide(cyl(1.6, 0.4, w / 2 - 1.2, G, -d / 2 + 1.2, C.darkMetal))
	tree(-w / 2 + 1.4, d / 2 - 1.4, 0.8)
end

-- Classic red barn: gambrel roof, white trim, X-braced doors, hay loft.
Styles.barn = function(w, d, _p)
	local bw, bd = w - 2, d - 2
	local red = rgb(164, 44, 38)
	local trim = rgb(240, 236, 228)
	local wallH = 6
	blk(bw, wallH, bd, 0, G, 0, red, Enum.Material.WoodPlanks)
	local top = G + wallH
	-- gambrel roof: steep lower slopes, shallow upper slopes (ridge along Z)
	local low, lowA = bw * 0.3, math.rad(62)
	local upA = math.rad(24)
	local xIn = bw / 2 - low * math.cos(lowA)
	local up = xIn / math.cos(upA) + 0.2
	local yTop = top + low * math.sin(lowA)
	local roofC = rgb(70, 74, 80)
	for _, s in { -1, 1 } do
		local x1 = s * (bw / 2 - low * math.cos(lowA) / 2)
		plank(low + 0.3, 0.3, bd + 0.8, CFrame.new(x1, top + low * math.sin(lowA) / 2, 0) * CFrame.Angles(0, 0, -s * lowA), roofC)
		plank(up, 0.3, bd + 0.8, CFrame.new(s * (xIn - up * math.cos(upA) / 2), yTop + up * math.sin(upA) / 2, 0) * CFrame.Angles(0, 0, -s * upA), roofC)
	end
	-- gable infill kept inside the roof line
	blk(xIn * 2 - 0.2, yTop - top, bd - 0.2, 0, top, 0, red, Enum.Material.WoodPlanks)
	blk(xIn - 0.2, xIn * math.tan(upA) * 0.5, bd - 0.2, 0, yTop, 0, red, Enum.Material.WoodPlanks)
	local front = faceOf(bw, bd, 0, 0, "front")
	-- big doors with white X bracing
	onFace(front, 0, G, 4.6, 4.6, -0.02, 0.1, trim)
	for _, s in { -1, 1 } do
		onFace(front, s * 1.12, G + 0.1, 2.1, 4.3, 0.06, 0.1, red, Enum.Material.WoodPlanks)
		local x = s * 1.12
		local brace = noCollide(plank(0.22, 4.6, 0.08, CFrame.new(x, G + 2.3, -bd / 2 - 0.2) * CFrame.Angles(0, 0, s * math.rad(26)), trim))
		brace.Name = "Brace"
		noCollide(plank(0.22, 4.6, 0.08, CFrame.new(x, G + 2.3, -bd / 2 - 0.2) * CFrame.Angles(0, 0, -s * math.rad(26)), trim))
	end
	onFace(front, 0, top + 0.4, 1.8, 1.8, 0, 0.1, trim) -- hay loft door
	onFace(front, 0, top + 0.6, 1.4, 1.4, 0.08, 0.06, rgb(120, 34, 30))
	for _, sx in { -1, 1 } do
		noCollide(blk(0.3, wallH, 0.3, sx * bw / 2, G, -bd / 2, trim))
	end
	-- cupola + hay bales
	blk(1.6, 1.4, 1.6, 0, yTop + xIn * math.tan(upA) - 0.3, 0, trim)
	noCollide(cyl(0.8, 1.3, w / 2 - 1, G, -d / 2 + 1, rgb(214, 182, 96)))
	noCollide(cyl(0.8, 1.3, w / 2 - 1, G + 0.8, -d / 2 + 1, rgb(220, 190, 104)))
end

-- Corrugated grain silo with a dome cap and a ladder.
Styles.silo = function(w, _d, _p)
	local dia = w - 2.6
	local h = 18
	cyl(h, dia, 0, G, 0, rgb(196, 200, 204), Enum.Material.Metal)
	for i = 1, 4 do
		noCollide(cyl(0.3, dia + 0.25, 0, G + i * h / 5, 0, rgb(160, 166, 172), Enum.Material.Metal))
	end
	local cap = ball(dia, 0, G + h, 0, rgb(176, 182, 188), Enum.Material.Metal)
	cap.Name = "Dome"
	noCollide(blk(0.6, h, 0.2, 0, G, -dia / 2 - 0.15, C.darkMetal))
	noCollide(cyl(1.2, 1.6, dia / 2 + 0.6, G, 0, C.darkMetal))
end

---------------------------------------------------------------------------
-- Barracks + helipad
---------------------------------------------------------------------------
Styles.barracks = function(w, d, _p)
	local bw, bd = w - 2, d * 0.5
	local cz = d * 0.2
	local wallC = rgb(170, 164, 132)
	local trim = rgb(214, 210, 188)
	local fh = 3.4
	blk(bw, fh * 2, bd, 0, G, cz, wallC)
	noCollide(blk(bw + 0.4, 0.5, bd + 0.4, 0, G + fh * 2, cz, C.oliveDark))
	local front = faceOf(bw, bd, 0, cz, "front")
	for f = 0, 1 do
		ribbon(front, bw - 6, G + f * fh + 1, 1.3, 2.2, trim)
		ribbon(faceOf(bw, bd, 0, cz, "back"), bw - 2, G + f * fh + 1, 1.3, 2.2, trim)
	end
	-- portico entrance + flags
	onFace(front, 0, G, 4.4, fh * 2 - 0.5, 0, 1.6, trim)
	door(front, 0, G, 2.2, 2.8, rgb(70, 76, 60), C.darkMetal)
	for _, s in { -1, 1 } do
		noCollide(cyl(9, 0.22, s * 4.5, G, -d / 2 + 2.5, C.metal))
		noCollide(blk(0.1, 1.4, 2.2, s * 4.5, G + 7.5, -d / 2 + 2.5 + 1.1, s > 0 and C.olive or rgb(200, 60, 50)))
	end
	-- parade ground with painted lines
	noCollide(blk(bw, 0.05, d * 0.42, 0, G, -d * 0.24, C.asphalt))
	for i = -2, 2 do
		noCollide(blk(0.25, 0.06, d * 0.36, i * bw * 0.16, G, -d * 0.24, C.line))
	end
	-- sandbag wall + guard booth
	for i = -2, 2 do
		noCollide(blk(2.2, 0.9, 0.9, -w / 2 + 2 + (i + 2) * 2.3, G, -d / 2 + 0.6, rgb(176, 160, 116)))
	end
	blk(1.8, 2.6, 1.8, w / 2 - 1.6, G, -d / 2 + 1.4, C.oliveDark)
	noCollide(blk(2.2, 0.2, 2.2, w / 2 - 1.6, G + 2.6, -d / 2 + 1.4, C.darkMetal))
end

Styles.helipad = function(w, d, _p)
	local b = M.PrimaryPart :: BasePart
	b.Color = rgb(150, 152, 150)
	b.Material = Enum.Material.Concrete
	local r = math.min(w, d) * 0.36
	local cx, cz = -w * 0.08, 0
	local disc = noCollide(cyl(0.08, r * 2, cx, G, cz, rgb(70, 74, 76)))
	disc.Name = "Pad"
	noCollide(cyl(0.1, r * 2 - 1.2, cx, G, cz, rgb(70, 74, 76)))
	local ring = noCollide(cyl(0.09, r * 2 - 0.4, cx, G, cz, rgb(236, 236, 230)))
	ring.Name = "Ring"
	noCollide(cyl(0.1, r * 2 - 1.4, cx, G + 0.01, cz, rgb(70, 74, 76)))
	-- the H
	noCollide(blk(0.9, 0.06, r * 0.9, cx - r * 0.3, G + 0.1, cz, C.white))
	noCollide(blk(0.9, 0.06, r * 0.9, cx + r * 0.3, G + 0.1, cz, C.white))
	noCollide(blk(r * 0.6, 0.06, 0.9, cx, G + 0.1, cz, C.white))
	-- edge lights glow at night
	for i = 0, 7 do
		local a = i * math.pi / 4
		local light = noCollide(cyl(0.3, 0.5, cx + math.sin(a) * (r + 0.6), G, cz + math.cos(a) * (r + 0.6), rgb(255, 210, 120), Enum.Material.Neon))
		light.Name = "PadLight"
	end
	-- control tower + fuel tank + windsock
	local tx = w / 2 - 3
	blk(3.6, 6, 3.6, tx, G, -d / 2 + 3, rgb(176, 172, 150))
	lit(blk(4, 1.8, 4, tx, G + 6, -d / 2 + 3, C.glass, Enum.Material.Glass))
	noCollide(blk(4.4, 0.4, 4.4, tx, G + 7.8, -d / 2 + 3, C.darkMetal))
	noCollide(cyl(3, 0.2, tx + 1, G + 8.2, -d / 2 + 3, C.metal))
	cyl(3.2, 3.4, tx, G, d / 2 - 3, rgb(226, 228, 220))
	noCollide(cyl(7, 0.2, -w / 2 + 1.2, G, -d / 2 + 1.2, C.metal))
	local sock = noCollide(plank(0.7, 0.7, 2.4, CFrame.new(-w / 2 + 1.2, G + 6.4, -d / 2 + 2.4), rgb(240, 120, 40)))
	sock.Name = "Windsock"
end

local function kitWithRoot(name: string, length: number, centered: boolean): Model?
	local kit = AssetLibrary.instantiate(name, { length = length })
	if not kit then
		return nil
	end
	local oldBase = kit:FindFirstChild("Base")
	if oldBase then
		oldBase:Destroy()
	end
	local _, size = kit:GetBoundingBox()
	if centered then
		for _, part in kit:GetDescendants() do
			if part:IsA("BasePart") then
				part.CFrame -= Vector3.new(0, size.Y / 2, 0)
			end
		end
	end
	local r = Instance.new("Part")
	r.Name = "Root"
	r.Size = size
	r.CFrame = CFrame.new(0, centered and 0 or size.Y / 2, 0)
	r.Transparency = 1
	r.CanCollide = false
	r.CanTouch = false
	r.Anchored = true
	r.Parent = kit
	kit.PrimaryPart = r
	for _, part in kit:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
		end
	end
	return kit
end

local UNIT_LENGTH = { truck = 9.4, ifv = 9, tank = 10, mlrs = 9.6, spaag = 9, humvee = 9.4, squad = 6, blackhawk = 17, chinook = 22 }

-- True when the Blender kit has been imported into ReplicatedStorage.Assets.
function ModelBuilder.usingKit(): boolean
	return AssetLibrary.count() > 0
end

function ModelBuilder.building(def: { id: string, model: string, size: { number }, params: { [string]: any }? }): Model
	local kit = AssetLibrary.instantiate(def.id, { width = def.size[1] * CELL, depth = def.size[2] * CELL, hitbox = true })
	if kit then
		kit.Name = def.id
		return kit
	end
	local model = Instance.new("Model")
	model.Name = def.id
	M = model
	local w, d = def.size[1] * CELL, def.size[2] * CELL
	if def.model ~= "road" then
		base(w - 0.2, d - 0.2, (def.model == "park") and C.grass or C.concrete)
	end
	local style = Styles[def.model]
	if style then
		style(w, d, def.params or {})
	else
		blk(w - 2, 4, d - 2, 0, G, 0, C.wall)
	end
	return model
end

---------------------------------------------------------------------------
-- Units (vehicles), front = -Z
---------------------------------------------------------------------------
local function root(sx: number, sy: number, sz: number): Part
	local r = Instance.new("Part")
	r.Name = "Root"
	r.Size = Vector3.new(sx, sy, sz)
	r.CFrame = CFrame.new(0, sy / 2, 0)
	r.Transparency = 1
	r.CanCollide = false
	r.CanTouch = false
	r.Anchored = true
	r.Parent = M
	M.PrimaryPart = r
	return r
end

local function tracks(len: number, width: number)
	blk(1, 1.4, len, -width / 2 + 0.5, 0, 0, C.black)
	blk(1, 1.4, len, width / 2 - 0.5, 0, 0, C.black)
end

local UnitStyles: { [string]: (p: { [string]: any }, col: Color3) -> () } = {}

UnitStyles.ifv = function(p, col)
	root(4.4, 3.6, 9)
	if p.wheeled then
		for _, z in { -3, -1, 1, 3 } do
			wheelPair(0, 0.8, z, 4.1, 1.6)
		end
		blk(3.8, 1.8, 8.6, 0, 0.9, 0, col)
	else
		tracks(8.6, 4.4)
		blk(3.6, 1.8, 8.6, 0, 0.6, 0, col)
	end
	plank(3.6, 0.3, 2.2, CFrame.new(0, 2.2, -4.2) * CFrame.Angles(math.rad(-30), 0, 0), col)
	blk(2.2, 1, 2.6, 0, 2.6, -0.5, col)
	axleCyl(3.2, 0.3, CFrame.new(0, 3.1, -3.2) * CFrame.Angles(0, math.rad(90), 0), C.darkMetal)
end

UnitStyles.tank = function(_p, col)
	root(5, 3.8, 10)
	tracks(9.6, 5)
	blk(4, 1.6, 9.6, 0, 0.7, 0, col)
	blk(3.4, 1.3, 4, 0, 2.3, 0.6, col)
	axleCyl(6, 0.45, CFrame.new(0, 2.9, -4.2) * CFrame.Angles(0, math.rad(90), 0), col)
end

UnitStyles.mlrs = function(p, col)
	root(3.8, 4, 9.6)
	blk(3.2, 1, 9, 0, 0.8, 0, col)
	blk(3.2, 2.2, 2.4, 0, 1.8, -3.3, col)
	lit(blk(2.8, 0.8, 0.15, 0, 3, -4.52, C.window))
	for _, z in { -3.3, 1.2, 3.4 } do
		wheelPair(0, 0.75, z, 3.3, 1.5)
	end
	if p.gun then
		axleCyl(7, 0.5, CFrame.new(0, 2.8, 0.4) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, math.rad(-12)), C.darkMetal)
	else
		local pod = plank(3, 2, 4.4, CFrame.new(0, 3, 1.8) * CFrame.Angles(math.rad(12), 0, 0), col)
		pod.Name = "Pod"
		noCollide(plank(2.4, 1.4, 0.2, CFrame.new(0, 3.5, -0.42) * CFrame.Angles(math.rad(12), 0, 0), C.black))
	end
end

UnitStyles.spaag = function(_p, col)
	root(4.6, 4.4, 9)
	tracks(8.6, 4.6)
	blk(3.8, 1.6, 8.6, 0, 0.7, 0, col)
	blk(3, 1.6, 3.2, 0, 2.3, 0.4, col)
	axleCyl(3.6, 0.3, CFrame.new(-1.7, 3, -1.6) * CFrame.Angles(0, math.rad(90), 0), C.darkMetal)
	axleCyl(3.6, 0.3, CFrame.new(1.7, 3, -1.6) * CFrame.Angles(0, math.rad(90), 0), C.darkMetal)
	plank(2, 1.4, 0.2, CFrame.new(0, 4.4, 1.6), C.white)
end

---------------------------------------------------------------------------
-- Infantry: classic Roblox (R6) soldiers with distinct kit
---------------------------------------------------------------------------
local SKIN = { rgb(234, 184, 146), rgb(204, 142, 105), rgb(160, 106, 74), rgb(114, 74, 52), rgb(242, 204, 170) }

type Kit = { shirt: Color3, pants: Color3, vest: Color3, helmet: Color3, gear: Color3, style: string }

local function kitFor(p: { [string]: any }): Kit
	if p.eastern then
		return { shirt = rgb(92, 104, 70), pants = rgb(84, 96, 64), vest = rgb(70, 82, 56), helmet = rgb(78, 92, 60), gear = rgb(52, 60, 42), style = "eastern" }
	elseif p.european then
		return { shirt = rgb(196, 178, 136), pants = rgb(176, 160, 120), vest = rgb(150, 132, 96), helmet = rgb(184, 166, 124), gear = rgb(110, 96, 70), style = "european" }
	elseif p.kit == "recon" then
		return { shirt = rgb(84, 96, 66), pants = rgb(70, 80, 56), vest = rgb(96, 110, 70), helmet = rgb(96, 104, 72), gear = rgb(58, 64, 46), style = "recon" }
	end
	return { shirt = rgb(112, 118, 86), pants = rgb(98, 104, 76), vest = rgb(150, 138, 102), helmet = rgb(104, 112, 82), gear = rgb(60, 64, 52), style = "standard" }
end

-- Motor6D from part0 to part1 at a world joint position (for animated limbs / rotors).
local function joint(name: string, part0: BasePart, part1: BasePart, at: CFrame): Motor6D
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = part0.CFrame:Inverse() * at
	m.C1 = part1.CFrame:Inverse() * at
	m.Parent = part0
	part1:SetAttribute("Jointed", true)
	return m
end

-- One soldier standing at (x, z), facing -Z. s = scale (1 = a normal R6 character).
local function soldier(x: number, z: number, s: number, kit: Kit, weapon: string, skin: Color3)
	local sub = Instance.new("Model")
	sub.Name = "Soldier"
	sub:SetAttribute("Soldier", true)
	sub.Parent = M
	local prev = M
	M = sub
	local function part(name: string, sx: number, sy: number, sz: number, cf: CFrame, color: Color3, material: Enum.Material?): Part
		local p = plank(sx * s, sy * s, sz * s, cf, color, material)
		p.Name = name
		return p
	end
	local function at(lx: number, ly: number, lz: number): CFrame
		return CFrame.new(x + lx * s, ly * s, z + lz * s)
	end
	local torso = part("Torso", 2, 2, 1, at(0, 3, 0), kit.shirt)
	local legL = part("Left Leg", 1, 2, 1, at(-0.5, 1, 0), kit.pants)
	local legR = part("Right Leg", 1, 2, 1, at(0.5, 1, 0), kit.pants)
	joint("LeftHip", torso, legL, at(-0.5, 2, 0)):SetAttribute("Swing", 1)
	joint("RightHip", torso, legR, at(0.5, 2, 0)):SetAttribute("Swing", -1)
	-- boots
	part("Boot", 1.02, 0.45, 1.05, at(-0.5, 0.22, -0.02), rgb(40, 36, 30)):SetAttribute("WeldTo", "Left Leg")
	part("Boot", 1.02, 0.45, 1.05, at(0.5, 0.22, -0.02), rgb(40, 36, 30)):SetAttribute("WeldTo", "Right Leg")
	-- head: the classic Roblox head mesh + face
	local head = part("Head", 2, 1, 1, at(0, 4.5, 0), skin)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Head
	mesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	mesh.Parent = head
	local face = Instance.new("Decal")
	face.Name = "face"
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = head
	-- arms raised to hold the weapon (posed, welded)
	local aim = weapon == "at" and 0.35 or 0.9
	part("Right Arm", 1, 2, 1, at(1.5, 3.25, -0.5) * CFrame.Angles(math.rad(70), 0, math.rad(-8)), kit.shirt)
	part("Left Arm", 1, 2, 1, at(-1.25, 3.25, -0.65) * CFrame.Angles(math.rad(80), math.rad(-25), math.rad(10)), kit.shirt)
	-- plate carrier with pouches + radio
	part("Vest", 2.15, 1.5, 1.25, at(0, 3.25, 0), kit.vest, Enum.Material.Fabric)
	for i = -1, 1 do
		part("Pouch", 0.5, 0.55, 0.3, at(i * 0.62, 2.85, -0.75), kit.gear, Enum.Material.Fabric)
	end
	part("Radio", 0.6, 0.9, 0.4, at(0.45, 3.2, 0.82), kit.gear)
	part("Antenna", 0.08, 1.6, 0.08, at(0.62, 4.2, 0.9), C.black)
	-- headgear
	if kit.style == "recon" then
		part("Brim", 2, 0.12, 2, at(0, 5.1, 0), kit.helmet, Enum.Material.Fabric)
		part("Hat", 1.45, 0.5, 1.45, at(0, 5.35, 0), kit.helmet, Enum.Material.Fabric)
		part("Ghillie", 2.4, 0.6, 1.5, at(0, 4, 0.1), rgb(86, 104, 58), Enum.Material.Grass)
	else
		local helmet = part("Helmet", 1.55, 1.05, 1.6, at(0, 5.05, 0.02), kit.helmet)
		local dome = Instance.new("SpecialMesh")
		dome.MeshType = Enum.MeshType.Sphere
		dome.Parent = helmet
		if kit.style == "standard" then
			part("NVGMount", 0.45, 0.35, 0.2, at(0, 5.25, -0.82), C.black)
			part("Goggles", 1.4, 0.25, 0.2, at(0, 5.4, -0.55), rgb(30, 30, 34))
		elseif kit.style == "eastern" then
			part("EarPro", 1.75, 0.55, 0.6, at(0, 4.55, 0), kit.gear)
			part("Visor", 1.3, 0.3, 0.15, at(0, 5.1, -0.82), rgb(40, 44, 38))
		else
			part("Band", 1.6, 0.18, 1.62, at(0, 4.9, 0.02), rgb(70, 60, 44))
			part("Glasses", 1.1, 0.22, 0.12, at(0, 4.7, -0.62), rgb(30, 30, 34))
		end
	end
	-- weapon
	if weapon == "at" then
		local tube = axleCyl(4.6 * s, 0.6 * s, at(0.9, 4.6, 0.2) * CFrame.Angles(0, math.rad(90), 0), rgb(76, 90, 60))
		tube.Name = "Launcher"
		axleCyl(0.9 * s, 0.8 * s, at(0.9, 4.6, -2) * CFrame.Angles(0, math.rad(90), 0), rgb(60, 70, 48)).Name = "Warhead"
	else
		local len = weapon == "recon" and 3.4 or 2.6
		part("Rifle", 0.28, 0.42, len, at(0.3, 3.55, -1.3) * CFrame.Angles(math.rad(-aim * 10), 0, 0), rgb(38, 40, 40))
		part("Magazine", 0.22, 0.6, 0.35, at(0.3, 3.15, -1.15), rgb(38, 40, 40))
		part("Optic", 0.22, 0.25, 0.6, at(0.3, 3.88, -1.15), rgb(24, 24, 26))
	end
	part("Pack", 1.6, 1.6, 0.7, at(0, 3.05, 0.95), kit.gear, Enum.Material.Fabric)
	M = prev
end

-- A squad unit: invisible root plus 2-4 soldiers in a loose wedge.
UnitStyles.squad = function(p, _col)
	local s = 0.72
	root(6, 5.2 * s, 6)
	local kit = kitFor(p)
	local count = p.count or 4
	local spots = { { 0, -1.8 }, { -1.9, 0.4 }, { 1.9, 0.6 }, { 0, 2.4 } }
	for i = 1, count do
		local spot = spots[i]
		soldier(spot[1], spot[2], s, kit, p.kit or "rifle", SKIN[(i + (p.eastern and 1 or 0)) % #SKIN + 1])
	end
end

---------------------------------------------------------------------------
-- Transports
---------------------------------------------------------------------------
UnitStyles.humvee = function(p, col)
	local body = p.eastern and C.eastern or (p.european and C.european or rgb(176, 160, 120))
	root(4.8, 4.6, 9.4)
	blk(4.5, 1.3, 9, 0, 0.9, 0, body) -- hull
	plank(4.3, 0.5, 3.2, CFrame.new(0, 2.45, -2.9) * CFrame.Angles(math.rad(-6), 0, 0), body) -- hood
	noCollide(blk(3.4, 0.3, 0.2, 0, 1.4, -4.55, C.darkMetal)) -- grille
	for _, sx in { -1, 1 } do
		lit(blk(0.5, 0.35, 0.12, sx * 1.6, 1.85, -4.56, rgb(255, 236, 190)))
	end
	blk(4.3, 1.5, 3.8, 0, 2.2, 0.4, body) -- cabin
	lit(blk(3.9, 0.8, 0.12, 0, 2.75, -1.52, C.window)) -- windscreen
	for _, sx in { -1, 1 } do
		lit(blk(0.12, 0.7, 2.8, sx * 2.16, 2.75, 0.4, C.window))
	end
	blk(4.3, 0.9, 2.4, 0, 2.2, 3.4, body) -- rear bed
	-- roof turret: ring, gun shield, machine gun
	noCollide(cyl(0.35, 2.2, 0, 3.7, 0.6, C.darkMetal))
	noCollide(blk(1.8, 1, 0.15, 0, 4.05, -0.3, body))
	axleCyl(2.4, 0.2, CFrame.new(0, 4.4, -1.2) * CFrame.Angles(0, math.rad(90), 0), C.black)
	for _, z in { -2.9, 2.9 } do
		wheelPair(0, 0.95, z, 4.6, 1.9)
	end
	noCollide(blk(0.12, 2, 0.12, -1.9, 3.7, 2.8, C.black)) -- whip antenna
	local _ = col
end

UnitStyles.truck = function(_p, col)
	root(3.8, 4.4, 9.4)
	blk(3.4, 0.6, 9, 0, 0.6, 0.2, C.darkMetal) -- chassis
	blk(3.4, 2.4, 2.6, 0, 1.2, -3.1, col) -- cab
	lit(blk(3.0, 0.9, 0.15, 0, 2.5, -4.42, C.window))
	for _, sx in { -1, 1 } do
		lit(blk(0.15, 0.8, 1.4, sx * 1.72, 2.5, -3.4, C.window))
	end
	noCollide(blk(2.8, 0.4, 0.2, 0, 1.4, -4.42, C.darkMetal))
	-- canvas-covered cargo bed with hoops
	blk(3.6, 0.8, 5.6, 0, 1.2, 1.5, rgb(110, 116, 90))
	blk(3.6, 2, 5.6, 0, 2, 1.5, rgb(122, 128, 96), Enum.Material.Fabric)
	for i = 0, 3 do
		noCollide(blk(3.7, 0.15, 0.2, 0, 4, -1.1 + i * 1.73, rgb(98, 104, 78)))
	end
	noCollide(cyl(0.5, 1.5, 0, 0.5, 4.45, C.black)).CFrame = CFrame.new(0, 1.3, 4.45) * CFrame.Angles(math.rad(90), 0, 0) -- spare tyre
	wheelPair(0, 0.8, -3.1, 3.5, 1.6)
	wheelPair(0, 0.8, 0.9, 3.5, 1.6)
	wheelPair(0, 0.8, 2.7, 3.5, 1.6)
end

---------------------------------------------------------------------------
-- Helicopters (rotors are jointed so the client can spin them)
---------------------------------------------------------------------------
-- Hub + blades; the hub is jointed to the root and spins around its local Y
-- (turn hubAt to spin around another axis, e.g. a tail rotor).
local function rotor(name: string, hubAt: CFrame, blades: number, len: number, color: Color3, spin: number, r: BasePart): BasePart
	local hub = plank(0.9, 0.5, 0.9, hubAt, C.darkMetal)
	hub.Name = name
	for i = 1, blades do
		local a = (i - 1) * (math.pi * 2 / blades)
		local blade = plank(0.7, 0.12, len, hubAt * CFrame.Angles(0, a, 0) * CFrame.new(0, 0.1, -len / 2), color)
		blade.Name = "Blade"
		blade:SetAttribute("WeldTo", name)
		blade.CastShadow = false
	end
	joint(name .. "Joint", r, hub, hubAt):SetAttribute("Spin", spin)
	return hub
end

UnitStyles.blackhawk = function(p, _col)
	local body = p.eastern and rgb(86, 98, 72) or rgb(56, 62, 52)
	local r = root(5, 5, 17)
	blk(3.8, 3, 7.6, 0, 1, -0.6, body) -- cabin
	plank(3.6, 2.4, 2.8, CFrame.new(0, 2.1, -5.4) * CFrame.Angles(math.rad(-18), 0, 0), body) -- nose
	lit(plank(3.4, 1.4, 1.8, CFrame.new(0, 3.05, -5.25) * CFrame.Angles(math.rad(-38), 0, 0), C.glass))
	for _, sx in { -1, 1 } do
		lit(blk(0.12, 1.2, 1.8, sx * 1.92, 2.6, -3.3, C.glass)) -- cockpit side
		blk(0.12, 1.6, 2, sx * 1.92, 1.6, 0.2, rgb(40, 44, 38)) -- open door
		noCollide(axleCyl(1.6, 0.18, CFrame.new(sx * 2.2, 2.2, 0.2) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, 0), C.black)) -- door gun
	end
	blk(2.6, 1, 4.2, 0, 4, -0.8, body) -- engine deck
	noCollide(cyl(0.9, 0.5, 0, 5, -0.8, C.darkMetal)) -- mast
	blk(1.2, 1.2, 8.6, 0, 2.6, 7.2, body) -- tail boom
	plank(0.3, 3, 1.8, CFrame.new(0, 4.4, 11.2) * CFrame.Angles(math.rad(-20), 0, 0), body) -- fin
	blk(3.8, 0.18, 1.1, 0, 2.9, 10.4, body) -- stabiliser
	for _, sx in { -1, 1 } do
		noCollide(axleCyl(0.45, 0.8, CFrame.new(sx * 1.4, 0.4, -3.6), C.black)) -- wheels
	end
	noCollide(axleCyl(0.3, 0.5, CFrame.new(0, 1.5, 11.1), C.black))
	rotor("MainRotor", CFrame.new(0, 5.5, -0.8), 4, 8.6, rgb(40, 42, 40), 18, r)
	rotor("TailRotor", CFrame.new(0.4, 5.2, 11.8) * CFrame.Angles(0, 0, math.rad(90)), 2, 1.6, rgb(40, 42, 40), 40, r)
end

UnitStyles.chinook = function(p, _col)
	local body = p.eastern and rgb(86, 98, 72) or rgb(92, 98, 76)
	local r = root(5.6, 7, 22)
	blk(4.6, 4.2, 15.6, 0, 0.7, 0.4, body) -- fuselage
	plank(4.4, 3.4, 2.6, CFrame.new(0, 2.4, -8.3) * CFrame.Angles(math.rad(-14), 0, 0), body) -- nose
	lit(plank(4.2, 1.2, 1.6, CFrame.new(0, 3.95, -8.4) * CFrame.Angles(math.rad(-40), 0, 0), C.glass))
	plank(4.4, 0.3, 3.2, CFrame.new(0, 1.3, 9.4) * CFrame.Angles(math.rad(28), 0, 0), body) -- rear ramp
	for _, sx in { -1, 1 } do
		blk(1, 1.5, 9.5, sx * 2.75, 0.9, 0.6, body) -- sponsons
		for i = 0, 4 do
			lit(blk(0.12, 0.7, 0.7, sx * 2.32, 3.2, -5 + i * 2.2, C.window))
		end
		noCollide(axleCyl(0.5, 1, CFrame.new(sx * 2.4, 0.5, -5.4), C.black))
		noCollide(axleCyl(0.5, 1, CFrame.new(sx * 2.9, 0.5, 4.2), C.black))
	end
	blk(1.8, 1.4, 2.4, 0, 4.9, -6.8, body) -- front pylon
	blk(2.4, 3.2, 3.6, 0, 4.9, 7.4, body) -- rear pylon
	blk(1.6, 0.9, 6, 0, 4.9, 1, rgb(80, 86, 66)) -- spine
	rotor("FrontRotor", CFrame.new(0, 6.7, -7), 3, 9.6, rgb(40, 42, 40), 15, r)
	rotor("RearRotor", CFrame.new(0, 8.5, 7.6), 3, 9.6, rgb(40, 42, 40), -15, r)
end

---------------------------------------------------------------------------
-- Forward Operating Base (built on the battlefield)
---------------------------------------------------------------------------
function ModelBuilder.fob(color: Color3?): Model
	local model = Instance.new("Model")
	model.Name = "FOB"
	M = model
	local size = 64
	local half = size / 2
	local gravel = blk(size, 0.4, size, 0, 0, 0, rgb(168, 156, 130), Enum.Material.Slate)
	gravel.Name = "Base"
	model.PrimaryPart = gravel
	local hesco = rgb(196, 176, 130)
	local seg = 9.6
	for _, side in { "front", "back", "left", "right" } do
		local n = math.floor(size / seg)
		for i = 0, n - 1 do
			local along = -half + seg / 2 + i * seg
			if not (side == "front" and math.abs(along) < seg) then
				local x, z, sx, sz
				if side == "front" or side == "back" then
					x, z, sx, sz = along, (side == "front" and -half or half), seg - 0.2, 3.2
				else
					x, z, sx, sz = (side == "left" and -half or half), along, 3.2, seg - 0.2
				end
				local wall = blk(sx, 3.4, sz, x, G, z, hesco, Enum.Material.Fabric)
				wall.Name = "Hesco"
			end
		end
	end
	-- watchtower at the back-left corner
	local tx, tz = -half + 5, half - 5
	for _, c in { { -1.5, -1.5 }, { 1.5, -1.5 }, { -1.5, 1.5 }, { 1.5, 1.5 } } do
		blk(0.4, 8, 0.4, tx + c[1], G, tz + c[2], WOOD)
	end
	blk(4.4, 0.4, 4.4, tx, G + 8, tz, WOOD)
	blk(4.4, 1.2, 4.4, tx, G + 8.4, tz, rgb(176, 160, 116), Enum.Material.Fabric)
	noCollide(blk(5, 0.3, 5, tx, G + 11, tz, C.oliveDark))
	for _, c in { { -2, -2 }, { 2, -2 } } do
		noCollide(blk(0.2, 2.6, 0.2, tx + c[1], G + 8.4, tz + c[2], WOOD))
	end
	-- tents
	for i, x in { -12, 2 } do
		local z = 6 + (i - 1) * 2
		blk(10, 2.6, 6, x, G, z, rgb(96, 108, 76), Enum.Material.Fabric)
		gableRoof(10.6, 6.4, x, G + 2.6, z, rgb(86, 98, 68), 30)
	end
	-- command container + mast
	blk(7, 3, 3, 14, G, 14, rgb(110, 118, 92))
	noCollide(cyl(12, 0.3, 17, G + 3, 15, C.metal))
	noCollide(plank(2, 0.2, 2, CFrame.new(17, G + 15, 15) * CFrame.Angles(math.rad(-30), 0, 0), C.white))
	-- helipad
	local hx, hz = 10, -12
	noCollide(cyl(0.1, 18, hx, G, hz, rgb(86, 88, 86)))
	noCollide(cyl(0.12, 16.6, hx, G, hz, rgb(236, 236, 230)))
	noCollide(cyl(0.14, 15.4, hx, G, hz, rgb(86, 88, 86)))
	noCollide(blk(0.8, 0.06, 7, hx - 2.2, G + 0.14, hz, C.white))
	noCollide(blk(0.8, 0.06, 7, hx + 2.2, G + 0.14, hz, C.white))
	noCollide(blk(4.4, 0.06, 0.8, hx, G + 0.14, hz, C.white))
	-- supply crates
	for i = 0, 5 do
		local cx, cz = -18 + (i % 3) * 2.6, -14 + math.floor(i / 3) * 2.6
		blk(2.3, 2, 2.3, cx, G, cz, i % 2 == 0 and rgb(112, 120, 82) or rgb(150, 116, 74))
	end
	blk(2.3, 2, 2.3, -15.4, G + 2, -14, rgb(112, 120, 82))
	-- sandbag nests at the gate
	for _, s in { -1, 1 } do
		noCollide(blk(4, 1.4, 1.4, s * 7, G, -half - 2.6, rgb(176, 160, 116), Enum.Material.Fabric))
	end
	-- floodlights (glow at night) + flag in the owner's colour
	for _, c in { { -half + 2, -half + 2 }, { half - 2, -half + 2 }, { half - 2, half - 2 } } do
		noCollide(cyl(7, 0.3, c[1], G, c[2], C.metal))
		local lamp = noCollide(blk(1, 0.6, 1, c[1], G + 7, c[2], rgb(255, 230, 180), Enum.Material.Neon))
		lamp.Transparency = 1
		lamp:SetAttribute("NightGlow", true)
	end
	noCollide(cyl(12, 0.3, -4, G, -half + 6, C.metal))
	local flag = noCollide(blk(0.12, 2.4, 4, -4, G + 9.4, -half + 8, color or C.olive))
	flag.Name = "Flag"
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end
	return model
end

-- Extra preview models for tools/export_parts.luau (FOB, crops at each stage).
function ModelBuilder.extras(): { [string]: () -> Model }
	local Crops = require(script.Parent.Catalog.Crops)
	local Buildings = require(script.Parent.Catalog.Buildings)
	local out: { [string]: () -> Model } = {
		fob = function()
			return ModelBuilder.fob(Color3.fromRGB(64, 140, 230))
		end,
	}
	local fieldDef = Buildings.get("farm_field")
	for _, crop in Crops.all() do
		for _, stage in { 1, 2, 3 } do
			out[("field_%s_%d"):format(crop.id, stage)] = function()
				local m = ModelBuilder.building(fieldDef :: any)
				ModelBuilder.crops(m, crop, stage)
				return m
			end
		end
	end
	return out
end

function ModelBuilder.unit(def: { id: string, model: string, params: { [string]: any }? }): Model
	local kit = kitWithRoot("unit_" .. def.id, UNIT_LENGTH[def.model] or 9, false)
	if kit then
		kit.Name = def.id
		return kit
	end
	local model = Instance.new("Model")
	model.Name = def.id
	M = model
	local p = def.params or {}
	local col = p.eastern and C.eastern or (p.european and C.european or C.olive)
	local style = UnitStyles[def.model] or UnitStyles.truck
	style(p, col)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.Anchored = true
		end
	end
	return model
end

---------------------------------------------------------------------------
-- Projectiles (client visuals), forward = -Z
---------------------------------------------------------------------------
function ModelBuilder.projectile(def: { kind: string, color: Color3, id: string }): Model
	local kit = kitWithRoot("proj_" .. def.id, def.kind == "drone" and 4.6 or (def.id == "MRBM" and 7.4 or 6), true)
	if kit then
		kit.Name = def.id
		local tail = Instance.new("Attachment")
		tail.Name = "Tail"
		tail.Position = Vector3.new(0, 0, (kit.PrimaryPart :: BasePart).Size.Z / 2)
		tail.Parent = kit.PrimaryPart
		for _, part in kit:GetDescendants() do
			if part:IsA("BasePart") then
				part.CanQuery = false
				part.CastShadow = false
			end
		end
		return kit
	end
	local model = Instance.new("Model")
	model.Name = def.id
	M = model
	local r = root(1, 1, 1)
	r.CFrame = CFrame.new()
	if def.kind == "drone" then
		if def.id == "RAPTOR" then
			axleCyl(4.4, 0.9, CFrame.Angles(0, math.rad(90), 0), def.color)
			plank(5, 0.15, 1.4, CFrame.new(0, 0, 0.6), def.color)
			plank(2, 0.15, 0.7, CFrame.new(0, 0, 2), def.color)
		else
			deltaDrone(CFrame.new(), 1, def.color)
		end
	else
		local len = def.id == "MRBM" and 7 or (def.id == "GLCM" and 4.5 or 6)
		axleCyl(len, 0.9, CFrame.Angles(0, math.rad(90), 0), def.color)
		ball(0.9, 0, 0, -len / 2, def.color)
		for k = 0, 3 do
			plank(0.12, 1.2, 1, CFrame.new(0, 0, len / 2 - 0.5) * CFrame.Angles(0, 0, math.rad(45 + k * 90)) * CFrame.new(0, 0.6, 0), C.darkMetal)
		end
		if def.id == "GLCM" then
			plank(3, 0.1, 0.6, CFrame.new(0, 0, 0.2), def.color)
		end
	end
	local tail = Instance.new("Attachment")
	tail.Name = "Tail"
	tail.Position = Vector3.new(0, 0, 2.6)
	tail.Parent = r
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanQuery = false
			part.CastShadow = false
		end
	end
	return model
end

function ModelBuilder.fuelTruck(): Model
	local kit = kitWithRoot("fuel_truck", 8, false)
	if kit then
		kit.Name = "FuelTruck"
		for _, part in kit:GetDescendants() do
			if part:IsA("BasePart") then
				part.CanQuery = false
			end
		end
		return kit
	end
	local model = Instance.new("Model")
	model.Name = "FuelTruck"
	M = model
	root(3.4, 3.6, 8)
	blk(3, 2.2, 2.2, 0, 0.8, -2.8, C.white)
	lit(blk(2.6, 0.8, 0.15, 0, 2, -3.92, C.window))
	blk(3, 0.6, 5.6, 0, 0.7, 0.9, C.darkMetal)
	axleCyl(5, 2.6, CFrame.new(0, 2.6, 0.9) * CFrame.Angles(0, math.rad(90), 0), C.white)
	noCollide(blk(3.1, 0.4, 2, 0, 2.4, 0.9, C.orange))
	wheelPair(0, 0.7, -2.8, 3.1, 1.4)
	wheelPair(0, 0.7, 1.4, 3.1, 1.4)
	wheelPair(0, 0.7, 3, 3.1, 1.4)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanQuery = false
		end
	end
	return model
end

---------------------------------------------------------------------------
-- Mainland strategic point structures (size in studs)
---------------------------------------------------------------------------
local PointStyles: { [string]: (s: number) -> () } = {}

PointStyles.city = function(s)
	local rng = Random.new(7)
	for i = 1, 22 do
		local x = rng:NextNumber(-s / 2.4, s / 2.4)
		local z = rng:NextNumber(-s / 2.4, s / 2.4)
		local h = rng:NextNumber(5, 22)
		local w = rng:NextNumber(6, 12)
		blk(w, h, w * rng:NextNumber(0.8, 1.4), x, 0, z, i % 3 == 0 and C.wallWarm or C.wallCool)
		blk(w * 0.9, 0.4, w * 0.9, x, h, z, C.roofGrey)
	end
	blk(s * 0.9, 0.2, 5, 0, 0, 0, C.asphalt)
	blk(5, 0.2, s * 0.9, 0, 0, 0, C.asphalt)
end

PointStyles.airport = function(s)
	blk(14, 0.3, s * 1.4, 0, 0, 0, C.asphalt)
	blk(6, 0.3, s * 1.2, 22, 0, 0, C.asphalt)
	for i = -6, 6 do
		noCollide(blk(0.8, 0.1, 6, 0, 0.3, i * s / 10, C.line))
	end
	for i = 0, 4 do
		local z = -s * 0.5 + i * s * 0.25
		blk(14, 7, 12, -26, 0, z, C.wallCool)
		gableRoof(14, 12, -26, 7, z, C.roofGrey, 14)
	end
	cyl(18, 3, -18, 0, s * 0.62, C.white)
	blk(6, 3, 6, -18, 18, s * 0.62, C.glass)
end

PointStyles.oilField = function(s)
	local rng = Random.new(3)
	for _ = 1, 9 do
		local x, z = rng:NextNumber(-s / 2.4, s / 2.4), rng:NextNumber(-s / 2.4, s / 2.4)
		blk(2.4, 0.6, 9, x, 0, z, C.darkMetal)
		blk(0.6, 0.7, 9, x, 5, z, C.orange)
		blk(0.6, 5, 0.6, x, 0, z, C.darkMetal)
	end
	for i = 0, 2 do
		cyl(6, 10, s * 0.35, 0, -s * 0.3 + i * 13, C.white)
	end
end

PointStyles.nuclear = function(s)
	local prev = G
	coolingTower(-s * 0.2, 0, 1.6)
	coolingTower(s * 0.12, -s * 0.1, 1.6)
	cyl(12, 16, s * 0.3, 0, s * 0.25, C.wall)
	ball(16, s * 0.3, 12, s * 0.25, C.wall)
	blk(s * 0.5, 9, 14, -s * 0.05, 0, s * 0.3, C.wallCool)
	local _ = prev
end

PointStyles.port = function(s)
	blk(s, 2, s * 0.35, 0, -1.6, -s * 0.2, C.concrete)
	local rng = Random.new(5)
	local colors = { C.red, C.blue, C.orange, C.olive, C.white }
	for i = 1, 26 do
		local x = rng:NextNumber(-s / 2.3, s / 2.3)
		local z = rng:NextNumber(-s * 0.3, -s * 0.08)
		blk(3, 3, 7, x, 0.4, z, colors[(i % #colors) + 1])
	end
	for i = 0, 2 do
		local x = -s * 0.3 + i * s * 0.3
		blk(1.2, 22, 1.2, x - 3, 0, -s * 0.34, C.orange)
		blk(1.2, 22, 1.2, x + 3, 0, -s * 0.34, C.orange)
		blk(1.2, 1.2, 24, x, 22, -s * 0.34 + 6, C.orange)
	end
end

PointStyles.base = function(s)
	for i = 0, 2 do
		local x = -s * 0.3 + i * s * 0.3
		blk(16, 8, 14, x, 0, -s * 0.15, rgb(150, 154, 132))
		gableRoof(16, 14, x, 8, -s * 0.15, C.oliveDark, 16)
	end
	cyl(0.3, 18, s * 0.25, 0, s * 0.25, C.asphalt)
	cyl(18, 0.6, -s * 0.35, 0, s * 0.3, C.metal)
	-- perimeter wall
	for _, side in { -1, 1 } do
		blk(s, 3, 1, 0, 0, side * s / 2, C.pad)
		blk(1, 3, s, side * s / 2, 0, 0, C.pad)
	end
end

function ModelBuilder.warPoint(style: string, size: number): Model
	local kit = AssetLibrary.instantiate("site_" .. style, { width = size, depth = size })
	if kit then
		kit.Name = style
		return kit
	end
	local model = Instance.new("Model")
	model.Name = style
	M = model
	local prevG = G
	G = 0
	local fn = PointStyles[style] or PointStyles.city
	fn(size)
	G = prevG
	local center = Instance.new("Part")
	center.Name = "Base"
	center.Anchored = true
	center.Size = Vector3.new(size, 0.2, size)
	center.CFrame = CFrame.new(0, -0.1, 0)
	center.Transparency = 1
	center.CanCollide = false
	center.Parent = model
	model.PrimaryPart = center
	return model
end

---------------------------------------------------------------------------
-- States
---------------------------------------------------------------------------
-- Under construction: show the building as a translucent blueprint.
function ModelBuilder.setConstruction(model: Model, on: boolean)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "Base" and d.Name ~= "Root" then
			if on then
				if d:GetAttribute("T0") == nil then
					d:SetAttribute("T0", d.Transparency)
					d:SetAttribute("C0", d.CanCollide)
				end
				d.Transparency = math.max(d.Transparency, 0.7)
				d.CanCollide = false
			else
				local t0 = d:GetAttribute("T0")
				if t0 ~= nil then
					d.Transparency = t0 :: number
					d.CanCollide = d:GetAttribute("C0") == true
					d:SetAttribute("T0", nil)
					d:SetAttribute("C0", nil)
				end
			end
		end
	end
end

-- Free-form road segment along local Z (width x len). Round caps at both
-- ends fill the joints, so segments meeting at any angle read as one road.
-- A single tile (len <= width) stays square, like the GRID-mode road tile.
function ModelBuilder.roadSegment(width: number, len: number, seed: number?): Model
	local model = Instance.new("Model")
	model.Name = "road"
	M = model
	local lift = ((seed or 0) % 5) * 0.012 -- overlapping junctions don't z-fight
	local h = 0.3 + lift
	local base = blk(width, h, len, 0, 0, 0, C.asphalt)
	base.Name = "Base"
	model.PrimaryPart = base
	if len > width + 0.01 then
		for _, z in { -len / 2, len / 2 } do
			local cap = cyl(h, width, 0, 0, z, C.asphalt)
			cap.Name = "Cap"
		end
	end
	if len > 3 then
		local lineLen = math.max(len - width, 1)
		local centre = noCollide(blk(0.35, 0.02, lineLen, 0, h, 0, C.line))
		centre.CanQuery = false
		for _, side in { -1, 1 } do
			local edge = noCollide(blk(0.25, 0.02, lineLen, side * (width / 2 - 0.7), h, 0, C.line))
			edge.CanQuery = false
		end
	end
	return model
end

-- Damaged by a strike: scorched colours + smoke until repaired.
function ModelBuilder.setDamaged(model: Model, on: boolean)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "Root" then
			if on then
				if d:GetAttribute("Col0") == nil then
					d:SetAttribute("Col0", d.Color)
				end
				d.Color = (d:GetAttribute("Col0") :: Color3):Lerp(Color3.new(0.12, 0.11, 0.1), 0.6)
			else
				local c0 = d:GetAttribute("Col0")
				if c0 ~= nil then
					d.Color = c0 :: Color3
					d:SetAttribute("Col0", nil)
				end
			end
		end
	end
	local base = model.PrimaryPart
	if not base then
		return
	end
	local existing = base:FindFirstChild("DamageSmoke")
	if on and not existing then
		local att = Instance.new("Attachment")
		att.Name = "DamageSmoke"
		att.Position = Vector3.new(0, 4, 0)
		att.Parent = base
		local smoke = Instance.new("ParticleEmitter")
		smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
		smoke.Color = ColorSequence.new(Color3.fromRGB(60, 60, 60))
		smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 9) })
		smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
		smoke.Lifetime = NumberRange.new(3, 5)
		smoke.Rate = 4
		smoke.Speed = NumberRange.new(4, 7)
		smoke.Parent = att
	elseif not on and existing then
		existing:Destroy()
	end
end

return ModelBuilder
