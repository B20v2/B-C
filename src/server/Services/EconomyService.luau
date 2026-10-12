--[[
	EconomyService
	Runs the 1-second simulation loop for every nation and owns the core
	economy: workers, power, water, road access, happiness, population,
	national resources and pay day.

	Each tick (in order):
	  BuildService (construction) -> Economy (stats) -> Logistics (refineries,
	  trucks) -> Production (factories) -> Research -> Rewards (quests) -> State
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local Nations = require(script.Parent.Nations)

type Nation = Nations.Nation

local EconomyService = {}
local S: { [string]: any }

local SERVICE_HAPPINESS = { Leisure = 15, Commerce = 10, Education = 10, Health = 15 }

local function setAttr(model: Model?, key: string, value: any)
	if model and model:GetAttribute(key) ~= value then
		model:SetAttribute(key, value)
	end
end
EconomyService.setAttr = setAttr

function EconomyService.incomeMultiplier(n: Nation): number
	local mult = 1
	if n.passes.VIP then
		mult += 0.25
	end
	if n.premium then
		mult += Config.PremiumIncomeBonus
	end
	if n.passes.DoubleCash then
		mult *= 2
	end
	if n.data.BoostUntil > os.time() then
		mult *= 2
	end
	return mult
end

function EconomyService.compute(n: Nation, dt: number)
	local data = n.data
	local pop = data.Population
	local bonus = S.ConquestService.bonusFor(n)

	-- 1) worker demand from active buildings
	local workersDemand = 0
	for _, b in n.buildings do
		if Nations.isActive(b) and b.def.workers then
			workersDemand += b.def.workers
		end
	end
	local wr = workersDemand > 0 and math.min(1, pop / workersDemand) or 1

	local function baseEff(b): number
		local e = b.connected and 1 or 0.5
		if b.def.workers then
			e *= wr
		end
		return e
	end

	-- 2) power
	local powerSupply, powerDemand = bonus.power or 0, 0
	for _, b in n.buildings do
		if Nations.isActive(b) then
			if b.def.powerOut then
				powerSupply += b.def.powerOut * baseEff(b)
			end
			if b.def.power then
				powerDemand += b.def.power
			end
		end
	end
	local pr = powerDemand > 0 and math.min(1, powerSupply / powerDemand) or 1

	-- 3) water
	local waterSupply, waterDemand = 0, 0
	for _, b in n.buildings do
		if Nations.isActive(b) then
			if b.def.waterOut then
				waterSupply += b.def.waterOut * baseEff(b) * (b.def.power and pr or 1)
			end
			if b.def.water then
				waterDemand += b.def.water
			end
		end
	end
	local wtr = waterDemand > 0 and math.min(1, waterSupply / waterDemand) or 1

	-- 4) per-building efficiency and outputs
	local housingCap = 0
	local oilRate, steelRate, rpRate = bonus.oil or 0, bonus.steel or 0, bonus.rp or 0
	local commerce = bonus.income or 0
	local services = { Leisure = 0, Commerce = 0, Education = 0, Health = 0 }
	local pollution, upkeep, damaged, constructing = 0, 0, 0, 0
	local oilCap, steelCap = Config.BaseResourceCap, Config.BaseResourceCap
	local depotCap = 0

	for _, b in n.buildings do
		local def = b.def
		if b.finishAt then
			constructing += 1
			b.eff = 0
			setAttr(b.model, "Status", "Under Construction")
		elseif b.damaged then
			damaged += 1
			upkeep += def.cost * Config.UpkeepRate
			b.eff = 0
			setAttr(b.model, "Status", "Damaged - Needs Repair")
		else
			upkeep += def.cost * Config.UpkeepRate
			local road = b.connected and 1 or 0.5
			local eff = road
			if def.workers then
				eff *= wr
			end
			if def.power then
				eff *= pr
			end
			if def.water then
				eff *= wtr
			end
			if def.housing then
				local h = road * (0.4 + 0.6 * math.min(pr, wtr))
				housingCap += def.housing * h
				eff = h
			end
			b.eff = eff
			if def.oilOut then
				oilRate += def.oilOut * eff
			end
			if def.steelOut then
				steelRate += def.steelOut * eff
			end
			if def.rpOut then
				rpRate += def.rpOut * eff
			end
			if def.income then
				commerce += def.income * eff
			end
			if def.service then
				services[def.service.kind] += def.service.serves * eff
			end
			if def.pollution then
				pollution += def.pollution
			end
			if def.storage then
				oilCap += def.storage.oil or 0
				steelCap += def.storage.steel or 0
			end
			if def.depot then
				depotCap += def.depot
			end
			-- generic status; specialised services overwrite it afterwards
			local status
			if not b.connected then
				status = "No Road Access - Half Speed"
			elseif def.workers and wr < 0.999 then
				status = "Not Enough Workers"
			elseif def.power and pr < 0.999 then
				status = "Not Enough Power"
			elseif def.water and wtr < 0.999 then
				status = "Not Enough Water"
			else
				status = "Working"
			end
			b.status = status
			setAttr(b.model, "Status", status)
		end
		setAttr(b.model, "Eff", math.floor(b.eff * 100 + 0.5))
	end

	-- 5) happiness
	local happiness = Config.HappinessBase
	for kind, max in SERVICE_HAPPINESS do
		local coverage = pop > 0 and math.min(1, services[kind] / pop) or 1
		happiness += max * coverage
	end
	happiness -= math.min(25, pollution * 0.6)
	happiness -= (1 - pr) * 20 + (1 - wtr) * 20
	happiness -= math.min(15, damaged * 2)
	if pop < 150 then
		happiness += 10 -- small towns are forgiving so new players grow fast
	end
	happiness = math.clamp(happiness, 0, 100)

	-- 6) population
	if pop < housingCap and happiness >= 35 then
		local growth = math.max(Config.PopulationMinGrowth, (housingCap - pop) * Config.PopulationGrowth) * dt
		pop = math.min(housingCap, pop + growth)
	elseif pop > housingCap then
		pop = math.max(housingCap, pop - math.max(1, (pop - housingCap) * 0.06) * dt)
	end
	if happiness < 25 then
		pop = math.max(0, pop - pop * 0.003 * dt)
	end
	data.Population = pop

	-- 7) national resources
	data.Oil = math.min(oilCap, data.Oil + oilRate / 60 * dt)
	data.Steel = math.min(steelCap, data.Steel + steelRate / 60 * dt)
	data.ResearchPoints += rpRate / 60 * dt

	-- 8) projected pay
	local taxes = pop * Config.TaxPerCitizen * (0.4 + 0.8 * happiness / 100)
	local mult = EconomyService.incomeMultiplier(n)
	local gross = (taxes + commerce) * mult
	local net = gross - upkeep

	local st = n.stats
	st.housingCap = housingCap
	st.workersDemand = workersDemand
	st.workersUsed = math.min(pop, workersDemand)
	st.powerSupply, st.powerDemand = powerSupply, powerDemand
	st.waterSupply, st.waterDemand = waterSupply, waterDemand
	st.happiness = happiness
	st.oilRate, st.steelRate, st.rpRate = oilRate, steelRate, rpRate
	st.oilCap, st.steelCap = oilCap, steelCap
	st.taxes, st.commerce, st.upkeep = taxes, commerce, upkeep
	st.gross, st.income, st.mult = gross, net, mult
	st.depotCap = depotCap
	st.damaged, st.constructing = damaged, constructing
	st.services = services
