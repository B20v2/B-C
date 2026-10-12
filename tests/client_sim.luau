--!nocheck
-- Client simulation: boots the real client UI against the simulated server. Run via tests/run.sh.
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
		local fns = self.fns
		return { Disconnect = function()
			local i = table.find(fns, fn)
			if i then table.remove(fns, i) end
		end }
	end
	function s:Fire(...)
		for _, fn in table.clone(self.fns) do fn(...) end
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
LOCAL_PLAYER = nil
CLIENT_READY = false
roblox.implementMethod("RemoteEvent", "FireClient", function(self, player, ...)
	sent[self.Name] = sent[self.Name] or {}
	table.insert(sent[self.Name], { player = player, args = { ... } })
	if CLIENT_READY and player == LOCAL_PLAYER then
		local args = table.pack(...)
		local ok, err = pcall(function() sigFor(self, "OnClientEvent"):Fire(table.unpack(args, 1, args.n)) end)
		if not ok then CLIENT_ERR(self.Name, err) end
	end
end)
roblox.implementMethod("RemoteEvent", "FireAllClients", function(self, ...)
	sent[self.Name] = sent[self.Name] or {}
	table.insert(sent[self.Name], { player = "all", args = { ... } })
	if CLIENT_READY then
		local args = table.pack(...)
		local ok, err = pcall(function() sigFor(self, "OnClientEvent"):Fire(table.unpack(args, 1, args.n)) end)
		if not ok then CLIENT_ERR(self.Name, err) end
	end
end)


---------------------------------------------------------------- client shims
local sigStore = {}
local sidCounter = 0
function sigFor(inst, name)
	local sid = inst:GetAttribute("__sid")
	if not sid then
		sidCounter += 1
		sid = sidCounter
		inst:SetAttribute("__sid", sid)
	end
	sigStore[sid] = sigStore[sid] or {}
	sigStore[sid][name] = sigStore[sid][name] or Signal()
	return sigStore[sid][name]
end
local GUI = { "Frame", "TextLabel", "TextButton", "ScrollingFrame", "ViewportFrame", "TextBox", "BillboardGui", "ScreenGui", "ImageLabel", "ImageButton" }
for _, cls in GUI do
	for _, ev in { "Activated", "MouseEnter", "MouseLeave", "MouseButton1Down", "MouseButton1Up", "FocusLost" } do
		pcall(roblox.implementProperty, cls, ev, function(self) return sigFor(self, ev) end)
	end
end
local ALL = { "Frame", "TextLabel", "TextButton", "ScrollingFrame", "ViewportFrame", "TextBox", "BillboardGui", "ScreenGui",
	"Model", "Folder", "Part", "Camera", "Player", "PlayerGui", "Workspace", "UIStroke", "UIScale", "Highlight", "Sound" }
for _, cls in ALL do
	roblox.implementMethod(cls, "GetPropertyChangedSignal", function(self, prop) return sigFor(self, "P_" .. prop) end)
	roblox.implementMethod(cls, "GetAttributeChangedSignal", function(self, attr) return sigFor(self, "A_" .. attr) end)
	for _, ev in { "AttributeChanged", "ChildAdded", "ChildRemoved", "AncestryChanged", "DescendantAdded" } do
		pcall(roblox.implementProperty, cls, ev, function(self) return sigFor(self, ev) end)
	end
	pcall(roblox.implementMethod, cls, "WaitForChild", function(self, name)
		local c = self:FindFirstChild(name)
		assert(c, "WaitForChild would hang: " .. name .. " in " .. self:GetFullName())
		return c
	end)
