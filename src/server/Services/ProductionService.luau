--[[
	ProductionService
	Military factories build missiles, drones and vehicles from a queue.
	Cash is paid when queued, steel when an item starts, and fuel is burned
	while it is being built (delivered by refinery trucks).
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Unlocks = require(Shared.Util.Unlocks)
local Weapons = require(Shared.Catalog.Weapons)
local Units = require(Shared.Catalog.Units)
local Nations = require(script.Parent.Nations)

type Nation = Nations.Nation

local ProductionService = {}
local S: { [string]: any }

function ProductionService.weaponDef(id: string)
	return Weapons.get(id)
end

function ProductionService.unitDef(id: string)
	return Units.get(id)
end

local function catalogFor(kind: string, id: string): any
	if kind == "unit" then
		return Units.get(id)
	end
	return Weapons.get(id)
end

function ProductionService.queueLimit(n: Nation): number
	return Config.MaxQueuePerFactory + (n.passes.ExtraQueue and 3 or 0)
end

local function encodeQueue(b): string
	local out = {}
	for _, item in b.queue do
		table.insert(out, { id = item.id, k = item.kind, p = math.floor(item.progress * 100) / 100 })
	end
	return HttpService:JSONEncode(out)
end

function ProductionService.tick(n: Nation, dt: number, _now: number)
	local setAttr = S.EconomyService.setAttr
	local speed = Nations.speed(n)
	for _, b in n.buildings do
		local fac = b.def.factory
		if fac then
			if Nations.isActive(b) then
				local item = b.queue[1]
				local status
				if not item then
					status = "Idle - Queue Something To Build"
				else
					local cat = catalogFor(item.kind, item.id)
					if not cat then
						table.remove(b.queue, 1)
						status = "Idle"
					elseif not item.started and n.data.Steel < cat.steel then
						status = ("Waiting For Steel (%d needed)"):format(cat.steel)
					else
						if not item.started then
							n.data.Steel -= cat.steel
							item.started = true
						end
						local dp = speed * fac.speed * math.max(b.eff, 0.25) / cat.time * dt
						dp = math.min(dp, 1 - item.progress)
						local fuelNeeded = cat.fuel * dp
						if b.fuel + 1e-6 < fuelNeeded then
							-- burn what we have, then wait for the next truck
							local partial = b.fuel / math.max(cat.fuel, 1e-3)
							item.progress += partial
							b.fuel = 0
							status = "Waiting For Fuel Delivery"
						else
							b.fuel -= fuelNeeded
							item.progress += dp
							status = ("Building %s (%d%%)"):format(cat.name, math.floor(item.progress * 100))
						end
						if item.progress >= 0.999 then
							item.progress = 1
							if item.kind == "unit" then
								if S.UnitService.canAdd(n) then
									S.UnitService.spawn(n, item.id, nil, b)
									table.remove(b.queue, 1)
									Nations.notify(n.player, cat.name .. " rolled out of the factory", "good")
								else
									status = "Army Full - Build Vehicle Depots"
								end
							else
								local stock = n.data.Inventory[item.id] or 0
								if stock < cat.stockCap then
									n.data.Inventory[item.id] = stock + 1
									table.remove(b.queue, 1)
								else
									status = "Stockpile Full - Fire Some!"
								end
							end
						end
					end
				end
				setAttr(b.model, "Status", status)
			end
			setAttr(b.model, "Queue", encodeQueue(b))
		end
	end
end

local function onQueue(player: Player, factoryUid: any, kind: any, id: any)
	local n = Nations.get(player)
	if not n or typeof(factoryUid) ~= "number" or (kind ~= "unit" and kind ~= "weapon") or typeof(id) ~= "string" then
		return { ok = false, err = "Invalid request" }
	end
	local b = n.buildings[factoryUid]
	if not b or not b.def.factory then
		return { ok = false, err = "Not a factory" }
	end
	if b.finishAt then
		return { ok = false, err = "Factory is still being built" }
	end
	local cat = catalogFor(kind, id)
	if not cat then
		return { ok = false, err = "Unknown item" }
	end
	local ok, reason = Unlocks.check(cat, S.BuildService.access(n))
	if not ok then
		return { ok = false, err = reason }
	end
	if #b.queue >= ProductionService.queueLimit(n) then
		return { ok = false, err = "Queue is full" }
	end
	if n.data.Cash < cat.cost then
		return { ok = false, err = "Not enough cash" }
	end
	n.data.Cash -= cat.cost
	table.insert(b.queue, { id = id, kind = kind, progress = 0, started = false })
	if b.model then
		b.model:SetAttribute("Queue", encodeQueue(b))
	end
	S.StateService.push(n)
	return { ok = true }
end

local function onCancel(player: Player, factoryUid: any, index: any)
	local n = Nations.get(player)
	if not n or typeof(factoryUid) ~= "number" or typeof(index) ~= "number" then
		return { ok = false }
	end
	local b = n.buildings[factoryUid]
	if not b or not b.def.factory then
		return { ok = false }
	end
	local item = b.queue[math.floor(index)]
	if not item then
		return { ok = false }
	end
	local cat = catalogFor(item.kind, item.id)
	table.remove(b.queue, math.floor(index))
	if cat then
		n.data.Cash += cat.cost
		if item.started then
			n.data.Steel += cat.steel
		end
	end
	if b.model then
		b.model:SetAttribute("Queue", encodeQueue(b))
	end
	S.StateService.push(n)
	return { ok = true }
end

function ProductionService.init(services)
	S = services
end

function ProductionService.start()
	Net.handle("QueueProduction", onQueue, 10)
	Net.handle("CancelProduction", onCancel, 10)
end

return ProductionService
