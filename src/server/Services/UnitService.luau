--[[
	UnitService
	Ground vehicles. Units are physics assemblies driven by AlignPosition /
	AlignOrientation (server-owned) so they glide smoothly on every client.

	They really drive: out of your city, over your bridge, across the central
	battlefield and, with PvP on, over a rival's bridge into their city. Every
	command is routed through the bridge waypoints. Units fight any enemy
	vehicle in the same theatre (the battlefield, or a city being raided),
	wear down strategic-point garrisons, and knock out buildings on raids.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Grid = require(Shared.Util.Grid)
local Net = require(Shared.Net)
local Format = require(Shared.Util.Format)
local Units = require(Shared.Catalog.Units)
local ModelBuilder = require(Shared.ModelBuilder)
local Nations = require(script.Parent.Nations)

type Nation = Nations.Nation

export type Unit = {
	uid: number,
	id: string,
	def: any,
	n: Nation,
	hp: number,
	model: Model,
	root: BasePart,
	align: AlignPosition,
	orient: AlignOrientation,
	location: string, -- "home" | "mainland" (battlefield + bridges) | "raid"
	height: number,
	lastShot: number,
	path: { Vector3 },
}

local UnitService = {}
local S: { [string]: any }
local folder: Folder
local all: { [Unit]: boolean } = {}

-- Battlefield or a bridge (open warzone).
function UnitService.inMainland(pos: Vector3): boolean
	local zone = Grid.zoneAt(pos)
	return zone == "mainland" or zone == "bridge"
end

function UnitService.stagingPos(n: Nation): Vector3
	return Grid.landing(n.plotIndex)
end

function UnitService.cap(n: Nation): number
	local cap = 10 + (n.stats.depotCap or 0)
	if n.passes.VIP then
		cap += 10
	end
	if n.passes.ExtraQueue then
		cap += 20
	end
	return math.min(cap, Config.MaxUnitsPerPlayer + 20)
end

function UnitService.count(n: Nation): number
	local c = 0
	for _ in n.units do
		c += 1
	end
	return c
end

function UnitService.canAdd(n: Nation): boolean
	return UnitService.count(n) < UnitService.cap(n)
end

local function homePos(n: Nation, near: any?): Vector3
	local anchor: Vector3? = nil
	for _, b in n.buildings do
		if b.def.depot and Nations.isActive(b) then
			anchor = S.BuildService.worldCFrame(n, b).Position
			break
		end
	end
	if not anchor and near then
		anchor = S.BuildService.worldCFrame(n, near).Position
	end
	local base = anchor or Grid.yard(n.plotIndex)
	local rng = Random.new()
	local p = base + Vector3.new(rng:NextNumber(-18, 18), 0, rng:NextNumber(-18, 18))
	-- keep inside the island
	local half = Grid.PlotSize / 2 - 6
	local l = Grid.toLocal(n.plotIndex, p)
	return (Grid.plotCFrame(n.plotIndex) * CFrame.new(math.clamp(l.X, -half, half), 0, math.clamp(l.Z, -half, half))).Position
end

local function setTarget(u: Unit, pos: Vector3)
	local current = u.root.CFrame.Position
	local target = Vector3.new(pos.X, u.height, pos.Z)
	u.align.Position = target
	local flatDir = Vector3.new(target.X - current.X, 0, target.Z - current.Z)
	if flatDir.Magnitude > 1 then
		u.orient.CFrame = CFrame.lookAt(Vector3.zero, flatDir.Unit)
	end
	u.model:SetAttribute("Moving", true)
end

function UnitService.spawn(n: Nation, id: string, hp: number?, near: any?, uid: number?): Unit?
	local def = Units.get(id)
	if not def then
		return nil
	end
	local model = ModelBuilder.unit(def)
	local root = model.PrimaryPart :: BasePart
	local height = root.Size.Y / 2
	-- weld everything to the root and make it a physics assembly
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.CanCollide = false
			p.CanTouch = false
			if p ~= root then
				p.Massless = true
				local w = Instance.new("WeldConstraint")
				w.Part0 = root
				w.Part1 = p
				w.Parent = p
			end
		end
	end
	local att = Instance.new("Attachment")
	att.Name = "Drive"
	att.Parent = root
	local align = Instance.new("AlignPosition")
	align.Mode = Enum.PositionAlignmentMode.OneAttachment
	align.Attachment0 = att
	align.MaxForce = 1e7
	align.MaxVelocity = def.speed * Config.UnitSpeedScale
	align.Responsiveness = 30
	align.Parent = root
	local orient = Instance.new("AlignOrientation")
	orient.Mode = Enum.OrientationAlignmentMode.OneAttachment
	orient.Attachment0 = att
	orient.MaxTorque = 1e7
	orient.Responsiveness = 18
	orient.Parent = root

	local unitUid = uid or n.nextUnitUid
	if unitUid >= n.nextUnitUid then
		n.nextUnitUid = unitUid + 1
	end
	model.Name = def.name
	model:SetAttribute("Unit", true)
	model:SetAttribute("UnitId", def.id)
	model:SetAttribute("Uid", unitUid)
	model:SetAttribute("OwnerId", n.userId)
	model:SetAttribute("OwnerName", n.player.DisplayName)
	model:SetAttribute("Hp", hp or def.hp)
	model:SetAttribute("MaxHp", def.hp)
	model:SetAttribute("Color", Config.NationColors[n.plotIndex] or Color3.new(1, 1, 1))

	local pos = homePos(n, near)
	model:PivotTo(CFrame.new(pos.X, height, pos.Z))
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = false
		end
	end
	align.Position = Vector3.new(pos.X, height, pos.Z)
	orient.CFrame = CFrame.new()
	model.Parent = folder
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	local u: Unit = {
		uid = unitUid,
		id = id,
		def = def,
		n = n,
		hp = hp or def.hp,
		model = model,
		root = root,
		align = align,
		orient = orient,
		location = "home",
		height = height,
		lastShot = 0,
		path = {},
	}
	n.units[unitUid] = u
	all[u] = true
	return u
end

function UnitService.remove(u: Unit, exploded: boolean?)
	all[u] = nil
	u.n.units[u.uid] = nil
	if exploded then
		Net.event("Effect"):FireAllClients("Explosion", u.root.CFrame.Position, 1)
	end
	u.model:Destroy()
end

-- Returns true if destroyed.
function UnitService.damage(u: Unit, amount: number, attacker: Nation?): boolean
	if not all[u] then
		return false
	end
	u.hp -= amount
	u.model:SetAttribute("Hp", math.max(0, math.floor(u.hp)))
	if u.hp <= 0 then
		Nations.notify(u.n.player, ("Your %s was destroyed"):format(u.def.name), "bad")
		if attacker then
			attacker.data.Stats.Kills += 1
		end
		UnitService.remove(u, true)
		return true
	end
	return false
end

function UnitService.unitsNear(pos: Vector3, radius: number, excludeUserId: number?): { Unit }
	local out = {}
	for u in all do
		if u.n.userId ~= excludeUserId then
			local p = u.root.CFrame.Position
			local d = Vector2.new(p.X - pos.X, p.Z - pos.Z).Magnitude
			if d <= radius then
				table.insert(out, u)
			end
		end
	end
	return out
end

function UnitService.mainlandUnits(): { Unit }
	local out = {}
	for u in all do
		if u.location == "mainland" then
			table.insert(out, u)
		end
	end
	return out
end

function UnitService.loadNation(n: Nation)
	for _, s in n.data.Units do
		if UnitService.count(n) >= Config.MaxUnitsPerPlayer + 20 then
			break
		end
		UnitService.spawn(n, s.id, s.hp, nil, s.u)
	end
end

function UnitService.serialize(n: Nation)
	local out = {}
	for _, u in n.units do
		table.insert(out, { u = u.uid, id = u.id, hp = math.floor(u.hp) })
	end
	n.data.Units = out
end

function UnitService.clearNation(n: Nation)
	for _, u in n.units do
		UnitService.remove(u, false)
	end
end

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------
local function collect(n: Nation, uids: any, filter: ((Unit) -> boolean)?): { Unit }
	local out = {}
	if typeof(uids) == "table" then
		for i, uid in uids do
			if i > 100 then
				break
			end
			local u = typeof(uid) == "number" and n.units[uid] or nil
			if u and (not filter or filter(u)) then
				table.insert(out, u)
			end
		end
	else
		for _, u in n.units do
			if not filter or filter(u) then
				table.insert(out, u)
			end
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Routing: city -> yard -> gate -> bridge -> shore -> battlefield -> ...
---------------------------------------------------------------------------
local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Waypoints from `from` to `to` through the bridges (straight lines on land).
function UnitService.route(from: Vector3, to: Vector3): { Vector3 }
	local zf, i = Grid.zoneAt(from)
	local zt, j = Grid.zoneAt(to)
	local out: { Vector3 } = {}
	local function add(p: Vector3)
		table.insert(out, flat(p))
	end
	local function intoTarget()
		if zt == "bridge" and j then
			add(Grid.landing(j))
			add(Grid.shore(j))
		elseif zt == "plot" and j then
			add(Grid.landing(j))
			add(Grid.shore(j))
			add(Grid.gate(j))
			add(Grid.yard(j))
		end
	end
	if zf == "plot" and i then
		if zt == "plot" and j == i then
			add(to)
			return out
		end
		add(Grid.yard(i))
		add(Grid.gate(i))
		if zt == "bridge" and j == i then
			add(to)
			return out
		end
		add(Grid.shore(i))
		add(Grid.landing(i))
	elseif zf == "bridge" and i then
		if zt == "plot" and j == i then
			add(Grid.gate(i))
			add(Grid.yard(i))
			add(to)
			return out
		elseif zt == "bridge" and j == i then
			add(to)
			return out
		end
		add(Grid.shore(i))
		add(Grid.landing(i))
	end
	intoTarget()
	add(to)
	-- drop waypoints that are behind us or doubled
	local cleaned: { Vector3 } = {}
	local last = flat(from)
	for _, p in out do
		if (p - last).Magnitude > 4 then
			table.insert(cleaned, p)
			last = p
		end
	end
	return cleaned
end

local function drive(u: Unit, target: Vector3)
	u.path = UnitService.route(u.root.CFrame.Position, target)
	local first = table.remove(u.path, 1)
	if first then
		setTarget(u, first)
	end
end

-- Theatre a unit is fighting in: "mainland" (battlefield + bridges), the
-- index of the island it's on, or nil when safe at home.
local function locate(u: Unit): (string, number?)
	local zone, idx = Grid.zoneAt(u.root.CFrame.Position)
	if zone == "plot" and idx == u.n.plotIndex then
		return "home", idx
	elseif zone == "plot" then
		return "raid", idx
	end
	return "mainland", nil
end

local function updateLocation(u: Unit)
	local loc = locate(u)
	if loc ~= u.location then
		u.location = loc
		u.model:SetAttribute("Location", loc)
	end
end

local function canRaid(n: Nation, defender: Nation?): (boolean, string?)
	if not defender or not defender.ready then
		return false, "Nobody lives there"
	end
	if not n.data.Pvp then
		return false, "Turn PvP ON to invade other nations"
	end
	if not defender.data.Pvp then
		return false, defender.player.DisplayName .. " has PvP OFF"
	end
	if S.CombatService.isShielded(defender) then
		return false, defender.player.DisplayName .. " is protected by the new-nation shield"
	end
	return true, nil
end

local function formation(units: { Unit }, target: Vector3): { Vector3 }
	local cols = math.ceil(math.sqrt(#units))
	local spacing = 11
	local out = {}
	for i = 1, #units do
		local row = (i - 1) // cols
		local col = (i - 1) % cols
		table.insert(out, target + Vector3.new((col - (cols - 1) / 2) * spacing, 0, (row - (cols - 1) / 2) * spacing))
	end
	return out
end

local function onCommand(player: Player, uids: any, target: any)
	local n = Nations.get(player)
	if not n or typeof(target) ~= "Vector3" or target.X ~= target.X or math.abs(target.X) > 1e5 or math.abs(target.Z) > 1e5 then
		return { ok = false, err = "Invalid request" }
	end
	local units = collect(n, uids)
	if #units == 0 then
		return { ok = false, err = "Select units first" }
	end
	local zone, idx = Grid.zoneAt(target)
	if zone == "sea" then
		return { ok = false, err = "Vehicles can't drive on water" }
	end
	if zone == "plot" and idx ~= n.plotIndex then
		local owner = S.PlotService.ownerAt(target)
		local ok, err = canRaid(n, owner and Nations.get(owner) or nil)
		if not ok then
			return { ok = false, err = err }
		end
		n.pvpLockUntil = Nations.now() + Config.PvpToggleCooldown
		n.shieldUntil = 0
	end
	local spots = formation(units, target)
	for i, u in units do
		drive(u, spots[i])
	end
	return { ok = true, count = #units }
end

local function onDeploy(player: Player, uids: any)
	local n = Nations.get(player)
	if not n then
		return { ok = false }
	end
	local units = collect(n, uids, function(u)
		return u.location == "home"
	end)
	local spots = formation(units, UnitService.stagingPos(n))
	for i, u in units do
		drive(u, spots[i])
	end
	if #units > 0 then
		Nations.notify(player, ("%d vehicles rolling out over the bridge to the front"):format(#units), "good")
	end
	return { ok = #units > 0, count = #units, err = #units == 0 and "No units at home" or nil }
end

local function onRecall(player: Player, uids: any)
	local n = Nations.get(player)
	if not n then
		return { ok = false }
	end
	local units = collect(n, uids, function(u)
		return u.location ~= "home"
	end)
	for _, u in units do
		drive(u, homePos(n))
	end
	return { ok = #units > 0, count = #units, err = #units == 0 and "No units on the battlefield" or nil }
end

-- Advance along the route; refresh where each unit is.
local function moveStep()
	for u in all do
		if u.model:GetAttribute("Moving") then
			local d = (u.align.Position - u.root.CFrame.Position) * Vector3.new(1, 0, 1)
			if d.Magnitude < 6 then
				local nextPoint = table.remove(u.path, 1)
				if nextPoint then
					setTarget(u, nextPoint)
				elseif d.Magnitude < 2 then
					u.model:SetAttribute("Moving", nil)
				end
			end
		end
		updateLocation(u)
	end
end

UnitService._moveStep = moveStep

---------------------------------------------------------------------------
-- Combat loop: battlefield fights, city raids and their defenders
---------------------------------------------------------------------------
local STEP = 0.5
local raidNotice: { [Nation]: number } = {}

-- Units fight when they're from different nations in the same theatre.
local function theatre(u: Unit): string
	local loc, idx = locate(u)
	if loc == "mainland" then
		return "mainland"
	end
	return "plot" .. tostring(idx)
end

local function raidAllowed(u: Unit, defender: Nation?): boolean
	return defender ~= nil and u.n.data.Pvp == true and defender.data.Pvp == true and not S.CombatService.isShielded(defender)
end

local function buildingTarget(u: Unit, defender: Nation, pos: Vector3): any?
	local best, bestD = nil, u.def.range
	for _, b in defender.buildings do
		if not b.damaged and not S.BuildService.isRoadDef(b.def) then
			local c = S.BuildService.worldCFrame(defender, b).Position
			local reach = math.min(b.def.size[1], b.def.size[2]) * Config.CellSize / 2
			local d = math.max(0, (Vector3.new(c.X, 0, c.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude - reach)
			if d <= bestD then
				best, bestD = b, d
			end
		end
	end
	return best
end

local function combatStep()
	local now = os.clock()
	local byTheatre: { [string]: { Unit } } = {}
	for u in all do
		local t = theatre(u)
		byTheatre[t] = byTheatre[t] or {}
		table.insert(byTheatre[t], u)
	end
	for t, units in byTheatre do
		local plotIdx = tonumber(string.match(t, "^plot(%d+)$"))
		local owner = plotIdx and S.PlotService.ownerAt(Grid.plotOrigin(plotIdx)) or nil
		local defender = owner and Nations.get(owner) or nil
		for _, u in units do
			if all[u] and u.def.dps > 0 then
				local pos = u.root.CFrame.Position
				-- in a city, only fight when the raid is legal
				local legal = t == "mainland" or (defender ~= nil and (u.n == defender or raidAllowed(u, defender)))
				local best, bestD = nil, u.def.range
				if legal then
					for _, other in units do
						if other.n ~= u.n and all[other] and (t == "mainland" or other.n == defender or u.n == defender) then
							local d = (other.root.CFrame.Position - pos).Magnitude
							if d <= bestD then
								best, bestD = other, d
							end
						end
					end
				end
				if best then
					if now - u.lastShot > 1 then
						u.lastShot = now
						Net.event("Effect"):FireAllClients("Shot", pos + Vector3.new(0, 2, 0), best.root.CFrame.Position, u.def.range > 150)
					end
					UnitService.damage(best, u.def.dps * STEP, u.n)
				elseif t == "mainland" then
					local point = S.ConquestService.enemyPointInRange(pos, u.def.range, u.n.userId)
					if point then
						if now - u.lastShot > 1.2 then
							u.lastShot = now
							Net.event("Effect"):FireAllClients("Shot", pos + Vector3.new(0, 2, 0), point.center + Vector3.new(0, 4, 0), u.def.range > 150)
						end
						S.ConquestService.damageGarrison(point, u.def.dps * STEP, u.n)
					end
				elseif defender and u.n ~= defender and raidAllowed(u, defender) then
					local b = buildingTarget(u, defender, pos)
					if b then
						if now - u.lastShot > 1.2 then
							u.lastShot = now
							Net.event("Effect"):FireAllClients("Shot", pos + Vector3.new(0, 2, 0), S.BuildService.worldCFrame(defender, b).Position + Vector3.new(0, 4, 0), u.def.range > 150)
						end
						local wasDamaged = b.damaged
						S.BuildService.damage(defender, b, u.def.dps * STEP * Config.RaidBuildingDamage)
						if b.damaged and not wasDamaged then
							local loot = math.floor(b.cost * Config.StrikeLootRate)
							u.n.data.Cash += loot
							Nations.notify(u.n.player, ("Your %s knocked out a %s%s"):format(u.def.name, b.def.name, loot > 0 and (" +" .. Format.cash(loot)) or ""), "good")
						end
						if (raidNotice[defender] or 0) < now then
							raidNotice[defender] = now + 30
							Nations.notify(defender.player, ("%s's vehicles are attacking your city!"):format(u.n.player.DisplayName), "bad")
						end
					end
				end
			end
		end
	end
end

-- exposed for automated tests
UnitService._combatStep = combatStep

function UnitService.init(services)
	S = services
	folder = Instance.new("Folder")
	folder.Name = "Units"
	folder.Parent = workspace
end

function UnitService.start()
	Net.handle("CommandUnits", onCommand, 6)
	Net.handle("DeployUnits", onDeploy, 3)
	Net.handle("RecallUnits", onRecall, 3)
	task.spawn(function()
		while true do
			task.wait(0.2)
			local ok, err = pcall(moveStep)
			if not ok then
				warn("[Units] move step failed: " .. tostring(err))
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(STEP)
			local ok, err = pcall(combatStep)
			if not ok then
				warn("[Units] combat step failed: " .. tostring(err))
			end
		end
	end)
end

return UnitService
