--[[
	ConquestService
	Generates the mainland (low-poly hills, dirt roads, forests, strategic
	points, staging pads) and runs the capture loop:

	  * Each point has a garrison. Enemy units in range shoot it down, missile
	    strikes knock big chunks off it, and it regenerates when left alone.
	  * At zero garrison, a single nation's units inside the ring capture it
	    (contested if the owner or a third nation is present).
	  * Owned points pay their bonus (cash, oil, power, steel, RP) every tick.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local WarMap = require(Shared.Catalog.WarMap)
local ModelBuilder = require(Shared.ModelBuilder)
local Nations = require(script.Parent.Nations)

type Nation = Nations.Nation

export type Point = {
	def: any,
	center: Vector3,
	model: Model,
	ring: BasePart,
	owner: number,
	garrison: number,
	capture: number,
	capturer: number,
}

local ConquestService = {}
local S: { [string]: any }
local points: { Point } = {}

local ORIGIN = Config.MainlandOrigin
local HALF = Config.MainlandSize / 2
local NEUTRAL = Color3.fromRGB(200, 200, 196)

local function part(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanTouch = false
	p.Parent = parent
	return p
end

---------------------------------------------------------------------------
-- World generation
---------------------------------------------------------------------------
local function buildGround(world: Folder)
	local tile = Config.MainlandSize / 2
	for ix = -1, 0 do
		for iz = -1, 0 do
			local c = ORIGIN + Vector3.new((ix + 0.5) * tile, -3, (iz + 0.5) * tile)
			part(world, Vector3.new(tile, 6, tile), CFrame.new(c), Color3.fromRGB(86, 110, 60), Enum.Material.Grass).Name = "Ground"
		end
	end
	local rim = 60
	for _, s in { -1, 1 } do
		part(world, Vector3.new(Config.MainlandSize + rim * 2, 6, rim), CFrame.new(ORIGIN + Vector3.new(0, -3.5, s * (HALF + rim / 2))), Color3.fromRGB(206, 184, 136), Enum.Material.Sand)
		part(world, Vector3.new(rim, 6, Config.MainlandSize), CFrame.new(ORIGIN + Vector3.new(s * (HALF + rim / 2), -3.5, 0)), Color3.fromRGB(206, 184, 136), Enum.Material.Sand)
	end
end

local function buildHills(world: Folder)
	local rng = Random.new(42)
	local greens = { Color3.fromRGB(72, 96, 52), Color3.fromRGB(96, 118, 62), Color3.fromRGB(118, 128, 70), Color3.fromRGB(84, 104, 56) }
	for _ = 1, 70 do
		-- hills hug the edges so the middle stays open for fighting
		local side = rng:NextInteger(1, 4)
		local along = rng:NextNumber(-HALF, HALF)
		local inward = rng:NextNumber(0, 260)
		local x, z
		if side == 1 then
			x, z = along, -HALF + inward
		elseif side == 2 then
			x, z = along, HALF - inward
		elseif side == 3 then
			x, z = -HALF + inward, along
		else
			x, z = HALF - inward, along
		end
		local size = Vector3.new(rng:NextNumber(60, 180), rng:NextNumber(30, 90), rng:NextNumber(60, 180))
		local cf = CFrame.new(ORIGIN + Vector3.new(x, -size.Y * 0.25, z))
			* CFrame.Angles(rng:NextNumber(-0.5, 0.5), rng:NextNumber(0, math.pi), rng:NextNumber(-0.5, 0.5))
		local hill = part(world, size, cf, greens[rng:NextInteger(1, #greens)])
		hill.Name = "Hill"
		hill.CanQuery = false
	end
end

local function buildRoad(world: Folder, a: Vector3, b: Vector3, bend: number)
	local mid = (a + b) / 2
	local dir = (b - a)
	local perp = Vector3.new(-dir.Z, 0, dir.X).Unit
	local ctrl = mid + perp * bend
	local segments = 14
	local prev = a
	for i = 1, segments do
		local t = i / segments
		local p = a * (1 - t) ^ 2 + ctrl * (2 * (1 - t) * t) + b * t ^ 2
		local len = (p - prev).Magnitude
		if len > 0.5 then
			local cf = CFrame.lookAt((prev + p) / 2, p) + Vector3.new(0, 0.05, 0)
			local seg = part(world, Vector3.new(9, 0.2, len + 4), cf, Color3.fromRGB(112, 78, 52))
			seg.Name = "Road"
			seg.CanCollide = false
		end
		prev = p
	end
end

local function buildTrees(world: Folder)
	local rng = Random.new(9)
	for _ = 1, 26 do
		local c = ORIGIN + Vector3.new(rng:NextNumber(-HALF + 120, HALF - 120), 0, rng:NextNumber(-HALF + 120, HALF - 120))
		local tooClose = false
		for _, def in WarMap do
			if ((ORIGIN + def.offset) - c).Magnitude < 160 then
				tooClose = true
				break
			end
		end
		if not tooClose then
			for _ = 1, rng:NextInteger(5, 10) do
				local p = c + Vector3.new(rng:NextNumber(-40, 40), 0, rng:NextNumber(-40, 40))
				local s = rng:NextNumber(0.8, 1.5)
				part(world, Vector3.new(1, 5 * s, 1), CFrame.new(p + Vector3.new(0, 2.5 * s, 0)), Color3.fromRGB(96, 74, 52)).CanCollide = false
				local canopy = part(world, Vector3.new(7 * s, 7 * s, 7 * s), CFrame.new(p + Vector3.new(0, 7 * s, 0)), Color3.fromRGB(62, 96, 50))
				canopy.Shape = Enum.PartType.Ball
				canopy.CanCollide = false
			end
		end
	end
end

local function buildStaging(world: Folder)
	for i = 1, Config.MaxPlots do
		local pos = ORIGIN + Vector3.new(-1050 + (i - 1) * 300, 0, HALF - 110)
		local pad = part(world, Vector3.new(90, 0.4, 60), CFrame.new(pos + Vector3.new(0, 0.2, 0)), Color3.fromRGB(176, 176, 168))
		pad.Name = "Staging_" .. i
		part(world, Vector3.new(0.6, 14, 0.6), CFrame.new(pos + Vector3.new(-40, 7, -26)), Color3.fromRGB(80, 84, 90))
		local flag = part(world, Vector3.new(0.2, 4, 7), CFrame.new(pos + Vector3.new(-40, 12, -22.5)), Config.NationColors[i])
		flag.Name = "Flag"
		-- tunnel mouth
		part(world, Vector3.new(26, 14, 10), CFrame.new(pos + Vector3.new(0, 7, 40)), Color3.fromRGB(120, 124, 116))
		part(world, Vector3.new(16, 10, 10.4), CFrame.new(pos + Vector3.new(0, 5, 40)), Color3.fromRGB(30, 32, 36))
	end
end

local function buildPoint(world: Folder, def): Point
	local center = ORIGIN + def.offset
	local model = ModelBuilder.warPoint(def.model, 130)
	model.Name = def.id
	model:PivotTo(CFrame.new(center))
	local ring = Instance.new("Part")
	ring.Name = "Ring"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.Size = Vector3.new(0.3, Config.CaptureRadius * 2, Config.CaptureRadius * 2)
	ring.CFrame = CFrame.new(center + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Color = NEUTRAL
	ring.Transparency = 0.75
	ring.Material = Enum.Material.SmoothPlastic
	ring.Parent = model
	model:SetAttribute("PointId", def.id)
	model:SetAttribute("PointName", def.name)
	model:SetAttribute("Bonus", def.bonusText)
	model:SetAttribute("MaxGarrison", def.garrison)
	model:SetAttribute("Garrison", def.garrison)
	model:SetAttribute("Capture", 0)
	model:SetAttribute("Owner", 0)
	model:SetAttribute("OwnerName", "")
	model.Parent = world
	return {
		def = def,
		center = center,
		model = model,
		ring = ring,
		owner = 0,
		garrison = def.garrison,
		capture = 0,
		capturer = 0,
	}
end

---------------------------------------------------------------------------
-- Queries used by other services
---------------------------------------------------------------------------
local function flatDist(a: Vector3, b: Vector3): number
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

function ConquestService.points(): { Point }
	return points
end

function ConquestService.enemyPointInRange(pos: Vector3, range: number, userId: number): Point?
	for _, p in points do
		if p.owner ~= userId and p.garrison > 0 and flatDist(pos, p.center) <= range + Config.CaptureRadius then
			return p
		end
	end
	return nil
end

function ConquestService.pointNear(pos: Vector3, extra: number): Point?
	for _, p in points do
		if flatDist(pos, p.center) <= Config.CaptureRadius + extra then
			return p
		end
	end
	return nil
end

function ConquestService.damageGarrison(p: Point, amount: number, attacker: Nation?): number
	if attacker and p.owner == attacker.userId then
		return 0
	end
	local dealt = math.min(p.garrison, amount)
	p.garrison -= dealt
	p.model:SetAttribute("Garrison", math.floor(p.garrison))
	return dealt
end

function ConquestService.bonusFor(n: Nation): { income: number, oil: number, power: number, steel: number, rp: number }
	local b = { income = 0, oil = 0, power = 0, steel = 0, rp = 0 }
	for _, p in points do
		if p.owner == n.userId then
			for k, v in p.def.bonus do
				b[k] += v
			end
		end
	end
	return b
end

local function setOwner(p: Point, userId: number)
	local old = p.owner
	p.owner = userId
	p.capture = 0
	p.capturer = 0
	local n = userId ~= 0 and Nations.byUserId(userId) or nil
	p.model:SetAttribute("Owner", userId)
	p.model:SetAttribute("OwnerName", n and n.player.DisplayName or "")
	p.ring.Color = n and (Config.NationColors[n.plotIndex] or NEUTRAL) or NEUTRAL
	p.model:SetAttribute("Color", p.ring.Color)
	if n then
		p.garrison = p.def.garrison * 0.3
		n.data.Stats.Captures += 1
		Nations.notifyAll(("%s captured the %s!"):format(n.player.DisplayName, p.def.name), "war")
	end
	local oldNation = old ~= 0 and Nations.byUserId(old) or nil
	if oldNation and old ~= userId then
		Nations.notify(oldNation.player, ("You lost the %s"):format(p.def.name), "bad")
	end
end

function ConquestService.releaseOwner(userId: number)
	for _, p in points do
		if p.owner == userId then
			setOwner(p, 0)
			p.garrison = p.def.garrison * 0.5
		end
		if p.capturer == userId then
			p.capture = 0
			p.capturer = 0
		end
	end
end

---------------------------------------------------------------------------
-- Capture loop
---------------------------------------------------------------------------
local function step(dt: number)
	local units = S.UnitService.mainlandUnits()
	for _, p in points do
		local occupants: { [number]: { power: number, units: { any } } } = {}
		for _, u in units do
			if flatDist(u.root.CFrame.Position, p.center) <= Config.CaptureRadius then
				local o = occupants[u.n.userId]
				if not o then
					o = { power = 0, units = {} }
					occupants[u.n.userId] = o
				end
				o.power += u.def.capture
				table.insert(o.units, u)
			end
		end
		local enemyIds = {}
		for userId in occupants do
			if userId ~= p.owner then
				table.insert(enemyIds, userId)
			end
		end
		local ownerPresent = p.owner ~= 0 and occupants[p.owner] ~= nil

		if #enemyIds == 0 then
			p.garrison = math.min(p.def.garrison, p.garrison + Config.GarrisonRegen * dt)
			p.capture = math.max(0, p.capture - 5 * dt)
			if p.capture == 0 then
				p.capturer = 0
			end
		else
			-- the garrison fights back
			if p.garrison > 0 then
				local dps = 6 + p.def.garrison * 0.012
				local target = occupants[enemyIds[1]].units[1]
				if target then
					S.UnitService.damage(target, dps * dt, nil)
				end
			end
			if p.garrison <= 0 and not ownerPresent and #enemyIds == 1 then
				local id = enemyIds[1]
				if p.capturer ~= id then
					p.capturer = id
					p.capture = 0
				end
				p.capture += occupants[id].power * dt
				if p.capture >= Config.CaptureTime then
					setOwner(p, id)
				end
			end
		end
		p.model:SetAttribute("Garrison", math.floor(p.garrison))
		p.model:SetAttribute("Capture", math.floor(p.capture / Config.CaptureTime * 100))
		p.model:SetAttribute("Capturer", p.capturer)
		p.model:SetAttribute("Contested", #enemyIds > 0 and (ownerPresent or #enemyIds > 1))
	end
end

-- exposed for automated tests
ConquestService._step = step

function ConquestService.init(services)
	S = services
	local world = Instance.new("Folder")
	world.Name = "Mainland"
	world.Parent = workspace
	buildGround(world)
	buildHills(world)
	local capital = ORIGIN
	for i, def in WarMap do
		if def.id ~= "capital" then
			buildRoad(world, capital, ORIGIN + def.offset, (i % 2 == 0 and 1 or -1) * 140)
		end
	end
	for i = 1, Config.MaxPlots do
		local staging = ORIGIN + Vector3.new(-1050 + (i - 1) * 300, 0, HALF - 110)
		if i % 2 == 1 then
			buildRoad(world, staging, capital, (i - 4) * 30)
		end
	end
	buildTrees(world)
	buildStaging(world)
	local pointsFolder = Instance.new("Folder")
	pointsFolder.Name = "Points"
	pointsFolder.Parent = world
	for _, def in WarMap do
		table.insert(points, buildPoint(pointsFolder, def))
	end
end

function ConquestService.start()
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(step, 1)
			if not ok then
				warn("[Conquest] step failed: " .. tostring(err))
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		ConquestService.releaseOwner(player.UserId)
	end)
end

return ConquestService
