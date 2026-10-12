--[[
	DataService
	Loads and saves player data with DataStoreService.

	  * Session lock: a profile records which server owns it. Another server
	    will wait (and eventually steal a stale lock) instead of loading a
	    copy, so items can't be duplicated by server hopping.
	  * Autosave every 2 minutes, on leave and on shutdown (BindToClose).
	  * Missing fields are filled from the template so new features never
	    break old saves.
	  * In Studio without API access the game still runs (data just isn't
	    persisted) so you can test immediately.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local DataService = {}

local AUTOSAVE_INTERVAL = 120
local LOCK_EXPIRE = 300

local store: DataStore? = nil
local storeOk = false
local profiles: { [Player]: { [string]: any } } = {}
local loadedCallbacks: { (Player, { [string]: any }) -> () } = {}
local beforeSaveCallbacks: { (Player, { [string]: any }) -> () } = {}
local releasing: { [Player]: boolean } = {}

local function template(): { [string]: any }
	return {
		Version = Config.DataVersion,
		Cash = Config.StartCash,
		Population = 0,
		ResearchPoints = 0,
		Researched = {},
		ActiveResearch = nil,
		Buildings = {},
		NextUid = 1,
		Inventory = {},
		Units = {},
		Oil = 0,
		Steel = 0,
		Stats = { Hits = 0, Launches = 0, Captures = 0, Kills = 0, TotalEarned = 0, PlayTime = 0 },
		Pvp = false,
		FirstJoin = 0,
		LastOnline = 0,
		LastPay = 0,
		Daily = { Streak = 0, LastDay = 0 },
		Quest = 1,
		Flags = {},
		BoostUntil = 0,
		Redeemed = {},
		Receipts = {},
		Billboard = "",
	}
end

local function reconcile(data: { [string]: any }, tmpl: { [string]: any })
	for k, v in tmpl do
		if data[k] == nil then
			if type(v) == "table" then
				data[k] = table.clone(v)
			else
				data[k] = v
			end
		elseif type(v) == "table" and type(data[k]) == "table" and next(v) ~= nil then
			reconcile(data[k], v)
		end
	end
end

local function keyFor(player: Player): string
	return "player_" .. player.UserId
end

local function now(): number
	return os.time()
end

local function tryLoad(player: Player): { [string]: any }?
	local s = store
	if not s then
		return nil
	end
	local result: { [string]: any }? = nil
	local attempts = 0
	while attempts < 8 and player.Parent do
		attempts += 1
		local stolen = false
		local ok, err = pcall(function()
			s:UpdateAsync(keyFor(player), function(old)
				local data = old or template()
				local lock = data._lock
				if lock and lock.job ~= game.JobId and now() - (lock.t or 0) < LOCK_EXPIRE then
					-- another server still owns this profile
					result = nil
					return nil
				end
				stolen = lock ~= nil and lock.job ~= game.JobId
				data._lock = { job = game.JobId, t = now() }
				result = data
				return data
			end)
		end)
		if ok and result then
			if stolen then
				warn(("[Data] Took over a stale session lock for %s"):format(player.Name))
			end
			return result
		elseif not ok then
			warn(("[Data] Load attempt %d failed for %s: %s"):format(attempts, player.Name, tostring(err)))
		end
		task.wait(attempts < 3 and 2 or 6)
	end
	return nil
end

local function save(player: Player, release: boolean): boolean
	local data = profiles[player]
	local s = store
	if not data or not s then
		return false
	end
	for _, cb in beforeSaveCallbacks do
		local ok, err = pcall(cb, player, data)
		if not ok then
			warn("[Data] beforeSave failed: " .. tostring(err))
		end
	end
	data.LastOnline = now()
	data._lock = (not release) and { job = game.JobId, t = now() } or nil
	local payload = data
	local ok, err = false, nil
	for _ = 1, 3 do
		ok, err = pcall(function()
			s:UpdateAsync(keyFor(player), function(old)
				if old and old._lock and old._lock.job ~= game.JobId then
					-- someone else took this profile; never overwrite it
					return nil
				end
				return payload
			end)
		end)
		if ok then
			break
		end
		task.wait(1)
	end
	if not ok then
		warn(("[Data] Save failed for %s: %s"):format(player.Name, tostring(err)))
	end
	return ok
end

function DataService.get(player: Player): { [string]: any }?
	return profiles[player]
end

function DataService.onLoaded(cb: (Player, { [string]: any }) -> ())
	table.insert(loadedCallbacks, cb)
	for p, data in profiles do
		task.spawn(cb, p, data)
	end
end

-- Lets runtime services write their live state into the profile right before it saves.
function DataService.beforeSave(cb: (Player, { [string]: any }) -> ())
	table.insert(beforeSaveCallbacks, cb)
end

function DataService.save(player: Player)
	task.spawn(save, player, false)
end

-- Final save when a player leaves. beforeSave callbacks run synchronously
-- (before the first yield) so callers can tear down runtime state right after.
function DataService.release(player: Player)
	if profiles[player] and not releasing[player] then
		releasing[player] = true
		task.spawn(function()
			save(player, true)
			profiles[player] = nil
			releasing[player] = nil
		end)
	end
end

function DataService.isPersistent(): boolean
	return storeOk
end

local function onPlayerAdded(player: Player)
	local data: { [string]: any }?
	if storeOk then
		data = tryLoad(player)
		if not data then
			if player.Parent then
				player:Kick("Could not load your nation. Please rejoin in a moment.")
			end
			return
		end
	else
		data = template()
	end
	local profile = data :: { [string]: any }
	if not player.Parent then
		-- left while loading: release the session lock we just took
		if storeOk then
			profiles[player] = profile
			save(player, true)
			profiles[player] = nil
		end
		return
	end
	reconcile(profile, template())
	if profile.FirstJoin == 0 then
		profile.FirstJoin = now()
	end
	profiles[player] = profile
	for _, cb in loadedCallbacks do
		task.spawn(cb, player, profile)
	end
end

function DataService.init(_S)
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
		-- In Studio, a quick read tells us whether API access is enabled.
		local readOk = pcall(function()
			(result :: DataStore):GetAsync("__probe")
		end)
		storeOk = readOk
		if not readOk then
			warn("[Data] DataStores unavailable (enable Studio API access to save). Running without saving.")
		end
	else
		warn("[Data] DataStores unavailable: " .. tostring(result))
	end
end

function DataService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayerAdded, p)
	end


	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for player in profiles do
				task.spawn(save, player, false)
				task.wait(0.5)
			end
		end
	end)

	game:BindToClose(function()
		if RunService:IsStudio() and not storeOk then
			return
		end
		local pending = 0
		for player in profiles do
			if not releasing[player] then
				pending += 1
				task.spawn(function()
					save(player, true)
					pending -= 1
				end)
			end
		end
		local start = os.clock()
		while pending > 0 and os.clock() - start < 25 do
			task.wait(0.2)
		end
	end)
end

return DataService
