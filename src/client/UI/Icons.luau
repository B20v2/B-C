--[[
	Icons
	Simple flat icons drawn with Frames, so the UI needs zero uploaded images.
	Every icon is a transparent square Frame of `size` pixels.
]]

local Lib = require(script.Parent.Lib)
local Theme = require(script.Parent.Theme)

local New = Lib.New
local Icons = {}

local function box(size: number): Frame
	return New("Frame", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
	})
end

local function rect(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, rot: number?, radius: number?): Frame
	local f = New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(x, y),
		Size = UDim2.fromScale(w, h),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Rotation = rot or 0,
		Parent = parent,
	})
	if radius then
		New("UICorner", { CornerRadius = UDim.new(radius, 0), Parent = f })
	end
	return f
end

local function circle(parent: Instance, x: number, y: number, d: number, color: Color3): Frame
	return rect(parent, x, y, d, d, color, 0, 1)
end

local function ring(parent: Instance, x: number, y: number, d: number, color: Color3, thickness: number): Frame
	local f = rect(parent, x, y, d, d, color, 0, 1)
	f.BackgroundTransparency = 1
	New("UIStroke", { Color = color, Thickness = thickness, Parent = f })
	return f
end

function Icons.person(size: number, color: Color3): Frame
	local f = box(size)
	circle(f, 0.5, 0.3, 0.36, color)
	local body = rect(f, 0.5, 0.82, 0.7, 0.42, color, 0, 0.5)
	body.ClipsDescendants = true
	return f
end

function Icons.people(size: number, color: Color3): Frame
	local f = box(size)
	circle(f, 0.68, 0.3, 0.28, color).BackgroundTransparency = 0.35
	rect(f, 0.72, 0.74, 0.5, 0.36, color, 0, 0.5).BackgroundTransparency = 0.35
	circle(f, 0.38, 0.32, 0.32, color)
	rect(f, 0.36, 0.8, 0.6, 0.4, color, 0, 0.5)
	return f
end

function Icons.smile(size: number, color: Color3): Frame
	local f = box(size)
	ring(f, 0.5, 0.5, 0.82, color, math.max(1.5, size / 12))
	circle(f, 0.36, 0.4, 0.12, color)
	circle(f, 0.64, 0.4, 0.12, color)
	local mouthClip = New("Frame", {
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.56),
		Size = UDim2.fromScale(0.42, 0.18),
		Parent = f,
	})
	local m = New("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(1, 2),
		Parent = mouthClip,
	})
	New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = m })
	New("UIStroke", { Color = color, Thickness = math.max(1.5, size / 12), Parent = m })
	return f
end

function Icons.coin(size: number, color: Color3): Frame
	local f = box(size)
	Lib.text({
		Text = "$",
		Size = UDim2.fromScale(1, 1),
		TextScaled = true,
		FontFace = Theme.Font.Bold,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = f,
	})
	return f
end

function Icons.hammer(size: number, color: Color3): Frame
	local f = box(size)
	rect(f, 0.56, 0.58, 0.16, 0.72, color, 45, 0.4)
	rect(f, 0.36, 0.34, 0.56, 0.24, color, 45, 0.2)
	return f
end

function Icons.trash(size: number, color: Color3): Frame
	local f = box(size)
	rect(f, 0.5, 0.2, 0.7, 0.1, color, 0, 0.5)
	rect(f, 0.5, 0.12, 0.26, 0.08, color, 0, 0.5)
	local body = rect(f, 0.5, 0.6, 0.56, 0.62, color, 0, 0.15)
	body.BackgroundTransparency = 0
	return f
end

function Icons.close(size: number, color: Color3): Frame
	local f = box(size)
	rect(f, 0.5, 0.5, 0.9, 0.14, color, 45, 0.5)
	rect(f, 0.5, 0.5, 0.9, 0.14, color, -45, 0.5)
	return f
end

function Icons.house(size: number, color: Color3): Frame
	local f = box(size)
	local roofClip = New("Frame", {
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(1, 0.48),
		Parent = f,
	})
	rect(roofClip, 0.5, 1, 0.66, 1.38, color, 45, 0.1)
	rect(f, 0.5, 0.7, 0.66, 0.44, color, 0, 0.08)
	rect(f, 0.5, 0.78, 0.18, 0.28, Color3.new(1, 1, 1), 0, 0.2).BackgroundTransparency = 0.15
	return f
end

