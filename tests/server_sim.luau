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
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint, ColorSequence = roblox.ColorSequence, NumberRange = roblox.NumberRange,
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

print("== early economy")
local function place_(p, id, x, z, r)
	local res = call("PlaceBuilding", p, id, x, z, r or 0)
	if not res.ok then print("    place " .. id .. " failed: " .. tostring(res.err)) end
	return res
end
local res = call("PlaceMany", A, "road", { {10, 10}, {12, 10}, {14, 10}, {16, 10}, {18, 10}, {20, 10} }, 0)
check(res.ok and res.placed == 6, "drag-place 6 roads")
check(place_(A, "small_house", 10, 12).ok, "house 1")
check(place_(A, "small_house", 12, 12).ok, "house 2")
check(place_(A, "small_house", 14, 12).ok, "house 3")
check(not place_(A, "small_house", 14, 12).ok, "overlap rejected")
check(not place_(A, "small_house", 99, 99).ok, "out of bounds rejected")
check(not place_(A, "apartment", 30, 30).ok, "locked research rejected")
check(place_(A, "wind_turbine", 30, 30).ok, "turbine")
check(place_(A, "water_tower", 34, 30).ok, "water tower")
local cash0 = nA.data.Cash
advance(12)
check(nA.data.Population > 0, ("population grows (%.1f)"):format(nA.data.Population))
local houses = 0
for _, b in nA.buildings do if b.id == "small_house" and not b.finishAt then houses += 1 end end
check(houses == 3, "houses finished construction")
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
check(call("MoveBuilding", A, r2.uid, 44, 44, 1).ok, "move shop")
check(nA.buildings[r2.uid].x == 44 and nA.buildings[r2.uid].r == 1, "moved coords")
check(call("DeleteBuilding", A, r2.uid).ok, "delete shop")
check(nA.buildings[r2.uid] == nil, "shop gone")

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
call("PlaceMany", A, "road", { {50, 50}, {52, 50}, {54, 50}, {56, 50}, {58, 50}, {60, 50}, {62, 50}, {64, 50}, {66, 50}, {68, 50}, {70, 50}, {72, 50} }, 0)
for i = 0, 9 do place_(A, "wind_turbine", 50 + i * 2, 60) end
for i = 0, 5 do place_(A, "apartment", 50 + i * 6, 70) end -- needs urban planning -> fails, fine
for i = 0, 7 do place_(A, "small_house", 50 + i * 2, 52) end
check(place_(A, "oil_pump", 50, 47).ok, "oil pump")
check(place_(A, "oil_pump", 52, 47).ok, "oil pump 2")
local ref = place_(A, "small_refinery", 56, 44)
check(ref.ok, "refinery")
local fac = place_(A, "small_military_factory", 64, 42)
check(fac.ok, "military factory")
local lau = place_(A, "srbm_launcher", 80, 80)
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
local hb = place_(B, "small_house", 49, 49)
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

print("== units + capture")
check(S.UnitService.count(nA) >= 1, ("units: %d"):format(S.UnitService.count(nA)))
local u
for _, unit in nA.units do u = unit end
if u then
	local cr = call("CommandUnits", A, { u.uid }, target)
	check(cr.ok, "command unit to airport")
	check(u.location == "mainland", "unit deployed")
	-- physics isn't simulated: teleport onto the point
	u.model:PivotTo(CFrame.new(target + Vector3.new(0, u.height, 0)))
	pts[2].garrison = 0
	advance(60)
	check(pts[2].owner == nA.userId, ("airport captured (capture %.0f, owner %d)"):format(pts[2].capture, pts[2].owner))
	local bonus = S.ConquestService.bonusFor(nA)
	check(bonus.income > 0, "capture bonus applies")
	check(call("RecallUnits", A, nil).ok, "recall")
end

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

print(("\n%d failures, %d server warnings"):format(failures, errors))
process.exit(failures == 0 and errors == 0 and 0 or 1)
