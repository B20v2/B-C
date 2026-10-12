--[[
	Effects
	Client-side visuals for combat:
	  * missiles / drones flying their synced Ballistics path with trails
	  * interceptor missiles that meet incoming strikes mid-air
	  * explosions (flash, smoke, debris-free Explosion), cluster scatter
	  * tracer shots between vehicles, move markers, build-complete sparkle
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Ballistics = require(Shared.Util.Ballistics)
local ModelBuilder = require(Shared.ModelBuilder)
local Weapons = require(Shared.Catalog.Weapons)
local Net = require(Shared.Net)

local Client = script.Parent.Parent
local Hub = require(Client.Hub)
local Lib = require(Client.UI.Lib)
local Sounds = require(script.Parent.Sounds)

local Effects = {}

local camera = workspace.CurrentCamera
local fx: Folder

type Flight = {
	model: Model,
	from: Vector3,
	to: Vector3,
	apex: number,
	kind: string,
	t0: number,
	flight: number,
	endAlpha: number?,
	done: boolean,
	onEnd: (() -> ())?,
}

local flights: { [any]: Flight } = {}
local shake = 0

local function addTrail(model: Model, color: Color3, width: number, smoke: boolean)
	local root = model.PrimaryPart :: BasePart
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, width / 2, 2)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -width / 2, 2)
	a1.Parent = root
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 1.4
	trail.Color = ColorSequence.new(color, Color3.fromRGB(200, 200, 200))
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 2.5) })
	trail.LightEmission = 0.4
	trail.FaceCamera = true
	trail.Parent = root
	if smoke then
		local tail = root:FindFirstChild("Tail") :: Attachment?
		local p = Instance.new("ParticleEmitter")
		p.Texture = "rbxasset://textures/particles/smoke_main.dds"
		p.Color = ColorSequence.new(Color3.fromRGB(220, 220, 215))
		p.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 5) })
		p.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
		p.Lifetime = NumberRange.new(1.2, 2)
		p.Rate = 40
		p.Speed = NumberRange.new(0.5, 1.5)
		p.Parent = tail or root
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(255, 180, 90)
		glow.Brightness = 3
		glow.Range = 14
		glow.Parent = root
	end
end

function Effects.explosion(pos: Vector3, scale: number, airburst: boolean?)
	local s = math.max(0.4, scale)
	-- flash
	local flash = Instance.new("Part")
	flash.Shape = Enum.PartType.Ball
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CanTouch = false
	flash.CastShadow = false
	flash.Material = Enum.Material.Neon
	flash.Color = airburst and Color3.fromRGB(255, 230, 170) or Color3.fromRGB(255, 160, 60)
	flash.Size = Vector3.one * 4 * s
	flash.Position = pos
	flash.Parent = fx
	Lib.tween(flash, 0.45, { Size = Vector3.one * 26 * s, Transparency = 1 })
	Debris:AddItem(flash, 0.5)
	-- smoke column
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.Transparency = 1
	holder.Size = Vector3.one
	holder.Position = pos
	holder.Parent = fx
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(airburst and Color3.fromRGB(150, 150, 150) or Color3.fromRGB(70, 66, 60))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 6 * s), NumberSequenceKeypoint.new(1, 18 * s) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(2.5, 4)
	smoke.Speed = NumberRange.new(6 * s, 14 * s)
	smoke.SpreadAngle = Vector2.new(60, 60)
	smoke.Rate = 0
	smoke.Parent = holder
	smoke:Emit(math.floor(14 * s))
	local fire = Instance.new("ParticleEmitter")
	fire.Texture = "rbxasset://textures/particles/fire_main.dds"
	fire.Color = ColorSequence.new(Color3.fromRGB(255, 190, 90), Color3.fromRGB(255, 90, 30))
	fire.LightEmission = 1
	fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 5 * s), NumberSequenceKeypoint.new(1, 1) })
	fire.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	fire.Lifetime = NumberRange.new(0.4, 0.8)
	fire.Speed = NumberRange.new(10 * s, 24 * s)
	fire.SpreadAngle = Vector2.new(180, 180)
	fire.Rate = 0
	fire.Parent = holder
	fire:Emit(math.floor(24 * s))
	Debris:AddItem(holder, 5)
	-- sound + shockwave (no physics damage, purely visual)
	local e = Instance.new("Explosion")
	e.Position = pos
	e.BlastPressure = 0
	e.BlastRadius = 0
	e.DestroyJointRadiusPercent = 0
	e.ExplosionType = Enum.ExplosionType.NoCraters
	e.Visible = false
	e.Parent = fx
	local dist = (camera.CFrame.Position - pos).Magnitude
	shake = math.max(shake, math.clamp(1 - dist / (700 * s), 0, 1) * 1.2 * s)
end

local function spawnFlight(id: any, weaponId: string?, from: Vector3, to: Vector3, apex: number, kind: string, t0: number, flight: number, endAlpha: number?, interceptor: boolean?)
	local def = weaponId and Weapons.get(weaponId)
	local model
	if interceptor or not def then
		model = ModelBuilder.projectile({ kind = "missile", color = Color3.fromRGB(240, 240, 236), id = "GLCM" })
		model:ScaleTo(0.6)
	else
		model = ModelBuilder.projectile(def)
	end
	model.Parent = fx
	addTrail(model, interceptor and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(255, 200, 120), interceptor and 0.6 or 1, kind ~= "drone")
	flights[id] = { model = model, from = from, to = to, apex = apex, kind = kind, t0 = t0, flight = flight, endAlpha = endAlpha, done = false }
	return flights[id]
end