function Icons.helmet(size: number, color: Color3): Frame
	local f = box(size)
	local clip = New("Frame", {
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Position = UDim2.fromScale(0, 0.12),
		Size = UDim2.fromScale(1, 0.5),
		Parent = f,
	})
	rect(clip, 0.5, 1, 0.78, 1.56, color, 0, 1)
	rect(f, 0.5, 0.66, 0.96, 0.14, color, 0, 0.5)
	rect(f, 0.5, 0.82, 0.12, 0.2, color, 0, 0.5)
	return f
end

function Icons.flask(size: number, color: Color3): Frame
	local f = box(size)
	rect(f, 0.5, 0.24, 0.22, 0.36, color, 0, 0.15)
	circle(f, 0.5, 0.64, 0.62, color)
	rect(f, 0.5, 0.1, 0.36, 0.08, color, 0, 0.5)
	return f
end

function Icons.bolt(size: number, color: Color3): Frame
	local f = box(size)
	rect(f, 0.58, 0.3, 0.16, 0.5, color, 25, 0.2)
	rect(f, 0.5, 0.5, 0.42, 0.13, color, 0, 0.3)
	rect(f, 0.42, 0.7, 0.16, 0.5, color, 25, 0.2)
	return f
end

function Icons.drop(size: number, color: Color3): Frame
	local f = box(size)
	circle(f, 0.5, 0.62, 0.6, color)
	rect(f, 0.5, 0.42, 0.42, 0.42, color, 45, 0.1)
	return f
end

function Icons.barrel(size: number, color: Color3): Frame
	local f = box(size)
	rect(f, 0.5, 0.5, 0.6, 0.8, color, 0, 0.18)
	rect(f, 0.5, 0.36, 0.64, 0.07, Color3.new(1, 1, 1), 0, 0.5).BackgroundTransparency = 0.5
	rect(f, 0.5, 0.64, 0.64, 0.07, Color3.new(1, 1, 1), 0, 0.5).BackgroundTransparency = 0.5
	return f
end

function Icons.beam(size: number, color: Color3): Frame
	local f = box(size)
	rect(f, 0.5, 0.2, 0.8, 0.14, color, 0, 0.1)
	rect(f, 0.5, 0.8, 0.8, 0.14, color, 0, 0.1)
	rect(f, 0.5, 0.5, 0.16, 0.66, color, 0, 0.1)
	return f
end

function Icons.gift(size: number, color: Color3): Frame
	local f = box(size)
	rect(f, 0.5, 0.64, 0.72, 0.56, color, 0, 0.1)
	rect(f, 0.5, 0.36, 0.84, 0.16, color, 0, 0.15)
	rect(f, 0.5, 0.58, 0.12, 0.7, Color3.new(1, 1, 1), 0, 0).BackgroundTransparency = 0.25
	ring(f, 0.38, 0.18, 0.24, color, math.max(1.5, size / 14))
	ring(f, 0.62, 0.18, 0.24, color, math.max(1.5, size / 14))
	return f
end

function Icons.cart(size: number, color: Color3): Frame
	local f = box(size)
	rect(f, 0.54, 0.44, 0.62, 0.36, color, 0, 0.15)
	rect(f, 0.16, 0.2, 0.26, 0.1, color, 20, 0.5)
	circle(f, 0.34, 0.84, 0.18, color)
	circle(f, 0.72, 0.84, 0.18, color)
	return f
end

function Icons.calendar(size: number, color: Color3): Frame
	local f = box(size)
	rect(f, 0.5, 0.58, 0.8, 0.7, color, 0, 0.12)
	rect(f, 0.5, 0.66, 0.6, 0.38, Color3.new(1, 1, 1), 0, 0.08).BackgroundTransparency = 0.2
	rect(f, 0.32, 0.18, 0.1, 0.22, color, 0, 0.5)
	rect(f, 0.68, 0.18, 0.1, 0.22, color, 0, 0.5)
	return f
end

function Icons.tank(size: number, color: Color3): Frame
	local f = box(size)
	rect(f, 0.5, 0.7, 0.9, 0.26, color, 0, 0.5)
	rect(f, 0.46, 0.46, 0.44, 0.24, color, 0, 0.3)
	rect(f, 0.76, 0.4, 0.46, 0.08, color, 0, 0.5)
	return f
end

function Icons.truck(size: number, color: Color3): Frame
	local f = box(size)
	rect(f, 0.4, 0.5, 0.56, 0.4, color, 0, 0.1)
	rect(f, 0.8, 0.56, 0.24, 0.28, color, 0, 0.15)
	circle(f, 0.26, 0.8, 0.18, color)
	circle(f, 0.74, 0.8, 0.18, color)
	return f
