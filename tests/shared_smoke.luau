--!nocheck
-- Run via tests/run.sh (needs Lune). Smoke-tests every shared module and procedural model.
-- Minimal Roblox-like loader for running ModuleScripts from a built place in Lune.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local H = {}

-- Model pivot helpers Lune doesn't ship
local function bbox(model)
	local minV, maxV
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local p = d.CFrame.Position
			local h = d.Size / 2
			local lo, hi = p - h, p + h
			minV = minV and roblox.Vector3.new(math.min(minV.X, lo.X), math.min(minV.Y, lo.Y), math.min(minV.Z, lo.Z)) or lo
			maxV = maxV and roblox.Vector3.new(math.max(maxV.X, hi.X), math.max(maxV.Y, hi.Y), math.max(maxV.Z, hi.Z)) or hi
		end
	end
	return minV, maxV
end
roblox.implementMethod("Model", "GetPivot", function(self)
	if self.PrimaryPart then
		return self.PrimaryPart.CFrame
	end
	local lo, hi = bbox(self)
	return roblox.CFrame.new(lo and (lo + hi) / 2 or roblox.Vector3.new())
end)
roblox.implementMethod("Model", "PivotTo", function(self, cf)
	local current = self:GetPivot()
	local delta = cf * current:Inverse()
	for _, d in self:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = delta * d.CFrame
		end
	end
end)
roblox.implementMethod("Model", "TranslateBy", function(self, v)
	for _, d in self:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = d.CFrame + v
		end
	end
end)
roblox.implementMethod("Model", "GetBoundingBox", function(self)
	local lo, hi = bbox(self)
	return roblox.CFrame.new((lo + hi) / 2), hi - lo
end)