end

function EconomyService.payDay(n: Nation)
	local net = math.floor(n.stats.income or 0)
	local data = n.data
	data.Cash = math.max(0, data.Cash + net)
	data.LastPay = net
	if net > 0 then
		data.Stats.TotalEarned += net
	end
	if net ~= 0 then
		Nations.notify(n.player, (net > 0 and "Pay day! +" or "Pay day: ") .. Format.cash(net), "pay")
	end
end

-- Cash = income per pay day for `minutes` minutes (used by cash packs & gifts).
function EconomyService.incomeFor(n: Nation, minutes: number): number
	local perPay = math.max(n.stats.gross or 0, 0)
	return perPay * (minutes * 60 / Config.PayInterval)
end

local function tick(dt: number)
	local now = Nations.now()
	for _, n in Nations.all() do
		if n.ready then
			local ok, err = pcall(function()
				S.BuildService.tick(n, now)
				EconomyService.compute(n, dt)
				S.LogisticsService.tick(n, dt, now)
				S.ProductionService.tick(n, dt, now)
				S.ResearchService.tick(n, now)
				S.RewardService.tick(n, now)
				S.NationService.tick(n, now)
				if now >= n.nextPayAt then
					n.nextPayAt += Config.PayInterval
					if n.nextPayAt < now then
						n.nextPayAt = now + Config.PayInterval
					end
					EconomyService.payDay(n)
				end
				n.data.Stats.PlayTime += dt
				S.StateService.push(n)
			end)
			if not ok then
				warn("[Economy] tick failed for " .. n.player.Name .. ": " .. tostring(err))
			end
		end
	end
end

-- exposed for automated tests
EconomyService._tick = tick

function EconomyService.init(services)
	S = services
end

function EconomyService.start()
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(1)
			local t = os.clock()
			local dt = math.min(3, t - last)
			last = t
			tick(dt)
		end
	end)
end

return EconomyService
