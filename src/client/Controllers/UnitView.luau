--[[
	UnitView
	Nameplates over every vehicle (navy tag with a role icon and the unit
	name), health bars when damaged, and green selection boxes for the
	units you have selected.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Units = require(ReplicatedStorage.Shared.Catalog.Units)

local Client = script.Parent.Parent
local Lib = require(Client.UI.Lib)
local Theme = require(Client.UI.Theme)
local Icons = require(Client.UI.Icons)

local New = Lib.New

local UnitView = {}

local player = Players.LocalPlayer
local selected: { [Model]: SelectionBox } = {}
local listeners: { () -> () } = {}

local NAVY = Color3.fromRGB(24, 40, 70)

local function roleIcon(role: string): string
	if role == "Artillery" then
		return "rocket"
	elseif role == "Capture" then
		return "truck"
	elseif role == "Anti-Air" then
		return "target"
	end
	return "tank"
end

local function decorate(model: Model)
	if not model:IsA("Model") or not model:GetAttribute("Unit") then
		return
	end
	local root = model:WaitForChild("Root", 5) :: BasePart?
	if not root then
		return
	end
	local def = Units.get(model:GetAttribute("UnitId") :: string)
	local mine = model:GetAttribute("OwnerId") == player.UserId
	local color = (model:GetAttribute("Color") :: Color3?) or Theme.Color.Accent

	local gui = New("BillboardGui", {
		Name = "Tag",
		Adornee = root,
		Size = UDim2.fromOffset(130, 40),
		StudsOffsetWorldSpace = Vector3.new(0, 5, 0),
		AlwaysOnTop = true,
		MaxDistance = 2600,
		LightInfluence = 0,
		Parent = model,
	})
	local tag = New("Frame", {
		BackgroundColor3 = NAVY,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = gui,
	}, {
		Lib.corner(5),
		Lib.stroke(Color3.new(1, 1, 1), 1.5, mine and 0 or 0.4),
		Lib.list("x", 6, nil, Enum.VerticalAlignment.Center),
		Lib.pad(0, 8, 0, 3),
	})
	local iconBox = New("Frame", {
		BackgroundColor3 = color,
		Size = UDim2.fromOffset(18, 16),
		LayoutOrder = 1,
		Parent = tag,
	}, { Lib.corner(3) })
	local ic = Icons.get(roleIcon(def and def.role or ""), 14, Color3.new(1, 1, 1))
	ic.AnchorPoint = Vector2.new(0.5, 0.5)
	ic.Position = UDim2.fromScale(0.5, 0.5)
	ic.Parent = iconBox
	Lib.text({
		Text = string.upper(def and def.name or model.Name),
		TextColor3 = Color3.new(1, 1, 1),
		FontFace = Theme.Font.Bold,
		TextSize = 12,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		TextTruncate = Enum.TextTruncate.None,
		LayoutOrder = 2,
		Parent = tag,
	})
	local hpBar = Lib.progress({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 26),
		Size = UDim2.fromOffset(70, 4),
		Visible = false,
		Parent = gui,
	})
	local function updateHp()
		local hp = (model:GetAttribute("Hp") :: number?) or 1
		local max = (model:GetAttribute("MaxHp") :: number?) or 1
		hpBar.frame.Visible = hp < max
		hpBar.set(hp / max, hp / max > 0.35 and Theme.Color.Good or Theme.Color.Bad)
	end
	model:GetAttributeChangedSignal("Hp"):Connect(updateHp)
	updateHp()
end

function UnitView.isSelected(model: Model): boolean
	return selected[model] ~= nil
end

function UnitView.select(model: Model, on: boolean)
	if on and not selected[model] then
		selected[model] = New("SelectionBox", {
			Adornee = model,
			Color3 = Color3.fromRGB(90, 230, 130),
			LineThickness = 0.08,
			SurfaceTransparency = 1,
			Parent = model,
		})
	elseif not on and selected[model] then
		selected[model]:Destroy()
		selected[model] = nil
	end
	for _, fn in listeners do
		task.spawn(fn)
	end
end

function UnitView.clear()
	for m, box in selected do
		box:Destroy()
		selected[m] = nil
	end
	for _, fn in listeners do
		task.spawn(fn)
	end
end

function UnitView.selectedUids(): { number }
	local out = {}
	for m in selected do
		if m.Parent then
			table.insert(out, m:GetAttribute("Uid") :: number)
		else
			selected[m] = nil
		end
	end
	return out
end

function UnitView.count(): number
	local c = 0
	for m in selected do
		if m.Parent then
			c += 1
		end
	end
	return c
end

function UnitView.onSelectionChanged(fn: () -> ())
	table.insert(listeners, fn)
end

-- Your own unit models.
function UnitView.mine(): { Model }
	local out = {}
	local folder = workspace:FindFirstChild("Units")
	if folder then
		for _, m in folder:GetChildren() do
			if m:IsA("Model") and m:GetAttribute("OwnerId") == player.UserId then
				table.insert(out, m)
			end
		end
	end
	return out
end

function UnitView.init()
	local folder = workspace:WaitForChild("Units")
	folder.ChildAdded:Connect(function(m)
		task.defer(decorate, m)
	end)
	folder.ChildRemoved:Connect(function(m)
		if selected[m :: Model] then
			selected[m :: Model] = nil
			for _, fn in listeners do
				task.spawn(fn)
			end
		end
	end)
	for _, m in folder:GetChildren() do
		task.spawn(decorate, m)
	end
end

return UnitView
