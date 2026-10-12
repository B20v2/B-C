--[[
	UnitService
	Everything you command on the map: vehicles, infantry squads (classic
	Roblox soldiers) and helicopters. Units are physics assemblies driven by
	AlignPosition / AlignOrientation (server-owned) so they glide smoothly on
	every client.

	  * Ground units really drive / march: out of your city, over your
	    bridge, across the central battlefield and, with PvP on, over a
	    rival's bridge into their city (waypoint routing through bridges).
	  * Helicopters fly straight to the target at altitude, then land.
	  * Transports carry squads (Humvees, IFVs, trucks, Black Hawks,
	    Chinooks), supply points (trucks + helicopters) and a slung light
	    vehicle (Chinook). Squads hide inside while carried.
	  * Units fight enemies of a class their weapons can hit (`vs`) in the
	    same theatre (the battlefield, or a city being raided), wear down
	    strategic points and enemy FOBs, and knock out buildings on raids.
	    A city's air defenses shoot at enemy helicopters overhead.
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
	location: string, -- "home" | "mainland" (battlefield, bridges, sea) | "raid"
	height: number,
	lastShot: number,
	path: { Vector3 },
	air: boolean,
	landed: boolean,
	arrive: string?, -- what to do on arrival: "unload" | "board:<uid>"
	carried: any?, -- the transport this unit rides in
	cargo: { any }, -- squads aboard
	slung: any?, -- vehicle under a Chinook
	sling: WeldConstraint?,
	supplies: number,
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

function UnitService.all(): { [Unit]: boolean }
	return all
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function posOf(u: Unit): Vector3
	return u.root.CFrame.Position
end

local function homePos(n: Nation, near: any?): Vector3
	local anchor: Vector3? = nil
	if near then
		anchor = S.BuildService.worldCFrame(n, near).Position
	else
		for _, b in n.buildings do
			if b.def.depot and Nations.isActive(b) then
				anchor = S.BuildService.worldCFrame(n, b).Position
				break
			end
		end
	end
	local base = anchor or Grid.yard(n.plotIndex)
	local rng = Random.new()
	local p = base + Vector3.new(rng:NextNumber(-18, 18), 0, rng:NextNumber(-18, 18))
	-- keep inside the island
	local half = Grid.PlotSize / 2 - 6
	local l = Grid.toLocal(n.plotIndex, p)
	return (Grid.plotCFrame(n.plotIndex) * CFrame.new(math.clamp(l.X, -half, half), 0, math.clamp(l.Z, -half, half))).Position
end

-- Where helicopters park at home: the first finished helipad, else the yard.
function UnitService.helipadPos(n: Nation): Vector3
	for _, b in n.buildings do
		if b.def.helipad and b.finishAt == nil then
			return S.BuildService.worldCFrame(n, b).Position
		end
	end
	return Grid.yard(n.plotIndex)
end

local function setTarget(u: Unit, pos: Vector3)
	local current = posOf(u)
	local y = u.height
	if u.air then
		y = Config.HeliAltitude
		u.landed = false
	end
	local target = Vector3.new(pos.X, y, pos.Z)
	u.align.Position = target
	local flatDir = Vector3.new(target.X - current.X, 0, target.Z - current.Z)
	if flatDir.Magnitude > 1 then
		u.orient.CFrame = CFrame.lookAt(Vector3.zero, flatDir.Unit)
	end
	u.model:SetAttribute("Moving", true)
end

local function cargoAttrs(u: Unit)
	u.model:SetAttribute("Cargo", #u.cargo > 0 and #u.cargo or nil)
	u.model:SetAttribute("Supplies", u.supplies > 0 and math.floor(u.supplies) or nil)
	u.model:SetAttribute("Slung", u.slung and u.slung.def.name or nil)
end

function UnitService.spawn(n: Nation, id: string, hp: number?, near: any?, uid: number?): Unit?
	local def = Units.get(id)
	if not def then
		return nil
	end
	local model = ModelBuilder.unit(def)
	local root = model.PrimaryPart :: BasePart
	local height = root.Size.Y / 2
	-- weld everything to the root (or to its rig part, e.g. boots to legs,
	-- blades to rotor hubs); jointed parts keep their Motor6D so clients can
	-- animate legs and rotors
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.CanCollide = false
			p.CanTouch = false
			if p ~= root then
				p.Massless = true
				if not p:GetAttribute("Jointed") then
					local to = root
					local name = p:GetAttribute("WeldTo") :: string?
					if name and p.Parent then
						to = (p.Parent:FindFirstChild(name) :: BasePart?) or root
					end
					local w = Instance.new("WeldConstraint")
					w.Part0 = to
					w.Part1 = p
					w.Parent = p
				end
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
	align.Responsiveness = def.class == "air" and 14 or 30
	align.Parent = root
	local orient = Instance.new("AlignOrientation")
	orient.Mode = Enum.OrientationAlignmentMode.OneAttachment
	orient.Attachment0 = att
	orient.MaxTorque = 1e7
	orient.Responsiveness = def.class == "air" and 8 or 18
	orient.Parent = root

	local unitUid = uid or n.nextUnitUid
	if unitUid >= n.nextUnitUid then
		n.nextUnitUid = unitUid + 1
	end
	model.Name = def.name
	model:SetAttribute("Unit", true)
	model:SetAttribute("UnitId", def.id)
	model:SetAttribute("Class", def.class)
	model:SetAttribute("Uid", unitUid)
	model:SetAttribute("OwnerId", n.userId)
	model:SetAttribute("OwnerName", n.player.DisplayName)
	model:SetAttribute("Hp", hp or def.hp)
	model:SetAttribute("MaxHp", def.hp)
	model:SetAttribute("Color", Config.NationColors[n.plotIndex] or Color3.new(1, 1, 1))
	if def.class == "infantry" then
		model:SetAttribute("Infantry", true)
	elseif def.class == "air" then
		model:SetAttribute("Rotors", true)
	end

	local pos = homePos(n, near)
	if def.class == "air" and not near then
		pos = UnitService.helipadPos(n)
	end
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
		air = def.class == "air",
		landed = true,
		arrive = nil,
		carried = nil,
		cargo = {},
		slung = nil,
		sling = nil,
		supplies = 0,
	}
	n.units[unitUid] = u
	all[u] = true
	return u
end

---------------------------------------------------------------------------
-- Cargo: squads inside, supplies, a slung vehicle
---------------------------------------------------------------------------
local function capacity(u: Unit, kind: string): number
	local c = u.def.cargo
	return c and (c[kind] or 0) or 0
end

function UnitService.freeSeats(u: Unit): number
	return capacity(u, "squads") - #u.cargo
end

-- Put a squad inside a transport (hidden until unloaded).
function UnitService.board(squad: Unit, transport: Unit): boolean
	if squad.def.class ~= "infantry" or squad.carried or UnitService.freeSeats(transport) <= 0 or squad.n ~= transport.n then
		return false
	end
	squad.carried = transport
	squad.path = {}
	squad.arrive = nil
	squad.model:SetAttribute("Moving", nil)
	squad.model:SetAttribute("Carried", transport.uid)
	squad.model.Parent = nil
	table.insert(transport.cargo, squad)
	cargoAttrs(transport)
	return true
end

-- Hang a light vehicle under a Chinook.
function UnitService.slingLoad(heli: Unit, vehicle: Unit): boolean
	if capacity(heli, "vehicles") <= 0 or heli.slung or not vehicle.def.light or vehicle.carried or vehicle.n ~= heli.n then
		return false
	end
	vehicle.carried = heli
	vehicle.path = {}
	vehicle.arrive = nil
	vehicle.align.Enabled = false
	vehicle.orient.Enabled = false
	vehicle.model:SetAttribute("Moving", nil)
	vehicle.model:SetAttribute("Carried", heli.uid)
	vehicle.model:PivotTo(heli.root.CFrame * CFrame.new(0, -heli.height - vehicle.height - 2.5, 0))
	for _, p in vehicle.model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Massless = true
		end
	end
	local weld = Instance.new("WeldConstraint")
	weld.Name = "Sling"
	weld.Part0 = heli.root
	weld.Part1 = vehicle.root
	weld.Parent = heli.root
	heli.slung = vehicle
	heli.sling = weld
	cargoAttrs(heli)
	return true
end

-- Everyone out: squads spread around the transport, slung vehicle set down.
function UnitService.unload(transport: Unit): number
	local base = flat(posOf(transport))
	local count = 0
	for i, squad in transport.cargo do
		local a = (i - 1) * (math.pi * 2 / math.max(1, #transport.cargo)) + 0.6
		local spot = base + Vector3.new(math.sin(a) * 9, 0, math.cos(a) * 9)
		squad.carried = nil
		squad.model:SetAttribute("Carried", nil)
		squad.model:PivotTo(CFrame.new(spot.X, squad.height, spot.Z))
		squad.align.Position = Vector3.new(spot.X, squad.height, spot.Z)
		squad.root.AssemblyLinearVelocity = Vector3.zero
		squad.model.Parent = folder
		count += 1
	end
	table.clear(transport.cargo)
	local v = transport.slung
	if v then
		if transport.sling then
			transport.sling:Destroy()
		end
		transport.slung = nil
		transport.sling = nil
		local spot = base + Vector3.new(0, 0, 14)
		v.carried = nil
		v.model:SetAttribute("Carried", nil)
		v.root.Massless = false
		v.model:PivotTo(CFrame.new(spot.X, v.height, spot.Z))
		v.align.Position = Vector3.new(spot.X, v.height, spot.Z)
		v.align.Enabled = true
		v.orient.Enabled = true
		v.root.AssemblyLinearVelocity = Vector3.zero
		count += 1
	end
	cargoAttrs(transport)
	return count
end

function UnitService.setSupplies(u: Unit, amount: number)
	u.supplies = math.max(0, amount)
	cargoAttrs(u)
end

function UnitService.remove(u: Unit, exploded: boolean?)
	all[u] = nil
	u.n.units[u.uid] = nil
	-- whoever rides inside goes down with it
	for _, squad in u.cargo do
		all[squad] = nil
		squad.n.units[squad.uid] = nil
		squad.model:Destroy()
	end
	table.clear(u.cargo)
	if u.slung then
		local v = u.slung
		u.slung = nil
		UnitService.remove(v, exploded)
	end
	if u.carried then
		local t = u.carried
		local idx = table.find(t.cargo, u)
		if idx then
			table.remove(t.cargo, idx)
		end
		if t.slung == u then
			t.slung = nil
			if t.sling then
				t.sling:Destroy()
				t.sling = nil
			end
		end
		cargoAttrs(t)
	end
	if exploded and u.model.Parent then
		Net.event("Effect"):FireAllClients("Explosion", posOf(u), 1)
	end
	u.model:Destroy()
end

-- Returns true if destroyed.
function UnitService.damage(u: Unit, amount: number, attacker: Nation?): boolean
	if not all[u] or u.carried then
		return false
	end
	u.hp -= amount
	u.model:SetAttribute("Hp", math.max(0, math.floor(u.hp)))
	if u.hp <= 0 then
		local lost = #u.cargo > 0 and (" with %d squads aboard"):format(#u.cargo) or ""
		Nations.notify(u.n.player, ("Your %s was destroyed%s"):format(u.def.name, lost), "bad")
		if attacker then
			attacker.data.Stats.Kills += 1
		end
		UnitService.remove(u, true)
		return true
	end
	return false
end

function UnitService.heal(u: Unit, amount: number): number
	local missing = u.def.hp - u.hp
	local healed = math.min(missing, amount)
	if healed > 0 then
		u.hp += healed
		u.model:SetAttribute("Hp", math.floor(u.hp))
	end
	return healed
end

function UnitService.unitsNear(pos: Vector3, radius: number, excludeUserId: number?): { Unit }
	local out = {}
	for u in all do
		if u.n.userId ~= excludeUserId and not u.carried then
			local p = posOf(u)
			local d = Vector2.new(p.X - pos.X, p.Z - pos.Z).Magnitude
			if d <= radius then
				table.insert(out, u)
			end
		end
	end
	return out
end

-- Ground units on the battlefield (helicopters and passengers can't capture).
function UnitService.mainlandUnits(): { Unit }
	local out = {}
	for u in all do
		if u.location == "mainland" and not u.carried and not u.air then
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
		if all[u] then
			UnitService.remove(u, false)
		end
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
UnitService.collect = collect

---------------------------------------------------------------------------
-- Routing: city -> yard -> gate -> bridge -> shore -> battlefield -> ...
---------------------------------------------------------------------------
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

-- Send a unit somewhere: helicopters fly straight, ground units take the bridges.
function UnitService.drive(u: Unit, target: Vector3, arrive: string?)
	if u.carried then
		return
	end
	u.arrive = arrive
	if u.air then
		u.path = { flat(target) }
	else
		u.path = UnitService.route(posOf(u), target)
	end
	local first = table.remove(u.path, 1)
	if first then
		setTarget(u, first)
	else
		u.model:SetAttribute("Moving", true)
		u.align.Position = Vector3.new(target.X, u.air and Config.HeliAltitude or u.height, target.Z)
	end
end
local drive = UnitService.drive

-- Theatre a unit is fighting in: "mainland" (battlefield + bridges), the
-- index of the island it's on, or nil when safe at home.
local function locate(u: Unit): (string, number?)
	local zone, idx = Grid.zoneAt(posOf(u))
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

function UnitService.formation(units: { Unit }, target: Vector3): { Vector3 }
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
local formation = UnitService.formation

local function onCommand(player: Player, uids: any, target: any)
	local n = Nations.get(player)
	if not n or typeof(target) ~= "Vector3" or target.X ~= target.X or math.abs(target.X) > 1e5 or math.abs(target.Z) > 1e5 then
		return { ok = false, err = "Invalid request" }
	end
	local units = collect(n, uids, function(u)
		return u.carried == nil
	end)
	if #units == 0 then
		return { ok = false, err = "Select units first" }
	end
	local zone, idx = Grid.zoneAt(target)
	local onlyAir = true
	for _, u in units do
		if not u.air then
			onlyAir = false
		end
	end
	if zone == "sea" and not onlyAir then
		return { ok = false, err = "Vehicles can't drive on water - helicopters can fly there" }
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
		return u.location == "home" and u.carried == nil
	end)
	local spots = formation(units, UnitService.stagingPos(n))
	for i, u in units do
		drive(u, spots[i])
	end
	if #units > 0 then
		Nations.notify(player, ("%d units rolling out over the bridge to the front"):format(#units), "good")
	end
	return { ok = #units > 0, count = #units, err = #units == 0 and "No units at home" or nil }
end

local function onRecall(player: Player, uids: any)
	local n = Nations.get(player)
	if not n then
		return { ok = false }
	end
	local units = collect(n, uids, function(u)
		return u.location ~= "home" and u.carried == nil
	end)
	for _, u in units do
		drive(u, u.air and UnitService.helipadPos(n) or homePos(n))
	end
	return { ok = #units > 0, count = #units, err = #units == 0 and "No units on the battlefield" or nil }
end

-- Arrival actions (landing + unloading, squads climbing aboard).
local function arrived(u: Unit)
	local action = u.arrive
	u.arrive = nil
	if not action then
		return
	end
	if action == "unload" then
		local count = UnitService.unload(u)
		local delivered = S.FobService.deliver(u)
		if count > 0 or delivered > 0 then
			Nations.notify(u.n.player, ("%s unloaded%s%s"):format(
				u.def.name,
				count > 0 and (" %d units"):format(count) or "",
				delivered > 0 and (" and %d supplies"):format(delivered) or ""
			), "good")
		end
	else
		local uid = tonumber(string.match(action, "^board:(%d+)$"))
		local t = uid and u.n.units[uid]
		if t and all[t] and (flat(posOf(t)) - flat(posOf(u))).Magnitude <= Config.BoardRange then
			UnitService.board(u, t)
		end
	end
end

-- Advance along routes, land helicopters, refresh where each unit is.
local function moveStep()
	for u in all do
		if not u.carried then
			if u.model:GetAttribute("Moving") then
				local d = (u.align.Position - posOf(u)) * Vector3.new(1, 0, 1)
				if d.Magnitude < 6 then
					local nextPoint = table.remove(u.path, 1)
					if nextPoint then
						setTarget(u, nextPoint)
					elseif u.air and not u.landed then
						-- over the destination: come down
						u.landed = true
						u.align.Position = Vector3.new(u.align.Position.X, u.height, u.align.Position.Z)
					elseif d.Magnitude < 2 and (not u.air or math.abs(posOf(u).Y - u.height) < 2) then
						u.model:SetAttribute("Moving", nil)
						arrived(u)
					end
				end
			end
			updateLocation(u)
		end
	end
end

UnitService._moveStep = moveStep

-- Land wherever we are now and run the arrival action.
function UnitService.landNow(u: Unit, action: string?)
	local p = posOf(u)
	u.path = {}
	u.arrive = action
	u.landed = true
	u.align.Position = Vector3.new(p.X, u.height, p.Z)
	u.model:SetAttribute("Moving", true)
end

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

local function shot(from: Vector3, to: Vector3, long: boolean)
	Net.event("Effect"):FireAllClients("Shot", from + Vector3.new(0, 2, 0), to, long)
end

-- Damage multiplier of `u`'s weapons against `target`'s class.
local function versus(u: Unit, target: Unit): number
	return u.def.vs[target.def.class] or 0
end
UnitService.versus = versus

local function combatStep()
	local now = os.clock()
	local byTheatre: { [string]: { Unit } } = {}
	for u in all do
		if not u.carried then
			local t = theatre(u)
			byTheatre[t] = byTheatre[t] or {}
			table.insert(byTheatre[t], u)
		end
	end
	for t, units in byTheatre do
		local plotIdx = tonumber(string.match(t, "^plot(%d+)$"))
		local owner = plotIdx and S.PlotService.ownerAt(Grid.plotOrigin(plotIdx)) or nil
		local defender = owner and Nations.get(owner) or nil
		for _, u in units do
			if all[u] and u.def.dps > 0 then
				local pos = posOf(u)
				-- in a city, only fight when the raid is legal
				local legal = t == "mainland" or (defender ~= nil and (u.n == defender or raidAllowed(u, defender)))
				local best, bestD = nil, u.def.range
				if legal then
					for _, other in units do
						if other.n ~= u.n and all[other] and versus(u, other) > 0 and (t == "mainland" or other.n == defender or u.n == defender) then
							-- helicopters are engaged by ground distance (anti-air reaches up)
							local d = other.air and (flat(posOf(other)) - flat(pos)).Magnitude or (posOf(other) - pos).Magnitude
							if d <= bestD then
								best, bestD = other, d
							end
						end
					end
				end
				if best then
					if now - u.lastShot > 1 then
						u.lastShot = now
						shot(pos, posOf(best), u.def.range > 150)
					end
					UnitService.damage(best, u.def.dps * STEP * versus(u, best), u.n)
				elseif t == "mainland" and not u.air then
					local point = S.ConquestService.enemyPointInRange(pos, u.def.range, u.n.userId)
					local fob = not point and S.FobService.enemyFobInRange(pos, u.def.range, u.n) or nil
					if point then
						if now - u.lastShot > 1.2 then
							u.lastShot = now
							shot(pos, point.center + Vector3.new(0, 4, 0), u.def.range > 150)
						end
						S.ConquestService.damageGarrison(point, u.def.dps * STEP, u.n)
					elseif fob then
						if now - u.lastShot > 1.2 then
							u.lastShot = now
							shot(pos, fob.pos + Vector3.new(0, 3, 0), u.def.range > 150)
						end
						S.FobService.damage(fob, u.def.dps * STEP, u.n)
					end
				elseif defender and u.n ~= defender and raidAllowed(u, defender) then
					local b = buildingTarget(u, defender, pos)
					if b then
						if now - u.lastShot > 1.2 then
							u.lastShot = now
							shot(pos, S.BuildService.worldCFrame(defender, b).Position + Vector3.new(0, 4, 0), u.def.range > 150)
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
							Nations.notify(defender.player, ("%s's forces are attacking your city!"):format(u.n.player.DisplayName), "bad")
						end
					end
				end
			end
		end
		-- a city's air defenses fire at enemy helicopters overhead
		if defender and plotIdx then
			for _, u in units do
				if all[u] and u.air and u.n ~= defender and raidAllowed(u, defender) then
					for _, b in defender.buildings do
						local ad = b.def.airDefense
						if ad and Nations.isActive(b) then
							local c = S.BuildService.worldCFrame(defender, b).Position
							if (flat(c) - flat(posOf(u))).Magnitude <= ad.range then
								if math.random() < 0.3 then
									shot(c + Vector3.new(0, 4, 0), posOf(u), true)
								end
								UnitService.damage(u, ad.chance * 30 * STEP, defender)
								break
							end
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
