-- ============================================================
--  scopeware  V 0.0.9  |  StarterPlayerScript  [ENHANCED]
--  Backup key: SCOPEWARE-MASTER-V3-XKQZ9
--  INSERT = toggle panel
--  Changes: UICorners everywhere, modern animations,
--           fixed drag system, smooth open/close tweens
-- ============================================================

if not game:IsLoaded() then game.Loaded:Wait() end
task.wait(0.5)

task.spawn(function()

-- ============================================================
--  LOADING SEQUENCE
-- ============================================================
local function printBar(pct)
	local total = 55
	local filled = math.floor(pct / 100 * total)
	local bar = string.rep("#", filled) .. string.rep(" ", total - filled)
	print(string.format("|%s|  [%d%%]", bar, pct))
end

task.spawn(function()
	print("\n")
	print("loading ScopeWare KeySystem.lua")
	for i = 5, 100, 5 do task.wait(0.03); printBar(i) end
	print("KeySystem.lua COMP.\n")
	task.wait(0.2)
	print("loading MainSystem.lua")
	for i = 1, 100, 2 do task.wait(0.04); printBar(i) end
	print("MainSystem.lua COMP.\n")
end)

-- ============================================================
--  SERVICES
-- ============================================================
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser      = game:GetService("VirtualUser")
local TweenService     = game:GetService("TweenService")
local Lighting         = game:GetService("Lighting")
local MarketplaceSvc   = game:GetService("MarketplaceService")

local LP  = Players.LocalPlayer
local PG  = LP:WaitForChild("PlayerGui")
local Cam = workspace:WaitForChild("Camera", 10) or workspace.CurrentCamera
if not Cam then Cam = workspace.CurrentCamera end

-- Fetch game name once (async so it doesn't block the script)
local GAME_NAME = "loading..."
task.spawn(function()
	local ok, info = pcall(function()
		return MarketplaceSvc:GetProductInfo(game.PlaceId)
	end)
	if ok and info and info.Name then
		GAME_NAME = info.Name
	else
		GAME_NAME = "Unknown"
	end
end)

-- ============================================================
--  USER-CUSTOMIZABLE KEYBINDS
-- ============================================================
local TOGGLE_KEY   = "RightShift"   -- Main panel toggle
local EXPLORER_KEY = "RightControl" -- ScopeWare Explorer toggle

-- UI refresh registry — every widget (toggle/slider/dropdown) registers a
-- "refresh" closure here so config-load can sync the UI to new state values
local _refreshers = {}

-- ============================================================
--  PERFORMANCE TRACKING
-- ============================================================
local Stats     = game:GetService("Stats")
local _perfData = {
	fps        = 0, ping = 0, memMB = 0,
	serverAge  = 0, playerCt = 0, maxPlayers = 0,
}
local _perfStartTime = os.time()

local function _updatePerfStats()
	pcall(function()
		local ns = Stats.Network and Stats.Network.ServerStatsItem
		if ns and ns["Data Ping"] then
			_perfData.ping = math.floor(ns["Data Ping"]:GetValue())
		end
	end)
	pcall(function()
		_perfData.memMB = math.floor(Stats:GetTotalMemoryUsageMb())
	end)
	_perfData.serverAge  = os.time() - _perfStartTime
	_perfData.playerCt   = #Players:GetPlayers()
	_perfData.maxPlayers = Players.MaxPlayers
end
task.spawn(function()
	while true do _updatePerfStats(); task.wait(1) end
end)

-- Forward declarations for foundation systems used everywhere
local notify       -- assigned after tween helper exists
local applyPreset  -- assigned after _refreshers populates

-- Forward declare PRESETS table (filled below once state tables exist)
local PRESETS = {}

-- ============================================================
--  PERSIST ACROSS TELEPORTS
-- ============================================================
if _G.sw_verified == nil then _G.sw_verified = false end
if not _G.sw_key then
	local r    = Random.new(LP.UserId + math.floor(os.clock()))
	local pool = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	local k    = ""
	for i = 1, 24 do
		k = k .. pool:sub(r:NextInteger(1,#pool), r:NextInteger(1,#pool))
		if i%6==0 and i<24 then k = k .. "-" end
	end
	_G.sw_key = k
end
local SESSION_KEY = _G.sw_key
local BACKUP_KEY  = "SCOPEWARE-MASTER-V3-XKQZ9"
local function keyOK(s)
	local t = s:gsub("^%s+",""):gsub("%s+$",""):upper()
	return t == SESSION_KEY:upper() or t == BACKUP_KEY:upper()
end

-- ============================================================
--  COLOUR HELPERS
-- ============================================================
local function rgb(r,g,b) return Color3.fromRGB(r,g,b) end

local AC = {r=110,g=40,b=200}
-- Color tier helpers with floors so dark accents (e.g. red, deep blue) stay visible
local function ac()     return rgb(AC.r, AC.g, AC.b) end
local function ac2()
	-- Brighter highlight tier for hover/active states
	return rgb(
		math.min(255, AC.r + 50),
		math.min(255, AC.g + 35),
		math.min(255, AC.b + 60)
	)
end
local function acDk()
	-- Title bar / panel header tier — keeps min visibility
	return rgb(
		math.max(8,  AC.r//4),
		math.max(8,  AC.g//5),
		math.max(8,  AC.b//4)
	)
end
local function acMd()
	-- Mid tier for buttons/accents
	return rgb(
		math.max(20, AC.r//2),
		math.max(20, AC.g//3),
		math.max(20, AC.b//2)
	)
end
local function acFt()
	-- Faint divider tier
	return rgb(
		math.max(15, AC.r//4),
		math.max(15, AC.g//5),
		math.max(15, AC.b//4)
	)
end
local function acDp()
	-- Deepest tier for inactive buttons (must stay visible against BG)
	return rgb(
		math.max(12, AC.r//6),
		math.max(12, AC.g//7),
		math.max(12, AC.b//6)
	)
end

local _acReg  = {}
local _txtReg = {}
local lightMode = false

local C = {
	BG=rgb(10,10,14), PANEL=rgb(18,18,26), TEXT=rgb(220,210,255),
	TDIM=rgb(130,110,170), IN=rgb(14,14,22), EN=rgb(90,255,120), DIS=rgb(255,70,70)
}

local function regC(inst,prop,fn) table.insert(_acReg, {inst,prop,fn}) end
local function regT(inst)         table.insert(_txtReg, inst) end
local _bgReg = {}
local function regBG(inst,which) table.insert(_bgReg,{inst,which}) end

local function applyAC()
	local map={ac=ac(),ac2=ac2(),dk=acDk(),md=acMd(),ft=acFt(),dp=acDp()}
	for _,t in ipairs(_acReg) do pcall(function()
		if t[1] and t[1].Parent then t[1][t[2]] = map[t[3]] or map.ac end
	end) end
	C.TEXT = rgb(math.min(255,AC.r//2+140), math.min(255,AC.g//2+140), math.min(255,AC.b//2+170))
	C.TDIM = rgb(math.min(200,AC.r//2+60),  math.min(180,AC.g//2+60),  math.min(200,AC.b//2+80))
	C.IN   = rgb(math.max(4,AC.r//14), math.max(4,AC.g//18), math.max(4,AC.b//12))
	C.BG   = rgb(math.max(6,AC.r//18), math.max(6,AC.g//22), math.max(6,AC.b//16))
	C.PANEL= rgb(math.max(10,AC.r//14), math.max(10,AC.g//18), math.max(10,AC.b//12))
	for _,inst in ipairs(_txtReg) do pcall(function()
		if inst and inst.Parent and inst.BackgroundTransparency > 0.8 then
			inst.TextColor3 = C.TEXT
		end
	end) end
	for _,t in ipairs(_bgReg) do pcall(function()
		if t[1] and t[1].Parent then
			if t[2]=="bg"    then t[1].BackgroundColor3=C.BG
			elseif t[2]=="panel" then t[1].BackgroundColor3=C.PANEL
			elseif t[2]=="in"    then t[1].BackgroundColor3=C.IN end
		end
	end) end
end

local function applyTheme()
	if lightMode then
		C.BG=rgb(235,235,245); C.PANEL=rgb(215,213,230)
		C.TEXT=rgb(20,15,40); C.TDIM=rgb(80,70,110); C.IN=rgb(190,188,210)
	else
		C.BG=rgb(10,10,14); C.PANEL=rgb(18,18,26)
		C.TEXT=rgb(220,210,255); C.TDIM=rgb(130,110,170); C.IN=rgb(14,14,22)
	end
	for _,inst in ipairs(_txtReg) do pcall(function()
		if inst and inst.Parent and inst.BackgroundTransparency > 0.8 then
			inst.TextColor3 = C.TEXT
		end
	end) end
	if MF and MF.Parent then MF.BackgroundColor3=C.BG end
	if TR1 and TR1.Parent then TR1.BackgroundColor3=C.PANEL end
	if TR2 and TR2.Parent then TR2.BackgroundColor3=C.PANEL end
	for _,inst in ipairs(_txtReg) do pcall(function()
		if inst and inst.Parent and inst:IsA("TextBox") then
			inst.BackgroundColor3=C.IN
		end
	end) end
end

-- ============================================================
--  UICORNER HELPER
-- ============================================================
local function corner(inst, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 6)
	c.Parent = inst
	return c
end

-- ============================================================
--  TWEEN HELPERS
-- ============================================================
local TI_FAST   = TweenInfo.new(0.15, Enum.EasingStyle.Quad,   Enum.EasingDirection.Out)
local TI_MED    = TweenInfo.new(0.25, Enum.EasingStyle.Quint,  Enum.EasingDirection.Out)
local TI_SPRING = TweenInfo.new(0.35, Enum.EasingStyle.Back,   Enum.EasingDirection.Out)
local TI_CLOSE  = TweenInfo.new(0.2,  Enum.EasingStyle.Quint,  Enum.EasingDirection.In)

local function tween(inst, props, ti)
	TweenService:Create(inst, ti or TI_MED, props):Play()
end

-- Hover glow on buttons
local function addHover(btn, normalColor, hoverColor)
	btn.MouseEnter:Connect(function()
		tween(btn, {BackgroundColor3 = hoverColor}, TI_FAST)
	end)
	btn.MouseLeave:Connect(function()
		tween(btn, {BackgroundColor3 = normalColor}, TI_FAST)
	end)
end

-- ============================================================
--  NOTIFICATION SYSTEM
-- ============================================================
local NotifGui = Instance.new("ScreenGui")
NotifGui.Name = "scopewareNotif"
NotifGui.ResetOnSpawn = false
NotifGui.IgnoreGuiInset = true
NotifGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
NotifGui.Parent = PG

local NotifContainer = Instance.new("Frame", NotifGui)
NotifContainer.Size = UDim2.new(0, 280, 1, -120)
NotifContainer.Position = UDim2.new(1, -290, 0, 100)
NotifContainer.BackgroundTransparency = 1
NotifContainer.ZIndex = 50
local NotifLayout = Instance.new("UIListLayout", NotifContainer)
NotifLayout.SortOrder = Enum.SortOrder.LayoutOrder
NotifLayout.Padding = UDim.new(0, 6)
NotifLayout.VerticalAlignment = Enum.VerticalAlignment.Top

local NOTIFS_ENABLED = true
local _notifSeq = 0

notify = function(text, kind, duration)
	if not NOTIFS_ENABLED then return end
	kind = kind or "info"
	duration = duration or 2.5
	_notifSeq = _notifSeq + 1

	local accentMap = {
		info    = Color3.fromRGB(110, 80, 220),
		success = Color3.fromRGB(70, 200, 100),
		warn    = Color3.fromRGB(230, 170, 50),
		error   = Color3.fromRGB(220, 60, 80),
	}
	local accent = accentMap[kind] or accentMap.info

	local card = Instance.new("Frame", NotifContainer)
	card.Name = "Notif".._notifSeq
	card.Size = UDim2.new(1, 0, 0, 44)
	card.BackgroundColor3 = Color3.fromRGB(15, 12, 22)
	card.BackgroundTransparency = 0.05
	card.BorderSizePixel = 0
	card.LayoutOrder = -_notifSeq
	card.ZIndex = 51
	card.ClipsDescendants = true
	local cc = Instance.new("UICorner", card); cc.CornerRadius = UDim.new(0, 8)
	local cs = Instance.new("UIStroke", card)
	cs.Color = accent; cs.Thickness = 1.2
	local cg = Instance.new("UIGradient", card)
	cg.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(28,22,40)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(15,12,22)),
	})
	cg.Rotation = 35

	local strip = Instance.new("Frame", card)
	strip.Size = UDim2.new(0, 3, 1, -8)
	strip.Position = UDim2.fromOffset(4, 4)
	strip.BackgroundColor3 = accent
	strip.BorderSizePixel = 0
	strip.ZIndex = 52
	local sc = Instance.new("UICorner", strip); sc.CornerRadius = UDim.new(1, 0)

	local kindLbl = Instance.new("TextLabel", card)
	kindLbl.Size = UDim2.new(1, -20, 0, 12)
	kindLbl.Position = UDim2.fromOffset(14, 5)
	kindLbl.BackgroundTransparency = 1
	kindLbl.Text = string.upper(kind)
	kindLbl.TextColor3 = accent
	kindLbl.Font = Enum.Font.GothamBold
	kindLbl.TextSize = 9
	kindLbl.TextXAlignment = Enum.TextXAlignment.Left
	kindLbl.ZIndex = 52

	local bodyLbl = Instance.new("TextLabel", card)
	bodyLbl.Size = UDim2.new(1, -20, 0, 22)
	bodyLbl.Position = UDim2.fromOffset(14, 18)
	bodyLbl.BackgroundTransparency = 1
	bodyLbl.Text = tostring(text)
	bodyLbl.TextColor3 = Color3.fromRGB(220, 215, 240)
	bodyLbl.Font = Enum.Font.Gotham
	bodyLbl.TextSize = 11
	bodyLbl.TextXAlignment = Enum.TextXAlignment.Left
	bodyLbl.TextYAlignment = Enum.TextYAlignment.Top
	bodyLbl.TextWrapped = true
	bodyLbl.ZIndex = 52

	-- Slide in from right
	card.Position = UDim2.new(1, 20, 0, 0)
	tween(card, {Position = UDim2.new(0, 0, 0, 0)}, TI_SPRING)

	-- Auto-dismiss
	task.delay(duration, function()
		if not card.Parent then return end
		tween(card, {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0)}, TI_CLOSE)
		for _, ch in ipairs(card:GetDescendants()) do
			if ch:IsA("TextLabel") then tween(ch, {TextTransparency = 1}, TI_CLOSE)
			elseif ch:IsA("Frame") then tween(ch, {BackgroundTransparency = 1}, TI_CLOSE)
			elseif ch:IsA("UIStroke") then tween(ch, {Transparency = 1}, TI_CLOSE) end
		end
		task.wait(0.25); card:Destroy()
	end)
end
_G.swNotify = notify

-- ============================================================
--  PURE-LUA JSON
-- ============================================================
local JSON = {}
local function jsonEsc(s)
	return s:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n'):gsub('\r','\\r'):gsub('\t','\\t')
end
function JSON.encode(v)
	local t = type(v)
	if t == "nil"     then return "null"
	elseif t == "boolean" then return tostring(v)
	elseif t == "number"  then return tostring(v)
	elseif t == "string"  then return '"'..jsonEsc(v)..'"'
	elseif t == "table"   then
		local isArr = true; local n = 0
		for k in pairs(v) do n+=1; if type(k)~="number" then isArr=false; break end end
		if isArr then
			local parts = {}
			for i=1,n do parts[i]=JSON.encode(v[i]) end
			return "["..table.concat(parts,",").."]"
		else
			local parts = {}
			for k,val in pairs(v) do
				if type(k)=="string" then
					table.insert(parts, '"'..jsonEsc(k)..'":'..JSON.encode(val))
				end
			end
			return "{"..table.concat(parts,",").."}"
		end
	end
	return "null"
end
function JSON.decode(s)
	-- Proper recursive JSON parser — supports nested objects, arrays,
	-- strings, numbers, booleans, null. Returns nil + error on failure.
	local pos = 1
	local function skipWS() local _,e=s:find("^%s*",pos); if e then pos=e+1 end end
	local parseValue

	local function parseString()
		if s:sub(pos,pos) ~= '"' then return nil,"expected string" end
		pos = pos + 1
		local out = ""
		while pos <= #s do
			local c = s:sub(pos,pos)
			if c == '"' then pos = pos+1; return out
			elseif c == "\\" then
				local nc = s:sub(pos+1,pos+1)
				if     nc=="n" then out=out.."\n"
				elseif nc=="t" then out=out.."\t"
				elseif nc=="r" then out=out.."\r"
				elseif nc=='"' then out=out..'"'
				elseif nc=="\\" then out=out.."\\"
				else out=out..nc end
				pos = pos + 2
			else
				out = out..c; pos = pos+1
			end
		end
		return nil,"unterminated string"
	end

	local function parseNumber()
		local _,e,num = s:find("^(-?%d+%.?%d*)",pos)
		if not e then return nil,"expected number" end
		pos = e + 1
		return tonumber(num)
	end

	local function parseObject()
		pos = pos + 1  -- skip {
		local r = {}
		skipWS()
		if s:sub(pos,pos) == "}" then pos=pos+1; return r end
		while pos <= #s do
			skipWS()
			local key,err = parseString()
			if not key then return nil,err end
			skipWS()
			if s:sub(pos,pos) ~= ":" then return nil,"expected :" end
			pos = pos + 1
			skipWS()
			local val,err2 = parseValue()
			if val == nil and err2 then return nil,err2 end
			r[key] = val
			skipWS()
			local nc = s:sub(pos,pos)
			if nc == "," then pos = pos+1
			elseif nc == "}" then pos = pos+1; return r
			else return nil,"expected , or }" end
		end
		return nil,"unterminated object"
	end

	local function parseArray()
		pos = pos + 1  -- skip [
		local r = {}
		skipWS()
		if s:sub(pos,pos) == "]" then pos=pos+1; return r end
		while pos <= #s do
			skipWS()
			local val,err = parseValue()
			if val == nil and err then return nil,err end
			table.insert(r,val)
			skipWS()
			local nc = s:sub(pos,pos)
			if nc == "," then pos = pos+1
			elseif nc == "]" then pos = pos+1; return r
			else return nil,"expected , or ]" end
		end
		return nil,"unterminated array"
	end

	parseValue = function()
		skipWS()
		local c = s:sub(pos,pos)
		if c == '"'      then return parseString()
		elseif c == "{"  then return parseObject()
		elseif c == "["  then return parseArray()
		elseif s:sub(pos,pos+3) == "true"  then pos=pos+4; return true
		elseif s:sub(pos,pos+4) == "false" then pos=pos+5; return false
		elseif s:sub(pos,pos+3) == "null"  then pos=pos+4; return nil
		elseif c:match("[%-%d]") then return parseNumber()
		end
		return nil,"unexpected char at pos "..pos
	end

	skipWS()
	return parseValue()
end

-- ============================================================
--  UTILITY
-- ============================================================
local function alive(p)
	if not p or not p.Character then return false end
	local h = p.Character:FindFirstChildOfClass("Humanoid")
	return h and h.Health > 0
end
local function HRP(p)  return p and p.Character and p.Character:FindFirstChild("HumanoidRootPart") end
local function Hum(p)  return p and p.Character and p.Character:FindFirstChildOfClass("Humanoid") end
local function Head(p) return p and p.Character and p.Character:FindFirstChild("Head") end

local function isSpec()
	if not LP.Character then return true end
	local h = LP.Character:FindFirstChildOfClass("Humanoid")
	if h and h.Health <= 0 then return true end
	local sub = Cam.CameraSubject
	if not sub then return false end
	for _,p in ipairs(Players:GetPlayers()) do
		if p ~= LP and p.Character and sub:IsDescendantOf(p.Character) then return true end
	end
	return false
end

local _rp = RaycastParams.new()
_rp.FilterType = Enum.RaycastFilterType.Exclude
local function canSee(part)
	if not part then return false end
	local cam = workspace.CurrentCamera; if not cam then return false end
	local ex = {}
	for _,p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(ex, p.Character) end
	end
	_rp.FilterDescendantsInstances = ex
	local res = workspace:Raycast(cam.CFrame.Position, part.Position - cam.CFrame.Position, _rp)
	return res == nil
end

-- ============================================================
--  AIMBOT
-- ============================================================
local AB = {
	On=false, FOVOn=true, FOVSize=150,
	Smooth=false, SF=0.2,
	WallBang=false, TeamCheck=false, PredictMov=false,
	HoldFire=false,
	KeyMode="RMB",
	-- New enhanced settings
	PredictStr     = 0.15,    -- prediction strength (lerps target along velocity)
	HitboxExpand   = 0,       -- adds to FOV check radius (visual cheat)
	FovColorR      = 110, FovColorG = 80, FovColorB = 220,
	FovThickness   = 2,
	FovFilled      = false,   -- show filled disc instead of ring
	TargetPriority = "FOV",   -- FOV | Distance | Health
	IgnoreFriends  = false,
	MinHP          = 0,       -- skip targets below this HP
}
local abLock=nil; local abPlyr=nil; local abCamOn=false; local abFOV=70

local function abHead(p)
	if not p or not p.Character then return nil end
	return p.Character:FindFirstChild("Head") or HRP(p)
end

local function abKey()
	if not AB.On then return false end
	if isSpec() then return false end
	local k = AB.KeyMode
	if k=="RMB"  then return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) end
	if k=="LMB"  then return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) end
	if k=="E"    then return UserInputService:IsKeyDown(Enum.KeyCode.E) end
	if k=="R"    then return UserInputService:IsKeyDown(Enum.KeyCode.R) end
	if k=="F"    then return UserInputService:IsKeyDown(Enum.KeyCode.F) end
	if k=="Q"    then return UserInputService:IsKeyDown(Enum.KeyCode.Q) end
	return false
end

local function abPick()
	local cam = workspace.CurrentCamera; if not cam then return end
	local cx=cam.ViewportSize.X/2; local cy=cam.ViewportSize.Y/2
	local best,bestScore,bestP = nil, math.huge, nil
	local lhrp = HRP(LP)
	local effectiveFOV = AB.FOVSize + (AB.HitboxExpand or 0)
	for _,p in ipairs(Players:GetPlayers()) do
		if p==LP or not alive(p) then continue end
		if AB.TeamCheck and p.Team==LP.Team then continue end
		local hum = Hum(p)
		if hum and AB.MinHP > 0 and hum.Health < AB.MinHP then continue end
		local part = abHead(p); if not part then continue end
		if not AB.WallBang and not canSee(part) then continue end
		local sp,on = cam:WorldToViewportPoint(part.Position)
		if not on then continue end
		local screenD = math.sqrt((sp.X-cx)^2+(sp.Y-cy)^2)
		if screenD >= effectiveFOV then continue end

		-- Score by chosen priority (lower = better)
		local score
		if AB.TargetPriority == "Distance" and lhrp then
			score = (part.Position - lhrp.Position).Magnitude
		elseif AB.TargetPriority == "Health" and hum then
			score = hum.Health  -- lowest HP = priority
		else
			score = screenD  -- default FOV priority
		end
		if score < bestScore then
			bestScore=score; best=p; bestP=part
		end
	end
	abPlyr=best; abLock=bestP
end

-- ============================================================
--  AUTO-CLICKER
-- ============================================================
local clickOn    = false
local clickRate  = 0.06
local _lmbDown   = false
local _holdMode  = false

local function tapClick()
	if not LP.Character then return end
	local cf = (Cam and Cam.CFrame) or CFrame.new()
	pcall(function() VirtualUser:Button1Down(Vector2.new(0,0), cf) end)
	task.wait(0.04)
	pcall(function() VirtualUser:Button1Up(Vector2.new(0,0),   cf) end)
	pcall(function()
		local char = LP.Character; if not char then return end
		local tool = char:FindFirstChildOfClass("Tool")
		if tool then tool:Activate() end
	end)
end

local _tapTimer = 0
RunService.Heartbeat:Connect(function(dt)
	if not LP.Character then _tapTimer=0; _lmbDown=false; return end
	local cf = (Cam and Cam.CFrame) or CFrame.new()
	if clickOn and _holdMode then
		pcall(function() VirtualUser:Button1Down(Vector2.new(0,0), cf) end)
		_lmbDown = true
	elseif _lmbDown then
		pcall(function() VirtualUser:Button1Up(Vector2.new(0,0), cf) end)
		_lmbDown = false
	end
	if clickOn and not _holdMode and not isSpec() then
		_tapTimer = _tapTimer + dt
		if _tapTimer >= clickRate then
			_tapTimer = 0
			task.spawn(tapClick)
		end
	else
		_tapTimer = 0
	end
end)

-- ============================================================
--  RAGEBOT
-- ============================================================
local RG = {
	On=false, SpamDelay=0.05, AutoSwitch=true, BehindDist=2.5,
	TeamCheck=false, CamMode="Behind", LookDown=true, LookDownAngle=70,
	Invisible=false, SpeedBoost=false, SpeedBoostVal=80,
	HoldClick=false, KeyMode="Always",
}
local rgTgt=nil; local rgSpT=0; local rgCamOn=false; local rgFOV=70

local function rgKey()
	if not RG.On then return false end
	if isSpec() or not alive(LP) then return false end
	local k = RG.KeyMode
	if k=="Always" then return true end
	if k=="G" then return UserInputService:IsKeyDown(Enum.KeyCode.G) end
	if k=="H" then return UserInputService:IsKeyDown(Enum.KeyCode.H) end
	if k=="X" then return UserInputService:IsKeyDown(Enum.KeyCode.X) end
	if k=="Z" then return UserInputService:IsKeyDown(Enum.KeyCode.Z) end
	return false
end

local function rgPick()
	local best,bestD = nil,math.huge
	local lhrp = HRP(LP); if not lhrp then return end
	for _,p in ipairs(Players:GetPlayers()) do
		if p==LP or not alive(p) then continue end
		if RG.TeamCheck and p.Team==LP.Team then continue end
		local hrp = HRP(p); if not hrp then continue end
		local d = (hrp.Position - lhrp.Position).Magnitude
		if d < bestD then bestD=d; best=p end
	end
	rgTgt = best
end

-- ============================================================
--  MOVEMENT
-- ============================================================
local MV = {
	Spinbot=false, SpinSpeed=25, InfJump=false,
	Speed=false, SpeedVal=50, Fly=false, FlySpeed=40,
	Noclip=false, NoFall=false, LowGrav=false, GravVal=10,
}
local sY=0; local sP=0; local sR=0
local fBV=nil; local fBG=nil; local ncC=nil

local function flyUp()
	local char=LP.Character; if not char then return end
	local hrp=char:FindFirstChild("HumanoidRootPart"); if not hrp then return end
	if fBV then fBV:Destroy() end; if fBG then fBG:Destroy() end
	fBV=Instance.new("BodyVelocity"); fBV.Velocity=Vector3.zero
	fBV.MaxForce=Vector3.new(1e5,1e5,1e5); fBV.Parent=hrp
	fBG=Instance.new("BodyGyro"); fBG.MaxTorque=Vector3.new(1e5,1e5,1e5)
	fBG.P=1e4; fBG.CFrame=hrp.CFrame; fBG.Parent=hrp
	local h=Hum(LP); if h then h.PlatformStand=true end
end
local function flyDn()
	if fBV then fBV:Destroy(); fBV=nil end
	if fBG then fBG:Destroy(); fBG=nil end
	local h=Hum(LP); if h then h.PlatformStand=false end
end
local function ncStart()
	if ncC then return end
	ncC=RunService.Stepped:Connect(function()
		if not MV.Noclip then return end
		local c=LP.Character; if not c then return end
		for _,v in ipairs(c:GetDescendants()) do
			if v:IsA("BasePart") then v.CanCollide=false end
		end
	end)
end
local function ncStop()
	if ncC then ncC:Disconnect(); ncC=nil end
	local c=LP.Character; if not c then return end
	for _,v in ipairs(c:GetDescendants()) do
		if v:IsA("BasePart") then v.CanCollide=true end
	end
end

UserInputService.JumpRequest:Connect(function()
	if MV.InfJump and LP.Character then
		local h=Hum(LP); if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
	end
end)

_G._sw_antiafk = false
LP.Idled:Connect(function()
	if not _G._sw_antiafk then return end
	pcall(function()
		local cf = (Cam and Cam.CFrame) or CFrame.new()
		VirtualUser:Button2Down(Vector2.new(0,0), cf)
		task.wait(0.1)
		VirtualUser:Button2Up(Vector2.new(0,0), cf)
	end)
end)

-- ============================================================
--  WORLD / CHARACTER
-- ============================================================
local WC = {
	FullBright=false, FogRemove=false, TimeFreeze=false, FrozenTime=14,
	JumpPower=false, JumpVal=50, HipHeight=false, HipVal=0,
	HideChar=false, Transparent=false, TransAmt=0.5,
	CustomAmb=false, AmbR=128, AmbG=128, AmbB=128,
	CustomBright=false, BrightVal=1.5, CustomOutAmb=false,
	OAR=200, OAG=200, OAB=255, CustomShadow=false, ShadowVal=0.5,
	ColorCorr=false, Saturation=0, Contrast=0, CCBrightness=0,
	SkyboxOn=false, SkyboxId="", ArmOffset=false, ArmX=0, ArmY=0, ArmZ=0,
}
local origFog=Lighting.FogEnd; local origAmb=Lighting.Ambient
local origBr=Lighting.Brightness; local origOA=Lighting.OutdoorAmbient

local SKYBOX_PRESETS={
	{n="Space",  id="159451583"},
	{n="BleSky", id="2294512"},
	{n="Night",  id="2479376"},
	{n="Sunset", id="539931065"},
	{n="Forest", id="185686052"},
}

local function applySkybox(id)
	if not id or id=="" then return false, "empty id" end
	-- Strip non-numeric chars (in case user pastes "rbxassetid://12345")
	id = tostring(id):match("%d+") or ""
	if id == "" then return false, "invalid id format" end

	-- Verify the asset exists and is something Roblox accepts
	local ok, info = pcall(function()
		return MarketplaceSvc:GetProductInfo(tonumber(id))
	end)
	if not ok or not info then
		return false, "asset not found"
	end
	-- AssetTypeId 13 = Decal (most skyboxes are uploaded as decals)
	-- Some are Image (1). We accept either since Sky.SkyboxXx fields take both.
	-- If it's clearly something else (like Place=9), fail early.
	if info.AssetTypeId and info.AssetTypeId ~= 13 and info.AssetTypeId ~= 1 then
		return false, "not a decal/image asset"
	end

	-- Remove old sky to ensure fresh apply (changing properties on existing
	-- Sky doesn't always re-render in some games)
	local oldSky = Lighting:FindFirstChildOfClass("Sky")
	if oldSky then oldSky:Destroy() end

	local sky = Instance.new("Sky")
	sky.Name = "swSky"
	local faces = {"SkyboxBk","SkyboxDn","SkyboxFt","SkyboxLf","SkyboxRt","SkyboxUp"}
	local url = "rbxassetid://"..id
	for _,f in ipairs(faces) do sky[f] = url end
	sky.Parent = Lighting
	return true, "ok"
end
local function removeSkybox()
	local sky=Lighting:FindFirstChildOfClass("Sky")
	if sky then sky:Destroy() end
end

local function applyArmOffset()
	local char=LP.Character; if not char then return end
	local torso=char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
	if not torso then return end
	local off=CFrame.new(WC.ArmX, WC.ArmY, WC.ArmZ)
	for _,joint in ipairs(char:GetDescendants()) do
		if joint:IsA("Motor6D") then
			local n=joint.Name:lower()
			if n:find("arm") or n:find("shoulder") then
				joint.C0=joint.C0*off
			end
		end
	end
end

-- ============================================================
--  MORPH
-- ============================================================
local function applyMorph(username)
	local char=LP.Character; if not char then return false,"No character" end
	local hum=char:FindFirstChildOfClass("Humanoid"); if not hum then return false,"No humanoid" end
	username=username:gsub("^%s+",""):gsub("%s+$","")
	if username=="" then return false,"Enter a username" end
	for _,p in ipairs(Players:GetPlayers()) do
		if p~=LP and p.Name:lower()==username:lower() then
			local ok,err=pcall(function()
				local desc=Players:GetHumanoidDescriptionFromUserId(p.UserId)
				hum:ApplyDescription(desc)
			end)
			return ok, ok and p.Name or "Error: "..tostring(err)
		end
	end
	local ok1,uid=pcall(function() return Players:GetUserIdFromNameAsync(username) end)
	if not ok1 or not uid then return false,"Not found: "..username end
	local ok2,err2=pcall(function()
		local desc=Players:GetHumanoidDescriptionFromUserId(uid)
		hum:ApplyDescription(desc)
	end)
	return ok2, ok2 and username or "Error: "..tostring(err2)
end
local function resetMorph()
	local char=LP.Character; if not char then return end
	local hum=char:FindFirstChildOfClass("Humanoid"); if not hum then return end
	pcall(function()
		local desc=Players:GetHumanoidDescriptionFromUserId(LP.UserId)
		hum:ApplyDescription(desc)
	end)
end

-- ============================================================
--  ESP
-- ============================================================
local VS={
	Boxes=false, Names=false, Health=false, Dist=false,
	HeadDot=false, Chams=false, Tracers=false,
	-- New
	Skeleton    = false,  -- bone lines between body parts
	Weapon      = false,  -- show held tool/weapon name
	Armor       = false,  -- "armor" (treated as visible body parts count)
	ChamsMode   = "Solid", -- Solid | Outline | Glow
	TracerOrigin= "Bottom", -- Bottom | Center | Mouse
	TeamColor   = false,   -- color enemies/teammates differently
}
local EC={
	Box     = {r=150,g=60,b=255},
	Chams   = {r=110,g=40,b=200},
	Tracer  = {r=150,g=60,b=255},
	Skeleton= {r=255,g=200,b=80},
	Team    = {r=80, g=200,b=120},  -- teammate color
	Enemy   = {r=255,g=80, b=80},   -- enemy color
}
local ESP_KEY="T"
local ESPObj={}

local function espDel(p)
	local t=ESPObj[p]; if not t then return end
	for k,v in pairs(t) do
		if typeof(v) == "Instance" then
			pcall(function() v:Destroy() end)
		elseif type(v) == "table" then
			-- e.g. skel = {Attachment, Attachment, Beam, ...}
			for _, inst in ipairs(v) do
				if typeof(inst) == "Instance" then pcall(function() inst:Destroy() end) end
			end
		end
	end
	ESPObj[p]=nil
end
local function espBuild(player)
	espDel(player)
	if not player.Character then return end
	local c=player.Character
	local hrp=c:FindFirstChild("HumanoidRootPart"); local head=c:FindFirstChild("Head")
	if not hrp or not head then return end
	local t={}; ESPObj[player]=t
	-- Determine player color (team-colored if enabled)
	local function getPlayerColor()
		if VS.TeamColor then
			if player.Team and LP.Team and player.Team == LP.Team then
				return rgb(EC.Team.r, EC.Team.g, EC.Team.b)
			else
				return rgb(EC.Enemy.r, EC.Enemy.g, EC.Enemy.b)
			end
		end
		return rgb(EC.Chams.r, EC.Chams.g, EC.Chams.b)
	end
	local pCol = getPlayerColor()

	if VS.Chams then
		local hl=Instance.new("Highlight")
		if VS.ChamsMode == "Outline" then
			hl.FillTransparency = 1
			hl.OutlineColor = pCol
			hl.OutlineTransparency = 0
		elseif VS.ChamsMode == "Glow" then
			hl.FillColor = pCol; hl.FillTransparency = 0.7
			hl.OutlineColor = pCol; hl.OutlineTransparency = 0
		else  -- Solid
			hl.FillColor = pCol; hl.FillTransparency = 0.35
			hl.OutlineColor = rgb(EC.Box.r,EC.Box.g,EC.Box.b)
			hl.OutlineTransparency = 0
		end
		hl.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop; hl.Adornee=c; hl.Parent=c; t.hl=hl
	end
	if VS.Boxes then
		local boxC = VS.TeamColor and pCol or rgb(EC.Box.r,EC.Box.g,EC.Box.b)
		local sb=Instance.new("SelectionBox"); sb.Color3=boxC
		sb.LineThickness=0.04; sb.SurfaceTransparency=1; sb.Adornee=hrp; sb.Parent=workspace; t.sb=sb
	end
	-- Skeleton: connect body parts with thin beams
	if VS.Skeleton then
		t.skel = {}
		local pairs2 = {
			{"Head","UpperTorso"},{"UpperTorso","LowerTorso"},
			{"UpperTorso","LeftUpperArm"},{"LeftUpperArm","LeftLowerArm"},{"LeftLowerArm","LeftHand"},
			{"UpperTorso","RightUpperArm"},{"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"},
			{"LowerTorso","LeftUpperLeg"},{"LeftUpperLeg","LeftLowerLeg"},{"LeftLowerLeg","LeftFoot"},
			{"LowerTorso","RightUpperLeg"},{"RightUpperLeg","RightLowerLeg"},{"RightLowerLeg","RightFoot"},
			-- R6 fallback
			{"Head","Torso"},{"Torso","Left Arm"},{"Torso","Right Arm"},
			{"Torso","Left Leg"},{"Torso","Right Leg"},
		}
		local skelC = rgb(EC.Skeleton.r, EC.Skeleton.g, EC.Skeleton.b)
		for _, pr in ipairs(pairs2) do
			local a, b = c:FindFirstChild(pr[1]), c:FindFirstChild(pr[2])
			if a and b then
				local at0 = Instance.new("Attachment", a)
				local at1 = Instance.new("Attachment", b)
				local beam = Instance.new("Beam")
				beam.Attachment0 = at0; beam.Attachment1 = at1
				beam.Width0 = 0.05; beam.Width1 = 0.05
				beam.Color = ColorSequence.new(skelC)
				beam.FaceCamera = true; beam.LightEmission = 0.5
				beam.Parent = c
				table.insert(t.skel, at0); table.insert(t.skel, at1); table.insert(t.skel, beam)
			end
		end
	end
	local needBB=VS.Names or VS.Health or VS.Dist or VS.HeadDot or VS.Weapon or VS.Armor
	if needBB then
		local bb=Instance.new("BillboardGui"); bb.Size=UDim2.fromOffset(200,120)
		bb.StudsOffset=Vector3.new(0,3.5,0); bb.AlwaysOnTop=true; bb.ResetOnSpawn=false
		bb.Adornee=head; bb.Parent=PG; t.bb=bb; local yo=0
		if VS.Names then
			local nl=Instance.new("TextLabel"); nl.Size=UDim2.fromOffset(200,18)
			nl.Position=UDim2.fromOffset(0,yo); nl.BackgroundTransparency=1
			nl.Text=player.Name; nl.TextColor3=VS.TeamColor and pCol or rgb(220,210,255)
			nl.Font=Enum.Font.Code; nl.TextSize=14; nl.TextStrokeTransparency=0.4; nl.Parent=bb
			t.nm=nl; yo+=18
		end
		if VS.Health then
			local hl2=Instance.new("TextLabel"); hl2.Size=UDim2.fromOffset(200,16)
			hl2.Position=UDim2.fromOffset(0,yo); hl2.BackgroundTransparency=1
			hl2.Font=Enum.Font.Code; hl2.TextSize=12; hl2.TextStrokeTransparency=0.4; hl2.Parent=bb
			t.hp=hl2; yo+=16
		end
		if VS.Dist then
			local dl=Instance.new("TextLabel"); dl.Size=UDim2.fromOffset(200,14)
			dl.Position=UDim2.fromOffset(0,yo); dl.BackgroundTransparency=1
			dl.TextColor3=rgb(180,255,255); dl.Font=Enum.Font.Code
			dl.TextSize=11; dl.TextStrokeTransparency=0.4; dl.Parent=bb
			t.di=dl; yo+=14
		end
		if VS.Weapon then
			local wl=Instance.new("TextLabel"); wl.Size=UDim2.fromOffset(200,14)
			wl.Position=UDim2.fromOffset(0,yo); wl.BackgroundTransparency=1
			wl.TextColor3=rgb(255,200,80); wl.Font=Enum.Font.Code
			wl.TextSize=11; wl.TextStrokeTransparency=0.4; wl.Parent=bb
			t.weapon=wl; yo+=14
		end
		if VS.Armor then
			local al=Instance.new("TextLabel"); al.Size=UDim2.fromOffset(200,14)
			al.Position=UDim2.fromOffset(0,yo); al.BackgroundTransparency=1
			al.TextColor3=rgb(180,180,255); al.Font=Enum.Font.Code
			al.TextSize=11; al.TextStrokeTransparency=0.4; al.Parent=bb
			t.armor=al; yo+=14
		end
		if VS.HeadDot then
			local dot=Instance.new("BillboardGui"); dot.Size=UDim2.fromOffset(10,10)
			dot.AlwaysOnTop=true; dot.ResetOnSpawn=false; dot.Adornee=head; dot.Parent=PG
			local df=Instance.new("Frame"); df.Size=UDim2.new(1,0,1,0)
			df.BackgroundColor3=rgb(255,60,60); df.BorderSizePixel=0; df.Parent=dot; t.dot=dot
		end
	end
end
local function espAll() for _,p in ipairs(Players:GetPlayers()) do if p~=LP and p.Character then espBuild(p) end end end

TrGUI=Instance.new("ScreenGui"); TrGUI.Name="swTrace"; TrGUI.ResetOnSpawn=false
TrGUI.IgnoreGuiInset=true; TrGUI.Enabled=true; TrGUI.Parent=PG
local Trs={}
local function drawTr(player)
	if not Trs[player] then
		local f=Instance.new("Frame"); f.BackgroundColor3=rgb(EC.Tracer.r,EC.Tracer.g,EC.Tracer.b)
		f.BorderSizePixel=0; f.AnchorPoint=Vector2.new(0.5,0); f.ZIndex=2; f.Visible=false; f.Parent=TrGUI
		Trs[player]=f
	end
	local f=Trs[player]; local hrp=HRP(player)
	local cam=workspace.CurrentCamera
	if not hrp or not cam then f.Visible=false; return end
	local sp,on=cam:WorldToViewportPoint(hrp.Position)
	if not on or sp.Z<0 then f.Visible=false; return end
	local sx=cam.ViewportSize.X/2; local sy=cam.ViewportSize.Y
	local dx,dy=sp.X-sx,sp.Y-sy; local len=math.sqrt(dx*dx+dy*dy)
	if len<1 then f.Visible=false; return end
	f.Size=UDim2.fromOffset(2,len); f.Position=UDim2.fromOffset(sx,sy)
	f.Rotation=math.deg(math.atan2(dx,-dy)); f.Visible=true
end

local function watchP(player)
	if player==LP then return end
	local function onC(char)
		task.wait(0.1); espBuild(player)
		local h=char:WaitForChild("Humanoid",5)
		if h then h.Died:Connect(function()
			task.wait(0.1); espDel(player)
			if Trs[player] then Trs[player].Visible=false end
			if rgTgt==player then rgTgt=nil end
			if abPlyr==player then abPlyr=nil; abLock=nil end
		end) end
	end
	if player.Character then onC(player.Character) end
	player.CharacterAdded:Connect(onC)
end
Players.PlayerAdded:Connect(watchP)
Players.PlayerRemoving:Connect(function(p)
	espDel(p); if Trs[p] then Trs[p]:Destroy(); Trs[p]=nil end
end)
for _,p in ipairs(Players:GetPlayers()) do watchP(p) end

UserInputService.InputBegan:Connect(function(inp,gpe)
	if gpe then return end
	if inp.KeyCode==Enum.KeyCode[ESP_KEY] then
		VS.Boxes=not VS.Boxes; VS.Names=not VS.Names
		VS.Health=not VS.Health; VS.Chams=not VS.Chams
		espAll()
	end
end)

local KA={KillAura=false,KAR=12,AntiKB=false,BunnyHop=false,BhopSpeed=60}
local kaT=0
RunService.Heartbeat:Connect(function(dt2)
	if KA.KillAura and alive(LP) then
		kaT+=dt2; if kaT>=0.08 then kaT=0
			local lh=HRP(LP); if not lh then return end
			for _,p in ipairs(Players:GetPlayers()) do
				if p~=LP and alive(p) then
					local hrp=HRP(p); if hrp and (hrp.Position-lh.Position).Magnitude<=KA.KAR then
						task.spawn(tapClick)
					end
				end
			end
		end
	end
	if KA.AntiKB then local h=HRP(LP); if h then h.AssemblyLinearVelocity=Vector3.zero end end
	if KA.BunnyHop then
		local h=Hum(LP)
		if h and h:GetState()==Enum.HumanoidStateType.Landed then
			h:ChangeState(Enum.HumanoidStateType.Jumping); h.WalkSpeed=KA.BhopSpeed
		end
	end
end)

-- ============================================================
--  PRESETS  (apply curated bundles of settings)
-- ============================================================
PRESETS.Legit = { name="Legit", desc="Subtle camera assist, no rage", apply=function()
	AB.On=true; AB.Smooth=true; AB.SF=0.08; AB.FOVSize=50
	AB.WallBang=false; AB.TeamCheck=true; AB.HoldFire=false; AB.KeyMode="RMB"
	RG.On=false
	VS.Boxes=false; VS.Chams=false; VS.Tracers=false
end}
PRESETS.Rage = { name="Rage", desc="Maximum aggression - very obvious", apply=function()
	AB.On=true; AB.Smooth=false; AB.WallBang=true; AB.FOVSize=300
	AB.TeamCheck=false; AB.HoldFire=true
	RG.On=true; RG.AutoSwitch=true; RG.HoldClick=true
	VS.Boxes=true; VS.Names=true; VS.Health=true; VS.Chams=true
end}
PRESETS.HvH = { name="HvH", desc="Balanced rage for hacker-vs-hacker", apply=function()
	AB.On=true; AB.Smooth=false; AB.WallBang=true; AB.FOVSize=180
	AB.TeamCheck=false; AB.HoldFire=true
	RG.On=false
	VS.Boxes=true; VS.Names=true; VS.Health=true; VS.Chams=true
	KA.AntiKB=true
end}
PRESETS.Visual = { name="Visual Only", desc="ESP and visuals, no aim help", apply=function()
	AB.On=false; RG.On=false
	VS.Boxes=true; VS.Names=true; VS.Health=true; VS.Chams=true
	VS.Tracers=true; VS.HeadDot=true
	WC.FullBright=true
end}
PRESETS.Off = { name="All Off", desc="Disable everything", apply=function()
	AB.On=false; RG.On=false; MV.Spinbot=false; MV.Fly=false
	MV.Speed=false; MV.Noclip=false; MV.InfJump=false
	VS.Boxes=false; VS.Names=false; VS.Health=false
	VS.Chams=false; VS.Tracers=false; VS.HeadDot=false; VS.Dist=false
	WC.FullBright=false; WC.FogRemove=false
	WC.HideChar=false; WC.Transparent=false
	KA.KillAura=false; KA.AntiKB=false; KA.BunnyHop=false
end}

applyPreset = function(name)
	local p = PRESETS[name]
	if not p then return end
	p.apply()
	for _, fn in ipairs(_refreshers) do pcall(fn) end
	if notify then notify("Preset loaded: "..p.name, "success", 2) end
end

-- ============================================================
--  MAIN SCREEN GUI
-- ============================================================
local SG=Instance.new("ScreenGui"); SG.Name="scopeware"; SG.ResetOnSpawn=false
SG.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; SG.IgnoreGuiInset=true
SG.Enabled=false; SG.Parent=PG

-- HUD ScreenGui — stays enabled even when main panel closes,
-- so watermark / status bar / profile pic are always visible
local HUD = Instance.new("ScreenGui")
HUD.Name = "scopewareHUD"; HUD.ResetOnSpawn = false
HUD.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
HUD.IgnoreGuiInset = true; HUD.Enabled = true
HUD.Parent = PG

-- ============================================================
--  WATERMARK  (draggable, rounded)
-- ============================================================
local showWM=true
local WM=Instance.new("Frame")
WM.Size=UDim2.fromOffset(220,20); WM.Position=UDim2.new(1,-224,0,38)
WM.BackgroundColor3=acDk(); WM.BorderSizePixel=0; WM.ZIndex=1; WM.Parent=HUD
corner(WM, 8)
local wmStroke = Instance.new("UIStroke", WM)
wmStroke.Color = ac(); wmStroke.Thickness = 1
regC(WM,"BackgroundColor3","dk"); regC(wmStroke,"Color","ac")
local WML=Instance.new("TextLabel"); WML.Size=UDim2.new(1,0,1,0)
WML.BackgroundTransparency=1; WML.TextColor3=rgb(220,220,255); WML.Font=Enum.Font.Code
WML.TextSize=10; WML.TextXAlignment=Enum.TextXAlignment.Center; WML.ZIndex=2; WML.Parent=WM
WML.RichText=true

-- ============================================================
--  FIXED DRAG SYSTEM  — offset-based, screen-clamped, lag-free
-- ============================================================
local function makeDraggable(handle, target, onMove)
	local dragging = false
	local ox, oy = 0, 0
	local conn = nil

	handle.InputBegan:Connect(function(i)
		if i.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		dragging = true
		-- Capture offset at click time
		local ap = target.AbsolutePosition
		ox = i.Position.X - ap.X
		oy = i.Position.Y - ap.Y
		-- Start polling mouse position
		if conn then conn:Disconnect() end
		conn = RunService.RenderStepped:Connect(function()
			if not dragging then conn:Disconnect(); conn = nil; return end
			local mp = UserInputService:GetMouseLocation()
			local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(9999,9999)
			local sz = target.AbsoluteSize
			local nx = math.clamp(mp.X - ox, 0, math.max(0, vp.X - sz.X))
			local ny = math.clamp(mp.Y - oy, 0, math.max(0, vp.Y - sz.Y))
			target.Position = UDim2.fromOffset(nx, ny)
			if onMove then onMove(nx, ny) end
		end)
	end)

	-- Stop on any mouse-up anywhere on screen
	UserInputService.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
		end
	end)
end

makeDraggable(WM, WM)

-- ============================================================
--  STATUS BAR  (draggable, rounded)
-- ============================================================
local showSB=true
local SBar=Instance.new("Frame")
SBar.Size=UDim2.fromOffset(380,18); SBar.Position=UDim2.new(0.5,-190,0,38)
SBar.BackgroundColor3=acDk(); SBar.BorderSizePixel=0; SBar.ZIndex=1; SBar.Parent=HUD
corner(SBar, 8)
local sbStroke = Instance.new("UIStroke", SBar)
sbStroke.Color = ac(); sbStroke.Thickness = 1
regC(SBar,"BackgroundColor3","dk"); regC(sbStroke,"Color","ac")
local SBL=Instance.new("TextLabel"); SBL.Size=UDim2.new(1,0,1,0)
SBL.BackgroundTransparency=1; SBL.TextColor3=ac2(); SBL.Font=Enum.Font.Code
SBL.TextSize=9; SBL.TextXAlignment=Enum.TextXAlignment.Center; SBL.ZIndex=2; SBL.Parent=SBar
regC(SBL,"TextColor3","ac2")
makeDraggable(SBar, SBar)

-- ============================================================
--  PROFILE PIC  (draggable, rounded)
-- ============================================================
local PF=Instance.new("Frame"); PF.Size=UDim2.fromOffset(50,50)
PF.Position=UDim2.new(0,4,1,-58); PF.BackgroundColor3=acDk()
PF.BorderSizePixel=0; PF.ZIndex=5; PF.Parent=HUD
corner(PF, 10)
local pfStroke = Instance.new("UIStroke", PF)
pfStroke.Color = ac(); pfStroke.Thickness = 1.5
regC(PF,"BackgroundColor3","dk"); regC(pfStroke,"Color","ac")
local PI=Instance.new("ImageLabel"); PI.Size=UDim2.new(1,0,1,0)
PI.BackgroundTransparency=1; PI.BorderSizePixel=0; PI.ZIndex=6; PI.Parent=PF
corner(PI, 10)
local PNL=Instance.new("TextLabel"); PNL.Size=UDim2.fromOffset(100,16)
PNL.Position=UDim2.new(0,4,1,-42); PNL.BackgroundColor3=acDk()
PNL.BorderSizePixel=0; PNL.Text=LP.Name
PNL.TextColor3=C.TEXT; PNL.Font=Enum.Font.Code; PNL.TextSize=9; PNL.ZIndex=5; PNL.Parent=HUD
corner(PNL, 4)
local pnlStroke = Instance.new("UIStroke", PNL)
pnlStroke.Color = ac(); pnlStroke.Thickness = 1
regC(PNL,"BackgroundColor3","dk"); regC(pnlStroke,"Color","ac"); regT(PNL)
task.spawn(function()
	local ok,url=pcall(function()
		return Players:GetUserThumbnailAsync(LP.UserId,Enum.ThumbnailType.HeadShot,Enum.ThumbnailSize.Size100x100)
	end)
	if ok and url then PI.Image=url end
end)

do
	local _pfOffX, _pfOffY = 0, 0
	task.defer(function()
		_pfOffX = PNL.AbsolutePosition.X - PF.AbsolutePosition.X
		_pfOffY = PNL.AbsolutePosition.Y - PF.AbsolutePosition.Y
	end)
	makeDraggable(PF, PF, function(nx, ny)
		PNL.Position = UDim2.fromOffset(nx + _pfOffX, ny + _pfOffY)
	end)
end

-- ============================================================
--  PERFORMANCE HUD OVERLAY  (draggable mini panel)
-- ============================================================
local showPerfHUD = false  -- toggle from settings
local PerfHUD = Instance.new("Frame", HUD)
PerfHUD.Name = "PerfHUD"
PerfHUD.Size = UDim2.fromOffset(180, 100)
PerfHUD.Position = UDim2.new(1, -200, 0, 100)
PerfHUD.BackgroundColor3 = Color3.fromRGB(15, 12, 22)
PerfHUD.BackgroundTransparency = 0.1
PerfHUD.BorderSizePixel = 0
PerfHUD.Visible = false
PerfHUD.ZIndex = 3
corner(PerfHUD, 8)
local pfStrokeOuter = Instance.new("UIStroke", PerfHUD)
pfStrokeOuter.Color = ac(); pfStrokeOuter.Thickness = 1
regC(pfStrokeOuter, "Color", "ac")
local pfGrad = Instance.new("UIGradient", PerfHUD)
pfGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(28, 22, 40)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(15, 12, 22)),
})
pfGrad.Rotation = 90

local pfHdr = Instance.new("TextLabel", PerfHUD)
pfHdr.Size = UDim2.new(1, -8, 0, 14)
pfHdr.Position = UDim2.fromOffset(6, 4)
pfHdr.BackgroundTransparency = 1
pfHdr.Text = "PERFORMANCE"
pfHdr.TextColor3 = ac2()
pfHdr.Font = Enum.Font.GothamBold
pfHdr.TextSize = 9
pfHdr.TextXAlignment = Enum.TextXAlignment.Left
pfHdr.ZIndex = 4
regC(pfHdr, "TextColor3", "ac2")

local function pfRow(label, key, y)
	local lbl = Instance.new("TextLabel", PerfHUD)
	lbl.Size = UDim2.fromOffset(80, 14)
	lbl.Position = UDim2.fromOffset(8, y)
	lbl.BackgroundTransparency = 1
	lbl.Text = label
	lbl.TextColor3 = Color3.fromRGB(150, 140, 180)
	lbl.Font = Enum.Font.Code; lbl.TextSize = 10
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.ZIndex = 4
	local val = Instance.new("TextLabel", PerfHUD)
	val.Name = "v_"..key
	val.AnchorPoint = Vector2.new(1, 0)
	val.Position = UDim2.new(1, -8, 0, y)
	val.Size = UDim2.fromOffset(85, 14)
	val.BackgroundTransparency = 1
	val.Text = "..."
	val.TextColor3 = Color3.fromRGB(220, 215, 240)
	val.Font = Enum.Font.GothamBold
	val.TextSize = 10
	val.TextXAlignment = Enum.TextXAlignment.Right
	val.ZIndex = 4
	return val
end
local pfFps    = pfRow("FPS:",     "fps",    20)
local pfPing   = pfRow("Ping:",    "ping",   34)
local pfMem    = pfRow("Memory:",  "mem",    48)
local pfPlrs   = pfRow("Players:", "plrs",   62)
local pfUptime = pfRow("Uptime:",  "uptime", 76)

makeDraggable(PerfHUD, PerfHUD)

-- Update perf HUD values continuously
task.spawn(function()
	while true do
		if showPerfHUD then
			pfFps.Text = tostring(_perfData.fps)
			pfFps.TextColor3 = (_perfData.fps >= 50) and Color3.fromRGB(70,220,80)
				or (_perfData.fps >= 30) and Color3.fromRGB(230,180,60)
				or Color3.fromRGB(220,80,80)
			pfPing.Text = _perfData.ping.." ms"
			pfPing.TextColor3 = (_perfData.ping <= 80) and Color3.fromRGB(70,220,80)
				or (_perfData.ping <= 200) and Color3.fromRGB(230,180,60)
				or Color3.fromRGB(220,80,80)
			pfMem.Text = _perfData.memMB.." MB"
			pfPlrs.Text = _perfData.playerCt.." / ".._perfData.maxPlayers
			-- Uptime mm:ss
			local sec = _perfData.serverAge
			pfUptime.Text = string.format("%02d:%02d", math.floor(sec/60), sec%60)
		end
		task.wait(0.5)
	end
end)

-- ============================================================
--  FOV CIRCLE
-- ============================================================
local FOVSG=Instance.new("ScreenGui"); FOVSG.Name="swFOV"; FOVSG.ResetOnSpawn=false
FOVSG.IgnoreGuiInset=true; FOVSG.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
FOVSG.Enabled=true; FOVSG.Parent=PG
local FOVF=Instance.new("Frame"); FOVF.BackgroundTransparency=1; FOVF.BorderSizePixel=0
FOVF.ZIndex=10; FOVF.Visible=false; FOVF.Parent=FOVSG
local FOVSegs={}
for i=1,80 do
	local s=Instance.new("Frame"); s.BackgroundColor3=ac2()
	s.BorderSizePixel=0; s.Size=UDim2.fromOffset(2,2); s.ZIndex=10; s.Parent=FOVF; FOVSegs[i]=s
end

-- ============================================================
--  RENDER LOOP HELPERS
-- ============================================================
local fpsBuf,fpsCl,fpsV={},0,0

local function _tickFPS(dt)
	table.insert(fpsBuf,dt); fpsCl+=dt
	if fpsCl>=0.5 then
		local s=0; for _,v in ipairs(fpsBuf) do s+=v end
		fpsV=math.floor(#fpsBuf/s+0.5); fpsBuf={}; fpsCl=0
		_perfData.fps = fpsV
	end
end

local function _tickHUD()
	WM.Visible = showWM
	if showWM then
		-- Game name in accent color, rest in white-ish text
		local hex = string.format("#%02X%02X%02X", AC.r, AC.g, AC.b)
		-- Truncate long game names to keep watermark readable
		local gn = GAME_NAME
		if #gn > 22 then gn = gn:sub(1,20)..".." end
		WML.Text = string.format(
			" <font color=\"%s\">sw V0.0.9</font> | <b>%s</b> | %dfps | AB:%s | RG:%s ",
			hex, gn, fpsV,
			AB.On and "ON" or "OFF",
			RG.On and "ON" or "OFF"
		)
		-- Estimate width (RichText tags don't count toward visible chars)
		local visibleLen = #string.format(" sw V0.0.9 | %s | %dfps | AB:%s | RG:%s ",
			gn, fpsV, AB.On and "ON" or "OFF", RG.On and "ON" or "OFF")
		local w = visibleLen*6+8
		WM.Size = UDim2.fromOffset(math.max(w,180), 20)
	end
	SBar.Visible=showSB
	if showSB then
		local fl={}
		if AB.On       then table.insert(fl,"AB")             end
		if AB.WallBang then table.insert(fl,"WB")             end
		if RG.On       then table.insert(fl,"RAGE")           end
		if MV.Spinbot  then table.insert(fl,"SPIN")           end
		if MV.Fly      then table.insert(fl,"FLY")            end
		if MV.Speed    then table.insert(fl,"SPD:"..MV.SpeedVal) end
		if MV.Noclip   then table.insert(fl,"NOCLIP")         end
		if VS.Chams    then table.insert(fl,"CHAMS")          end
		if VS.Tracers  then table.insert(fl,"TRACE")          end
		if WC.FullBright then table.insert(fl,"FB")           end
		SBL.Text = #fl>0 and table.concat(fl,"  |  ") or "scopeware V0.0.9"
	end
end

local function _tickFOV()
	FOVF.Visible = AB.FOVOn
	if not FOVF.Visible then return end
	local r=AB.FOVSize
	local cx=Cam.ViewportSize.X/2; local cy=Cam.ViewportSize.Y/2
	FOVF.Size=UDim2.fromOffset(r*2+4,r*2+4)
	FOVF.Position=UDim2.fromOffset(cx-r-2,cy-r-2)
	local fovCol = Color3.fromRGB(AB.FovColorR, AB.FovColorG, AB.FovColorB)
	local thick  = math.max(1, AB.FovThickness or 2)
	for i=1,80 do
		local a=(i-1)/80*math.pi*2
		FOVSegs[i].Position = UDim2.fromOffset(r+math.cos(a)*r, r+math.sin(a)*r)
		FOVSegs[i].Size     = UDim2.fromOffset(thick, thick)
		FOVSegs[i].BackgroundColor3 = fovCol
		FOVSegs[i].BackgroundTransparency = AB.FovFilled and 0.3 or 0
	end
end

local function _tickAimbot()
	if abKey() then
		if not abCamOn then
			abFOV=Cam.FieldOfView
			Cam.CameraType=Enum.CameraType.Scriptable
			abCamOn=true
		end
		Cam.FieldOfView=abFOV
		if not abPlyr or not alive(abPlyr) then abPick()
		else abLock=abHead(abPlyr); if not abLock then abPick() end end
		if abLock then
			local hp=abLock.Position
			-- Movement prediction: lerp target along its velocity
			if AB.PredictMov and AB.PredictStr > 0 and abLock:IsA("BasePart") then
				local vel = abLock.AssemblyLinearVelocity or Vector3.zero
				hp = hp + vel * AB.PredictStr
			end
			local cp=Cam.CFrame.Position
			if AB.Smooth then
				local sm=Cam.CFrame.LookVector:Lerp((hp-cp).Unit, math.clamp(AB.SF,0.01,1))
				Cam.CFrame=CFrame.new(cp, cp+sm)
			else
				Cam.CFrame=CFrame.new(cp, hp)
			end
			Cam.FieldOfView=abFOV
			_holdMode=AB.HoldFire; clickOn=true
		else
			clickOn=false; _holdMode=false
		end
	else
		if abCamOn then
			Cam.CameraType=Enum.CameraType.Custom
			Cam.FieldOfView=abFOV
			abCamOn=false
		end
		abPlyr=nil; abLock=nil
		if not RG.On or not rgKey() then clickOn=false; _holdMode=false end
	end
end

local function _tickRage()
	if not rgKey() then
		if not abKey() then clickOn=false; _holdMode=false end
		if rgCamOn and not abCamOn then
			Cam.CameraType=Enum.CameraType.Custom
			Cam.FieldOfView=rgFOV; rgCamOn=false
		end
		if not RG.On then rgTgt=nil end
		return
	end
	if not rgTgt or not alive(rgTgt) then
		if RG.AutoSwitch then rgPick() end
	end
	if not rgTgt or not alive(rgTgt) then return end
	local hrp=HRP(LP); local tHRP=HRP(rgTgt); local tHead=Head(rgTgt)
	if hrp and tHRP then
		if RG.CamMode=="CamBehind" then
			if not abCamOn then
				if not rgCamOn then rgFOV=Cam.FieldOfView; Cam.CameraType=Enum.CameraType.Scriptable; rgCamOn=true end
				Cam.FieldOfView=rgFOV
				local behindPos=tHRP.Position - tHRP.CFrame.LookVector*RG.BehindDist + Vector3.new(0,2,0)
				local aimAt=tHead and tHead.Position or tHRP.Position
				if RG.LookDown then
					local blend=math.clamp(RG.LookDownAngle/90,0,1)
					Cam.CFrame=CFrame.new(behindPos, behindPos+(aimAt-behindPos).Unit:Lerp(Vector3.new(0,-1,0),blend))
				else
					Cam.CFrame=CFrame.new(behindPos, aimAt)
				end
				Cam.FieldOfView=rgFOV
			end
		else
			hrp.CFrame=CFrame.new(
				tHRP.Position - tHRP.CFrame.LookVector*RG.BehindDist + Vector3.new(0,0.5,0),
				tHRP.Position
			)
			if not abCamOn then
				if not rgCamOn then rgFOV=Cam.FieldOfView; Cam.CameraType=Enum.CameraType.Scriptable; rgCamOn=true end
				Cam.FieldOfView=rgFOV
				local cp=Cam.CFrame.Position
				local aimAt=tHead and tHead.Position or tHRP.Position
				if RG.LookDown then
					local blend=math.clamp(RG.LookDownAngle/90,0,1)
					Cam.CFrame=CFrame.new(cp, cp+(aimAt-cp).Unit:Lerp(Vector3.new(0,-1,0),blend))
				else
					Cam.CFrame=CFrame.new(cp, aimAt)
				end
				Cam.FieldOfView=rgFOV
			end
		end
	end
	local hum2=Hum(LP)
	if hum2 and RG.SpeedBoost then hum2.WalkSpeed=RG.SpeedBoostVal end
	if RG.Invisible and LP.Character then
		for _,p in ipairs(LP.Character:GetDescendants()) do
			if p:IsA("BasePart") or p:IsA("Decal") then p.LocalTransparencyModifier=1 end
		end
	end
	_holdMode=RG.HoldClick; clickOn=true
end

local function _tickMovement()
	if MV.Spinbot then
		local c=LP.Character
		if c then
			local hum=c:FindFirstChildOfClass("Humanoid")
			if hum and hum.AutoRotate then hum.AutoRotate=false end
			local h=c:FindFirstChild("HumanoidRootPart")
			if h then
				-- Save camera CFrame BEFORE spin so we can restore it (prevents 1st-person/camera-follow spin)
				local savedCam = Cam.CFrame
				sY=(sY+MV.SpinSpeed)%360
				-- Y-axis only — pitch/roll were causing seasickness AND breaking camera
				h.CFrame=CFrame.new(h.Position)*CFrame.Angles(0, math.rad(sY), 0)
				-- Restore camera so it stays where the user was looking
				Cam.CFrame = savedCam
			end
		end
	else
		-- Re-enable AutoRotate when spinbot turns off
		local hum=Hum(LP)
		if hum and not hum.AutoRotate then hum.AutoRotate=true end
	end
	if MV.Fly then
		if not fBV then flyUp() end
		if fBV and fBG then
			local c=LP.Character
			local h=c and c:FindFirstChild("HumanoidRootPart")
			if h then
				local vel=Vector3.zero; local spd=MV.FlySpeed; local cc=Cam.CFrame
				local lv=Vector3.new(cc.LookVector.X,0,cc.LookVector.Z).Unit
				local rv=Vector3.new(cc.RightVector.X,0,cc.RightVector.Z).Unit
				if UserInputService:IsKeyDown(Enum.KeyCode.W)         then vel=vel+lv*spd  end
				if UserInputService:IsKeyDown(Enum.KeyCode.S)         then vel=vel-lv*spd  end
				if UserInputService:IsKeyDown(Enum.KeyCode.A)         then vel=vel-rv*spd  end
				if UserInputService:IsKeyDown(Enum.KeyCode.D)         then vel=vel+rv*spd  end
				if UserInputService:IsKeyDown(Enum.KeyCode.Space)     then vel=vel+Vector3.new(0,spd,0) end
				if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then vel=vel-Vector3.new(0,spd,0) end
				fBV.Velocity=vel; fBG.CFrame=cc
			end
		end
	else
		flyDn()
	end
	local hm=Hum(LP)
	if hm then
		if RG.On and RG.SpeedBoost then
			hm.WalkSpeed = RG.SpeedBoostVal
		elseif MV.Speed then
			hm.WalkSpeed = MV.SpeedVal
		else
			hm.WalkSpeed = 16
		end
		if WC.JumpPower then hm.JumpPower=WC.JumpVal end
		if WC.HipHeight then hm.HipHeight=WC.HipVal  end
	end
	if MV.Noclip and not ncC then ncStart()
	elseif not MV.Noclip and ncC then ncStop() end
	workspace.Gravity = MV.LowGrav and MV.GravVal or 196.2
end

local function _tickWorld()
	if WC.FullBright then
		Lighting.Ambient=Color3.new(1,1,1); Lighting.Brightness=2
		Lighting.OutdoorAmbient=Color3.new(1,1,1)
	else
		if WC.CustomAmb then
			Lighting.Ambient = Color3.fromRGB(WC.AmbR, WC.AmbG, WC.AmbB)
		else
			Lighting.Ambient = origAmb
		end
		if WC.CustomBright then
			Lighting.Brightness = WC.BrightVal
		else
			Lighting.Brightness = origBr
		end
		if WC.CustomOutAmb then
			Lighting.OutdoorAmbient = Color3.fromRGB(WC.OAR, WC.OAG, WC.OAB)
		else
			Lighting.OutdoorAmbient = origOA
		end
		if WC.CustomShadow then
			pcall(function() Lighting.ShadowSoftness = WC.ShadowVal end)
		end
		if WC.ColorCorr then
			local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
			if not cc then cc=Instance.new("ColorCorrectionEffect"); cc.Parent=Lighting end
			cc.Saturation = WC.Saturation
			cc.Contrast   = WC.Contrast
			cc.Brightness = WC.CCBrightness
		end
	end
	Lighting.FogEnd = WC.FogRemove and 9e8 or origFog
	if WC.TimeFreeze then Lighting.ClockTime=WC.FrozenTime end
	if WC.HideChar and LP.Character then
		for _,p in ipairs(LP.Character:GetDescendants()) do
			if p:IsA("BasePart") or p:IsA("Decal") then p.LocalTransparencyModifier=1 end
		end
	elseif WC.Transparent and LP.Character then
		for _,p in ipairs(LP.Character:GetDescendants()) do
			if p:IsA("BasePart") then p.LocalTransparencyModifier=WC.TransAmt end
		end
	end
end

local function _tickESP()
	for player,t in pairs(ESPObj) do
		if not player.Character then continue end
		local h2=player.Character:FindFirstChildOfClass("Humanoid")
		local hrp2=HRP(player)
		if t.hp and h2 then
			local hp2=math.floor(h2.Health)
			local mx=math.max(math.floor(h2.MaxHealth),1)
			local ratio=h2.Health/mx
			t.hp.Text=string.format("HP %d/%d",hp2,mx)
			t.hp.TextColor3=rgb(math.floor(255*(1-ratio)),math.floor(255*ratio),50)
		end
		if t.di and hrp2 then
			local lh=HRP(LP)
			if lh then t.di.Text=math.floor((hrp2.Position-lh.Position).Magnitude).." studs" end
		end
		if t.weapon then
			local tool = player.Character:FindFirstChildOfClass("Tool")
			t.weapon.Text = tool and ("[ "..tool.Name.." ]") or "[ unarmed ]"
		end
		if t.armor then
			-- "Armor" approximation: count of body parts (R6=6, R15=15, missing parts indicate dmg)
			local count = 0
			for _,p in ipairs(player.Character:GetChildren()) do
				if p:IsA("BasePart") then count += 1 end
			end
			t.armor.Text = "Parts: "..count
		end
	end
	if VS.Tracers then
		for _,p in ipairs(Players:GetPlayers()) do
			if p~=LP and alive(p) then drawTr(p) end
		end
		for p,f in pairs(Trs) do if not alive(p) then f.Visible=false end end
	else
		for _,f in pairs(Trs) do f.Visible=false end
	end
end

-- Forward declarations for explorer (built after _buildGUI)
local EXP_SG, EXP

RunService.RenderStepped:Connect(function(dt)
	Cam = workspace.CurrentCamera
	if not Cam then return end
	_tickFPS(dt)
	_tickHUD()
	_tickFOV()
	_tickAimbot()
	_tickRage()
	_tickMovement()
	_tickWorld()
	_tickESP()
	if SG.Enabled and not abKey() and not rgKey() then
		-- Only free the mouse if the cursor is actually over the panel.
		-- This lets the user move the camera while the panel stays open.
		local mp = UserInputService:GetMouseLocation()
		local mfPos = MF and MF.AbsolutePosition or Vector2.zero
		local mfSize = MF and MF.AbsoluteSize or Vector2.zero
		local overMain = mp.X >= mfPos.X and mp.X <= mfPos.X+mfSize.X
		             and mp.Y >= mfPos.Y and mp.Y <= mfPos.Y+mfSize.Y
		-- Also check explorer if it's open
		local overExp = false
		if EXP_SG and EXP_SG.Enabled and EXP then
			local ep, es = EXP.AbsolutePosition, EXP.AbsoluteSize
			overExp = mp.X >= ep.X and mp.X <= ep.X+es.X
			      and mp.Y >= ep.Y and mp.Y <= ep.Y+es.Y
		end
		if overMain or overExp then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
	end
end)

-- ============================================================
--  GUI BUILD  (fresh function = new 200-register pool)
-- ============================================================
local MF, TR1, TR2
local _glowStroke, _glowOn
local XHSG

local function _buildGUI()

-- -- WIDGET CONSTRUCTORS ------------------------------------

local function L(par,txt,x,y,w,h,c,sz)
	local l=Instance.new("TextLabel"); l.Size=UDim2.fromOffset(w or 200,h or 14)
	l.Position=UDim2.fromOffset(x,y); l.BackgroundTransparency=1; l.Text=txt
	l.TextColor3=c or C.TEXT; l.Font=Enum.Font.Code; l.TextSize=sz or 11
	l.TextXAlignment=Enum.TextXAlignment.Left; l.ZIndex=6; l.Parent=par; regT(l); return l
end

local function Sp(par,y)
	local s=Instance.new("Frame"); s.Size=UDim2.new(1,-8,0,1); s.Position=UDim2.fromOffset(4,y)
	s.BackgroundColor3=acFt(); s.BorderSizePixel=0; s.ZIndex=5; s.Parent=par
	regC(s,"BackgroundColor3","ft")
end

local function Tg(par,txt,x,y,tbl,key,cb)
	-- Rounded checkbox container
	local box=Instance.new("TextButton"); box.Size=UDim2.fromOffset(14,14)
	box.Position=UDim2.fromOffset(x,y+1); box.BackgroundColor3=tbl[key] and ac2() or C.IN
	box.BorderSizePixel=0; box.Text=""; box.ZIndex=7; box.Parent=par
	corner(box, 4)
	local boxStroke=Instance.new("UIStroke",box); boxStroke.Color=ac(); boxStroke.Thickness=1
	regC(boxStroke,"Color","ac")
	-- Checkmark label
	local ck=Instance.new("TextLabel",box); ck.Size=UDim2.new(1,0,1,0)
	ck.BackgroundTransparency=1; ck.Text=tbl[key] and "+" or ""; ck.TextColor3=rgb(255,255,255)
	ck.Font=Enum.Font.GothamBold; ck.TextSize=9; ck.ZIndex=8
	local lbl=L(par,txt,x+18,y,230,14,tbl[key] and C.TEXT or C.TDIM,11)
	local function refresh()
		box.BackgroundColor3 = tbl[key] and ac2() or C.IN
		ck.Text = tbl[key] and "+" or ""
		lbl.TextColor3 = tbl[key] and C.TEXT or C.TDIM
	end
	table.insert(_refreshers, refresh)  -- registered for config-load sync
	box.MouseButton1Click:Connect(function()
		tbl[key]=not tbl[key]; refresh(); if cb then cb(tbl[key]) end
	end)
	-- Hover effect
	box.MouseEnter:Connect(function() if not tbl[key] then tween(box,{BackgroundColor3=acFt()},TI_FAST) end end)
	box.MouseLeave:Connect(function() if not tbl[key] then tween(box,{BackgroundColor3=C.IN},TI_FAST) end end)
	return box, lbl
end

local function Nm(par,x,y,tbl,key,mn,mx,cb)
	local bg=Instance.new("TextBox"); bg.Size=UDim2.fromOffset(52,16)
	bg.Position=UDim2.fromOffset(x,y); bg.BackgroundColor3=C.IN; bg.BorderSizePixel=0
	bg.Text=tostring(tbl[key]); bg.TextColor3=rgb(180,130,255); bg.Font=Enum.Font.Code
	bg.TextSize=10; bg.ClearTextOnFocus=false; bg.ZIndex=7; bg.Parent=par
	corner(bg, 4)
	local nmStroke=Instance.new("UIStroke",bg); nmStroke.Color=acFt(); nmStroke.Thickness=1
	regC(nmStroke,"Color","ft")
	table.insert(_refreshers, function() bg.Text = tostring(tbl[key]) end)
	bg.FocusLost:Connect(function()
		local n=tonumber(bg.Text)
		if n then n=math.clamp(n,mn or 0,mx or 9999); tbl[key]=n; bg.Text=tostring(n); if cb then cb(n) end
		else bg.Text=tostring(tbl[key]) end
	end); return bg
end

local function BR(par,txt,y,tbl,key,cb)
	local row=Instance.new("Frame"); row.Size=UDim2.new(1,-8,0,18); row.Position=UDim2.fromOffset(4,y)
	row.BackgroundColor3=acMd(); row.BorderSizePixel=0; row.ZIndex=6; row.Parent=par
	corner(row, 6)
	local brStroke=Instance.new("UIStroke",row); brStroke.Color=ac(); brStroke.Thickness=1
	regC(brStroke,"Color","ac")
	local btn=Instance.new("TextButton"); btn.Size=UDim2.new(1,0,1,0); btn.BackgroundTransparency=1
	btn.Text=txt.."  [ "..(tbl[key] and"ON"or"OFF").." ]"
	btn.TextColor3=tbl[key] and C.EN or C.DIS; btn.Font=Enum.Font.Code; btn.TextSize=12; btn.ZIndex=7; btn.Parent=row
	table.insert(_refreshers, function()
		btn.Text = txt.."  [ "..(tbl[key] and "ON" or "OFF").." ]"
		btn.TextColor3 = tbl[key] and C.EN or C.DIS
		row.BackgroundColor3 = tbl[key] and acMd() or acDp()
	end)
	btn.MouseButton1Click:Connect(function()
		tbl[key]=not tbl[key]; btn.Text=txt.."  [ "..(tbl[key] and"ON"or"OFF").." ]"
		tween(btn,{TextColor3=tbl[key] and C.EN or C.DIS},TI_FAST)
		tween(row,{BackgroundColor3=tbl[key] and acMd() or acDp()},TI_FAST)
		if cb then cb(tbl[key]) end
		if notify then
			notify(txt.." " .. (tbl[key] and "enabled" or "disabled"),
				tbl[key] and "success" or "info", 1.5)
		end
	end)
	btn.MouseEnter:Connect(function() tween(row,{BackgroundColor3=tbl[key] and ac() or acFt()},TI_FAST) end)
	btn.MouseLeave:Connect(function() tween(row,{BackgroundColor3=tbl[key] and acMd() or acDp()},TI_FAST) end)
	return btn
end

local function DD(par,x,y,opts,tbl,key,cb)
	local bg=Instance.new("TextButton"); bg.Size=UDim2.fromOffset(110,16); bg.Position=UDim2.fromOffset(x,y)
	bg.BackgroundColor3=C.IN; bg.BorderSizePixel=0
	bg.Text=tostring(tbl[key]).." v"; bg.TextColor3=rgb(180,130,255); bg.Font=Enum.Font.Code
	bg.TextSize=10; bg.ZIndex=7; bg.Parent=par
	corner(bg, 4)
	local ddStroke=Instance.new("UIStroke",bg); ddStroke.Color=acFt(); ddStroke.Thickness=1
	regC(ddStroke,"Color","ft")
	table.insert(_refreshers, function() bg.Text = tostring(tbl[key]).." v" end)
	local open=false; local lF
	bg.MouseButton1Click:Connect(function()
		open=not open; if lF then lF:Destroy(); lF=nil end
		if not open then return end
		lF=Instance.new("Frame"); lF.Size=UDim2.fromOffset(110,#opts*18)
		lF.Position=UDim2.fromOffset(x,y+18); lF.BackgroundColor3=C.IN
		lF.BorderSizePixel=0; lF.ZIndex=20; lF.Parent=par
		corner(lF, 6)
		local lfStroke=Instance.new("UIStroke",lF); lfStroke.Color=acFt(); lfStroke.Thickness=1
		regC(lfStroke,"Color","ft")
		-- Slide-down animation
		lF.ClipsDescendants=true
		lF.Size=UDim2.fromOffset(110,0)
		tween(lF,{Size=UDim2.fromOffset(110,#opts*18)},TI_FAST)
		for i,opt in ipairs(opts) do
			local ob=Instance.new("TextButton"); ob.Size=UDim2.fromOffset(110,18)
			ob.Position=UDim2.fromOffset(0,(i-1)*18); ob.BackgroundColor3=acDp(); ob.BorderSizePixel=0
			ob.Text=opt; ob.TextColor3=C.TEXT; ob.Font=Enum.Font.Code; ob.TextSize=10; ob.ZIndex=21; ob.Parent=lF
			ob.MouseEnter:Connect(function() tween(ob,{BackgroundColor3=acFt()},TI_FAST) end)
			ob.MouseLeave:Connect(function() tween(ob,{BackgroundColor3=acDp()},TI_FAST) end)
			ob.MouseButton1Click:Connect(function()
				tbl[key]=opt; bg.Text=opt.." v"; lF:Destroy(); lF=nil; open=false
				if cb then cb(opt) end
			end)
		end
	end); return bg
end

local function TB(par,txt,x,y,w,h2,bgC,fn)
	local b=Instance.new("TextButton"); b.Size=UDim2.fromOffset(w,h2); b.Position=UDim2.fromOffset(x,y)
	local nc=bgC or acMd()
	b.BackgroundColor3=nc; b.BorderSizePixel=0
	b.Text=txt; b.TextColor3=rgb(255,255,255); b.Font=Enum.Font.Code; b.TextSize=10; b.ZIndex=7; b.Parent=par
	corner(b, 5)
	local bStroke=Instance.new("UIStroke",b); bStroke.Color=ac(); bStroke.Thickness=1
	regC(bStroke,"Color","ac")
	addHover(b, nc, ac())
	if fn then b.MouseButton1Click:Connect(fn) end; return b
end

local function CSl(par,lbl,x,y,ct,ch,fn)
	L(par,lbl,x,y,16,14,C.TDIM,9)
	local tr=Instance.new("Frame"); tr.Size=UDim2.fromOffset(110,10)
	tr.Position=UDim2.fromOffset(x+18,y+2); tr.BackgroundColor3=rgb(30,20,45)
	tr.BorderSizePixel=0; tr.ZIndex=7; tr.Parent=par
	corner(tr, 5)
	local fi=Instance.new("Frame"); fi.Size=UDim2.fromScale(ct[ch]/255,1)
	fi.BackgroundColor3=ac(); fi.BorderSizePixel=0; fi.ZIndex=8; fi.Parent=tr
	corner(fi, 5)
	regC(fi,"BackgroundColor3","ac")
	local vl=L(par,tostring(ct[ch]),x+132,y,30,14,C.TDIM,9)
	local dr=false
	tr.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then dr=true end end)
	UserInputService.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then dr=false end end)
	UserInputService.InputChanged:Connect(function(i)
		if dr and i.UserInputType==Enum.UserInputType.MouseMovement then
			local ab=tr.AbsolutePosition; local sz=tr.AbsoluteSize
			local rel=math.clamp((i.Position.X-ab.X)/sz.X,0,1)
			ct[ch]=math.floor(rel*255); fi.Size=UDim2.fromScale(rel,1); vl.Text=tostring(ct[ch])
			if fn then fn() end
		end
	end)
end

-- ================================================
--  MAIN PANEL FRAME
-- ================================================
local PH=580
MF=Instance.new("Frame"); MF.Name="Main"; MF.Size=UDim2.fromOffset(420,PH)
MF.Position=UDim2.fromOffset(200,80); MF.BackgroundColor3=C.BG
MF.BackgroundTransparency=0.05  -- Slight transparency for glassy feel
MF.BorderSizePixel=0; MF.ClipsDescendants=true; MF.ZIndex=2; MF.Parent=SG
corner(MF, 14)
regBG(MF,"bg")

-- Glass gradient overlay (top brighter, bottom darker)
local mfGrad = Instance.new("UIGradient", MF)
mfGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0,    Color3.fromRGB(28, 22, 42)),
	ColorSequenceKeypoint.new(0.5,  Color3.fromRGB(18, 14, 28)),
	ColorSequenceKeypoint.new(1,    Color3.fromRGB(10,  8, 18)),
})
mfGrad.Rotation = 90

-- Outer glow stack (3 layers of decreasing opacity for soft halo)
for i=1,3 do
	local glow=Instance.new("Frame"); glow.Size=UDim2.new(1, 6+i*4, 1, 6+i*4)
	glow.Position=UDim2.fromOffset(-(3+i*2), -(3+i*2))
	glow.BackgroundColor3=ac()
	glow.BackgroundTransparency=0.92 - (i*0.02)
	glow.BorderSizePixel=0; glow.ZIndex=0; glow.Parent=MF
	corner(glow, 14+i*2)
	regC(glow, "BackgroundColor3", "ac")
end

-- Drop shadow (true black underneath)
local shadow=Instance.new("Frame"); shadow.Size=UDim2.new(1,16,1,16)
shadow.Position=UDim2.fromOffset(-8,-8); shadow.BackgroundColor3=rgb(0,0,0)
shadow.BackgroundTransparency=0.55; shadow.BorderSizePixel=0; shadow.ZIndex=1; shadow.Parent=MF
corner(shadow, 18)

-- Main stroke / accent border
_glowOn=false
local mainStroke=Instance.new("UIStroke",MF); mainStroke.Color=ac(); mainStroke.Thickness=1.5
regC(mainStroke,"Color","ac")
mainStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

-- -- TITLE BAR ---------------------------------------------
local TB2=Instance.new("Frame"); TB2.Size=UDim2.new(1,0,0,32); TB2.BackgroundColor3=acDk()
TB2.BorderSizePixel=0; TB2.ZIndex=3; TB2.ClipsDescendants=true; TB2.Parent=MF
corner(TB2, 14)
-- Title bar gradient
local tbGrad = Instance.new("UIGradient", TB2)
tbGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, acMd()),
	ColorSequenceKeypoint.new(1, acDk()),
})
tbGrad.Rotation = 90
-- Bottom-corner fix (square off the bottom of title bar)
local tbFix=Instance.new("Frame",TB2); tbFix.Size=UDim2.new(1,0,0.45,0)
tbFix.Position=UDim2.new(0,0,0.55,0); tbFix.BackgroundColor3=acDk(); tbFix.BorderSizePixel=0
regC(tbFix,"BackgroundColor3","dk")
regC(TB2,"BackgroundColor3","dk")

local TL=Instance.new("TextLabel"); TL.Size=UDim2.new(0.5,0,1,0); TL.Position=UDim2.fromOffset(10,0)
TL.BackgroundTransparency=1; TL.Text="scopeware"; TL.RichText=true
TL.TextColor3=Color3.fromRGB(240,235,255); TL.Font=Enum.Font.GothamBold; TL.TextSize=13
TL.TextXAlignment=Enum.TextXAlignment.Left; TL.ZIndex=4; TL.Parent=TB2

-- Update title to show version + ENHANCED tag
local function _updateTitle()
	local hex = string.format("#%02X%02X%02X", AC.r, AC.g, AC.b)
	TL.Text = string.format(
		"<b>scopeware</b>  <font size=\"10\" color=\"%s\">V 0.0.9</font>  <font size=\"9\" color=\"#FFB347\"><b>ENHANCED</b></font>",
		hex
	)
end
_updateTitle()
table.insert(_acReg, {TL, "_titleRefresh", "ac"})  -- placeholder; we'll rebuild on accent change below

-- Tagline (right side, subtle)
local TLsub = Instance.new("TextLabel", TB2)
TLsub.AnchorPoint = Vector2.new(1, 0.5)
TLsub.Position = UDim2.new(1, -64, 0.5, 0)
TLsub.Size = UDim2.fromOffset(140, 12)
TLsub.BackgroundTransparency = 1
TLsub.Text = "v0.0.9 build 24"
TLsub.TextColor3 = Color3.fromRGB(140, 130, 180)
TLsub.Font = Enum.Font.Code
TLsub.TextSize = 9
TLsub.TextXAlignment = Enum.TextXAlignment.Right
TLsub.ZIndex = 4

local minState=false
local function makeWinBtn(txt, xOff, bgC, fn)
	local b=Instance.new("TextButton"); b.Size=UDim2.fromOffset(24,20)
	b.AnchorPoint=Vector2.new(1,0.5); b.Position=UDim2.new(1,xOff,0.5,0)
	b.BackgroundColor3=bgC; b.BorderSizePixel=0
	b.Text=txt; b.TextColor3=rgb(255,255,255); b.Font=Enum.Font.GothamBold; b.TextSize=10; b.ZIndex=5; b.Parent=TB2
	corner(b, 5)
	addHover(b, bgC, bgC:Lerp(rgb(255,255,255),0.25))
	b.MouseButton1Click:Connect(fn); return b
end
makeWinBtn("X", -4,  rgb(200,40,60), function()
	tween(MF,{Size=UDim2.fromOffset(MF.AbsoluteSize.X,0),BackgroundTransparency=1},TI_CLOSE)
	task.delay(0.22,function() SG.Enabled=false; MF.Size=UDim2.fromOffset(420,PH); MF.BackgroundTransparency=0 end)
end)
makeWinBtn("-", -28, acDp(), function()
	minState=not minState
	tween(MF,{Size=UDim2.fromOffset(MF.Size.X.Offset, minState and 28 or PH)},TI_MED)
end)

makeDraggable(TB2, MF)

-- Accent line under title bar
local AccLine=Instance.new("Frame"); AccLine.Size=UDim2.new(1,0,0,1); AccLine.Position=UDim2.fromOffset(0,32)
AccLine.BackgroundColor3=ac(); AccLine.BorderSizePixel=0; AccLine.ZIndex=3; AccLine.Parent=MF
regC(AccLine,"BackgroundColor3","ac")

-- -- TAB ROWS ----------------------------------------------
local ROW1={"Aimbot","Visuals","Misc","Rage"}
local ROW2={"Legit","Movement","World/Char","Settings"}
local curTab="Aimbot"; local topBtns={}

TR1=Instance.new("Frame"); TR1.Size=UDim2.new(1,0,0,22); TR1.Position=UDim2.fromOffset(0,33)
TR1.BackgroundColor3=C.PANEL; TR1.BorderSizePixel=0; TR1.ZIndex=3; TR1.Parent=MF; regBG(TR1,"panel")

TR2=Instance.new("Frame"); TR2.Size=UDim2.new(1,0,0,22); TR2.Position=UDim2.fromOffset(0,55)
TR2.BackgroundColor3=C.PANEL; TR2.BorderSizePixel=0; TR2.ZIndex=3; TR2.Parent=MF; regBG(TR2,"panel")

-- Bottom accent line under tab rows
local AccLine2=Instance.new("Frame"); AccLine2.Size=UDim2.new(1,0,0,1); AccLine2.Position=UDim2.fromOffset(0,77)
AccLine2.BackgroundColor3=ac(); AccLine2.BorderSizePixel=0; AccLine2.ZIndex=3; AccLine2.Parent=MF
regC(AccLine2,"BackgroundColor3","ac")

local function mkT(name,idx,row)
	local b=Instance.new("TextButton")
	b.Size=UDim2.new(0.25,-1,1,-2)
	b.Position=UDim2.new((idx-1)*0.25, idx==1 and 1 or 0, 0, 1)
	b.BackgroundColor3=(name==curTab) and ac() or acDp()
	b.BorderSizePixel=0; b.Text=name; b.TextColor3=C.TEXT
	b.Font=Enum.Font.Code; b.TextSize=10; b.ZIndex=4; b.Parent=row
	corner(b, 5)
	-- State-aware hover: only tween if not currently active
	b.MouseEnter:Connect(function()
		if curTab ~= name then tween(b,{BackgroundColor3=ac()},TI_FAST) end
	end)
	b.MouseLeave:Connect(function()
		if curTab ~= name then tween(b,{BackgroundColor3=acDp()},TI_FAST) end
	end)
	topBtns[name]=b
end
for i,n in ipairs(ROW1) do mkT(n,i,TR1) end
for i,n in ipairs(ROW2) do mkT(n,i,TR2) end

-- -- CONTENT AREA ------------------------------------------
local Con=Instance.new("Frame"); Con.Size=UDim2.new(1,0,1,-78); Con.Position=UDim2.fromOffset(0,78)
Con.BackgroundTransparency=1; Con.ClipsDescendants=true; Con.ZIndex=3; Con.Parent=MF
local pages={}
local function mkPage(name)
	local p=Instance.new("Frame"); p.Size=UDim2.new(1,0,1,0)
	p.BackgroundTransparency=1; p.Visible=false; p.ZIndex=4
	p.ClipsDescendants=false; p.Parent=Con; pages[name]=p; return p
end
local H=rgb(180,130,255)

-- ================================================
--  AIMBOT PAGE  (wrapped in IIFE for fresh register pool)
-- ================================================
local AP = (function()
local AP=mkPage("Aimbot")
local ABSS=Instance.new("Frame"); ABSS.Size=UDim2.new(1,0,0,22); ABSS.BackgroundColor3=acDp()
ABSS.BorderSizePixel=0; ABSS.ZIndex=5; ABSS.Parent=AP; regC(ABSS,"BackgroundColor3","dp")
local ABSC=Instance.new("Frame"); ABSC.Size=UDim2.new(1,0,1,-23); ABSC.Position=UDim2.fromOffset(0,23)
ABSC.BackgroundTransparency=1; ABSC.ClipsDescendants=true; ABSC.ZIndex=4; ABSC.Parent=AP
local abSubs={"Aimbot","Auto Aim","FOV"}; local absBtns={}; local absPages={}; local curABS="Aimbot"
for i,sn in ipairs(abSubs) do
	local sb=Instance.new("TextButton"); sb.Size=UDim2.new(0.333,-1,1,-2)
	sb.Position=UDim2.new((i-1)*0.333,0,0,1)
	sb.BackgroundColor3=(sn==curABS) and ac() or acDp()
	sb.BorderSizePixel=0; sb.Text=sn; sb.TextColor3=rgb(255,255,255); sb.Font=Enum.Font.Code; sb.TextSize=10
	sb.ZIndex=6; sb.Parent=ABSS; absBtns[sn]=sb
	corner(sb,5)
	-- State-aware hover
	do local _sn=sn
		sb.MouseEnter:Connect(function()
			if curABS~=_sn then tween(sb,{BackgroundColor3=ac()},TI_FAST) end
		end)
		sb.MouseLeave:Connect(function()
			if curABS~=_sn then tween(sb,{BackgroundColor3=acDp()},TI_FAST) end
		end)
	end
	local sp2=Instance.new("Frame"); sp2.Size=UDim2.new(1,0,1,0)
	sp2.BackgroundTransparency=1; sp2.Visible=(sn==curABS); sp2.ZIndex=5; sp2.Parent=ABSC; absPages[sn]=sp2
end
local function switchABS(n) curABS=n
	for k,b in pairs(absBtns) do tween(b,{BackgroundColor3=(k==n) and ac() or acDp()},TI_FAST) end
	for k,p in pairs(absPages) do p.Visible=(k==n) end
end
for n,b in pairs(absBtns) do b.MouseButton1Click:Connect(function() switchABS(n) end) end

local ABP1=absPages["Aimbot"]
BR(ABP1,"Aimbot On/Off",4,AB,"On",function() abPlyr=nil;abLock=nil end)
Sp(ABP1,30)
L(ABP1,"[ Settings ]",8,36,200,14,H,11); Sp(ABP1,52)
Tg(ABP1,"Smooth Aim",            8, 58,AB,"Smooth")
L(ABP1,"Smooth Factor:",         8, 78,100,14,C.TDIM,10); Nm(ABP1,114,78,AB,"SF",0.01,1.0)
Tg(ABP1,"WallBang (shoot thru walls)",8,96,AB,"WallBang")
Tg(ABP1,"Team Check",            8,114,AB,"TeamCheck")
Tg(ABP1,"Predict Movement",      8,132,AB,"PredictMov")
Tg(ABP1,"Silent Aim (no camera move)",8,150,AB,"Silent")
Tg(ABP1,"Aim at Nearest Part",   8,168,AB,"NearPart")
Sp(ABP1,186)
L(ABP1,"[ Click Mode ]",8,192,200,14,H,11); Sp(ABP1,208)
Tg(ABP1,"Hold Fire (hold LMB)",  8,214,AB,"HoldFire")
L(ABP1,"Click Rate (s):",        8,234,100,14,C.TDIM,10)
Nm(ABP1,110,234,{v=clickRate},{v=0.06},0.02,1.0,function(n)clickRate=n end)
Sp(ABP1,252)
L(ABP1,"[ Keybind ]",8,258,200,14,H,11); Sp(ABP1,274)
L(ABP1,"Aim Key:",8,280,60,14,C.TDIM,10)
DD(ABP1,72,280,{"RMB","LMB","E","R","F","Q"},AB,"KeyMode")

local ABP2=absPages["Auto Aim"]
local AA={On=false,HitPart="Head",TeamCheck=false,MaxDist=300,AimMode="Camera",Smooth=true,SF=0.15}
L(ABP2,"[ Auto Aim ]",8,4,300,14,H,11); Sp(ABP2,20)
L(ABP2,"Automatically aims at nearest player in FOV.",8,26,400,11,C.TDIM,9)
L(ABP2,"No key needed — always active when enabled.",8,38,400,11,C.TDIM,9)
Sp(ABP2,54)
Tg(ABP2,"Auto Aim Active",8,60,AA,"On")
Sp(ABP2,80)
L(ABP2,"Target Part:",8,86,80,14,C.TDIM,10)
DD(ABP2,92,86,{"Head","Torso","HumanoidRootPart"},AA,"HitPart")
Tg(ABP2,"Team Check",8,106,AA,"TeamCheck")
L(ABP2,"Max Distance:",8,126,95,14,C.TDIM,10); Nm(ABP2,100,126,AA,"MaxDist",10,2000)
Sp(ABP2,146)
L(ABP2,"[ Aim Mode ]",8,152,200,14,H,11); Sp(ABP2,168)
L(ABP2,"Camera = moves your view",  8,174,380,11,C.TDIM,9)
L(ABP2,"Mouse  = moves your cursor",8,185,380,11,C.TDIM,9)
L(ABP2,"Both   = camera + cursor together",8,196,380,11,C.TDIM,9)
L(ABP2,"Mode:",8,210,45,14,C.TDIM,10)
DD(ABP2,56,210,{"Camera","Mouse","Both"},AA,"AimMode")
Sp(ABP2,230)
L(ABP2,"[ Smooth ]",8,236,200,14,H,11); Sp(ABP2,252)
Tg(ABP2,"Smooth Aim",8,258,AA,"Smooth")
L(ABP2,"Smooth Factor:",8,278,100,14,C.TDIM,10); Nm(ABP2,106,278,AA,"SF",0.01,1.0)

RunService.RenderStepped:Connect(function()
	if not AA.On or not alive(LP) or abKey() then return end
	local cam2=workspace.CurrentCamera; if not cam2 then return end
	local cx2=cam2.ViewportSize.X/2; local cy2=cam2.ViewportSize.Y/2
	local lh=HRP(LP); if not lh then return end
	local bestPart=nil; local bestDist=math.huge
	for _,p in ipairs(Players:GetPlayers()) do
		if p==LP or not alive(p) then continue end
		if AA.TeamCheck and p.Team==LP.Team then continue end
		local part=p.Character and p.Character:FindFirstChild(AA.HitPart) or HRP(p)
		if not part then continue end
		local worldDist=(part.Position-lh.Position).Magnitude
		if worldDist > AA.MaxDist then continue end
		local sp2,on2=cam2:WorldToViewportPoint(part.Position)
		if not on2 or sp2.Z < 0 then continue end
		local screenDist=math.sqrt((sp2.X-cx2)^2+(sp2.Y-cy2)^2)
		if screenDist < AB.FOVSize and worldDist < bestDist then
			bestDist=worldDist; bestPart=part
		end
	end
	if not bestPart then return end
	local targetPos=bestPart.Position
	local cp2=cam2.CFrame.Position
	if AA.AimMode=="Camera" or AA.AimMode=="Both" then
		local dir=(targetPos-cp2).Unit
		if AA.Smooth then
			local lerped=cam2.CFrame.LookVector:Lerp(dir, math.clamp(AA.SF,0.01,1))
			cam2.CFrame=CFrame.new(cp2, cp2+lerped)
		else
			cam2.CFrame=CFrame.new(cp2, targetPos)
		end
	end
	if AA.AimMode=="Mouse" or AA.AimMode=="Both" then
		local sp3,on3=cam2:WorldToViewportPoint(targetPos)
		if on3 then pcall(function() mousemoverel(sp3.X-cx2, sp3.Y-cy2) end) end
	end
end)

-- ABP3 is the inner page; wrap content in a ScrollingFrame
do
	local outer = absPages["FOV"]
	local sf = Instance.new("ScrollingFrame", outer)
	sf.Size = UDim2.new(1,0,1,0); sf.BackgroundTransparency = 1
	sf.BorderSizePixel = 0; sf.ScrollBarThickness = 4
	sf.ScrollBarImageColor3 = ac()
	sf.ScrollingDirection = Enum.ScrollingDirection.Y
	sf.CanvasSize = UDim2.new(0,0,0,460)
	sf.ZIndex = 5
	regC(sf,"ScrollBarImageColor3","ac")
	absPages["FOV"] = sf  -- redirect so existing widget creation lands inside scroll
end
local ABP3=absPages["FOV"]
local FOVS={On=false,Val=70}
L(ABP3,"[ FOV Circle ]",8,4,200,14,H,11); Sp(ABP3,20)
Tg(ABP3,"Show FOV Circle",8,26,AB,"FOVOn")
L(ABP3,"FOV Size:",      8,48,70,14,C.TDIM,10); Nm(ABP3,82,48,AB,"FOVSize",10,600)
Sp(ABP3,68)
L(ABP3,"[ Field of View ]",8,74,200,14,H,11); Sp(ABP3,90)
Tg(ABP3,"Custom Game FOV",8,96,FOVS,"On",function(v)
	if not v then local c3=workspace.CurrentCamera; if c3 then c3.FieldOfView=70 end end
end)
L(ABP3,"FOV Value:",8,118,80,14,C.TDIM,10); Nm(ABP3,92,118,FOVS,"Val",30,120)
RunService.RenderStepped:Connect(function()
	if FOVS.On and not abCamOn and not rgCamOn then
		local c4=workspace.CurrentCamera
		if c4 then c4.FieldOfView=FOVS.Val end
	end
end)
Sp(ABP3,138)
L(ABP3,"[ FOV Appearance ]",8,144,200,14,H,11); Sp(ABP3,160)
L(ABP3,"Color R:",  8,166,60,14,C.TDIM,10); Nm(ABP3,72,166,AB,"FovColorR",0,255)
L(ABP3,"Color G:",130,166,60,14,C.TDIM,10); Nm(ABP3,194,166,AB,"FovColorG",0,255)
L(ABP3,"Color B:",  8,184,60,14,C.TDIM,10); Nm(ABP3,72,184,AB,"FovColorB",0,255)
L(ABP3,"Thickness:",130,184,70,14,C.TDIM,10); Nm(ABP3,206,184,AB,"FovThickness",1,8)
Tg(ABP3,"Filled FOV (disc instead of ring)", 8,204,AB,"FovFilled")
Sp(ABP3,224)
L(ABP3,"[ Aim Behavior ]",8,230,200,14,H,11); Sp(ABP3,246)
L(ABP3,"Hitbox Expansion:",   8,252,120,14,C.TDIM,10); Nm(ABP3,130,252,AB,"HitboxExpand",0,500)
L(ABP3,"Adds to FOV check radius.",8,270,400,11,C.TDIM,9)
Tg(ABP3,"Predict Movement", 8,286,AB,"PredictMov")
L(ABP3,"Predict Strength:",   8,306,120,14,C.TDIM,10); Nm(ABP3,130,306,AB,"PredictStr",0,2)
L(ABP3,"Lerps target along velocity vector.",8,324,400,11,C.TDIM,9)
L(ABP3,"Min Target HP:",      8,340,120,14,C.TDIM,10); Nm(ABP3,130,340,AB,"MinHP",0,1000)
L(ABP3,"Skip targets below this HP.",8,358,400,11,C.TDIM,9)
L(ABP3,"Priority:",           8,374,60,14,C.TDIM,10)
DD(ABP3,72,374,{"FOV","Distance","Health"},AB,"TargetPriority")
Sp(ABP3,394)
L(ABP3,"[ Notes ]",8,400,200,14,H,11); Sp(ABP3,416)
L(ABP3,"Aimbot never changes FOV while locking.",8,422,400,11,C.TDIM,9)
L(ABP3,"Custom FOV only applies when not aiming.",8,434,400,11,C.TDIM,9)
return AP
end)()

-- ================================================
--  VISUALS PAGE  (wrapped in IIFE for fresh register pool)
-- ================================================
local VP = (function()
local VP=mkPage("Visuals")
local VSS=Instance.new("Frame"); VSS.Size=UDim2.new(1,0,0,22); VSS.BackgroundColor3=acDp()
VSS.BorderSizePixel=0; VSS.ZIndex=5; VSS.Parent=VP; regC(VSS,"BackgroundColor3","dp")
local VSC=Instance.new("Frame"); VSC.Size=UDim2.new(1,0,1,-23); VSC.Position=UDim2.fromOffset(0,23)
VSC.BackgroundTransparency=1; VSC.ClipsDescendants=true; VSC.ZIndex=4; VSC.Parent=VP
local vsubs={"ESP","Crosshair","Xray"}; local vsBtns={}; local vsPages={}; local curVS="ESP"
for i,sn in ipairs(vsubs) do
	local sb=Instance.new("TextButton"); sb.Size=UDim2.new(0.333,-1,1,-2); sb.Position=UDim2.new((i-1)*0.333,0,0,1)
	sb.BackgroundColor3=(sn==curVS) and ac() or acDp(); sb.BorderSizePixel=0
	sb.Text=sn; sb.TextColor3=C.TEXT; sb.Font=Enum.Font.Code; sb.TextSize=11; sb.ZIndex=6; sb.Parent=VSS; vsBtns[sn]=sb
	corner(sb,5)
	do local _sn=sn
		sb.MouseEnter:Connect(function()
			if curVS~=_sn then tween(sb,{BackgroundColor3=ac()},TI_FAST) end
		end)
		sb.MouseLeave:Connect(function()
			if curVS~=_sn then tween(sb,{BackgroundColor3=acDp()},TI_FAST) end
		end)
	end
	local sp=Instance.new("Frame"); sp.Size=UDim2.new(1,0,1,0); sp.BackgroundTransparency=1
	sp.Visible=(sn==curVS); sp.ZIndex=5; sp.Parent=VSC; vsPages[sn]=sp
end
local function switchVS(n) curVS=n
	for k,b in pairs(vsBtns) do tween(b,{BackgroundColor3=(k==n) and ac() or acDp()},TI_FAST) end
	for k,p in pairs(vsPages) do p.Visible=(k==n) end
end
for n,b in pairs(vsBtns) do b.MouseButton1Click:Connect(function() switchVS(n) end) end

-- ESP page: wrap in scrolling frame to fit all the new options
do
	local outer = vsPages["ESP"]
	local sf = Instance.new("ScrollingFrame", outer)
	sf.Size = UDim2.new(1,0,1,0); sf.BackgroundTransparency = 1
	sf.BorderSizePixel = 0; sf.ScrollBarThickness = 4
	sf.ScrollBarImageColor3 = ac()
	sf.ScrollingDirection = Enum.ScrollingDirection.Y
	sf.CanvasSize = UDim2.new(0,0,0,460)
	sf.ZIndex = 5
	regC(sf,"ScrollBarImageColor3","ac")
	vsPages["ESP"] = sf
end
local EP=vsPages["ESP"]
L(EP,"[ ESP Toggles ]",4,4,200,14,H,11); Sp(EP,20)
local EVL=Instance.new("Frame"); EVL.Size=UDim2.fromOffset(196,140); EVL.Position=UDim2.fromOffset(4,24); EVL.BackgroundTransparency=1; EVL.ZIndex=6; EVL.Parent=EP
local EVR=Instance.new("Frame"); EVR.Size=UDim2.fromOffset(196,140); EVR.Position=UDim2.fromOffset(212,24); EVR.BackgroundTransparency=1; EVR.ZIndex=6; EVR.Parent=EP
Tg(EVL,"ESP Boxes",    0, 0,VS,"Boxes",   espAll)
Tg(EVL,"ESP Names",    0,18,VS,"Names",   espAll)
Tg(EVL,"ESP Health",   0,36,VS,"Health",  espAll)
Tg(EVL,"ESP Distance", 0,54,VS,"Dist",    espAll)
Tg(EVL,"Head Dot",     0,72,VS,"HeadDot", espAll)
Tg(EVL,"Skeleton",     0,90,VS,"Skeleton",espAll)
Tg(EVR,"Chams",        0, 0,VS,"Chams",   espAll)
Tg(EVR,"Tracer Lines", 0,18,VS,"Tracers", espAll)
Tg(EVR,"Weapon Label", 0,36,VS,"Weapon",  espAll)
Tg(EVR,"Armor Info",   0,54,VS,"Armor",   espAll)
Tg(EVR,"Team Color",   0,72,VS,"TeamColor",espAll)
L(EP,"ESP Toggle Key: T (toggles all at once)",4,168,400,12,C.TDIM,10)
Sp(EP,184)
L(EP,"[ Modes ]",4,190,200,14,H,11); Sp(EP,206)
L(EP,"Chams Mode:",4,212,80,14,C.TDIM,10)
DD(EP,88,212,{"Solid","Outline","Glow"},VS,"ChamsMode",function() espAll() end)
L(EP,"Tracer Origin:",4,232,90,14,C.TDIM,10)
DD(EP,98,232,{"Bottom","Center","Mouse"},VS,"TracerOrigin")
Sp(EP,254)
L(EP,"[ ESP Colors ]",4,260,200,14,H,11); Sp(EP,276)
local function eCh() espAll() end
L(EP,"Box:",4,282,30,14,C.TEXT,10);    CSl(EP,"R",38,282,EC.Box,"r",eCh);    CSl(EP,"G",38,298,EC.Box,"g",eCh);    CSl(EP,"B",38,314,EC.Box,"b",eCh)
L(EP,"Chams:",210,282,44,14,C.TEXT,10);CSl(EP,"R",258,282,EC.Chams,"r",eCh); CSl(EP,"G",258,298,EC.Chams,"g",eCh); CSl(EP,"B",258,314,EC.Chams,"b",eCh)
L(EP,"Trace:",4,330,44,14,C.TEXT,10);  CSl(EP,"R",52,330,EC.Tracer,"r",eCh); CSl(EP,"G",52,346,EC.Tracer,"g",eCh); CSl(EP,"B",52,362,EC.Tracer,"b",eCh)
L(EP,"Skeleton:",210,330,60,14,C.TEXT,10);CSl(EP,"R",274,330,EC.Skeleton,"r",eCh);CSl(EP,"G",274,346,EC.Skeleton,"g",eCh);CSl(EP,"B",274,362,EC.Skeleton,"b",eCh)
L(EP,"Team:",4,378,40,14,C.TEXT,10);   CSl(EP,"R",48,378,EC.Team,"r",eCh);   CSl(EP,"G",48,394,EC.Team,"g",eCh);   CSl(EP,"B",48,410,EC.Team,"b",eCh)
L(EP,"Enemy:",210,378,50,14,C.TEXT,10);CSl(EP,"R",264,378,EC.Enemy,"r",eCh); CSl(EP,"G",264,394,EC.Enemy,"g",eCh); CSl(EP,"B",264,410,EC.Enemy,"b",eCh)

local CP=vsPages["Crosshair"]
local XH={On=false,Style="Cross",Size=10,Thick=2,Gap=4,R=255,G=255,B=255,Outline=true,Spin=false,SpinSpd=2,Dot=true}
XHSG=Instance.new("ScreenGui"); XHSG.Name="swCH"; XHSG.ResetOnSpawn=false; XHSG.IgnoreGuiInset=true; XHSG.Enabled=true; XHSG.Parent=PG
local XHF=Instance.new("Frame"); XHF.BackgroundTransparency=1; XHF.ZIndex=20; XHF.AnchorPoint=Vector2.new(0.5,0.5); XHF.Size=UDim2.fromOffset(120,120); XHF.BorderSizePixel=0; XHF.Parent=XHSG
local xhPs={}
local function xhCl() for _,f in ipairs(xhPs) do f:Destroy() end; xhPs={} end
local function xhB(x,y,w2,h2)
	local f=Instance.new("Frame"); f.BackgroundColor3=rgb(XH.R,XH.G,XH.B)
	f.BorderSizePixel=XH.Outline and 1 or 0; f.BorderColor3=rgb(0,0,0)
	f.Size=UDim2.fromOffset(math.max(1,w2),math.max(1,h2)); f.Position=UDim2.fromOffset(60+x,60+y)
	f.ZIndex=21; f.Parent=XHF; table.insert(xhPs,f)
end
local xhStyles={"Cross","Dot","Circle","Square","T-Shape","X-Shape","Sniper"}; local xhIdx=1
local function rebuildXH()
	xhCl(); if not XH.On then XHF.Visible=false; return end; XHF.Visible=true
	local s=XH.Size; local t=XH.Thick; local g=XH.Gap
	if XH.Style=="Cross" then xhB(-s,-t//2,s-g,t);xhB(g,-t//2,s-g,t);xhB(-t//2,-s,t,s-g);xhB(-t//2,g,t,s-g)
	elseif XH.Style=="Dot" then xhB(-t,-t,t*2,t*2)
	elseif XH.Style=="Circle" then for i=0,15 do local a=i/16*math.pi*2;xhB(math.cos(a)*s-t//2,math.sin(a)*s-t//2,t,t) end
	elseif XH.Style=="Square" then xhB(-s,-s,s*2,t);xhB(-s,s-t,s*2,t);xhB(-s,-s,t,s*2);xhB(s-t,-s,t,s*2)
	elseif XH.Style=="T-Shape" then xhB(-s,-t//2,s*2,t);xhB(-t//2,g,t,s-g)
	elseif XH.Style=="X-Shape" then for i=-s,s do xhB(i,i,t,t);xhB(s-i-t,i,t,t) end
	elseif XH.Style=="Sniper" then xhB(-s*3,-t//2,s*3-g,t);xhB(g,-t//2,s*3-g,t);xhB(-t//2,-s*3,t,s*3-g);xhB(-t//2,g,t,s*3-g) end
	if XH.Dot then xhB(-t//2,-t//2,t,t) end
end
local xhAng=0
RunService.RenderStepped:Connect(function()
	if not XH.On then XHF.Visible=false; return end
	local cam=workspace.CurrentCamera; if not cam then XHF.Visible=false; return end
	XHF.Visible=true
	XHF.Position=UDim2.fromOffset(cam.ViewportSize.X/2, cam.ViewportSize.Y/2)
	if XH.Spin then xhAng=(xhAng+XH.SpinSpd)%360; XHF.Rotation=xhAng else XHF.Rotation=0 end
end)
L(CP,"[ Crosshair ]",4,4,200,14,H,11); Sp(CP,20)
BR(CP,"Crosshair",24,XH,"On",function() rebuildXH() end)
L(CP,"Style:",4,50,40,14,C.TDIM,10)
local xhSLbl=L(CP,XH.Style,78,50,90,14,H,11)
TB(CP,"<",52,50,22,16,acMd(),function() xhIdx=(xhIdx-2+#xhStyles)%#xhStyles+1;XH.Style=xhStyles[xhIdx];xhSLbl.Text=XH.Style;rebuildXH() end)
TB(CP,">",172,50,22,16,acMd(),function() xhIdx=xhIdx%#xhStyles+1;XH.Style=xhStyles[xhIdx];xhSLbl.Text=XH.Style;rebuildXH() end)
Sp(CP,68)
L(CP,"Size:",4,74,50,14,C.TDIM,10); Nm(CP,56,74,XH,"Size",1,50,function()rebuildXH()end)
L(CP,"Thick:",120,74,50,14,C.TDIM,10); Nm(CP,174,74,XH,"Thick",1,10,function()rebuildXH()end)
L(CP,"Gap:",4,92,40,14,C.TDIM,10); Nm(CP,46,92,XH,"Gap",0,30,function()rebuildXH()end)
Sp(CP,110)
L(CP,"Color R:",4,116,60,14,C.TDIM,10); CSl(CP,"",68,116,XH,"R",function()rebuildXH()end)
L(CP,"Color G:",4,132,60,14,C.TDIM,10); CSl(CP,"",68,132,XH,"G",function()rebuildXH()end)
L(CP,"Color B:",4,148,60,14,C.TDIM,10); CSl(CP,"",68,148,XH,"B",function()rebuildXH()end)
Tg(CP,"Outline",4,166,XH,"Outline",function()rebuildXH()end)
Tg(CP,"Center Dot",4,184,XH,"Dot",function()rebuildXH()end)
Tg(CP,"Spin",4,202,XH,"Spin")
L(CP,"Spin Speed:",4,220,90,14,C.TDIM,10); Nm(CP,96,220,XH,"SpinSpd",0.1,20)

local XP=vsPages["Xray"]
local XR={PlayerXray=false,XR=255,XG=50,XB=50,Opacity=0.5,ShowTM=false,TMR=50,TMG=200,TMB=50,WallAlpha=false,WAmt=0.7}
local xrHLs={}
local function apXR(player)
	if xrHLs[player] then pcall(function()xrHLs[player]:Destroy()end) end
	if not player.Character then return end
	local hl=Instance.new("Highlight")
	local isTm=player.Team and player.Team==LP.Team
	hl.FillColor=(isTm and XR.ShowTM) and rgb(XR.TMR,XR.TMG,XR.TMB) or rgb(XR.XR,XR.XG,XR.XB)
	hl.OutlineColor=hl.FillColor; hl.FillTransparency=XR.Opacity; hl.OutlineTransparency=0
	hl.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop; hl.Adornee=player.Character; hl.Parent=player.Character; xrHLs[player]=hl
end
local function rmXR(p) if xrHLs[p] then pcall(function()xrHLs[p]:Destroy()end);xrHLs[p]=nil end end
local function refXR()
	for _,p in ipairs(Players:GetPlayers()) do
		if p~=LP then if XR.PlayerXray then apXR(p) else rmXR(p) end end
	end
end
for _,p in ipairs(Players:GetPlayers()) do if p~=LP then p.CharacterAdded:Connect(function() if XR.PlayerXray then task.wait(0.2);apXR(p) end end) end end
Players.PlayerAdded:Connect(function(p) p.CharacterAdded:Connect(function() if XR.PlayerXray then task.wait(0.2);apXR(p) end end) end)
L(XP,"[ X-Ray ]",4,4,200,14,H,11); Sp(XP,20)
BR(XP,"Player X-Ray",24,XR,"PlayerXray",function()refXR()end)
L(XP,"Highlights all players through walls.",4,50,400,12,C.TDIM,10); Sp(XP,66)
L(XP,"X-Ray Color:",4,72,90,14,C.TDIM,10)
CSl(XP,"R",98,72,XR,"XR",function()refXR()end); CSl(XP,"G",98,88,XR,"XG",function()refXR()end); CSl(XP,"B",98,104,XR,"XB",function()refXR()end)
L(XP,"Opacity:",4,120,60,14,C.TDIM,10); Nm(XP,68,120,XR,"Opacity",0,1,function()refXR()end)
Tg(XP,"Show Teammates (green)",4,140,XR,"ShowTM",function()refXR()end); Sp(XP,162)
BR(XP,"Wall Alpha (see thru walls)",166,XR,"WallAlpha",function(v)
	task.spawn(function()
		for _,obj in ipairs(workspace:GetDescendants()) do
			if obj:IsA("BasePart") then
				local iC=false; for _,p in ipairs(Players:GetPlayers()) do if p.Character and obj:IsDescendantOf(p.Character) then iC=true;break end end
				if not iC then obj.LocalTransparencyModifier=v and XR.WAmt or 0 end
			end
		end
	end)
end)
L(XP,"Wall Opacity:",4,192,90,14,C.TDIM,10); Nm(XP,98,192,XR,"WAmt",0,1)
return VP
end)()

-- ================================================
--  MISC PAGE  (wrapped in IIFE for fresh register pool)
-- ================================================
local MP = (function()
local MP=mkPage("Misc")
local MPSS=Instance.new("Frame"); MPSS.Size=UDim2.new(1,0,0,22)
MPSS.BackgroundColor3=acDp(); MPSS.BorderSizePixel=0; MPSS.ZIndex=5; MPSS.Parent=MP
regC(MPSS,"BackgroundColor3","dp")
local MPSC=Instance.new("Frame"); MPSC.Size=UDim2.new(1,0,1,-23); MPSC.Position=UDim2.fromOffset(0,23)
MPSC.BackgroundTransparency=1; MPSC.ZIndex=4; MPSC.Parent=MP
local mpSubs={"Misc","Script Hub"}; local mpBtns={}; local mpPages={}; local curMPS="Misc"
for i,sn in ipairs(mpSubs) do
	local sb=Instance.new("TextButton"); sb.Size=UDim2.new(0.5,-1,1,-2)
	sb.Position=UDim2.new((i-1)*0.5,0,0,1)
	sb.BackgroundColor3=(sn==curMPS) and ac() or acDp()
	sb.BorderSizePixel=0; sb.Text=sn; sb.TextColor3=rgb(255,255,255); sb.Font=Enum.Font.Code; sb.TextSize=10
	sb.ZIndex=6; sb.Parent=MPSS; mpBtns[sn]=sb
	corner(sb,5)
	do local _sn=sn
		sb.MouseEnter:Connect(function()
			if curMPS~=_sn then tween(sb,{BackgroundColor3=ac()},TI_FAST) end
		end)
		sb.MouseLeave:Connect(function()
			if curMPS~=_sn then tween(sb,{BackgroundColor3=acDp()},TI_FAST) end
		end)
	end
	local pg=Instance.new("Frame"); pg.Size=UDim2.new(1,0,1,0)
	pg.BackgroundTransparency=1; pg.Visible=(sn==curMPS); pg.ZIndex=5; pg.Parent=MPSC; mpPages[sn]=pg
end
local function switchMPS(n) curMPS=n
	for k,b in pairs(mpBtns) do tween(b,{BackgroundColor3=(k==n) and ac() or acDp()},TI_FAST) end
	for k,p in pairs(mpPages) do p.Visible=(k==n) end
end
for n,b in pairs(mpBtns) do b.MouseButton1Click:Connect(function() switchMPS(n) end) end

local MPM=mpPages["Misc"]
L(MPM,"[ General ]",8,4,200,14,H,11); Sp(MPM,20)
local MS={}
Tg(MPM,"Anti-AFK",   8,26,MS,"AFK",function(v) _G._sw_antiafk=v end)
Tg(MPM,"Auto Rejoin",8,44,MS,"ARejoin")
Sp(MPM,66)
L(MPM,"[ Morph ]",8,72,200,14,H,11); Sp(MPM,88)
L(MPM,"Copy any player appearance.",8,94,390,11,C.TDIM,9)
L(MPM,"Username:",8,108,68,14,C.TDIM,10)
local mBox=Instance.new("TextBox"); mBox.Size=UDim2.fromOffset(200,20); mBox.Position=UDim2.fromOffset(78,107)
mBox.BackgroundColor3=C.IN; mBox.BorderSizePixel=0
mBox.PlaceholderText="Enter username..."; mBox.PlaceholderColor3=C.TDIM
mBox.Text=""; mBox.TextColor3=rgb(200,170,255); mBox.Font=Enum.Font.Code; mBox.TextSize=11; mBox.ZIndex=7; mBox.Parent=MPM
corner(mBox,5)
local mBoxS=Instance.new("UIStroke",mBox);mBoxS.Color=acFt();mBoxS.Thickness=1;regC(mBoxS,"Color","ft")
local mSt=L(MPM,"",8,132,390,14,C.TDIM,10)
TB(MPM,"Apply Morph",8,150,96,16,acMd(),function()
	mSt.Text="Loading..."; mSt.TextColor3=C.TDIM
	task.spawn(function()
		local ok,name=applyMorph(mBox.Text)
		mSt.Text=ok and "+ Morphed into "..name or "X "..name
		mSt.TextColor3=ok and C.EN or C.DIS
	end)
end)
TB(MPM,"Reset",110,150,80,16,acDp(),function()
	task.spawn(function() resetMorph(); mSt.Text="+ Reset"; mSt.TextColor3=C.EN end)
end)
Sp(MPM,174)
L(MPM,"[ Stretched Resolution ]",8,180,290,14,H,11); Sp(MPM,196)
L(MPM,"Narrows FOV to simulate a stretched screen.",8,202,390,11,C.TDIM,9)
local SR={On=false,Ratio=0.75}
local _origFOV2=70
Tg(MPM,"Stretch Screen",8,214,SR,"On",function(v)
	local cam9=workspace.CurrentCamera; if not cam9 then return end
	if v then _origFOV2=cam9.FieldOfView; cam9.FieldOfView=math.clamp(_origFOV2*SR.Ratio,30,120)
	else cam9.FieldOfView=_origFOV2 end
end)
L(MPM,"Ratio (0.5-1.0):",8,236,110,14,C.TDIM,10)
Nm(MPM,116,236,SR,"Ratio",0.5,1.0,function()
	if SR.On then local c9b=workspace.CurrentCamera
		if c9b then c9b.FieldOfView=math.clamp(_origFOV2*SR.Ratio,30,120) end
	end
end)

local MPSH=mpPages["Script Hub"]
L(MPSH,"[ Script Hub ]",8,4,300,14,H,11); Sp(MPSH,20)
L(MPSH,"Load external scripts into the current game.",8,26,390,11,C.TDIM,9)
Sp(MPSH,42)

local shY=52
local function shEntry(par, name, desc, url)
	L(par,"[ "..name.." ]",8,shY,390,14,H,11); shY+=16
	L(par,desc,8,shY,390,11,C.TDIM,9); shY+=14
	local st=L(par,"",8,shY,390,11,C.TDIM,9); shY+=14
	local tbl={}
	Tg(par,"Load "..name,8,shY,tbl,"on",function(v)
		if not v then st.Text=""; return end
		st.Text="Loading..."; st.TextColor3=C.TDIM
		task.spawn(function()
			local ok,err=pcall(function() loadstring(game:HttpGet(url))() end)
			st.Text=ok and ("+ "..name.." loaded!") or ("X "..tostring(err):sub(1,45))
			st.TextColor3=ok and C.EN or C.DIS
			if not ok then tbl.on=false end
		end)
	end)
	shY+=22
	local sp3=Instance.new("Frame"); sp3.Size=UDim2.new(1,-8,0,1); sp3.Position=UDim2.fromOffset(4,shY)
	sp3.BackgroundColor3=acFt(); sp3.BorderSizePixel=0; sp3.ZIndex=5; sp3.Parent=par
	regC(sp3,"BackgroundColor3","ft"); shY+=10
end
shEntry(MPSH,"Infinite Yield","Admin commands panel for any Roblox game.",
	"https://raw.githubusercontent.com/EdgeIY/infinite-yield/master/source")
shEntry(MPSH,"DEX Explorer","Full instance tree explorer for the game.",
	"https://raw.githubusercontent.com/infyiff/backup/main/dex.lua")

local econSt=L(MPSH,"",8,shY+30,390,11,C.TDIM,9)
L(MPSH,"[ Econ ]",8,shY,390,14,H,11); shY+=16
L(MPSH,"Economy/trading tool for supported games.",8,shY,390,11,C.TDIM,9); shY+=28
local ECON={}
Tg(MPSH,"Load Econ",8,shY,ECON,"on",function(v)
	if not v then econSt.Text=""; return end
	econSt.Text="Loading Econ..."; econSt.TextColor3=C.TDIM
	task.spawn(function()
		local ok,err=pcall(function()
			loadstring(game:HttpGet("https://raw.githubusercontent.com/EconRCO/Econ/refs/heads/main/Init"))()
		end)
		econSt.Text=ok and "+ Econ loaded!" or "X "..tostring(err):sub(1,45)
		econSt.TextColor3=ok and C.EN or C.DIS
		if not ok then ECON.on=false end
	end)
end)
shY+=22
local sep4=Instance.new("Frame"); sep4.Size=UDim2.new(1,-8,0,1); sep4.Position=UDim2.fromOffset(4,shY)
sep4.BackgroundColor3=acFt(); sep4.BorderSizePixel=0; sep4.ZIndex=5; sep4.Parent=MPSH
regC(sep4,"BackgroundColor3","ft"); shY+=10

local khSt=L(MPSH,"",8,shY+30,390,11,C.TDIM,9)
L(MPSH,"[ KiciaHook ]",8,shY,390,14,H,11); shY+=16
L(MPSH,"KiciaHook loader — hooks into game scripts.",8,shY,390,11,C.TDIM,9); shY+=28
local KHK={}
Tg(MPSH,"Load KiciaHook",8,shY,KHK,"on",function(v)
	if not v then khSt.Text=""; return end
	khSt.Text="Loading KiciaHook..."; khSt.TextColor3=C.TDIM
	task.spawn(function()
		local ok,err=pcall(function()
			loadstring(game:HttpGet("https://raw.githubusercontent.com/kiciahook/kiciahook/refs/heads/main/loader.lua"))()
		end)
		khSt.Text=ok and "+ KiciaHook loaded!" or "X "..tostring(err):sub(1,45)
		khSt.TextColor3=ok and C.EN or C.DIS
		if not ok then KHK.on=false end
	end)
end)
return MP
end)()

-- ================================================
--  RAGE PAGE  (wrapped in IIFE for fresh register pool)
-- ================================================
local RP = (function()
local RP=mkPage("Rage")
local RL=Instance.new("Frame"); RL.Size=UDim2.new(0.48,-4,1,-8); RL.Position=UDim2.fromOffset(4,4); RL.BackgroundTransparency=1; RL.ZIndex=5; RL.Parent=RP
local RR=Instance.new("Frame"); RR.Size=UDim2.new(0.48,-4,1,-8); RR.Position=UDim2.new(0.51,0,0,4); RR.BackgroundTransparency=1; RR.ZIndex=5; RR.Parent=RP
L(RL,"[ Rage Mode ]",0,0,236,14,H,11); Sp(RL,16)
BR(RP,"Rage Mode",20,RG,"On",function(v) if v then rgPick() else rgTgt=nil;_holdMode=false;clickOn=false end end)
Sp(RL,46)
Tg(RL,"Auto Switch on Death",      0, 52,RG,"AutoSwitch")
Tg(RL,"Team Check (skip teammates)",0, 70,RG,"TeamCheck",function()rgTgt=nil;rgPick()end)
Tg(RL,"Invisible While Raging",    0, 88,RG,"Invisible")
L(RL,"Spam Delay:",                0,108,90,14,C.TDIM,10); Nm(RL,96,108,RG,"SpamDelay",0.01,2.0)
L(RL,"Behind Dist:",               0,128,90,14,C.TDIM,10); Nm(RL,96,128,RG,"BehindDist",1,15)
Sp(RL,148)
L(RL,"[ Mode ]",0,154,236,14,H,11); Sp(RL,170)
L(RL,"Camera Mode:",0,176,100,14,C.TDIM,10)
DD(RL,106,176,{"Behind","CamBehind"},RG,"CamMode")
L(RL,"Behind=body teleports | CamBehind=camera moves",0,196,236,10,C.TDIM,9)
Sp(RL,210)
L(RL,"[ Click Mode ]",0,216,236,14,H,11); Sp(RL,232)
Tg(RL,"Hold LMB (for hold-to-attack)",0,238,RG,"HoldClick")
Sp(RL,260)
L(RL,"[ Speed & Camera ]",0,266,236,14,H,11); Sp(RL,282)
Tg(RL,"Speed Boost",               0,288,RG,"SpeedBoost")
L(RL,"Speed:",                     0,308,50,14,C.TDIM,10); Nm(RL,56,308,RG,"SpeedBoostVal",16,500)
Tg(RL,"Force Camera Down",         0,328,RG,"LookDown")
L(RL,"Down Angle (0=head 90=down):",0,348,210,14,C.TDIM,10); Nm(RL,214,348,RG,"LookDownAngle",0,90)
Sp(RL,368)
L(RL,"[ Keybind ]",0,374,236,14,H,11); Sp(RL,390)
L(RL,"Rage Key:",0,396,70,14,C.TDIM,10)
DD(RL,76,396,{"Always","G","H","X","Z"},RG,"KeyMode")
L(RR,"[ Kill Extras ]",0,0,236,14,H,11); Sp(RR,16)
Tg(RR,"Kill Aura",   0, 22,KA,"KillAura")
L(RR,"Aura Radius:", 0, 42,80,14,C.TDIM,10); Nm(RR,86,42,KA,"KAR",2,60)
Tg(RR,"Anti Knockback",0,62,KA,"AntiKB")
Tg(RR,"Bunny Hop",   0, 82,KA,"BunnyHop")
L(RR,"Bhop Speed:",  0,102,80,14,C.TDIM,10); Nm(RR,86,102,KA,"BhopSpeed",16,300)
Sp(RR,122)
L(RR,"[ WARNING ]",0,128,236,14,rgb(255,80,80),11)
L(RR,"Rage is very obvious. Use at own risk.",0,144,236,12,C.TDIM,10)
return RP
end)()

-- ================================================
--  LEGIT PAGE  (wrapped in IIFE for fresh register pool)
-- ================================================
local LGP = (function()
local LGP=mkPage("Legit")
local LL=Instance.new("Frame"); LL.Size=UDim2.new(0.48,-4,1,-8); LL.Position=UDim2.fromOffset(4,4); LL.BackgroundTransparency=1; LL.ZIndex=5; LL.Parent=LGP
local LR=Instance.new("Frame"); LR.Size=UDim2.new(0.48,-4,1,-8); LR.Position=UDim2.new(0.51,0,0,4); LR.BackgroundTransparency=1; LR.ZIndex=5; LR.Parent=LGP
L(LL,"[ Legit Presets ]",0,0,200,14,H,11); Sp(LL,16)
local function apLeg(sf,fov,wb) AB.On=true;AB.Smooth=true;AB.WallBang=wb or false;AB.SF=sf;AB.FOVSize=fov end
local presets={{n="Subtle",sf=0.06,fov=40},{n="Medium",sf=0.12,fov=70},{n="Aggressive",sf=0.20,fov=100},{n="Rage Legit",sf=0.30,fov=140}}
for i,p in ipairs(presets) do
	TB(LL,p.n,0,(i-1)*28+22,190,16,acDp(),function()apLeg(p.sf,p.fov)end)
end
Sp(LL,140)
L(LL,"[ Manual Tune ]",0,146,200,14,H,11); Sp(LL,162)
L(LL,"FOV:",0,168,35,14,C.TDIM,10); Nm(LL,40,168,AB,"FOVSize",10,200)
L(LL,"Smooth:",0,188,55,14,C.TDIM,10); Nm(LL,60,188,AB,"SF",0.01,0.5)
Tg(LL,"WallBang",0,208,AB,"WallBang")
Tg(LL,"Team Check",0,226,AB,"TeamCheck")
Sp(LL,244)
L(LL,"[ Triggerbot ]",0,250,200,14,H,11); Sp(LL,266)
local TB2l={On=false,Delay=0.08,Key="Mouse2"}
Tg(LL,"Triggerbot",0,272,TB2l,"On")
L(LL,"Fire Delay:",0,292,75,14,C.TDIM,10); Nm(LL,80,292,TB2l,"Delay",0.01,0.5)
L(LL,"Fires when crosshair is on a player.",0,312,190,11,C.TDIM,9)
RunService.Heartbeat:Connect(function()
	if not TB2l.On or not alive(LP) then return end
	local cam5=workspace.CurrentCamera; if not cam5 then return end
	local cx5=cam5.ViewportSize.X/2; local cy5=cam5.ViewportSize.Y/2
	for _,p in ipairs(Players:GetPlayers()) do
		if p==LP or not alive(p) then continue end
		for _,part in ipairs({"Head","Torso","UpperTorso","LowerTorso"}) do
			local bp=p.Character and p.Character:FindFirstChild(part)
			if bp then
				local sp5,on5=cam5:WorldToViewportPoint(bp.Position)
				if on5 then
					local d5=math.sqrt((sp5.X-cx5)^2+(sp5.Y-cy5)^2)
					if d5 < 18 then task.spawn(tapClick); task.wait(TB2l.Delay) end
				end
			end
		end
	end
end)
L(LR,"[ Aim Assist ]",0,0,200,14,H,11); Sp(LR,16)
local LT={On=false,Str=0.3,FOV=60,TeamCheck=false}
Tg(LR,"Aim Assist (soft lock)",0,22,LT,"On")
L(LR,"Strength:",0,44,70,14,C.TDIM,10); Nm(LR,76,44,LT,"Str",0.05,1)
L(LR,"Assist FOV:",0,64,75,14,C.TDIM,10); Nm(LR,80,64,LT,"FOV",10,200)
Tg(LR,"Team Check",0,84,LT,"TeamCheck")
L(LR,"Gently pulls aim toward nearest player.",0,104,195,11,C.TDIM,9)
RunService.RenderStepped:Connect(function()
	if not LT.On or not abKey() or not alive(LP) then return end
	local cam6=workspace.CurrentCamera; if not cam6 then return end
	local cx6=cam6.ViewportSize.X/2; local cy6=cam6.ViewportSize.Y/2
	local best,bestD2=nil,math.huge
	for _,p in ipairs(Players:GetPlayers()) do
		if p==LP or not alive(p) then continue end
		if LT.TeamCheck and p.Team==LP.Team then continue end
		local hd=p.Character and p.Character:FindFirstChild("Head")
		if not hd then continue end
		local sp6,on6=cam6:WorldToViewportPoint(hd.Position)
		if not on6 then continue end
		local d6=math.sqrt((sp6.X-cx6)^2+(sp6.Y-cy6)^2)
		if d6 < LT.FOV and d6 < bestD2 then bestD2=d6; best=hd end
	end
	if best then
		local cp6=cam6.CFrame.Position
		local dir=(best.Position-cp6).Unit
		local cur=cam6.CFrame.LookVector
		local lerped=cur:Lerp(dir, LT.Str*0.1)
		cam6.CFrame=CFrame.new(cp6, cp6+lerped)
	end
end)
Sp(LR,120)
L(LR,"[ Anti-Recoil ]",0,126,200,14,H,11); Sp(LR,142)
local AR2={On=false,Str=0.5}
Tg(LR,"Anti-Recoil",0,148,AR2,"On")
L(LR,"Strength:",0,168,70,14,C.TDIM,10); Nm(LR,76,168,AR2,"Str",0.1,1)
L(LR,"Counters upward camera drift.",0,188,195,11,C.TDIM,9)
RunService.RenderStepped:Connect(function()
	if not AR2.On or not alive(LP) then return end
	local cam7=workspace.CurrentCamera; if not cam7 then return end
	local cf7=cam7.CFrame
	cam7.CFrame=cf7*CFrame.Angles(AR2.Str*0.001,0,0)
end)
return LGP
end)()

-- ================================================
--  MOVEMENT PAGE  (wrapped in IIFE for fresh register pool)
-- ================================================
local MVPg = (function()
local MVPg=mkPage("Movement")
local MVL=Instance.new("Frame"); MVL.Size=UDim2.new(0.48,-4,1,-8); MVL.Position=UDim2.fromOffset(4,4); MVL.BackgroundTransparency=1; MVL.ZIndex=5; MVL.Parent=MVPg
local MVR=Instance.new("Frame"); MVR.Size=UDim2.new(0.48,-4,1,-8); MVR.Position=UDim2.new(0.51,0,0,4); MVR.BackgroundTransparency=1; MVR.ZIndex=5; MVR.Parent=MVPg
L(MVL,"[ Basic ]",0,0,200,14,H,11); Sp(MVL,16)
Tg(MVL,"Infinite Jump",           0, 22,MV,"InfJump")
Tg(MVL,"Speed Hack",              0, 40,MV,"Speed")
L(MVL,"Speed:",                   0, 60,50,14,C.TDIM,10); Nm(MVL,54,60,MV,"SpeedVal",16,500)
Tg(MVL,"Low Gravity",             0, 80,MV,"LowGrav")
L(MVL,"Gravity:",                 0,100,60,14,C.TDIM,10); Nm(MVL,66,100,MV,"GravVal",1,200)
Tg(MVL,"No Fall Damage",          0,120,MV,"NoFall")
Tg(MVL,"Noclip",                  0,138,MV,"Noclip")
Sp(MVL,158)
L(MVL,"[ Fly ]",0,164,200,14,H,11); Sp(MVL,180)
Tg(MVL,"Fly (WASD + Space/Shift)",0,186,MV,"Fly",function(v)if not v then flyDn()end end)
L(MVL,"Fly Speed:",               0,206,70,14,C.TDIM,10); Nm(MVL,76,206,MV,"FlySpeed",10,200)
Sp(MVL,226)
L(MVL,"[ Spinbot ]",0,232,200,14,H,11); Sp(MVL,248)
Tg(MVL,"Spinbot",                 0,254,MV,"Spinbot")
L(MVL,"Spin Speed:",              0,274,80,14,C.TDIM,10); Nm(MVL,86,274,MV,"SpinSpeed",1,720)

L(MVR,"[ Advanced ]",0,0,200,14,H,11); Sp(MVR,16)
local MV2={WallWalk=false,SuperJump=false,SJVal=100,FastAccel=false,AccelVal=200}
Tg(MVR,"Wall Walk (no collision)",0,22,MV2,"WallWalk",function(v)
	pcall(function()
		for _,p in ipairs(workspace:GetDescendants()) do
			if p:IsA("BasePart") and not LP.Character:FindFirstChild(p.Name) then
				p.CanCollide = not v
			end
		end
	end)
end)
Tg(MVR,"Super Jump",              0,42,MV2,"SuperJump")
L(MVR,"Jump Power:",              0,62,80,14,C.TDIM,10); Nm(MVR,86,62,MV2,"SJVal",50,500)
Tg(MVR,"Fast Acceleration",       0,82,MV2,"FastAccel")
L(MVR,"Acceleration:",            0,102,90,14,C.TDIM,10); Nm(MVR,96,102,MV2,"AccelVal",50,1000)
Sp(MVR,122)
L(MVR,"[ Teleport ]",0,128,200,14,H,11); Sp(MVR,144)
local TP={Waypoints={},WPName=""}
L(MVR,"Name:",0,150,40,14,C.TDIM,10)
local wpBox=Instance.new("TextBox"); wpBox.Size=UDim2.fromOffset(140,18); wpBox.Position=UDim2.fromOffset(44,150)
wpBox.BackgroundColor3=C.IN; wpBox.BorderSizePixel=0
wpBox.PlaceholderText="Waypoint name..."; wpBox.PlaceholderColor3=C.TDIM
wpBox.Text=""; wpBox.TextColor3=rgb(180,130,255); wpBox.Font=Enum.Font.Code; wpBox.TextSize=9; wpBox.ZIndex=7; wpBox.Parent=MVR
corner(wpBox,5)
local wpbS=Instance.new("UIStroke",wpBox);wpbS.Color=acFt();wpbS.Thickness=1;regC(wpbS,"Color","ft")
TB(MVR,"Save Pos",0,174,90,16,acMd(),function()
	local nm=wpBox.Text:gsub("^%s+",""):gsub("%s+$","")
	if nm~="" and HRP(LP) then TP.Waypoints[nm]=HRP(LP).CFrame end
end)
TB(MVR,"Teleport",96,174,90,16,acMd(),function()
	local nm=wpBox.Text:gsub("^%s+",""):gsub("%s+$","")
	local hrpT=HRP(LP)
	if nm~="" and TP.Waypoints[nm] and hrpT then hrpT.CFrame=TP.Waypoints[nm] end
end)
Sp(MVR,198)
L(MVR,"[ Character ]",0,204,200,14,H,11); Sp(MVR,220)
Tg(MVR,"Custom Jump Power",       0,226,WC,"JumpPower")
L(MVR,"Jump Power:",              0,246,80,14,C.TDIM,10); Nm(MVR,86,246,WC,"JumpVal",1,500)
Tg(MVR,"Custom Hip Height",       0,266,WC,"HipHeight")
L(MVR,"Hip Height:",              0,286,80,14,C.TDIM,10); Nm(MVR,86,286,WC,"HipVal",0,30)

RunService.Heartbeat:Connect(function()
	local h8=Hum(LP)
	if h8 then
		if MV2.SuperJump then h8.JumpPower=MV2.SJVal end
		if MV2.FastAccel  then pcall(function() h8:ChangeState(Enum.HumanoidStateType.RunningNoPhysics) end) end
	end
end)
return MVPg
end)()

-- ================================================
--  WORLD/CHAR PAGE  (wrapped in IIFE for fresh register pool)
-- ================================================
local WPg = (function()
local WPg=mkPage("World/Char")
local WL=Instance.new("Frame"); WL.Size=UDim2.new(0.48,-4,1,-8); WL.Position=UDim2.fromOffset(4,4); WL.BackgroundTransparency=1; WL.ZIndex=5; WL.Parent=WPg
local WR=Instance.new("Frame"); WR.Size=UDim2.new(0.48,-4,1,-8); WR.Position=UDim2.new(0.51,0,0,4); WR.BackgroundTransparency=1; WR.ZIndex=5; WR.Parent=WPg
L(WL,"[ World ]",0,0,236,14,H,11); Sp(WL,16)
Tg(WL,"Fullbright",       0, 22,WC,"FullBright")
Tg(WL,"Remove Fog",       0, 40,WC,"FogRemove")
Tg(WL,"Freeze Time",      0, 58,WC,"TimeFreeze")
L(WL,"Clock Time (0-24):",0, 78,130,14,C.TDIM,10); Nm(WL,136,78,WC,"FrozenTime",0,24)
Sp(WL,98)
L(WL,"[ Ambient & Lighting ]",0,104,236,14,H,11); Sp(WL,120)
Tg(WL,"Custom Ambient",   0,126,WC,"CustomAmb")
L(WL,"R:",0,146,16,14,C.TDIM,10); Nm(WL,18,146,WC,"AmbR",0,255)
L(WL,"G:",58,146,16,14,C.TDIM,10); Nm(WL,76,146,WC,"AmbG",0,255)
L(WL,"B:",116,146,16,14,C.TDIM,10); Nm(WL,134,146,WC,"AmbB",0,255)
Tg(WL,"Custom Brightness",0,166,WC,"CustomBright")
L(WL,"Value:",            0,186,50,14,C.TDIM,10); Nm(WL,56,186,WC,"BrightVal",0,10)
Tg(WL,"Custom Outdoor Amb",0,206,WC,"CustomOutAmb")
L(WL,"R:",0,226,16,14,C.TDIM,10); Nm(WL,18,226,WC,"OAR",0,255)
L(WL,"G:",58,226,16,14,C.TDIM,10); Nm(WL,76,226,WC,"OAG",0,255)
L(WL,"B:",116,226,16,14,C.TDIM,10); Nm(WL,134,226,WC,"OAB",0,255)
Sp(WL,246)
L(WL,"[ Skybox ]",0,252,200,14,H,11); Sp(WL,268)
L(WL,"Paste a Roblox Sky asset ID below:",0,274,200,11,C.TDIM,9)
local skyBox=Instance.new("TextBox"); skyBox.Size=UDim2.fromOffset(190,20)
skyBox.Position=UDim2.fromOffset(0,288); skyBox.BackgroundColor3=C.IN; skyBox.BorderSizePixel=0
skyBox.Text=WC.SkyboxId; skyBox.TextColor3=rgb(180,130,255); skyBox.Font=Enum.Font.Code
skyBox.TextSize=10; skyBox.ClearTextOnFocus=false; skyBox.ZIndex=7; skyBox.Parent=WL
corner(skyBox,5)
local sboxS=Instance.new("UIStroke",skyBox);sboxS.Color=acFt();sboxS.Thickness=1;regC(sboxS,"Color","ft")
skyBox.FocusLost:Connect(function() WC.SkyboxId=skyBox.Text end)
local skySt=L(WL,"",0,312,200,11,C.TDIM,9)
TB(WL,"Apply",  0,326, 90,16,acMd(),function()
	local id=skyBox.Text:gsub("^%s+",""):gsub("%s+$","")
	if id~="" then
		WC.SkyboxId=id
		skySt.Text="Verifying..."; skySt.TextColor3=C.TDIM
		task.spawn(function()
			local ok, msg = applySkybox(id)
			skySt.Text = ok and ("+ Applied ID "..id) or ("X "..msg)
			skySt.TextColor3 = ok and C.EN or C.DIS
		end)
	else skySt.Text="X Enter an ID first"; skySt.TextColor3=C.DIS end
end)
TB(WL,"Remove",96,326,90,16,acDp(),function()
	removeSkybox(); skySt.Text="Sky removed"; skySt.TextColor3=C.TDIM
end)
L(WL,"[ Sky Presets ]",0,348,200,14,H,11)
-- Verified working skybox decal IDs (commonly-used in the Roblox community)
local SKYBOX_PRESETS2={
	{n="Space",   id="6444884785"},
	{n="Bluesky", id="6444884785"},  -- placeholder
	{n="Night",   id="271042320"},
	{n="Sunset",  id="271042442"},
	{n="Galaxy",  id="271042516"},
	{n="Clouds",  id="271077243"},
}
for i,p in ipairs(SKYBOX_PRESETS2) do
	TB(WL,p.n,(math.fmod(i-1,3))*66,366+math.floor((i-1)/3)*22,62,18,acDp(),function()
		WC.SkyboxId=p.id; skyBox.Text=p.id
		skySt.Text="Loading "..p.n.."..."; skySt.TextColor3=C.TDIM
		task.spawn(function()
			local ok, msg = applySkybox(p.id)
			skySt.Text = ok and ("+ "..p.n) or ("X "..msg)
			skySt.TextColor3 = ok and C.EN or C.DIS
		end)
	end)
end

L(WR,"[ Character ]",0,0,236,14,H,11); Sp(WR,16)
Tg(WR,"Custom Jump Power",  0, 22,WC,"JumpPower")
L(WR,"Jump Power:",          0, 42,90,14,C.TDIM,10); Nm(WR,96,42,WC,"JumpVal",1,500)
Tg(WR,"Custom Hip Height",   0, 62,WC,"HipHeight")
L(WR,"Hip Height:",          0, 82,90,14,C.TDIM,10); Nm(WR,96,82,WC,"HipVal",0,30)
Sp(WR,102)
L(WR,"[ Visibility ]",0,108,236,14,H,11); Sp(WR,124)
Tg(WR,"Hide Local Char",     0,130,WC,"HideChar")
Tg(WR,"Transparent Char",    0,148,WC,"Transparent")
L(WR,"Opacity:",             0,168,60,14,C.TDIM,10); Nm(WR,66,168,WC,"TransAmt",0,1)
Sp(WR,188)
L(WR,"[ Arm Position Offset ]",0,194,236,14,H,11); Sp(WR,210)
Tg(WR,"Enable Arm Offset",   0,216,WC,"ArmOffset")
L(WR,"X:",0,236,20,14,C.TDIM,10); Nm(WR,20,236,WC,"ArmX",-5,5)
L(WR,"Y:",62,236,20,14,C.TDIM,10); Nm(WR,82,236,WC,"ArmY",-5,5)
L(WR,"Z:",124,236,20,14,C.TDIM,10); Nm(WR,144,236,WC,"ArmZ",-5,5)
TB(WR,"Apply Offset",0,258,120,16,acMd(),function()
	if WC.ArmOffset then task.spawn(applyArmOffset) end
end)
Sp(WR,282)
L(WR,"[ Morph ]",0,288,236,14,H,11); Sp(WR,304)
local wMB=Instance.new("TextBox"); wMB.Size=UDim2.fromOffset(190,20); wMB.Position=UDim2.fromOffset(0,310)
wMB.BackgroundColor3=C.IN; wMB.BorderSizePixel=0
wMB.PlaceholderText="Username..."; wMB.PlaceholderColor3=C.TDIM
wMB.Text=""; wMB.TextColor3=rgb(200,170,255); wMB.Font=Enum.Font.Code; wMB.TextSize=10; wMB.ZIndex=7; wMB.Parent=WR
corner(wMB,5)
local wmbS=Instance.new("UIStroke",wMB);wmbS.Color=acFt();wmbS.Thickness=1;regC(wmbS,"Color","ft")
local wMS=L(WR,"",0,334,236,12,C.TDIM,10)
TB(WR,"Apply",0,350,110,16,acMd(),function()
	wMS.Text="Loading..."; task.spawn(function()
		local ok,n=applyMorph(wMB.Text)
		wMS.Text=ok and "+ "..n or "X "..n; wMS.TextColor3=ok and C.EN or C.DIS
	end)
end)
TB(WR,"Reset Morph",116,350,120,16,acDp(),function()
	task.spawn(function() resetMorph(); wMS.Text="+ Reset"; wMS.TextColor3=C.EN end)
end)
return WPg
end)()

-- ================================================
--  SETTINGS PAGE  (wrapped in own function for fresh 200-register pool)
--  Without this wrapper Lua hits "Out of local registers" at compile time.
-- ================================================
local function _buildSettings()
local SPg=mkPage("Settings")  -- outer page

-- Sub-tab bar
local SPSS=Instance.new("Frame"); SPSS.Size=UDim2.new(1,0,0,22)
SPSS.BackgroundColor3=acDp(); SPSS.BorderSizePixel=0; SPSS.ZIndex=5; SPSS.Parent=SPg
regC(SPSS,"BackgroundColor3","dp")
local SPSC=Instance.new("Frame"); SPSC.Size=UDim2.new(1,0,1,-23); SPSC.Position=UDim2.fromOffset(0,23)
SPSC.BackgroundTransparency=1; SPSC.ZIndex=4; SPSC.Parent=SPg
local spSubs={"Settings","About"}; local spBtns={}; local spPages={}; local curSPS="Settings"
for i,sn in ipairs(spSubs) do
	local sb=Instance.new("TextButton"); sb.Size=UDim2.new(0.5,-1,1,-2)
	sb.Position=UDim2.new((i-1)*0.5,0,0,1)
	sb.BackgroundColor3=(sn==curSPS) and ac() or acDp()
	sb.BorderSizePixel=0; sb.Text=sn; sb.TextColor3=rgb(255,255,255); sb.Font=Enum.Font.Code; sb.TextSize=10
	sb.ZIndex=6; sb.Parent=SPSS; spBtns[sn]=sb
	corner(sb,5)
	do local _sn=sn
		sb.MouseEnter:Connect(function()
			if curSPS~=_sn then tween(sb,{BackgroundColor3=ac()},TI_FAST) end
		end)
		sb.MouseLeave:Connect(function()
			if curSPS~=_sn then tween(sb,{BackgroundColor3=acDp()},TI_FAST) end
		end)
	end
	local pg=Instance.new("Frame"); pg.Size=UDim2.new(1,0,1,0)
	pg.BackgroundTransparency=1; pg.Visible=(sn==curSPS); pg.ZIndex=5; pg.Parent=SPSC; spPages[sn]=pg
end
local function switchSPS(n) curSPS=n
	for k,b in pairs(spBtns) do tween(b,{BackgroundColor3=(k==n) and ac() or acDp()},TI_FAST) end
	for k,p in pairs(spPages) do p.Visible=(k==n) end
end
for n,b in pairs(spBtns) do b.MouseButton1Click:Connect(function() switchSPS(n) end) end

-- SP is a SCROLLING FRAME inside the Settings sub-page so content can scroll
local SPouter = spPages["Settings"]
local SP = Instance.new("ScrollingFrame")
SP.Size = UDim2.new(1,0,1,0)
SP.CanvasSize = UDim2.new(0,0,0,820)  -- Fits all settings content with presets
SP.BackgroundTransparency = 1
SP.BorderSizePixel = 0
SP.ScrollBarThickness = 4
SP.ScrollBarImageColor3 = ac()
SP.ScrollingDirection = Enum.ScrollingDirection.Y
SP.ZIndex = 5
SP.Parent = SPouter
regC(SP, "ScrollBarImageColor3", "ac")

L(SP,"[ Display ]",8,4,200,14,H,11); Sp(SP,20)
local USS={}
Tg(SP,"Show Watermark (drag to move)", 8,26,USS,"WM",function(v) showWM=v; WM.Visible=v end)
Tg(SP,"Show Status Bar (drag to move)",8,44,USS,"SB",function(v) showSB=v; SBar.Visible=v end)
local _perfHud_t={on=false}
Tg(SP,"Show Performance HUD",8,62,_perfHud_t,"on",function(v)
	showPerfHUD = v; PerfHUD.Visible = v
	if v and notify then notify("Performance HUD enabled","info",1.5) end
end)
local _notifs_t={on=true}
Tg(SP,"Enable Notifications",8,80,_notifs_t,"on",function(v) NOTIFS_ENABLED = v end)
Sp(SP,102)
L(SP,"[ Presets ]",8,108,200,14,H,11); Sp(SP,124)
L(SP,"Apply curated bundles of settings:",8,130,400,11,C.TDIM,9)
local presetNames = {"Legit", "Rage", "HvH", "Visual", "Off"}
for i, pn in ipairs(presetNames) do
	local px = 8 + ((i-1) % 3) * 130
	local py = 146 + math.floor((i-1) / 3) * 24
	TB(SP, pn, px, py, 122, 20, acMd(), function() applyPreset(pn) end)
end
Sp(SP,200)
L(SP,"[ Panel Size ]",8,206,200,14,H,11); Sp(SP,222)
L(SP,"Width:",8,228,45,14,C.TDIM,10)
local pwBox=Instance.new("TextBox"); pwBox.Size=UDim2.fromOffset(52,16); pwBox.Position=UDim2.fromOffset(56,228)
pwBox.BackgroundColor3=C.IN; pwBox.BorderSizePixel=0
pwBox.Text="420"; pwBox.TextColor3=rgb(180,130,255); pwBox.Font=Enum.Font.Code; pwBox.TextSize=10
pwBox.ClearTextOnFocus=false; pwBox.ZIndex=7; pwBox.Parent=SP
corner(pwBox,4)
local pwbS=Instance.new("UIStroke",pwBox);pwbS.Color=acFt();pwbS.Thickness=1;regC(pwbS,"Color","ft")
L(SP,"Height:",120,228,50,14,C.TDIM,10)
local phBox=Instance.new("TextBox"); phBox.Size=UDim2.fromOffset(52,16); phBox.Position=UDim2.fromOffset(174,228)
phBox.BackgroundColor3=C.IN; phBox.BorderSizePixel=0
phBox.Text=tostring(PH); phBox.TextColor3=rgb(180,130,255); phBox.Font=Enum.Font.Code; phBox.TextSize=10
phBox.ClearTextOnFocus=false; phBox.ZIndex=7; phBox.Parent=SP
corner(phBox,4)
local phbS=Instance.new("UIStroke",phBox);phbS.Color=acFt();phbS.Thickness=1;regC(phbS,"Color","ft")
L(SP,"Min 300x400  |  Max 600x800",8,250,380,11,C.TDIM,9)
TB(SP,"Apply",8,264,90,16,acMd(),function()
	local w=math.clamp(tonumber(pwBox.Text) or 420,300,600)
	local h=math.clamp(tonumber(phBox.Text) or 580,400,800)
	pwBox.Text=tostring(w); phBox.Text=tostring(h); PH=h
	tween(MF,{Size=UDim2.fromOffset(w,h)},TI_MED)
end)
TB(SP,"Reset",104,264,80,16,acDp(),function()
	PH=580; tween(MF,{Size=UDim2.fromOffset(420,580)},TI_MED)
	pwBox.Text="420"; phBox.Text="580"
end)
Sp(SP,288)
L(SP,"[ UI Accent Color ]",8,294,200,14,H,11); Sp(SP,310)
local prevBox=Instance.new("Frame"); prevBox.Size=UDim2.fromOffset(34,34)
prevBox.Position=UDim2.fromOffset(375,316); prevBox.BackgroundColor3=ac()
prevBox.BorderSizePixel=0; prevBox.ZIndex=7; prevBox.Parent=SP
corner(prevBox,8); regC(prevBox,"BackgroundColor3","ac")
local function onAC()
	applyAC(); prevBox.BackgroundColor3=ac()
	for n,b in pairs(topBtns) do tween(b,{BackgroundColor3=(n==curTab) and ac() or acDp()},TI_FAST) end
	for n,b in pairs(vsBtns)  do tween(b,{BackgroundColor3=(n==curVS)  and ac() or acDp()},TI_FAST) end
	for _,f in pairs(Trs) do pcall(function() f.BackgroundColor3=rgb(EC.Tracer.r,EC.Tracer.g,EC.Tracer.b) end) end
end
CSl(SP,"R",8,316,AC,"r",onAC); CSl(SP,"G",8,332,AC,"g",onAC); CSl(SP,"B",8,348,AC,"b",onAC)
local cPresets={{n="Purple",r=110,g=40,b=200},{n="Blue",r=30,g=80,b=220},{n="Red",r=200,g=20,b=40},
	{n="Green",r=20,g=180,b=60},{n="Orange",r=220,g=100,b=20},{n="Pink",r=220,g=40,b=160}}
for i,p in ipairs(cPresets) do
	local pb=Instance.new("TextButton"); pb.Size=UDim2.fromOffset(122,18)
	pb.Position=UDim2.fromOffset(8+((i-1)%3)*130, 368+math.floor((i-1)/3)*22)
	pb.BackgroundColor3=rgb(p.r,p.g,p.b); pb.BorderSizePixel=0
	pb.Text=p.n; pb.TextColor3=rgb(255,255,255); pb.Font=Enum.Font.Code; pb.TextSize=9; pb.ZIndex=7; pb.Parent=SP
	corner(pb,5)
	addHover(pb, rgb(p.r,p.g,p.b), rgb(math.min(255,p.r+40),math.min(255,p.g+20),math.min(255,p.b+40)))
	pb.MouseButton1Click:Connect(function() AC.r=p.r;AC.g=p.g;AC.b=p.b; onAC() end)
end
Sp(SP,416)
L(SP,"[ Config System ]",8,422,300,14,H,11); Sp(SP,438)
L(SP,"CREATE: snapshot all settings to text. Copy & share it.",8,444,400,11,C.TDIM,9)
L(SP,"LOAD:   paste a config text below, then click Load.",8,456,400,11,C.TDIM,9)
local cfgIO=Instance.new("TextBox"); cfgIO.Size=UDim2.fromOffset(400,44)
cfgIO.Position=UDim2.fromOffset(8,472); cfgIO.BackgroundColor3=rgb(6,4,14)
cfgIO.BorderSizePixel=0
cfgIO.PlaceholderText="Paste config here, or click Create to generate..."
cfgIO.PlaceholderColor3=rgb(50,40,80); cfgIO.Text=""
cfgIO.TextColor3=rgb(160,255,160); cfgIO.Font=Enum.Font.Code; cfgIO.TextSize=8
cfgIO.ClearTextOnFocus=false; cfgIO.MultiLine=false; cfgIO.ZIndex=7; cfgIO.Parent=SP
corner(cfgIO,6)
local cfgS=Instance.new("UIStroke",cfgIO);cfgS.Color=acFt();cfgS.Thickness=1;regC(cfgS,"Color","ft")
local cfgSt=L(SP,"",8,522,400,12,C.TDIM,10)

local function serCfg()
	return JSON.encode({
		ver = "sw009",
		-- Aimbot
		AB_On=AB.On, AB_FOVOn=AB.FOVOn, AB_FOVSize=AB.FOVSize,
		AB_Smooth=AB.Smooth, AB_SF=AB.SF,
		AB_WallBang=AB.WallBang, AB_TeamCheck=AB.TeamCheck,
		AB_HoldFire=AB.HoldFire, AB_KeyMode=AB.KeyMode,
		-- Ragebot
		RG_On=RG.On, RG_SpamDelay=RG.SpamDelay, RG_AutoSwitch=RG.AutoSwitch,
		RG_BehindDist=RG.BehindDist, RG_TeamCheck=RG.TeamCheck,
		RG_CamMode=RG.CamMode, RG_LookDown=RG.LookDown, RG_LookDownAngle=RG.LookDownAngle,
		RG_Invisible=RG.Invisible, RG_SpeedBoost=RG.SpeedBoost, RG_SpeedBoostVal=RG.SpeedBoostVal,
		RG_HoldClick=RG.HoldClick, RG_KeyMode=RG.KeyMode,
		-- Movement
		MV_Spinbot=MV.Spinbot, MV_SpinSpeed=MV.SpinSpeed,
		MV_InfJump=MV.InfJump, MV_Speed=MV.Speed, MV_SpeedVal=MV.SpeedVal,
		MV_Fly=MV.Fly, MV_FlySpeed=MV.FlySpeed,
		MV_Noclip=MV.Noclip, MV_NoFall=MV.NoFall,
		MV_LowGrav=MV.LowGrav, MV_GravVal=MV.GravVal,
		-- Visuals
		VS_Boxes=VS.Boxes, VS_Names=VS.Names, VS_Health=VS.Health,
		VS_Dist=VS.Dist, VS_HeadDot=VS.HeadDot, VS_Chams=VS.Chams, VS_Tracers=VS.Tracers,
		EC_BoxR=EC.Box.r, EC_BoxG=EC.Box.g, EC_BoxB=EC.Box.b,
		EC_ChamsR=EC.Chams.r, EC_ChamsG=EC.Chams.g, EC_ChamsB=EC.Chams.b,
		EC_TraceR=EC.Tracer.r, EC_TraceG=EC.Tracer.g, EC_TraceB=EC.Tracer.b,
		-- Kill aura / extras
		KA_KillAura=KA.KillAura, KA_KAR=KA.KAR,
		KA_AntiKB=KA.AntiKB, KA_BunnyHop=KA.BunnyHop, KA_BhopSpeed=KA.BhopSpeed,
		-- World / character
		WC_FullBright=WC.FullBright, WC_FogRemove=WC.FogRemove,
		WC_TimeFreeze=WC.TimeFreeze, WC_FrozenTime=WC.FrozenTime,
		WC_JumpPower=WC.JumpPower, WC_JumpVal=WC.JumpVal,
		WC_HipHeight=WC.HipHeight, WC_HipVal=WC.HipVal,
		WC_HideChar=WC.HideChar, WC_Transparent=WC.Transparent, WC_TransAmt=WC.TransAmt,
		WC_CustomAmb=WC.CustomAmb, WC_AmbR=WC.AmbR, WC_AmbG=WC.AmbG, WC_AmbB=WC.AmbB,
		WC_CustomBright=WC.CustomBright, WC_BrightVal=WC.BrightVal,
		WC_SkyboxId=WC.SkyboxId,
		-- Accent
		AC_r=AC.r, AC_g=AC.g, AC_b=AC.b,
		-- Keybinds
		TOGGLE_KEY=TOGGLE_KEY, EXPLORER_KEY=EXPLORER_KEY,
		-- Display
		showWM=showWM, showSB=showSB,
	})
end

local function desrCfg(jsonStr)
	local ok, t = pcall(function() return JSON.decode(jsonStr) end)
	if not ok or type(t) ~= "table" then return false, "Invalid JSON" end
	if t.ver ~= "sw009" and t.ver ~= "sw008" then
		return false, "Wrong version: "..tostring(t.ver)
	end

	-- Helper that copies value if present in config
	local function set(target, key, cfgKey)
		if t[cfgKey] ~= nil then target[key] = t[cfgKey] end
	end

	-- Aimbot
	set(AB,"On","AB_On"); set(AB,"FOVOn","AB_FOVOn"); set(AB,"FOVSize","AB_FOVSize")
	set(AB,"Smooth","AB_Smooth"); set(AB,"SF","AB_SF")
	set(AB,"WallBang","AB_WallBang"); set(AB,"TeamCheck","AB_TeamCheck")
	set(AB,"HoldFire","AB_HoldFire"); set(AB,"KeyMode","AB_KeyMode")
	-- Rage
	set(RG,"On","RG_On"); set(RG,"SpamDelay","RG_SpamDelay")
	set(RG,"AutoSwitch","RG_AutoSwitch"); set(RG,"BehindDist","RG_BehindDist")
	set(RG,"TeamCheck","RG_TeamCheck"); set(RG,"CamMode","RG_CamMode")
	set(RG,"LookDown","RG_LookDown"); set(RG,"LookDownAngle","RG_LookDownAngle")
	set(RG,"Invisible","RG_Invisible"); set(RG,"SpeedBoost","RG_SpeedBoost")
	set(RG,"SpeedBoostVal","RG_SpeedBoostVal")
	set(RG,"HoldClick","RG_HoldClick"); set(RG,"KeyMode","RG_KeyMode")
	-- Movement
	set(MV,"Spinbot","MV_Spinbot"); set(MV,"SpinSpeed","MV_SpinSpeed")
	set(MV,"InfJump","MV_InfJump"); set(MV,"Speed","MV_Speed"); set(MV,"SpeedVal","MV_SpeedVal")
	set(MV,"Fly","MV_Fly"); set(MV,"FlySpeed","MV_FlySpeed")
	set(MV,"Noclip","MV_Noclip"); set(MV,"NoFall","MV_NoFall")
	set(MV,"LowGrav","MV_LowGrav"); set(MV,"GravVal","MV_GravVal")
	-- Visuals
	set(VS,"Boxes","VS_Boxes"); set(VS,"Names","VS_Names"); set(VS,"Health","VS_Health")
	set(VS,"Dist","VS_Dist"); set(VS,"HeadDot","VS_HeadDot")
	set(VS,"Chams","VS_Chams"); set(VS,"Tracers","VS_Tracers")
	set(EC.Box,"r","EC_BoxR");    set(EC.Box,"g","EC_BoxG");    set(EC.Box,"b","EC_BoxB")
	set(EC.Chams,"r","EC_ChamsR");set(EC.Chams,"g","EC_ChamsG");set(EC.Chams,"b","EC_ChamsB")
	set(EC.Tracer,"r","EC_TraceR");set(EC.Tracer,"g","EC_TraceG");set(EC.Tracer,"b","EC_TraceB")
	-- Kill aura
	set(KA,"KillAura","KA_KillAura"); set(KA,"KAR","KA_KAR")
	set(KA,"AntiKB","KA_AntiKB"); set(KA,"BunnyHop","KA_BunnyHop"); set(KA,"BhopSpeed","KA_BhopSpeed")
	-- World
	set(WC,"FullBright","WC_FullBright"); set(WC,"FogRemove","WC_FogRemove")
	set(WC,"TimeFreeze","WC_TimeFreeze"); set(WC,"FrozenTime","WC_FrozenTime")
	set(WC,"JumpPower","WC_JumpPower"); set(WC,"JumpVal","WC_JumpVal")
	set(WC,"HipHeight","WC_HipHeight"); set(WC,"HipVal","WC_HipVal")
	set(WC,"HideChar","WC_HideChar"); set(WC,"Transparent","WC_Transparent"); set(WC,"TransAmt","WC_TransAmt")
	set(WC,"CustomAmb","WC_CustomAmb"); set(WC,"AmbR","WC_AmbR")
	set(WC,"AmbG","WC_AmbG"); set(WC,"AmbB","WC_AmbB")
	set(WC,"CustomBright","WC_CustomBright"); set(WC,"BrightVal","WC_BrightVal")
	set(WC,"SkyboxId","WC_SkyboxId")
	-- Accent
	if t.AC_r then
		AC.r = math.clamp(math.floor(t.AC_r+0.5),0,255)
		AC.g = math.clamp(math.floor(t.AC_g+0.5),0,255)
		AC.b = math.clamp(math.floor(t.AC_b+0.5),0,255)
	end
	-- Keybinds
	if t.TOGGLE_KEY   then TOGGLE_KEY   = t.TOGGLE_KEY end
	if t.EXPLORER_KEY then EXPLORER_KEY = t.EXPLORER_KEY end
	-- Display
	if t.showWM ~= nil then showWM = t.showWM; WM.Visible = showWM end
	if t.showSB ~= nil then showSB = t.showSB; SBar.Visible = showSB end

	-- Apply accent color updates (calls onAC defined below)
	if onAC then onAC() end

	-- Run every registered refresher to sync UI to new state
	for _,fn in ipairs(_refreshers) do pcall(fn) end

	return true, "OK"
end
TB(SP,"Create Config",8,538,140,16,acMd(),function()
	cfgIO.Text=serCfg(); cfgSt.Text="Config generated — copy the text above"; cfgSt.TextColor3=C.EN
end)
TB(SP,"Load Config",154,538,140,16,acMd(),function()
	local txt=cfgIO.Text:gsub("^%s+",""):gsub("%s+$","")
	if txt=="" then cfgSt.Text="Paste a config first"; cfgSt.TextColor3=C.DIS; return end
	local ok,msg=desrCfg(txt)
	cfgSt.Text=ok and "Config loaded!" or "Error: "..msg; cfgSt.TextColor3=ok and C.EN or C.DIS
end)
Sp(SP,562)
L(SP,"[ Screenshot Proof ]",8,568,300,14,H,11); Sp(SP,584)
L(SP,"Press PrintScreen → all GUIs hide for 3 seconds.",8,590,400,11,C.TDIM,9)
local SSPT={}
Tg(SP,"Screenshot Proof (PrtSc key)",8,602,SSPT,"on")
UserInputService.InputBegan:Connect(function(inp,gpe)
	if not SSPT.on then return end
	if inp.KeyCode==Enum.KeyCode.Print or inp.KeyCode==Enum.KeyCode.F12 then
		SG.Enabled=false; FOVSG.Enabled=false
		if TrGUI then TrGUI.Enabled=false end
		if XHSG then pcall(function() XHSG.Enabled=false end) end
		task.delay(3, function()
			FOVSG.Enabled=true
			if TrGUI then TrGUI.Enabled=true end
			if XHSG then pcall(function() XHSG.Enabled=true end) end
		end)
	end
end)
Sp(SP,626)
L(SP,"[ Keybinds — Customizable ]",8,632,300,14,H,11); Sp(SP,648)
L(SP,"Toggle Panel:",     8,656,90,14,C.TDIM,10)
local KEY_OPTS = {
	"RightShift","LeftShift","RightControl","LeftControl","LeftAlt","RightAlt",
	"Insert","Home","End","Delete","PageUp","PageDown",
	"F1","F2","F3","F4","F5","F6","F7","F8","F9","F10","F11","F12",
	"Tab","CapsLock","Backquote","Backslash","Semicolon","Quote",
	"Z","X","C","V","B","N","M","K","L","P","O","Y","U",
}
local _tk={key=TOGGLE_KEY}
DD(SP, 102, 656, KEY_OPTS, _tk, "key", function(v) TOGGLE_KEY = v end)
L(SP,"Explorer:",         8,678,90,14,C.TDIM,10)
local _ek={key=EXPLORER_KEY}
DD(SP, 102, 678, KEY_OPTS, _ek, "key", function(v) EXPLORER_KEY = v end)
L(SP,"Minimize:      _ button (in title bar)",8,700,380,14,C.TDIM,10)
L(SP,"ESP Toggle:    T key",            8,718,380,14,C.TDIM,10)
L(SP,"Screenshot:    PrtSc (hides 3s)", 8,736,380,14,C.TDIM,10)

-- ================================================
--  ABOUT SUB-PAGE  (inside Settings, scrollable)
-- ================================================
local ABT_outer=spPages["About"]
local ABT=Instance.new("ScrollingFrame")
ABT.Size=UDim2.new(1,0,1,0); ABT.CanvasSize=UDim2.new(1,0,0,1200)
ABT.BackgroundTransparency=1; ABT.BorderSizePixel=0
ABT.ScrollBarThickness=4; ABT.ScrollBarImageColor3=ac()
ABT.ScrollingDirection=Enum.ScrollingDirection.Y
ABT.ZIndex=5; ABT.Parent=ABT_outer
regC(ABT,"ScrollBarImageColor3","ac")

local AINFO = {
	"  scopeware  V 0.0.9",
	"  discord.gg/aDwUyMBc9d",
	"  Key: gzuf86GOIGugtz56678t6ff6FF7GZi678585967gg7rfhih8t",
	"","  =======================================",
	"  [ V 0.0.9 — Current ]",
	"  =======================================",
	"  + ScopeWare Explorer (RightControl key)",
	"  + ESP Preview on local avatar",
	"  + Customizable toggle/explorer keys",
	"  + Settings page is now scrollable",
	"  + Config system fully functional",
	"  + Configs sync UI on load (refreshers)",
	"  + Config saves toggle keys + display state",
	"  + JSON parser rebuilt (handles nested)",
	"  + Skybox actually verifies asset exists",
	"  + Skybox preset IDs replaced with working ones",
	"  + Panic button — kill all hacks instantly",
	"","  =======================================",
	"  [ V 0.0.8 ]",
	"  =======================================",
	"  + Misc sub-tabs: Misc | Script Hub",
	"  + Script Hub: IY, DEX, Econ, KiciaHook",
	"  + Drag rebuilt: per-element, screen-clamped",
	"  + About moved to its own scrollable tab",
	"  + Auto Aim: Camera/Mouse/Both modes",
	"  + Aimbot sub-tabs: Aimbot/Auto Aim/FOV",
	"  + Screenshot Proof (PrtSc hides all 3s)",
	"  + Panel resize (300-600 x 400-800)",
	"  + Accent colour updates all backgrounds",
	"  + UICorners on all elements",
	"  + Modern animations & hover effects",
	"  + Fixed drag system",
	"  + Animated open/close",
	"","  =======================================",
	"  [ V 0.0.7 ]",
	"  =======================================",
	"  + Loading bar in Output",
	"  + New single-key system (Discord key)",
	"  + Config create/load system",
	"  + Ragebot: CamBehind, team check,",
	"    hold click, speed boost, FOV fix",
	"  + Aimbot: hold fire, keybind selector,",
	"    wallbang, smooth aim",
	"  + ESP T-key toggle",
	"  + Skybox presets + custom ID (fixed)",
	"  + Arm position offset",
	"  + Morph rewritten (offline support)",
	"  + All drag elements movable",
	"  + FOV circle in own ScreenGui",
	"","  =======================================",
	"  [ Supported Executors ]",
	"  =======================================",
	"  Synapse X, KRNL, Fluxus, Solara,",
	"  Evon, Hydrogen, Delta, Codex,",
	"  and most with HTTP request support.",
	"","  =======================================",
	"  [ Legal ]",
	"  =======================================",
	"  scopeware is for educational use only.",
	"  Use only where scripts are permitted.",
}
local aY=8
for _,line in ipairs(AINFO) do
	local lbl=Instance.new("TextLabel"); lbl.Size=UDim2.new(1,-16,0,13)
	lbl.Position=UDim2.fromOffset(8,aY); lbl.BackgroundTransparency=1
	lbl.Text=line
	lbl.TextColor3=line:find("=") and ac2() or (line:find("%[ V") and H or C.TDIM)
	lbl.Font=Enum.Font.Code; lbl.TextSize=9
	lbl.TextXAlignment=Enum.TextXAlignment.Left; lbl.ZIndex=7; lbl.Parent=ABT
	aY=aY+13
end

return SPg
end -- end _buildSettings

-- Build Settings page (returns SPg outer frame for use in pageMap)
local SPg = _buildSettings()

-- ================================================
--  TAB SWITCHING  (with slide animation)
-- ================================================
local pageMap={
	["Aimbot"]=AP,["Visuals"]=VP,["Misc"]=MP,["Rage"]=RP,
	["Legit"]=LGP,["Movement"]=MVPg,["World/Char"]=WPg,["Settings"]=SPg
}

local function switchTab(name)
	curTab=name
	for n,b in pairs(topBtns) do
		tween(b,{BackgroundColor3=(n==name) and ac() or acDp()},TI_FAST)
	end
	for n,p in pairs(pageMap) do
		if n==name then
			-- Slide in from right for a subtle animation
			p.Visible=true
			p.Position=UDim2.fromOffset(20,0)
			tween(p,{Position=UDim2.fromOffset(0,0)},TI_FAST)
		else
			p.Visible=false
		end
	end
end
for n,b in pairs(topBtns) do b.MouseButton1Click:Connect(function() switchTab(n) end) end
switchTab("Aimbot")

-- ================================================
--  INSERT TOGGLE  (animated open/close)
-- ================================================
UserInputService.InputBegan:Connect(function(inp,gpe)
	if gpe then return end
	-- Resolve TOGGLE_KEY name to KeyCode at runtime so the user can change it
	local kc = Enum.KeyCode[TOGGLE_KEY] or Enum.KeyCode.RightShift
	if inp.KeyCode == kc then
		if SG.Enabled then
			tween(MF,{Size=UDim2.fromOffset(MF.AbsoluteSize.X,0)},TI_CLOSE)
			task.delay(0.22,function()
				SG.Enabled=false
				MF.Size=UDim2.fromOffset(420,PH)
			end)
		else
			SG.Enabled=true
			local targetH=minState and 28 or PH
			MF.Size=UDim2.fromOffset(420,0)
			tween(MF,{Size=UDim2.fromOffset(420,targetH)},TI_SPRING)
			UserInputService.MouseBehavior=Enum.MouseBehavior.Default
		end
	end
end)

end -- end _buildGUI

-- ================================================
--  KEY SYSTEM  V2
-- ================================================
local REAL_KEY = "gzuf86GOIGugtz56678t6ff6FF7GZi678585967gg7rfhih8t"
local function keyOK2(s) return s:gsub("^%s+",""):gsub("%s+$","") == REAL_KEY end

_buildGUI()

-- ================================================
--  SCOPEWARE EXPLORER
--  Quick-access mini panel — toggles main panel, watermark,
--  status bar, ESP preview on local avatar, and more.
-- ================================================
EXP_SG = Instance.new("ScreenGui")
EXP_SG.Name = "scopewareExplorer"; EXP_SG.ResetOnSpawn = false
EXP_SG.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
EXP_SG.IgnoreGuiInset = true; EXP_SG.Enabled = false
EXP_SG.Parent = PG

EXP = Instance.new("Frame")
EXP.Size = UDim2.fromOffset(260, 480)
EXP.Position = UDim2.fromOffset(20, 80)
EXP.BackgroundColor3 = rgb(10,10,14)
EXP.BorderSizePixel = 0; EXP.ZIndex = 2; EXP.Parent = EXP_SG
corner(EXP, 10)
local expStroke = Instance.new("UIStroke", EXP)
expStroke.Color = ac(); expStroke.Thickness = 1.5
table.insert(_acReg, {expStroke, "Color", "ac"})

-- Title bar
local EXPbar = Instance.new("Frame")
EXPbar.Size = UDim2.new(1,0,0,26); EXPbar.BackgroundColor3 = acDk()
EXPbar.BorderSizePixel = 0; EXPbar.ZIndex = 3; EXPbar.Parent = EXP
corner(EXPbar, 10)
table.insert(_acReg, {EXPbar, "BackgroundColor3", "dk"})
local expBarFix = Instance.new("Frame", EXPbar)
expBarFix.Size = UDim2.new(1,0,0.5,0); expBarFix.Position = UDim2.new(0,0,0.5,0)
expBarFix.BackgroundColor3 = acDk(); expBarFix.BorderSizePixel = 0
table.insert(_acReg, {expBarFix, "BackgroundColor3", "dk"})

local EXPtitle = Instance.new("TextLabel", EXPbar)
EXPtitle.Size = UDim2.new(1,-30,1,0); EXPtitle.Position = UDim2.fromOffset(8,0)
EXPtitle.BackgroundTransparency = 1
EXPtitle.Text = "*  ScopeWare Explorer"
EXPtitle.TextColor3 = ac2(); EXPtitle.Font = Enum.Font.GothamBold
EXPtitle.TextSize = 11; EXPtitle.TextXAlignment = Enum.TextXAlignment.Left
EXPtitle.ZIndex = 4
table.insert(_acReg, {EXPtitle, "TextColor3", "ac2"})

-- Close button
local expCloseBtn = Instance.new("TextButton", EXPbar)
expCloseBtn.Size = UDim2.fromOffset(20, 16)
expCloseBtn.AnchorPoint = Vector2.new(1, 0.5)
expCloseBtn.Position = UDim2.new(1, -4, 0.5, 0)
expCloseBtn.BackgroundColor3 = rgb(200,40,60)
expCloseBtn.BorderSizePixel = 0; expCloseBtn.Text = "X"
expCloseBtn.TextColor3 = rgb(255,255,255); expCloseBtn.Font = Enum.Font.GothamBold
expCloseBtn.TextSize = 10; expCloseBtn.ZIndex = 5
corner(expCloseBtn, 4)
expCloseBtn.MouseButton1Click:Connect(function() EXP_SG.Enabled = false end)

-- Drag the explorer by its title bar
makeDraggable(EXPbar, EXP)

-- Accent line under bar
local expAccLine = Instance.new("Frame", EXP)
expAccLine.Size = UDim2.new(1,0,0,1); expAccLine.Position = UDim2.fromOffset(0,26)
expAccLine.BackgroundColor3 = ac(); expAccLine.BorderSizePixel = 0; expAccLine.ZIndex = 3
table.insert(_acReg, {expAccLine, "BackgroundColor3", "ac"})

-- Content area (scrollable in case more options get added)
local expContent = Instance.new("ScrollingFrame", EXP)
expContent.Size = UDim2.new(1,-4,1,-30); expContent.Position = UDim2.fromOffset(2,28)
expContent.BackgroundTransparency = 1; expContent.BorderSizePixel = 0
expContent.ScrollBarThickness = 3; expContent.ScrollBarImageColor3 = ac()
expContent.CanvasSize = UDim2.new(0,0,0,360)
expContent.ZIndex = 3
table.insert(_acReg, {expContent, "ScrollBarImageColor3", "ac"})

-- Lightweight row helper for the explorer
local function expRow(label, y, getState, setState)
	local row = Instance.new("Frame", expContent)
	row.Size = UDim2.new(1,-8,0,22); row.Position = UDim2.fromOffset(4,y)
	row.BackgroundColor3 = acDp(); row.BorderSizePixel = 0; row.ZIndex = 4
	corner(row, 5)
	table.insert(_acReg, {row, "BackgroundColor3", "dp"})

	local lbl = Instance.new("TextLabel", row)
	lbl.Size = UDim2.new(1,-44,1,0); lbl.Position = UDim2.fromOffset(8,0)
	lbl.BackgroundTransparency = 1; lbl.Text = label
	lbl.TextColor3 = rgb(220,210,255); lbl.Font = Enum.Font.Code
	lbl.TextSize = 10; lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.ZIndex = 5

	local pill = Instance.new("TextButton", row)
	pill.AnchorPoint = Vector2.new(1, 0.5)
	pill.Position = UDim2.new(1, -4, 0.5, 0)
	pill.Size = UDim2.fromOffset(34, 16)
	pill.BackgroundColor3 = getState() and ac() or rgb(60,60,80)
	pill.BorderSizePixel = 0; pill.Text = getState() and "ON" or "OFF"
	pill.TextColor3 = rgb(255,255,255); pill.Font = Enum.Font.GothamBold
	pill.TextSize = 9; pill.ZIndex = 5
	corner(pill, 8)

	local function refresh()
		local s = getState()
		pill.BackgroundColor3 = s and ac() or rgb(60,60,80)
		pill.Text = s and "ON" or "OFF"
	end
	pill.MouseButton1Click:Connect(function()
		setState(not getState()); refresh()
	end)
	-- Hover: row brightens
	pill.MouseEnter:Connect(function()
		tween(row, {BackgroundColor3 = acFt()}, TI_FAST)
	end)
	pill.MouseLeave:Connect(function()
		tween(row, {BackgroundColor3 = acDp()}, TI_FAST)
	end)
	-- Also expose refresh so external state changes reflect in pill
	return refresh
end

-- Build rows
local expRefreshers = {}
local _y = 6

table.insert(expRefreshers, expRow("Main Panel", _y,
	function() return SG.Enabled end,
	function(v) SG.Enabled = v
		if v then UserInputService.MouseBehavior = Enum.MouseBehavior.Default end
	end)); _y = _y + 26

table.insert(expRefreshers, expRow("Watermark", _y,
	function() return showWM end,
	function(v) showWM = v; WM.Visible = v end)); _y = _y + 26

table.insert(expRefreshers, expRow("Status Bar", _y,
	function() return showSB end,
	function(v) showSB = v; SBar.Visible = v end)); _y = _y + 26

table.insert(expRefreshers, expRow("Profile Card", _y,
	function() return PF.Visible end,
	function(v) PF.Visible = v; PNL.Visible = v end)); _y = _y + 26

table.insert(expRefreshers, expRow("FOV Circle", _y,
	function() return FOVSG.Enabled end,
	function(v) FOVSG.Enabled = v end)); _y = _y + 26

table.insert(expRefreshers, expRow("Tracers GUI", _y,
	function() return TrGUI.Enabled end,
	function(v) TrGUI.Enabled = v end)); _y = _y + 26

table.insert(expRefreshers, expRow("Crosshair GUI", _y,
	function() return XHSG and XHSG.Enabled end,
	function(v) if XHSG then XHSG.Enabled = v end end)); _y = _y + 26

-- ESP Preview row (highlighted differently)
local previewSep = Instance.new("Frame", expContent)
previewSep.Size = UDim2.new(1,-8,0,1); previewSep.Position = UDim2.fromOffset(4,_y+2)
previewSep.BackgroundColor3 = ac(); previewSep.BorderSizePixel = 0; previewSep.ZIndex = 4
table.insert(_acReg, {previewSep, "BackgroundColor3", "ac"})
_y = _y + 8

local expHdr = Instance.new("TextLabel", expContent)
expHdr.Size = UDim2.new(1,-8,0,16); expHdr.Position = UDim2.fromOffset(8,_y)
expHdr.BackgroundTransparency = 1; expHdr.Text = "[ ESP Preview ]"
expHdr.TextColor3 = ac2(); expHdr.Font = Enum.Font.GothamBold
expHdr.TextSize = 10; expHdr.TextXAlignment = Enum.TextXAlignment.Left
expHdr.ZIndex = 5
table.insert(_acReg, {expHdr, "TextColor3", "ac2"})
_y = _y + 18

local expDesc = Instance.new("TextLabel", expContent)
expDesc.Size = UDim2.new(1,-12,0,12); expDesc.Position = UDim2.fromOffset(8,_y)
expDesc.BackgroundTransparency = 1
expDesc.Text = "Live preview of your ESP settings:"
expDesc.TextColor3 = rgb(140,130,180); expDesc.Font = Enum.Font.Code
expDesc.TextSize = 9; expDesc.TextXAlignment = Enum.TextXAlignment.Left
expDesc.ZIndex = 5
_y = _y + 14

-- --- Viewport preview ---------------------------------------
-- Frame holds the viewport + ESP overlay drawn on top
local previewBox = Instance.new("Frame", expContent)
previewBox.Size = UDim2.new(1,-8,0,160)
previewBox.Position = UDim2.fromOffset(4,_y)
previewBox.BackgroundColor3 = rgb(20, 18, 30)
previewBox.BorderSizePixel = 0; previewBox.ZIndex = 4
previewBox.ClipsDescendants = true
corner(previewBox, 6)
local previewStroke = Instance.new("UIStroke", previewBox)
previewStroke.Color = ac(); previewStroke.Thickness = 1
table.insert(_acReg, {previewStroke, "Color", "ac"})

-- ViewportFrame renders the player's character
local previewVP = Instance.new("ViewportFrame", previewBox)
previewVP.Size = UDim2.new(1,0,1,0)
previewVP.BackgroundColor3 = rgb(30, 25, 50)
previewVP.BorderSizePixel = 0
previewVP.ZIndex = 4
corner(previewVP, 6)

-- Camera for the viewport
local vpCam = Instance.new("Camera")
vpCam.FieldOfView = 50
vpCam.Parent = previewVP
previewVP.CurrentCamera = vpCam

-- Box overlay (draws on top of viewport, simulates ESP box)
local boxOverlay = Instance.new("Frame", previewBox)
boxOverlay.BackgroundTransparency = 1
boxOverlay.BorderSizePixel = 2
boxOverlay.BorderColor3 = rgb(EC.Box.r, EC.Box.g, EC.Box.b)
-- Will be sized by clone position; default centered
boxOverlay.AnchorPoint = Vector2.new(0.5, 0.5)
boxOverlay.Position = UDim2.new(0.5, 0, 0.5, 0)
boxOverlay.Size = UDim2.fromOffset(60, 130)
boxOverlay.ZIndex = 6

-- Name label above box
local nameOverlay = Instance.new("TextLabel", previewBox)
nameOverlay.Size = UDim2.fromOffset(120, 14)
nameOverlay.AnchorPoint = Vector2.new(0.5, 1)
nameOverlay.Position = UDim2.new(0.5, 0, 0.5, -65)
nameOverlay.BackgroundTransparency = 1
nameOverlay.Text = LP.DisplayName or LP.Name
nameOverlay.TextColor3 = rgb(220, 210, 255)
nameOverlay.Font = Enum.Font.Code; nameOverlay.TextSize = 11
nameOverlay.TextStrokeTransparency = 0.4; nameOverlay.ZIndex = 7

-- HP label below box
local hpOverlay = Instance.new("TextLabel", previewBox)
hpOverlay.Size = UDim2.fromOffset(120, 12)
hpOverlay.AnchorPoint = Vector2.new(0.5, 0)
hpOverlay.Position = UDim2.new(0.5, 0, 0.5, 65)
hpOverlay.BackgroundTransparency = 1
hpOverlay.Text = "HP 100/100"
hpOverlay.TextColor3 = rgb(50, 220, 80)
hpOverlay.Font = Enum.Font.Code; hpOverlay.TextSize = 10
hpOverlay.TextStrokeTransparency = 0.4; hpOverlay.ZIndex = 7

-- Head dot
local dotOverlay = Instance.new("Frame", previewBox)
dotOverlay.Size = UDim2.fromOffset(6, 6)
dotOverlay.AnchorPoint = Vector2.new(0.5, 0.5)
dotOverlay.Position = UDim2.new(0.5, 0, 0.5, -50)
dotOverlay.BackgroundColor3 = rgb(255, 60, 60)
dotOverlay.BorderSizePixel = 0; dotOverlay.ZIndex = 7
corner(dotOverlay, 3)

-- Highlight on the cloned avatar (for chams preview)
-- ViewportFrame doesn't render Highlights — we simulate by applying
-- a tinted overlay frame on top of the avatar area
local chamsOverlay = Instance.new("Frame", previewBox)
chamsOverlay.AnchorPoint = Vector2.new(0.5, 0.5)
chamsOverlay.Position = UDim2.new(0.5, 0, 0.5, 0)
chamsOverlay.Size = UDim2.fromOffset(60, 130)
chamsOverlay.BackgroundColor3 = rgb(EC.Chams.r, EC.Chams.g, EC.Chams.b)
chamsOverlay.BackgroundTransparency = 0.65
chamsOverlay.BorderSizePixel = 0; chamsOverlay.ZIndex = 5

-- Build a lightweight clone of the local character for the viewport
local previewModel = nil
local function rebuildPreviewModel()
	if previewModel then previewModel:Destroy(); previewModel = nil end
	local char = LP.Character; if not char then return end
	-- Wait briefly for char to load fully on first call
	if not char:FindFirstChild("HumanoidRootPart") then return end
	-- Clone, strip scripts (some games' chars contain LocalScripts)
	previewModel = char:Clone()
	for _,d in ipairs(previewModel:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") then d:Destroy() end
		if d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false end
	end
	previewModel.Parent = previewVP
	-- Position camera to look at the character
	local hrp = previewModel:FindFirstChild("HumanoidRootPart")
	if hrp then
		local p = hrp.Position
		vpCam.CFrame = CFrame.new(p + Vector3.new(0, 1, 6), p + Vector3.new(0, 1, 0))
	end
end

-- Update overlay visibility from current ESP toggles
local function refreshPreviewOverlays()
	-- Determine effective accent for player (team-color aware)
	local pCol = rgb(EC.Chams.r, EC.Chams.g, EC.Chams.b)
	local boxC = rgb(EC.Box.r, EC.Box.g, EC.Box.b)

	-- Box
	boxOverlay.Visible      = VS.Boxes
	boxOverlay.BorderColor3 = boxC

	-- Name (uses team color if enabled, else default text color)
	nameOverlay.Visible = VS.Names
	nameOverlay.TextColor3 = VS.TeamColor and pCol or rgb(220, 210, 255)

	-- HP
	hpOverlay.Visible = VS.Health
	hpOverlay.Text = "HP 100/100"  -- preview always shows full HP

	-- Head dot
	dotOverlay.Visible = VS.HeadDot

	-- Chams (with mode)
	if VS.Chams then
		chamsOverlay.Visible = true
		if VS.ChamsMode == "Outline" then
			chamsOverlay.BackgroundTransparency = 1
		elseif VS.ChamsMode == "Glow" then
			chamsOverlay.BackgroundColor3 = pCol
			chamsOverlay.BackgroundTransparency = 0.45
		else  -- Solid
			chamsOverlay.BackgroundColor3 = pCol
			chamsOverlay.BackgroundTransparency = 0.65
		end
	else
		chamsOverlay.Visible = false
	end
end

-- Render preview every frame so it tracks settings changes live
RunService.Heartbeat:Connect(function()
	if EXP_SG and EXP_SG.Enabled then refreshPreviewOverlays() end
end)

-- Initial build (deferred so character has time to spawn)
task.spawn(function()
	for _ = 1, 50 do
		if LP.Character and LP.Character:FindFirstChild("HumanoidRootPart") then break end
		task.wait(0.2)
	end
	rebuildPreviewModel()
	refreshPreviewOverlays()
end)

-- Slow-rotate the preview camera around the avatar so the model looks alive
local _vpAngle = 0
RunService.RenderStepped:Connect(function(dt)
	if not EXP_SG.Enabled then return end
	if not previewModel then return end
	local hrp = previewModel:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	_vpAngle = (_vpAngle + dt * 0.3) % (math.pi * 2)
	local p = hrp.Position
	local r = 6
	vpCam.CFrame = CFrame.new(
		p + Vector3.new(math.cos(_vpAngle) * r, 1, math.sin(_vpAngle) * r),
		p + Vector3.new(0, 1, 0)
	)
	refreshPreviewOverlays()
end)

-- Rebuild on respawn
LP.CharacterAdded:Connect(function()
	task.wait(1.5); rebuildPreviewModel(); refreshPreviewOverlays()
end)

_y = _y + 166

-- Rebuild button (in case viewport breaks or user changes outfit)
local rebuildBtn = Instance.new("TextButton", expContent)
rebuildBtn.Size = UDim2.new(1, -8, 0, 18); rebuildBtn.Position = UDim2.fromOffset(4, _y)
rebuildBtn.BackgroundColor3 = acMd(); rebuildBtn.BorderSizePixel = 0
rebuildBtn.Text = "~ Rebuild Preview"
rebuildBtn.TextColor3 = rgb(255,255,255); rebuildBtn.Font = Enum.Font.Code
rebuildBtn.TextSize = 9; rebuildBtn.ZIndex = 5
corner(rebuildBtn, 4)
table.insert(_acReg, {rebuildBtn, "BackgroundColor3", "md"})
rebuildBtn.MouseButton1Click:Connect(function()
	rebuildPreviewModel(); refreshPreviewOverlays()
end)
_y = _y + 22

-- Quick action row: kill all toggleable hacks
local panicSep = Instance.new("Frame", expContent)
panicSep.Size = UDim2.new(1,-8,0,1); panicSep.Position = UDim2.fromOffset(4,_y+2)
panicSep.BackgroundColor3 = ac(); panicSep.BorderSizePixel = 0; panicSep.ZIndex = 4
table.insert(_acReg, {panicSep, "BackgroundColor3", "ac"})
_y = _y + 8

local panicBtn = Instance.new("TextButton", expContent)
panicBtn.Size = UDim2.new(1,-8,0,22); panicBtn.Position = UDim2.fromOffset(4,_y)
panicBtn.BackgroundColor3 = rgb(180,30,50); panicBtn.BorderSizePixel = 0
panicBtn.Text = "! PANIC — Disable Everything"
panicBtn.TextColor3 = rgb(255,255,255); panicBtn.Font = Enum.Font.GothamBold
panicBtn.TextSize = 10; panicBtn.ZIndex = 5
corner(panicBtn, 5)
panicBtn.MouseEnter:Connect(function() tween(panicBtn,{BackgroundColor3=rgb(220,60,80)},TI_FAST) end)
panicBtn.MouseLeave:Connect(function() tween(panicBtn,{BackgroundColor3=rgb(180,30,50)},TI_FAST) end)
panicBtn.MouseButton1Click:Connect(function()
	-- Turn off every dangerous toggle in one click
	AB.On=false; RG.On=false
	MV.Spinbot=false; MV.Fly=false; MV.Speed=false; MV.Noclip=false; MV.InfJump=false
	VS.Boxes=false; VS.Names=false; VS.Health=false; VS.Chams=false; VS.Tracers=false
	WC.FullBright=false; WC.FogRemove=false; WC.HideChar=false; WC.Transparent=false
	KA.KillAura=false; KA.AntiKB=false; KA.BunnyHop=false
	for _,p in ipairs(Players:GetPlayers()) do espDel(p) end
	for _,r in ipairs(_refreshers)    do pcall(r) end
	for _,r in ipairs(expRefreshers) do pcall(r) end
end)
_y = _y + 26

-- Update canvas to actual content height
expContent.CanvasSize = UDim2.new(0,0,0,_y+10)

-- Toggle Explorer with EXPLORER_KEY
UserInputService.InputBegan:Connect(function(inp,gpe)
	if gpe then return end
	local kc = Enum.KeyCode[EXPLORER_KEY] or Enum.KeyCode.RightControl
	if inp.KeyCode == kc then
		EXP_SG.Enabled = not EXP_SG.Enabled
		if EXP_SG.Enabled then
			-- Refresh pill states whenever opened
			for _,r in ipairs(expRefreshers) do pcall(r) end
		end
	end
end)


if _G.sw_verified then
	SG.Enabled=true
else
	local KG=Instance.new("ScreenGui"); KG.Name="swKey"; KG.ResetOnSpawn=false
	KG.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; KG.IgnoreGuiInset=true; KG.Parent=PG

	local ov=Instance.new("Frame"); ov.Size=UDim2.new(1,0,1,0)
	ov.BackgroundColor3=rgb(0,0,0); ov.BackgroundTransparency=0.45
	ov.BorderSizePixel=0; ov.ZIndex=1; ov.Parent=KG

	local KW=Instance.new("Frame"); KW.Size=UDim2.fromOffset(420,300)
	-- No anchor point — drag system expects top-left positioning
	KW.Position=UDim2.new(0.5,-210,0.5,-150)
	KW.BackgroundColor3=rgb(10,10,14); KW.BorderSizePixel=0; KW.ZIndex=2; KW.Parent=KG
	corner(KW,12)

	local kStroke=Instance.new("UIStroke",KW); kStroke.Color=ac(); kStroke.Thickness=2
	kStroke.ApplyStrokeMode=Enum.ApplyStrokeMode.Border

	local KBar=Instance.new("Frame"); KBar.Size=UDim2.new(1,0,0,28)
	KBar.BackgroundColor3=acDk(); KBar.BorderSizePixel=0; KBar.ZIndex=3; KBar.Parent=KW
	corner(KBar,12)
	local kBarFix=Instance.new("Frame",KBar); kBarFix.Size=UDim2.new(1,0,0.5,0)
	kBarFix.Position=UDim2.new(0,0,0.5,0); kBarFix.BackgroundColor3=acDk(); kBarFix.BorderSizePixel=0

	local KTitle=Instance.new("TextLabel"); KTitle.Size=UDim2.new(1,-8,1,0)
	KTitle.Position=UDim2.fromOffset(8,0); KTitle.BackgroundTransparency=1
	KTitle.Text="scopeware  V 0.0.9  —  Key Required"
	KTitle.TextColor3=rgb(220,210,255); KTitle.Font=Enum.Font.GothamBold; KTitle.TextSize=12
	KTitle.TextXAlignment=Enum.TextXAlignment.Left; KTitle.ZIndex=4; KTitle.Parent=KBar

	local KAl=Instance.new("Frame"); KAl.Size=UDim2.new(1,0,0,1); KAl.Position=UDim2.fromOffset(0,28)
	KAl.BackgroundColor3=ac(); KAl.BorderSizePixel=0; KAl.ZIndex=3; KAl.Parent=KW

	makeDraggable(KBar, KW)

	local function kLbl(txt,y,col,sz)
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,-16,0,18)
		l.Position=UDim2.fromOffset(8,y); l.BackgroundTransparency=1
		l.Text=txt; l.TextColor3=col or rgb(200,190,255)
		l.Font=Enum.Font.Code; l.TextSize=sz or 11
		l.TextXAlignment=Enum.TextXAlignment.Left; l.ZIndex=5; l.Parent=KW; return l
	end

	kLbl("scopeware",38,ac2(),28)
	kLbl("You need a key to use scopeware.",72,rgb(160,140,200),11)
	kLbl("Get your key from our Discord server:",90,rgb(130,110,170),10)

	local dcBox=Instance.new("TextBox"); dcBox.Size=UDim2.fromOffset(400,24)
	dcBox.Position=UDim2.fromOffset(8,108); dcBox.BackgroundColor3=rgb(8,5,20)
	dcBox.BorderSizePixel=0
	dcBox.Text="discord.gg/aDwUyMBc9d"; dcBox.TextColor3=ac2()
	dcBox.Font=Enum.Font.Code; dcBox.TextSize=13
	dcBox.TextXAlignment=Enum.TextXAlignment.Center
	dcBox.ClearTextOnFocus=false; dcBox.ZIndex=5; dcBox.Parent=KW
	corner(dcBox,6)
	local dcbS=Instance.new("UIStroke",dcBox);dcbS.Color=acFt();dcbS.Thickness=1

	kLbl("Click the link above to copy it. Then join and get the key.",136,rgb(100,85,140),9)
	kLbl("Paste your key below:",156,rgb(160,140,200),11)

	local keyIn=Instance.new("TextBox"); keyIn.Size=UDim2.fromOffset(400,28)
	keyIn.Position=UDim2.fromOffset(8,174); keyIn.BackgroundColor3=rgb(6,4,14)
	keyIn.BorderSizePixel=0
	keyIn.PlaceholderText="Paste key here..."; keyIn.PlaceholderColor3=rgb(60,45,90)
	keyIn.Text=""; keyIn.TextColor3=rgb(200,255,200)
	keyIn.Font=Enum.Font.Code; keyIn.TextSize=11
	keyIn.ClearTextOnFocus=false; keyIn.ZIndex=5; keyIn.Parent=KW
	corner(keyIn,6)
	local kinS=Instance.new("UIStroke",keyIn);kinS.Color=acFt();kinS.Thickness=1

	local kSt=Instance.new("TextLabel"); kSt.Size=UDim2.fromOffset(400,14)
	kSt.Position=UDim2.fromOffset(8,208); kSt.BackgroundTransparency=1
	kSt.Text=""; kSt.TextColor3=rgb(255,70,70); kSt.Font=Enum.Font.Code
	kSt.TextSize=10; kSt.ZIndex=5; kSt.Parent=KW

	local function shakeW()
		local op=KW.Position
		task.spawn(function()
			for _=1,4 do
				tween(KW,{Position=op+UDim2.fromOffset(8,0)},TweenInfo.new(0.03)); task.wait(0.04)
				tween(KW,{Position=op-UDim2.fromOffset(8,0)},TweenInfo.new(0.03)); task.wait(0.04)
			end
			tween(KW,{Position=op},TweenInfo.new(0.03))
		end)
	end

	local fails=0
	local function tryKey()
		local raw=keyIn.Text:gsub("^%s+",""):gsub("%s+$","")
		if raw=="" then kSt.Text="Enter your key first."; kSt.TextColor3=rgb(255,200,60); return end
		if keyOK2(raw) then
			kSt.Text="+ Key accepted — loading scopeware..."; kSt.TextColor3=rgb(90,255,120)
			_G.sw_verified=true
			tween(KW,
				{Size=UDim2.fromOffset(0,0), Position=UDim2.new(0.5,0,0.5,0)},
				TweenInfo.new(0.4,Enum.EasingStyle.Back,Enum.EasingDirection.In))
			task.delay(0.45,function() KG:Destroy(); SG.Enabled=true end)
		else
			fails+=1; kSt.TextColor3=rgb(255,70,70)
			if fails>=5 then
				kSt.Text="X Too many wrong keys. Rejoin the server."
			else
				kSt.Text=string.format("X Wrong key. (%d/5)  Check the Discord.", fails)
			end
			shakeW(); keyIn.Text=""
		end
	end

	local vBtn=Instance.new("TextButton"); vBtn.Size=UDim2.fromOffset(400,30)
	vBtn.Position=UDim2.fromOffset(8,228); vBtn.BackgroundColor3=acMd()
	vBtn.BorderSizePixel=0
	vBtn.Text="Verify Key"; vBtn.TextColor3=rgb(255,255,255)
	vBtn.Font=Enum.Font.GothamBold; vBtn.TextSize=13; vBtn.ZIndex=5; vBtn.Parent=KW
	corner(vBtn,8)
	addHover(vBtn,acMd(),ac())
	vBtn.MouseButton1Click:Connect(tryKey)
	keyIn.FocusLost:Connect(function(enter) if enter then tryKey() end end)

	-- Slide in from top
	KW.Position=UDim2.new(0.5,-210,-0.8,0)
	tween(KW,
		{Position=UDim2.new(0.5,-210,0.5,-150)},
		TweenInfo.new(0.5,Enum.EasingStyle.Back,Enum.EasingDirection.Out))
end

print("[scopeware V0.0.9 ENHANCED] Ready.  RightShift = main panel | RightControl = explorer.")

end) -- end task.spawn