local function onProjectile(data)
	local weapon = Weapons.get(data.w)
	spawnFlight(data.id, data.w, data.from, data.to, data.apex, data.kind, data.t0, data.flight, data.ic)
	Sounds.at("Launch", data.from, 0.6)
	if data.ic and data.icFrom then
		-- interceptor timed to meet the strike at the intercept point
		local meetTime = data.t0 + data.flight * data.ic
		local meetPos = Ballistics.position(data.from, data.to, data.apex, data.kind, data.ic)
		local dur = math.clamp(data.flight * data.ic * 0.6, 1.2, 3)
		local start = meetTime - dur
		task.delay(math.max(0, start - Lib.serverNow()), function()
			spawnFlight(tostring(data.id) .. "i", nil, data.icFrom, meetPos, 30, "missile", start, dur, 1, true)
			Sounds.at("Launch", data.icFrom, 0.5)
		end)
	end
	local _ = weapon
end

local function endFlight(id: any)
	local f = flights[id]
	if f then
		flights[id] = nil
		local root = f.model.PrimaryPart
		if root then
			-- let trails fade out
			for _, d in f.model:GetDescendants() do
				if d:IsA("BasePart") then
					d.Transparency = 1
				elseif d:IsA("ParticleEmitter") then
					d.Enabled = false
				end
			end
		end
		Debris:AddItem(f.model, 2)
	end
end

local function onProjectileEnd(data)
	local f = flights[data.id]
	local pos: Vector3
	if data.intercepted then
		if f then
			pos = Ballistics.position(f.from, f.to, f.apex, f.kind, f.endAlpha or 0.7)
		else
			return
		end
		endFlight(data.id)
		endFlight(tostring(data.id) .. "i")
		Effects.explosion(pos, 0.7, true)
		return
	end
	endFlight(data.id)
	pos = data.pos or (f and f.to) or Vector3.zero
	local w = Weapons.get(data.w or "")
	local scale = w and math.clamp(w.radius / 24, 0.6, 2) or 1
	if data.w == "CLUSTER" and w then
		for i = 1, 8 do
			task.delay(i * 0.08, function()
				local a = math.random() * math.pi * 2
				local r = math.random() * w.radius
				Effects.explosion(pos + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r), 0.6)
			end)
		end
	else
		Effects.explosion(pos, scale)
	end
end

local function step()
	local now = Lib.serverNow()
	for id, f in flights do
		local alpha = (now - f.t0) / f.flight
		if alpha < 0 then
			f.model.Parent = nil
		else
			f.model.Parent = fx
			local limit = f.endAlpha or 1
			local a = math.min(alpha, limit)
			f.model:PivotTo(Ballistics.cframe(f.from, f.to, f.apex, f.kind, a))
			if alpha > limit + 2 then
				endFlight(id) -- safety: server never answered
			end
		end
	end
	if shake > 0.01 then
		local o = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * shake
		camera.CFrame *= CFrame.new(o)
		shake *= 0.88
	end
end

local function tracer(from: Vector3, to: Vector3, artillery: boolean)
	if artillery then
		local id = {}
		local flight = math.clamp((to - from).Magnitude / 220, 0.8, 2.2)
		local now = Lib.serverNow()
		spawnFlight(id, nil, from, to, 40, "missile", now, flight, 1, true)
		task.delay(flight, function()
			endFlight(id)
			Effects.explosion(to, 0.35)
		end)
		return
	end
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(255, 220, 140)
	local len = (to - from).Magnitude
	p.Size = Vector3.new(0.25, 0.25, len)
	p.CFrame = CFrame.lookAt((from + to) / 2, to)
	p.Parent = fx
	Lib.tween(p, 0.18, { Transparency = 1 })
	Debris:AddItem(p, 0.2)
end

local function moveMarker(pos: Vector3)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(90, 230, 130)
	ring.Size = Vector3.new(0.2, 4, 4)
	ring.CFrame = CFrame.new(pos.X, 0.3, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
	ring.Transparency = 0.3
	ring.Parent = fx
	Lib.tween(ring, 0.6, { Size = Vector3.new(0.2, 26, 26), Transparency = 1 })
	Debris:AddItem(ring, 0.7)
end

local function buildDone(pos: Vector3)
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.Transparency = 1
	holder.Size = Vector3.one
	holder.Position = pos + Vector3.new(0, 4, 0)
	holder.Parent = fx
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 230, 120))
	sparkle.LightEmission = 1
	sparkle.Size = NumberSequence.new(1.2, 0)
	sparkle.Lifetime = NumberRange.new(0.6, 1.2)
	sparkle.Speed = NumberRange.new(8, 16)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Rate = 0
	sparkle.Parent = holder
	sparkle:Emit(30)
	Debris:AddItem(holder, 2)
	Sounds.play("Place", 1.3)
end

function Effects.init()
	fx = Instance.new("Folder")
	fx.Name = "FX"
	fx.Parent = workspace
	Net.event("Projectile").OnClientEvent:Connect(onProjectile)
	Net.event("ProjectileEnd").OnClientEvent:Connect(onProjectileEnd)
	Net.event("Effect").OnClientEvent:Connect(function(kind, a, b, c)
		if kind == "Explosion" then
			Effects.explosion(a, b or 1)
		elseif kind == "Shot" then
			tracer(a, b, c == true)
		elseif kind == "BuildDone" then
			buildDone(a)
		elseif kind == "Welcome" then
			Hub.call("showWelcome", b, c)
		elseif kind == "ResearchDone" then
			Sounds.play("Success")
		elseif kind == "RankUp" then
			Hub.call("showRankUp", a)
		end
	end)
	Hub.moveMarker = moveMarker
	-- after the camera scripts so screen shake isn't overwritten
	RunService:BindToRenderStep("FFEffects", Enum.RenderPriority.Camera.Value + 1, step)
end

return Effects
