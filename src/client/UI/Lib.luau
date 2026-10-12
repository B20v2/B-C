--[[
	Lib
	Declarative UI helpers + the Field Command component set. Everything in
	the game UI is built from these, so the whole interface stays consistent
	and needs no uploaded images.

	Lib.New("Frame", { Size = ..., Activated = function() end }, { children })
	  * function values on signal properties are connected
	  * children may be Instances or nested arrays (nil holes are skipped)
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent.Theme)

local C = Theme.Color
local Lib = {}

local function applyChildren(parent: Instance, children: { any }?)
	if not children then
		return
	end
	for _, child in children do
		if typeof(child) == "Instance" then
			child.Parent = parent
		elseif type(child) == "table" then
			applyChildren(parent, child)
		end
	end
end

function Lib.New(className: string, props: { [string]: any }?, children: { any }?): any
	local inst = Instance.new(className)
	local parent = nil
	if props then
		for k, v in props do
			if k == "Parent" then
				parent = v
			elseif type(v) == "function" then
				((inst :: any)[k] :: RBXScriptSignal):Connect(v)
			else
				(inst :: any)[k] = v
			end
		end
	end
	applyChildren(inst, children)
	if parent then
		inst.Parent = parent
	end
	return inst
end

local New = Lib.New

local function merge(base: { [string]: any }, over: { [string]: any }?): { [string]: any }
	if over then
		for k, v in over do
			base[k] = v
		end
	end
	return base
end
Lib.merge = merge

---------------------------------------------------------------------------
-- layout primitives
---------------------------------------------------------------------------
function Lib.corner(r: number?): UICorner
	return New("UICorner", { CornerRadius = UDim.new(0, r or Theme.Radius.Card) })
end

function Lib.round(): UICorner
	return New("UICorner", { CornerRadius = UDim.new(1, 0) })
end

function Lib.stroke(color: Color3?, thickness: number?, transparency: number?): UIStroke
	return New("UIStroke", {
		Color = color or C.Line,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Lib.pad(t: number, r: number?, b: number?, l: number?): UIPadding
	return New("UIPadding", {
		PaddingTop = UDim.new(0, t),
		PaddingRight = UDim.new(0, r or t),
		PaddingBottom = UDim.new(0, b or t),
		PaddingLeft = UDim.new(0, l or r or t),
	})
end

function Lib.list(direction: string?, gap: number?, hAlign: Enum.HorizontalAlignment?, vAlign: Enum.VerticalAlignment?): UIListLayout
	return New("UIListLayout", {
		FillDirection = direction == "x" and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, gap or 0),
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

function Lib.grid(cell: UDim2, gap: number): UIGridLayout
	return New("UIGridLayout", {
		CellSize = cell,
		CellPadding = UDim2.fromOffset(gap, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

function Lib.frame(props: { [string]: any }?, children: { any }?): Frame
	return New("Frame", merge({ BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) }, props), children)
end

---------------------------------------------------------------------------
-- text
---------------------------------------------------------------------------
function Lib.text(props: { [string]: any }, children: { any }?): TextLabel
	return New("TextLabel", merge({
		BackgroundTransparency = 1,
		FontFace = Theme.Font.Body,
		TextColor3 = C.Text,
		TextSize = Theme.TextSize.Body,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Size = UDim2.new(1, 0, 0, 20),
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, props), children)
end

-- Stencil heading / number.
function Lib.display(props: { [string]: any }, children: { any }?): TextLabel
	return Lib.text(merge({ FontFace = Theme.Font.Display, TextSize = Theme.TextSize.Title }, props), children)
end

-- Small uppercase label ("OIL STORED").
function Lib.caption(text: string, props: { [string]: any }?): TextLabel
	return Lib.text(merge({
		Text = string.upper(text),
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = C.Muted,
		FontFace = Theme.Font.Display,
		Size = UDim2.new(1, 0, 0, 14),
	}, props))
end

---------------------------------------------------------------------------
-- surfaces
---------------------------------------------------------------------------
-- Corner brackets: the signature frame motif (echoes the targeting reticle).
function Lib.brackets(target: GuiObject, color: Color3?, len: number?, thick: number?, out: number?): Frame
	local col = color or C.Accent
	local l, t, o = len or 10, thick or 2, out or 3
	local holder = New("Frame", {
		Name = "Brackets",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, o * 2, 1, o * 2),
		Position = UDim2.fromOffset(-o, -o),
		ZIndex = target.ZIndex + 1,
		Parent = target,
	})
	for _, c in { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } } do
		local corner = New("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(c[1], c[2]),
			Position = UDim2.fromScale(c[1], c[2]),
			Size = UDim2.fromOffset(l, l),
			ZIndex = target.ZIndex + 1,
			Parent = holder,
		})
		New("Frame", { BackgroundColor3 = col, BorderSizePixel = 0, Size = UDim2.fromOffset(l, t), Position = UDim2.fromOffset(0, c[2] == 0 and 0 or l - t), ZIndex = target.ZIndex + 1, Parent = corner })
		New("Frame", { BackgroundColor3 = col, BorderSizePixel = 0, Size = UDim2.fromOffset(t, l), Position = UDim2.fromOffset(c[1] == 0 and 0 or l - t, 0), ZIndex = target.ZIndex + 1, Parent = corner })
	end
	return holder
end

function Lib.panel(props: { [string]: any }, children: { any }?): Frame
	local f = New("Frame", merge({
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = Theme.Transparency.Panel,
		BorderSizePixel = 0,
	}, props), children)
	Lib.corner(Theme.Radius.Panel).Parent = f
	Lib.stroke(C.Line, 1, 0.35).Parent = f
	-- faint top sheen
	New("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(205, 210, 205)),
		Rotation = 90,
		Parent = f,
	})
	return f
end

function Lib.card(props: { [string]: any }, children: { any }?): Frame
	local f = New("Frame", merge({ BackgroundColor3 = C.Raised, BorderSizePixel = 0 }, props), children)
	Lib.corner(Theme.Radius.Card).Parent = f
	Lib.stroke(C.LineSoft, 1, 0).Parent = f
	return f
end

-- Recessed well (bars, inputs, viewports).
function Lib.inset(props: { [string]: any }, children: { any }?): Frame
	local f = New("Frame", merge({ BackgroundColor3 = C.Inset, BorderSizePixel = 0 }, props), children)
	Lib.corner(Theme.Radius.Card).Parent = f
	return f
end

function Lib.divider(props: { [string]: any }?): Frame
	return New("Frame", merge({ BackgroundColor3 = C.Line, BackgroundTransparency = 0.4, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 1) }, props))
end

-- Diagonal hazard stripes drawn with a hard-stop gradient (no images).
function Lib.hazard(props: { [string]: any }?, a: Color3?, b: Color3?, stripes: number?): Frame
	local ca, cb = a or C.Accent, b or C.Ink
	local n = math.clamp(stripes or 8, 2, 9)
	local keys = {}
	for i = 0, n - 1 do
		local t0 = i / n
		local t1 = (i + 1) / n
		local col = i % 2 == 0 and ca or cb
		table.insert(keys, ColorSequenceKeypoint.new(t0, col))
		table.insert(keys, ColorSequenceKeypoint.new(math.max(t0, t1 - 0.001), col))
	end
	keys[#keys] = ColorSequenceKeypoint.new(1, keys[#keys].Value)
	return New("Frame", merge({ BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 6) }, props), {
		New("UIGradient", { Color = ColorSequence.new(keys), Rotation = 20 }),
	})
end

-- Legacy soft shadow (kept for compatibility, dark theme uses strokes).
function Lib.shadow(target: GuiObject)
	return target
end

---------------------------------------------------------------------------
-- controls
---------------------------------------------------------------------------
local clickSound: Sound? = nil
function Lib.setClickSound(s: Sound)
	clickSound = s
end

local VARIANTS = {
	primary = { bg = C.Accent, fg = C.OnAccent, stroke = nil, font = "Display" },
	secondary = { bg = C.Raised, fg = C.Text, stroke = C.Line, font = "Display" },
	ghost = { bg = C.Panel, fg = C.TextSoft, stroke = C.LineSoft, font = "Display" },
	good = { bg = Color3.fromRGB(70, 150, 60), fg = C.Text, stroke = nil, font = "Display" },
	danger = { bg = C.BadSoft, fg = C.Bad, stroke = C.Bad, font = "Display" },
	gold = { bg = C.Gold, fg = C.OnAccent, stroke = nil, font = "Display" },
	premium = { bg = Color3.fromRGB(110, 72, 170), fg = C.Text, stroke = C.Premium, font = "Display" },
}

-- Button with hover / press feedback. props.Variant picks a style.
function Lib.button(props: { [string]: any }, children: { any }?): TextButton
	local variant = VARIANTS[props.Variant or ""]
	local p = {
		AutoButtonColor = false,
		BackgroundColor3 = variant and variant.bg or C.Raised,
		FontFace = variant and Theme.Font.Display or Theme.Font.BodyBold,
		TextColor3 = variant and variant.fg or C.Text,
		TextSize = Theme.TextSize.Small,
		Text = "",
		Size = UDim2.fromOffset(120, 36),
		BorderSizePixel = 0,
	}
	local onClick = props.Activated
	for k, v in props do
		if k ~= "Activated" and k ~= "Variant" then
			p[k] = v
		end
	end
	local btn = New("TextButton", p, children) :: TextButton
	if variant then
		if not btn:FindFirstChildOfClass("UICorner") then
			Lib.corner(Theme.Radius.Button).Parent = btn
		end
		if variant.stroke and not btn:FindFirstChildOfClass("UIStroke") then
			Lib.stroke(variant.stroke, 1, 0.2).Parent = btn
		end
	end
	btn:SetAttribute("Base", btn.BackgroundColor3)
	local scale = New("UIScale", { Parent = btn })
	local function base(): Color3
		return (btn:GetAttribute("Base") :: Color3?) or btn.BackgroundColor3
	end
	btn.MouseEnter:Connect(function()
		local b = base()
		local lift = (b.R + b.G + b.B) / 3 > 0.5 and Color3.new(1, 1, 1) or Color3.fromRGB(90, 100, 92)
		TweenService:Create(btn, TweenInfo.new(0.1), { BackgroundColor3 = b:Lerp(lift, 0.22) }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = base() }):Play()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1 }):Play()
	end)
	btn.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.06), { Scale = 0.95 }):Play()
	end)
	btn.MouseButton1Up:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end)
	if onClick then
		btn.Activated:Connect(function(...)
			if clickSound then
				clickSound:Play()
			end
			onClick(...)
		end)
	end
	return btn
