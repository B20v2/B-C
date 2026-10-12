--[[
	BuildService
	Server-authoritative placement: validates every request against the grid,
	cash, research, passes and limits. Owns building runtime objects, their
	models, construction timers, road connectivity, undo, move and repair.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Grid = require(Shared.Util.Grid)
local Unlocks = require(Shared.Util.Unlocks)
local Buildings = require(Shared.Catalog.Buildings)
local ModelBuilder = require(Shared.ModelBuilder)
local Net = require(Shared.Net)
local Nations = require(script.Parent.Nations)

type Nation = Nations.Nation
type BRuntime = Nations.BRuntime

local BuildService = {}
local S: { [string]: any }

---------------------------------------------------------------------------
-- Grid helpers
---------------------------------------------------------------------------
local function footprintOf(def, r: number): (number, number)
	return Grid.footprint(def.size[1], def.size[2], r)
end

local function cellsOf(def, x: number, z: number, r: number): { number }
	local fw, fd = footprintOf(def, r)
	local out = {}
	for cx = x, x + fw - 1 do
		for cz = z, z + fd - 1 do
			table.insert(out, Grid.key(cx, cz))
		end
	end
	return out
end

local function isRoadDef(def): boolean
	return def.id == "road" or def.id == "plaza"
end

function BuildService.canPlace(n: Nation, def, x: number, z: number, r: number, ignoreUid: number?): (boolean, string?)
	if typeof(x) ~= "number" or typeof(z) ~= "number" or x ~= x or z ~= z then
		return false, "Invalid position"
	end
	local fw, fd = footprintOf(def, r)
	if not Grid.inBounds(x, z, fw, fd) then
		return false, "Outside your land"
	end
	for _, key in cellsOf(def, x, z, r) do
		local occ = n.grid[key]
		if occ and occ ~= ignoreUid then
			return false, "Space is taken"
		end
	end
	return true, nil
end

local function connectedAt(n: Nation, b: BRuntime): boolean
	if not b.def.needsRoad or isRoadDef(b.def) then
		return true
	end
	local fw, fd = footprintOf(b.def, b.r)
	local function isRoad(cx: number, cz: number): boolean
		if cx < 0 or cz < 0 or cx >= Grid.PlotCells or cz >= Grid.PlotCells then
			return false
		end
		local uid = n.grid[Grid.key(cx, cz)]
		local other = uid and n.buildings[uid]
		return other ~= nil and isRoadDef(other.def) and other.finishAt == nil
	end
	for cx = b.x, b.x + fw - 1 do
		if isRoad(cx, b.z - 1) or isRoad(cx, b.z + fd) then
			return true
		end
	end
	for cz = b.z, b.z + fd - 1 do
		if isRoad(b.x - 1, cz) or isRoad(b.x + fw, cz) then
			return true
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
	return Grid.cframeFor(n.origin, b.x, b.z, b.def.size[1], b.def.size[2], b.r)
end

local function spawnModel(n: Nation, b: BRuntime)
	if b.model then
		b.model:Destroy()
	end
	local model = ModelBuilder.building(b.def)
	model.Name = tostring(b.uid)
	model:PivotTo(BuildService.worldCFrame(n, b))
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
end

---------------------------------------------------------------------------
-- Runtime creation
---------------------------------------------------------------------------
local function newRuntime(n: Nation, def, x: number, z: number, r: number, uid: number?): BRuntime
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
	for _, key in cellsOf(b.def, b.x, b.z, b.r) do
		n.grid[key] = b.uid
	end
end

local function unindex(n: Nation, b: BRuntime)
	for _, key in cellsOf(b.def, b.x, b.z, b.r) do
		if n.grid[key] == b.uid then
			n.grid[key] = nil
		end
	end
end

function BuildService.access(n: Nation): Unlocks.Access
	return { researched = n.data.Researched, passes = n.passes }
end

-- Core placement used by requests, undo and loading.
local function placeInternal(n: Nation, def, x: number, z: number, r: number, charge: boolean): (boolean, string?, BRuntime?)
	local ok, err = BuildService.canPlace(n, def, x, z, r)
	if not ok then
		return false, err, nil
	end
	if def.max and Nations.countAll(n, def.id) >= def.max then
		return false, ("Limit reached (max %d)"):format(def.max), nil
	end
	if charge then
		if n.data.Cash < def.cost then
			return false, "Not enough cash", nil
		end
		n.data.Cash -= def.cost
	end
	local b = newRuntime(n, def, x, z, r)
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
function BuildService.loadNation(n: Nation)
	for _, s in n.data.Buildings do
		local def = Buildings.get(s.id)
		if def then
			local r = s.r or 0
			if BuildService.canPlace(n, def, s.x, s.z, r) then
				local b = newRuntime(n, def, s.x, s.z, r, s.u)
				b.finishAt = s.f
				b.startAt = s.st
				b.damaged = s.d == true
				b.hp = b.damaged and 0 or math.clamp(s.hp or def.hp, 1, def.hp)
				b.oil = s.o or 0
				b.fuel = s.fu or 0
				b.dest = s.de or 0
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
			r = b.r ~= 0 and b.r or nil,
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
			local price = math.floor(b.def.cost * Config.RepairCostRate)
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

local function validRotation(r: any): number
	if typeof(r) ~= "number" then
		return 0
	end
	return math.floor(r) % 4
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

local function onPlace(player: Player, id: any, x: any, z: any, r: any)
	local n = nationOf(player)
	if not n then
		return { ok = false, err = "Loading..." }
	end
	local def, err = requireDef(n, id)
	if not def then
		return { ok = false, err = err }
	end
	if typeof(x) ~= "number" or typeof(z) ~= "number" then
		return { ok = false, err = "Invalid position" }
	end
	local ok, perr, b = placeInternal(n, def, math.floor(x), math.floor(z), validRotation(r), true)
	if not ok or not b then
		return { ok = false, err = perr }
	end
	pushUndo(n, { kind = "place", uid = b.uid, cost = def.cost })
	S.StateService.push(n)
	return { ok = true, uid = b.uid }
end

local function onPlaceMany(player: Player, id: any, cells: any, r: any)
	local n = nationOf(player)
	if not n then
		return { ok = false, err = "Loading..." }
	end
	local def, err = requireDef(n, id)
	if not def then
		return { ok = false, err = err }
	end
	if typeof(cells) ~= "table" then
		return { ok = false, err = "Invalid request" }
	end
	local placed = 0
	local lastErr: string? = nil
	local uids = {}
	for i, cell in cells do
		if i > 250 then
			break
		end
		if typeof(cell) == "table" and typeof(cell[1]) == "number" and typeof(cell[2]) == "number" then
			local ok, perr, b = placeInternal(n, def, math.floor(cell[1]), math.floor(cell[2]), validRotation(r), true)
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
		pushUndo(n, { kind = "placeMany", uids = uids, cost = def.cost })
		BuildService.recomputeRoads(n)
		S.StateService.push(n)
	end
	return { ok = placed > 0, placed = placed, err = placed == 0 and lastErr or nil }
end

local function refundFor(b: BRuntime): number
	if b.finishAt then
		return b.def.cost
	elseif b.damaged then
		return math.floor(b.def.cost * Config.SellRefund * 0.5)
	end
	return math.floor(b.def.cost * Config.SellRefund)
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
	pushUndo(n, { kind = "delete", id = b.id, x = b.x, z = b.z, r = b.r, refund = refund, wasBuilt = b.finishAt == nil })
	removeInternal(n, b)
	S.StateService.push(n)
	return { ok = true, refund = refund }
end

local function onMove(player: Player, uid: any, x: any, z: any, r: any)
	local n = nationOf(player)
	if not n or typeof(uid) ~= "number" or typeof(x) ~= "number" or typeof(z) ~= "number" then
		return { ok = false, err = "Invalid request" }
	end
	local b = n.buildings[uid]
	if not b then
		return { ok = false, err = "Building not found" }
	end
	local nx, nz, nr = math.floor(x), math.floor(z), validRotation(r)
	local ok, err = BuildService.canPlace(n, b.def, nx, nz, nr, b.uid)
	if not ok then
		return { ok = false, err = err }
	end
	pushUndo(n, { kind = "move", uid = b.uid, x = b.x, z = b.z, r = b.r })
	unindex(n, b)
	b.x, b.z, b.r = nx, nz, nr
	for _, key in cellsOf(b.def, b.x, b.z, b.r) do
		n.grid[key] = b.uid
	end
	if b.model then
		b.model:PivotTo(BuildService.worldCFrame(n, b))
	end
	BuildService.recomputeRoads(n)
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
				n.data.Cash += b.def.cost
				removeInternal(n, b)
			end
		end
	elseif action.kind == "delete" then
		local def = Buildings.get(action.id)
		if def then
			if n.data.Cash < action.refund then
				return { ok = false, err = "Not enough cash" }
			end
			local ok, err, b = placeInternal(n, def, action.x, action.z, action.r, false)
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
		if b and BuildService.canPlace(n, b.def, action.x, action.z, action.r, b.uid) then
			unindex(n, b)
			b.x, b.z, b.r = action.x, action.z, action.r
			for _, key in cellsOf(b.def, b.x, b.z, b.r) do
				n.grid[key] = b.uid
			end
			if b.model then
				b.model:PivotTo(BuildService.worldCFrame(n, b))
			end
			BuildService.recomputeRoads(n)
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
	local price = math.floor(b.def.cost * Config.RepairCostRate)
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
	Net.handle("DeleteBuilding", onDelete, 12)
	Net.handle("MoveBuilding", onMove, 8)
	Net.handle("Undo", onUndo, 6)
	Net.handle("RepairBuilding", onRepair, 8)
	Net.handle("RepairAll", onRepairAll, 2)
	Net.handle("SetBillboard", onSetBillboard, 1)
end

return BuildService
