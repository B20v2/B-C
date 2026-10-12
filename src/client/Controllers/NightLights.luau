--[[
	NightLights
	When the server clock passes dusk, city windows light up (most of them;
	a few stay dark so blocks don't look like solid neon), Blender-kit light
	meshes switch on their glow twin, and the scene gets a cool night grade.
	Everything flips back at dawn.
]]

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local NightLights = {}

local WARM = Color3.fromRGB(255, 214, 140)
local COOL = Color3.fromRGB(200, 236, 255)

local night = false
local grade: ColorCorrectionEffect? = nil

function NightLights.isNight(clock: number): boolean
	return clock >= 18.4 or clock < 5.6
end

-- Stable per-window choice: ~70% lit, a few cool office tones.
local function windowLook(p: BasePart): (boolean, Color3)
	local pos = p.CFrame.Position
	local h = (math.floor(pos.X * 7.31) + math.floor(pos.Y * 3.17) * 17 + math.floor(pos.Z * 5.13) * 31) % 100
	return h < 70, h % 9 == 0 and COOL or WARM
end

function NightLights.apply(p: Instance, on: boolean)
	if not p:IsA("BasePart") then
		return
	end
	if p:GetAttribute("NightGlow") then
		p.Transparency = on and 0 or 1
	elseif p:GetAttribute("Window") then
		if on then
			local litNow, col = windowLook(p)
			if litNow then
				if p:GetAttribute("DayColor") == nil then
					p:SetAttribute("DayColor", p.Color)
					p:SetAttribute("DayMaterial", p.Material.Name)
				end
				p.Material = Enum.Material.Neon
				p.Color = col
			end
		else
			local col = p:GetAttribute("DayColor") :: Color3?
			if col then
				p.Color = col
				local mat = p:GetAttribute("DayMaterial") :: string?
				p.Material = (mat and (Enum.Material :: any)[mat]) or Enum.Material.SmoothPlastic
			end
		end
	end
end

local function roots(): { Instance }
	local out = {}
	for _, name in { "Homeland", "Mainland" } do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(out, f)
		end
	end
	return out
end

function NightLights.set(on: boolean)
	if on == night then
		return
	end
	night = on
	for _, root in roots() do
		for _, d in root:GetDescendants() do
			NightLights.apply(d, on)
		end
	end
	if grade then
		local goal = on and { TintColor = Color3.fromRGB(196, 212, 255), Brightness = 0.03, Contrast = 0.1, Saturation = -0.12 }
			or { TintColor = Color3.new(1, 1, 1), Brightness = 0, Contrast = 0, Saturation = 0 }
		TweenService:Create(grade, TweenInfo.new(4), goal):Play()
	end
end

local function watch(root: Instance)
	root.DescendantAdded:Connect(function(d)
		if night then
			task.defer(NightLights.apply, d, true)
		end
	end)
end

function NightLights.init()
	local ok = pcall(function()
		local g = Instance.new("ColorCorrectionEffect")
		g.Name = "NightGrade"
		g.Parent = Lighting
		grade = g
	end)
	if not ok then
		grade = nil
	end
	task.spawn(function()
		for _, name in { "Homeland", "Mainland" } do
			task.spawn(function()
				watch(workspace:WaitForChild(name))
			end)
		end
	end)
	local function check()
		NightLights.set(NightLights.isNight(Lighting.ClockTime))
	end
	pcall(function()
		Lighting:GetPropertyChangedSignal("ClockTime"):Connect(check)
	end)
	check()
end

return NightLights
