--[[
	CLTui.lua
	------------------------------------------------------------------
	Drop-in replacement for the UI library loaded by BloxFruits.lua
	(the remote zzzz.lua). Same API surface, new look.

	API implemented (everything the script actually calls):
		A.CreateMain({ Title, Desc })          -> Main
		A.CreateNoti({ Title, Desc, ShowTime })
		A.Options                               -> registry table

		Main.CreatePage({ Page_Name, Page_Title }) -> Page
		Page.CreateSection(name)                   -> Section

		Section.CreateToggle({ Title, Desc, Default }, cb)      cb(bool)
		Section.CreateButton({ Title }, cb)                     cb()
		Section.CreateSlider({ Title, Min, Max, Default,
		                       Precise, Step }, cb)             cb(number)
		Section.CreateDropdown({ Title, List, Search,
		                         Selected, Default }, cb)       cb(string)
		                                                        cb(key, bool) when Selected = true
		Section.CreateBox({ Title, Placeholder, Number,
		                    Default }, cb)                      cb(string)
		Section.CreateLabel({ Title })                          obj:SetText / obj:GetText
		Section.CreateBind({ Title, Key }, cb)                  cb() on key press

	Style: dark neo-brutalism. Near-black surfaces, paper-white
	borders and text, thick hard offset shadows (no blur) in the
	section accent colour, blue / cyan / pink / lime blocks,
	uppercase headings, monospace status lines.

	The main ScreenGui is named "CLT Hub GUI" on purpose: the
	script's own "Toggle GUI" bind (LeftControl) looks for that exact
	name in CoreGui and flips .Enabled. The mobile launcher bubble
	lives in a separate "CLTLauncher" ScreenGui so that bind can
	never hide it.
]]

if getgenv and getgenv().CLTui then
	return getgenv().CLTui
end

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")

-- ======================= palette =======================

local INK = Color3.fromRGB(10, 10, 10)
local BG = Color3.fromRGB(14, 14, 14)
local PANEL = Color3.fromRGB(22, 22, 22)
local SURFACE = Color3.fromRGB(31, 31, 31)
local RAISED = Color3.fromRGB(46, 46, 46)
local PAPER = Color3.fromRGB(245, 242, 232)
local BORDER = Color3.fromRGB(245, 242, 232)
local MUTED = Color3.fromRGB(150, 144, 130)
local BLUE = Color3.fromRGB(43, 92, 230)
local BLUE_LIGHT = Color3.fromRGB(96, 140, 255)
local BLUE_DARK = Color3.fromRGB(28, 66, 176)
local CYAN = Color3.fromRGB(35, 213, 255)
local PINK = Color3.fromRGB(255, 92, 138)
local LIME = Color3.fromRGB(183, 255, 76)
local PURPLE = Color3.fromRGB(192, 139, 255)
local ORANGE = Color3.fromRGB(255, 155, 74)

local ACCENTS = { BLUE, CYAN, PINK, LIME, PURPLE, ORANGE }

-- logo / launcher icon (decal uploaded by the hub owner)
local LOGO = "rbxassetid://98853113630447"

-- dark text on bright accents, paper text on the dark blue one
local function readableOn(c)
	local lum = 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
	return lum > 0.42 and INK or PAPER
end

-- ======================= helpers =======================

