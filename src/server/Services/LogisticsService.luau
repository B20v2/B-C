--[[
	LogisticsService
	Oil pumps fill the national oil pool. Refineries pull oil, refine it into
	fuel and dispatch fuel trucks to fuel consumers (military factories),
	either to a chosen destination or "Auto" (the one with most free space).

	Truck trips are exposed to clients as model attributes
	("Truck1" = "targetUid|departAt|arriveAt|returnAt") so every client,
	including late joiners, animates trucks driving along the roads.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Nations = require(script.Parent.Nations)

type Nation = Nations.Nation
type BRuntime = Nations.BRuntime

local LogisticsService = {}
local S: { [string]: any }

local MIN_LOAD = 60

local function freeSpace(b: BRuntime): number
	return (b.def.fuelCap or 0) - b.fuel - b.incoming
end

local function centerOf(n: Nation, b: BRuntime): Vector3
	return S.BuildService.worldCFrame(n, b).Position
end

local function chooseTarget(n: Nation, refinery: BRuntime): BRuntime?
	if refinery.dest ~= 0 then
		local t = n.buildings[refinery.dest]
		if t and t.def.fuelCap and Nations.isActive(t) and freeSpace(t) > 1 then
			return t
		end
		return nil
	end
	local best, bestFree = nil, 1
	for _, b in n.buildings do
		if b.def.fuelCap and Nations.isActive(b) then
			local free = freeSpace(b)
			if free > bestFree then
				best, bestFree = b, free
			end
		end
	end
	return best
end

function LogisticsService.tick(n: Nation, dt: number, now: number)
	local setAttr = S.EconomyService.setAttr
	local oilShare = 0
	local refineries = 0
	for _, b in n.buildings do
		if b.def.refine and Nations.isActive(b) then
			refineries += 1
		end
	end
	if refineries > 0 then
		oilShare = (n.stats.oilRate or 0) / refineries
	end

	for _, b in n.buildings do
		local rf = b.def.refine
		if rf then
			-- trucks keep driving even if the refinery gets knocked out
			local busy = false
			for i, t in b.trucks do
				if t.state == "out" and now >= t.arriveAt then
					local target = n.buildings[t.target]
					if target and target.def.fuelCap then
						target.incoming = math.max(0, target.incoming - t.amount)
						target.fuel = math.min(target.def.fuelCap, target.fuel + t.amount)
					else
						b.fuel = math.min(rf.fuelCap, b.fuel + t.amount) -- destination vanished: bring it home
					end
					t.state = "back"
				end
				if t.state == "back" and now >= t.returnAt then
					t.state = "idle"
					setAttr(b.model, "Truck" .. i, "")
				end
				if t.state ~= "idle" then
					busy = true
				end
			end

			if Nations.isActive(b) then
				-- pull oil from the national pool
				local want = math.min(rf.oilCap - b.oil, rf.rate * 2 / 60 * dt)
				local take = math.max(0, math.min(want, n.data.Oil))
				n.data.Oil -= take
				b.oil += take
				-- refine
				local amount = math.max(0, math.min(b.oil, rf.rate / 60 * dt * b.eff, rf.fuelCap - b.fuel))
				b.oil -= amount
				b.fuel += amount

				-- dispatch idle trucks
				for i, t in b.trucks do
					if t.state == "idle" and b.fuel >= math.min(MIN_LOAD, rf.fuelCap) then
						local target = chooseTarget(n, b)
						if target then
							local load = math.floor(math.min(b.fuel, Config.TruckCapacity, freeSpace(target)))
							if load > 0 then
								local a, c = centerOf(n, b), centerOf(n, target)
								local dist = math.abs(a.X - c.X) + math.abs(a.Z - c.Z)
								local trip = math.max(4, dist / Config.TruckSpeed)
								t.state = "out"
								t.target = target.uid
								t.amount = load
								t.arriveAt = now + trip
								t.returnAt = now + trip * 2
								b.fuel -= load
								target.incoming += load
								busy = true
								setAttr(b.model, "Truck" .. i, ("%d|%.2f|%.2f|%.2f"):format(target.uid, now, t.arriveAt, t.returnAt))
							end
						end
					end
				end

				local status
				if busy then
					status = "Fuel Truck Already Delivering"
				elseif b.fuel >= rf.fuelCap - 0.5 then
					status = chooseTarget(n, b) and "Loading Truck" or "Fuel Storage Full - No Destination"
				elseif b.oil < 1 and n.data.Oil < 1 then
					status = "Waiting For Oil - Build Oil Pumps"
				elseif b.status ~= "Working" then
					status = b.status
				else
					status = "Refining Oil Into Fuel"
				end
				setAttr(b.model, "Status", status)
			end
			setAttr(b.model, "Oil", math.floor(b.oil))
			setAttr(b.model, "Fuel", math.floor(b.fuel))
			setAttr(b.model, "OilArriving", math.floor(oilShare * 10) / 10)
			setAttr(b.model, "Dest", b.dest)
		elseif b.def.fuelCap then
			setAttr(b.model, "Fuel", math.floor(b.fuel))
			setAttr(b.model, "Incoming", math.floor(b.incoming))
		end
	end
end

local function onSetDestination(player: Player, refineryUid: any, destUid: any)
	local n = Nations.get(player)
	if not n or typeof(refineryUid) ~= "number" or typeof(destUid) ~= "number" then
		return { ok = false }
	end
	local b = n.buildings[refineryUid]
	if not b or not b.def.refine then
		return { ok = false, err = "Not a refinery" }
	end
	if destUid ~= 0 then
		local t = n.buildings[destUid]
		if not t or not t.def.fuelCap then
			return { ok = false, err = "That building doesn't use fuel" }
		end
	end
	b.dest = destUid
	if b.model then
		b.model:SetAttribute("Dest", destUid)
	end
	return { ok = true }
end

function LogisticsService.init(services)
	S = services
end

function LogisticsService.start()
	Net.handle("SetFuelDestination", onSetDestination, 6)
end

return LogisticsService
