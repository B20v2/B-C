--[[
	Lib
	Tiny declarative UI helpers. Everything in the game UI is built in code
	with these, so the whole interface stays consistent and needs no assets.

	Lib.New("Frame", { Size = ..., Activated = function() end }, { children })
	  * function values on signal properties are connected
	  * children may be Instances or nested arrays
]]

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent.Theme)

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

function Lib.corner(r: number?): UICorner
	return New("UICorner", { CornerRadius = UDim.new(0, r or Theme.Radius.Card) })
end

function Lib.round(): UICorner
	return New("UICorner", { CornerRadius = UDim.new(1, 0) })
end

function Lib.stroke(color: Color3?, thickness: number?, transparency: number?): UIStroke
	return New("UIStroke", {
		Color = color or Theme.Color.CardStroke,
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

-- Text label with theme defaults. props override anything.
function Lib.text(props: { [string]: any }, children: { any }?): TextLabel
	local p = {
		BackgroundTransparency = 1,
		FontFace = Theme.Font.Semi,
		TextColor3 = Theme.Color.Text,
		TextSize = Theme.TextSize.Body,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Size = UDim2.new(1, 0, 0, 20),
		TextTruncate = Enum.TextTruncate.AtEnd,
	}
	for k, v in props do
		p[k] = v
	end
	return New("TextLabel", p, children)
end

-- Small uppercase caption ("OIL STORED").
function Lib.caption(text: string, props: { [string]: any }?): TextLabel
	local p = {
		Text = string.upper(text),
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = Theme.Color.Muted,
		FontFace = Theme.Font.Semi,
		Size = UDim2.new(1, 0, 0, 14),
	}
	if props then
		for k, v in props do
			p[k] = v
		end
	end
	return Lib.text(p)
end

local clickSound: Sound? = nil
function Lib.setClickSound(s: Sound)
	clickSound = s
end

-- Button with hover / press feedback.
function Lib.button(props: { [string]: any }, children: { any }?): TextButton
	local p = {
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Color.Card,
		FontFace = Theme.Font.Semi,
		TextColor3 = Theme.Color.Text,
		TextSize = Theme.TextSize.Small,
		Text = "",
		Size = UDim2.fromOffset(120, 36),
	}
	local onClick = props.Activated
	for k, v in props do
		if k ~= "Activated" then
			p[k] = v
		end
	end
	local btn = New("TextButton", p, children) :: TextButton
	btn:SetAttribute("Base", btn.BackgroundColor3)
	local scale = New("UIScale", { Parent = btn })
	local function base(): Color3
		return (btn:GetAttribute("Base") :: Color3?) or btn.BackgroundColor3
	end
	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = base():Lerp(Color3.new(1, 1, 1), 0.25) }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = base() }):Play()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1 }):Play()
	end)
	btn.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.06), { Scale = 0.96 }):Play()
	end)
	btn.MouseButton1Up:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1 }):Play()
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

function Lib.panel(props: { [string]: any }, children: { any }?): Frame
	local p = {
		BackgroundColor3 = Theme.Color.Panel,
		BorderSizePixel = 0,
	}
	for k, v in props do
		p[k] = v
	end
	local f = New("Frame", p, children)
	Lib.corner(Theme.Radius.Panel).Parent = f
	Lib.stroke(Theme.Color.PanelStroke).Parent = f
	return f
end

function Lib.card(props: { [string]: any }, children: { any }?): Frame
	local p = {
		BackgroundColor3 = Theme.Color.Card,
		BorderSizePixel = 0,
	}
	for k, v in props do
		p[k] = v
	end
	local f = New("Frame", p, children)
	Lib.corner(Theme.Radius.Card).Parent = f
	Lib.stroke(Theme.Color.CardStroke).Parent = f
	return f
end

