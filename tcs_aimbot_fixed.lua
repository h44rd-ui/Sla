local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local Workspace           = game:GetService("Workspace")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local UserInputService    = game:GetService("UserInputService")
local MarketplaceService  = game:GetService("MarketplaceService")
local TweenService        = game:GetService("TweenService")
local Stats               = game:GetService("Stats")
local LocalizationService = game:GetService("LocalizationService")
local TextChatService     = game:GetService("TextChatService")
local Lighting            = game:GetService("Lighting")
local HttpService         = game:GetService("HttpService")
local CoreGui             = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

local clock, clear, insert, remove = os.clock, table.clear, table.insert, table.remove
local spawn, defer, wait_ = task.spawn, task.defer, task.wait

local function try(fn, ...)
    local ok, a, b = pcall(fn, ...)
    return ok, a, b
end
local function clamp(v, lo, hi) if v < lo then return lo end; if v > hi then return hi end; return v end

local State = { Character = nil, Humanoid = nil, HRP = nil, Ready = false }
local function refreshState(char)
    char = char or LocalPlayer.Character
    State.Character = char
    State.Humanoid  = char and char:FindFirstChildOfClass("Humanoid")
    State.HRP       = char and char:FindFirstChild("HumanoidRootPart")
    State.Ready     = State.Humanoid ~= nil and State.HRP ~= nil
end

local onCharacterAdded, onCharacterRemoving = {}, {}
local function fireHandlers(list, char) for i = 1, #list do defer(list[i], char) end end

local _charGen = 0
LocalPlayer.CharacterAdded:Connect(function(c)
    _charGen += 1
    local gen = _charGen
    refreshState(c)
    c:WaitForChild("Humanoid", 15)
    c:WaitForChild("HumanoidRootPart", 15)
    if gen ~= _charGen then return end
    refreshState(c)
    fireHandlers(onCharacterAdded, c)
end)
LocalPlayer.CharacterRemoving:Connect(function(c)
    fireHandlers(onCharacterRemoving, c)
    if c == State.Character then
        State.Character, State.Humanoid, State.HRP, State.Ready = nil, nil, nil, false
    end
end)
refreshState()

local BG_ASSET   = "rbxassetid://93633918862061"
local ICON_ASSET = "rbxassetid://90533551558606"

local WindUI
do
    local src
    local ok = pcall(function()
        src = game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/refs/heads/main/dist/main.lua")
    end)
    if not ok or not src then error("[LuaTpsUltimate] Could not download WindUI") end
    local chunk, err = loadstring(src)
    if not chunk then error("[LuaTpsUltimate] WindUI loadstring failed: " .. tostring(err)) end
    WindUI = chunk()
end

local Window = WindUI:CreateWindow({
    Title = "Lua - The Classic", Icon = ICON_ASSET, Author = "Lua",
    Folder = "LuaTpsUltimate", Size = UDim2.fromOffset(580, 480),
    Transparent = true, Theme = "Dark", Background = BG_ASSET,
})

local _notifyWarned = false
local function Notify(args)
    local ok, err = pcall(function()
        local fn = Window.Notify
        if type(fn) == "function" then fn(Window, args); return end
        if type(Window.notify) == "function" then Window:notify(args) end
    end)
    if not ok and not _notifyWarned then
        _notifyWarned = true
        warn("[LuaTpsUltimate] Notify failed:", err)
    end
end

do
    local function resizeWindowIcon()
        for _, gui in ipairs(PlayerGui:GetChildren()) do
            if gui:IsA("ScreenGui") then
                for _, d in ipairs(gui:GetDescendants()) do
                    if d:IsA("ImageLabel") and d.Image == ICON_ASSET then
                        try(function()
                            d.Size = UDim2.fromOffset(32, 32)
                            d.ScaleType = Enum.ScaleType.Fit
                            d.AnchorPoint = Vector2.new(0, 0.5)
                        end)
                    end
                end
            end
        end
    end
    defer(function() for _, t in ipairs({ 0.25, 0.75, 2.0 }) do wait_(t); resizeWindowIcon() end end)
end

local MobileButtons = {
    registry = {}, order = {}, baseX = 20, baseY = 200, spacing = 68,
    refSize = Vector2.new(130, 58),
    colors = {
        offBG = Color3.fromRGB(30, 32, 46), onBG = Color3.fromRGB(35, 115, 75),
        offStroke = Color3.fromRGB(100, 100, 130), onStroke = Color3.fromRGB(80, 255, 130),
    },
}
local function getViewportSize()
    local cam = Workspace.CurrentCamera
    return cam and cam.ViewportSize or Vector2.new(1920, 1080)
end
local function getSafeTopInset() return UserInputService.TouchEnabled and 44 or 0 end
local function getButtonSize()
    local vp = getViewportSize()
    local scale = clamp(math.min(vp.X / 1280, vp.Y / 720), 0.8, 1)
    return Vector2.new(math.floor(MobileButtons.refSize.X * scale), math.floor(MobileButtons.refSize.Y * scale))
end
local function getAbsolutePos(pos, vp) return pos.X.Scale * vp.X + pos.X.Offset, pos.Y.Scale * vp.Y + pos.Y.Offset end
local function computeSlotPosition(idx, _size)
    local vp = getViewportSize()
    local yPx = vp.Y - (MobileButtons.baseY + (idx - 1) * MobileButtons.spacing)
    return UDim2.fromOffset(MobileButtons.baseX, math.max(getSafeTopInset(), yPx))
end
local function reflow()
    for i, name in ipairs(MobileButtons.order) do
        local data = MobileButtons.registry[name]
        if data and data.btn and data.btn.Parent then
            local sz = data.size or getButtonSize()
            if not data.userMoved then
                data.btn.Position = computeSlotPosition(i, sz)
            else
                local vp = getViewportSize()
                local x, y = data.btn.Position.X.Offset, data.btn.Position.Y.Offset
                data.btn.Position = UDim2.fromOffset(clamp(x, 0, vp.X - sz.X), clamp(y, getSafeTopInset(), vp.Y - sz.Y))
            end
        end
    end
end
local function disconnectAll(conns)
    if not conns then return end
    for i = #conns, 1, -1 do pcall(function() conns[i]:Disconnect() end); conns[i] = nil end
end
local function applyButtonState(data, on, onText, offText)
    if not data or not data.btn then return end
    data.label.Text = on and onText or offText
    local c = MobileButtons.colors
    TweenService:Create(data.btn,    TweenInfo.new(0.15), { BackgroundColor3 = on and c.onBG  or c.offBG   }):Play()
    TweenService:Create(data.stroke, TweenInfo.new(0.15), { Color            = on and c.onStroke or c.offStroke }):Play()
end
local function destroyMobileButton(guiName)
    local data = MobileButtons.registry[guiName]
    if data then
        disconnectAll(data.conns)
        if data.gui then data.gui:Destroy() end
        MobileButtons.registry[guiName] = nil
        local idx = table.find(MobileButtons.order, guiName)
        if idx then remove(MobileButtons.order, idx) end
    else
        local g = PlayerGui:FindFirstChild(guiName); if g then g:Destroy() end
    end
    reflow()
