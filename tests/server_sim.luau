--!nocheck
-- End-to-end server simulation in Lune with mocked Roblox services. Run via tests/run.sh.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local stdtask = require("@lune/task")

local Instance, Vector3, CFrame, Enum = roblox.Instance, roblox.Vector3, roblox.CFrame, roblox.Enum

---------------------------------------------------------------- shims
local function bbox(model)
	local minV, maxV
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local p = d.CFrame.Position
			local h = d.Size / 2
			local lo, hi = p - h, p + h
			minV = minV and Vector3.new(math.min(minV.X, lo.X), math.min(minV.Y, lo.Y), math.min(minV.Z, lo.Z)) or lo
			maxV = maxV and Vector3.new(math.max(maxV.X, hi.X), math.max(maxV.Y, hi.Y), math.max(maxV.Z, hi.Z)) or hi
		end
	end
	return minV, maxV
end
roblox.implementMethod("Model", "GetPivot", function(self)
	if self.PrimaryPart then return self.PrimaryPart.CFrame end
	local lo, hi = bbox(self)
	return CFrame.new(lo and (lo + hi) / 2 or Vector3.zero)
end)
roblox.implementMethod("Model", "PivotTo", function(self, cf)
	local delta = cf * self:GetPivot():Inverse()
	for _, d in self:GetDescendants() do
		if d:IsA("BasePart") then d.CFrame = delta * d.CFrame end
	end
end)
roblox.implementMethod("Model", "TranslateBy", function(self, v)
	for _, d in self:GetDescendants() do
		if d:IsA("BasePart") then d.CFrame = d.CFrame + v end
	end
end)
roblox.implementMethod("Model", "GetBoundingBox", function(self)
	local lo, hi = bbox(self)
	return CFrame.new((lo + hi) / 2), hi - lo
end)
roblox.implementProperty("Part", "Position", function(self) return self.CFrame.Position end, function(self, v)
	self.CFrame = CFrame.new(v) * (self.CFrame - self.CFrame.Position)
end)
roblox.implementMethod("Part", "SetNetworkOwner", function() end)

for _, cls in { "Folder", "Model", "Player", "Part", "Workspace", "ReplicatedStorage", "Script", "ModuleScript" } do
	roblox.implementMethod(cls, "WaitForChild", function(self, name)
		local c = self:FindFirstChild(name)
		assert(c, "WaitForChild would hang: " .. name .. " in " .. self:GetFullName())
		return c
	end)
end

local serverNow = 1000000
roblox.implementMethod("Workspace", "GetServerTimeNow", function() return serverNow end)

-- signals
local function Signal()
	local s = { fns = {} }
	function s:Connect(fn)
		table.insert(self.fns, fn)
		return { Disconnect = function() end }
	end
	function s:Fire(...)
		for _, fn in self.fns do fn(...) end
	end
	return s
end

local playerSignals = {}
local function psig(p, name)
	playerSignals[p] = playerSignals[p] or {}
	playerSignals[p][name] = playerSignals[p][name] or Signal()
	return playerSignals[p][name]
end
roblox.implementProperty("Player", "CharacterAdded", function(self) return psig(self, "CharacterAdded") end)
roblox.implementProperty("Player", "MembershipType", function() return Enum.MembershipType.None end)
local kicked = {}
roblox.implementMethod("Player", "Kick", function(self, msg) kicked[self.Name] = msg end)
roblox.implementMethod("Player", "IsInGroup", function() return true end)

-- remotes
local invokers = {}
roblox.implementProperty("RemoteFunction", "OnServerInvoke", function(self) return invokers[self.Name] end, function(self, fn) invokers[self.Name] = fn end)
local sent = {} -- [eventName] = list of {player, args}
roblox.implementMethod("RemoteEvent", "FireClient", function(self, player, ...)
	sent[self.Name] = sent[self.Name] or {}
	table.insert(sent[self.Name], { player = player, args = { ... } })
end)
roblox.implementMethod("RemoteEvent", "FireAllClients", function(self, ...)
	sent[self.Name] = sent[self.Name] or {}
	table.insert(sent[self.Name], { player = "all", args = { ... } })
end)

---------------------------------------------------------------- place + services
local place = roblox.deserializePlace(fs.readFile(process.args[1]))
local Workspace = place:FindFirstChildOfClass("Workspace")
local ReplicatedStorage = place:FindFirstChildOfClass("ReplicatedStorage")
local ServerScriptService = place:FindFirstChildOfClass("ServerScriptService")

local playerList = {}
local Players = {
	PlayerAdded = Signal(),
	PlayerRemoving = Signal(),
	PlayerMembershipChanged = Signal(),
}
function Players:GetPlayers() return table.clone(playerList) end
function Players:GetPlayerByUserId(id)
	for _, p in playerList do if p.UserId == id then return p end end
	return nil
