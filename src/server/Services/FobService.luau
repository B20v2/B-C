--[[
	FobService
	Forward Operating Bases and field logistics.

	  * A Logistics Truck or Chinook on the battlefield can set up a FOB
	    (cash + steel). One per nation (two with VIP), away from strategic
	    points and other FOBs. It has walls, tents, a helipad, a watchtower
	    and a supply dump.
	  * Supplies are packed at home from food + steel into trucks and
	    helicopters, then driven or flown out and unloaded at the FOB.
	  * A supplied FOB heals your units around it and its perimeter gun
	    shoots enemy ground units. Enemies can shoot it down (units or
	    missiles); a destroyed FOB loses its supplies.
	  * Unit orders: MOUNT (squads climb into transports), DISMOUNT, LOAD /
	    UNLOAD SUPPLIES, SET UP FOB and AIRLIFT (helicopters shuttle squads,
	    supplies and a slung vehicle between your helipad and your FOB).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Grid = require(Shared.Util.Grid)
local Net = require(Shared.Net)
local Format = require(Shared.Util.Format)
local ModelBuilder = require(Shared.ModelBuilder)
local WarMap = require(Shared.Catalog.WarMap)
local Nations = require(script.Parent.Nations)

type Nation = Nations.Nation

export type Fob = {
	id: number,
	n: Nation,
	pos: Vector3,
	hp: number,
	supplies: number,
	model: Model,
	lastShot: number,
}

local FobService = {}
local S: { [string]: any }
local folder: Folder
local nextId = 0

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function dist(a: Vector3, b: Vector3): number
	return (flat(a) - flat(b)).Magnitude
end

function FobService.maxFor(n: Nation): number
	return Config.FobMax + (n.passes.VIP and 1 or 0)
end

function FobService.all(): { Fob }
	local out = {}
	for _, n in Nations.all() do
		for _, f in n.fobs do
			table.insert(out, f)
		end
	end
	return out
end

local function refresh(f: Fob)
	f.model:SetAttribute("Hp", math.floor(f.hp))
	f.model:SetAttribute("Supplies", math.floor(f.supplies))
end

local function create(n: Nation, pos: Vector3, hp: number?, supplies: number?): Fob
	nextId += 1
	local model = ModelBuilder.fob(Config.NationColors[n.plotIndex])
	model.Name = "FOB_" .. n.userId .. "_" .. nextId
	-- gate faces the capital
	local look = flat(Config.MainlandOrigin - pos)
	local cf = look.Magnitude > 1 and CFrame.lookAt(flat(pos), flat(pos) + look.Unit) or CFrame.new(flat(pos))
	model:PivotTo(cf)
	model:SetAttribute("Fob", true)
	model:SetAttribute("OwnerId", n.userId)
	model:SetAttribute("OwnerName", n.player.DisplayName)
	model:SetAttribute("Color", Config.NationColors[n.plotIndex])
	model:SetAttribute("MaxHp", Config.FobHp)
	model:SetAttribute("SupplyCap", Config.FobSupplyCap)
	model.Parent = folder
	local f: Fob = {
		id = nextId,
		n = n,
		pos = flat(pos),
		hp = hp or Config.FobHp,
		supplies = supplies or 0,
		model = model,
		lastShot = 0,
	}
	table.insert(n.fobs, f)
	refresh(f)
	return f
end

-- Is this a legal FOB spot? (on the battlefield, clear of points and other FOBs)
function FobService.canBuildAt(pos: Vector3): (boolean, string?)
	if not Grid.inMainland(pos, -60) then
		return false, "FOBs go on the central battlefield"
	end
	for _, def in WarMap do
		if dist(pos, Config.MainlandOrigin + def.offset) < Config.FobSpacing then
			return false, ("Too close to the %s"):format(def.name)
		end
	end
	for _, f in FobService.all() do
		if dist(pos, f.pos) < Config.FobSpacing then
			return false, "Too close to another FOB"
		end
	end
	return true, nil
end

function FobService.deploy(n: Nation, u: any): (boolean, string?)
	if not u.def.fob then
		return false, "Only Logistics Trucks and Chinooks can set up a FOB"
	end
	if u.carried then
		return false, "Unload it first"
	end
	if #n.fobs >= FobService.maxFor(n) then
		return false, ("FOB limit reached (%d)%s"):format(FobService.maxFor(n), n.passes.VIP and "" or " - VIP raises it to 2")
	end
	-- the base goes up just ahead of the truck, towards the capital
	local here = flat(u.root.CFrame.Position)
	local toCentre = flat(Config.MainlandOrigin) - here
	local at = toCentre.Magnitude > 50 and here + toCentre.Unit * 40 or here
	local ok, err = FobService.canBuildAt(at)
	if not ok then
		return false, err
	end
	if n.data.Cash < Config.FobCost then
		return false, ("A FOB costs %s"):format(Format.cash(Config.FobCost))
	end
	if n.data.Steel < Config.FobSteel then
		return false, ("A FOB needs %d steel"):format(Config.FobSteel)
	end
	n.data.Cash -= Config.FobCost
	n.data.Steel -= Config.FobSteel
	local f = create(n, at)
	-- whatever the builder carried goes straight into the dump
	local moved = math.min(u.supplies, Config.FobSupplyCap)
	f.supplies += moved
	S.UnitService.setSupplies(u, u.supplies - moved)
	refresh(f)
	Nations.notify(n.player, "FOB established on the front line", "good")
	Net.event("Effect"):FireClient(n.player, "BuildDone", f.pos, "Forward Operating Base")
	return true, nil
end

-- Own FOB within `radius` of a position.
function FobService.near(n: Nation, pos: Vector3, radius: number?): Fob?
	for _, f in n.fobs do
		if dist(pos, f.pos) <= (radius or Config.FobRadius) then
			return f
		end
	end
	return nil
end

function FobService.enemyFobInRange(pos: Vector3, range: number, n: Nation): Fob?
	for _, f in FobService.all() do
		if f.n ~= n and dist(pos, f.pos) <= range + 30 then
			return f
		end
	end
	return nil
end

local function destroy(f: Fob, attacker: Nation?)
	local idx = table.find(f.n.fobs, f)
	if idx then
		table.remove(f.n.fobs, idx)
	end
	Net.event("Effect"):FireAllClients("Explosion", f.pos + Vector3.new(0, 3, 0), 3)
	f.model:Destroy()
	Nations.notify(f.n.player, "Your FOB was destroyed!", "bad")
	if attacker and attacker.player.Parent then
		attacker.data.Cash += 15000
		Nations.notify(attacker.player, ("You destroyed %s's FOB! +%s"):format(f.n.player.DisplayName, Format.cash(15000)), "good")
	end
end

function FobService.damage(f: Fob, amount: number, attacker: Nation?)
	if f.hp <= 0 then
		return
	end
	f.hp -= amount
	if f.hp <= 0 then
		destroy(f, attacker)
	else
		refresh(f)
	end
end

-- Missiles hitting the battlefield also hurt FOBs in the blast.
function FobService.damageNear(pos: Vector3, radius: number, amount: number, attacker: Nation)
	for _, f in FobService.all() do
		if f.n ~= attacker and dist(pos, f.pos) <= radius + 30 then
			FobService.damage(f, amount, attacker)
		end
	end
end

-- Unload a transport's supplies into a nearby own FOB; returns amount moved.
function FobService.deliver(u: any): number
	if (u.supplies or 0) <= 0 then
		return 0
	end
	local f = FobService.near(u.n, u.root.CFrame.Position)
	if not f then
		return 0
	end
	local moved = math.floor(math.min(u.supplies, Config.FobSupplyCap - f.supplies))
	if moved > 0 then
		f.supplies += moved
		S.UnitService.setSupplies(u, u.supplies - moved)
		refresh(f)
	end
	return moved
end

-- Pack supplies at home from food + steel; returns amount loaded.
function FobService.pack(n: Nation, u: any): number
	local cap = u.def.cargo and u.def.cargo.supplies or 0
	local room = cap - u.supplies
	local cost = Config.SupplyCost
	local afford = math.min(room, math.floor(n.data.Food / cost.food), math.floor(n.data.Steel / cost.steel))
	if afford <= 0 then
		return 0
	end
	n.data.Food -= afford * cost.food
	n.data.Steel -= afford * cost.steel
	S.UnitService.setSupplies(u, u.supplies + afford)
	return afford
end

---------------------------------------------------------------------------
-- Tick: heal friendly units, perimeter gun
---------------------------------------------------------------------------
local function tick(dt: number)
	local now = os.clock()
	local units = S.UnitService.all()
	for _, f in FobService.all() do
		local target, bestD = nil, Config.FobGunRange
		for u in units do
			if not u.carried then
				local d = dist(u.root.CFrame.Position, f.pos)
				if u.n == f.n then
					if d <= Config.FobRadius and f.supplies > 0 and u.hp < u.def.hp then
						local healed = S.UnitService.heal(u, math.min(Config.FobHealRate * dt, f.supplies * Config.FobHealPerSupply))
						f.supplies = math.max(0, f.supplies - healed / Config.FobHealPerSupply)
					end
				elseif not u.air and d <= bestD then
					target, bestD = u, d
				end
			end
		end
		if target then
			if now - f.lastShot > 1 then
				f.lastShot = now
				Net.event("Effect"):FireAllClients("Shot", f.pos + Vector3.new(0, 9, 0), target.root.CFrame.Position, false)
			end
			S.UnitService.damage(target, Config.FobGunDps * dt, f.n)
		end
		refresh(f)
	end
end

FobService._tick = tick

---------------------------------------------------------------------------
-- Field orders
---------------------------------------------------------------------------
local function transportsIn(list: { any }): { any }
	local out = {}
	for _, u in list do
		if u.def.cargo and (u.def.cargo.squads or 0) > 0 and not u.carried then
			table.insert(out, u)
		end
	end
	return out
end

local function squadsIn(list: { any }): { any }
	local out = {}
	for _, u in list do
		if u.def.class == "infantry" and not u.carried then
			table.insert(out, u)
		end
	end
	return out
end

-- Squads climb into the nearest transport with room (walking over if needed).
local function mount(n: Nation, units: { any }): (number, string?)
	local squads = squadsIn(units)
	if #squads == 0 then
		return 0, "Select infantry squads (and a transport)"
	end
	local transports = transportsIn(units)
	if #transports == 0 then
		for _, u in n.units do
			if u.def.cargo and (u.def.cargo.squads or 0) > 0 and not u.carried then
				table.insert(transports, u)
			end
		end
	end
	local boarded, walking = 0, 0
	local seats: { [any]: number } = {}
	for _, t in transports do
		seats[t] = S.UnitService.freeSeats(t)
	end
	for _, sq in squads do
		local best, bestD = nil, math.huge
		for _, t in transports do
			if seats[t] > 0 then
				local d = dist(sq.root.CFrame.Position, t.root.CFrame.Position)
				if d < bestD then
					best, bestD = t, d
				end
			end
		end
		if best then
			seats[best] -= 1
			if bestD <= Config.BoardRange then
				if S.UnitService.board(sq, best) then
					boarded += 1
				end
			else
				S.UnitService.drive(sq, best.root.CFrame.Position, "board:" .. best.uid)
				walking += 1
			end
		end
	end
	if boarded + walking == 0 then
		return 0, "No free seats - Humvees, IFVs, trucks and helicopters carry squads"
	end
	return boarded + walking, nil
end

local function dismount(units: { any }): number
	local count = 0
	for _, u in units do
		if #u.cargo > 0 or u.slung then
			if u.air and not u.landed then
				S.UnitService.landNow(u, "unload")
				count += #u.cargo + (u.slung and 1 or 0)
			else
				count += S.UnitService.unload(u)
			end
		end
	end
	return count
end

-- Helicopter shuttle between the home helipad and the FOB.
local function airlift(n: Nation, units: { any }, dest: string): (number, string?)
	local helis = {}
	for _, u in units do
		if u.air and u.def.cargo and not u.carried then
			table.insert(helis, u)
		end
	end
	if #helis == 0 then
		return 0, "Select a Black Hawk or Chinook"
	end
	local fob = n.fobs[1]
	if dest == "fob" and not fob then
		return 0, "Set up a FOB first (Logistics Truck or Chinook on the battlefield)"
	end
	for _, h in helis do
		local here = h.root.CFrame.Position
		if dest == "fob" then
			if h.location == "home" then
				-- pick up squads waiting at home, supplies, and (Chinook) a light vehicle
				for _, sq in n.units do
					if S.UnitService.freeSeats(h) <= 0 then
						break
					end
					if sq.def.class == "infantry" and not sq.carried and sq.location == "home" then
						S.UnitService.board(sq, h)
					end
				end
				FobService.pack(n, h)
				if (h.def.cargo.vehicles or 0) > 0 and not h.slung then
					local best, bestD = nil, math.huge
					for _, v in n.units do
						if v.def.light and not v.carried and v.location == "home" and v ~= h then
							local d = dist(v.root.CFrame.Position, here)
							if d < bestD then
								best, bestD = v, d
							end
						end
					end
					if best then
						S.UnitService.slingLoad(h, best)
					end
				end
			end
			S.UnitService.drive(h, (fob :: Fob).pos + Vector3.new(0, 0, 0), "unload")
		else
			local f = FobService.near(n, here)
			if f then
				for _, sq in n.units do
					if S.UnitService.freeSeats(h) <= 0 then
						break
					end
					if sq.def.class == "infantry" and not sq.carried and dist(sq.root.CFrame.Position, f.pos) <= Config.FobRadius then
						S.UnitService.board(sq, h)
					end
				end
			end
			S.UnitService.drive(h, S.UnitService.helipadPos(n), "unload")
		end
	end
	return #helis, nil
end

local function onOrder(player: Player, kind: any, uids: any, arg: any)
	local n = Nations.get(player)
	if not n or not n.ready or typeof(kind) ~= "string" then
		return { ok = false, err = "Invalid request" }
	end
	local units = S.UnitService.collect(n, uids)
	if #units == 0 then
		return { ok = false, err = "Select units first" }
	end
	if kind == "mount" then
		local count, err = mount(n, units)
		return { ok = count > 0, count = count, err = err }
	elseif kind == "dismount" then
		local count = dismount(units)
		return { ok = count > 0, count = count, err = count == 0 and "Nobody aboard" or nil }
	elseif kind == "loadSupplies" then
		local total = 0
		for _, u in units do
			if u.def.cargo and (u.def.cargo.supplies or 0) > 0 and not u.carried then
				if u.location ~= "home" then
					return { ok = false, err = "Supplies are packed at home - bring the transport back" }
				end
				total += FobService.pack(n, u)
			end
		end
		S.StateService.push(n)
		return { ok = total > 0, count = total, err = total == 0 and "Nothing loaded - needs a truck or helicopter with room, food and steel" or nil }
	elseif kind == "unloadSupplies" then
		local total = 0
		for _, u in units do
			total += FobService.deliver(u)
		end
		return { ok = total > 0, count = total, err = total == 0 and "Drive a loaded transport into your FOB first" or nil }
	elseif kind == "fob" then
		for _, u in units do
			if u.def.fob then
				local ok, err = FobService.deploy(n, u)
				S.StateService.push(n)
				return { ok = ok, err = err }
			end
		end
		return { ok = false, err = "Select a Logistics Truck or Chinook on the battlefield" }
	elseif kind == "airlift" then
		local count, err = airlift(n, units, arg == "home" and "home" or "fob")
		S.StateService.push(n)
		return { ok = count > 0, count = count, err = err }
	end
	return { ok = false, err = "Unknown order" }
end

---------------------------------------------------------------------------
-- Save / load / snapshot
---------------------------------------------------------------------------
function FobService.loadNation(n: Nation)
	for _, s in n.data.Fobs or {} do
		if typeof(s) == "table" and type(s.x) == "number" and type(s.z) == "number" then
			local pos = Vector3.new(s.x, 0, s.z)
			if Grid.inMainland(pos) and #n.fobs < FobService.maxFor(n) then
				create(n, pos, math.clamp(s.hp or Config.FobHp, 1, Config.FobHp), math.clamp(s.s or 0, 0, Config.FobSupplyCap))
			end
		end
	end
end

function FobService.serialize(n: Nation)
	local out = {}
	for _, f in n.fobs do
		table.insert(out, { x = math.floor(f.pos.X), z = math.floor(f.pos.Z), hp = math.floor(f.hp), s = math.floor(f.supplies) })
	end
	n.data.Fobs = out
end

function FobService.clearNation(n: Nation)
	for _, f in n.fobs do
		f.model:Destroy()
	end
	table.clear(n.fobs)
end

function FobService.snapshot(n: Nation): { any }
	local out = {}
	for _, f in n.fobs do
		table.insert(out, { x = math.floor(f.pos.X), z = math.floor(f.pos.Z), hp = math.floor(f.hp), maxHp = Config.FobHp, supplies = math.floor(f.supplies), cap = Config.FobSupplyCap })
	end
	return out
end

function FobService.init(services)
	S = services
	folder = Instance.new("Folder")
	folder.Name = "Fobs"
	local mainland = workspace:FindFirstChild("Mainland")
	folder.Parent = mainland or workspace
end

function FobService.start()
	Net.handle("UnitOrder", onOrder, 6)
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(tick, 1)
			if not ok then
				warn("[FOB] tick failed: " .. tostring(err))
			end
		end
	end)
end

return FobService
