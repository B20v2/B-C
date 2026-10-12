--[[
	NationService
	Nation identity and standing:
	  * SetNation  - name (3-20 chars, text-filtered) + flag, saved with the data
	  * identity   - player attributes (NationName / NationFlag) and the plot's
	                 sign + flagpole, so every client can draw the nation
	  * rank       - power score from population, buildings, tech, vehicles
	                 and captured points; each new rank pays a one-off reward
]]

local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Flag = require(Shared.Util.Flag)
local Format = require(Shared.Util.Format)
local Rank = require(Shared.Util.Rank)
local Nations = require(script.Parent.Nations)

type Nation = Nations.Nation

local NationService = {}
local S: { [string]: any }

local NAME_CHARS = "^[%w %-'%.]+$"

local function cleanName(s: string): string
	s = string.gsub(s, "%s+", " ")
	s = string.match(s, "^%s*(.-)%s*$") or ""
	return s
end

-- Pushes the saved identity to attributes and the plot.
function NationService.apply(n: Nation)
	local nation = n.data.Nation
	local name = type(nation) == "table" and nation.Name or nil
	local flag = type(nation) == "table" and nation.Flag or nil
	n.player:SetAttribute("NationName", name)
	n.player:SetAttribute("NationFlag", flag)
	S.PlotService.setIdentity(n.player, name, flag)
end

local function onSetNation(player: Player, name: any, flag: any)
	local n = Nations.get(player)
	if not n or not n.ready then
		return { ok = false }
	end
	if typeof(name) ~= "string" then
		return { ok = false, err = "Pick a name for your nation" }
	end
	name = cleanName(string.sub(name, 1, 64))
	local len = utf8.len(name) or #name
	if len < Config.NationNameMin or len > Config.NationNameMax then
		return { ok = false, err = ("Names are %d-%d characters"):format(Config.NationNameMin, Config.NationNameMax) }
	end
	if not string.match(name, NAME_CHARS) then
		return { ok = false, err = "Use letters, numbers, spaces, - ' or ." }
	end
	local data = typeof(flag) == "string" and Flag.decode(flag) or Flag.sanitize(flag)
	local ok, filtered = pcall(function()
		local result = TextService:FilterStringAsync(name, player.UserId, Enum.TextFilterContext.PublicChat)
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not ok then
		return { ok = false, err = "Couldn't check that name, try again" }
	end
	if filtered ~= name then
		return { ok = false, err = "That name isn't allowed, try another" }
	end
	local founded = n.data.Nation == nil
	n.data.Nation = { Name = filtered, Flag = Flag.encode(data) }
	NationService.apply(n)
	if founded then
		Nations.notifyAll(("%s founded the nation of %s"):format(player.DisplayName, filtered), "info")
	end
	S.StateService.push(n)
	return { ok = true, name = filtered, flag = n.data.Nation.Flag }
end

function NationService.compute(n: Nation): Rank.Info
	local value = 0
	for _, b in n.buildings do
		if not b.finishAt then
			value += b.cost
		end
	end
	local techs = 0
	for _ in n.data.Researched do
		techs += 1
	end
	local held = 0
	for _, p in S.ConquestService.points() do
		if p.owner == n.userId then
			held += 1
		end
	end
	return Rank.of(Rank.power({
		pop = n.data.Population,
		buildingValue = value,
		researched = techs,
		units = S.UnitService.count(n),
		points = held,
	}))
end

-- Called from the economy tick (once per second per nation).
function NationService.tick(n: Nation, _now: number)
	local info = NationService.compute(n)
	n.stats.rank = info
	local data = n.data
	local best = data.RankLevel or 1
	if info.level > best then
		for level = best + 1, info.level do
			local r = Config.Ranks[level]
			data.Cash += r.reward
			Nations.notify(n.player, ("RANK UP · %s  +%s"):format(string.upper(r.name), Format.cash(r.reward)), "good")
		end
		data.RankLevel = info.level
		Net.event("Effect"):FireClient(n.player, "RankUp", info.level)
		if info.level >= 4 then
			Nations.notifyAll(("%s is now a %s"):format(data.Nation and data.Nation.Name or n.player.DisplayName, info.name), "info")
		end
	end
	if n.player:GetAttribute("Power") ~= info.power then
		n.player:SetAttribute("Power", info.power)
	end
	if n.player:GetAttribute("RankName") ~= info.name then
		n.player:SetAttribute("RankName", info.name)
	end
end

function NationService.onJoin(n: Nation)
	NationService.apply(n)
	NationService.tick(n, Nations.now())
end

function NationService.snapshot(n: Nation): (any, any)
	local nation = n.data.Nation
	local rank = n.stats.rank or Rank.of(0)
	local outNation: any = false
	if type(nation) == "table" then
		outNation = { name = nation.Name, flag = nation.Flag }
	end
	return outNation, rank
end

function NationService.init(services)
	S = services
end

function NationService.start()
	Net.handle("SetNation", onSetNation, 2)
end

return NationService