end

function Icons.rocket(size: number, color: Color3): Frame
	local f = box(size)
	rect(f, 0.5, 0.5, 0.2, 0.7, color, 35, 0.5)
	rect(f, 0.33, 0.73, 0.1, 0.24, color, 35 + 90, 0.3)
	rect(f, 0.62, 0.8, 0.1, 0.24, color, 35, 0.3)
	return f
end

function Icons.target(size: number, color: Color3): Frame
	local f = box(size)
	ring(f, 0.5, 0.5, 0.8, color, math.max(1.5, size / 14))
	ring(f, 0.5, 0.5, 0.4, color, math.max(1.5, size / 14))
	circle(f, 0.5, 0.5, 0.12, color)
	return f
end

function Icons.map(size: number, color: Color3): Frame
	local f = box(size)
	circle(f, 0.5, 0.36, 0.56, color)
	rect(f, 0.5, 0.62, 0.32, 0.32, color, 45, 0.1)
	circle(f, 0.5, 0.36, 0.22, Color3.new(1, 1, 1))
	return f
end

function Icons.ticket(size: number, color: Color3): Frame
	local f = box(size)
	rect(f, 0.5, 0.5, 0.86, 0.52, color, -15, 0.12)
	circle(f, 0.12, 0.56, 0.2, Color3.new(1, 1, 1)).BackgroundTransparency = 0.6
	return f
end

function Icons.star(size: number, color: Color3): Frame
	local f = box(size)
	for i = 0, 4 do
		rect(f, 0.5, 0.52, 0.2, 0.86, color, i * 36, 0.2)
	end
	return f
end

function Icons.shield(size: number, color: Color3): Frame
	local f = box(size)
	rect(f, 0.5, 0.36, 0.72, 0.5, color, 0, 0.15)
	rect(f, 0.5, 0.6, 0.5, 0.5, color, 45, 0.15)
	return f
end

function Icons.undo(size: number, color: Color3): Frame
	local f = box(size)
	local arc = ring(f, 0.55, 0.55, 0.66, color, math.max(1.5, size / 9))
	local cover = rect(f, 0.3, 0.75, 0.42, 0.42, Color3.new(1, 1, 1), 0, 0)
	cover.BackgroundTransparency = 1
	rect(f, 0.24, 0.3, 0.32, 0.12, color, -40, 0.5)
	rect(f, 0.3, 0.42, 0.32, 0.12, color, 50, 0.5)
	local _ = arc
	return f
end

function Icons.heli(size: number, color: Color3): Frame
	local f = box(size)
	rect(f, 0.5, 0.18, 0.92, 0.07, color, 0, 0.5) -- rotor
	rect(f, 0.5, 0.27, 0.07, 0.14, color)
	rect(f, 0.42, 0.52, 0.5, 0.3, color, 0, 0.45) -- cabin
	rect(f, 0.78, 0.46, 0.38, 0.08, color, 0, 0.5) -- tail boom
	rect(f, 0.94, 0.38, 0.06, 0.2, color)
	rect(f, 0.42, 0.8, 0.56, 0.05, color) -- skid
	return f
end

function Icons.soldier(size: number, color: Color3): Frame
	local f = box(size)
	rect(f, 0.5, 0.2, 0.38, 0.22, color, 0, 1) -- helmet
	rect(f, 0.5, 0.29, 0.26, 0.12, color, 0, 0.4)
	rect(f, 0.5, 0.56, 0.42, 0.38, color, 0, 0.15) -- torso
	rect(f, 0.38, 0.86, 0.14, 0.26, color, 0, 0.2)
	rect(f, 0.62, 0.86, 0.14, 0.26, color, 0, 0.2)
	rect(f, 0.62, 0.5, 0.62, 0.07, color, -12, 0.5) -- rifle
	return f
end

function Icons.wheat(size: number, color: Color3): Frame
	local f = box(size)
	rect(f, 0.5, 0.62, 0.06, 0.66, color)
	for i = 0, 3 do
		local y = 0.2 + i * 0.13
		rect(f, 0.38, y, 0.16, 0.1, color, 30, 1)
		rect(f, 0.62, y, 0.16, 0.1, color, -30, 1)
	end
	return f
end

function Icons.get(name: string, size: number, color: Color3?): Frame
	local fn = (Icons :: any)[name]
	if type(fn) ~= "function" then
		fn = Icons.star
	end
	return fn(size, color or Theme.Color.Text)
end

return Icons
