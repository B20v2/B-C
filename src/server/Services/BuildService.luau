--[[
	BuildService
	Server-authoritative free-form placement. Buildings sit anywhere on your
	island at any angle (island-local studs + yaw), roads are drawn as
	segments of any length and direction, and every request is validated
	against footprint overlap (Footprint SAT + spatial hash), your land,
	cash, research, passes and limits. Owns building runtime objects, their
	models, construction timers, road access, undo, move and repair.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Grid = require(Shared.Util.Grid)
local Footprint = require(Shared.Util.Footprint)
local Unlocks = require(Shared.Util.Unlocks)
local Buildings = require(Shared.Catalog.Buildings)
local ModelBuilder = require(Shared.ModelBuilder)
local Net = require(Shared.Net)
local Nations = require(script.Parent.Nations)

type Nation = Nations.Nation
type BRuntime = Nations.BRuntime

local BuildService = {}
local S: { [string]: any }

local HALF = Grid.PlotSize / 2 - 0.5 -- buildable half-extent on an island
local ROAD_REACH = 3 -- a building within this many studs of a road is connected

---------------------------------------------------------------------------
-- Footprints
---------------------------------------------------------------------------
local function isRoadDef(def): boolean
	return def.id == "road" or def.id == "plaza"
end
BuildService.isRoadDef = isRoadDef

-- Segment roads stretch; everything else uses its catalog footprint.
local function isSegment(def): boolean
	return def.id == "road"
end

local function rectFor(def, x: number, z: number, angle: number, len: number?): Footprint.Rect
	local w, d = Footprint.size(def, len)
	return Footprint.rect(x, z, w, d, angle)
end

local function rectOf(b: BRuntime): Footprint.Rect
	return rectFor(b.def, b.x, b.z, b.r, b.len)
end

-- Price of a placement (roads are charged per tile of length).
local function costFor(def, len: number?): number
	if len and isSegment(def) then
		return def.cost * math.max(1, math.ceil(len / (def.size[2] * Config.CellSize) - 0.01))
	end
	return def.cost
end

local function finite(v: any): boolean
	return typeof(v) == "number" and v == v and math.abs(v) < 1e4
end

local function cleanAngle(a: any): number
	if not finite(a) then
		return 0
	end
	return (math.floor(a * 2 + 0.5) / 2) % 360
end

local function cleanPos(v: number): number
	return math.floor(v * 20 + 0.5) / 20
end

function BuildService.canPlace(n: Nation, def, x: number, z: number, angle: number, len: number?, ignoreUid: number?): (boolean, string?)
	if not finite(x) or not finite(z) or not finite(angle) then
		return false, "Invalid position"
	end
	local rect = rectFor(def, x, z, angle, len)
	if not Footprint.inside(rect, HALF) then
		return false, "Outside your land"
	end
	local ground = isRoadDef(def)
	-- a road's round end caps count against buildings
	local mine = isSegment(def) and Footprint.capped(rect) or rect
	for uid in Footprint.hashQuery(n.grid, mine) do
		local other = n.buildings[uid]
		if other and uid ~= ignoreUid and not (ground and isRoadDef(other.def)) then
			local theirs = rectOf(other)
			if isSegment(other.def) then
				theirs = Footprint.capped(theirs)
			end
			if Footprint.overlaps(mine, theirs) then
				return false, (isRoadDef(other.def) and not ground) and "Can't build on a road" or "Space is taken"
			end
		end
	end
	return true, nil
end

local function connectedAt(n: Nation, b: BRuntime): boolean
	if not b.def.needsRoad or isRoadDef(b.def) then
		return true
	end
	local reach = Footprint.grow(rectOf(b), ROAD_REACH)
	for uid in Footprint.hashQuery(n.grid, reach) do
		local other = n.buildings[uid]
		if other and other ~= b and isRoadDef(other.def) and other.finishAt == nil then
			if Footprint.overlaps(reach, rectOf(other), 0) then
				return true
			end
		end
	end
	return false
end

function BuildService.recomputeRoads(n: Nation)
	for _, b in n.buildings do
		b.connected = connectedAt(n, b)
		if b.model then
			b.model:SetAttribute("Connected", b.connected)
		end
	end
end

---------------------------------------------------------------------------
-- Models
---------------------------------------------------------------------------
local function applyBillboard(n: Nation, b: BRuntime)
	if not b.def.billboard or not b.model then
		return
	end
	local text = n.data.Billboard ~= "" and n.data.Billboard or (n.player.DisplayName .. " WAS HERE")
	for _, d in b.model:GetDescendants() do
		if d:IsA("TextLabel") and d.Name == "Message" then
			d.Text = text
		end
	end
end

function BuildService.worldCFrame(n: Nation, b: BRuntime): CFrame
	return Grid.toWorld(n.plotIndex, b.x, b.z, b.r)
end

local function spawnModel(n: Nation, b: BRuntime)
	if b.model then
		b.model:Destroy()
	end
	local model
	if isSegment(b.def) and b.len then
		model = ModelBuilder.roadSegment(b.def.size[1] * Config.CellSize, b.len, b.uid)
	else
		model = ModelBuilder.building(b.def)
	end
	model.Name = tostring(b.uid)
	model:PivotTo(BuildService.worldCFrame(n, b))
	-- placement data for the client ghost / move tool
	model:SetAttribute("PX", b.x)
	model:SetAttribute("PZ", b.z)
	model:SetAttribute("Angle", b.r)
	model:SetAttribute("Len", b.len)
	model:SetAttribute("Uid", b.uid)
	model:SetAttribute("BuildingId", b.id)
	model:SetAttribute("OwnerId", n.userId)
	model:SetAttribute("MaxHp", b.def.hp)
	model:SetAttribute("Hp", b.hp)
	model:SetAttribute("Connected", b.connected)
	if b.finishAt then
		model:SetAttribute("BuildStart", b.startAt or Nations.now())
		model:SetAttribute("FinishAt", b.finishAt)
		model:SetAttribute("Status", "Under Construction")
		ModelBuilder.setConstruction(model, true)
	end
	if b.damaged then
		model:SetAttribute("Damaged", true)
		ModelBuilder.setDamaged(model, true)
	end
	model.Parent = n.folder
	b.model = model
	applyBillboard(n, b)
	if b.def.farm then
		S.FarmService.attach(n, b)
	end
end

---------------------------------------------------------------------------
-- Runtime creation
---------------------------------------------------------------------------
local function newRuntime(n: Nation, def, x: number, z: number, r: number, len: number?, uid: number?): BRuntime
	local id = uid
	if not id then
		id = n.data.NextUid
		n.data.NextUid += 1
	end
	local b: BRuntime = {
		uid = id :: number,
		id = def.id,
		def = def,
		x = x,
		z = z,
		r = r,
		len = len,
		cost = costFor(def, len),
		model = nil,
		finishAt = nil,
		startAt = nil,
		damaged = false,
		hp = def.hp,
		oil = 0,
		fuel = 0,
		incoming = 0,
		dest = 0,
		trucks = {},
		queue = {},
		reloadUntil = 0,
		connected = true,
		eff = 1,
		status = "",
	}
	if def.refine then
		for _ = 1, def.refine.trucks do
			table.insert(b.trucks, { state = "idle", target = 0, amount = 0, arriveAt = 0, returnAt = 0 })
		end
	end
	return b
end

local function insert(n: Nation, b: BRuntime)
	n.buildings[b.uid] = b
	Footprint.hashAdd(n.grid, b.uid, rectOf(b))
end

local function unindex(n: Nation, b: BRuntime)
	Footprint.hashRemove(n.grid, b.uid, rectOf(b))
end

local function countBuildings(n: Nation): number
	local c = 0
	for _ in n.buildings do
		c += 1
	end
	return c
end

function BuildService.access(n: Nation): Unlocks.Access
	return { researched = n.data.Researched, passes = n.passes }
end

-- Core placement used by requests and undo.
local function placeInternal(n: Nation, def, x: number, z: number, r: number, len: number?, charge: boolean): (boolean, string?, BRuntime?)
	local ok, err = BuildService.canPlace(n, def, x, z, r, len)
	if not ok then
		return false, err, nil
	end
	if def.max and Nations.countAll(n, def.id) >= def.max then
		return false, ("Limit reached (max %d)"):format(def.max), nil
	end
	if countBuildings(n) >= Config.MaxBuildings then
		return false, ("Your nation is at the %d building limit"):format(Config.MaxBuildings), nil
	end
	local cost = costFor(def, len)
	if charge then
		if n.data.Cash < cost then
			return false, "Not enough cash", nil
		end
		n.data.Cash -= cost
	end
	local b = newRuntime(n, def, x, z, r, len)
	local time = def.buildTime / Nations.speed(n)
	if time > 0 then
		b.startAt = Nations.now()
		b.finishAt = b.startAt + time
	end
	insert(n, b)
	b.connected = connectedAt(n, b)
	spawnModel(n, b)
	if isRoadDef(def) and not b.finishAt then
		BuildService.recomputeRoads(n)
	end
	return true, nil, b
end

local function pushUndo(n: Nation, action: { [string]: any })
	action.t = Nations.now()
	table.insert(n.undo, action)
	if #n.undo > 25 then
		table.remove(n.undo, 1)
	end
end

local function removeInternal(n: Nation, b: BRuntime)
	unindex(n, b)
	n.buildings[b.uid] = nil
	if b.model then
		b.model:Destroy()
		b.model = nil
	end
	-- refund queued production
	for _, item in b.queue do
		local cat = item.kind == "unit" and S.ProductionService.unitDef(item.id) or S.ProductionService.weaponDef(item.id)
		if cat then
			n.data.Cash += cat.cost
		end
	end
	if isRoadDef(b.def) then
		BuildService.recomputeRoads(n)
	end
end

function BuildService.completeConstruction(n: Nation, b: BRuntime)
	b.finishAt = nil
	b.startAt = nil
	if b.model then
		ModelBuilder.setConstruction(b.model, false)
		b.model:SetAttribute("FinishAt", nil)
		b.model:SetAttribute("BuildStart", nil)
	end
	if isRoadDef(b.def) then
		BuildService.recomputeRoads(n)
	end
	Net.event("Effect"):FireClient(n.player, "BuildDone", b.model and b.model:GetPivot().Position or n.origin, b.def.name)
end

function BuildService.setDamaged(n: Nation, b: BRuntime, on: boolean)
	b.damaged = on
	if on then
		b.hp = 0
	else
		b.hp = b.def.hp
	end
	if b.model then
		b.model:SetAttribute("Damaged", on or nil)
		b.model:SetAttribute("Hp", b.hp)
		ModelBuilder.setDamaged(b.model, on)
	end
	local _ = n
end

-- Apply strike damage; returns damage actually dealt.
function BuildService.damage(n: Nation, b: BRuntime, amount: number): number
	if b.damaged or isRoadDef(b.def) then
		return 0
	end
	local dealt = math.min(b.hp, amount)
	b.hp -= dealt
	if b.model then
		b.model:SetAttribute("Hp", b.hp)
	end
	if b.hp <= 0 then
		BuildService.setDamaged(n, b, true)
		-- stored resources are lost when a building is knocked out
		b.fuel = 0
		b.oil = 0
	end
	return dealt
end

---------------------------------------------------------------------------
-- Load / save
---------------------------------------------------------------------------
-- Old saves stored grid cells (min corner on a 100-cell plot) and quarter
-- turns; convert them to island-local studs + degrees.
local OLD_CELLS = 100

local function migrate(def, s): (number, number, number)
	local r = s.r or 0
	local fw, fd = def.size[1], def.size[2]
	if r % 2 == 1 then
		fw, fd = fd, fw
	end
	local cell = Config.CellSize
	return (s.x + fw / 2 - OLD_CELLS / 2) * cell, (s.z + fd / 2 - OLD_CELLS / 2) * cell, (r % 4) * 90
end

function BuildService.loadNation(n: Nation)
	for _, s in n.data.Buildings do
		local def = Buildings.get(s.id)
		if def and finite(s.x) and finite(s.z) then
			local x, z, r, len
			if s.a ~= nil then
				x, z, r, len = s.x, s.z, cleanAngle(s.a), s.L
			else
				x, z, r = migrate(def, s)
				len = isSegment(def) and def.size[2] * Config.CellSize or nil
			end
			if BuildService.canPlace(n, def, x, z, r, len) then
				local b = newRuntime(n, def, x, z, r, len, s.u)
				b.finishAt = s.f
				b.startAt = s.st
				b.damaged = s.d == true
				b.hp = b.damaged and 0 or math.clamp(s.hp or def.hp, 1, def.hp)
				b.oil = s.o or 0
				b.fuel = s.fu or 0
				b.dest = s.de or 0
				if def.farm then
					b.crop = type(s.cr) == "string" and s.cr or nil
					b.growth = type(s.gr) == "number" and math.clamp(s.gr, 0, 1) or 0
					b.auto = s.ar == true
					b.lastCrop = type(s.lc) == "string" and s.lc or nil
				end
				if s.q then
					for _, q in s.q do
						table.insert(b.queue, { id = q.id, kind = q.k, progress = q.p or 0, started = q.s == true })
					end
				end
				insert(n, b)
				if (s.u or 0) >= n.data.NextUid then
					n.data.NextUid = s.u + 1
				end
			end
		end
	end
	BuildService.recomputeRoads(n)
	-- spawn models gradually so a huge city doesn't hitch the server
	local count = 0
	for _, b in n.buildings do
		if not n.player.Parent then
			return
		end
		spawnModel(n, b)
		count += 1
		if count % 40 == 0 then
			task.wait()
		end
	end
end

function BuildService.serialize(n: Nation)
	local out = {}
	for _, b in n.buildings do
		local q = nil
		if #b.queue > 0 then
			q = {}
			for _, item in b.queue do
				table.insert(q, { id = item.id, k = item.kind, p = item.progress, s = item.started })
			end
		end
		local fuel = b.fuel
		-- fuel on the road is returned to the refinery when saving
		for _, t in b.trucks do
			if t.state ~= "idle" and t.state ~= "back" then
				fuel += t.amount
			end
		end
		table.insert(out, {
			u = b.uid,
			id = b.id,
			x = b.x,
			z = b.z,
			a = b.r,
			L = b.len,
			cr = b.crop,
			gr = b.crop and math.floor((b.growth or 0) * 1000) / 1000 or nil,
			ar = b.auto or nil,
			lc = b.lastCrop,
			f = b.finishAt,
			st = b.startAt,
			d = b.damaged or nil,
			hp = (b.hp < b.def.hp and not b.damaged) and math.floor(b.hp) or nil,
			o = b.oil > 0 and math.floor(b.oil) or nil,
			fu = fuel > 0 and math.floor(fuel) or nil,
			de = b.dest ~= 0 and b.dest or nil,
			q = q,
		})
	end
	n.data.Buildings = out
end

---------------------------------------------------------------------------
-- Tick (called by the simulation loop)
---------------------------------------------------------------------------
function BuildService.tick(n: Nation, now: number)
	for _, b in n.buildings do
		if b.finishAt and now >= b.finishAt then
			BuildService.completeConstruction(n, b)
		end
	end
end

function BuildService.finishAll(n: Nation)
	for _, b in n.buildings do
		if b.finishAt then
			BuildService.completeConstruction(n, b)
		end
	end
end

function BuildService.repairAll(n: Nation, free: boolean): (number, number)
	local count, cost = 0, 0
	for _, b in n.buildings do
		if b.damaged then
			local price = math.floor(b.cost * Config.RepairCostRate)
			if free or n.data.Cash >= price then
				if not free then
					n.data.Cash -= price
					cost += price
				end
				BuildService.setDamaged(n, b, false)
				count += 1
			end
		end
	end
	return count, cost
end

---------------------------------------------------------------------------
-- Requests
---------------------------------------------------------------------------
local function nationOf(player: Player): Nation?
	local n = Nations.get(player)
	if n and n.ready then
		return n
	end
	return nil
end

local function requireDef(n: Nation, id: any): (any, string?)
	if typeof(id) ~= "string" then
		return nil, "Unknown building"
	end
	local def = Buildings.get(id)
	if not def then
		return nil, "Unknown building"
	end
	local ok, reason = Unlocks.check(def, BuildService.access(n))
	if not ok then
		return nil, reason
	end
	return def, nil
end

-- x, z: island-local studs (footprint centre); a: yaw in degrees.
local function onPlace(player: Player, id: any, x: any, z: any, a: any)
	local n = nationOf(player)
	if not n then
		return { ok = false, err = "Loading..." }
	end
	local def, err = requireDef(n, id)
	if not def then
		return { ok = false, err = err }
	end
	if not finite(x) or not finite(z) then
		return { ok = false, err = "Invalid position" }
	end
	local len = isSegment(def) and def.size[2] * Config.CellSize or nil
	local ok, perr, b = placeInternal(n, def, cleanPos(x), cleanPos(z), cleanAngle(a), len, true)
	if not ok or not b then
		return { ok = false, err = perr }
	end
	pushUndo(n, { kind = "place", uid = b.uid })
	S.StateService.push(n)
	return { ok = true, uid = b.uid }
end

-- A row of the same building (drag tool): spots = { {x, z}, ... }.
local function onPlaceMany(player: Player, id: any, spots: any, a: any)
	local n = nationOf(player)
	if not n then
		return { ok = false, err = "Loading..." }
	end
	local def, err = requireDef(n, id)
	if not def then
		return { ok = false, err = err }
	end
	if typeof(spots) ~= "table" then
		return { ok = false, err = "Invalid request" }
	end
	local angle = cleanAngle(a)
	local len = isSegment(def) and def.size[2] * Config.CellSize or nil
	local placed = 0
	local lastErr: string? = nil
	local uids = {}
	for i, spot in spots do
		if i > 120 then
			break
		end
		if typeof(spot) == "table" and finite(spot[1]) and finite(spot[2]) then
			local ok, perr, b = placeInternal(n, def, cleanPos(spot[1]), cleanPos(spot[2]), angle, len, true)
			if ok and b then
				placed += 1
				table.insert(uids, b.uid)
			else
				lastErr = perr
				if perr == "Not enough cash" then
					break
				end
			end
		end
	end
	if placed > 0 then
		pushUndo(n, { kind = "placeMany", uids = uids })
		BuildService.recomputeRoads(n)
		S.StateService.push(n)
	end
	return { ok = placed > 0, placed = placed, err = placed == 0 and lastErr or nil }
end

-- Draw a road from A to B (island-local studs), any length and direction.
local function onPlaceRoad(player: Player, id: any, ax: any, az: any, bx: any, bz: any)
	local n = nationOf(player)
	if not n then
		return { ok = false, err = "Loading..." }
	end
	local def, err = requireDef(n, id)
	if not def then
		return { ok = false, err = err }
	end
	if not isSegment(def) then
		return { ok = false, err = "Only roads can be drawn" }
	end
	if not (finite(ax) and finite(az) and finite(bx) and finite(bz)) then
		return { ok = false, err = "Invalid position" }
	end
	local x, z, angle, len = Footprint.segment(ax, az, bx, bz)
	if len < 2 then
		return { ok = false, err = "Drag further to draw a road" }
	end
	if len > Config.RoadMaxLength then
		return { ok = false, err = ("Roads are drawn in pieces up to %d studs"):format(Config.RoadMaxLength) }
	end
	local ok, perr, b = placeInternal(n, def, cleanPos(x), cleanPos(z), cleanAngle(angle), math.floor(len * 10 + 0.5) / 10, true)
	if not ok or not b then
		return { ok = false, err = perr }
	end
	pushUndo(n, { kind = "place", uid = b.uid })
	S.StateService.push(n)
	return { ok = true, uid = b.uid, cost = b.cost }
end

local function refundFor(b: BRuntime): number
	if b.finishAt then
		return b.cost
	elseif b.damaged then
		return math.floor(b.cost * Config.SellRefund * 0.5)
	end
	return math.floor(b.cost * Config.SellRefund)
end

local function onDelete(player: Player, uid: any)
	local n = nationOf(player)
	if not n or typeof(uid) ~= "number" then
		return { ok = false, err = "Invalid request" }
	end
	local b = n.buildings[uid]
	if not b then
		return { ok = false, err = "Building not found" }
	end
	local refund = refundFor(b)
	n.data.Cash += refund
	pushUndo(n, { kind = "delete", id = b.id, x = b.x, z = b.z, r = b.r, len = b.len, refund = refund, wasBuilt = b.finishAt == nil })
	removeInternal(n, b)
	S.StateService.push(n)
	return { ok = true, refund = refund }
end

local function relocate(n: Nation, b: BRuntime, x: number, z: number, r: number)
	unindex(n, b)
	b.x, b.z, b.r = x, z, r
	insert(n, b)
	if b.model then
		b.model:PivotTo(BuildService.worldCFrame(n, b))
		b.model:SetAttribute("PX", b.x)
		b.model:SetAttribute("PZ", b.z)
		b.model:SetAttribute("Angle", b.r)
	end
	BuildService.recomputeRoads(n)
end

local function onMove(player: Player, uid: any, x: any, z: any, a: any)
	local n = nationOf(player)
	if not n or typeof(uid) ~= "number" or not finite(x) or not finite(z) then
		return { ok = false, err = "Invalid request" }
	end
	local b = n.buildings[uid]
	if not b then
		return { ok = false, err = "Building not found" }
	end
	local nx, nz, nr = cleanPos(x), cleanPos(z), cleanAngle(a)
	local ok, err = BuildService.canPlace(n, b.def, nx, nz, nr, b.len, b.uid)
	if not ok then
		return { ok = false, err = err }
	end
	pushUndo(n, { kind = "move", uid = b.uid, x = b.x, z = b.z, r = b.r })
	relocate(n, b, nx, nz, nr)
	return { ok = true }
end

local function onUndo(player: Player)
	local n = nationOf(player)
	if not n then
		return { ok = false }
	end
	local action = table.remove(n.undo)
	if not action then
		return { ok = false, err = "Nothing to undo" }
	end
	if Nations.now() - action.t > Config.UndoWindow then
		table.clear(n.undo)
		return { ok = false, err = "Too late to undo" }
	end
	if action.kind == "place" or action.kind == "placeMany" then
		local uids = action.uids or { action.uid }
		for _, uid in uids do
			local b = n.buildings[uid]
			if b then
				n.data.Cash += b.cost
				removeInternal(n, b)
			end
		end
	elseif action.kind == "delete" then
		local def = Buildings.get(action.id)
		if def then
			if n.data.Cash < action.refund then
				return { ok = false, err = "Not enough cash" }
			end
			local ok, err, b = placeInternal(n, def, action.x, action.z, action.r, action.len, false)
			if not ok or not b then
				return { ok = false, err = err }
			end
			n.data.Cash -= action.refund
			if action.wasBuilt then
				-- it was finished before: put it back finished
				BuildService.completeConstruction(n, b)
			end
		end
	elseif action.kind == "move" then
		local b = n.buildings[action.uid]
		if b and BuildService.canPlace(n, b.def, action.x, action.z, action.r, b.len, b.uid) then
			relocate(n, b, action.x, action.z, action.r)
		end
	end
	S.StateService.push(n)
	return { ok = true }
end

local function onRepair(player: Player, uid: any)
	local n = nationOf(player)
	if not n or typeof(uid) ~= "number" then
		return { ok = false, err = "Invalid request" }
	end
	local b = n.buildings[uid]
	if not b or not b.damaged then
		return { ok = false, err = "Nothing to repair" }
	end
	local price = math.floor(b.cost * Config.RepairCostRate)
	if n.data.Cash < price then
		return { ok = false, err = "Not enough cash" }
	end
	n.data.Cash -= price
	BuildService.setDamaged(n, b, false)
	S.StateService.push(n)
	return { ok = true }
end

local function onRepairAll(player: Player)
	local n = nationOf(player)
	if not n then
		return { ok = false }
	end
	local count, cost = BuildService.repairAll(n, false)
	S.StateService.push(n)
	if count == 0 then
		return { ok = false, err = "Nothing to repair (or not enough cash)" }
	end
	return { ok = true, count = count, cost = cost }
end

local function onSetBillboard(player: Player, text: any)
	local n = nationOf(player)
	if not n or typeof(text) ~= "string" then
		return { ok = false }
	end
	if not n.passes.Billboard then
		return { ok = false, err = "Requires the Billboard pass" }
	end
	text = string.sub(text, 1, 40)
	local ok, filtered = pcall(function()
		local result = TextService:FilterStringAsync(text, player.UserId, Enum.TextFilterContext.PublicChat)
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not ok then
		return { ok = false, err = "Could not filter text, try again" }
	end
	n.data.Billboard = filtered
	for _, b in n.buildings do
		applyBillboard(n, b)
	end
	return { ok = true, text = filtered }
end

function BuildService.init(services)
	S = services
end

function BuildService.start()
	Net.handle("PlaceBuilding", onPlace, 12)
	Net.handle("PlaceMany", onPlaceMany, 4)
	Net.handle("PlaceRoad", onPlaceRoad, 12)
	Net.handle("DeleteBuilding", onDelete, 12)
	Net.handle("MoveBuilding", onMove, 8)
	Net.handle("Undo", onUndo, 6)
	Net.handle("RepairBuilding", onRepair, 8)
	Net.handle("RepairAll", onRepairAll, 2)
	Net.handle("SetBillboard", onSetBillboard, 1)
end

return BuildService
