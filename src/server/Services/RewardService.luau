--[[
	RewardService
	Retention loops: offline earnings, daily login streak, playtime gifts,
	group reward, codes and the objective (quest) chain.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)
local Quests = require(Shared.Catalog.Quests)
local Nations = require(script.Parent.Nations)

type Nation = Nations.Nation

local RewardService = {}
local S: { [string]: any }

local function today(): number
	return os.time() // 86400
end

---------------------------------------------------------------------------
-- Offline earnings
---------------------------------------------------------------------------
function RewardService.onJoin(n: Nation)
	local data = n.data
	n.giftAt = n.joinAt + Config.PlaytimeGiftInterval
	if data.LastOnline > 0 and data.LastPay > 0 then
		local away = os.time() - data.LastOnline
		if away > 120 then
			local capped = math.min(away, Config.OfflineEarningsHours * 3600 * (n.passes.VIP and 2 or 1))
			local rate = Config.OfflineEarningsRate * (n.passes.DoubleCash and 2 or 1)
			local amount = math.floor(data.LastPay * (capped / Config.PayInterval) * rate)
			if amount > 0 then
				data.Cash += amount
				Net.event("Effect"):FireClient(n.player, "Welcome", nil, amount, away)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Daily / gift / group / codes
---------------------------------------------------------------------------
function RewardService.dailyReward(n: Nation, streak: number): number
	local base = Config.DailyRewards[((streak - 1) % #Config.DailyRewards) + 1]
	return math.floor(base + math.max(0, n.stats.gross or 0) * 2)
end

function RewardService.dailyInfo(n: Nation): { [string]: any }
	local d = n.data.Daily
	local canClaim = d.LastDay < today()
	local nextStreak = (d.LastDay == today() - 1) and d.Streak + 1 or (canClaim and 1 or d.Streak)
	return { streak = d.Streak, canClaim = canClaim, next = nextStreak, reward = RewardService.dailyReward(n, math.max(1, nextStreak)) }
end

function RewardService.giftReward(n: Nation): number
	return math.floor(math.max(5000, (n.stats.gross or 0) * Config.PlaytimeGiftPays))
end

local function onClaimDaily(player: Player)
	local n = Nations.get(player)
	if not n then
		return { ok = false }
	end
	local d = n.data.Daily
	if d.LastDay >= today() then
		return { ok = false, err = "Come back tomorrow!" }
	end
	d.Streak = (d.LastDay == today() - 1) and d.Streak + 1 or 1
	d.LastDay = today()
	local reward = RewardService.dailyReward(n, d.Streak)
	n.data.Cash += reward
	Nations.notify(player, ("Day %d reward: +%s"):format(d.Streak, Format.cash(reward)), "pay")
	S.StateService.push(n)
	return { ok = true, reward = reward }
end

local function onClaimPlaytime(player: Player)
	local n = Nations.get(player)
	if not n then
		return { ok = false }
	end
	local now = Nations.now()
	if now < n.giftAt then
		return { ok = false, err = "Gift not ready yet" }
	end
	local reward = RewardService.giftReward(n)
	n.data.Cash += reward
	n.giftAt = now + Config.PlaytimeGiftInterval
	Nations.notify(player, ("Playtime gift: +%s"):format(Format.cash(reward)), "pay")
	S.StateService.push(n)
	return { ok = true, reward = reward }
end

local function onClaimGroup(player: Player)
	local n = Nations.get(player)
	if not n or Config.GroupId == 0 then
		return { ok = false, err = "No group reward" }
	end
	if n.data.Flags.Group then
		return { ok = false, err = "Already claimed" }
	end
	local ok, inGroup = pcall(player.IsInGroup, player, Config.GroupId)
	if not ok or not inGroup then
		return { ok = false, err = "Join the group first, then claim!" }
	end
	n.data.Flags.Group = true
	n.data.Cash += Config.GroupRewardCash
	Nations.notify(player, ("Thanks for joining! +%s"):format(Format.cash(Config.GroupRewardCash)), "pay")
	S.StateService.push(n)
	return { ok = true }
end

local function onRedeem(player: Player, code: any)
	local n = Nations.get(player)
	if not n or typeof(code) ~= "string" then
		return { ok = false }
	end
	code = string.upper((code:gsub("%s", "")))
	local reward = Config.Codes[code]
	if not reward then
		return { ok = false, err = "Invalid code" }
	end
	if n.data.Redeemed[code] then
		return { ok = false, err = "Code already redeemed" }
	end
	n.data.Redeemed[code] = true
	n.data.Cash += reward
	Nations.notify(player, ("Code redeemed: +%s"):format(Format.cash(reward)), "pay")
	S.StateService.push(n)
	return { ok = true, reward = reward }
end

---------------------------------------------------------------------------
-- Quests
---------------------------------------------------------------------------
function RewardService.questProgress(n: Nation): (any?, number, number)
	local q = Quests[n.data.Quest]
	if not q then
		return nil, 0, 0
	end
	local data = n.data
	local cur = 0
	if q.kind == "build" then
		cur = Nations.countBuilt(n, q.target :: string)
	elseif q.kind == "population" then
		cur = math.floor(data.Population)
	elseif q.kind == "research" then
		cur = data.Researched[q.target :: string] and 1 or 0
	elseif q.kind == "stock" then
		cur = data.Inventory[q.target :: string] or 0
	elseif q.kind == "launch" then
		cur = data.Stats.Launches
	elseif q.kind == "hits" then
		cur = data.Stats.Hits
	elseif q.kind == "capture" then
		cur = data.Stats.Captures
	elseif q.kind == "units" then
		cur = S.UnitService.count(n)
	end
	return q, math.min(cur, q.count), q.count
end

function RewardService.tick(_n: Nation, _now: number)
	-- quest progress is computed on demand by StateService
end

local function onClaimQuest(player: Player)
	local n = Nations.get(player)
	if not n then
		return { ok = false }
	end
	local q, cur, max = RewardService.questProgress(n)
	if not q or cur < max then
		return { ok = false, err = "Objective not complete" }
	end
	n.data.Quest += 1
	n.data.Cash += q.reward
	Nations.notify(player, ("Objective complete: +%s"):format(Format.cash(q.reward)), "pay")
	S.StateService.push(n)
	return { ok = true, reward = q.reward }
end

function RewardService.init(services)
	S = services
end

function RewardService.start()
	Net.handle("ClaimDaily", onClaimDaily, 2)
	Net.handle("ClaimPlaytime", onClaimPlaytime, 2)
	Net.handle("ClaimGroup", onClaimGroup, 2)
	Net.handle("RedeemCode", onRedeem, 2)
	Net.handle("ClaimQuest", onClaimQuest, 3)
end

return RewardService