-- Soft drop shadow behind a frame (no image assets needed).
function Lib.shadow(target: GuiObject)
	local s = New("Frame", {
		Name = "Shadow",
		BackgroundColor3 = Theme.Color.Shadow,
		BackgroundTransparency = 0.82,
		Size = UDim2.new(1, 6, 1, 8),
		Position = UDim2.fromOffset(-3, 2),
		ZIndex = target.ZIndex - 1,
		BorderSizePixel = 0,
	}, { Lib.corner(Theme.Radius.Panel + 3) })
	s.Parent = target.Parent
	-- keep shadow glued to target
	local function sync()
		s.Size = UDim2.new(target.Size.X.Scale, target.Size.X.Offset + 6, target.Size.Y.Scale, target.Size.Y.Offset + 8)
		s.Position = UDim2.new(target.Position.X.Scale, target.Position.X.Offset - 3, target.Position.Y.Scale, target.Position.Y.Offset + 2)
		s.AnchorPoint = target.AnchorPoint
		s.Visible = target.Visible
	end
	sync()
	target:GetPropertyChangedSignal("Size"):Connect(sync)
	target:GetPropertyChangedSignal("Position"):Connect(sync)
	target:GetPropertyChangedSignal("Visible"):Connect(sync)
	return s
end

-- Coloured chip with text ("$12000", "48s", "Locked").
function Lib.chip(text: string, bg: Color3, fg: Color3, props: { [string]: any }?): Frame
	local label = Lib.text({
		Name = "Label",
		Text = text,
		TextColor3 = fg,
		TextSize = Theme.TextSize.Small,
		FontFace = Theme.Font.Bold,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
	})
	local p = {
		BackgroundColor3 = bg,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 22),
		BorderSizePixel = 0,
	}
	if props then
		for k, v in props do
			p[k] = v
		end
	end
	return New("Frame", p, { Lib.corner(Theme.Radius.Chip), Lib.pad(0, 8), label })
end

export type Progress = { frame: Frame, set: (number, Color3?) -> () }

function Lib.progress(props: { [string]: any }?): Progress
	local fill = New("Frame", {
		Name = "Fill",
		BackgroundColor3 = Theme.Color.Accent,
		Size = UDim2.fromScale(0, 1),
		BorderSizePixel = 0,
	}, { Lib.round() })
	local p = {
		BackgroundColor3 = Theme.Color.Track,
		Size = UDim2.new(1, 0, 0, 5),
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}
	if props then
		for k, v in props do
			p[k] = v
		end
	end
	local frame = New("Frame", p, { Lib.round(), fill })
	return {
		frame = frame,
		set = function(frac: number, color: Color3?)
			frac = math.clamp(frac, 0, 1)
			fill.Size = UDim2.fromScale(frac, 1)
			fill.BackgroundColor3 = color or (frac >= 0.995 and Theme.Color.Amber or Theme.Color.Accent)
		end,
	}
end

-- 3D thumbnail of a model (build cards, panel headers).
function Lib.viewport(model: Model, props: { [string]: any }?, angle: number?): ViewportFrame
	local p = {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Ambient = Color3.fromRGB(190, 196, 206),
		LightColor = Color3.fromRGB(255, 252, 245),
		LightDirection = Vector3.new(-1, -2, -0.6),
	}
	if props then
		for k, v in props do
			p[k] = v
		end
	end
	local vp = New("ViewportFrame", p) :: ViewportFrame
	local clone = model:Clone()
	clone:PivotTo(CFrame.new())
	clone.Parent = vp
	local cf, size = clone:GetBoundingBox()
	local radius = size.Magnitude / 2
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	local dir = (CFrame.Angles(0, math.rad(angle or 35), 0) * CFrame.Angles(math.rad(-32), 0, 0)).LookVector
	local dist = radius / math.sin(math.rad(cam.FieldOfView / 2)) * 0.92
	cam.CFrame = CFrame.lookAt(cf.Position - dir * dist, cf.Position)
	cam.Parent = vp
	vp.CurrentCamera = cam
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