-- Random shim (Lune's roblox lib has no Random)
local Random = {}
Random.__index = Random
function Random.new(seed)
	return setmetatable({ s = (seed or os.clock() * 1e6) % 2147483647 }, Random)
end
function Random:_next()
	self.s = (self.s * 16807) % 2147483647
	return self.s / 2147483647
end
function Random:NextNumber(a, b)
	a, b = a or 0, b or 1
	return a + (b - a) * self:_next()
end
function Random:NextInteger(a, b)
	return math.floor(a + (b - a + 1) * self:_next())
end

local process = require("@lune/process")
local game = roblox.deserializePlace(fs.readFile(process.args[1]))
H.game = game

local cache = {}
local env
local function req(module)
	local key = module:GetFullName()
	if cache[key] then
		return cache[key]
	end
	assert(module:IsA("ModuleScript"), "require on non-module " .. module:GetFullName())
	local fn = luau.load(module.Source, {
		debugName = module:GetFullName(),
		environment = (function()
			local e = { script = module, require = req, game = game, workspace = game:FindFirstChildOfClass("Workspace"), Random = Random }
			for k, v in env do
				e[k] = v
			end
			return e
		end)(),
	})
	local result = fn()
	cache[key] = result
	return result
end

env = setmetatable({
	Instance = roblox.Instance, Vector3 = roblox.Vector3, Vector2 = roblox.Vector2, CFrame = roblox.CFrame,
	Color3 = roblox.Color3, UDim2 = roblox.UDim2, UDim = roblox.UDim, Enum = roblox.Enum, Font = roblox.Font,
	NumberSequence = roblox.NumberSequence, NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	ColorSequence = roblox.ColorSequence, ColorSequenceKeypoint = roblox.ColorSequenceKeypoint, NumberRange = roblox.NumberRange, Random = Random,
	typeof = typeof, task = task, warn = print,
}, { __index = _G })

H.require = req


local game = H.game
local Shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
local function mod(path)
	local inst = Shared
	for part in path:gmatch("[^%.]+") do
		inst = inst:FindFirstChild(part)
		assert(inst, "missing " .. path)
	end
	return H.require(inst)
end

local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FAIL: " .. msg)
	end
end

local Config = mod("Config")
local Format = mod("Util.Format")
local Grid = mod("Util.Grid")
local Ballistics = mod("Util.Ballistics")
local Buildings = mod("Catalog.Buildings")
local Weapons = mod("Catalog.Weapons")
local Units = mod("Catalog.Units")
local Research = mod("Catalog.Research")
local Products = mod("Catalog.Products")
local Quests = mod("Catalog.Quests")
local WarMap = mod("Catalog.WarMap")
local ModelBuilder = mod("ModelBuilder")

-- Format
check(Format.short(24100000) == "24.1M", "short 24.1M got " .. Format.short(24100000))
check(Format.short(9400) == "9.4k", "short 9.4k got " .. Format.short(9400))
check(Format.short(1000) == "1k", "short 1k got " .. Format.short(1000))
check(Format.short(950) == "950", "short 950")
check(Format.short(123456) == "123k", "short 123k got " .. Format.short(123456))
check(Format.commas(12000) == "12,000", "commas got " .. Format.commas(12000))
check(Format.commas(1234567) == "1,234,567", "commas big")
check(Format.clock(83) == "01:23", "clock")
check(Format.duration(48) == "48s" and Format.duration(130) == "2m 10s", "duration")
check(Format.cash(-1500) == "-$1.5k", "neg cash " .. Format.cash(-1500))

-- World layout: islands on a ring around the central battlefield
local V3 = roblox.Vector3
local CFrame = roblox.CFrame
local Vector2 = roblox.Vector2
for i = 1, Config.MaxPlots do
	local o = Grid.plotOrigin(i)
	-- the island's front edge (local -Z) faces the battlefield
	local look = Grid.plotCFrame(i).LookVector
	local toCenter = (Config.MainlandOrigin - o).Unit
	check(look:Dot(toCenter) > 0.999, "island faces centre " .. i)
	-- island + beach corners stay clear of the battlefield and of each other
	local half = Grid.PlotSize / 2 + Grid.Rim
	for _, c in { { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } } do
		local corner = (Grid.plotCFrame(i) * CFrame.new(c[1] * half, 0, c[2] * half)).Position
		check(not Grid.inMainland(corner, 15), "island overlaps battlefield " .. i)
		for j = 1, Config.MaxPlots do
			if j ~= i then
				check(not Grid.insidePlot(j, corner, Grid.Rim + 10), ("islands %d/%d overlap"):format(i, j))
			end
		end
	end
	-- local <-> world round trip
	local cf = Grid.toWorld(i, 37.5, -120, 30)
	local l = Grid.toLocal(i, cf.Position)
	check(math.abs(l.X - 37.5) < 1e-3 and math.abs(l.Z + 120) < 1e-3, "toLocal round trip " .. i)
	-- zones
	local z1, i1 = Grid.zoneAt(o)
	check(z1 == "plot" and i1 == i, "zone plot " .. i)
	local z2, i2 = Grid.zoneAt((Grid.shore(i) + Grid.gate(i)) / 2)
	check(z2 == "bridge" and i2 == i, "zone bridge " .. i .. " got " .. tostring(z2))
	check((Grid.zoneAt(Grid.landing(i))) == "mainland", "landing on battlefield " .. i)
	check((Grid.zoneAt(Grid.yard(i))) == "plot", "yard on island " .. i)
end
check((Grid.zoneAt(Config.MainlandOrigin)) == "mainland", "zone centre")
check((Grid.zoneAt(Config.MainlandOrigin + V3.new(2200, 0, 0))) == "sea", "zone sea")
local gx, gz = Grid.snapLocal(5.3, -7.9, 8, 12, 90)
check((gx - 6) % 4 == 0 and (gz - 4) % 4 == 0, ("grid snap edges on cells %.2f %.2f"):format(gx, gz))

-- Footprints (free-form placement geometry)
local Footprint = mod("Util.Footprint")
local a = Footprint.rect(0, 0, 8, 8, 0)
check(not Footprint.overlaps(a, Footprint.rect(8, 0, 8, 8, 0)), "touching rects don't overlap")
check(Footprint.overlaps(a, Footprint.rect(7, 0, 8, 8, 0)), "overlapping rects")
check(Footprint.overlaps(a, Footprint.rect(9, 0, 8, 8, 45)), "rotated corner overlaps")
check(not Footprint.overlaps(a, Footprint.rect(10, 0, 8, 8, 45)), "rotated clear")
check(Footprint.inside(Footprint.rect(0, 0, 8, 8, 30), 10) and not Footprint.inside(Footprint.rect(236, 0, 8, 8, 45), 239.5), "inside land")
local sx, sz, sa, sl = Footprint.segment(0, 0, 30, 40)
check(math.abs(sl - 50) < 1e-6 and math.abs(sx - 15) < 1e-6 and math.abs(sz - 20) < 1e-6, "segment centre/length")
local e1, e2 = Footprint.ends(Footprint.rect(sx, sz, 8, sl, sa))
check((e1 - Vector2.new(0, 0)).Magnitude < 1e-3 and (e2 - Vector2.new(30, 40)).Magnitude < 1e-3, "segment ends")
local h = {}
Footprint.hashAdd(h, 7, Footprint.rect(100, 100, 8, 8, 0))
check(Footprint.hashQuery(h, Footprint.rect(104, 100, 4, 4, 0))[7] == true, "hash finds neighbour")
check(Footprint.hashQuery(h, Footprint.rect(-100, -100, 4, 4, 0))[7] == nil, "hash skips far")
Footprint.hashRemove(h, 7, Footprint.rect(100, 100, 8, 8, 0))
check(next(h) == nil, "hash empties")

-- Catalog consistency
local passKeys = {}
for _, p in Products.Passes do passKeys[p.key] = true end
for _, def in Buildings.all() do
	if def.research then check(Research.get(def.research) ~= nil, "building research missing " .. def.id) end
	if def.pass then check(passKeys[def.pass], "building pass missing " .. def.id) end
	if def.launcher then
		local found = false
		for _, w in Weapons.all() do if w.family == def.launcher then found = true end end
		check(found, "launcher without weapon " .. def.id)
	end
	check(def.size[1] >= 1 and def.size[2] >= 1, "size " .. def.id)
end
for _, w in Weapons.all() do
	check(Research.get(w.research) ~= nil, "weapon research " .. w.id)
	local launcher = false
	for _, def in Buildings.all() do if def.launcher == w.family and def.faction == "Standard" then launcher = true end end
	check(launcher, "weapon has no standard launcher " .. w.id)
end
for _, u in Units.all() do
	check(Research.get(u.research) ~= nil, "unit research " .. u.id)
	if u.pass then check(passKeys[u.pass], "unit pass " .. u.id) end
end
for _, r in Research.all() do
	for _, req in r.requires do check(Research.get(req) ~= nil, "research req " .. r.id .. " -> " .. req) end
end
for i, q in Quests do
	if q.kind == "build" then check(Buildings.get(q.target) ~= nil, "quest building " .. i) end
	if q.kind == "research" then check(Research.get(q.target) ~= nil, "quest research " .. i) end
	if q.kind == "stock" then check(Weapons.get(q.target) ~= nil, "quest weapon " .. i) end
end
for _, p in WarMap do
	check(p.offset.Magnitude < Config.MainlandRadius - 250, "point near edge " .. p.id)
	for i = 1, Config.MaxPlots do
		-- keep strategic points off the bridge lanes
		local dir = Grid.direction(i)
		local along = p.offset:Dot(dir)
		check(p.id == "capital" or along < 0 or (p.offset - dir * along).Magnitude > 120, ("point %s on lane %d"):format(p.id, i))
	end
end

-- ModelBuilder: every asset builds, has parts and a primary part
local function partCount(m)
	local n = 0
	for _, d in m:GetDescendants() do if d:IsA("BasePart") then n += 1 end end
	return n
end
for _, def in Buildings.all() do
	local ok, m = pcall(ModelBuilder.building, def)
	check(ok, "building model error " .. def.id .. ": " .. tostring(m))
	if ok then
		check(m.PrimaryPart ~= nil and m.PrimaryPart.Name == "Base", "no Base " .. def.id)
		check(partCount(m) >= (def.model == "road" and 1 or 3), "too few parts " .. def.id .. " (" .. partCount(m) .. ")")
		-- footprint containment: nothing pokes far outside its cells
		local w, d = def.size[1] * Config.CellSize, def.size[2] * Config.CellSize
		for _, p in m:GetDescendants() do
			if p:IsA("BasePart") then
				local pos = p.CFrame.Position
				if math.abs(pos.X) > w / 2 + 4 or math.abs(pos.Z) > d / 2 + 4 then
					check(false, ("part outside footprint %s %s at %.1f,%.1f (size %dx%d)"):format(def.id, p.Name, pos.X, pos.Z, w, d))
					break
				end
			end
		end
		local ok2, err2 = pcall(function()
			ModelBuilder.setConstruction(m, true)
			ModelBuilder.setConstruction(m, false)
			ModelBuilder.setDamaged(m, true)
			ModelBuilder.setDamaged(m, false)
		end)
		check(ok2, "state toggles " .. def.id .. ": " .. tostring(err2))
	end
end
for _, u in Units.all() do
	local ok, m = pcall(ModelBuilder.unit, u)
	check(ok and m.PrimaryPart and m.PrimaryPart.Name == "Root", "unit model " .. u.id .. ": " .. tostring(m))
end
for _, w in Weapons.all() do
	local ok, m = pcall(ModelBuilder.projectile, w)
	check(ok and m.PrimaryPart ~= nil, "projectile " .. w.id .. ": " .. tostring(m))
end
check(pcall(ModelBuilder.fuelTruck), "fuel truck")
local okRoad, road = pcall(ModelBuilder.roadSegment, 8, 53.5, 3)
check(okRoad and road.PrimaryPart ~= nil and math.abs(road.PrimaryPart.Size.Z - 53.5) < 1e-6, "road segment model")
for _, p in WarMap do
	local ok, m = pcall(ModelBuilder.warPoint, p.model, 130)
	check(ok, "war point " .. p.model .. ": " .. tostring(m))
end

-- Rank ladder + flags
local Rank = mod("Util.Rank")
local Flag = mod("Util.Flag")
check(Rank.of(0).name == "Outpost" and Rank.of(0).level == 1, "rank 0")
check(Rank.of(600).name == "Township" and Rank.of(600).progress > 0, "rank township")
check(Rank.of(1e9).level == #Config.Ranks and Rank.of(1e9).next == nil, "rank cap")
check(Rank.power({ pop = 100, buildingValue = 10000, researched = 2, units = 1, points = 1 }) == 100 + 100 + 300 + 80 + 600, "power formula")
check(Flag.encode(Flag.decode("3,5,1,6,4")) == "3,5,1,6,4", "flag round trip")
check(Flag.encode(Flag.decode("garbage")) == Flag.encode(Flag.Default), "flag decode fallback")
check(Flag.encode(Flag.sanitize({ p = 99, c = { -4, 99, 2.7 }, e = 50 })) == "6,1,12,2,4", "flag sanitize clamps")
for p = 1, #Flag.Patterns do
	for e = 0, #Flag.Emblems - 1 do
		local holder = roblox.Instance.new("Frame")
		local ok, err = pcall(Flag.draw, holder, { p = p, c = { 1, 4, 3 }, e = e })
		check(ok, ("flag draw p%d e%d: %s"):format(p, e, tostring(err)))
	end
end

-- Blender kit: fake imported meshes are picked up, normalised and used
do
	local roblox = require("@lune/roblox")
	local V3, CF = roblox.Vector3, roblox.CFrame
	local RS = game:GetService("ReplicatedStorage")
	local assets = RS:FindFirstChild("Assets") or roblox.Instance.new("Folder")
	assets.Name = "Assets"
	assets.Parent = RS
	local function mesh(parent, name, size, pos)
		local p = roblox.Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = CF.new(pos)
		p.Parent = parent
		return p
	end
	-- a house modelled 3x too big, offset from the origin, long side on Z
	local house = roblox.Instance.new("Model")
	house.Name = "small_house"
	house.Parent = assets
	mesh(house, "small_house__Body", V3.new(18, 15, 24), V3.new(50, 7.5, 50))
	mesh(house, "small_house__Lights", V3.new(12, 3, 0.3), V3.new(50, 6, 38))
	-- a tank pointing +X (Front marker on +X)
	local tank = roblox.Instance.new("Model")
	tank.Name = "unit_m1"
	tank.Parent = assets
	mesh(tank, "unit_t90__Body", V3.new(20, 6, 8), V3.new(0, 3, 0))
	mesh(tank, "unit_t90__Front", V3.new(0.2, 0.2, 0.2), V3.new(12, 3, 0))
	-- turbine with a rotor + pivot marker
	local wt = roblox.Instance.new("Model")
	wt.Name = "wind_turbine"
	wt.Parent = assets
	mesh(wt, "wind_turbine__Body", V3.new(2, 30, 2), V3.new(0, 15, 0))
	mesh(wt, "wind_turbine__Rotor", V3.new(16, 16, 1), V3.new(0, 30, -1.2))
	mesh(wt, "wind_turbine__Spin", V3.new(0.2, 0.2, 0.2), V3.new(0, 30, -1.2))
	local AssetLibrary = mod("AssetLibrary")
	AssetLibrary.refresh()
	check(AssetLibrary.count() == 3 and AssetLibrary.has("small_house") and AssetLibrary.has("unit_t90"), "kit indexed")
	local defH = Buildings.get("small_house")
	local m = ModelBuilder.building(defH)
	check(m:GetAttribute("FromKit") == true, "kit building used")
	local lo, hi = bbox(m)
	local fw, fd = defH.size[1] * Config.CellSize, defH.size[2] * Config.CellSize
	check(hi.X - lo.X <= fw + 0.05 and hi.Z - lo.Z <= fd + 0.05 and math.abs(lo.Y) < 0.05, ("kit building fits footprint (%.2f x %.2f in %dx%d)"):format(hi.X - lo.X, hi.Z - lo.Z, fw, fd))
	check(m:FindFirstChild("Hitbox") ~= nil and m.PrimaryPart.Name == "Base", "kit building base + hitbox")
	local glow = m:FindFirstChild("LightsGlow")
	check(glow ~= nil and glow:GetAttribute("NightGlow") == true and glow.Transparency == 1, "kit night glow twin")
	local unitDef
	for _, u in Units.all() do
		if u.id == "t90" then
			unitDef = u
		end
	end
	if unitDef then
		local um = ModelBuilder.unit(unitDef)
		-- rotation-aware extents of the hull mesh
		local body = um:FindFirstChild("unit_t90__Body")
		local ext = body.CFrame:VectorToWorldSpace(body.Size)
		check(um.PrimaryPart.Name == "Root" and math.abs(ext.Z) > math.abs(ext.X), "kit unit turned to face -Z")
	else
		check(false, "unit t90 missing from catalog")
	end
	local wtm = ModelBuilder.building(Buildings.get("wind_turbine"))
	local rotor = wtm:FindFirstChild("Rotor")
	check(rotor and rotor.PrimaryPart and rotor:GetAttribute("Spin") ~= nil, "kit rotor pivot")
	-- unknown ids still fall back to procedural models
	check(ModelBuilder.building(Buildings.get("apartment")):GetAttribute("FromKit") == nil, "procedural fallback")
	assets:Destroy()
	AssetLibrary.refresh()
	check(AssetLibrary.count() == 0, "kit cleared")
end

-- Ballistics: endpoints and apex
local a, b = Vector3 and nil, nil
local roblox = require("@lune/roblox")
local from, to = roblox.Vector3.new(0, 0, 0), roblox.Vector3.new(1000, 0, 0)
check((Ballistics.position(from, to, 300, "missile", 0) - from).Magnitude < 1e-6, "ballistic start")
check((Ballistics.position(from, to, 300, "missile", 1) - to).Magnitude < 1e-6, "ballistic end")
check(math.abs(Ballistics.position(from, to, 300, "missile", 0.5).Y - 300) < 1e-6, "ballistic apex")
check((Ballistics.position(from, to, 40, "drone", 1) - to).Magnitude < 1e-6, "drone end")

print(failures == 0 and "ALL SHARED CHECKS PASSED" or (failures .. " FAILURES"))
