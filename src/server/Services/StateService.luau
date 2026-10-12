--[[
	StateService
	Builds the local player's state snapshot and sends only the keys that
	changed since the last push (one small RemoteEvent per second at most).
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Weapons = require(Shared.Catalog.Weapons)
local Nations = require(script.Parent.Nations)

type Nation = Nations.Nation

local StateService = {}
local S: { [string]: any }

local function r1(x: number?): number
	return math.floor((x or 0) * 10 + 0.5) / 10
end

function StateService.snapshot(n: Nation): { [string]: any }
	local data = n.data
	local st = n.stats
	local now = Nations.now()

	local launchers = {}
	local seen = {}
	for _, w in Weapons.all() do
		if not seen[w.family] then
			seen[w.family] = true
			local total, ready, _, nextReady = S.CombatService.launcherState(n, w.family, now)
			if total > 0 then
				launchers[w.family] = { total = total, ready = ready, nextReady = nextReady ~= math.huge and nextReady or 0 }
			end
		end
	end

	local q, qCur, qMax = S.RewardService.questProgress(n)
	local quest: any = false
	if q then
		quest = { i = data.Quest, text = q.text, cur = qCur, max = qMax, reward = q.reward, done = qCur >= qMax }
	end

	local nation, rank = S.NationService.snapshot(n)

	return {
		nation = nation,
		rank = rank,
		cash = math.floor(data.Cash),
		income = math.floor(st.income or 0),
		gross = math.floor(st.gross or 0),
		upkeep = math.floor(st.upkeep or 0),
		mult = r1(st.mult or 1),
		nextPay = n.nextPayAt,
		pop = math.floor(data.Population),
		popCap = math.floor(st.housingCap or 0),
		workersDemand = math.floor(st.workersDemand or 0),
		workersUsed = math.floor(st.workersUsed or 0),
		happiness = math.floor(st.happiness or 0),
		power = { math.floor(st.powerSupply or 0), math.floor(st.powerDemand or 0) },
		water = { math.floor(st.waterSupply or 0), math.floor(st.waterDemand or 0) },
		oil = math.floor(data.Oil),
		oilCap = st.oilCap or Config.BaseResourceCap,
		oilRate = r1(st.oilRate),
		steel = math.floor(data.Steel),
		food = math.floor(data.Food),
		foodCap = st.foodCap or Config.FoodBaseCap,
		foodUse = math.floor((data.Population * Config.FoodPerCitizen) * 10) / 10,
		fed = st.fed == true,
		fobs = S.FobService.snapshot(n),
		fobMax = S.FobService.maxFor(n),
		steelCap = st.steelCap or Config.BaseResourceCap,
		steelRate = r1(st.steelRate),
		rp = math.floor(data.ResearchPoints),
		rpRate = r1(st.rpRate),
		researched = data.Researched,
		research = data.ActiveResearch or false,
		inventory = data.Inventory,
		launchers = launchers,
		units = S.UnitService.count(n),
		unitCap = S.UnitService.cap(n),
		stats = data.Stats,
		pvp = data.Pvp,
		pvpLock = n.pvpLockUntil,
		shield = n.shieldUntil,
		passes = n.passes,
		boostUntil = data.BoostUntil,
		quest = quest,
		daily = S.RewardService.dailyInfo(n),
		giftAt = n.giftAt,
		giftReward = S.RewardService.giftReward(n),
		groupId = Config.GroupId,
		groupClaimed = data.Flags.Group == true,
		starter = data.Flags.StarterPack == true,
		plot = n.plotIndex,
		billboard = data.Billboard,
		queueLimit = S.ProductionService.queueLimit(n),
		damaged = st.damaged or 0,
		persistent = S.DataService.isPersistent(),
	}
end

-- Send changed keys (or everything when full = true).
function StateService.push(n: Nation, full: boolean?)
	if not n.ready or not n.player.Parent then
		return
	end
	local snap = StateService.snapshot(n)
	local patch = {}
	local any = false
	for k, v in snap do
		local enc = type(v) == "table" and HttpService:JSONEncode(v) or tostring(v)
		if full or n.sent[k] ~= enc then
			n.sent[k] = enc
			patch[k] = v
			any = true
		end
	end
	if any then
		Net.event("State"):FireClient(n.player, patch)
	end
end

function StateService.init(services)
	S = services
end

function StateService.start()
	Net.handle("GetSnapshot", function(player)
		local n = Nations.get(player)
		if not n or not n.ready then
			return nil
		end
		local snap = StateService.snapshot(n)
		for k, v in snap do
			n.sent[k] = type(v) == "table" and HttpService:JSONEncode(v) or tostring(v)
		end
		return snap
	end, 4)
end

return StateService