end
roblox.implementMethod("Sound", "Play", function() end)
roblox.implementMethod("Workspace", "Raycast", function() return nil end)
roblox.implementMethod("ParticleEmitter", "Emit", function() end)
roblox.implementMethod("Model", "ScaleTo", function() end)
roblox.implementMethod("Camera", "ScreenPointToRay", function(self, x, y)
	-- straight down from high above, offset by pointer
	local o = self.CFrame.Position + Vector3.new((x - 800) * 0.5, 0, (y - 450) * 0.5)
	return { Origin = o, Direction = Vector3.new(0, -1, 0) }
end)
roblox.implementMethod("Camera", "WorldToScreenPoint", function(self, p)
	return Vector3.new(800, 450, 1), true
end)
roblox.implementProperty("RemoteEvent", "OnClientEvent", function(self) return sigFor(self, "OnClientEvent") end)
roblox.implementMethod("RemoteFunction", "InvokeServer", function(self, ...)
	return invokers[self.Name](LOCAL_PLAYER, ...)
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
	TweenInfo = { new = function(...) return { ... } end },
	RaycastParams = { new = function() return {} end },
	Ray = { new = function(o, d) return { Origin = o, Direction = d } end },
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
CLIENT_ERRORS = 0
function CLIENT_ERR(where, err) CLIENT_ERRORS += 1 print("CLIENT ERROR in " .. tostring(where) .. ": " .. tostring(err)) end
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


---------------------------------------------------------------- client boot
print("== client boot")
nA.data.Cash = 90000000
nA.data.ResearchPoints = 100000
nA.passes.Billboard = true
for _, id in { "military_doctrine", "heavy_industry", "ballistics", "mechanized", "urban_planning", "drones_1", "air_defense_1", "air_defense_2" } do
	nA.data.Researched[id] = true
end
-- a small city to inspect
call("PlaceMany", A, "road", { {10, 10}, {12, 10}, {14, 10}, {16, 10}, {18, 10}, {20, 10}, {22, 10} }, 0)
local placed = {}
for _, spec in { {"small_house", 10, 12}, {"wind_turbine", 30, 30}, {"water_tower", 34, 30}, {"oil_pump", 14, 6}, {"small_refinery", 16, 12},
	{"small_military_factory", 30, 12}, {"srbm_launcher", 60, 60}, {"billboard", 70, 70}, {"apartment", 22, 12}, {"ciws", 80, 80}, {"radar_station", 84, 84}, {"hornet_launcher", 88, 88} } do
	local r = call("PlaceBuilding", A, spec[1], spec[2], spec[3], 0)
	if not r.ok then print("    place " .. spec[1] .. " failed: " .. tostring(r.err)) end
	placed[spec[1]] = r.uid
	print("    placed", spec[1], r.ok, r.uid)
end
nA.passes.Billboard = true
advance(70)

local function svc(name, v) services[name] = v end
local UIS = { InputBegan = Signal(), InputChanged = Signal(), InputEnded = Signal(), TouchPinch = Signal(), TouchPan = Signal(), TouchEnabled = false }
function UIS:IsKeyDown() return false end
function UIS:GetMouseLocation() return roblox.Vector2.new(800, 450) end
svc("UserInputService", UIS)
local renderSteps = {}
services.RunService.RenderStepped = Signal()
function services.RunService:BindToRenderStep(name, _p, fn) renderSteps[name] = fn end
svc("TweenService", { Create = function(_, inst, _info, props)
	return { Play = function() for k, v in props do inst[k] = v end end, Completed = Signal() }
end })
svc("ContextActionService", { BindActionAtPriority = function() end, UnbindAction = function() end })
local soundFolder = Instance.new("Folder")
svc("SoundService", soundFolder)
svc("TextChatService", {})
svc("GuiService", { GetGuiInset = function() return roblox.Vector2.zero end })
svc("Debris", { AddItem = function() end })
function Marketplace:GetProductInfo() return { PriceInRobux = 99 } end
function Marketplace:PromptGamePassPurchase() end
function Marketplace:PromptProductPurchase() end
Players.LocalPlayer = A
LOCAL_PLAYER = A
local playerGui = Instance.new("PlayerGui")
playerGui.Parent = A
local cam = Instance.new("Camera")
cam.ViewportSize = roblox.Vector2.new(1600, 900)
cam.CFrame = CFrame.lookAt(nA.origin + Vector3.new(0, 200, 200), nA.origin)
cam.Parent = Workspace
Workspace.CurrentCamera = cam

-- client env differs from server env only in what the mocks return
local StarterPlayer = place:FindFirstChildOfClass("StarterPlayer")
local clientFolder = StarterPlayer:FindFirstChild("StarterPlayerScripts"):FindFirstChild("Client")
local okBoot, bootErr = pcall(load, clientFolder:FindFirstChild("Main"))
check(okBoot, "client Main boots: " .. tostring(bootErr))
CLIENT_READY = true
stdtask.wait(0.1)

local function req(path)
	local inst = clientFolder
	for part in path:gmatch("[^%.]+") do inst = inst:FindFirstChild(part) end
	return load(inst)
end
local ClientState = req("ClientState")
local Hub = req("Hub")
check(ClientState.get("cash") ~= nil, "client got snapshot")
check(playerGui:FindFirstChild("FF_HUD") ~= nil, "HUD layer created")

local function frame(dt)
	local ok, err = pcall(function()
		services.RunService.Heartbeat:Fire(dt or 0.25)
		services.RunService.RenderStepped:Fire(dt or 0.016)
		for _, fn in renderSteps do fn(dt or 0.016) end
	end)
	if not ok then CLIENT_ERR("frame", err) end
end
local function guarded(name, fn, ...)
	print("    -> " .. name)
	local ok, err = pcall(fn, ...)
	if not ok then CLIENT_ERR(name, err) end
	return ok
end
local function findButton(match)
	for _, d in playerGui:GetDescendants() do
		if d:IsA("TextButton") and (d.Name == match or d.Text == match) then
			return d
		end
	end
	return nil
end
local function click(match)
	local b = findButton(match)
	if not b then
		CLIENT_ERR("click", "no button " .. match)
		return
	end
	guarded("click " .. match, function() b.Activated:Fire() end)
	stdtask.wait()
end

advance(2)
frame()

print("    billboard runtime", nA.buildings[placed.billboard], nA.buildings[placed.billboard] and nA.buildings[placed.billboard].model)
print("== HUD + build menu")
click("BuildButton")
check(ClientState.mode == "build", "build mode")
click("Military")
click("Missiles")
click("srbm_launcher")
frame()
click("Air Defense")
click("Eastern")
click("Civilian")
click("Roads")
click("road")
frame()
guarded("rotate", function() req("Controllers.Placement").rotate() end)
click("Delete")
click("Move")
click("Undo")
frame()
click("Close")

print("== building panels")
for id, uid in placed do
	local b = nA.buildings[uid]
	if b and b.model then
		guarded("panel " .. id, Hub.openBuilding, b.model)
		for _ = 1, 3 do frame(0.5) end
		advance(1)
	end
end
-- interact with factory panel
guarded("refinery panel", Hub.openBuilding, nA.buildings[placed.small_refinery].model)
frame(0.5)

print("== windows")
guarded("research", Hub.openResearch)
frame(0.6)
click("urban_planning")
guarded("shop", Hub.openShop)
for _, t in { "Passes", "Cash", "Boosts", "Featured" } do
	click(t)
	frame()
end
guarded("daily", Hub.openDaily)
guarded("codes", Hub.openCodes)
guarded("army", Hub.openArmy)
guarded("welcome", Hub.showWelcome, 12345, 3600)
stdtask.wait(0.1)
guarded("travel", Hub.openTravel)
frame()

print("== war view")
nA.data.Inventory.SRBM = 5
advance(1)
guarded("goWar", Hub.goWar, "mainland")
check(ClientState.mode == "war", "war mode")
for _ = 1, 5 do frame(1) end
local key1 = { UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.Two, Position = Vector3.zero }
guarded("key1", function() UIS.InputBegan:Fire(key1, false) end)
frame()
local launchesBefore = nA.data.Stats.Launches
local clickIn = { UserInputType = Enum.UserInputType.MouseButton1, Position = Vector3.new(800, 450, 0), KeyCode = Enum.KeyCode.Unknown }
guarded("fire", function() UIS.InputBegan:Fire(clickIn, false) UIS.InputEnded:Fire(clickIn) end)
check(nA.data.Stats.Launches > launchesBefore, "launched from war view")
print("    cam", cam.CFrame.Position, "inv", nA.data.Inventory.SRBM)
local ns = sent.Notify or {}
for i = math.max(1, #ns - 3), #ns do print("    notify:", ns[i].args[1]) end
for _ = 1, 20 do frame(0.1) end
advance(12)
for _ = 1, 10 do frame(0.1) end
-- box select / right click
guarded("deselect", function() UIS.InputBegan:Fire({ UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.Escape, Position = Vector3.zero }, false) end)
guarded("box", function()
	UIS.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton1, Position = Vector3.new(100, 100, 0), KeyCode = Enum.KeyCode.Unknown }, false)
	UIS.InputChanged:Fire({ UserInputType = Enum.UserInputType.MouseMovement, Position = Vector3.new(1500, 800, 0), KeyCode = Enum.KeyCode.Unknown })
	UIS.InputEnded:Fire({ UserInputType = Enum.UserInputType.MouseButton1, Position = Vector3.new(1500, 800, 0), KeyCode = Enum.KeyCode.Unknown })
	UIS.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton2, Position = Vector3.new(700, 400, 0), KeyCode = Enum.KeyCode.Unknown }, false)
	UIS.InputEnded:Fire({ UserInputType = Enum.UserInputType.MouseButton2, Position = Vector3.new(700, 400, 0), KeyCode = Enum.KeyCode.Unknown })
end)
guarded("wheel", function() UIS.InputChanged:Fire({ UserInputType = Enum.UserInputType.MouseWheel, Position = Vector3.new(0, 0, 1), KeyCode = Enum.KeyCode.Unknown }) end)
frame()
guarded("goHome", Hub.goHome)
check(ClientState.mode == "play", "back home")

print("== effects")
guarded("explosion", function() req("Controllers.Effects").explosion(nA.origin, 1) end)
for _ = 1, 5 do frame() end
-- pay day / notifications
advance(61)
frame()

print(("\nclient errors: %d, failures: %d, server warnings: %d"):format(CLIENT_ERRORS, failures, errors))
process.exit((CLIENT_ERRORS == 0 and failures == 0 and errors == 0) and 0 or 1)
