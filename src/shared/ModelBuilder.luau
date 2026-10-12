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
-- Building styles
---------------------------------------------------------------------------
local Styles: { [string]: (w: number, d: number, p: { [string]: any }) -> () } = {}

Styles.house = function(w, d, p)
	local bw, bd = w - 1.6, d - 1.6
	local wallC = p.wallColor or C.wallWarm
	blk(bw, 5, bd, 0, G, 0, wallC)
	local roofC = p.roof == "slate" and C.slate or C.terracotta
	gableRoof(bw + 0.6, bd, 0, G + 5, 0, roofC)
	noCollide(blk(1.4, 2.6, 0.2, 0, G, -bd / 2 - 0.1, C.trunk)) -- door
	lit(blk(1.2, 1.2, 0.2, -bw / 4 - 0.3, G + 2.2, -bd / 2 - 0.1, C.window))
	lit(blk(1.2, 1.2, 0.2, bw / 4 + 0.3, G + 2.2, -bd / 2 - 0.1, C.window))
	lit(blk(0.2, 1.2, 1.2, bw / 2 + 0.1, G + 2.2, 0, C.window))
	lit(blk(0.2, 1.2, 1.2, -bw / 2 - 0.1, G + 2.2, 0, C.window))
	blk(0.8, 2.5, 0.8, bw / 4, G + 6, bd / 4, C.brick)
end

Styles.townhouse = function(w, d, p)
	local n = p.count or 3
	local each = w / n
	local walls = { C.wallWarm, C.wall, rgb(222, 200, 186) }
	for i = 1, n do
		local x = -w / 2 + each * (i - 0.5)
		local bw, bd = each - 0.3, d - 1.6
		blk(bw, 7, bd, x, G, 0, walls[(i - 1) % #walls + 1])
		gableRoof(bw, bd, x, G + 7, 0, i % 2 == 0 and C.slate or C.terracotta, 24)
		noCollide(blk(1.4, 2.6, 0.2, x, G, -bd / 2 - 0.1, C.trunk))
		lit(blk(bw - 2, 1.2, 0.2, x, G + 4.4, -bd / 2 - 0.1, C.window))
		lit(blk(bw - 2, 1.2, 0.2, x, G + 4.4, bd / 2 + 0.1, C.window))
	end
end

Styles.apartment = function(w, d, p)
	local floors = p.floors or 4
	local fh = 3.2
	local bw, bd = w - 1.4, d - 1.4
	blk(bw, floors * fh + 0.8, bd, 0, G, 0, C.panel)
	windows(bw, bd, 0, 0, G + 0.8, floors, fh, C.window, true)
	blk(bw + 0.4, 0.6, bd + 0.4, 0, G + floors * fh + 0.8, 0, C.roofGrey)
	-- rooftop details
	local units = math.max(1, math.floor(bw / 12))
	for i = 1, units do
		local x = -bw / 2 + (i - 0.5) * (bw / units)
		blk(2.2, 1.6, 2.2, x, G + floors * fh + 1.4, 0, C.metal)
	end
	-- entrances
	local doors = math.max(1, math.floor(bw / 10))
	for i = 1, doors do
		local x = -bw / 2 + (i - 0.5) * (bw / doors)
		noCollide(blk(2, 2.6, 0.4, x, G, -bd / 2 - 0.2, C.darkMetal))
	end
end

Styles.tower = function(w, d, p)
	local floors = p.floors or 14
	local fh = 3.2
	local bw, bd = w - 2.2, d - 2.2
	blk(w - 0.8, 4, d - 0.8, 0, G, 0, C.wallCool)
	blk(bw, floors * fh, bd, 0, G + 4, 0, C.wall)
	windows(bw, bd, 0, 0, G + 4, floors, fh, C.glass)
	local top = G + 4 + floors * fh
	blk(bw - 2, 3, bd - 2, 0, top, 0, C.roofGrey)
	noCollide(cyl(6, 0.3, 0, top + 3, 0, C.metal))
	noCollide(ball(0.7, 0, top + 9.2, 0, C.red, Enum.Material.Neon))
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

Styles.shop = function(w, d, _p)
	local bw, bd = w - 1.4, d - 1.4
	blk(bw, 4.6, bd, 0, G, 0, C.wall)
	blk(bw + 0.2, 0.4, bd + 0.2, 0, G + 4.6, 0, C.roofGrey)
	noCollide(blk(bw - 1, 2.6, 0.2, 0, G + 0.6, -bd / 2 - 0.1, C.glass))
	local awning = noCollide(plank(bw, 0.2, 1.8, CFrame.new(0, G + 3.6, -bd / 2 - 0.8) * CFrame.Angles(math.rad(18), 0, 0), C.red))
	awning.Name = "Awning"
	noCollide(blk(bw * 0.7, 0.9, 0.25, 0, G + 4.8, -bd / 2 + 0.2, C.yellow))
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

Styles.office = function(w, d, p)
	local floors = p.floors or 8
	local fh = 3.4
	local bw, bd = w - 1.6, d - 1.6
	blk(bw, floors * fh, bd, 0, G, 0, C.glass, Enum.Material.Glass).Transparency = 0
	for f = 1, floors do
		noCollide(blk(bw + 0.2, 0.5, bd + 0.2, 0, G + f * fh - 0.5, 0, C.wallCool))
	end
	blk(bw - 2, 2, bd - 2, 0, G + floors * fh, 0, C.metal)
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

local UNIT_LENGTH = { truck = 8, ifv = 9, tank = 10, mlrs = 9.6, spaag = 9 }

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

UnitStyles.truck = function(_p, col)
	root(3.6, 3.4, 8)
	blk(3.2, 2.4, 2.4, 0, 0.8, -2.6, col)
	lit(blk(2.8, 0.8, 0.15, 0, 2.1, -3.82, C.window))
	blk(3.4, 2.6, 5, 0, 0.8, 1.2, rgb(120, 126, 98))
	wheelPair(0, 0.75, -2.6, 3.3, 1.5)
	wheelPair(0, 0.75, 0.6, 3.3, 1.5)
	wheelPair(0, 0.75, 2.6, 3.3, 1.5)
end

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
