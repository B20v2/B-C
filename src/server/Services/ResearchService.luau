--[[
	ResearchService
	One active research at a time. RP and cash are paid up front; the timer
	keeps running while offline (finishAt is an absolute time).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Research = require(Shared.Catalog.Research)
local Nations = require(script.Parent.Nations)

type Nation = Nations.Nation

local ResearchService = {}
local S: { [string]: any }

function ResearchService.canStart(n: Nation, id: string): (boolean, string?)
	local def = Research.get(id)
	if not def then
		return false, "Unknown research"
	end
	local data = n.data
	if data.Researched[id] then
		return false, "Already researched"
	end
	if data.ActiveResearch then
		return false, "Already researching something"
	end
	for _, req in def.requires do
		if not data.Researched[req] then
			local r = Research.get(req)
			return false, "Requires " .. (r and r.name or req)
		end
	end
	if def.hits and data.Stats.Hits < def.hits then
		return false, ("Requires %d hits (you have %d)"):format(def.hits, data.Stats.Hits)
	end
	if data.ResearchPoints < def.rp then
		return false, "Not enough research points"
	end
	if data.Cash < def.cash then
		return false, "Not enough cash"
	end
	return true, nil
end

function ResearchService.complete(n: Nation)
	local active = n.data.ActiveResearch
	if not active then
		return
	end
	n.data.Researched[active.id] = true
	n.data.ActiveResearch = nil
	local def = Research.get(active.id)
	Nations.notify(n.player, "Research complete: " .. (def and def.name or active.id), "good")
	Net.event("Effect"):FireClient(n.player, "ResearchDone", nil, def and def.name or active.id)
end

function ResearchService.tick(n: Nation, now: number)
	local active = n.data.ActiveResearch
	if active and now >= active.finishAt then
		ResearchService.complete(n)
	end
end

local function onStart(player: Player, id: any)
	local n = Nations.get(player)
	if not n or typeof(id) ~= "string" then
		return { ok = false, err = "Invalid request" }
	end
	local ok, err = ResearchService.canStart(n, id)
	if not ok then
		return { ok = false, err = err }
	end
	local def = Research.get(id)
	if not def then
		return { ok = false }
	end
	n.data.ResearchPoints -= def.rp
	n.data.Cash -= def.cash
	local now = Nations.now()
	n.data.ActiveResearch = { id = id, startAt = now, finishAt = now + def.time / Nations.speed(n) }
	S.StateService.push(n)
	return { ok = true }
end

function ResearchService.init(services)
	S = services
end

function ResearchService.start()
	Net.handle("StartResearch", onStart, 4)
end

return ResearchService