end

local stores = {}
local DataStoreService = {}
function DataStoreService:GetDataStore(name)
	stores[name] = stores[name] or { data = {} }
	local st = stores[name]
	return {
		GetAsync = function(_, key) return st.data[key] end,
		UpdateAsync = function(_, key, fn)
			-- deep copy through JSON to mimic serialization
			local old = st.data[key] and serde.decode("json", serde.encode("json", st.data[key])) or nil
			local new = fn(old)
			if new ~= nil then st.data[key] = serde.decode("json", serde.encode("json", new)) end
			return new
		end,
	}
end

local Marketplace = { PromptGamePassPurchaseFinished = Signal() }
function Marketplace:UserOwnsGamePassAsync() return false end

local services = {
	Players = Players,
	DataStoreService = DataStoreService,
	MarketplaceService = Marketplace,
	ReplicatedStorage = ReplicatedStorage,
	ServerScriptService = ServerScriptService,
	Workspace = Workspace,
	Lighting = place:FindFirstChildOfClass("Lighting"),
	RunService = { IsStudio = function() return true end, IsServer = function() return true end, Heartbeat = Signal() },
	HttpService = {
		JSONEncode = function(_, v) return serde.encode("json", v) end,
		JSONDecode = function(_, s) return serde.decode("json", s) end,
	},
	TextService = {
		FilterStringAsync = function(_, text)
			return { GetNonChatStringForBroadcastAsync = function() return text end }
		end,
	},
}
local bindToClose = {}
local game = { JobId = "test-job" }
function game:GetService(name)
	local s = services[name]
	assert(s, "unmocked service " .. name)
	return s
end
function game:BindToClose(fn) table.insert(bindToClose, fn) end

-- fake task: loops that wait >0 freeze (we drive them by hand); delays run on fake time
local delayed = {}
local fakeTask = {
	spawn = stdtask.spawn,
	defer = stdtask.spawn,
	delay = function(t, fn, ...)
		table.insert(delayed, { at = serverNow + t, fn = fn, args = { ... } })
	end,
	wait = function(t)
		if t == nil or t == 0 then return 0 end
		coroutine.yield() -- never resumed: background loops stay frozen
	end,
}

local errors = 0
fakeClock = 0
local cache = {}
local env = {
	Instance = Instance, Vector3 = Vector3, Vector2 = roblox.Vector2, CFrame = CFrame, Color3 = roblox.Color3,
	UDim2 = roblox.UDim2, UDim = roblox.UDim, Enum = Enum, Font = roblox.Font, NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint, ColorSequence = roblox.ColorSequence, ColorSequenceKeypoint = roblox.ColorSequenceKeypoint, NumberRange = roblox.NumberRange,
	game = game, workspace = Workspace, task = fakeTask, typeof = typeof,
	warn = function(...) errors += 1 print("WARN:", ...) end,
	os = { clock = function() return fakeClock end, time = os.time, date = os.date },
	print = print,
}
local Random = {}
Random.__index = Random
function Random.new(seed) return setmetatable({ s = (seed or 12345) % 2147483647 + 1 }, Random) end
function Random:_n() self.s = (self.s * 16807) % 2147483647 return self.s / 2147483647 end
function Random:NextNumber(a, b) a, b = a or 0, b or 1 return a + (b - a) * self:_n() end
function Random:NextInteger(a, b) return math.floor(a + (b - a + 1) * self:_n()) end
env.Random = Random

local function load(script)
	local key = script:GetFullName()
	if cache[key] then return cache[key] end
	local e = { script = script }
	for k, v in env do e[k] = v end
	e.require = load
	local fn = luau.load(script.Source, { debugName = script:GetFullName(), environment = e })
	local result = fn()
	cache[key] = result
	return result
end

---------------------------------------------------------------- boot
local Server = ServerScriptService:FindFirstChild("Server")
load(Server:FindFirstChild("Main"))
local Svc = Server:FindFirstChild("Services")
local S = {}
for _, m in Svc:GetChildren() do S[m.Name] = load(m) end
local Nations = S.Nations

local failures = 0
local function check(cond, msg)
	if cond then print("  ok  " .. msg) else failures += 1 print("FAIL  " .. msg) end
end

local function call(name, player, ...)
	local fn = invokers[name]
	assert(fn, "no handler " .. name)
	fakeClock += 0.5
	local r = fn(player, ...)
	return r
end

local function advance(seconds)
	for _ = 1, seconds do
		serverNow += 1
		S.EconomyService._tick(1)
		S.ConquestService._step(1)
		S.UnitService._combatStep()
		S.UnitService._combatStep()
		local due = {}
		for i = #delayed, 1, -1 do
			if delayed[i].at <= serverNow then table.insert(due, table.remove(delayed, i)) end
		end
		for _, d in due do stdtask.spawn(d.fn, table.unpack(d.args)) end
	end