end

-- Set a button's resting colour (keeps hover logic correct).
function Lib.setButtonColor(btn: GuiButton, color: Color3)
	btn:SetAttribute("Base", color)
	btn.BackgroundColor3 = color
end

-- On/off switch. Returns the button and a setter.
function Lib.toggle(props: { [string]: any }, onChanged: (boolean) -> ()): (TextButton, (boolean) -> ())
	local state = false
	local btn = New("TextButton", merge({
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = C.Inset,
		Size = UDim2.fromOffset(52, 26),
		BorderSizePixel = 0,
	}, props), { Lib.round(), Lib.stroke(C.Line, 1, 0.3) })
	local knob = New("Frame", {
		BackgroundColor3 = C.Muted,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 3, 0.5, 0),
		Size = UDim2.fromOffset(20, 20),
		Parent = btn,
	}, { Lib.round() })
	local function set(on: boolean)
		state = on
		Lib.tween(knob, 0.15, { Position = on and UDim2.new(1, -23, 0.5, 0) or UDim2.new(0, 3, 0.5, 0), BackgroundColor3 = on and C.Bad or C.Muted })
		Lib.tween(btn, 0.15, { BackgroundColor3 = on and C.BadSoft or C.Inset })
	end
	btn.Activated:Connect(function()
		if clickSound then
			clickSound:Play()
		end
		onChanged(not state)
	end)
	return btn, set