end
local function createMobileButton(guiName, text, onToggle)
    destroyMobileButton(guiName)
    local btnSize = getButtonSize()
    local sg = Instance.new("ScreenGui")
    sg.Name, sg.ResetOnSpawn, sg.IgnoreGuiInset = guiName, false, true
    sg.DisplayOrder, sg.ZIndexBehavior = 1000, Enum.ZIndexBehavior.Sibling
    sg.Parent = PlayerGui

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.fromOffset(btnSize.X, btnSize.Y)
    btn.BackgroundColor3 = MobileButtons.colors.offBG
    btn.BackgroundTransparency = 0.1
    btn.BorderSizePixel, btn.AutoButtonColor, btn.Text = 0, false, ""
    btn.Parent = sg

    if BG_ASSET and BG_ASSET ~= "" then
        local bg = Instance.new("ImageLabel")
        bg.Size = UDim2.fromScale(1, 1)
        bg.BackgroundTransparency, bg.Image = 1, BG_ASSET
        bg.ImageTransparency, bg.ScaleType, bg.ZIndex = 0.55, Enum.ScaleType.Crop, 0
        bg.Parent = btn
        Instance.new("UICorner", bg).CornerRadius = UDim.new(0, 12)
    end
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 12)

    local grad = Instance.new("UIGradient", btn)
    grad.Rotation = 90
    grad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(60, 65, 90)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 32, 46)),
    })
    grad.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0.35),
    })

    local stroke = Instance.new("UIStroke", btn)
    stroke.Thickness, stroke.Color, stroke.Transparency = 1.5, MobileButtons.colors.offStroke, 0.3
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

    local label = Instance.new("TextLabel", btn)
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextSize, label.Font, label.TextWrapped = 13, Enum.Font.GothamBold, true
    label.TextStrokeTransparency, label.TextStrokeColor3 = 0.5, Color3.fromRGB(0, 0, 0)
    label.ZIndex = 2
    label.Parent = btn

    local conns = {}
    local DRAG_THRESHOLD = 10
    local dragging, moved, activeInput, dragStart, startPos = false, false, nil, nil, nil

    local function add(c) conns[#conns + 1] = c end
    local function isSameGesture(input)
        if not activeInput then return false end
        if activeInput.UserInputType == Enum.UserInputType.Touch then return input == activeInput end
        if activeInput.UserInputType == Enum.UserInputType.MouseButton1 then return input.UserInputType == Enum.UserInputType.MouseMovement end
        return false
    end
    local function isGestureEnd(input)
        if not activeInput then return false end
        if activeInput.UserInputType == Enum.UserInputType.Touch then return input == activeInput end
        if activeInput.UserInputType == Enum.UserInputType.MouseButton1 then return input.UserInputType == Enum.UserInputType.MouseButton1 end
        return false
    end

    add(btn.InputBegan:Connect(function(input)
        local t = input.UserInputType
        if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
            dragging, moved, activeInput = true, false, input
            dragStart = input.Position
            local vp = getViewportSize()
            local ax, ay = getAbsolutePos(btn.Position, vp)
            startPos = Vector2.new(ax, ay)
            TweenService:Create(btn, TweenInfo.new(0.08, Enum.EasingStyle.Quad),
                { Size = UDim2.fromOffset(btnSize.X - 4, btnSize.Y - 4) }):Play()
        end
    end))

    add(UserInputService.InputChanged:Connect(function(input)
        if not dragging or not isSameGesture(input) then return end
        local delta = input.Position - dragStart
        if not moved then
            if math.abs(delta.X) > DRAG_THRESHOLD or math.abs(delta.Y) > DRAG_THRESHOLD then moved = true
            else return end
        end
        local vp = getViewportSize()
        local w, h, top = btnSize.X, btnSize.Y, getSafeTopInset()
        btn.Position = UDim2.fromOffset(
            clamp(startPos.X + delta.X, -w / 2, vp.X - w / 2),
            clamp(startPos.Y + delta.Y, top,     vp.Y - h / 2)
        )
    end))

    add(UserInputService.InputEnded:Connect(function(input)
        if not dragging or not isGestureEnd(input) then return end
        dragging, activeInput = false, nil
        TweenService:Create(btn, TweenInfo.new(0.1, Enum.EasingStyle.Quad),
            { Size = UDim2.fromOffset(btnSize.X, btnSize.Y) }):Play()
        if moved then
            local data = MobileButtons.registry[guiName]
            if data then data.userMoved = true end
        end
    end))

    add(btn.Activated:Connect(function()
        if moved then moved = false; return end
        TweenService:Create(btn, TweenInfo.new(0.06),
            { Size = UDim2.fromOffset(btnSize.X - 6, btnSize.Y - 6) }):Play()
        task.delay(0.06, function()
            if btn.Parent then
                TweenService:Create(btn, TweenInfo.new(0.1),
                    { Size = UDim2.fromOffset(btnSize.X, btnSize.Y) }):Play()
            end
        end)
        onToggle()
    end))

    add(btn.MouseEnter:Connect(function()
        TweenService:Create(btn,    TweenInfo.new(0.12), { BackgroundTransparency = 0 }):Play()
        TweenService:Create(stroke, TweenInfo.new(0.12), { Transparency = 0 }):Play()
    end))
    add(btn.MouseLeave:Connect(function()
        TweenService:Create(btn,    TweenInfo.new(0.12), { BackgroundTransparency = 0.1 }):Play()
        TweenService:Create(stroke, TweenInfo.new(0.12), { Transparency = 0.3 }):Play()
    end))

    local idx = #MobileButtons.order + 1
    MobileButtons.order[idx] = guiName
    btn.Position = computeSlotPosition(idx, btnSize)

    local data = { gui = sg, btn = btn, label = label, stroke = stroke,
                   conns = conns, userMoved = false, size = btnSize }
    MobileButtons.registry[guiName] = data
    return sg, data
end

do
    local lastViewport = getViewportSize()
    local pending = false
    local function onViewportChanged()
        if pending then return end
        pending = true
        defer(function()
            wait_(0.15)
            pending = false
            local vp = getViewportSize()
            if vp == lastViewport then return end
            lastViewport = vp
            local newSize = getButtonSize()
            for _, data in pairs(MobileButtons.registry) do
                if data.btn and data.btn.Parent then
                    data.size = newSize
                    data.btn.Size = UDim2.fromOffset(newSize.X, newSize.Y)
                end
            end
            reflow()
        end)
    end
    if Workspace.CurrentCamera then
        Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(onViewportChanged)
    end
end

local function makeSection(parent, title)
    local sec = parent:Section({ Title = title })
    try(function() sec.Opened = true end)
    try(function() sec:Open() end)
    return sec
end

local HomeTab     = Window:Tab({ Title = "Home",      Icon = "home"      })
local ReachTab    = Window:Tab({ Title = "Reach",     Icon = "box"       })
local GKTab       = Window:Tab({ Title = "GK",        Icon = "shield"    })
local FollowTab   = Window:Tab({ Title = "Follow",    Icon = "crosshair" })
local BallESPTab  = Window:Tab({ Title = "Ball ESP",  Icon = "eye"       })
local AimbotTab   = Window:Tab({ Title = "Aimbot",    Icon = "target"    })
local CharsTab    = Window:Tab({ Title = "Chars",     Icon = "user"      })
local SkyboxTab   = Window:Tab({ Title = "Skybox",    Icon = "cloud"     })
local SettingsTab = Window:Tab({ Title = "Settings",  Icon = "settings"  })

do
    local FPS, fpsTimer, fpsFrames = 60, 0, 0
    RunService.RenderStepped:Connect(function(dt)
        fpsFrames += 1; fpsTimer += dt
        if fpsTimer >= 0.5 then FPS = math.floor(fpsFrames / fpsTimer + 0.5); fpsFrames, fpsTimer = 0, 0 end
    end)
    local function getExecutor()
        if not identifyexecutor then return "Unknown" end
        local ok, ex = pcall(identifyexecutor)
        return (ok and ex) or "Unknown"
    end
    local function getGameName()
        local name = tostring(game.PlaceId)
        try(function()
            local info = MarketplaceService:GetProductInfo(game.PlaceId)
            if info and info.Name then name = info.Name end
        end)
        return name
    end
    local function getPing()
        local ok, p = pcall(function() return LocalPlayer:GetNetworkPing() end)
        if ok and typeof(p) == "number" and p > 0 then
            local ms = (p < 5) and (p * 1000) or p
            return string.format("%d ms", math.floor(ms + 0.5))
        end
        local ms
        try(function() ms = Stats.Network.ServerStatsItem["Data Ping"]:GetValue() end)
        if typeof(ms) == "number" and ms > 0 then return string.format("%d ms", math.floor(ms + 0.5)) end
        return "—"
    end
    local function getRegion()
        local region
        try(function()
            local containers = { Workspace, game, ReplicatedStorage }
            local names = { "ServerRegion", "Region", "ServerLocation", "RegionName", "ServerLocationName" }
            for _, c in ipairs(containers) do
                for _, n in ipairs(names) do
                    local v = c:FindFirstChild(n)
                    if v and v:IsA("StringValue") and v.Value ~= "" then region = v.Value; return end
                end
                for _, n in ipairs(names) do
                    local a = c:GetAttribute(n)
                    if a ~= nil and tostring(a) ~= "" then region = tostring(a); return end
                end
            end
        end)
        if region then return region end
        try(function()
            local c = LocalizationService:GetCountryRegionForPlayerAsync(LocalPlayer)
            if c and c ~= "" then region = c end
        end)
        return region or "Unknown"
    end

    local sys = makeSection(HomeTab, "System Info")
    local rows = {}
    local function findTitleLabel(inst, expectedPrefix)
        if not inst or typeof(inst) ~= "Instance" then return nil end
        local ok, descs = pcall(function() return inst:GetDescendants() end)
        if not ok or not descs then return nil end
        local best, bestLen = nil, 0
        for _, d in ipairs(descs) do
            if d:IsA("TextLabel") and d.Text ~= "" then
                if expectedPrefix and d.Text:find(expectedPrefix, 1, true) then return d end
                if #d.Text > bestLen then best, bestLen = d, #d.Text end
            end
        end
        return best
    end
    local function unwrapInstance(obj)
        if not obj then return nil end
        if typeof(obj) == "Instance" then return obj end
        if type(obj) ~= "table" then return nil end
        for _, key in ipairs({ "Instance", "Object", "UIElement", "UI", "Main", "Frame", "Button", "Holder", "Root", "Element" }) do
            local v = obj[key]
            if typeof(v) == "Instance" then return v end
        end
        return nil
    end
    local function addInfoRow(label, getter)
        local ok, btn = try(function()
            return sys:Button({ Title = label .. ": " .. tostring(getter()), Justify = "Left", Callback = function() end })
        end)
        if not ok or not btn then return end
        local entry = { btn = btn, label = label, getter = getter, titleLabel = nil }
        insert(rows, entry)
        defer(function()
            wait_(0.15)
            local inst = unwrapInstance(btn)
            local lbl = inst and findTitleLabel(inst, label .. ":")
            if lbl then
                entry.titleLabel = lbl
                try(function()
                    lbl.TextXAlignment = Enum.TextXAlignment.Left
                    lbl.Position = UDim2.new(0, 8, 0, 0)
                    lbl.Size = UDim2.new(1, -16, 1, 0)
                    lbl.AnchorPoint = Vector2.new(0, 0)
                    lbl.ZIndex = 3
                    lbl.TextTruncate = Enum.TextTruncate.AtEnd
                end)
            end
        end)
    end
    addInfoRow("Player",   function() return LocalPlayer.Name .. "  |  " .. tostring(LocalPlayer.UserId) end)
    addInfoRow("Executor", getExecutor)
    addInfoRow("Game",     getGameName)
    addInfoRow("FPS",      function() return tostring(FPS) end)
    addInfoRow("Ping",     getPing)
    addInfoRow("Region",   getRegion)
    addInfoRow("Time",     function() return os.date("%H:%M  |  %d/%m/%Y") end)

    local function updateRow(row)
        if not row or not row.titleLabel or not row.titleLabel.Parent then return end
        local ok, value = pcall(row.getter)
        if not ok or value == nil then value = "—" end
        local newText = row.label .. ": " .. tostring(value)
        if row.titleLabel.Text ~= newText then row.titleLabel.Text = newText end
    end
    spawn(function()
        while PlayerGui and PlayerGui.Parent do
            for i = 1, #rows do updateRow(rows[i]) end
            wait_(0.5)
        end
    end)

    HomeTab:Space()
    try(function()
        HomeTab:Button({
            Title = "Copy Discord Link", Justify = "Left", Icon = "message-circle",
            IconThemed = true, Color = Color3.fromHex("#5865F2"),
            Callback = function()
                if setclipboard then
                    try(setclipboard, "https://discord.gg/6KmTGAzbe")
                    Notify({ Title = "Discord copied!", Content = "Link on clipboard.", Duration = 4, Icon = "check" })
                else
                    Notify({ Title = "Error", Content = "setclipboard unavailable.", Duration = 4 })
                end
            end,
        })
    end)
end

local BALL_NAMES = { TPS = true, PSoccerBall = true }
local ballSet, ballList = {}, {}
local function addBall(b) if ballSet[b] then return end; ballSet[b] = true; insert(ballList, b) end
local function removeBall(b)
    if not ballSet[b] then return end
    ballSet[b] = nil
    for i = #ballList, 1, -1 do if ballList[i] == b then remove(ballList, i); break end end
end
local function scanBalls()
    clear(ballSet); clear(ballList)
    for _, d in ipairs(Workspace:GetDescendants()) do
        if d:IsA("BasePart") and BALL_NAMES[d.Name] then addBall(d) end
    end
end
scanBalls()

local _nearestBall, _nearestDist, _nearestStamp = nil, math.huge, 0
local function getNearestBall()
    local now = clock()
    if now - _nearestStamp < 0.008 then return _nearestBall, _nearestDist end
    _nearestStamp = now
    local hrp = State.HRP
    if not hrp then _nearestBall, _nearestDist = nil, math.huge; return nil, math.huge end
    local hrpPos = hrp.Position
    local best, bestDist = nil, math.huge
    for i = 1, #ballList do
        local ball = ballList[i]
        if ball and ball.Parent then
            local d = (hrpPos - ball.Position).Magnitude
            if d < bestDist then bestDist, best = d, ball end
        end
    end
    _nearestBall, _nearestDist = best, bestDist
    return best, bestDist
end

local ESPBall         = false
local ESPPrediction   = false
local PredictionTime  = 0.35
local CurrentTPS      = nil

local ESPHighlight = Instance.new("Highlight")
ESPHighlight.Name = "TPS_ESP"
ESPHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
ESPHighlight.FillTransparency = 0.35
ESPHighlight.OutlineTransparency = 0
ESPHighlight.Enabled = false
ESPHighlight.Parent = CoreGui

local ESPLine
do
    local ok = pcall(function() ESPLine = Drawing.new("Line") end)
    if ok and ESPLine then
        ESPLine.Visible = false
        ESPLine.Thickness = 2
        ESPLine.Transparency = 1
    end
end

local TPS_FOLDER_HINT = "WorkspaceLeaderboards"
local _tpsCache
local _currentBallPart
local _tpsGeneration = 0

local function resolveTPS()
    local folder = Workspace:FindFirstChild(TPS_FOLDER_HINT)
    if not folder then
        return nil
    end
    return folder:FindFirstChild("TPS")
end

local function GetBallPart(Object)
    if not Object or not Object.Parent then
        return nil
    end

    if Object:IsA("BasePart") then
        return Object
    end

    if Object:IsA("Model") then
        return Object.PrimaryPart
            or Object:FindFirstChildWhichIsA("BasePart", true)
    end

    return nil
end

local function updateCurrentTPS()
    local newTPS = resolveTPS()
    local newPart = GetBallPart(newTPS)

    if newTPS ~= _tpsCache or newPart ~= _currentBallPart then
        _tpsCache = newTPS
        _currentBallPart = newPart
        CurrentTPS = newTPS
        _tpsGeneration += 1

        if AimbotGoal and AimbotGoal.TouchConn then
            AimbotGoal.TouchConn:Disconnect()
            AimbotGoal.TouchConn = nil
        end

        if AimbotGoal then
            AimbotGoal.BallControl = false
            AimbotGoal.ShotDetected = false
            AimbotGoal.LastTouchTime = 0
            AimbotGoal.LastBallVelocity = Vector3.zero
        end
    end

    return _tpsCache, _currentBallPart, _tpsGeneration
end

local function scheduleTPSTry()
    defer(function()
        updateCurrentTPS()
    end)
end

local function FindTPS()
    updateCurrentTPS()
    return _tpsCache
end

local function GetCurrentBall()
    updateCurrentTPS()
    return _currentBallPart
end

local function GetPosition(Object)
    if not Object or not Object.Parent then return nil end
    if Object:IsA("BasePart") then return Object.Position end
    if Object:IsA("Model") then return Object:GetPivot().Position end
    return nil
end

local function GetVelocity(Object)
    if not Object or not Object.Parent then return Vector3.zero end
    if Object:IsA("BasePart") then return Object.AssemblyLinearVelocity end
    if Object:IsA("Model") and Object.PrimaryPart then
        return Object.PrimaryPart.AssemblyLinearVelocity
    end
    return Vector3.zero
end

local function UpdateESP()
    if not CurrentTPS or not CurrentTPS.Parent then
        ESPHighlight.Adornee = nil
        ESPHighlight.Enabled = false
        if ESPLine then ESPLine.Visible = false end
        return
    end

    local Position = GetPosition(CurrentTPS)

    if ESPBall then
        ESPHighlight.Adornee = CurrentTPS
        ESPHighlight.Enabled = true
    else
        ESPHighlight.Adornee = nil
        ESPHighlight.Enabled = false
    end

    if not ESPPrediction or not Position or not ESPLine then
        if ESPLine then ESPLine.Visible = false end
        return
    end

    local Velocity = GetVelocity(CurrentTPS)
    local PredictedPosition = Position + (Velocity * PredictionTime)

    local Camera = Workspace.CurrentCamera
    if not Camera then ESPLine.Visible = false; return end

    local StartPos, StartVisible = Camera:WorldToViewportPoint(Position)
    local EndPos, EndVisible = Camera:WorldToViewportPoint(PredictedPosition)

    if not StartVisible or not EndVisible then ESPLine.Visible = false; return end

    ESPLine.From = Vector2.new(StartPos.X, StartPos.Y)
    ESPLine.To   = Vector2.new(EndPos.X, EndPos.Y)
    ESPLine.Visible = true
end

local AutoGoal        = false
local SelectedGoal    = "Goal 1"
local ShootCooldown   = 0.15
local Goal1           = Vector3.new(-17, -29, 379)
local Goal2           = Vector3.new(-19, -29, -197)
local _goalGen        = 0

local AIMBOT_GOALS = { Goal1, Goal2 }

local AimbotGoal = {
    Enabled          = false,
    Speed            = 180,
    Smoothness       = 0.25,
    BallControl      = false,
    ShotDetected     = false,
    LastBallVelocity = Vector3.zero,
    LastTouchTime    = 0,
    TouchConn        = nil,
    MobileRefs       = nil,
    -- ✅ ADICIONADO: constantes do standalone
    DistanceToGoal   = 3,
    DistanceToBall   = 8,
}

local Telekinesis = {
    Enabled          = false,
    Speed            = 180,
    Smoothness       = 0.25,
    OldCameraSubject = nil,
}

local function getNearestAimbotGoal(position)
    local best, bestDist = nil, math.huge
    for i = 1, #AIMBOT_GOALS do
        local d = (AIMBOT_GOALS[i] - position).Magnitude
        if d < bestDist then bestDist, best = d, AIMBOT_GOALS[i] end
    end
    return best, bestDist
end

local function hasShootTool()
    local char = LocalPlayer.Character
    if not char then return false end
    local tool = char:FindFirstChild("Shoot")
    return tool ~= nil and tool:IsA("Tool")
end

local function resetAimbotState()
    AimbotGoal.BallControl      = false
    AimbotGoal.ShotDetected     = false
    AimbotGoal.LastTouchTime    = 0
    AimbotGoal.LastBallVelocity = Vector3.zero
end

local function bindAimbotTouch()
    if AimbotGoal.TouchConn then
        AimbotGoal.TouchConn:Disconnect()
        AimbotGoal.TouchConn = nil
    end

    resetAimbotState()

    local ball = GetCurrentBall()
    if not ball then
        return
    end

    local boundBall = ball

    AimbotGoal.TouchConn = boundBall.Touched:Connect(function()
        if not AimbotGoal.Enabled then return end
        if GetCurrentBall() ~= boundBall then return end
        if not hasShootTool() then return end

        local char = LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then return end

        if (boundBall.Position - root.Position).Magnitude > AimbotGoal.DistanceToBall then
            return
        end

        AimbotGoal.LastTouchTime = tick()
        AimbotGoal.ShotDetected = false
        AimbotGoal.BallControl = false
        AimbotGoal.LastBallVelocity = boundBall.AssemblyLinearVelocity
    end)
end

local function detectAimbotShot(ball)
    if not ball then return false end
    if AimbotGoal.LastTouchTime <= 0 then return false end
    if tick() - AimbotGoal.LastTouchTime > 1 then return false end

    local currentVel   = ball.AssemblyLinearVelocity
    local currentSpeed = currentVel.Magnitude
    local oldSpeed     = AimbotGoal.LastBallVelocity.Magnitude

    if currentSpeed > 8 and currentSpeed > oldSpeed + 4 then
        return true
    end

    AimbotGoal.LastBallVelocity = currentVel
    return false
end

local function setAimbotGoal(v)
    AimbotGoal.Enabled = v
    if AimbotGoal.MobileRefs then
        applyButtonState(AimbotGoal.MobileRefs, v, "AIMBOT\nON", "AIMBOT\nOFF")
    end
    if not v then
        resetAimbotState()
        if AimbotGoal.TouchConn then
            AimbotGoal.TouchConn:Disconnect()
            AimbotGoal.TouchConn = nil
        end
        return
    end
    scheduleTPSTry()
    defer(function() wait_(0.1); bindAimbotTouch() end)
end

local function setTelekinesis(v)
    local camera = Workspace.CurrentCamera
    if not camera then
        Telekinesis.Enabled = false
        return
    end

    if v then
        Telekinesis.OldCameraSubject = camera.CameraSubject
        Telekinesis.Enabled = true
        local ball = GetCurrentBall()
        if ball then
            camera.CameraSubject = ball
        else
            scheduleTPSTry()
        end
    else
        Telekinesis.Enabled = false
        local ball = GetCurrentBall()
        if ball then
            ball.AssemblyLinearVelocity = Vector3.zero
        end
        if Telekinesis.OldCameraSubject and Telekinesis.OldCameraSubject.Parent then
            camera.CameraSubject = Telekinesis.OldCameraSubject
        else
            local char = LocalPlayer.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum then camera.CameraSubject = hum end
        end
        Telekinesis.OldCameraSubject = nil
    end
end

local function GetShoot()
    local Character = LocalPlayer.Character
    if not Character then return nil end
    for _, Object in ipairs(Character:GetChildren()) do
        if Object:IsA("Tool") and string.lower(Object.Name):find("shoot") then return Object end
    end
    for _, Object in ipairs(LocalPlayer.Backpack:GetChildren()) do
        if Object:IsA("Tool") and string.lower(Object.Name):find("shoot") then return Object end
    end
    return nil
end
local function EquipShoot()
    local Character = LocalPlayer.Character
    local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
    if not Humanoid then return nil end
    local Tool = GetShoot()
    if Tool and Tool.Parent == LocalPlayer.Backpack then Humanoid:EquipTool(Tool) end
    return Tool
end
local function Shoot()
    local Tool = EquipShoot()
    if Tool then pcall(function() Tool:Activate() end) end
end

local function RunAutoGoalGen(gen)
    while AutoGoal and _goalGen == gen do
        local Character = LocalPlayer.Character
        local Root = Character and Character:FindFirstChild("HumanoidRootPart")
        if not Root then task.wait(0.01); continue end
        if not CurrentTPS or not CurrentTPS.Parent then
            scheduleTPSTry(); task.wait(0.05); continue
        end
        local GoalPosition = (SelectedGoal == "Goal 1") and Goal1 or Goal2
        local BallPosition = GetPosition(CurrentTPS)
        if not BallPosition then scheduleTPSTry(); task.wait(0.02); continue end
        local DirectionVector = GoalPosition - BallPosition
        if DirectionVector.Magnitude <= 2 then Shoot(); task.wait(ShootCooldown); continue end
        local Direction = DirectionVector.Unit
        local TargetPosition = BallPosition - Direction * 0.8 + Vector3.new(0, 0.3, 0)
        Root.CFrame = CFrame.lookAt(TargetPosition, BallPosition)
        task.wait(0.015)
        BallPosition = GetPosition(CurrentTPS)
        if not BallPosition then scheduleTPSTry(); task.wait(0.02); continue end
        local Distance = (GoalPosition - BallPosition).Magnitude
        local PushPosition = BallPosition + Direction * math.min(2.5, Distance) + Vector3.new(0, 0.3, 0)
        Root.CFrame = CFrame.lookAt(PushPosition, GoalPosition)
        Shoot()
        task.wait(ShootCooldown)
    end
end

local function setAutoGoal(v)
    AutoGoal = v
    _goalGen += 1
    if not v then return end
    local g = _goalGen
    spawn(function()
        local ok, err = pcall(RunAutoGoalGen, g)
        if not ok then warn("[AutoGoal] Erro:", err) end
    end)
end

local _equippedCache, _equippedStamp = nil, 0
local function getEquippedToolName()
    local now = clock()
    if now - _equippedStamp < 0.05 then return _equippedCache end
    _equippedStamp = now
    local char = LocalPlayer.Character
    if not char then _equippedCache = "NONE"; return _equippedCache end
    local tool = char:FindFirstChildOfClass("Tool")
    _equippedCache = tool and tool.Name or "NONE"
    return _equippedCache
end
local function ballIsFreeOrMine(ball)
    local owner = ball:FindFirstChild("Owner")
    if not owner or not owner:IsA("ObjectValue") then return true end
    local v = owner.Value
    return v == nil or v == LocalPlayer
end
local fireTouchFn = firetouchtransmitter or firetouchinterest
local function fireTouch(part, ball)
    if not part or not ball then return end
    if not part.Parent or not ball.Parent then return end
    if not fireTouchFn then return end
    pcall(fireTouchFn, part, ball, 0)
    pcall(fireTouchFn, part, ball, 1)
end
local function forceLegTouch(leg, ball)
    if not leg or not ball then return end
    if not ballIsFreeOrMine(ball) then return end
    fireTouch(leg, ball)
end

local GK_TOUCH_COOLDOWN = 0.6
local gkLastTrigger = 0

local _lowCatch
local function getLowCatchSignal()
    if _lowCatch and _lowCatch.Parent then return _lowCatch end
    local gui = PlayerGui:FindFirstChild("Start")
    if not gui then _lowCatch = nil; return nil end
    local imgLabel = gui:FindFirstChild("ImageLabel")
    if not imgLabel then _lowCatch = nil; return nil end
    _lowCatch = imgLabel:FindFirstChild("Low Catch")
    return _lowCatch
end
PlayerGui.DescendantAdded:Connect(function(d)
    if d.Name == "Low Catch" then _lowCatch = d end
end)
PlayerGui.DescendantRemoving:Connect(function(d)
    if d == _lowCatch then _lowCatch = nil end
end)

local function triggerLowCatch()
    local signal = getLowCatchSignal()
    if not signal then return false end
    if firesignal then
        local ok = pcall(firesignal, signal.MouseButton1Down)
        if ok then return true end
    end
    if getconnections then
        local ok, conns = pcall(getconnections, signal.MouseButton1Down)
        if ok and conns then
            for _, conn in ipairs(conns) do
                if conn.Function then spawn(function() pcall(conn.Function) end) end
            end
            return true
        end
    end
    return false
end
local function forceGKTouch(ball)
    if not ball or not ball.Parent then return end
    if not ballIsFreeOrMine(ball) then return end
    local now = clock()
    if now - gkLastTrigger < GK_TOUCH_COOLDOWN then return end
    gkLastTrigger = now
    if not triggerLowCatch() then return end
    wait_(0.02)
    local char = LocalPlayer.Character
    if not char then return end
    local bodyParts = { "Head", "Torso", "Right Arm", "Left Arm", "Right Leg", "Left Leg" }
    for _, name in ipairs(bodyParts) do
        local limb = char:FindFirstChild(name)
        if limb then fireTouch(limb, ball) end
    end
end
local function forceTouchDispatch(limbPart, ball)
    local tool = getEquippedToolName()
    if tool == "GK" then forceGKTouch(ball) else forceLegTouch(limbPart, ball) end
end

local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude
local EXCLUDE = {}
overlapParams.FilterDescendantsInstances = EXCLUDE

local function updateOverlapExclude(char)
    clear(EXCLUDE)
    if char then EXCLUDE[1] = char end
end
updateOverlapExclude(LocalPlayer.Character)
insert(onCharacterAdded,    updateOverlapExclude)
insert(onCharacterRemoving, function() updateOverlapExclude(nil) end)

local function findTarget(part)
    local c = part
    while c and c ~= Workspace do
        if c:IsA("BasePart") and BALL_NAMES[c.Name] then return c end
        c = c.Parent
    end
    return nil
end

local HitboxGroup = {}
HitboxGroup.__index = HitboxGroup
function HitboxGroup.new(parts, partToGroup)
    local self = setmetatable({}, HitboxGroup)
    self.parts, self.partToGroup = parts, partToGroup
    self.hitboxes, self.visualizers, self.baseParts, self.lastTouch = {}, {}, {}, {}
    self._stepNames = {}
    self.timer = 0.08
    return self
end
function HitboxGroup:_getSettings(_) return nil end
function HitboxGroup:_makeSize(parent, settings) return parent.Size * settings.Size end
function HitboxGroup:clearPart(partName)
    local hb = self.hitboxes[partName];    if hb then hb:Destroy() end
    local vz = self.visualizers[partName]; if vz then vz:Destroy() end
    self.hitboxes[partName], self.visualizers[partName], self.baseParts[partName] = nil, nil, nil
end
function HitboxGroup:updatePart(partName)
    local char = LocalPlayer.Character
    if not char then self:clearPart(partName); return end
    local parent = char:FindFirstChild(partName)
    if not parent then self:clearPart(partName); return end
    local cfg = self:_getSettings(partName)
    if not cfg or not cfg.Enabled then self:clearPart(partName); return end
    local sz = self:_makeSize(parent, cfg)
    if sz.X <= 0 or sz.Y <= 0 or sz.Z <= 0 then self:clearPart(partName); return end
    local hb = self.hitboxes[partName]
    if not hb or not hb.Parent then
        hb = Instance.new("Part")
        hb.Name = partName .. "_Hitbox"
        hb.Anchored, hb.CanCollide, hb.Transparency, hb.Massless = false, false, 1, true
        hb.CanQuery, hb.CanTouch = false, false
        hb.Size, hb.CFrame = sz, parent.CFrame
        hb.Parent = char
        local w = Instance.new("WeldConstraint")
        w.Part0, w.Part1, w.Parent = parent, hb, hb
        self.hitboxes[partName] = hb
    end
    hb.Size = sz
    self.baseParts[partName] = parent
    if cfg.Visualizer then
        local vis = self.visualizers[partName]
        if not vis or not vis.Parent then
            vis = Instance.new("Part")
            vis.Name = partName .. "_Visualizer"
            vis.Anchored, vis.CanCollide = false, false
            vis.Transparency, vis.Material, vis.Massless = 0.7, Enum.Material.Neon, true
            vis.CanQuery, vis.CanTouch = false, false
            vis.Parent = hb
            local w2 = Instance.new("WeldConstraint")
            w2.Part0, w2.Part1, w2.Parent = hb, vis, vis
            self.visualizers[partName] = vis
        end
        vis.Size, vis.Color = sz, cfg.Color
    else
        local vis = self.visualizers[partName]
        if vis then vis:Destroy() end
        self.visualizers[partName] = nil
    end
end
function HitboxGroup:updateAll() for i = 1, #self.parts do self:updatePart(self.parts[i]) end end
function HitboxGroup:clearAll()
    for i = 1, #self.parts do self:clearPart(self.parts[i]) end
    clear(self.hitboxes); clear(self.visualizers); clear(self.baseParts); clear(self.lastTouch)
end
function HitboxGroup:pruneLastTouch(now)
    local stale = {}
    for k, v in pairs(self.lastTouch) do if now - v > 3 then insert(stale, k) end end
    for i = 1, #stale do self.lastTouch[stale[i]] = nil end
end
function HitboxGroup:step(now, prefix)
    if next(self.hitboxes) == nil then return end
    local names = self._stepNames
    clear(names)
    for name in pairs(self.hitboxes) do names[#names + 1] = name end
    for i = 1, #names do
        local name = names[i]
        local hb = self.hitboxes[name]
        if hb and hb.Parent then
            local bp = self.baseParts[name]
            if bp and bp.Parent then
                local parts = Workspace:GetPartBoundsInBox(hb.CFrame, hb.Size, overlapParams)
                for j = 1, #parts do
                    local t = findTarget(parts[j])
                    if t then
                        local key = prefix .. name .. ":" .. t:GetFullName()
                        local last = self.lastTouch[key]
                        if not last or now - last > self.timer then
                            self.lastTouch[key] = now
                            forceTouchDispatch(bp, t)
                        end
                    end
                end
            end
        end
    end
end

local REACH_PARTS = { "Head", "Torso", "Right Leg", "Left Leg" }
local PART_TO_GROUP = { ["Head"] = "Head", ["Torso"] = "Torso", ["Right Leg"] = "Legs", ["Left Leg"] = "Legs" }
local ReachSettings = {
    Legs  = { Enabled = false, Visualizer = false, Size = 1, Color = Color3.fromRGB(0, 255, 0) },
    Torso = { Enabled = false, Visualizer = false, Size = 1, Color = Color3.fromRGB(0, 255, 0) },
    Head  = { Enabled = false, Visualizer = false, Size = 1, Color = Color3.fromRGB(0, 255, 0) },
    Distance = 50,
}
local Reach = HitboxGroup.new(REACH_PARTS, PART_TO_GROUP)
function Reach:_getSettings(partName)
    local grp = self.partToGroup[partName]
    return grp and ReachSettings[grp] or nil
end
insert(onCharacterAdded, function() Reach:clearAll(); wait_(2); Reach:updateAll() end)

local ARM_PARTS = {
    "RightHand", "Right Arm", "RightUpperArm", "RightLowerArm",
    "LeftHand",  "Left Arm",  "LeftUpperArm",  "LeftLowerArm",
}
local GKSettings = { Enabled = false, Visualizer = false, Size = 1, Range = 10, Color = Color3.fromRGB(0, 200, 255) }
local GKReach = HitboxGroup.new(ARM_PARTS, nil)
function GKReach:_getSettings(_) return GKSettings end
function GKReach:_makeSize(parent, settings)
    local maxDim = settings.Range
    local s = settings.Size
    return Vector3.new(
        math.min(parent.Size.X * s, maxDim),
        math.min(parent.Size.Y * s, maxDim),
        math.min(parent.Size.Z * s, maxDim)
    )
end
insert(onCharacterAdded, function() GKReach:clearAll(); wait_(2); GKReach:updateAll() end)

local AutoCatch = { Enabled = false, Range = 50, Cooldown = 0.25, LastCatch = 0, MobileRefs = nil }
local function fireCatchBall(ball)
    local remote = ReplicatedStorage:FindFirstChild("CatchBall")
    if remote and remote:IsA("RemoteEvent") then
        AutoCatch.LastCatch = clock()
        pcall(function() remote:FireServer(ball) end)
        return true
    end
    return false
end

RunService.Heartbeat:Connect(function()
    local now = clock()
    Reach:step(now, "")
    GKReach:step(now, "GK:")
    if now - (AutoCatch._lastPrune or 0) > 5 then
        AutoCatch._lastPrune = now
        Reach:pruneLastTouch(now)
        GKReach:pruneLastTouch(now)
    end
    if AutoCatch.Enabled then
        local hum, hrp = State.Humanoid, State.HRP
        if hum and hrp and hum.Health > 0 then
            if now - AutoCatch.LastCatch >= AutoCatch.Cooldown then
                local ball, dist = getNearestBall()
                if ball and dist <= AutoCatch.Range then fireCatchBall(ball) end
            end
        end
    end

    if AimbotGoal.Enabled then
        if _tpsCache ~= CurrentTPS then CurrentTPS = _tpsCache end
        local ball = GetCurrentBall()
        if ball then
            if not AimbotGoal.BallControl and not AimbotGoal.ShotDetected then
                if detectAimbotShot(ball) then
                    AimbotGoal.ShotDetected = true
                    AimbotGoal.BallControl = true
                end
            end

            -- ✅ CORRIGIDO: check de distância da meta antes de empurrar
            if AimbotGoal.BallControl then
                local goal = getNearestAimbotGoal(ball.Position)
                if goal then
                    local diff = goal - ball.Position
                    local dist = diff.Magnitude

                    if dist <= AimbotGoal.DistanceToGoal then
                        ball.AssemblyLinearVelocity = Vector3.zero
                        AimbotGoal.BallControl   = false
                        AimbotGoal.ShotDetected  = false
                        AimbotGoal.LastTouchTime = 0
                    else
                        local target = diff.Unit * AimbotGoal.Speed
                        ball.AssemblyLinearVelocity =
                            ball.AssemblyLinearVelocity:Lerp(target, AimbotGoal.Smoothness)
                    end
                end
            end
        else
            resetAimbotState()
        end
    end

    if Telekinesis.Enabled then
        local ball = GetCurrentBall()
        local camera = Workspace.CurrentCamera
        if ball and camera then
            local dir = camera.CFrame.LookVector
            local target = dir * Telekinesis.Speed
            ball.AssemblyLinearVelocity = ball.AssemblyLinearVelocity:Lerp(target, Telekinesis.Smoothness)
        end
    end
end)

RunService.RenderStepped:Connect(function()
    if CurrentTPS and not CurrentTPS.Parent then
        _tpsCache, CurrentTPS = nil, nil
        scheduleTPSTry()
    end
    if not CurrentTPS and not _tpsCache then
        scheduleTPSTry()
    end
    UpdateESP()
end)

Workspace.DescendantRemoving:Connect(function(d)
    if ballSet[d] then removeBall(d) end
    if d == CurrentTPS then
        CurrentTPS = nil
        _tpsCache = nil
        ESPHighlight.Adornee = nil
        ESPHighlight.Enabled = false
        if ESPLine then ESPLine.Visible = false end
        resetAimbotState()
        defer(scheduleTPSTry)
    end
end)
Workspace.DescendantAdded:Connect(function(d)
    if d:IsA("BasePart") and BALL_NAMES[d.Name] then addBall(d) end
    if (d.Name == "TPS" or d.Name == TPS_FOLDER_HINT) and not _tpsCache then
        scheduleTPSTry()
        defer(function()
            wait_(0.05)
            if AimbotGoal.Enabled then bindAimbotTouch() end
            if Telekinesis.Enabled then
                local ball = GetCurrentBall()
                local camera = Workspace.CurrentCamera
                if ball and camera then
                    camera.CameraSubject = ball
                end
            end
        end)
    end
end)
scheduleTPSTry()

local Follow = {
    Enabled      = false,
    Distance     = 0.5,
    PredictTime  = 0.35,
    SmoothRate   = 15,
    Connection   = nil,
    MobileRefs   = nil,
}

local PredState = {
    ball      = nil,
    lastVel   = nil,
    lastTime  = 0,
    smoothed  = nil,
}

local function resetPredState(ball)
    PredState.ball     = ball
    PredState.lastVel  = nil
    PredState.lastTime = clock()
    PredState.smoothed = nil
end

local function computePredicted(ball, _dt)
    local pos = ball.Position
    local vel = ball.AssemblyLinearVelocity

    if PredState.ball ~= ball then
        resetPredState(ball)
        return pos
    end

    local now = clock()
    local deltaT = math.clamp(now - PredState.lastTime, 1/240, 1/15)
    PredState.lastTime = now

    local accel = Vector3.zero
    if PredState.lastVel then
        accel = (vel - PredState.lastVel) / deltaT
        local maxAccel = 500
        if accel.Magnitude > maxAccel then
            accel = accel.Unit * maxAccel
        end
    end
    PredState.lastVel = vel

    local t = Follow.PredictTime
    local rawPredicted = pos + vel * t + 0.5 * accel * t * t

    if PredState.smoothed then
        local rate = Follow.SmoothRate
        local k = 1 - math.exp(-rate * deltaT)
        PredState.smoothed = PredState.smoothed:Lerp(rawPredicted, k)
    else
        PredState.smoothed = rawPredicted
    end

    return PredState.smoothed
end

local function stopFollow()
    Follow.Enabled = false
    if Follow.Connection then Follow.Connection:Disconnect(); Follow.Connection = nil end
    if State.Humanoid then pcall(function() State.Humanoid:Move(Vector3.zero, false) end) end
    resetPredState(nil)
end

local function startFollow()
    Follow.Enabled = true
    if Follow.Connection then Follow.Connection:Disconnect() end
    resetPredState(nil)

    Follow.Connection = RunService.RenderStepped:Connect(function(dt)
        if not Follow.Enabled then return end

        local hum, hrp = State.Humanoid, State.HRP
        if not hum or not hrp or hum.Health <= 0 then return end
        if hum.MoveDirection.Magnitude > 0.05 then return end

        local ball = getNearestBall()
        if not ball or not ball.Parent then return end

        local predicted = computePredicted(ball, dt)

        local target = Vector3.new(predicted.X, hrp.Position.Y, predicted.Z)
        local diff = target - hrp.Position
        local distance = diff.Magnitude

        if distance > Follow.Distance then
            hum:Move(diff.Unit, false)
            hrp.CFrame = CFrame.new(hrp.Position, target)
        else
            hum:Move(Vector3.zero, false)
        end
    end)
end

local function setFollow(v)
    if v then if not Follow.Enabled then startFollow() end
    else stopFollow() end
end
insert(onCharacterAdded, function() stopFollow() end)
insert(onCharacterAdded, function()
    resetAimbotState()
    defer(function() wait_(1); bindAimbotTouch() end)
end)

local AutoSaveEnabled = false
local AutoLoadEnabled = false
local _configChangeQueued = false
local _saveConfigFn
local function onConfigChanged()
    if not AutoSaveEnabled then return end
    if _configChangeQueued then return end
    _configChangeQueued = true
    defer(function()
        wait_(0.6)
        _configChangeQueued = false
        if _saveConfigFn then _saveConfigFn() end
    end)
end

local function reachSection(key, title)
    local sec = makeSection(ReachTab, title)
    sec:Toggle({
        Title = "Enable " .. title, Default = false,
        Callback = function(v)
            ReachSettings[key].Enabled = v
            defer(Reach.updateAll, Reach)
            Notify({ Title = title, Content = v and "Enabled!" or "Disabled!", Duration = 2 })
            onConfigChanged()
        end,
    })
    sec:Toggle({ Title = "Show Visualizer", Default = false,
        Callback = function(v) ReachSettings[key].Visualizer = v; defer(Reach.updateAll, Reach); onConfigChanged() end })
    sec:Slider({ Title = "Size", Step = 0.5,
        Value = { Min = 0.5, Max = 20, Default = 1 },
        Callback = function(v) ReachSettings[key].Size = v; defer(Reach.updateAll, Reach); onConfigChanged() end })
end
reachSection("Legs", "Leg Reach"); ReachTab:Space()
reachSection("Torso", "Torso Reach"); ReachTab:Space()
reachSection("Head", "Head Reach")

do
    local sec = makeSection(GKTab, "GK Reach")
    sec:Toggle({
        Title = "Enable GK Reach", Default = false,
        Callback = function(v)
            GKSettings.Enabled = v
            defer(GKReach.updateAll, GKReach)
            Notify({ Title = "GK Reach", Content = v and "Enabled!" or "Disabled!", Duration = 2 })
            onConfigChanged()
        end,
    })
    sec:Toggle({ Title = "Show Visualizer", Default = false,
        Callback = function(v) GKSettings.Visualizer = v; defer(GKReach.updateAll, GKReach); onConfigChanged() end })
    sec:Slider({ Title = "Size", Step = 0.5,
        Value = { Min = 0.5, Max = 20, Default = 1 },
        Callback = function(v) GKSettings.Size = v; defer(GKReach.updateAll, GKReach); onConfigChanged() end })
end

do
    local sec = makeSection(BallESPTab, "Ball ESP")
    sec:Toggle({
        Title = "ESP Ball",
        Default = false,
        Callback = function(v)
            ESPBall = v
            UpdateESP()
            Notify({ Title = "Ball ESP", Content = v and "Enabled!" or "Disabled!", Duration = 2 })
            onConfigChanged()
        end,
    })
    sec:Toggle({
        Title = "ESP Prediction",
        Default = false,
        Callback = function(v) ESPPrediction = v; UpdateESP(); onConfigChanged() end,
    })
    sec:Slider({
        Title = "Prediction Time", Step = 0.05,
        Value = { Min = 0.05, Max = 1, Default = 0.35 },
        Callback = function(v) PredictionTime = v; onConfigChanged() end,
    })
end

do
    local sec = makeSection(AimbotTab, "Auto Goal")
    sec:Toggle({
        Title = "Auto Goal",
        Default = false,
        Callback = function(v)
            setAutoGoal(v)
            Notify({ Title = "Auto Goal", Content = v and "Enabled!" or "Disabled!", Duration = 2 })
            onConfigChanged()
        end,
    })
    sec:Dropdown({
        Title = "Select Goal",
        Values = { "Goal (Green)", "Goal (Blue)" },
        Value = "Goal (Green)",
        Callback = function(Value)
            if Value == "Goal (Green)" then SelectedGoal = "Goal 1"
            else SelectedGoal = "Goal 2" end
            onConfigChanged()
        end,
    })
end

AimbotTab:Space()
do
    local sec = makeSection(AimbotTab, "Aimbot Goal")
    sec:Toggle({
        Title = "Enable Aimbot Goal",
        Default = false,
        Callback = function(v)
            setAimbotGoal(v)
            Notify({ Title = "Aimbot Goal", Content = v and "Enabled!" or "Disabled!", Duration = 2 })
            onConfigChanged()
        end,
    })
    sec:Slider({
        Title = "Speed", Step = 5,
        Value = { Min = 20, Max = 500, Default = 180 },
        Callback = function(v) AimbotGoal.Speed = v; onConfigChanged() end,
    })
    sec:Slider({
        Title = "Smoothness", Step = 0.01,
        Value = { Min = 0.01, Max = 1, Default = 0.25 },
        Callback = function(v) AimbotGoal.Smoothness = v; onConfigChanged() end,
    })
    sec:Slider({
        Title = "Distance To Goal", Step = 0.5,
        Value = { Min = 0.5, Max = 15, Default = 3 },
        Callback = function(v) AimbotGoal.DistanceToGoal = v; onConfigChanged() end,
    })
    sec:Slider({
        Title = "Distance To Ball (Touch)", Step = 1,
        Value = { Min = 1, Max = 30, Default = 8 },
        Callback = function(v) AimbotGoal.DistanceToBall = v; onConfigChanged() end,
    })
    sec:Toggle({
        Title = "Show Mobile Button", Default = false,
        Callback = function(v)
            if v then
                local _, refs = createMobileButton("LuaAimbotMobile", "AIMBOT\nOFF", function()
                    setAimbotGoal(not AimbotGoal.Enabled)
                end)
                AimbotGoal.MobileRefs = refs
                if AimbotGoal.Enabled then
                    applyButtonState(refs, true, "AIMBOT\nON", "AIMBOT\nOFF")
                end
            else
                setAimbotGoal(false)
                destroyMobileButton("LuaAimbotMobile")
                AimbotGoal.MobileRefs = nil
            end
        end,
    })
end

AimbotTab:Space()
do
    local sec = makeSection(AimbotTab, "Telekinesis")
    sec:Toggle({
        Title = "Enable Telekinesis",
        Default = false,
        Callback = function(v)
            setTelekinesis(v)
            Notify({ Title = "Telekinesis", Content = v and "Enabled!" or "Disabled!", Duration = 2 })
            onConfigChanged()
        end,
    })
    sec:Slider({
        Title = "Speed", Step = 5,
        Value = { Min = 20, Max = 500, Default = 180 },
        Callback = function(v) Telekinesis.Speed = v; onConfigChanged() end,
    })
    sec:Slider({
        Title = "Smoothness", Step = 0.01,
        Value = { Min = 0.01, Max = 1, Default = 0.25 },
        Callback = function(v) Telekinesis.Smoothness = v; onConfigChanged() end,
    })
end

local CHAT_KEYWORDS = { "global", "chat", "say", "messenger", "main" }
local _chatRemotes, _chatRemoteStamp = {}, 0
local function chatRemoteCache()
    if tick() - _chatRemoteStamp < 5 then return _chatRemotes end
    _chatRemoteStamp = tick()
    clear(_chatRemotes)
    for _, v in ipairs(ReplicatedStorage:GetDescendants()) do
        if v:IsA("RemoteEvent") then
            local lname = string.lower(v.Name)
            for i = 1, #CHAT_KEYWORDS do
                if string.find(lname, CHAT_KEYWORDS[i], 1, true) then
                    insert(_chatRemotes, v)
                    break
                end
            end
        end
    end
    return _chatRemotes
end
local function tryFireRemotes(msg)
    local list = chatRemoteCache()
    if #list == 0 then return false end
    for i = 1, #list do pcall(function() list[i]:FireServer(msg) end) end
    return true
end
local function tryTextChatService(msg)
    if not TextChatService then return false end
    local ok = false
    pcall(function()
        local channels = TextChatService:FindFirstChild("TextChannels")
        local channel = channels and channels:FindFirstChild("RBXGeneral")
        if channel then channel:SendAsync(msg); ok = true end
    end)
    return ok
end
local function tryLegacyChat(msg)
    local chat = ReplicatedStorage:FindFirstChild("DefaultChatSystemChatEvents")
    if not chat then return false end
    local sayRequest = chat:FindFirstChild("SayMessageRequest")
    if not sayRequest then return false end
    pcall(function() sayRequest:FireServer(msg, "All") end)
    return true
end
local function sendGlobalMessage(msg)
    if tryFireRemotes(msg)     then return true end
    if tryTextChatService(msg) then return true end
    if tryLegacyChat(msg)      then return true end
    return false
end

local CHAR_NICKS_RAW = {
    "Feliipeef", "pret_oncio", "jessnaldo", "lucasbr8181", "PositiveVapor",
    "kvbberdad", "kvbber", "ongoal", "leolity", "paulonetos05",
    "candyxzzz0", "BRENOTAKEDA2011 (troll)", "monoball_jhh (troll)",
    "zvbFaeTVXTq", "defantastico", "emaofj", "5zB4y", "ByGui08",
    "levi_furacao", "o_lfk", "feliou23", "3qu", "thunder65q",
    "MiguelcalebeGamer202", "legendinho", "THIXGOOOOOO", "talenttt",
    "vnpthu", "oxlade", "Dismalbeni", "megutrap", "brvnofalcon",
    "Rhuanbla", "SenAstrozx", "I_Ruanblox", "Rvnezzy", "heheboi202000",
    "Nescauzin_skills", "lilililililili_305", "heitor756666", "nexzaard",
    "mitoashpikachu2", "rosa_skillsz", "zico_alt123", "b_2020f",
    "ry_dinno", "cachorrao_fla", "barard28", "yurinho_0011",
    "deyvztcs", "euperdro14", "Alex151kk",
}

local function parseNick(raw)
    local base = raw:gsub("%s*%(troll%)%s*$", "")
    return base, raw ~= base
end

local CHAR_NICKS
do
    local seen, unique = {}, {}
    for i = 1, #CHAR_NICKS_RAW do
        local raw = CHAR_NICKS_RAW[i]
        local base = parseNick(raw)
        local key = string.lower(base)
        if not seen[key] then
            seen[key] = true
            unique[#unique + 1] = raw
        end
    end
    CHAR_NICKS = unique
end

local charButtons = {}
local charSection
local currentSearch = ""

local function rebuildCharButtons(filter)
    if not charSection then return end
    filter = string.lower(filter or "")
    for i = 1, #charButtons do
        pcall(function() charButtons[i]:Destroy() end)
        charButtons[i] = nil
    end
    for i = 1, #CHAR_NICKS do
        local raw = CHAR_NICKS[i]
        local base = parseNick(raw)
        if filter == "" or string.find(string.lower(raw), filter, 1, true) then
            local cmd = ":char " .. base
            local display = ":char " .. raw
            local btn = charSection:Button({
                Title = display, Justify = "Left", Icon = "user",
                Callback = function()
                    local ok = sendGlobalMessage(cmd)
                    if ok then
                        Notify({ Title = "Chars", Content = cmd .. " enviado.", Duration = 2, Icon = "check" })
                    else
                        Notify({ Title = "Chars", Content = "Falha ao enviar.", Duration = 3 })
                    end
                end,
            })
            if btn then charButtons[#charButtons + 1] = btn end
        end
    end
end

do
    local searchBtn = makeSection(CharsTab, "Search")
    local inputBox
    pcall(function()
        inputBox = searchBtn:Input({
            Title = "Nick", Placeholder = "digite o nick aqui...",
            Callback = function(text) currentSearch = text or ""; rebuildCharButtons(currentSearch) end,
        })
    end)
    searchBtn:Button({
        Title = "Use Char of Search", Justify = "Center", Icon = "send",
        Callback = function()
            if currentSearch == "" and inputBox then
                local inst = inputBox
                if type(inst) == "table" then
                    for _, key in ipairs({ "Instance", "Object", "UIElement", "UI", "Main", "Frame", "Button", "TextBox", "Root", "Element" }) do
                        local v = inst[key]; if typeof(v) == "Instance" then inst = v; break end
                    end
                end
                if typeof(inst) == "Instance" then
                    local tb = inst:IsA("TextBox") and inst or inst:FindFirstChildWhichIsA("TextBox", true)
                    if tb and tb.Text ~= "" then currentSearch = tb.Text end
                end
            end
            if currentSearch == "" then Notify({ Title = "Chars", Content = "Digite um nick primeiro.", Duration = 2 }); return end
            local cmd = ":char " .. currentSearch
            if sendGlobalMessage(cmd) then
                Notify({ Title = "Chars", Content = cmd .. " enviado.", Duration = 2, Icon = "check" })
            else
                Notify({ Title = "Chars", Content = "Falha ao enviar.", Duration = 3 })
            end
        end,
    })
    searchBtn:Button({
        Title = "Clear Filter", Justify = "Center", Icon = "x",
        Callback = function() currentSearch = ""; rebuildCharButtons("") end,
    })
end

charSection = makeSection(CharsTab, "Chars (" .. #CHAR_NICKS .. ")")
rebuildCharButtons("")

local function isSkyKeyword(name)
    local n = string.lower(name)
    return string.find(n, "sky", 1, true) or string.find(n, "dome", 1, true)
        or string.find(n, "ceu", 1, true) or string.find(n, "atmosphere", 1, true)
end
local function isOurSky(obj) return string.find(string.lower(obj.Name), "scarhub", 1, true) ~= nil end
local function getBackupFolder()
    local f = Lighting:FindFirstChild("ScarHubSkyBackup")
    if not f then f = Instance.new("Folder"); f.Name = "ScarHubSkyBackup"; f.Parent = Lighting end
    return f
end
local function saveOriginalSky()
    local folder = getBackupFolder()
    if #folder:GetChildren() > 0 then return end
    for _, child in ipairs(Lighting:GetChildren()) do
        if child ~= folder and (child:IsA("Sky") or child:IsA("Atmosphere")
        or child:IsA("Clouds") or child:IsA("PostEffect")
        or child:IsA("ColorCorrectionEffect")) then
            pcall(function() local c = child:Clone(); c.Parent = folder end)
        end
    end
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if (obj:IsA("BasePart") or obj:IsA("Model")) and isSkyKeyword(obj.Name) and not isOurSky(obj) then
            pcall(function() local c = obj:Clone(); c.Parent = folder end)
        end
    end
end
local function wipeCurrentSky()
    for _, child in ipairs(Lighting:GetChildren()) do
        if child:IsA("Sky") or child:IsA("Atmosphere") or child:IsA("Clouds")
        or child:IsA("PostEffect") or child:IsA("ColorCorrectionEffect") then
            pcall(function() child:Destroy() end)
        end
    end
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if (obj:IsA("BasePart") or obj:IsA("Model")) and isSkyKeyword(obj.Name) and not isOurSky(obj) then
            pcall(function() obj:Destroy() end)
        end
    end
end
local function restoreOriginalSky()
    local folder = Lighting:FindFirstChild("ScarHubSkyBackup")
    if not folder or #folder:GetChildren() == 0 then
        Notify({ Title = "Skybox", Content = "Nada salvo ainda.", Duration = 3 }); return
    end
    wipeCurrentSky()
    for _, clone in ipairs(folder:GetChildren()) do
        pcall(function()
            local newObj = clone:Clone()
            if newObj:IsA("BasePart") or newObj:IsA("Model") then newObj.Parent = Workspace
            else newObj.Parent = Lighting end
        end)
    end
    Notify({ Title = "Skybox", Content = "Ceu original restaurado.", Duration = 2, Icon = "check" })
end
local function ForceSkyTCS(assetId)
    saveOriginalSky()
    wipeCurrentSky()
    local url = "rbxassetid://" .. tostring(assetId)
    local loaded = false
    pcall(function()
        local objects = game:GetObjects(url)
        for _, v in ipairs(objects) do
            if v:IsA("Sky") then v.Name = "ScarHubSky"; v.Parent = Lighting; loaded = true end
        end
    end)
    if not loaded then
        local newSky = Instance.new("Sky")
        newSky.Name = "ScarHubSky"
        newSky.SkyboxBk, newSky.SkyboxDn, newSky.SkyboxFt = url, url, url
        newSky.SkyboxLf, newSky.SkyboxRt, newSky.SkyboxUp = url, url, url
        newSky.Parent = Lighting
    end
    Notify({ Title = "Skybox", Content = "Ceu aplicado.", Duration = 2, Icon = "check" })
end

do
    local SKY_LIST = {
        { Name = "Scary Red Sky",       Id = "136055162054954" },
        { Name = "Pink Sky",            Id = "96902346573845"  },
        { Name = "Minecraft Sky",       Id = "96736589365838"  },
        { Name = "Epic Night Sky",      Id = "143962526"       },
        { Name = "Green Sky",           Id = "348361280"       },
        { Name = "Space Sky",           Id = "196277044"       },
        { Name = "Sky 66",              Id = "171591350"       },
        { Name = "Anime Sky",           Id = "365232842"       },
        { Name = "Aesthetic Night Sky", Id = "1045971296"      },
        { Name = "c00lkidd Sky",        Id = "133973334152130" },
        { Name = "Snow Sky",            Id = "2706122232"      },
        { Name = "Black Hole Sky",      Id = "14201658516"     },
        { Name = "Shrek Sky",           Id = "90269177738915"  },
        { Name = "HD Sky",              Id = "17124418086"     },
        { Name = "Weirdcore Sky",       Id = "6823350455"      },
        { Name = "Hatsune Miku Sky",    Id = "2900944368"      },
        { Name = "Saturn Sky",          Id = "1898754079"      },
    }
    local skySec = makeSection(SkyboxTab, "Skyboxes")
    for i = 1, #SKY_LIST do
        local item = SKY_LIST[i]
        skySec:Button({
            Title = item.Name, Justify = "Left", Icon = "cloud",
            Callback = function() ForceSkyTCS(item.Id) end,
        })
    end
    SkyboxTab:Space()
    SkyboxTab:Button({
        Title = "Restaurar Ceu Original", Justify = "Center", Icon = "rotate-ccw",
        Callback = restoreOriginalSky,
    })
end

local KeybindSystem = {
    UIKeybind = Enum.KeyCode.LeftShift,
    _conn     = nil,
}
local function findWindowGui()
    for _, gui in ipairs(PlayerGui:GetChildren()) do
        if gui:IsA("ScreenGui") then
            local ok, descs = pcall(function() return gui:GetDescendants() end)
            if ok and descs then
                for _, d in ipairs(descs) do
                    if d:IsA("ImageLabel") and d.Image == ICON_ASSET then return gui end
                end
            end
        end
    end
    return nil
end
local cachedWindowGui = nil
local function getWindowGui()
    if cachedWindowGui and cachedWindowGui.Parent then return cachedWindowGui end
    cachedWindowGui = findWindowGui()
    return cachedWindowGui
end
local function toggleWindow()
    local gui = getWindowGui()
    if gui then gui.Enabled = not gui.Enabled end
end
local function startKeybindListener()
    if KeybindSystem._conn then KeybindSystem._conn:Disconnect() end
    KeybindSystem._conn = UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        if input.KeyCode == KeybindSystem.UIKeybind then toggleWindow() end
    end)
end
local function captureNewKeybind(callback)
    local conn
    local finished = false
    conn = UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        finished = true
        KeybindSystem.UIKeybind = input.KeyCode
        if conn then conn:Disconnect() end
        if callback then callback(input.KeyCode) end
    end)
    task.delay(8, function()
        if not finished and conn then
            conn:Disconnect()
            Notify({ Title = "Keybind", Content = "Tempo esgotado.", Duration = 3 })
        end
    end)
    Notify({ Title = "Keybind", Content = "Pressione uma tecla...", Duration = 4 })
end
startKeybindListener()

local CONFIG_FOLDER  = "LuaTpsUltimate"
local CONFIG_FILE    = CONFIG_FOLDER .. "/config.json"

local function ensureFolder()
    if makefolder then
        if isfolder and not isfolder(CONFIG_FOLDER) then pcall(makefolder, CONFIG_FOLDER)
        else pcall(makefolder, CONFIG_FOLDER) end
    end
end
local function encodeJSON(data)
    local ok, res = pcall(function() return HttpService:JSONEncode(data) end)
    if ok then return res end
    return nil
end
local function decodeJSON(str)
    local ok, res = pcall(function() return HttpService:JSONDecode(str) end)
    if ok then return res end
    return nil
end

local function captureConfig()
    return {
        Reach = {
            Legs  = { Enabled = ReachSettings.Legs.Enabled,  Visualizer = ReachSettings.Legs.Visualizer,  Size = ReachSettings.Legs.Size },
            Torso = { Enabled = ReachSettings.Torso.Enabled, Visualizer = ReachSettings.Torso.Visualizer, Size = ReachSettings.Torso.Size },
            Head  = { Enabled = ReachSettings.Head.Enabled,  Visualizer = ReachSettings.Head.Visualizer,  Size = ReachSettings.Head.Size },
        },
        GKReach   = { Enabled = GKSettings.Enabled, Visualizer = GKSettings.Visualizer, Size = GKSettings.Size, Range = GKSettings.Range },
        AutoCatch = { Enabled = AutoCatch.Enabled, Range = AutoCatch.Range, Cooldown = AutoCatch.Cooldown },
        Follow    = {
            Enabled     = Follow.Enabled,
            Distance    = Follow.Distance,
            PredictTime = Follow.PredictTime,
        },
        BallESP   = { ESPBall = ESPBall, ESPPrediction = ESPPrediction, PredictionTime = PredictionTime },
        Goal      = { AutoGoal = AutoGoal, SelectedGoal = SelectedGoal },
        Aimbot    = {
            Enabled         = AimbotGoal.Enabled,
            Speed           = AimbotGoal.Speed,
            Smoothness      = AimbotGoal.Smoothness,
            DistanceToGoal  = AimbotGoal.DistanceToGoal,
            DistanceToBall  = AimbotGoal.DistanceToBall,
        },
        Telekinesis = {
            Enabled    = Telekinesis.Enabled,
            Speed      = Telekinesis.Speed,
            Smoothness = Telekinesis.Smoothness,
        },
        Keybinds  = { UIKeybind = KeybindSystem.UIKeybind.Name },
        AutoFlags = { AutoSave = AutoSaveEnabled, AutoLoad = AutoLoadEnabled },
    }
end

local function applyConfig(cfg)
    if not cfg then return end

    if cfg.Reach then
        for _, key in ipairs({ "Legs", "Torso", "Head" }) do
            local s = cfg.Reach[key]
            if s then
                if s.Enabled    ~= nil then ReachSettings[key].Enabled    = s.Enabled end
                if s.Visualizer ~= nil then ReachSettings[key].Visualizer = s.Visualizer end
                if s.Size       ~= nil then ReachSettings[key].Size       = s.Size end
            end
        end
        defer(Reach.updateAll, Reach)
    end

    if cfg.GKReach then
        if cfg.GKReach.Enabled    ~= nil then GKSettings.Enabled    = cfg.GKReach.Enabled end
        if cfg.GKReach.Visualizer ~= nil then GKSettings.Visualizer = cfg.GKReach.Visualizer end
        if cfg.GKReach.Size       ~= nil then GKSettings.Size       = cfg.GKReach.Size end
        defer(GKReach.updateAll, GKReach)
    end

    if cfg.AutoCatch then
        if cfg.AutoCatch.Enabled  ~= nil then AutoCatch.Enabled  = cfg.AutoCatch.Enabled end
        if cfg.AutoCatch.Range    ~= nil then AutoCatch.Range    = cfg.AutoCatch.Range end
        if cfg.AutoCatch.Cooldown ~= nil then AutoCatch.Cooldown = cfg.AutoCatch.Cooldown end
    end

    if cfg.Follow then
        if cfg.Follow.Enabled ~= nil then setFollow(cfg.Follow.Enabled) end
        if cfg.Follow.Distance    ~= nil then Follow.Distance    = cfg.Follow.Distance end
        if cfg.Follow.PredictTime ~= nil then Follow.PredictTime = cfg.Follow.PredictTime end
    end

    if cfg.BallESP then
        if cfg.BallESP.ESPBall        ~= nil then ESPBall        = cfg.BallESP.ESPBall end
        if cfg.BallESP.ESPPrediction  ~= nil then ESPPrediction  = cfg.BallESP.ESPPrediction end
        if cfg.BallESP.PredictionTime ~= nil then PredictionTime = cfg.BallESP.PredictionTime end
        UpdateESP()
    end

    if cfg.Goal then
        if cfg.Goal.AutoGoal     ~= nil then setAutoGoal(cfg.Goal.AutoGoal) end
        if cfg.Goal.SelectedGoal ~= nil then SelectedGoal = cfg.Goal.SelectedGoal end
    end

    if cfg.Aimbot then
        if cfg.Aimbot.Speed           ~= nil then AimbotGoal.Speed           = cfg.Aimbot.Speed end
        if cfg.Aimbot.Smoothness      ~= nil then AimbotGoal.Smoothness      = cfg.Aimbot.Smoothness end
        if cfg.Aimbot.DistanceToGoal  ~= nil then AimbotGoal.DistanceToGoal  = cfg.Aimbot.DistanceToGoal end
        if cfg.Aimbot.DistanceToBall  ~= nil then AimbotGoal.DistanceToBall  = cfg.Aimbot.DistanceToBall end
        if cfg.Aimbot.Enabled         ~= nil then setAimbotGoal(cfg.Aimbot.Enabled) end
    end

    if cfg.Telekinesis then
        if cfg.Telekinesis.Speed      ~= nil then Telekinesis.Speed      = cfg.Telekinesis.Speed end
        if cfg.Telekinesis.Smoothness ~= nil then Telekinesis.Smoothness = cfg.Telekinesis.Smoothness end
        if cfg.Telekinesis.Enabled    ~= nil then setTelekinesis(cfg.Telekinesis.Enabled) end
    end

    if cfg.Keybinds then
        if cfg.Keybinds.UIKeybind then
            local ok, key = pcall(function() return Enum.KeyCode[cfg.Keybinds.UIKeybind] end)
            if ok and key then KeybindSystem.UIKeybind = key end
        end
    end

    if cfg.AutoFlags then
        if cfg.AutoFlags.AutoSave ~= nil then AutoSaveEnabled = cfg.AutoFlags.AutoSave end
        if cfg.AutoFlags.AutoLoad ~= nil then AutoLoadEnabled = cfg.AutoFlags.AutoLoad end
    end
end

local function saveConfig(path)
    ensureFolder()
    if not writefile then return false end
    local encoded = encodeJSON(captureConfig())
    if not encoded then return false end
    return pcall(writefile, path or CONFIG_FILE, encoded)
end
_saveConfigFn = function() saveConfig(CONFIG_FILE) end

local function loadConfig(path)
    if not readfile then return nil end
    if isfile and not isfile(path or CONFIG_FILE) then return nil end
    local ok, content = pcall(readfile, path or CONFIG_FILE)
    if not ok or not content then return nil end
    return decodeJSON(content)
end

local function listConfigs()
    local list = {}
    if not listfiles then return list end
    ensureFolder()
    local ok, files = pcall(listfiles, CONFIG_FOLDER)
    if ok and files then
        for _, f in ipairs(files) do
            local name = f:match("([^/\\]+)%.json$")
            if name then insert(list, name) end
        end
    end
    return list
end

do
    local kbSec = makeSection(SettingsTab, "Keybinds")
    local uiKeyBtn
    local function updateUIKeyLabel()
        if uiKeyBtn then pcall(function() uiKeyBtn:SetTitle("UI Keybind: " .. KeybindSystem.UIKeybind.Name) end) end
    end
    uiKeyBtn = kbSec:Button({
        Title = "UI Keybind: " .. KeybindSystem.UIKeybind.Name,
        Justify = "Left", Icon = "keyboard",
        Callback = function()
            captureNewKeybind(function()
                updateUIKeyLabel()
                Notify({ Title = "Keybind", Content = "Nova tecla: " .. KeybindSystem.UIKeybind.Name, Duration = 2, Icon = "check" })
                onConfigChanged()
            end)
        end,
    })
    kbSec:Button({
        Title = "Reset Keybinds", Justify = "Center", Icon = "rotate-ccw",
        Callback = function()
            KeybindSystem.UIKeybind = Enum.KeyCode.LeftShift
            updateUIKeyLabel()
            Notify({ Title = "Keybinds", Content = "Redefinidos para o padrao.", Duration = 2 })
            onConfigChanged()
        end,
    })

    SettingsTab:Space()
    local cfgSec = makeSection(SettingsTab, "Config")
    cfgSec:Button({
        Title = "Save Config", Justify = "Center", Icon = "save",
        Callback = function()
            if saveConfig(CONFIG_FILE) then
                Notify({ Title = "Config", Content = "Salvo com sucesso.", Duration = 2, Icon = "check" })
            else
                Notify({ Title = "Config", Content = "Falha ao salvar.", Duration = 3 })
            end
        end,
    })
    cfgSec:Button({
        Title = "Load Config", Justify = "Center", Icon = "upload",
        Callback = function()
            local cfg = loadConfig(CONFIG_FILE)
            if cfg then applyConfig(cfg); Notify({ Title = "Config", Content = "Carregado.", Duration = 2, Icon = "check" })
            else Notify({ Title = "Config", Content = "Nenhum config salvo.", Duration = 3 }) end
        end,
    })
    cfgSec:Toggle({
        Title = "Auto Save", Default = false,
        Callback = function(v)
            AutoSaveEnabled = v
            Notify({ Title = "Config", Content = v and "Auto Save ON" or "Auto Save OFF", Duration = 2 })
            if v then saveConfig(CONFIG_FILE) end
        end,
    })
    cfgSec:Toggle({
        Title = "Auto Load", Default = false,
        Callback = function(v)
            AutoLoadEnabled = v
            Notify({ Title = "Config", Content = v and "Auto Load ON" or "Auto Load OFF", Duration = 2 })
            if v then local cfg = loadConfig(CONFIG_FILE); if cfg then applyConfig(cfg) end end
            if AutoSaveEnabled then saveConfig(CONFIG_FILE) end
        end,
    })
    cfgSec:Button({
        Title = "Reset Config", Justify = "Center", Icon = "trash-2",
        Callback = function()
            if delfile and isfile and isfile(CONFIG_FILE) then pcall(delfile, CONFIG_FILE) end
            for _, key in ipairs({ "Legs", "Torso", "Head" }) do
                ReachSettings[key].Enabled    = false
                ReachSettings[key].Visualizer = false
                ReachSettings[key].Size       = 1
            end
            GKSettings.Enabled    = false
            GKSettings.Visualizer = false
            GKSettings.Size       = 1
            AutoCatch.Enabled     = false
            AutoCatch.Range       = 50
            AutoCatch.Cooldown    = 0.25
            Follow.Distance       = 0.5
            Follow.PredictTime    = 0.35
            setFollow(false)
            ESPBall           = false
            ESPPrediction     = false
            PredictionTime    = 0.35
            setAutoGoal(false)
            SelectedGoal      = "Goal 1"
            setAimbotGoal(false)
            AimbotGoal.Speed          = 180
            AimbotGoal.Smoothness     = 0.25
            AimbotGoal.DistanceToGoal = 3
            AimbotGoal.DistanceToBall = 8
            setTelekinesis(false)
            Telekinesis.Speed      = 180
            Telekinesis.Smoothness = 0.25
            UpdateESP()
            KeybindSystem.UIKeybind = Enum.KeyCode.LeftShift
            defer(Reach.updateAll, Reach)
            defer(GKReach.updateAll, GKReach)
            Notify({ Title = "Config", Content = "Resetado para o padrao.", Duration = 3 })
        end,
    })

    SettingsTab:Space()
    local mgrSec = makeSection(SettingsTab, "Config Manager")
    local selectedConfig = ""
    pcall(function()
        mgrSec:Input({
            Title = "Nome do Config", Placeholder = "ex: main / pvp / gk",
            Callback = function(text) selectedConfig = text or "" end,
        })
    end)
    mgrSec:Button({
        Title = "Save As (nome acima)", Justify = "Center", Icon = "save",
        Callback = function()
            if selectedConfig == "" then Notify({ Title = "Config Manager", Content = "Digite um nome primeiro.", Duration = 2 }); return end
            local path = CONFIG_FOLDER .. "/" .. selectedConfig .. ".json"
            if saveConfig(path) then Notify({ Title = "Config Manager", Content = "Salvo: " .. selectedConfig, Duration = 2, Icon = "check" })
            else Notify({ Title = "Config Manager", Content = "Falha ao salvar.", Duration = 3 }) end
        end,
    })
    mgrSec:Button({
        Title = "Load (nome acima)", Justify = "Center", Icon = "upload",
        Callback = function()
            if selectedConfig == "" then Notify({ Title = "Config Manager", Content = "Digite um nome primeiro.", Duration = 2 }); return end
            local path = CONFIG_FOLDER .. "/" .. selectedConfig .. ".json"
            local cfg = loadConfig(path)
            if cfg then applyConfig(cfg); Notify({ Title = "Config Manager", Content = "Carregado: " .. selectedConfig, Duration = 2, Icon = "check" })
            else Notify({ Title = "Config Manager", Content = "Nao encontrado.", Duration = 3 }) end
        end,
    })
    mgrSec:Button({
        Title = "List Saved Configs", Justify = "Center", Icon = "list",
        Callback = function()
            local list = listConfigs()
            if #list == 0 then Notify({ Title = "Config Manager", Content = "Nenhum config salvo.", Duration = 3 })
            else Notify({ Title = "Config Manager", Content = table.concat(list, ", "), Duration = 6 }) end
        end,
    })
    mgrSec:Button({
        Title = "Delete (nome acima)", Justify = "Center", Icon = "trash-2",
        Callback = function()
            if selectedConfig == "" then Notify({ Title = "Config Manager", Content = "Digite um nome primeiro.", Duration = 2 }); return end
            local path = CONFIG_FOLDER .. "/" .. selectedConfig .. ".json"
            if delfile and isfile and isfile(path) then
                pcall(delfile, path)
                Notify({ Title = "Config Manager", Content = "Deletado: " .. selectedConfig, Duration = 2 })
            else Notify({ Title = "Config Manager", Content = "Arquivo nao existe.", Duration = 3 }) end
        end,
    })
end

do
    local sec = makeSection(GKTab, "Auto Catch")
    sec:Toggle({
        Title = "Enable Auto Catch", Default = false,
        Callback = function(v)
            AutoCatch.Enabled = v
            if AutoCatch.MobileRefs then
                applyButtonState(AutoCatch.MobileRefs, v, "CATCH\nON", "CATCH\nOFF")
            end
            Notify({ Title = "Auto Catch", Content = v and "Enabled!" or "Disabled!", Duration = 2 })
            onConfigChanged()
        end,
    })
    sec:Slider({ Title = "Catch Distance", Step = 1,
        Value = { Min = 1, Max = 150, Default = 50 },
        Callback = function(v) AutoCatch.Range = v; onConfigChanged() end })
    sec:Slider({ Title = "Cooldown", Step = 0.05,
        Value = { Min = 0.05, Max = 2, Default = 0.25 },
        Callback = function(v) AutoCatch.Cooldown = v; onConfigChanged() end })
    sec:Button({
        Title = "Catch Nearest Ball", Justify = "Center", Icon = "hand",
        Callback = function()
            local ball = getNearestBall()
            if not ball then Notify({ Title = "Auto Catch", Content = "No ball found.", Duration = 2 }); return end
            if fireCatchBall(ball) then
                Notify({ Title = "Auto Catch", Content = "Ball caught!", Duration = 2 })
            else
                Notify({ Title = "Auto Catch", Content = "CatchBall remote missing.", Duration = 3 })
            end
        end,
    })
    sec:Toggle({
        Title = "Show Mobile Button", Default = false,
        Callback = function(v)
            if v then
                local _, refs = createMobileButton("LuaAutoCatchMobile", "CATCH\nOFF", function()
                    AutoCatch.Enabled = not AutoCatch.Enabled
                    if AutoCatch.MobileRefs then
                        applyButtonState(AutoCatch.MobileRefs, AutoCatch.Enabled, "CATCH\nON", "CATCH\nOFF")
                    end
                end)
                AutoCatch.MobileRefs = refs
                if AutoCatch.Enabled then applyButtonState(refs, true, "CATCH\nON", "CATCH\nOFF") end
            else
                destroyMobileButton("LuaAutoCatchMobile")
                AutoCatch.MobileRefs = nil
            end
        end,
    })
end

do
    local sec = makeSection(FollowTab, "Follow Ball")

    sec:Toggle({
        Title = "Enable Follow Ball", Default = false,
        Callback = function(v)
            setFollow(v)
            if Follow.MobileRefs then applyButtonState(Follow.MobileRefs, v, "FOLLOW\nON", "FOLLOW\nOFF") end
            Notify({ Title = "Follow Ball", Content = v and "Enabled!" or "Disabled!", Duration = 2 })
            onConfigChanged()
        end,
    })

    sec:Slider({
        Title = "Stop Distance", Step = 0.5,
        Value = { Min = 0.5, Max = 30, Default = 0.5 },
        Callback = function(v) Follow.Distance = v; onConfigChanged() end,
    })

    sec:Slider({
        Title = "Prediction Time", Step = 0.05,
        Value = { Min = 0.1, Max = 1, Default = 0.35 },
        Callback = function(v) Follow.PredictTime = v; onConfigChanged() end,
    })

    sec:Button({
        Title = "Teleport to Ball", Justify = "Center", Icon = "map-pin",
        Callback = function()
            if not State.HRP then return end
            local ball = getNearestBall()
            if ball then
                State.HRP.CFrame = ball.CFrame + Vector3.new(0, 3, 0)
                Notify({ Title = "Follow", Content = "Teleported!", Duration = 2 })
            else
                Notify({ Title = "Follow", Content = "No ball found.", Duration = 2 })
            end
        end,
    })
end
FollowTab:Space()
FollowTab:Toggle({
    Title = "Show Mobile Button", Default = false,
    Callback = function(v)
        if v then
            local _, refs = createMobileButton("LuaFollowMobile", "FOLLOW\nOFF", function()
                setFollow(not Follow.Enabled)
                if Follow.MobileRefs then
                    applyButtonState(Follow.MobileRefs, Follow.Enabled, "FOLLOW\nON", "FOLLOW\nOFF")
                end
            end)
            Follow.MobileRefs = refs
            if Follow.Enabled then applyButtonState(refs, true, "FOLLOW\nON", "FOLLOW\nOFF") end
        else
            destroyMobileButton("LuaFollowMobile")
            Follow.MobileRefs = nil
        end
    end,
})

defer(function()
    wait_(1.5)
    local cfg = loadConfig(CONFIG_FILE)
    if cfg and cfg.AutoFlags and cfg.AutoFlags.AutoLoad then
        applyConfig(cfg)
        Notify({ Title = "Config", Content = "Auto Load aplicado.", Duration = 3, Icon = "check" })
    end
end)

script.Destroying:Connect(function()
    stopFollow()
    setAutoGoal(false)
    setAimbotGoal(false)
    setTelekinesis(false)
    Reach:clearAll()
    GKReach:clearAll()
    if ESPHighlight then ESPHighlight:Destroy() end
    if ESPLine then pcall(function() ESPLine:Remove() end) end
    if KeybindSystem._conn then KeybindSystem._conn:Disconnect() end
    for name in pairs(MobileButtons.registry) do destroyMobileButton(name) end
end)

Notify({
    Title = "Lua - The Classic",
    Content = "Loaded successfully.",
    Duration = 5,
    Icon = "check",
})