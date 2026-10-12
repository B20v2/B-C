--[[
	Nations
	Runtime registry of every player's nation (live state that is not just
	saved data: building instances, occupancy grid, computed stats, timers).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

export type BRuntime = {
	uid: number,
	id: string,
	def: any,
	x: number, -- island-local studs (footprint centre)
	z: number,
	r: number, -- yaw in degrees
	len: number?, -- road segments: length in studs
	cost: number, -- what was paid (roads scale with length)
	model: Model?,
	finishAt: number?,
	startAt: number?,
	damaged: boolean,
	hp: number,
	oil: number,
	fuel: number,
	incoming: number,
	dest: number,
	trucks: { { state: string, target: number, amount: number, arriveAt: number, returnAt: number } },
	queue: { { id: string, kind: string, progress: number, started: boolean } },
	reloadUntil: number,
	connected: boolean,
	crop: string?, -- farm fields
	growth: number?,
	auto: boolean?,
	lastCrop: string?,
	eff: number,
	status: string,
}

export type Nation = {
	player: Player,
	userId: number,
	data: { [string]: any },
	plotIndex: number,
	origin: Vector3,
	frame: CFrame, -- island frame; -Z faces the battlefield
	folder: Folder,
	buildings: { [number]: BRuntime },
	grid: { [number]: { [number]: boolean } }, -- spatial hash (Footprint)
	stats: { [string]: any },
	passes: { [string]: boolean },
	premium: boolean,
	joinAt: number,
	nextPayAt: number,
	giftAt: number,
	pvpLockUntil: number,
	shieldUntil: number,
	undo: { { [string]: any } },
	units: { [number]: any },
	fobs: { any },
	nextUnitUid: number,
	sent: { [string]: string },
	ready: boolean,
}

local Nations = {}

local byPlayer: { [Player]: Nation } = {}

function Nations.now(): number
	return workspace:GetServerTimeNow()
end

function Nations.add(n: Nation)
	byPlayer[n.player] = n
end

function Nations.remove(player: Player)
	byPlayer[player] = nil
end

function Nations.get(player: Player): Nation?
	return byPlayer[player]
end

function Nations.all(): { [Player]: Nation }
	return byPlayer
end

function Nations.byUserId(userId: number): Nation?
	local p = Players:GetPlayerByUserId(userId)
	return p and byPlayer[p] or nil
end

-- kind: "info" | "good" | "bad" | "pay"
function Nations.notify(player: Player, text: string, kind: string?)
	Net.event("Notify"):FireClient(player, text, kind or "info")
end

function Nations.notifyAll(text: string, kind: string?)
	Net.event("Notify"):FireAllClients(text, kind or "info")
end

function Nations.hasPass(n: Nation, key: string): boolean
	return n.passes[key] == true
end

-- Multiplier for construction, research and factory speed.
function Nations.speed(n: Nation): number
	return n.passes.FastBuild and 2 or 1
end

-- Finished buildings of a type. Road segments count per 8-stud tile of length.
function Nations.countBuilt(n: Nation, id: string): number
	local c = 0
	for _, b in n.buildings do
		if b.id == id and not b.finishAt then
			if b.len then
				c += math.max(1, math.floor(b.len / 8 + 0.5))
			else
				c += 1
			end
		end
	end
	return c
end

function Nations.countAll(n: Nation, id: string): number
	local c = 0
	for _, b in n.buildings do
		if b.id == id then
			c += 1
		end
	end
	return c
end

-- Finished, undamaged building.
function Nations.isActive(b: BRuntime): boolean
	return b.finishAt == nil and not b.damaged
end

return Nations