end

function Lib.textbox(props: { [string]: any }): TextBox
	return New("TextBox", merge({
		Text = "",
		PlaceholderText = "",
		PlaceholderColor3 = C.Faint,
		FontFace = Theme.Font.BodyBold,
		TextSize = Theme.TextSize.Body,
		TextColor3 = C.Text,
		BackgroundColor3 = C.Inset,
		ClearTextOnFocus = false,
		Size = UDim2.new(1, 0, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
		BorderSizePixel = 0,
	}, props), { Lib.corner(Theme.Radius.Button), Lib.stroke(C.Line, 1, 0.3), Lib.pad(0, 12) })
end

function Lib.scroll(props: { [string]: any }?, children: { any }?): ScrollingFrame
	return New("ScrollingFrame", merge({
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = C.Accent,
		ScrollBarImageTransparency = 0.4,
	}, props), children)
end

---------------------------------------------------------------------------
-- data display
---------------------------------------------------------------------------
-- Chip: tinted label ("$12,000", "48s", "LOCKED").
function Lib.chip(text: string, bg: Color3, fg: Color3, props: { [string]: any }?): Frame
	local label = Lib.text({
		Name = "Label",
		Text = text,
		TextColor3 = fg,
		TextSize = Theme.TextSize.Tiny + 1,
		FontFace = Theme.Font.Display,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
	})
	return New("Frame", merge({
		BackgroundColor3 = bg,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
		BorderSizePixel = 0,
	}, props), { Lib.corner(Theme.Radius.Chip), Lib.pad(0, 7), label })
end

export type Progress = { frame: Frame, set: (number, Color3?) -> () }

-- Bar; props.Segments draws notch dividers for the "ammo" look.
function Lib.progress(props: { [string]: any }?): Progress
	local segments = props and props.Segments
	local p = {}
	if props then
		for k, v in props do
			if k ~= "Segments" then
				p[k] = v
			end
		end
	end
	local fill = New("Frame", {
		Name = "Fill",
		BackgroundColor3 = C.Accent,
		Size = UDim2.fromScale(0, 1),
		BorderSizePixel = 0,
	})
	local frame = New("Frame", merge({
		BackgroundColor3 = C.Inset,
		Size = UDim2.new(1, 0, 0, 5),
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, p), { Lib.corner(2), fill })
	if segments and segments > 1 then
		for i = 1, segments - 1 do
			New("Frame", {
				BackgroundColor3 = C.Panel,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(i / segments, 0),
				Size = UDim2.new(0, 2, 1, 0),
				ZIndex = 3,
				Parent = frame,
			})
		end
	end
	return {
		frame = frame,
		set = function(frac: number, color: Color3?)
			frac = math.clamp(frac, 0, 1)
			fill.Size = UDim2.fromScale(frac, 1)
			fill.BackgroundColor3 = color or (frac >= 0.995 and C.Gold or C.Accent)
		end,
	}
end

-- 3D thumbnail of a model. spin = degrees / second turntable.
function Lib.viewport(model: Model, props: { [string]: any }?, angle: number?, spin: number?): ViewportFrame
	local vp = New("ViewportFrame", merge({
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Ambient = Color3.fromRGB(150, 156, 150),
		LightColor = Color3.fromRGB(255, 244, 222),
		LightDirection = Vector3.new(-1, -2, -0.6),
	}, props)) :: ViewportFrame
	local clone = model:Clone()
	clone:PivotTo(CFrame.new())
	clone.Parent = vp
	local cf, size = clone:GetBoundingBox()
	local radius = size.Magnitude / 2
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.Parent = vp
	vp.CurrentCamera = cam
	local yaw = math.rad(angle or 35)
	local dist = radius / math.sin(math.rad(cam.FieldOfView / 2)) * 0.95
	local function place()
		local dir = (CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(-30), 0, 0)).LookVector
		cam.CFrame = CFrame.lookAt(cf.Position - dir * dist, cf.Position)
	end
	place()
	if spin and spin ~= 0 then
		local conn
		conn = RunService.Heartbeat:Connect(function(dt)
			-- stop once the window is gone (reading a destroyed instance can throw)
			local alive, parent = pcall(function()
				return vp.Parent
			end)
			if not alive or not parent then
				conn:Disconnect()
				return
			end
			yaw += math.rad(spin) * dt
			place()
		end)
	end
	return vp
end

function Lib.tween(inst: Instance, time: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween
	local t = TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

function Lib.serverNow(): number
	return Workspace:GetServerTimeNow()
end

-- Clear generated children but keep layout objects.
function Lib.clear(parent: Instance)
	for _, c in parent:GetChildren() do
		if not c:IsA("UIBase") then
			c:Destroy()
		end
	end
end

return Lib