local function new(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props or {}) do
		inst[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

-- every child must get an explicit ZIndex: ScreenGui runs in Sibling mode
-- so a default ZIndex of 1 would drop labels behind their parent card.
local function child(parent, class, props)
	props = props or {}
	if props.ZIndex == nil then
		props.ZIndex = (parent.ZIndex or 1) + 1
	end
	return new(class, props, parent)
end

local function stroke(inst, thickness, color)
	return new("UIStroke", {
		Thickness = thickness or 2,
		Color = color or BORDER,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Miter,
	}, inst)
end

local function tw(inst, time, props)
	local t = TweenService:Create(
		inst,
		TweenInfo.new(time or 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		props
	)
	t:Play()
	return t
end

local function txt(parent, props)
	props = props or {}
	props.BackgroundTransparency = 1
	props.BorderSizePixel = 0
	props.TextColor3 = props.TextColor3 or PAPER
	props.Font = props.Font or Enum.Font.GothamBold
	props.TextSize = props.TextSize or 12
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	props.TextYAlignment = props.TextYAlignment or Enum.TextYAlignment.Center
	if props.TextTruncate == nil then
		props.TextTruncate = Enum.TextTruncate.AtEnd
	end
	return child(parent, "TextLabel", props)
end

local orderSeq = setmetatable({}, { __mode = "k" })

local function nextOrder(parent)
	local n = (orderSeq[parent] or 0) + 1
	orderSeq[parent] = n
	return n
end

-- base sits above every shell element (window bar/body sit around 9000)
local ZI = 20000

local function nextZI()
	ZI = ZI + 4
	return ZI
end

-- fixed-height row: transparent holder + shadow + bordered face.
-- the holder is what the UIListLayout positions, so the face can be
-- nudged on press without fighting the layout.
local function face(parent, height, bg, shColor)
	local zi = nextZI()
	local holder = new("Frame", {
		Name = "Row",
		Size = UDim2.new(1, 0, 0, height),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		LayoutOrder = nextOrder(parent),
	}, parent)
	holder.ZIndex = zi

	local sh = new("Frame", {
		Name = "Shadow",
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.new(0, 4, 0, 4),
		BackgroundColor3 = shColor or PAPER,
		BorderSizePixel = 0,
	}, holder)
	sh.ZIndex = zi

	local card = new("TextButton", {
		Name = "Face",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = bg or SURFACE,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
	}, holder)
	card.ZIndex = zi + 1
	stroke(card, 2, BORDER)

	return holder, card, sh
end

local function hover(card, normal, hot)
	card.MouseEnter:Connect(function()
		tw(card, 0.1, { BackgroundColor3 = hot })
	end)
	card.MouseLeave:Connect(function()
		tw(card, 0.1, { BackgroundColor3 = normal })
	end)
end

local function fmtNum(v)
	if v % 1 == 0 then
		return tostring(math.floor(v))
	end
	return (string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", ""))
end

local function normalizeList(list)
	local out, seen = {}, {}
	if type(list) ~= "table" then
		return out
	end
	for _, v in ipairs(list) do
		local name = tostring(v)
		if not seen[name] then
			seen[name] = true
			out[#out + 1] = name
		end
	end
	for k, v in pairs(list) do
		if type(k) ~= "number" then
			local name = tostring(k)
			if not seen[name] then
				seen[name] = true
				out[#out + 1] = name
			end
		end
	end
	return out
end

-- ======================= library =======================

local Lib = {}
Lib.Options = {}

local UI = {
	screen = nil,
	window = nil,
	body = nil,
	sidebar = nil,
	content = nil,
	notiStack = nil,
	pages = {},
	notis = {},
}

local ctx = { page = nil, section = nil }

local function register(title, data)
	if title == nil then
		return nil
	end
	Lib.Options[tostring(title)] = data
	return data
end

-- ======================= window shell =======================

local function buildShell(cfg)
	cfg = cfg or {}

	local vp = Vector2.new(1280, 720)
	pcall(function()
		if workspace.CurrentCamera then
			vp = workspace.CurrentCamera.ViewportSize
		end
	end)
	local W = math.max(620, math.min(880, math.floor(vp.X * 0.92)))
	local H = math.max(430, math.min(600, math.floor(vp.Y * 0.86)))

	local screen = new("ScreenGui", {
		Name = "CLT Hub GUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 5,
	})
	local ok = pcall(function()
		screen.Parent = CoreGui
	end)
	if not ok or not screen.Parent then
		pcall(function()
			screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		end)
	end
	UI.screen = screen

	-- ---------- window ----------

	local win = new("Frame", {
		Name = "NeoWindow",
		Size = UDim2.fromOffset(W, H),
		Position = UDim2.new(0.5, -math.floor(W / 2), 0.5, -math.floor(H / 2)),
		BackgroundColor3 = BG,
		BorderSizePixel = 0,
		ClipsDescendants = false,
	}, screen)
	win.ZIndex = 9000
	stroke(win, 3, PAPER)

	local winShadow = new("Frame", {
		Name = "Shadow",
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.new(0, 10, 0, 10),
		BackgroundColor3 = BLUE,
		BorderSizePixel = 0,
	}, win)
	winShadow.ZIndex = 8999

	UI.window = win

	-- ---------- title bar ----------

	local bar = child(win, "Frame", {
		Name = "TitleBar",
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundColor3 = BLUE,
		BorderSizePixel = 0,
	})

	child(bar, "Frame", {
		Size = UDim2.new(1, 0, 0, 3),
		Position = UDim2.new(0, 0, 1, -3),
		BackgroundColor3 = INK,
		BorderSizePixel = 0,
	})

	local logo = child(bar, "Frame", {
		Name = "Logo",
		Size = UDim2.new(0, 34, 0, 34),
		Position = UDim2.new(0, 13, 0, 11),
		BackgroundColor3 = PAPER,
		BorderSizePixel = 0,
		Rotation = -6,
	})
	stroke(logo, 2, INK)
	child(logo, "ImageLabel", {
		Name = "LogoImage",
		Size = UDim2.new(1, -6, 1, -6),
		Position = UDim2.new(0, 3, 0, 3),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = LOGO,
		ScaleType = Enum.ScaleType.Fit,
	})

	child(bar, "TextLabel", {
		Size = UDim2.new(0, 420, 0, 22),
		Position = UDim2.new(0, 58, 0, 8),
		BackgroundTransparency = 1,
		Text = string.upper(tostring(cfg.Title or "Neo Hub")),
		TextColor3 = PAPER,
		Font = Enum.Font.GothamBlack,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	local desc = tostring(cfg.Desc or ""):gsub("^%s*%-%s*", "")
	child(bar, "TextLabel", {
		Size = UDim2.new(0, 520, 0, 16),
		Position = UDim2.new(0, 59, 0, 31),
		BackgroundTransparency = 1,
		Text = string.upper(desc),
		TextColor3 = Color3.fromRGB(198, 214, 255),
		Font = Enum.Font.GothamBold,
		TextSize = 9,
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	local minBtn = child(bar, "TextButton", {
		Size = UDim2.new(0, 26, 0, 26),
		Position = UDim2.new(1, -74, 0, 15),
		BackgroundColor3 = PAPER,
		BorderSizePixel = 0,
		Text = "-",
		TextColor3 = INK,
		Font = Enum.Font.GothamBlack,
		TextSize = 18,
		AutoButtonColor = false,
	})
	stroke(minBtn, 2, INK)

	local closeBtn = child(bar, "TextButton", {
		Size = UDim2.new(0, 26, 0, 26),
		Position = UDim2.new(1, -40, 0, 15),
		BackgroundColor3 = PINK,
		BorderSizePixel = 0,
		Text = "X",
		TextColor3 = INK,
		Font = Enum.Font.GothamBlack,
		TextSize = 13,
		AutoButtonColor = false,
	})
	stroke(closeBtn, 2, INK)

	-- ---------- body / sidebar / content ----------

	local body = child(win, "Frame", {
		Name = "Body",
		Size = UDim2.new(1, 0, 1, -56),
		Position = UDim2.new(0, 0, 0, 56),
		BackgroundColor3 = BG,
		BorderSizePixel = 0,
	})
	UI.body = body

	local sidebar = child(body, "Frame", {
		Name = "Sidebar",
		Size = UDim2.new(0, 210, 1, 0),
		BackgroundColor3 = PANEL,
		BorderSizePixel = 0,
	})
	UI.sidebar = sidebar

	child(sidebar, "Frame", {
		Size = UDim2.new(0, 3, 1, 0),
		Position = UDim2.new(1, -3, 0, 0),
		BackgroundColor3 = PAPER,
		BorderSizePixel = 0,
	})

	txt(sidebar, {
		Size = UDim2.new(1, -24, 0, 16),
		Position = UDim2.new(0, 12, 0, 10),
		Text = "// PAGES",
		TextSize = 9,
		Font = Enum.Font.Code,
		TextColor3 = MUTED,
	})

	local pageList = child(sidebar, "ScrollingFrame", {
		Name = "PageList",
		Size = UDim2.new(1, 0, 1, -66),
		Position = UDim2.new(0, 0, 0, 30),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = PAPER,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ElasticBehavior = Enum.ElasticBehavior.Never,
	})
	new("UIPadding", {
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 12),
	}, pageList)
	new("UIListLayout", {
		Padding = UDim.new(0, 7),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, pageList)
	UI.pageList = pageList

	txt(sidebar, {
		Size = UDim2.new(1, -24, 0, 12),
		Position = UDim2.new(0, 12, 1, -26),
		Text = "NEO-BRUTAL // BUILT FOR AOID",
		TextSize = 8,
		Font = Enum.Font.Code,
		TextColor3 = MUTED,
	})

	local content = child(body, "Frame", {
		Name = "Content",
		Size = UDim2.new(1, -210, 1, 0),
		Position = UDim2.new(0, 210, 0, 0),
		BackgroundColor3 = BG,
		BorderSizePixel = 0,
	})
	UI.content = content

	-- ---------- notifications ----------

	local notiStack = new("Frame", {
		Name = "Notifications",
		Size = UDim2.new(0, 330, 0, 480),
		Position = UDim2.new(1, -346, 0, 16),
		BackgroundTransparency = 1,
	}, screen)
	notiStack.ZIndex = 200000
	new("UIListLayout", {
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, notiStack)
	UI.notiStack = notiStack

	-- ---------- window buttons ----------

	local collapsed = false
	minBtn.MouseButton1Click:Connect(function()
		collapsed = not collapsed
		body.Visible = not collapsed
		win.Size = collapsed and UDim2.fromOffset(W, 56) or UDim2.fromOffset(W, H)
		minBtn.Text = collapsed and "+" or "-"
	end)

	closeBtn.MouseButton1Click:Connect(function()
		win.Visible = false
	end)

	hover(minBtn, PAPER, Color3.fromRGB(228, 224, 212))
	hover(closeBtn, PINK, Color3.fromRGB(255, 150, 178))

	-- ---------- launcher bubble ----------
	-- Lives in its OWN ScreenGui so the hub's Ctrl bind (which only flips
	-- "CLT Hub GUI") can never take it off screen. The window itself
	-- is toggled from here.

	local launcherGui = new("ScreenGui", {
		Name = "CLTLauncher",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 50,
	})
	local lok = pcall(function()
		launcherGui.Parent = CoreGui
	end)
	if not lok or not launcherGui.Parent then
		pcall(function()
			launcherGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		end)
	end

	local bubble = new("TextButton", {
		Name = "NeoLauncher",
		Size = UDim2.new(0, 46, 0, 46),
		Position = UDim2.new(0, 14, 0, 92),
		BackgroundColor3 = BLUE,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
	}, launcherGui)
	bubble.ZIndex = 20
	stroke(bubble, 3, INK)

	local bs = new("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.new(0, 4, 0, 4),
		BackgroundColor3 = INK,
		BorderSizePixel = 0,
	}, bubble)
	bs.ZIndex = 19

	local iconBack = child(bubble, "Frame", {
		Name = "IconBack",
		Size = UDim2.new(1, -12, 1, -12),
		Position = UDim2.new(0, 6, 0, 6),
		BackgroundColor3 = PAPER,
		BorderSizePixel = 0,
	})
	child(iconBack, "ImageLabel", {
		Name = "Icon",
		Size = UDim2.new(1, -4, 1, -4),
		Position = UDim2.new(0, 2, 0, 2),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = LOGO,
		ScaleType = Enum.ScaleType.Fit,
	})

	local function toggleWindow()
		if screen.Enabled and win.Visible then
			win.Visible = false
		else
			screen.Enabled = true
			win.Visible = true
		end
	end

	local function clampPos(pos)
		local vp = Vector2.new(1280, 720)
		pcall(function()
			if workspace.CurrentCamera then
				vp = workspace.CurrentCamera.ViewportSize
			end
		end)
		local w = bubble.AbsoluteSize.X
		local h = bubble.AbsoluteSize.Y
		local x = math.clamp(pos.X.Offset, 4, math.max(4, vp.X - w - 4))
		local y = math.clamp(pos.Y.Offset, 4, math.max(4, vp.Y - h - 4))
		return UDim2.new(0, x, 0, y)
	end

	local bDragging, bMoved, bStart, bPos = false, false, nil, nil

	bubble.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			bDragging = true
			bMoved = false
			bStart = input.Position
			bPos = bubble.Position
		end
	end)

	UIS.InputChanged:Connect(function(input)
		if not bDragging then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch
		then
			local delta = input.Position - bStart
			if math.abs(delta.X) > 6 or math.abs(delta.Y) > 6 then
				bMoved = true
			end
			if bMoved then
				bubble.Position = clampPos(UDim2.new(0, bPos.X.Offset + delta.X, 0, bPos.Y.Offset + delta.Y))
			end
		end
	end)

	UIS.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			if bDragging and not bMoved then
				toggleWindow()
			end
			bDragging = false
		end
	end)

	pcall(function()
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			bubble.Position = clampPos(bubble.Position)
		end)
	end)

	UI.launcher = bubble
	UI.launcherGui = launcherGui

	-- ---------- drag ----------

	local dragging, dragStart, startPos

	bar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = true
			dragStart = input.Position
			startPos = win.Position
		end
	end)

	UIS.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch
		then
			local delta = input.Position - dragStart
			win.Position = UDim2.new(
				startPos.X.Scale,
				startPos.X.Offset + delta.X,
				startPos.Y.Scale,
				startPos.Y.Offset + delta.Y
			)
		end
	end)

	UIS.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = false
		end
	end)
end

-- ======================= page / section =======================

local createSection -- forward declaration, defined after the element builders

local function selectPage(page)
	for _, p in ipairs(UI.pages) do
		p.Container.Visible = (p == page)
		if p == page then
			tw(p.Button, 0.1, { BackgroundColor3 = BLUE })
			p.Button.TextColor3 = PAPER
			if p.Shadow then
				tw(p.Shadow, 0.1, { BackgroundColor3 = PAPER })
			end
		else
			tw(p.Button, 0.1, { BackgroundColor3 = SURFACE })
			p.Button.TextColor3 = PAPER
			if p.Shadow then
				tw(p.Shadow, 0.1, { BackgroundColor3 = RAISED })
			end
		end
	end
	ctx.page = page
end

local function createPage(pageCfg)
	pageCfg = pageCfg or {}
	local name = tostring(pageCfg.Page_Name or pageCfg.Page_Title or "Page")

	local page = {
		Name = name,
		Title = tostring(pageCfg.Page_Title or name),
	}

	local zi = nextZI()

	-- sidebar entry (holder + hard shadow + face)
	local holder = new("Frame", {
		Name = "PageRow",
		Size = UDim2.new(1, -4, 0, 32),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = nextOrder(UI.pageList),
	}, UI.pageList)
	holder.ZIndex = zi

	local sh = new("Frame", {
		Name = "Shadow",
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.new(0, 3, 0, 3),
		BackgroundColor3 = RAISED,
		BorderSizePixel = 0,
	}, holder)
	sh.ZIndex = zi

	local btn = new("TextButton", {
		Name = "PageButton",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = SURFACE,
		BorderSizePixel = 0,
		Text = string.upper(name),
		TextColor3 = PAPER,
		Font = Enum.Font.GothamBold,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		AutoButtonColor = false,
	}, holder)
	btn.ZIndex = zi + 1
	stroke(btn, 2, PAPER)
	new("UIPadding", { PaddingLeft = UDim.new(0, 9) }, btn)

	-- page scroll
	local scroll = child(UI.content, "ScrollingFrame", {
		Name = "Page_" .. name,
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = PAPER,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ElasticBehavior = Enum.ElasticBehavior.Never,
	})
	new("UIPadding", {
		PaddingTop = UDim.new(0, 14),
		PaddingBottom = UDim.new(0, 22),
		PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 16),
	}, scroll)
	new("UIListLayout", {
		Padding = UDim.new(0, 14),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, scroll)

	page.Button = btn
	page.Shadow = sh
	page.Container = scroll

	btn.MouseButton1Click:Connect(function()
		selectPage(page)
	end)

	UI.pages[#UI.pages + 1] = page
	if #UI.pages == 1 then
		selectPage(page)
	end

	ctx.page = page

	function page.CreateSection(sectionName)
		return createSection(page, sectionName)
	end

	return page
end

-- ======================= elements =======================

local function createToggle(sec, opts, cb)
	opts = opts or {}
	local title = tostring(opts.Title or "Toggle")
	local hasDesc = opts.Desc ~= nil
	local h = hasDesc and 58 or 44

	local _, card = face(sec.body, h, SURFACE, sec.accent)
	local zi = card.ZIndex

	txt(card, {
		Text = string.upper(title),
		Size = UDim2.new(1, -88, 0, 20),
		Position = UDim2.new(0, 12, 0, hasDesc and 8 or 12),
		TextSize = 11,
		TextColor3 = PAPER,
	})

	if hasDesc then
		txt(card, {
			Text = tostring(opts.Desc),
			Size = UDim2.new(1, -88, 0, 14),
			Position = UDim2.new(0, 12, 0, 28),
			TextSize = 9,
			Font = Enum.Font.Gotham,
			TextColor3 = MUTED,
		})
	end

	local sw = child(card, "Frame", {
		Size = UDim2.new(0, 54, 0, 26),
		Position = UDim2.new(1, -66, 0.5, -13),
		BackgroundColor3 = RAISED,
		BorderSizePixel = 0,
	})
	stroke(sw, 2, PAPER)

	local knob = child(sw, "Frame", {
		Size = UDim2.new(0, 20, 0, 20),
		Position = UDim2.new(0, 2, 0, 2),
		BackgroundColor3 = PAPER,
		BorderSizePixel = 0,
	})
	stroke(knob, 2, INK)

	local value = opts.Default == true

	local opt = {
		type = "toggle",
		Page_Name = sec.Page_Name,
		Section_Name = sec.Name,
		value = value,
		FunctionCreate = nil,
	}

	local function apply(v)
		value = v == true
		opt.value = value
		tw(sw, 0.12, { BackgroundColor3 = value and LIME or RAISED })
		tw(knob, 0.12, { Position = UDim2.new(0, value and 29 or 2, 0, 2) })
	end

	local api = {}

	function api.SetValue(a, b)
		local v = b ~= nil and b or a
		if v == nil then
			return
		end
		apply(v)
		if cb then
			cb(v == true)
		end
	end

	opt.FunctionCreate = api
	register(title, opt)

	card.MouseButton1Click:Connect(function()
		api.SetValue(not value)
	end)

	apply(value)
	return api
end

local function createButton(sec, opts, cb)
	opts = opts or {}
	local title = tostring(opts.Title or "Button")
	local _, card, sh = face(sec.body, 40, BLUE)
	local zi = card.ZIndex

	child(card, "TextLabel", {
		Size = UDim2.new(1, -20, 1, 0),
		Position = UDim2.new(0, 10, 0, 0),
		BackgroundTransparency = 1,
		Text = string.upper(title),
		TextColor3 = PAPER,
		Font = Enum.Font.GothamBlack,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	local opt = {
		type = "button",
		Page_Name = sec.Page_Name,
		Section_Name = sec.Name,
		value = title,
		FunctionCreate = nil,
	}

	local api = {}
	local basePos = UDim2.new(0, 0, 0, 0)

	card.MouseButton1Down:Connect(function()
		tw(card, 0.05, { Position = UDim2.new(0, 4, 0, 4), BackgroundColor3 = BLUE_DARK })
		sh.Visible = false
	end)

	card.MouseButton1Up:Connect(function()
		tw(card, 0.08, { Position = basePos, BackgroundColor3 = BLUE })
		sh.Visible = true
	end)

	card.MouseLeave:Connect(function()
		tw(card, 0.08, { Position = basePos, BackgroundColor3 = BLUE })
		sh.Visible = true
	end)

	card.MouseButton1Click:Connect(function()
		if cb then
			local ok, err = pcall(cb)
			if not ok then
				warn("[CLTui] button '" .. title .. "' failed: " .. tostring(err))
			end
		end
	end)

	opt.FunctionCreate = api
	register(title, opt)

	hover(card, BLUE, BLUE_LIGHT)
	return api
end

local function createSlider(sec, opts, cb)
	opts = opts or {}
	local title = tostring(opts.Title or "Slider")
	local mn = tonumber(opts.Min) or 0
	local mx = tonumber(opts.Max) or 100
	if mx < mn then
		mn, mx = mx, mn
	end
	local step = tonumber(opts.Step) or 1
	if step <= 0 then
		step = 1
	end
	local value = tonumber(opts.Default) or mn
	value = math.clamp(value, mn, mx)

	local _, card = face(sec.body, 58, SURFACE, sec.accent)
	local zi = card.ZIndex

	txt(card, {
		Text = string.upper(title),
		Size = UDim2.new(1, -100, 0, 16),
		Position = UDim2.new(0, 12, 0, 8),
		TextSize = 11,
	})

	local badge = child(card, "TextLabel", {
		Size = UDim2.new(0, 56, 0, 18),
		Position = UDim2.new(1, -68, 0, 7),
		BackgroundColor3 = BLUE,
		BorderSizePixel = 0,
		Text = fmtNum(value),
		TextColor3 = PAPER,
		Font = Enum.Font.Code,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	local track = child(card, "Frame", {
		Size = UDim2.new(1, -24, 0, 10),
		Position = UDim2.new(0, 12, 0, 38),
		BackgroundColor3 = RAISED,
		BorderSizePixel = 0,
	})
	stroke(track, 2, PAPER)

	local fill = child(track, "Frame", {
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = PINK,
		BorderSizePixel = 0,
	})

	local knob = child(track, "Frame", {
		Size = UDim2.new(0, 14, 0, 18),
		Position = UDim2.new(0, -7, 0.5, -9),
		BackgroundColor3 = PAPER,
		BorderSizePixel = 0,
	})
	stroke(knob, 2, INK)

	local opt = {
		type = "slider",
		Page_Name = sec.Page_Name,
		Section_Name = sec.Name,
		min = mn,
		max = mx,
		step = step,
		value = value,
		FunctionCreate = nil,
	}

	local function paint(v)
		local p = (mx == mn) and 0 or (v - mn) / (mx - mn)
		fill.Size = UDim2.new(p, 0, 1, 0)
		knob.Position = UDim2.new(p, -7, 0.5, -9)
		badge.Text = fmtNum(v)
	end

	local api = {}

	function api.SetValue(a, b)
		local v = tonumber(b ~= nil and b or a)
		if v == nil then
			return
		end
		value = math.clamp(v, mn, mx)
		opt.value = value
		paint(value)
		if cb then
			cb(value)
		end
	end

	local function fromX(px)
		local rel = (px - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1)
		rel = math.clamp(rel, 0, 1)
		local raw = mn + rel * (mx - mn)
		local snapped = math.floor((raw - mn) / step + 0.5) * step + mn
		snapped = math.clamp(snapped, mn, mx)
		if math.abs(snapped - value) < (step / 1000) then
			return
		end
		api.SetValue(snapped)
	end

	local dragging = false

	local function grab(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = true
			fromX(input.Position.X)
		end
	end

	card.InputBegan:Connect(grab)
	track.InputBegan:Connect(grab)
	knob.InputBegan:Connect(grab)

	UIS.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch
		then
			fromX(input.Position.X)
		end
	end)

	UIS.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = false
		end
	end)

	opt.FunctionCreate = api
	register(title, opt)

	paint(value)
	return api
end

local function createLabel(sec, opts)
	opts = opts or {}
	local title = tostring(opts.Title or "")

	local long = #title > 58

	local holder = new("Frame", {
		Size = UDim2.new(1, 0, 0, long and 34 or 22),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = nextOrder(sec.body),
	}, sec.body)
	holder.ZIndex = nextZI()

	child(holder, "Frame", {
		Size = UDim2.new(0, 6, 0, 6),
		Position = UDim2.new(0, 2, 0, long and 6 or 0.5),
		AnchorPoint = long and Vector2.new(0, 0) or Vector2.new(0, 0.5),
		BackgroundColor3 = PAPER,
		BorderSizePixel = 0,
	})

	local label = child(holder, "TextLabel", {
		Size = UDim2.new(1, -16, 1, 0),
		Position = UDim2.new(0, 16, 0, 0),
		BackgroundTransparency = 1,
		Text = title,
		TextColor3 = PAPER,
		Font = Enum.Font.Code,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = long and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center,
		TextWrapped = long,
		TextTruncate = long and Enum.TextTruncate.None or Enum.TextTruncate.AtEnd,
	})

	local opt = {
		type = "textlabel",
		Page_Name = sec.Page_Name,
		Section_Name = sec.Name,
		text = title,
		color = "#f5f2e8",
		size = "11px",
		bold = false,
		value = title,
		FunctionCreate = nil,
	}

	local api = {}

	function api.SetText(a, b)
		local t = b ~= nil and b or a
		t = tostring(t)
		label.Text = t
		opt.text = t
		opt.value = t
	end

	function api.GetText()
		return label.Text
	end

	opt.FunctionCreate = api
	register(title ~= "" and title or nil, opt)

	return api
end

local function createBox(sec, opts, cb)
	opts = opts or {}
	local title = tostring(opts.Title or "Input")
	local value = opts.Default ~= nil and tostring(opts.Default) or ""

	local _, card = face(sec.body, 74, SURFACE, sec.accent)
	local zi = card.ZIndex

	txt(card, {
		Text = string.upper(title),
		Size = UDim2.new(1, -24, 0, 16),
		Position = UDim2.new(0, 12, 0, 8),
		TextSize = 10,
	})

	local box = child(card, "TextBox", {
		Size = UDim2.new(1, -24, 0, 30),
		Position = UDim2.new(0, 12, 0, 30),
		BackgroundColor3 = INK,
		BorderSizePixel = 0,
		Text = value,
		PlaceholderText = tostring(opts.Placeholder or "Type here"),
		PlaceholderColor3 = MUTED,
		TextColor3 = PAPER,
		Font = Enum.Font.Code,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
	})
	stroke(box, 2, PAPER)
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, box)

	local opt = {
		type = "box",
		Page_Name = sec.Page_Name,
		Section_Name = sec.Name,
		value = value,
		FunctionCreate = nil,
	}

	local api = {}

	function api.SetValue(a, b)
		local v = b ~= nil and b or a
		if v == nil then
			return
		end
		value = tostring(v)
		box.Text = value
		opt.value = value
	end

	local function commit()
		value = box.Text
		opt.value = value
		if cb then
			cb(value)
		end
	end

	box.FocusLost:Connect(commit)

	if opts.Number then
		box:GetPropertyChangedSignal("Text"):Connect(function()
			local digits = box.Text:gsub("%D", "")
			if digits ~= box.Text then
				box.Text = digits
			end
		end)
	end

	opt.FunctionCreate = api
	register(title, opt)
	return api
end

local function createDropdown(sec, opts, cb)
	opts = opts or {}
	local title = tostring(opts.Title or "Select")
	local multi = opts.Selected == true
	local search = opts.Search == true

	local items = normalizeList(opts.List)

	local selected = {}
	local value = nil

	if multi then
		local def = opts.Default
		for _, name in ipairs(items) do
			local on = false
			if type(def) == "table" then
				on = def[name] == true
			elseif type(opts.List) == "table" then
				on = opts.List[name] == true
			end
			selected[name] = on
		end
	else
		value = type(opts.Default) == "string" and opts.Default or nil
	end

	-- card: accent background + padding gives a 2px accent border and a
	-- 6px bottom-right hard shadow without a layout-breaking extra frame.
	local card = new("Frame", {
		Name = "Dropdown_" .. title,
		Size = UDim2.new(1, 0, 0, 42),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = sec.accent or BLUE,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		LayoutOrder = nextOrder(sec.body),
	}, sec.body)
	card.ZIndex = nextZI()
	new("UIPadding", {
		PaddingTop = UDim.new(0, 2),
		PaddingBottom = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 2),
		PaddingRight = UDim.new(0, 6),
	}, card)
	new("UIListLayout", {
		Padding = UDim.new(0, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, card)

	local header = child(card, "TextButton", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 42),
		BackgroundColor3 = SURFACE,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = 1,
	})

	txt(header, {
		Text = string.upper(title),
		Size = UDim2.new(1, -170, 1, 0),
		Position = UDim2.new(0, 12, 0, 0),
		TextSize = 11,
		TextColor3 = PAPER,
	})

	local chip = child(header, "TextLabel", {
		Size = UDim2.new(0, 110, 0, 20),
		Position = UDim2.new(1, -142, 0.5, -10),
		BackgroundColor3 = BLUE,
		BorderSizePixel = 0,
		Text = "SELECT",
		TextColor3 = PAPER,
		Font = Enum.Font.Code,
		TextSize = 9,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	local caret = txt(header, {
		Text = "+",
		Size = UDim2.new(0, 16, 1, 0),
		Position = UDim2.new(1, -26, 0, 0),
		TextSize = 14,
		TextColor3 = PAPER,
		Font = Enum.Font.GothamBlack,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	local panel = child(card, "Frame", {
		Name = "Panel",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = BG,
		BorderSizePixel = 0,
		Visible = false,
		LayoutOrder = 2,
	})
	new("UIPadding", {
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 6),
		PaddingRight = UDim.new(0, 6),
	}, panel)
	new("UIListLayout", {
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, panel)

	local searchBox
	if search then
		searchBox = child(panel, "TextBox", {
			Name = "Search",
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundColor3 = INK,
			BorderSizePixel = 0,
			Text = "",
			PlaceholderText = "search...",
			PlaceholderColor3 = MUTED,
			TextColor3 = PAPER,
			Font = Enum.Font.Code,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Left,
			ClearTextOnFocus = false,
			LayoutOrder = 1,
		})
		stroke(searchBox, 2, PAPER)
		new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, searchBox)
	end

	local rows = child(panel, "ScrollingFrame", {
		Name = "Rows",
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = PAPER,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ElasticBehavior = Enum.ElasticBehavior.Never,
		LayoutOrder = 2,
	})
	new("UIListLayout", {
		Padding = UDim.new(0, 3),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, rows)

	local opt = {
		type = multi and "priority_dropdown" or "dropdown",
		Page_Name = sec.Page_Name,
		Section_Name = sec.Name,
		list = items,
		value = multi and selected or value,
		FunctionCreate = nil,
	}

	local function countSelected()
		local n = 0
		for _, on in pairs(selected) do
			if on then
				n = n + 1
			end
		end
		return n
	end

	local function updateChip()
		if multi then
			chip.Text = tostring(countSelected()) .. " SELECTED"
			opt.value = selected
		else
			chip.Text = value and string.upper(tostring(value)) or "SELECT"
			opt.value = value
		end
	end

	local rebuild

	local function makeRow(name, order)
		local on = multi and selected[name] == true or false
		local sel = (not multi and value == name)
		local row = new("TextButton", {
			Name = "Row_" .. name,
			Size = UDim2.new(1, 0, 0, 28),
			BackgroundColor3 = sel and BLUE or SURFACE,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = order,
		}, rows)
		row.ZIndex = rows.ZIndex + 1

		local check
		if multi then
			check = child(row, "Frame", {
				Size = UDim2.new(0, 14, 0, 14),
				Position = UDim2.new(0, 4, 0.5, -7),
				BackgroundColor3 = on and LIME or INK,
				BorderSizePixel = 0,
			})
			stroke(check, 2, PAPER)
		end

		local rowLabel = child(row, "TextLabel", {
			Size = UDim2.new(1, -32, 1, 0),
			Position = UDim2.new(0, multi and 26 or 8, 0, 0),
			BackgroundTransparency = 1,
			Text = name,
			TextColor3 = PAPER,
			Font = Enum.Font.Code,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})

		hover(row, sel and BLUE or SURFACE, RAISED)

		row.MouseButton1Click:Connect(function()
			if multi then
				local newVal = not selected[name]
				selected[name] = newVal
				check.BackgroundColor3 = newVal and LIME or INK
				rowLabel.TextColor3 = PAPER
				updateChip()
				if cb then
					cb(name, newVal)
				end
			else
				value = name
				updateChip()
				panel.Visible = false
				caret.Text = "+"
				if cb then
					cb(name)
				end
				task.defer(rebuild)
			end
		end)
	end

	rebuild = function()
		for _, c in ipairs(rows:GetChildren()) do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end

		local query = ""
		if searchBox then
			query = searchBox.Text:lower()
		end

		local shown = 0
		for _, name in ipairs(items) do
			if query == "" or name:lower():find(query, 1, true) then
				shown = shown + 1
				makeRow(name, shown)
			end
		end

		rows.Size = UDim2.new(1, 0, 0, math.min(shown * 31, 168))
		updateChip()
	end

	local api = {}

	function api.SetValue(a, b)
		local v = b ~= nil and b or a
		if v == nil then
			return
		end

		if multi then
			if type(v) == "table" then
				for k, val in pairs(v) do
					if type(k) == "number" then
						selected[tostring(val)] = true
					else
						selected[tostring(k)] = (val == true)
					end
				end
			elseif type(v) == "string" then
				selected[v] = true
			end
			updateChip()
			rebuild()
		else
			value = tostring(v)
			updateChip()
			panel.Visible = false
			caret.Text = "+"
			rebuild()
		end
	end

	function api.GetNewList(a, b)
		local list = b ~= nil and b or a
		if type(list) ~= "table" then
			return
		end
		items = normalizeList(list)
		opt.list = items
		if multi then
			local fresh = {}
			for _, name in ipairs(items) do
				fresh[name] = selected[name] == true
			end
			selected = fresh
		elseif value then
			local found = false
			for _, name in ipairs(items) do
				if name == value then
					found = true
				end
			end
			if not found then
				value = nil
			end
		end
		rebuild()
	end

	function api.GetValue()
		return multi and selected or value
	end

	header.MouseButton1Click:Connect(function()
		panel.Visible = not panel.Visible
		caret.Text = panel.Visible and "-" or "+"
		if panel.Visible then
			rebuild()
		end
	end)

	if searchBox then
		searchBox:GetPropertyChangedSignal("Text"):Connect(rebuild)
	end

	opt.FunctionCreate = api
	register(title, opt)

	rebuild()
	return api
end

local function createBind(sec, opts, cb)
	opts = opts or {}
	local title = tostring(opts.Title or "Bind")
	local key = opts.Key or Enum.KeyCode.LeftControl

	local _, card = face(sec.body, 42, SURFACE, sec.accent)
	local zi = card.ZIndex

	txt(card, {
		Text = string.upper(title),
		Size = UDim2.new(1, -120, 1, 0),
		Position = UDim2.new(0, 12, 0, 0),
		TextSize = 11,
	})

	local badge = child(card, "TextButton", {
		Size = UDim2.new(0, 92, 0, 22),
		Position = UDim2.new(1, -104, 0.5, -11),
		BackgroundColor3 = BLUE,
		BorderSizePixel = 0,
		Text = key.Name,
		TextColor3 = PAPER,
		Font = Enum.Font.Code,
		TextSize = 9,
		AutoButtonColor = false,
	})
	stroke(badge, 2, INK)

	local listening = false

	local opt = {
		type = "bind",
		Page_Name = sec.Page_Name,
		Section_Name = sec.Name,
		value = key.Name,
		FunctionCreate = nil,
	}

	local api = {}

	function api.SetValue(a, b)
		local v = b ~= nil and b or a
		if v == nil then
			return
		end
		if typeof(v) == "EnumItem" then
			key = v
		else
			local found = Enum.KeyCode[tostring(v)]
			if found then
				key = found
			end
		end
		badge.Text = key.Name
		opt.value = key.Name
	end

	badge.MouseButton1Click:Connect(function()
		listening = true
		badge.Text = "..."
		badge.BackgroundColor3 = PINK
		badge.TextColor3 = INK
	end)

	UIS.InputBegan:Connect(function(input, processed)
		if listening and input.UserInputType == Enum.UserInputType.Keyboard then
			key = input.KeyCode
			listening = false
			badge.Text = key.Name
			badge.BackgroundColor3 = BLUE
			badge.TextColor3 = PAPER
			opt.value = key.Name
			return
		end
		if processed or listening then
			return
		end
		if input.KeyCode == key then
			if cb then
				cb()
			end
		end
	end)

	opt.FunctionCreate = api
	register(title, opt)
	return api
end

-- ======================= section builder =======================

local sectionIndex = 0

createSection = function(page, sectionName)
	local name = tostring(sectionName or "Section")
	sectionIndex = sectionIndex + 1
	local accent = ACCENTS[((sectionIndex - 1) % #ACCENTS) + 1]

	local card = new("Frame", {
		Name = "Sec_" .. name,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		LayoutOrder = nextOrder(page.Container),
	}, page.Container)
	card.ZIndex = nextZI()
	new("UIPadding", {
		PaddingTop = UDim.new(0, 2),
		PaddingBottom = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 2),
		PaddingRight = UDim.new(0, 6),
	}, card)
	new("UIListLayout", {
		Padding = UDim.new(0, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, card)

	local header = child(card, "Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		LayoutOrder = 1,
	})

	txt(header, {
		Text = string.upper(name),
		Size = UDim2.new(1, -90, 1, 0),
		Position = UDim2.new(0, 10, 0, 0),
		TextSize = 10,
		Font = Enum.Font.GothamBlack,
		TextColor3 = readableOn(accent),
	})

	txt(header, {
		Text = "///",
		Size = UDim2.new(0, 50, 1, 0),
		Position = UDim2.new(1, -58, 0, 0),
		TextSize = 10,
		Font = Enum.Font.Code,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = readableOn(accent),
	})

	local body = child(card, "Frame", {
		Name = "Body",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = PANEL,
		BorderSizePixel = 0,
		LayoutOrder = 2,
	})
	new("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
	}, body)
	new("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, body)

	local sec = {
		Name = name,
		Page_Name = page.Name,
		body = body,
		card = card,
		accent = accent,
	}

	ctx.section = sec

	function sec.CreateToggle(opts, cb)
		return createToggle(sec, opts, cb)
	end

	function sec.CreateButton(opts, cb)
		return createButton(sec, opts, cb)
	end

	function sec.CreateSlider(opts, cb)
		return createSlider(sec, opts, cb)
	end

	function sec.CreateDropdown(opts, cb)
		return createDropdown(sec, opts, cb)
	end

	function sec.CreateBox(opts, cb)
		return createBox(sec, opts, cb)
	end

	function sec.CreateLabel(opts)
		return createLabel(sec, opts)
	end

	function sec.CreateBind(opts, cb)
		return createBind(sec, opts, cb)
	end

	return sec
end

-- ======================= public API =======================

function Lib.CreateMain(cfg)
	cfg = cfg or {}
	buildShell(cfg)

	local Main = {
		Title = cfg.Title,
		Desc = cfg.Desc,
		Gui = UI.screen,
		Window = UI.window,
	}

	function Main.CreatePage(pageCfg)
		return createPage(pageCfg)
	end

	function Main.SetVisible(state)
		UI.window.Visible = state ~= false
		if state ~= false then
			UI.screen.Enabled = true
		end
	end

	function Main.Destroy()
		if UI.screen then
			UI.screen:Destroy()
		end
		UI.screen = nil
		if UI.launcherGui then
			UI.launcherGui:Destroy()
			UI.launcherGui = nil
		end
	end

	return Main
end

function Lib.CreateNoti(o)
	o = o or {}
	local stack = UI.notiStack
	if not stack or not stack.Parent then
		return
	end

	local accent = ACCENTS[math.random(#ACCENTS)]
	local width = 330

	local card = new("Frame", {
		Name = "Noti",
		Size = UDim2.new(0, width, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		LayoutOrder = nextOrder(stack),
	}, stack)
	card.ZIndex = 200001
	new("UIPadding", {
		PaddingTop = UDim.new(0, 2),
		PaddingBottom = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 2),
		PaddingRight = UDim.new(0, 6),
	}, card)
	new("UIListLayout", {
		Padding = UDim.new(0, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, card)

	local head = child(card, "Frame", {
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		LayoutOrder = 1,
	})

	child(head, "TextLabel", {
		Size = UDim2.new(1, -16, 1, 0),
		Position = UDim2.new(0, 8, 0, 0),
		BackgroundTransparency = 1,
		Text = string.upper(tostring(o.Title or "Notification")),
		TextColor3 = readableOn(accent),
		Font = Enum.Font.GothamBlack,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	local bodyFrame = child(card, "Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = SURFACE,
		BorderSizePixel = 0,
		LayoutOrder = 2,
	})
	new("UIPadding", {
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
	}, bodyFrame)
	new("UIListLayout", {
		Padding = UDim.new(0, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, bodyFrame)

	child(bodyFrame, "TextLabel", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = tostring(o.Desc or ""),
		TextColor3 = PAPER,
		Font = Enum.Font.Code,
		TextSize = 10,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	})

	UI.notis[#UI.notis + 1] = card

	if #UI.notis > 4 then
		local old = table.remove(UI.notis, 1)
		if old and old.Parent then
			old:Destroy()
		end
	end

	local ttl = tonumber(o.ShowTime) or 5
	task.delay(ttl, function()
		if card.Parent then
			card:Destroy()
		end
	end)

	return card
end

Lib.Accents = ACCENTS
Lib.Colors = {
	Ink = INK,
	Paper = PAPER,
	Bg = BG,
	Panel = PANEL,
	Surface = SURFACE,
	Border = BORDER,
	Blue = BLUE,
	Cyan = CYAN,
	Pink = PINK,
	Lime = LIME,
	Purple = PURPLE,
	Orange = ORANGE,
}

if getgenv then
	getgenv().CLTui = Lib
end

return Lib