end

local function newPlayer(id, name)
	local p = Instance.new("Player")
	p.UserId = id
	p.Name = name
	p.DisplayName = name
	p.Parent = place:FindFirstChildOfClass("Players") or place
	table.insert(playerList, p)
	Players.PlayerAdded:Fire(p)
	return p
end

print("== join")
local A = newPlayer(101, "Alpha")
local B = newPlayer(202, "Bravo")
stdtask.wait(0.1)
local nA, nB = Nations.get(A), Nations.get(B)
check(nA and nA.ready, "Alpha nation ready")
check(nB and nB.ready, "Bravo nation ready")
check(nA.plotIndex ~= nB.plotIndex, "different plots")
check(sent.State and #sent.State > 0, "state pushed to client")
check(A:FindFirstChild("leaderstats") ~= nil, "leaderstats")

print("== early economy (free-form building)")
-- positions are island-local studs (footprint centre) + yaw in degrees
local function place_(p, id, x, z, a)
	local res = call("PlaceBuilding", p, id, x, z, a or 0)
	if not res.ok then print("    place " .. id .. " failed: " .. tostring(res.err)) end
	return res
end
local res = call("PlaceRoad", A, "road", -200, -160, -152, -160)
check(res.ok and res.cost == 240, "draw a 48-stud road (6 tiles) " .. tostring(res.err) .. " " .. tostring(res.cost))
check(nA.buildings[res.uid].len == 48 and nA.buildings[res.uid].r == 90, "road segment length + heading")
check(not call("PlaceRoad", A, "road", 0, 0, 0, 400).ok, "over-long road rejected")
local junction = call("PlaceRoad", A, "road", -176, -160, -176, -200)
check(junction.ok, "roads may cross / join other roads")
check(place_(A, "small_house", -196, -152).ok, "house 1")
check(place_(A, "small_house", -188, -152).ok, "house 2")
check(place_(A, "small_house", -160, -152).ok, "house 3")
check(not place_(A, "small_house", -160, -152).ok, "overlap rejected")
check(call("PlaceBuilding", A, "small_house", -164, -160, 0).err == "Can't build on a road", "can't build on a road")
check(not place_(A, "small_house", 238, 238).ok, "out of bounds rejected")
check(call("PlaceBuilding", A, "small_house", -146, -160, 0).err == "Can't build on a road", "road end caps block buildings")
local rot = place_(A, "small_house", -120, -152, 37)
check(rot.ok and nA.buildings[rot.uid].r == 37, "any angle")
check(not place_(A, "apartment", 60, 60).ok, "locked research rejected")
check(place_(A, "wind_turbine", -100, -120).ok, "turbine")
check(place_(A, "water_tower", -88, -120).ok, "water tower")
local cash0 = nA.data.Cash
advance(12)
check(nA.data.Population > 0, ("population grows (%.1f)"):format(nA.data.Population))
local houses = 0
for _, b in nA.buildings do if b.id == "small_house" and not b.finishAt then houses += 1 end end
check(houses == 4, "houses finished construction")
local connected = 0
for _, b in nA.buildings do if b.id == "small_house" and b.connected then connected += 1 end end
check(connected >= 3, ("houses beside the road are connected (%d)"):format(connected))
advance(60)
check(nA.data.Cash ~= cash0, ("pay day changed cash (%d -> %d)"):format(cash0, nA.data.Cash))
check(sent.Notify and #sent.Notify > 0, "notifications sent")
local q = nA.data.Quest
check(call("ClaimQuest", A).ok, "claim quest 1 (roads)")
check(nA.data.Quest == q + 1, "quest advanced")

print("== undo / move / delete")
local r1 = place_(A, "park", 40, 40)
check(r1.ok, "park placed")
local cBefore = nA.data.Cash
check(call("Undo", A).ok, "undo place")
check(nA.data.Cash == cBefore + 2000, "undo refunded")
local r2 = place_(A, "shop", 40, 40)
check(call("MoveBuilding", A, r2.uid, 80, 80, 45).ok, "move shop")
check(nA.buildings[r2.uid].x == 80 and nA.buildings[r2.uid].r == 45, "moved coords")
check(nA.buildings[r2.uid].model:GetAttribute("Angle") == 45, "model carries placement attrs")
check(call("DeleteBuilding", A, r2.uid).ok, "delete shop")
check(nA.buildings[r2.uid] == nil, "shop gone")
local rowRes = call("PlaceMany", A, "small_house", { { 120, -200 }, { 128, -200 }, { 136, -200 } }, 0)
check(rowRes.ok and rowRes.placed == 3, "row of houses")

print("== research + industry")
nA.data.Cash = 50000000
nA.data.ResearchPoints = 100000
local function research(p, id)
	local r = call("StartResearch", p, id)
	if not r.ok then print("    research err", id, r.err) end
	advance(400)
	return Nations.get(p).data.Researched[id] == true
end
check(research(A, "military_doctrine"), "research military doctrine")
check(research(A, "heavy_industry"), "research heavy industry")
check(research(A, "ballistics"), "research ballistics")
check(research(A, "mechanized"), "research mechanized")
check(not call("StartResearch", A, "cruise_missiles").ok, "cruise missiles gated by hits")

-- power + water + roads for industry
check(call("PlaceRoad", A, "road", -220, 100, 20, 100).ok, "240-stud road")
for i = 0, 9 do place_(A, "wind_turbine", -210 + i * 10, 108) end
for i = 0, 5 do place_(A, "apartment", -210 + i * 26, 140) end -- needs urban planning -> fails, fine
for i = 0, 7 do place_(A, "small_house", -210 + i * 10, 120) end
check(place_(A, "oil_pump", -210, 90).ok, "oil pump")
check(place_(A, "oil_pump", -198, 90).ok, "oil pump 2")
local ref = place_(A, "small_refinery", -170, 80)
check(ref.ok, "refinery")
local fac = place_(A, "small_military_factory", -130, 76)
check(fac.ok, "military factory")
local lau = place_(A, "srbm_launcher", 100, 100)
check(lau.ok, "srbm launcher")
advance(60)
local refB = nA.buildings[ref.uid]
check(refB.finishAt == nil, "refinery built")
advance(120)
check(refB.fuel > 0 or nA.buildings[fac.uid].fuel > 0, ("fuel produced (ref %.0f, fac %.0f)"):format(refB.fuel, nA.buildings[fac.uid].fuel))
check(refB.model:GetAttribute("Status") ~= nil, "refinery status: " .. tostring(refB.model:GetAttribute("Status")))
check(call("SetFuelDestination", A, ref.uid, fac.uid).ok, "set fuel destination")
nA.data.Steel = 5000
for _ = 1, 3 do check(call("QueueProduction", A, fac.uid, "weapon", "SRBM").ok, "queue SRBM") end
check(call("QueueProduction", A, fac.uid, "unit", "marder").ok, "queue Marder")
advance(300)
print(("    factory fuel %.0f, queue %d, status %s"):format(nA.buildings[fac.uid].fuel, #nA.buildings[fac.uid].queue, tostring(nA.buildings[fac.uid].model:GetAttribute("Status"))))
check((nA.data.Inventory.SRBM or 0) >= 1, ("SRBMs produced: %d"):format(nA.data.Inventory.SRBM or 0))

print("== strike mainland")
nA.data.Inventory.SRBM = 10
local Config = load(ReplicatedStorage.Shared.Config)
local WarMap = load(ReplicatedStorage.Shared.Catalog.WarMap)
local target = Config.MainlandOrigin + WarMap[2].offset
local pts = S.ConquestService.points()
local g0 = pts[2].garrison
local lr = call("LaunchWeapon", A, "SRBM", target)
check(lr.ok, "launch at airport " .. tostring(lr.err))
check(sent.Projectile and #sent.Projectile >= 1, "projectile broadcast")
check(not call("LaunchWeapon", A, "SRBM", target).ok, "single launcher reloading")
advance(15)
check(pts[2].garrison < g0, ("garrison damaged %d -> %d"):format(g0, pts[2].garrison))
check(nA.data.Stats.Hits >= 1, "hit counted")

print("== PvP")
check(not call("LaunchWeapon", A, "SRBM", nB.origin).ok, "pvp off blocks")
call("SetPvp", A, true)
call("SetPvp", B, true)
advance(25)
local blocked = call("LaunchWeapon", A, "SRBM", nB.origin)
check(not blocked.ok and blocked.err:find("shield") ~= nil, "new nation shield blocks: " .. tostring(blocked.err))
nB.shieldUntil = 0
local hb = place_(B, "small_house", 0, 0)
advance(10)
local hbB = nB.buildings[hb.uid]
local center = S.BuildService.worldCFrame(nB, hbB).Position
advance(25)
local pr = call("LaunchWeapon", A, "SRBM", center)
check(pr.ok, "strike Bravo " .. tostring(pr.err))
advance(15)
check(hbB.damaged or hbB.hp < hbB.def.hp, ("Bravo house damaged (hp %.0f)"):format(hbB.hp))
check(not call("SetPvp", A, false).ok, "pvp lock after attacking")
if hbB.damaged then
	check(call("RepairBuilding", B, hb.uid).ok, "repair")
end

print("== units: drive over the bridges, capture, raid")
local Grid = load(ReplicatedStorage.Shared.Util.Grid)
check(S.UnitService.count(nA) >= 1, ("units: %d"):format(S.UnitService.count(nA)))
local u
for _, unit in nA.units do u = unit end
if u then
	check(u.location == "home", "unit starts at home")
	local cr = call("CommandUnits", A, { u.uid }, target)
	check(cr.ok, "command unit to airport")
	-- the route leaves through this nation's gate and bridge
	local function passes(path, p)
		for _, w in path do
			if (Vector3.new(w.X, 0, w.Z) - Vector3.new(p.X, 0, p.Z)).Magnitude < 1 then return true end
		end
		return false
	end
	local remaining = table.clone(u.path)
	table.insert(remaining, 1, u.align.Position)
	check(passes(remaining, Grid.gate(nA.plotIndex)) and passes(remaining, Grid.shore(nA.plotIndex)), "routed over own bridge")
	check(not call("CommandUnits", A, { u.uid }, Config.MainlandOrigin + Vector3.new(2250, 0, 0)).ok, "can't drive into the sea")
	-- physics isn't simulated: teleport onto the point
	u.model:PivotTo(CFrame.new(target + Vector3.new(0, u.height, 0)))
	u.path = {}
	S.UnitService._moveStep()
	check(u.location == "mainland", "unit on the battlefield")
	pts[2].garrison = 0
	advance(60)
	check(pts[2].owner == nA.userId, ("airport captured (capture %.0f, owner %d)"):format(pts[2].capture, pts[2].owner))
	local bonus = S.ConquestService.bonusFor(nA)
	check(bonus.income > 0, "capture bonus applies")

	-- raid Bravo's city
	call("SetPvp", B, false)
	local houseB = nB.buildings[hb.uid]
	local nearHouse = S.BuildService.worldCFrame(nB, houseB).Position + Vector3.new(14, 0, 0)
	local blockedRaid = call("CommandUnits", A, { u.uid }, nearHouse)
	check(not blockedRaid.ok and (blockedRaid.err or ""):find("PvP OFF") ~= nil, "no raid on PvP OFF city: " .. tostring(blockedRaid.err))
	call("SetPvp", B, true)
	S.BuildService.setDamaged(nB, houseB, false)
	local raid = call("CommandUnits", A, { u.uid }, nearHouse)
	check(raid.ok, "raid order " .. tostring(raid.err))
	local rp = table.clone(u.path)
	table.insert(rp, 1, u.align.Position)
	check(passes(rp, Grid.gate(nB.plotIndex)), "raid route crosses the enemy bridge")
	u.model:PivotTo(CFrame.new(nearHouse + Vector3.new(0, u.height, 0)))
	u.path = {}
	S.UnitService._moveStep()
	check(u.location == "raid", "unit in enemy city")
	for _ = 1, 40 do S.UnitService._combatStep() end
	check(houseB.damaged, ("raiders knock out buildings (hp %.0f)"):format(houseB.hp))
	check(call("RecallUnits", A, nil).ok, "recall")
	check(#u.path >= 3, "recall drives home over the bridges")
end

print("== infantry, transports, FOB, airlift")
for _, id in { "aviation", "mechanized", "military_doctrine" } do nA.data.Researched[id] = true end
nA.data.Cash = 50000000
local bar = place_(A, "barracks", 160, -60)
local pad = place_(A, "helipad", 160, -140)
check(bar.ok and pad.ok, "barracks + helipad placed")
S.BuildService.finishAll(nA)
check(call("QueueProduction", A, bar.uid, "unit", "rifle_squad").ok, "barracks trains a rifle squad")
local wrongQ = call("QueueProduction", A, bar.uid, "weapon", "SRBM")
check(not wrongQ.ok and (wrongQ.err or ""):find("Military Factory") ~= nil, "barracks can't build missiles")
check(not call("QueueProduction", A, fac.uid, "unit", "rifle_squad").ok, "factories don't train infantry")
check(not call("QueueProduction", A, fac.uid, "unit", "chinook").ok, "factories don't build helicopters")
local US = S.UnitService
local sq1 = US.spawn(nA, "rifle_squad")
local sq2 = US.spawn(nA, "at_team")
local hum = US.spawn(nA, "humvee")
local truck = US.spawn(nA, "truck")
local chin = US.spawn(nA, "chinook")
local hawk = US.spawn(nA, "blackhawk")
check(sq1 and sq2 and hum and truck and chin and hawk, "infantry, humvee, truck and helicopters spawn")
check(sq1.model:FindFirstChild("Soldier") ~= nil and sq1.model:FindFirstChild("LeftHip", true) ~= nil, "squads are jointed Roblox soldiers")
check(chin.model:FindFirstChild("FrontRotorJoint", true) ~= nil, "chinook rotors are jointed")
local padPos = S.BuildService.worldCFrame(nA, nA.buildings[pad.uid]).Position
check((Vector3.new(chin.root.CFrame.Position.X, 0, chin.root.CFrame.Position.Z) - Vector3.new(padPos.X, 0, padPos.Z)).Magnitude < 40, "helicopters park at the helipad")
-- mount / dismount
local mres = call("UnitOrder", A, "mount", { sq1.uid, sq2.uid, hum.uid })
check(mres.ok and #hum.cargo == 1, ("squad boards the humvee (%s)"):format(tostring(mres.err)))
local boarded = sq1.carried == hum and sq1 or sq2
check(boarded.model.Parent == nil and hum.model:GetAttribute("Cargo") == 1, "passengers hide inside + cargo tag")
check(US.damage(boarded, 999) == false, "passengers can't be shot")
check(call("UnitOrder", A, "dismount", { hum.uid }).ok and #hum.cargo == 0 and boarded.carried == nil and boarded.model.Parent ~= nil, "dismount")
-- supplies + FOB
nA.data.Food = 400
nA.data.Steel = 5000
local food0 = nA.data.Food
local lres = call("UnitOrder", A, "loadSupplies", { truck.uid })
check(lres.ok and truck.supplies == 150 and nA.data.Food == food0 - 150, ("truck packs 150 supplies (%s)"):format(tostring(lres.err)))
check(not call("UnitOrder", A, "fob", { truck.uid }).ok, "no FOB at home")
local fobSpot = Grid.landing(nA.plotIndex)
truck.model:PivotTo(CFrame.new(fobSpot + Vector3.new(0, truck.height, 0)))
truck.align.Position = fobSpot + Vector3.new(0, truck.height, 0)
US._moveStep()
local cash1 = nA.data.Cash
local fres = call("UnitOrder", A, "fob", { truck.uid })
check(fres.ok and #nA.fobs == 1, "FOB set up on the battlefield " .. tostring(fres.err))
local fob = nA.fobs[1]
check(fob and fob.supplies == 150 and truck.supplies == 0 and nA.data.Cash == cash1 - Config.FobCost, "FOB takes the truck's supplies and costs cash")
check(fob.model.Parent ~= nil and fob.model:GetAttribute("Supplies") == 150, "FOB model on the map")
check(not call("UnitOrder", A, "fob", { truck.uid }).ok, "FOB limit")
check(invokers.GetSnapshot(A).fobs[1].supplies == 150, "FOB in snapshot")
-- FOB heals
sq2.hp = 30
sq2.model:PivotTo(CFrame.new(fob.pos + Vector3.new(10, sq2.height, 0)))
local sup0 = fob.supplies
S.FobService._tick(2)
check(sq2.hp > 30 and fob.supplies < sup0, ("FOB heals from supplies (hp %.0f, supplies %.1f)"):format(sq2.hp, fob.supplies))
sq2.model:PivotTo(CFrame.new(Grid.yard(nA.plotIndex) + Vector3.new(0, sq2.height, 0)))
US._moveStep()
-- airlift: chinook loads squads at home, supplies and the humvee, flies to the FOB, unloads
nA.data.Food = 1000
local supBefore = fob.supplies
US._moveStep()
local ares = call("UnitOrder", A, "airlift", { chin.uid }, "fob")
check(ares.ok, "airlift order " .. tostring(ares.err))
check(#chin.cargo >= 1 and chin.supplies > 0 and chin.slung == hum, ("chinook loaded (%d squads, %d supplies, slung %s)"):format(#chin.cargo, chin.supplies, tostring(chin.slung and chin.slung.def.name)))
check(chin.align.Position.Y == Config.HeliAltitude, "chinook takes off to cruise height")
chin.model:PivotTo(CFrame.new(fob.pos + Vector3.new(0, chin.height, 0)))
for _ = 1, 3 do US._moveStep() end
check(#chin.cargo == 0 and chin.slung == nil and hum.carried == nil, "chinook lands and unloads at the FOB")
check(fob.supplies > supBefore, ("supplies delivered by air (%d -> %d)"):format(supBefore, fob.supplies))
check(hum.location == "mainland", "slung humvee set down on the battlefield")
-- helicopters: only anti-air can hit them; city air defense shoots intruders
local enemyTank = US.spawn(nB, "leopard")
hawk.model:PivotTo(CFrame.new(fob.pos + Vector3.new(30, Config.HeliAltitude, 0)))
enemyTank.model:PivotTo(CFrame.new(fob.pos + Vector3.new(60, enemyTank.height, 0)))
US._moveStep()
local hawkHp = hawk.hp
US._combatStep()
check(hawk.hp == hawkHp, "tanks can't shoot helicopters")
local gep = US.spawn(nB, "gepard")
gep.model:PivotTo(CFrame.new(fob.pos + Vector3.new(50, gep.height, 0)))
US._moveStep()
US._combatStep()
check(hawk.hp < hawkHp, "anti-air hits helicopters")
check(US.versus(sq1, enemyTank) < 0.5 and US.versus(sq2, enemyTank) > 2, "anti-tank teams wreck armour, riflemen don't")
US.remove(enemyTank)
US.remove(gep)
-- save + destroy
S.FobService.serialize(nA)
check(#nA.data.Fobs == 1 and nA.data.Fobs[1].s ~= nil, "FOB saved")
local bCash = nB.data.Cash
S.FobService.damage(fob, 1e6, nB)
check(#nA.fobs == 0 and nB.data.Cash == bCash + 15000, "FOB destroyed pays the attacker")

print("== farming")
local field = place_(A, "farm_field", -40, 200)
local barn = place_(A, "barn", -2, 200)
check(field.ok and barn.ok, "field + barn placed")
S.BuildService.finishAll(nA)
local fb = nA.buildings[field.uid]
check(fb.model:FindFirstChild("FarmPrompt", true) ~= nil, "field has a walk-up prompt")
local cashF = nA.data.Cash
check(call("FarmAction", A, field.uid, "plant", "wheat").ok and fb.crop == "wheat" and nA.data.Cash == cashF - 120, "plant wheat")
check(not call("FarmAction", A, field.uid, "plant", "corn").ok, "can't plant over a crop")
check(not call("FarmAction", A, field.uid, "harvest").ok, "can't harvest unripe")
advance(30)
check(fb.growth > 0.2 and fb.model:GetAttribute("Stage") >= 1, ("crop grows (%.0f%%)"):format(fb.growth * 100))
local crops = fb.model:FindFirstChild("Crops")
check(crops ~= nil and #crops:GetChildren() > 0, "crop rows appear")
for _ = 1, 40 do
	if fb.growth >= 1 then break end
	advance(10)
end
check(fb.growth >= 1 and fb.model:GetAttribute("Stage") == 3, ("crop ripens (%.0f%%)"):format(fb.growth * 100))
nA.data.Food = 0
local hres = call("HarvestAll", A)
check(hres.ok and hres.food == 90 and nA.data.Food == 90 and nA.data.Stats.Harvests == 1, "harvest all fields -> food")
check(fb.crop == nil, "field empties after harvest")
call("FarmAction", A, field.uid, "auto")
call("FarmAction", A, field.uid, "plant", "potatoes")
for _ = 1, 60 do
	if fb.growth >= 1 then break end
	advance(10)
end
call("FarmAction", A, field.uid, "harvest")
check(fb.crop == "potatoes" and fb.auto == true, "auto-replant")
nA.data.Food = nA.stats.foodCap
local cashO = nA.data.Cash
S.FarmService.addFood(nA, 100)
check(nA.data.Cash == cashO + 100 * Config.FoodPrice, "overflow food is sold")
nA.data.Food = 1000
local eat = nA.data.Population * Config.FoodPerCitizen
S.FarmService.payDay(nA)
check(math.abs(nA.data.Food - (1000 - eat)) < 0.01 and nA.stats.fed == true, ("citizens eat (%.1f food)"):format(eat))
local sres = call("SellFood", A)
check(sres.ok and nA.data.Food == 0, "sell food")
S.BuildService.serialize(nA)
local savedField
for _, e in nA.data.Buildings do if e.u == field.uid then savedField = e end end
check(savedField and savedField.cr == "potatoes" and savedField.ar == true, "field state saved")

print("== monetization + rewards")
check(call("StudioPurchase", A, "pass", "DoubleCash").ok, "studio pass purchase")
check(nA.passes.DoubleCash == true, "2x cash owned")
local c1 = nA.data.Cash
check(call("StudioPurchase", A, "product", "Cash2").ok, "cash pack")
check(nA.data.Cash > c1, "cash pack granted")
check(call("StudioPurchase", A, "product", "StarterPack").ok, "starter pack")
check(nA.data.Flags.StarterPack == true, "starter flag")
check(call("StudioPurchase", A, "product", "SupplyDrop").ok, "supply drop")
check(call("StudioPurchase", A, "product", "InstantBuild").ok, "instant build")
check(call("ClaimDaily", A).ok, "daily claim")
check(not call("ClaimDaily", A).ok, "daily twice blocked")
check(call("RedeemCode", A, "forge").ok, "code redeem")
check(not call("RedeemCode", A, "FORGE").ok, "code twice blocked")
advance(601)
check(call("ClaimPlaytime", A).ok, "playtime gift")
check(call("ClaimGroup", A).ok == false, "group reward off when GroupId = 0")
-- receipt idempotency
local Products = load(ReplicatedStorage.Shared.Catalog.Products)
local ps = place:GetDescendants()
local cash2 = nA.data.Cash

print("== nation identity + rank")
check(nA.data.Nation == nil and invokers.GetSnapshot(A).nation == false, "new nation unfounded")
check(string.find(call("SetNation", A, "ab", "1,4,1,3,1").err or "", "characters") ~= nil, "name too short rejected")
check(string.find(call("SetNation", A, "Bad<Name>", "1,4,1,3,1").err or "", "letters") ~= nil, "bad characters rejected")
local resN = call("SetNation", A, "  Iron   Republic ", "3,5,1,6,4")
check(resN.ok and resN.name == "Iron Republic", "nation founded (trimmed)")
check(A:GetAttribute("NationName") == "Iron Republic" and A:GetAttribute("NationFlag") == "3,5,1,6,4", "identity attributes")
local plotA = Workspace:FindFirstChild("Homeland"):FindFirstChild("Plot_" .. nA.plotIndex)
local signGui = plotA:FindFirstChild("SignBoard"):FindFirstChildOfClass("SurfaceGui")
check(signGui:FindFirstChild("Title").Text == "IRON REPUBLIC", "plot sign renamed")
local cloth = plotA:FindFirstChild("FlagCloth")
check(cloth.Transparency == 0 and cloth:FindFirstChild("FlagFront"):FindFirstChild("Flag") ~= nil, "flag raised on pole")
check(call("SetNation", A, "Iron Republic", { p = 99, c = { -1, 500, 2 }, e = 77 }).ok, "garbage flag sanitized")
local snapN = invokers.GetSnapshot(A)
check(snapN.nation and snapN.nation.name == "Iron Republic", "nation in snapshot")
check(snapN.rank and snapN.rank.power > 0 and snapN.rank.name ~= nil, "rank in snapshot")
local cashBefore = nA.data.Cash
nA.data.RankLevel = 1
nA.data.Population += 3000
advance(1)
check(nA.data.RankLevel >= 3 and nA.data.Cash >= cashBefore + 40000, "rank-up rewards paid once")
local cashAfter = nA.data.Cash
advance(1)
check(nA.data.Cash - cashAfter < 40000, "rank rewards not repeated")
check(A:GetAttribute("Power") == nA.stats.rank.power and A:GetAttribute("RankName") == nA.stats.rank.name, "power attributes")

print("== snapshot")
local snap = invokers.GetSnapshot(A)
check(snap and snap.cash ~= nil and snap.quest ~= nil, "snapshot")
local ok = pcall(serde.encode, "json", snap)
check(ok, "snapshot serializable")

print("== save + rejoin")
local buildingCount = 0
for _ in nA.buildings do buildingCount += 1 end
local unitCount = S.UnitService.count(nA)
local inv = nA.data.Inventory.SRBM
playerList[1] = nil
playerList = { B }
Players.PlayerRemoving:Fire(A)
A.Parent = nil
stdtask.wait(0.1)
check(Nations.get(A) == nil, "nation removed on leave")
local saved = stores[Config.DataStoreName].data["player_101"]
check(saved ~= nil and saved._lock == nil, "saved and lock released")
local A2 = newPlayer(101, "Alpha")
stdtask.wait(0.1)
local nA2 = Nations.get(A2)
check(nA2 and nA2.ready, "rejoined")
local count2 = 0
for _ in nA2.buildings do count2 += 1 end
check(count2 == buildingCount, ("buildings restored %d/%d"):format(count2, buildingCount))
check(S.UnitService.count(nA2) == unitCount, "units restored")
check(nA2.data.Inventory.SRBM == inv, "inventory restored")
check(nA2.passes.DoubleCash == true, "studio pass restored")
check(nA2.data.Nation and nA2.data.Nation.Name == "Iron Republic" and A2:GetAttribute("NationName") == "Iron Republic", "nation identity restored")

print("== old grid saves migrate")
stores[Config.DataStoreName].data["player_303"] = {
	Version = 1, Cash = 1000, NextUid = 4,
	Buildings = {
		{ u = 1, id = "road", x = 50, z = 50 },
		{ u = 2, id = "small_house", x = 50, z = 52 },
		{ u = 3, id = "shop", x = 60, z = 60, r = 1 },
	},
}
local Cc = newPlayer(303, "Charlie")
stdtask.wait(0.1)
local nC = Nations.get(Cc)
check(nC and nC.ready, "old save loads")
local road3, house3, shop3 = nC.buildings[1], nC.buildings[2], nC.buildings[3]
check(road3 and road3.x == 4 and road3.z == 4 and road3.len == 8, "old road tile -> segment")
check(house3 and house3.x == 4 and house3.z == 12 and house3.connected, "old house keeps its spot + road access")
check(shop3 and shop3.x == 46 and shop3.z == 46 and shop3.r == 90, "old quarter turn -> degrees")
S.BuildService.serialize(nC)
check(nC.data.Buildings[1].a ~= nil, "saves in the new format")

print(("\n%d failures, %d server warnings"):format(failures, errors))
process.exit(failures == 0 and errors == 0 and 0 or 1)
