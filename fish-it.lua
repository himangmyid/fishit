-- =====================================================
-- 🧹 BAGIAN 1: CLEANUP SYSTEM
-- =====================================================
if getgenv().fishingStart then
    getgenv().fishingStart = false
    task.wait(0.5)
end

local CoreGui = game:GetService("CoreGui")
local GUI_NAMES = {
    Main = "Mangkuy_Fishing_UI",
    Mobile = "Mangkuy_Mobile_Button",
    Coords = "Mangkuy_Coords_HUD"
}

for _, v in pairs(CoreGui:GetChildren()) do
    for _, name in pairs(GUI_NAMES) do
        if v.Name == name then v:Destroy() end
    end
end

for _, v in pairs(CoreGui:GetDescendants()) do
    if v:IsA("TextLabel") and v.Text == "Mangkuy" then
        
        local container = v
        
        for i = 1, 10 do
            -- Cegah nil edge cases
            if typeof(container) ~= "Instance" then 
                break 
            end

            local parent = container.Parent
            if not parent then 
                break 
            end

            container = parent

            if typeof(container) == "Instance" and container:IsA("ScreenGui") then
                container:Destroy()
                break
            end
        end
    end
end


-- =====================================================
-- 🎣 BAGIAN 2: VARIABEL & REMOTE
-- =====================================================
getgenv().fishingStart = false
local legit = false
local instant = false
local superInstant = true 

local args = { -1.115296483039856, 0, 1763651451.636425 }
local delayTime = 0.56   
local delayCharge = 1.15 
local delayReset = 0.2 

local rs = game:GetService("ReplicatedStorage")
local net = rs.Packages["_Index"]["sleitnick_net@0.2.0"].net

-- Remote Definitions
local ChargeRod    = net["RF/ChargeFishingRod"]
local RequestGame  = net["RF/RequestFishingMinigameStarted"]
local CompleteGame = net["RE/FishingCompleted"]
local CancelInput  = net["RF/CancelFishingInputs"]
local SellAll      = net["RF/SellAllItems"] 
local EquipTank    = net["RF/EquipOxygenTank"]
local UpdateRadar  = net["RF/UpdateFishingRadar"]

local SettingsState = { 
    FPSBoost = { Active = false, BackupLighting = {} }, 
    VFXRemoved = false,
    DestroyerActive = false,
    PopupDestroyed = false,
    AutoSell = {
        TimeActive = false,
        TimeInterval = 60,
        IsSelling = false
    },
    AutoWeather = {
        Active = false,
        Targets = {} 
    },
    PosWatcher = { Active = false, Connection = nil },
    WaterWalk = { Active = false, Part = nil, Connection = nil },
    AnimsDisabled = { Active = false, Connections = {} },
    AutoEventDisco = { Active = false },
    AutoFavorite = {
        Active = false,
        Rarities = {}
    },
}

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local RunService = game:GetService("RunService")

local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

do
    ----------------------------------------------------------------
    -- SERVICES
    ----------------------------------------------------------------
    local RunService = game:GetService("RunService")
    local Players = game:GetService("Players")
    local LP = Players.LocalPlayer

    ----------------------------------------------------------------
    -- CONFIG
    ----------------------------------------------------------------
    local EVENT_HOURS = {
        [0]=true,[2]=true,[4]=true,[6]=true,
        [8]=true,[10]=true,[12]=true,
        [14]=true,[16]=true,[18]=true,
        [20]=true,[22]=true,
    }


    local EVENT_DURATION = 29 * 60 -- 30 menit
    local TARGET_POS = Vector3.new(715, -487, 8910)

    ----------------------------------------------------------------
    -- INTERNAL STATE
    ----------------------------------------------------------------
    local running = false
    local active = false
    local eventStartUTC = 0
    local savedPos = nil
    local uiConn = nil

    ----------------------------------------------------------------
    -- TIME HELPERS (UTC SAFE)
    ----------------------------------------------------------------
    local function NowUTC()
        return os.time(os.date("!*t"))
    end

    local function FormatHMS(sec)
        sec = math.max(0, sec)
        local h = math.floor(sec / 3600)
        local m = math.floor((sec % 3600) / 60)
        local s = sec % 60
        return string.format("%02d:%02d:%02d", h, m, s)
    end

    local function FormatHM(ts, utc)
        local t = os.date(utc and "!*t" or "*t", ts)
        return string.format("%02d:%02d", t.hour, t.min)
    end

    ----------------------------------------------------------------
    -- NEXT EVENT (ABSOLUTE, TERDEKAT)
    ----------------------------------------------------------------
    local function NextEventTs()
        local now = NowUTC()
        local t = os.date("!*t", now)
        local nearest = nil

        -- hari ini (UTC)
        for h in pairs(EVENT_HOURS) do
            local ts = os.time({
                year=t.year, month=t.month, day=t.day,
                hour=h, min=0, sec=0, isdst=false
            })
            if ts > now and (not nearest or ts < nearest) then
                nearest = ts
            end
        end

        -- besok (UTC)
        if not nearest then
            for h in pairs(EVENT_HOURS) do
                local ts = os.time({
                    year=t.year, month=t.month, day=t.day + 1,
                    hour=h, min=0, sec=0, isdst=false
                })
                if not nearest or ts < nearest then
                    nearest = ts
                end
            end
        end

        return nearest
    end

    ----------------------------------------------------------------
    -- TELEPORT UTILS
    ----------------------------------------------------------------
    local function HRP()
        local c = LP.Character
        return c and c:FindFirstChild("HumanoidRootPart")
    end

    local function SafeTP(pos)
        for _ = 1, 5 do
            local hrp = HRP()
            if hrp then
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.CFrame = CFrame.new(pos)
            end
            task.wait(0.08)
        end
    end

    ----------------------------------------------------------------
    -- PUBLIC FUNCTION
    ----------------------------------------------------------------
    function ToggleAutoTimedEvent(state, uiParagraph)
        running = state

        -- OFF
        if not state then
            active = false

            if uiConn then
                uiConn:Disconnect()
                uiConn = nil
            end

            if savedPos then
                SafeTP(savedPos + Vector3.new(0,2,0))
            end

            savedPos = nil
            if uiParagraph then
                uiParagraph:SetDesc("Status: Off")
            end
            return
        end

        -- ON (RenderStepped updater)
        uiConn = RunService.RenderStepped:Connect(function()
            if not running or not uiParagraph then return end

            local nowUTC = NowUTC()
            local nowT = os.date("!*t", nowUTC)

            -- START EVENT (UTC, menit 00)
            if EVENT_HOURS[nowT.hour] and nowT.min == 0 and not active then
                local hrp = HRP()
                if hrp then
                    savedPos = hrp.Position
                end
                active = true
                eventStartUTC = nowUTC
                SafeTP(TARGET_POS + Vector3.new(0,2,0))
            end

            -- STOP EVENT (30 menit)
            if active and (nowUTC - eventStartUTC >= EVENT_DURATION) then
                active = false
                if savedPos then
                    SafeTP(savedPos + Vector3.new(0,2,0))
                end
                savedPos = nil
            end

            -- UI UPDATE (OPSI C)
            if active then
                uiParagraph:SetDesc(
                    "EVENT ACTIVE\nRemaining: " ..
                    FormatHMS(EVENT_DURATION - (nowUTC - eventStartUTC))
                )
            else
                local nextTs = NextEventTs()
                if nextTs then
                    uiParagraph:SetDesc(
                        string.format(
                            "Server : %s\nLocal : %s\nCountdown : %s",
                            FormatHM(nextTs, true),       -- server (UTC)
                            FormatHM(nextTs, false),      -- local
                            FormatHMS(nextTs - nowUTC)    -- countdown
                        )
                    )
                else
                    uiParagraph:SetDesc("Next Event: --:--")
                end
            end
        end)
    end
end


-- ---------------------------------------------------------------------
-- -- GLOBAL EXPORT (untuk SimMode atau script eksternal)
-- ---------------------------------------------------------------------
-- _G.StartAutoDisco = StartAutoDisco
-- _G.StopAutoDisco  = StopAutoDisco

-- print("[AutoDisco v13] Loaded.")



local Waypoints = {
    ["Fisherman Island"]    = Vector3.new(-33, 10, 2770),
    ["Traveling Merchant"]  = Vector3.new(-135, 2, 2764),
    ["Kohana"]              = Vector3.new(-626, 16, 588),
    ["Kohana Lava"]         = Vector3.new(-594, 59, 112),
    ["Esoteric Island"]     = Vector3.new(1991, 6, 1390),
    ["Esoteric Depths"]     = Vector3.new(3240, -1302, 1404),
    ["Tropical Grove"]      = Vector3.new(-2132, 53, 3630),
    ["Coral Reef"]          = Vector3.new(-3138, 4, 2132),
    ["Weather Machine"]     = Vector3.new(-1517, 3, 1910),
    ["Sisyphus Statue"]     = Vector3.new(-3657, -134, -963),
    ["Treasure Room"]       = Vector3.new(-3604, -284, -1632),
    ["Ancient Jungle"]      = Vector3.new(1463, 8, -358),
    ["Ancient Ruin"]        = Vector3.new(6067, -586, 4714),
    ["Sacred Temple"]       = Vector3.new(1476, -22, -632),
    ["Classic Island"]      = Vector3.new(1433, 44, 2755),
    ["Iron Cavern"]         = Vector3.new(-8798, -585, 241),
    ["Iron Cafe"]           = Vector3.new(-8647, -548, 160),
    ["Crater Island"]       = Vector3.new(1070, 2, 5102),
    ["Cristmas Island"]     = Vector3.new(1175, 24, 1558),
    ["Underground Cellar"]     = Vector3.new(2135, -91, -700),
    ["Christmas Cave"]     = Vector3.new(715, -487, 8910),
}

local function TeleportTo(targetPos)
    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
        local HRP = LocalPlayer.Character.HumanoidRootPart
        HRP.AssemblyLinearVelocity = Vector3.new(0,0,0) 
        HRP.CFrame = CFrame.new(targetPos + Vector3.new(0, 3, 0))
    end
end

---------------------------------------------------------
-- AUTO WEATHER — ULTRA LIGHT (FINAL PATCH)
---------------------------------------------------------

task.defer(function()
    print("====== WEATHER SNIFFER ARMED v3 (SAFE) ======")

    local RS = game:GetService("ReplicatedStorage")
    local Replion = require(RS.Packages.Replion)
    local Events = Replion.Client:WaitReplion("Events")

    -- Coba sekali Get("WeatherMachine")
    local ok, result = pcall(function()
        return Events:Get("WeatherMachine")
    end)

    print("[SNIFF] First WeatherMachine value =", ok and result or "ERROR:", result)

    -- Start light polling
    task.spawn(function()
        local lastJson = ""

        while true do
            task.wait(1)

            local current = nil
            local ok2, res2 = pcall(function()
                return Events:Get("WeatherMachine")
            end)

            if ok2 then
                current = res2
            end

            -- Convert ke string buat deteksi perubahan
            local asJson = game:GetService("HttpService"):JSONEncode(current or {})

            if asJson ~= lastJson then
                warn("[SNIFF] WeatherMachine CHANGED →", current)
                lastJson = asJson
            end
        end
    end)
end)
-- ==========================================
-- AUTO WEATHER v4 — Ultra Light + Stable
-- ==========================================

local RS = game:GetService("ReplicatedStorage")
local Replion = require(RS.Packages.Replion)

local EventsReplion = Replion.Client:WaitReplion("Events")

local PurchaseWeather = RS
	:WaitForChild("Packages")
	:WaitForChild("_Index")
	:WaitForChild("sleitnick_net@0.2.0")
	:WaitForChild("net")
	:WaitForChild("RF/PurchaseWeatherEvent")

-- cache connection
local WeatherConn

-- cek apakah weather masih aktif di WeatherMachine
local function IsWeatherActive(name)
	local list = EventsReplion:Get("WeatherMachine")
	if not list then return false end

	for _, v in ipairs(list) do
		if v == name then
			return true
		end
	end
	return false
end

-- beli ulang jika cuaca habis
local function WeatherUpdated()
	local selected = SettingsState.AutoWeather.SelectedList
	if not selected then return end

	local activeList = EventsReplion:Get("WeatherMachine") or {}

	for _, weather in ipairs(selected) do
		if not IsWeatherActive(weather) then
			warn("[AUTO WEATHER] Purchasing:", weather)
			pcall(function()
				PurchaseWeather:InvokeServer(weather)
			end)
			task.wait(0.2)
		end
	end
end

-- start mode
function StartAutoWeather()
	if not SettingsState.AutoWeather.Active then return end

	warn("===== WEATHER SNIFFER ARMED v4 =====")

	-- disconnect old
	if WeatherConn then
		WeatherConn:Disconnect()
	end

	-- listen perubahan state replion WeatherMachine
	WeatherConn = EventsReplion:OnChange("WeatherMachine", function(newValue)
		warn("[SNIFF] WeatherMachine Changed =", newValue)
		task.defer(WeatherUpdated)
	end)

	-- initial scan
	task.defer(WeatherUpdated)
end

-- stop mode
function StopAutoWeather()
	if WeatherConn then
		WeatherConn:Disconnect()
		WeatherConn = nil
	end

	warn("[AUTO WEATHER] Disabled")
end

-- =====================================================
-- 💰 BAGIAN 4: AUTO SELL
-- =====================================================
local function StartAutoSellLoop()
    task.spawn(function()
        print("💰 Auto Sell: BACKGROUND MODE STARTED")
        while SettingsState.AutoSell.TimeActive do
            for i = 1, SettingsState.AutoSell.TimeInterval do
                if not SettingsState.AutoSell.TimeActive then return end
                task.wait(1)
            end
            task.spawn(function()
                pcall(function() SellAll:InvokeServer() end)
            end)
        end
    end)
end

-- =====================================================
-- 🎣 BAGIAN 5: LOGIKA FISHING (TURBO)
-- =====================================================
local function startFishingLoop()
    local _Cancel = CancelInput
    print("🎣 Standard Loop")
    while getgenv().fishingStart do
        game:GetService("ReplicatedStorage"):WaitForChild("Packages"):WaitForChild("_Index"):WaitForChild("sleitnick_net@0.2.0"):WaitForChild("net"):WaitForChild("RF/ChargeFishingRod"):InvokeServer()
        -- task.wait(delayCharge)
        if not getgenv().fishingStart then break end
        
        game:GetService("ReplicatedStorage"):WaitForChild("Packages"):WaitForChild("_Index"):WaitForChild("sleitnick_net@0.2.0"):WaitForChild("net"):WaitForChild("RF/RequestFishingMinigameStarted"):InvokeServer(unpack(args))
        task.wait(delayTime)
        if not getgenv().fishingStart then break end 
        
        game:GetService("ReplicatedStorage"):WaitForChild("Packages"):WaitForChild("_Index"):WaitForChild("sleitnick_net@0.2.0"):WaitForChild("net"):WaitForChild("RE/FishingCompleted"):FireServer()
        
        -- task.wait(1)
        -- game:GetService("ReplicatedStorage"):WaitForChild("Packages"):WaitForChild("_Index"):WaitForChild("sleitnick_net@0.2.0"):WaitForChild("net"):WaitForChild("RE/FishingStopped"):FireServer()
        task.wait(0.05)
        pcall(function() _Cancel:InvokeServer() end)
    end
end

local function startFishingSuperInstantLoop()
    print("⚡ TURBO Loop Started")
    local _Charge = ChargeRod
    local _Request = RequestGame
    local _Complete = CompleteGame
    local _Cancel = CancelInput
    while getgenv().fishingStart do
        pcall(function() _Cancel:InvokeServer() end)
        task.wait(0.055)
        task.spawn(function() pcall(function() _Charge:InvokeServer() end) end)
        task.wait(0.055)
        task.spawn(function() pcall(function() _Request:InvokeServer(unpack(args)) end) end)
        task.wait(delayCharge) 
        pcall(function() _Complete:FireServer() end)
        task.wait(delayReset) 
        pcall(function() _Cancel:InvokeServer() end)
        task.wait(0.055)
    end
    print("🛑 TURBO Loop Stopped")
end

local function resetCharacter()
    local _Complete = CompleteGame
    local _Cancel = CancelInput
    pcall(function() _Complete:FireServer() end)
    task.wait(0.05) 
    pcall(function() _Cancel:InvokeServer() end)
end

-- =====================================================
-- ⚙️ BAGIAN 6: FITUR LAIN
-- =====================================================
local function ToggleFPSBoost(state)
    if state then
        pcall(function()
            settings().Rendering.QualityLevel = 1
            game:GetService("Lighting").GlobalShadows = false
        end)
        for _, v in pairs(game:GetDescendants()) do
            if v:IsA("BasePart") then v.Material = Enum.Material.Plastic; v.CastShadow = false end
        end
    end
end

local function ExecuteRemoveVFX()
    local function KillVFX(obj)
        if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") then
            obj.Enabled = false
            obj.Transparency = NumberSequence.new(1)
        elseif obj:IsA("Explosion") then obj.Visible = false end
    end
    for _, v in pairs(game:GetDescendants()) do pcall(function() KillVFX(v) end) end
    workspace.DescendantAdded:Connect(function(child)
        task.wait()
        pcall(function() 
            KillVFX(child) 
            for _, gc in pairs(child:GetDescendants()) do KillVFX(gc) end 
        end)
    end)
end

local function ExecuteDestroyPopup()
    local target = PlayerGui:FindFirstChild("Small Notification")
    if target then target:Destroy() end
    PlayerGui.ChildAdded:Connect(function(child)
        if child.Name == "Small Notification" then
            task.wait() 
            child:Destroy()
        end
    end)
end

local function StartAntiAFK()
    local VirtualUser = game:GetService("VirtualUser")
    if getconnections then
        for _, conn in pairs(getconnections(LocalPlayer.Idled)) do
            if conn.Disable then conn:Disable() elseif conn.Disconnect then conn:Disconnect() end
        end
    end
    pcall(function()
        LocalPlayer.Idled:Connect(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end)
end

local function ToggleWaterWalk(state)
    if state then
        local p = Instance.new("Part")
        p.Name = "Mangkuy_WaterPlatform"
        p.Anchored = true
        p.CanCollide = true
        p.Transparency = 1
        p.Size = Vector3.new(15, 1, 15)
        p.Parent = Workspace
        SettingsState.WaterWalk.Part = p

        SettingsState.WaterWalk.Connection = RunService.Heartbeat:Connect(function()
            local Char = Players.LocalPlayer.Character
            if Char and Char:FindFirstChild("HumanoidRootPart") and SettingsState.WaterWalk.Part then
                local hrpPos = Char.HumanoidRootPart.Position
                SettingsState.WaterWalk.Part.CFrame = CFrame.new(hrpPos.X, -3.1, hrpPos.Z)
            end
        end)
    else
        if SettingsState.WaterWalk.Connection then 
            SettingsState.WaterWalk.Connection:Disconnect() 
            SettingsState.WaterWalk.Connection = nil
        end
        if SettingsState.WaterWalk.Part then 
            SettingsState.WaterWalk.Part:Destroy() 
            SettingsState.WaterWalk.Part = nil
        end
    end
end

local function ToggleAnims(state)
    SettingsState.AnimsDisabled.Active = state
    
    local function StopAll()
        local Char = Players.LocalPlayer.Character
        if Char and Char:FindFirstChild("Humanoid") then
            local Hum = Char.Humanoid
            local Animator = Hum:FindFirstChild("Animator")
            if Animator then
                for _, track in pairs(Animator:GetPlayingAnimationTracks()) do
                    track:Stop()
                end
            end
        end
    end

    if state then
        StopAll()
        local function HookChar(char)
            local hum = char:WaitForChild("Humanoid")
            local animator = hum:WaitForChild("Animator")
            local conn = animator.AnimationPlayed:Connect(function(track)
                if SettingsState.AnimsDisabled.Active then track:Stop() end
            end)
            table.insert(SettingsState.AnimsDisabled.Connections, conn)
        end

        if Players.LocalPlayer.Character then HookChar(Players.LocalPlayer.Character) end
        local conn2 = Players.LocalPlayer.CharacterAdded:Connect(HookChar)
        table.insert(SettingsState.AnimsDisabled.Connections, conn2)
    else
        for _, conn in pairs(SettingsState.AnimsDisabled.Connections) do
            conn:Disconnect()
        end
        SettingsState.AnimsDisabled.Connections = {}
    end
end

-- ============================================================
-- 🎣 AUTO FAVORITE v7 — HYBRID WITH PROPER ON/OFF CONTROL
-- ============================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Replion = require(ReplicatedStorage.Packages.Replion)
local Data = Replion.Client:WaitReplion("Data")

-- Remote
local FavoriteItem = ReplicatedStorage
	:WaitForChild("Packages")
	:WaitForChild("_Index")
	:WaitForChild("sleitnick_net@0.2.0")
	:WaitForChild("net")
	:WaitForChild("RE/FavoriteItem")
	-- :WaitForChild("")

-------------------------------------------------------
-- Load FishDB
-------------------------------------------------------
local FishDB = {}
for _, module in ipairs(ReplicatedStorage.Items:GetChildren()) do
	if module:IsA("ModuleScript") then
		local ok, mod = pcall(require, module)
		if ok and mod and mod.Data and mod.Data.Type == "Fish" then
			FishDB[mod.Data.Id] = mod.Data.Tier
		end
	end
end
warn("[AFv7] FishDB Loaded:", #FishDB)

local function GetTier(id)
	return FishDB[id]
end

-------------------------------------------------------
-- Selected Tier
-------------------------------------------------------
local SelectedTier = {}

function SetSelectedRarities(list)
	SelectedTier = {}

	local map = {
		Common = 1, Uncommon = 2, Rare = 3, Epic = 4,
		Legendary = 5, Mythic = 6, Secret = 7,
		Exotic = 8, Azure = 9
	}

	for _, rarity in ipairs(list) do
		local tier = map[rarity]
		if tier then SelectedTier[tier] = true end
	end

	warn("[AFv7] Selected Tier Updated:", SelectedTier)
end

-------------------------------------------------------
-- FAVORITE LOGIC
-------------------------------------------------------
local KnownUUID = {}

local function FavoriteIfMatch(item)
	if not item then return end
	local uuid = item.UUID
	if KnownUUID[uuid] then return end

	local id = item.Id
	local fav = item.Favorited
	local tier = GetTier(id)

	if tier and SelectedTier[tier] and not fav then
		warn("[AFv7] Favoriting:", uuid, "Tier:", tier)
		pcall(function()
			FavoriteItem:FireServer(uuid)
		end)
	end

	KnownUUID[uuid] = true
end

local function InitialScan()
	local inv = Data:Get("Inventory")
	if inv and inv.Items then
		warn("[AFv7] InitialScan...")
		for _, item in pairs(inv.Items) do
			FavoriteIfMatch(item)
		end
	end
end

-------------------------------------------------------
-- EVENT CONTROL (ON / OFF)
-------------------------------------------------------
-- local InventoryConnection = nil  
local newFishConnection = nil
local AutoFavActive = false
local ObtainedNewFish = net["RE/ObtainedNewFishNotification"]

local function StartAutoFavorite()
	if SettingsState.AutoFavActive then return end
	warn("[AFv7] Auto Favorite ENABLED")

     -- FIX: RESET CACHE SETIAP DI-ON
    KnownUUID = {}

	-- initial scan once
	InitialScan()

	-- attach event
    newFishConnection = ObtainedNewFish.OnClientEvent:Connect(function(...)
        if not SettingsState.AutoFavorite.Active then return end

        warn("[AFv7] New fish obtained → scanning...")

        task.defer(function()
            local inv = Data:Get("Inventory")
            if not inv or not inv.Items then return end

            for _, item in pairs(inv.Items) do
                FavoriteIfMatch(item)
            end
        end)
    end)
end

local function StopAutoFavorite()
	if not AutoFavActive then return end
	AutoFavActive = false
	warn("[AFv7] Auto Favorite DISABLED")
    if newFishConnection then
        newFishConnection:Disconnect()
        newFishConnection = nil
    end

     -- FIX: RESET CACHE SETIAP DI-ON
    KnownUUID = {}
end

-------------------------------------------------------
-- UI toggle wrapper
-------------------------------------------------------
function ToggleAutoFavorite(state)
	if state then StartAutoFavorite()
	else StopAutoFavorite() end
end


local function SetSelectedRarities(list)
    SelectedTier = {}
    for _, rarityName in ipairs(list) do
        local map = {
            Common = 1,
            Uncommon = 2,
            Rare = 3,
            Epic = 4,
            Legendary = 5,
            Mythic = 6,
            Secret = 7,
        }

        local tier = map[rarityName]
        if tier then SelectedTier[tier] = true end
    end
end

-- =====================================================
-- 🌌 BAGIAN 7: TELEPORT UTILS
-- =====================================================
local function TeleportToMegalodon()
    local ringsFolder = Workspace:FindFirstChild("!!! MENU RINGS")
    if not ringsFolder then return end
    local propsFolder = ringsFolder:FindFirstChild("Props")
    if not propsFolder then return end
    local eventModel = propsFolder:FindFirstChild("Megalodon Hunt")
    
    if eventModel then
        local topPart = eventModel:FindFirstChild("Top")
        if topPart and topPart:FindFirstChild("BlackHole") then
            TeleportTo(topPart.BlackHole.Position + Vector3.new(0, 20, 0))
        else
            TeleportTo(eventModel:GetPivot().Position)
        end
    end
end

local CoordDisplay = nil 
local LivePosToggle = nil 

local function TogglePosWatcher(state)
    SettingsState.PosWatcher.Active = state
    if state then
        SettingsState.PosWatcher.Connection = RunService.RenderStepped:Connect(function()
            local Char = Players.LocalPlayer.Character
            if Char and Char:FindFirstChild("HumanoidRootPart") then
                local pos = Char.HumanoidRootPart.Position
                local txt = string.format("X: %.1f | Y: %.1f | Z: %.1f", pos.X, pos.Y, pos.Z)
                if CoordDisplay then pcall(function() CoordDisplay:SetDesc(txt) end) end
                if LivePosToggle then pcall(function() LivePosToggle:SetDesc(txt) end) end
            end
        end)
    else
        if SettingsState.PosWatcher.Connection then SettingsState.PosWatcher.Connection:Disconnect() end
        if CoordDisplay then pcall(function() CoordDisplay:SetDesc("Status: Off") end) end
        if LivePosToggle then pcall(function() LivePosToggle:SetDesc("Click to show coordinates") end) end
    end
end

local function FindPlayer(name)
    name = string.lower(name)
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            if string.find(string.lower(p.Name), name) or string.find(string.lower(p.DisplayName), name) then
                return p
            end
        end
    end
    return nil
end
local function GetPlayerList()
    local names = {}
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then table.insert(names, p.Name) end
    end
    table.sort(names)
    return names
end

local zoneNames = {}
for name, _ in pairs(Waypoints) do table.insert(zoneNames, name) end
table.sort(zoneNames)

-- =====================================================
-- 🎭 NAME SPOOFER (OVERHEAD HEADER BASED)
-- =====================================================
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local NameSpoof = {
	Active = false,
	FakeName = "",
	OriginalText = nil,
	Label = nil,
	CharConn = nil
}

local function GetNameLabel()
	local char = LocalPlayer.Character
	if not char then return nil end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end

	local overhead = hrp:FindFirstChild("Overhead")
	if not overhead then return nil end

	local content = overhead:FindFirstChild("Content")
	if not content then return nil end

	local header = content:FindFirstChild("Header")
	if header and header:IsA("TextLabel") then
		return header
	end

	return nil
end

local function ApplyNameSpoof()
	if not NameSpoof.Active or NameSpoof.FakeName == "" then return end

	local label = GetNameLabel()
	if not label then return end

	if not NameSpoof.OriginalText then
		NameSpoof.OriginalText = label.Text
	end

	NameSpoof.Label = label
	label.Text = NameSpoof.FakeName
end

local function RestoreName()
	if NameSpoof.Label and NameSpoof.OriginalText then
		NameSpoof.Label.Text = NameSpoof.OriginalText
	end

	NameSpoof.OriginalText = nil
	NameSpoof.Label = nil
end


local function EnableNameSpoof()
	if NameSpoof.Active or NameSpoof.FakeName == "" then return end
	NameSpoof.Active = true

	ApplyNameSpoof()

	NameSpoof.CharConn = LocalPlayer.CharacterAdded:Connect(function()
		task.wait(0.3)
		ApplyNameSpoof()
	end)
end

local function DisableNameSpoof()
	if not NameSpoof.Active then return end
	NameSpoof.Active = false

	if NameSpoof.CharConn then
		NameSpoof.CharConn:Disconnect()
		NameSpoof.CharConn = nil
	end

	RestoreName()
end

-- -- =====================================================
-- -- 🎣 HOLY TRIDENT FULL ANIMATION OVERRIDE (NO CONFLICT)
-- -- Replace ALL animations with Holy Trident set
-- -- =====================================================

-- local Players = game:GetService("Players")
-- local LP = Players.LocalPlayer

-- -------------------------------------------------------
-- -- STATE
-- -------------------------------------------------------
-- local State = {
--     Enabled = false,
--     Index = 1
-- }

-- -------------------------------------------------------
-- -- HOLY TRIDENT ANIMATION SET (OFFICIAL ASSET)
-- -------------------------------------------------------
-- local HOLY_TRIDENT_ANIMS = {
--     "rbxassetid://114917462794864",  -- RodThrow
--     "rbxassetid://83219020397849",   -- StartRodCharge / EquipIdle
--     "rbxassetid://12683185389724",   -- ReelStart / ReelIdle / Intermission
--     "rbxassetid://1128167068291703", -- FishCaught
-- }

-- -------------------------------------------------------
-- -- CORE OVERRIDE
-- -------------------------------------------------------
-- local function HookAnimator(char)
--     local hum = char:WaitForChild("Humanoid")
--     local animator = hum:WaitForChild("Animator")

--     animator.AnimationPlayed:Connect(function(track)
--         if not State.Enabled then return end

--         -- hentikan animasi asli
--         track:Stop()

--         -- rotate holy anim
--         State.Index = State.Index + 1
--         if State.Index > #HOLY_TRIDENT_ANIMS then
--             State.Index = 1
--         end

--         local anim = track.Animation
--         anim.AnimationId = HOLY_TRIDENT_ANIMS[State.Index]

--         local newTrack = animator:LoadAnimation(anim)
--         newTrack.Priority = track.Priority -- jaga priority
--         newTrack:Play()
--     end)
-- end

-- -------------------------------------------------------
-- -- PUBLIC API
-- -------------------------------------------------------
-- function EnableHolyFullOverride()
--     State.Enabled = true
--     warn("[HolyFullOverride] ENABLED")
-- end

-- function DisableHolyFullOverride()
--     State.Enabled = false
--     warn("[HolyFullOverride] DISABLED")
-- end

-- -------------------------------------------------------
-- -- INIT
-- -------------------------------------------------------
-- if LP.Character then
--     HookAnimator(LP.Character)
-- end

-- LP.CharacterAdded:Connect(HookAnimator)


---------------------------------------------------------------------
-- 🎣 FISH WEBHOOK LOGGER (FINAL - STATIC RARITY SOURCE)
---------------------------------------------------------------------

-------------------------------------------------------
-- CONFIG
-------------------------------------------------------
local DEBUG = false -- set false kalau sudah beres

-------------------------------------------------------
-- SERVICES
-------------------------------------------------------
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService       = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local net = ReplicatedStorage.Packages["_Index"]["sleitnick_net@0.2.0"].net

-------------------------------------------------------
-- DEBUG LOGGER
-------------------------------------------------------
local function dlog(...)
	if DEBUG then
		warn("[WEBHOOK][DEBUG]", ...)
	end
end

-------------------------------------------------------
-- STATE
-------------------------------------------------------
SettingsState.WebhookFish = {
	Active = false,
	Url = "",
	SentUUID = {},
	SelectedRarities = {} -- [tier] = true
}

-------------------------------------------------------
-- EXECUTOR HTTP
-------------------------------------------------------
local HttpRequest =
	syn and syn.request
	or http_request
	or request
	or (fluxus and fluxus.request)
	or (krnl and krnl.request)

if not HttpRequest then
	warn("[WEBHOOK][FATAL] HttpRequest not available in this executor")
end

-------------------------------------------------------
-- RARITY MAP
-------------------------------------------------------
local RARITY_MAP = {
	[1] = "Common",
	[2] = "Uncommon",
	[3] = "Rare",
	[4] = "Epic",
	[5] = "Legendary",
	[6] = "Mythic",
	[7] = "Secret",
}

-------------------------------------------------------
-- NAME → TIER (UI)
-------------------------------------------------------
local RARITY_NAME_TO_TIER = {
	Common = 1,
	Uncommon = 2,
	Rare = 3,
	Epic = 4,
	Legendary = 5,
	Mythic = 6,
	Secret = 7,
}

-------------------------------------------------------
-- COLOR + GRADIENT
-------------------------------------------------------
local RARITY_COLOR = {
	[1] = 0x9e9e9e,
	[2] = 0x4caf50,
	[3] = 0x2196f3,
	[4] = 0x9c27b0,
	[5] = 0xff9800,
	[6] = 0xf44336,
	[7] = 0xff1744,
}

local RARITY_GRADIENT = {
	[1] = "⚪🔺",
	[2] = "🟢🔺",
	[3] = "🔵🔺",
	[4] = "🟣🔺",
	[5] = "🟠🔺",
	[6] = "🔴🔺",
	[7] = "⚫🔺",
}


-------------------------------------------------------
-- FISH DATABASE (STATIC SOURCE OF TRUTH)
-------------------------------------------------------
local FishDB = {}

for _, module in ipairs(ReplicatedStorage.Items:GetChildren()) do
	if module:IsA("ModuleScript") then
		local ok, mod = pcall(require, module)
		if ok and mod and mod.Data and mod.Data.Type == "Fish" then
			FishDB[mod.Data.Id] = {
				Name = mod.Data.Name,
				Tier = mod.Data.Tier,
				Icon = mod.Data.Icon
			}
		end
	end
end

-------------------------------------------------------
-- ICON CACHE (EVENT DRIVEN)
-------------------------------------------------------
local IconCache  = {}
local IconWaiter = {}

-------------------------------------------------------
-- FETCH ICON
-------------------------------------------------------
local function FetchFishIconAsync(fishId, onReady)
	if IconCache[fishId] then
		onReady(IconCache[fishId])
		return
	end

	if IconWaiter[fishId] then
		table.insert(IconWaiter[fishId], onReady)
		return
	end

	IconWaiter[fishId] = { onReady }

	task.spawn(function()
		local fish = FishDB[fishId]
		if not fish or not fish.Icon then
			dlog("No icon for fishId", fishId)
			return
		end

		local assetId = tostring(fish.Icon):match("%d+")
		if not assetId then return end

		local api =
			("https://thumbnails.roblox.com/v1/assets?assetIds=%s&size=420x420&format=Png&isCircular=false")
			:format(assetId)

		local res = HttpRequest({ Url = api, Method = "GET" })
		if not res or not res.Body then
			dlog("Icon fetch failed")
			return
		end

		local ok, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
		if not ok then return end

		local imageUrl =
			data and data.data and data.data[1] and data.data[1].imageUrl

		if not imageUrl then return end

		IconCache[fishId] = imageUrl
		dlog("Icon cached for", fishId)

		for _, cb in ipairs(IconWaiter[fishId]) do
			cb(imageUrl)
		end
		IconWaiter[fishId] = nil
	end)
end

-------------------------------------------------------
-- STRICT STATIC RARITY FILTER
-------------------------------------------------------
local function IsRarityAllowedById(fishId)
	local fish = FishDB[fishId]
	if not fish then
		dlog("BLOCK: fish not in DB", fishId)
		return false
	end

	local tier = fish.Tier
	if type(tier) ~= "number" then
		dlog("BLOCK: invalid tier for", fishId)
		return false
	end

	local selected = SettingsState.WebhookFish.SelectedRarities

	if next(selected) == nil then
		dlog("ALLOW: no filter selected")
		return true
	end

	if selected[tier] then
		dlog("ALLOW: tier", tier, "matched")
		return true
	end

	dlog("BLOCK: tier", tier, "not selected")
	return false
end

-------------------------------------------------------
-- BUILD PAYLOAD
-------------------------------------------------------
local function BuildFishPayload(player, fishId, weight)
	local fish = FishDB[fishId]
	local tier = fish.Tier

	return {
		username = "Mangkuy Fishing Log",
		embeds = {{
			title = (RARITY_GRADIENT[tier] or "") .. " 🎣 Fish Obtained",
			color = RARITY_COLOR[tier],
			fields = {
				{ name = "Player", value = player, inline = true },
				{ name = "Fish", value = fish.Name, inline = true },
				{ name = "Rarity", value = RARITY_MAP[tier], inline = true },
				{ name = "Weight", value = string.format("%.2f kg", weight or 0), inline = true },
			},
			thumbnail = { url = IconCache[fishId] },
			timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
		}}
	}
end

-------------------------------------------------------
-- SEND WEBHOOK (HARD DEBUG)
-------------------------------------------------------
local function SendWebhook(payload)
	if not SettingsState.WebhookFish.Active then
		dlog("Webhook inactive")
		return
	end

	if SettingsState.WebhookFish.Url == "" then
		dlog("Webhook URL empty")
		return
	end

	dlog("Sending webhook...")

	local res = HttpRequest({
		Url = SettingsState.WebhookFish.Url,
		Method = "POST",
		Headers = { ["Content-Type"] = "application/json" },
		Body = HttpService:JSONEncode(payload)
	})

	if not res then
		dlog("No response from HttpRequest")
		return
	end

	dlog("Response:", res.StatusCode, res.Success)
end

-------------------------------------------------------
-- EVENT HANDLER (FINAL)
-------------------------------------------------------
local ObtainedNewFish = net["RE/ObtainedNewFishNotification"]

ObtainedNewFish.OnClientEvent:Connect(function(_, weightData, wrapper)
	dlog("Event fired")

	if not SettingsState.WebhookFish.Active then return end
	if not wrapper or not wrapper.InventoryItem then return end

	local item = wrapper.InventoryItem
	if not item.Id or not item.UUID then return end

	if not IsRarityAllowedById(item.Id) then
		dlog("Event blocked by rarity filter")
		return
	end

	if SettingsState.WebhookFish.SentUUID[item.UUID] then
		dlog("Duplicate UUID")
		return
	end

	SettingsState.WebhookFish.SentUUID[item.UUID] = true

	FetchFishIconAsync(item.Id, function()
		SendWebhook(
			BuildFishPayload(
				LocalPlayer.Name,
				item.Id,
				weightData and weightData.Weight or 0
			)
		)
	end)
end)

-------------------------------------------------------
-- CONTROLLER
-------------------------------------------------------
local function StartFishWebhook()
	if SettingsState.WebhookFish.Active then return end
	if SettingsState.WebhookFish.Url == "" then
		WindUI:Notify({ Title = "Webhook", Content = "Webhook URL belum diisi", Duration = 2 })
		return
	end

	SettingsState.WebhookFish.Active = true
	SettingsState.WebhookFish.SentUUID = {}
	warn("[WEBHOOK] ENABLED")
end

local function StopFishWebhook()
	if not SettingsState.WebhookFish.Active then return end
	SettingsState.WebhookFish.Active = false
	SettingsState.WebhookFish.SentUUID = {}
	warn("[WEBHOOK] DISABLED")
end


-- =====================================================
-- 🎨 BAGIAN 8: WIND UI SETUP
-- =====================================================
local function setElementVisible(name, visible)
    task.spawn(function()
        local CoreGui = game:GetService("CoreGui")
        for _, v in pairs(CoreGui:GetDescendants()) do
            if v:IsA("TextLabel") and v.Text == name then
                local current = v
                for i = 1, 6 do
                    if current.Parent then
                        current = current.Parent
                        if current.Parent:IsA("ScrollingFrame") then
                            current.Visible = visible
                            break 
                        end
                    end
                end
                pcall(function()
                    if v.Parent.Parent:IsA("Frame") and v.Parent.Parent.Name ~= "Content" then v.Parent.Parent.Visible = visible end
                    if v.Parent.Parent.Parent:IsA("Frame") then v.Parent.Parent.Parent.Visible = visible end
                end)
                break 
            end
        end
    end)
end

local Window = WindUI:CreateWindow({ Title = "Mangkuy", Icon = "https://raw.githubusercontent.com/himangmyid/fishit/refs/heads/main/3.png", Author = "by Himang.my.id", Transparent = true })
Window.Name = GUI_NAMES.Main 
Window:Tag({ Title = "V.Beta", Icon = "github", Color = Color3.fromHex("#30ff6a"), Radius = 0 })
Window:SetToggleKey(Enum.KeyCode.H)

local TabPlayer = Window:Tab({ Title = "Player Setting", Icon = "https://cdn4.vectorstock.com/i/1000x1000/09/78/user-neon-label-vector-28270978.jpg" })
local TabFishing = Window:Tab({ Title = "Auto Fishing", Icon = "https://img.freepik.com/vetores-premium/rotulo-de-neon-de-pesca_520826-7042.jpg" })
local TabFavorite = Window:Tab({ Title = "Auto Favorite", Icon = "https://media.istockphoto.com/id/1203142341/id/vektor/bingkai-bintang-neon-atau-tanda-lampu-neon-latar-belakang-abstrak-vektor-terowongan-portal.jpg?s=170667a&w=0&k=20&c=u7ezrDeSrsbH8YZJJr_78blNJqRguy4ZgImjBJAu3Sk=" })
local TabSell = Window:Tab({ Title = "Auto Sell", Icon = "https://images.rawpixel.com/image_social_square/cHJpdmF0ZS9sci9pbWFnZXMvd2Vic2l0ZS8yMDI0LTA0L3Jhd3BpeGVsX29mZmljZV81Ml9zaW1wbGVfbGluZV9uZW9uX29mX3RyYXZlbF9pY29uX2luX3RoZV9zdHlsZV9iZDQ1Mzg0Ny02MjkwLTRhM2YtOWFjZS1mMGVhNGJlZTdlOTJfMS5qcGc.jpg" })
local TabWeather = Window:Tab({ Title = "Weather", Icon = "https://cdn2.vectorstock.com/i/1000x1000/10/86/glowing-neon-line-cloud-with-snow-rain-and-sun-vector-37061086.jpg" })
local TabTeleport = Window:Tab({ Title = "Teleport", Icon = "https://tse4.mm.bing.net/th/id/OIP.1o3a96woCe-17zoHNYeroAHaHa?w=626&h=626&rs=1&pid=ImgDetMain&o=7&rm=3" })
local TabWebHook = Window:Tab({ Title = "Webhook", Icon = "https://i.pinimg.com/originals/45/fc/04/45fc047a4d037ea0e090b341a46ff4e9.jpg" })
local TabSettings = Window:Tab({ Title = "Settings", Icon = "https://media.istockphoto.com/vectors/glowing-neon-circular-saw-blade-icon-isolated-on-blue-background-saw-vector-id1223024883?k=6&m=1223024883&s=612x612&w=0&h=_4-y7Z20qgE6ImyY4bDDSZDRqhvSKHNabZsHdvp8sWM=" })

-- [[ TAB PLAYER: UTILITIES ]]
TabPlayer:Section({ Title = "Hide Name" })
TabPlayer:Input({
	Title = "Fake Name",
	Desc = "Visual only (level safe)",
	Placeholder = "Input fake name",
	Callback = function(text)
		NameSpoof.FakeName = tostring(text):gsub("^%s+", ""):gsub("%s+$", "")
	end
})

TabPlayer:Toggle({
	Title = "Spoof Player Name",
	Desc = "Only name, level untouched",
	Icon = "user-check",
	Value = false,
	Callback = function(state)
		if state then
			EnableNameSpoof()
			WindUI:Notify({ Title = "Name Spoof", Content = "Enabled", Duration = 2 })
		else
			DisableNameSpoof()
			WindUI:Notify({ Title = "Name Spoof", Content = "Restored", Duration = 2 })
		end
	end
})

-- TabFishing:Toggle({
--     Title = "Holy Trident Full Anim",
--     Desc = "Replace all fishing animations",
--     Icon = "zap",
--     Value = false,
--     Callback = function(state)
--         if state then
--             EnableHolyFullOverride()
--         else
--             DisableHolyFullOverride()
--         end
--     end
-- })


TabPlayer:Section({ Title = "Players Feature" })
TabPlayer:Toggle({ Title = "Walk on Water", Desc = "Creates a platform below you", Icon = "waves", Value = false, Callback = function(state) ToggleWaterWalk(state); WindUI:Notify({Title = "Movement", Content = state and "Water Walk ON" or "Water Walk OFF", Duration = 2}) end })
TabPlayer:Toggle({ Title = "Disable Animation", Desc = "Stop character anims (T-Pose)", Icon = "user-x", Value = false, Callback = function(state) ToggleAnims(state); WindUI:Notify({Title = "Player", Content = state and "Animations Disabled" or "Animations Enabled", Duration = 2}) end })

TabPlayer:Section({ Title = "Equipment" })
TabPlayer:Toggle({ Title = "Equip Diving Gear", Desc = "Toggle Oxygen Tank (105)", Icon = "anchor", Value = false, Callback = function(state) if state then pcall(function() EquipTank:InvokeServer(105) end); WindUI:Notify({Title = "Item", Content = "Diving Gear Equipped", Duration = 2}) else local Char = Players.LocalPlayer.Character; local Backpack = Players.LocalPlayer.Backpack; if Char then for _, t in pairs(Char:GetChildren()) do if t:IsA("Tool") and (string.find(t.Name, "Oxygen") or string.find(t.Name, "Tank") or string.find(t.Name, "Diving")) then t.Parent = Backpack end end end; WindUI:Notify({Title = "Item", Content = "Diving Gear Unequipped", Duration = 2}) end end })
TabPlayer:Toggle({ Title = "Equip Radar", Desc = "Toggle Fishing Radar", Icon = "radar", Value = false, Callback = function(state) pcall(function() UpdateRadar:InvokeServer(state) end); WindUI:Notify({Title = "Item", Content = state and "Radar ON" or "Radar OFF", Duration = 2}) end })

-- [[ TAB 1: FISHING ]]


TabFishing:Dropdown({ Title = "Category Fishing", Desc = "Select Mode", Values = {"Instant", "Blatan"}, Value = "Instant", Callback = function(option) instant, superInstant = (option == "Instant"), (option == "Blatan"); setElementVisible("Delay Fishing", false); setElementVisible("Delay Catch", false); setElementVisible("Reset Delay", false); if instant then setElementVisible("Delay Catch", true) elseif superInstant then setElementVisible("Delay Fishing", true); setElementVisible("Reset Delay", true) end end })
TabFishing:Input({
    Title = "Delay Fishing",
    Desc = "Wait Fish (Blatan)",
    Value = "1.30",
    Callback = function(text)
        if not text:match("^%d*%.?%d+$") then
            delayCharge = 1.30
            return "1.30"
        end

        local num = tonumber(text)
        if not num then
            delayCharge = 1.30
            return "1.30"
        end

        delayCharge = math.clamp(num, 0, 3)
        return tostring(delayCharge)
    end
})

TabFishing:Input({
    Title = "Reset Delay",
    Desc = "After Catch (Blatan)",
    Value = "0.20",
    Callback = function(text)
        if not text:match("^%d*%.?%d+$") then
            delayReset = 0.2
            return "0.2"
        end

        local num = tonumber(text)
        if not num then
            delayReset = 0.2
            return "0.2"
        end

        delayReset = math.clamp(num, 0, 1)
        return tostring(delayReset)
    end
})

TabFishing:Input({
    Title = "Delay Catch",
    Desc = "Instant Speed",
    Value = "1.05",
    Callback = function(text)
        if not text:match("^%d*%.?%d+$") then
            delayTime = 1.05
            return "1.05"
        end

        local num = tonumber(text)
        if not num then
            delayTime = 1.05
            return "1.05"
        end

        delayTime = math.clamp(num, 0.1, 3)
        return tostring(delayTime)
    end
})

TabFishing:Toggle({ Title = "Activate Fishing", Desc = "Start/Stop Loop", Icon = "check", Value = false, Callback = function(state) getgenv().fishingStart = state; if state then pcall(function() CancelInput:InvokeServer() end); if superInstant then task.spawn(startFishingSuperInstantLoop) else task.spawn(startFishingLoop) end; WindUI:Notify({Title = "Fishing", Content = "Started!", Duration = 2}) else pcall(function() CompleteGame:FireServer() end); pcall(function() CancelInput:InvokeServer() end); WindUI:Notify({Title = "Fishing", Content = "Stopped", Duration = 2}) end end })
TabFishing:Button({
    Title = "Unstuck",
    Desc = "Unstuck while using blatant",
    Icon = "person-standing",
    Callback = function()
        task.spawn(function()
            resetCharacter()
            WindUI:Notify({
                Title = "Unstuck",
                Content = "Already unstuck",
                Duration = 2
            })
        end)
    end
})


-- [[ TAB 2: AUTO SELL ]]
TabSell:Toggle({ Title = "Auto Sell (Time)", Desc = "Safe Pauses Fishing to Sell", Icon = "timer", Value = false, Callback = function(state) SettingsState.AutoSell.TimeActive = state; if state then StartAutoSellLoop(); WindUI:Notify({Title = "Auto Sell", Content = "Loop Started", Duration = 2}) else SettingsState.AutoSell.IsSelling = false; WindUI:Notify({Title = "Auto Sell", Content = "Loop Stopped", Duration = 2}) end end })
TabSell:Input({
    Title = "Sell Interval (Seconds)",
    Desc = "Time between sells",
    Value = "600",
    Callback = function(text)
        -- hanya angka bulat
        if not text:match("^%d+$") then
            SettingsState.AutoSell.TimeInterval = 600
            return "60"
        end

        local num = tonumber(text)
        if not num then
            SettingsState.AutoSell.TimeInterval = 600
            return "60"
        end

        num = math.clamp(math.floor(num), 10, 300)
        SettingsState.AutoSell.TimeInterval = num
        return tostring(num)
    end
})
TabSell:Button({ Title = "Sell Now", Desc = "Sell All Items Immediately", Icon = "trash-2", Callback = function() task.spawn(function() SettingsState.AutoSell.IsSelling = true; task.wait(0.2); pcall(function() SellAll:InvokeServer() end); WindUI:Notify({Title = "Sell All", Content = "Sold!", Duration = 2}); task.wait(0.5); SettingsState.AutoSell.IsSelling = false end) end })

-- [[ TAB 3: WEATHER ]]
TabWeather:Dropdown({ Title = "Select Weather(s)", Desc = "Choose multiple weathers to maintain", Values = {"Wind", "Cloudy", "Snow", "Storm", "Radiant"}, Value = {}, Multi = true, AllowNone = true, Callback = function(option) SettingsState.AutoWeather.SelectedList = option end })
TabWeather:Toggle({ Title = "Smart Monitor", Desc = "Checks every 15s", Icon = "cloud-lightning", Value = false, Callback = function(state) SettingsState.AutoWeather.Active = state; if state then StartAutoWeather(); WindUI:Notify({Title = "Weather", Content = "Monitor Started", Duration = 2}) else StopAutoWeather() WindUI:Notify({Title = "Weather", Content = "Monitor Stopped", Duration = 2}) end end })

-- [[ TAB 4: TELEPORT ]]
TabTeleport:Section({ Title = "Auto Event" })
local TimedLabel = TabTeleport:Paragraph({
    Title = "Christmas Time",
    Desc = "Status: Off"
})

TabTeleport:Toggle({
    Title = "Auto Christmas Time",
    Desc = "Auto Join",
    Icon = "clock",
    Value = false,
    Callback = function(state)
        ToggleAutoTimedEvent(state, TimedLabel)
    end
})

TabTeleport:Button({ Title = "Teleport to Megalodon", Desc = "Now Bug Dont Use", Icon = "skull", Callback = function() TeleportToMegalodon() end })

TabTeleport:Section({ Title = "Islands" }) 
local TP_Dropdown = TabTeleport:Dropdown({ Title = "Select Island", Desc = "Fixed GPS Coordinates", Values = zoneNames, Value = zoneNames[1] or "Select", Callback = function(val) selectedZone = val end })
TabTeleport:Button({ Title = "Teleport to Island", Desc = "Warp to selected location", Icon = "navigation", Callback = function() if selectedZone and Waypoints[selectedZone] then TeleportTo(Waypoints[selectedZone]) else WindUI:Notify({Title = "Error", Content = "Coordinates missing", Duration = 2}) end end })
TabTeleport:Button({ Title = "Refresh List", Icon = "refresh-cw", Callback = function() WindUI:Notify({Title = "System", Content = "Static list reloaded", Duration = 1}) end })

TabTeleport:Section({ Title = "Player Teleport" })
local targetPlayerName = ""
local playerNames = GetPlayerList()
local PlayerDropdown = TabTeleport:Dropdown({ Title = "Select Player", Desc = "List of players in server", Values = playerNames, Value = playerNames[1] or "None", Callback = function(val) targetPlayerName = val end })
TabTeleport:Button({ Title = "Teleport to Player", Desc = "Go to target player", Icon = "user", Callback = function() local target = FindPlayer(targetPlayerName); if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then TeleportTo(target.Character.HumanoidRootPart.Position + Vector3.new(3, 0, 0)); WindUI:Notify({Title = "Teleport", Content = "Warped to " .. target.Name, Duration = 2}) else WindUI:Notify({Title = "Error", Content = "Player not found!", Duration = 2}) end end })
TabTeleport:Button({ Title = "Refresh Players", Desc = "Update list", Icon = "refresh-cw", Callback = function() local newPlayers = GetPlayerList(); PlayerDropdown:Refresh(newPlayers, newPlayers[1] or "None"); WindUI:Notify({Title = "System", Content = "List updated!", Duration = 2}) end })

TabTeleport:Section({ Title = "Coordinate Tools" })
LivePosToggle = TabTeleport:Toggle({ Title = "Show Live Pos", Desc = "Click to show coordinates", Icon = "monitor", Value = false, Callback = function(state) TogglePosWatcher(state) end })
CoordDisplay = TabTeleport:Paragraph({ Title = "Current Position", Desc = "Status: Off" })
TabTeleport:Button({ Title = "Copy Position", Desc = "Copy 'Vector3.new(...)'", Icon = "copy", Callback = function() local Char = Players.LocalPlayer.Character; if Char and Char:FindFirstChild("HumanoidRootPart") then local pos = Char.HumanoidRootPart.Position; local str = string.format("Vector3.new(%.0f, %.0f, %.0f)", pos.X, pos.Y, pos.Z); if setclipboard then setclipboard(str); WindUI:Notify({Title = "Copied!", Content = "Saved", Duration = 2}) else print("📍 COPIED: " .. str); WindUI:Notify({Title = "Error", Content = "Check F9", Duration = 2}) end end end })


-- [[ TAB 5: SETTINGS ]]
TabSettings:Section({ Title = "Server" })
TabSettings:Button({ 
    Title = "Server Hop (Low Player)", 
    Desc = "Find server with space", 
    Icon = "server", 
    Callback = function() 
        WindUI:Notify({Title = "Server Hop", Content = "Searching...", Duration = 3})
        local Http = game:GetService("HttpService")
        local TPS = game:GetService("TeleportService")
        local Api = "https://games.roblox.com/v1/games/"
        local PlaceId = game.PlaceId
        local _servers = Api..PlaceId.."/servers/Public?sortOrder=Asc&limit=100"
        
        local function ListServers(cursor)
            local Raw = game:HttpGet(_servers .. ((cursor and "&cursor="..cursor) or ""))
            return Http:JSONDecode(Raw)
        end
        
        local Server, Next; repeat
            local Servers = ListServers(Next)
            Server = Servers.data[1]
            Next = Servers.nextPageCursor
        until Server
        
        TPS:TeleportToPlaceInstance(PlaceId, Server.id, LocalPlayer)
    end 
})

TabSettings:Button({
    Title = "Rejoin Game (Auto-Exec)",
    Desc = "Rejoin & Run Script",
    Icon = "rotate-cw",
    Callback = function()
        local ts = game:GetService("TeleportService")
        local p = game:GetService("Players").LocalPlayer
        
        WindUI:Notify({Title = "System", Content = "Rejoining...", Duration = 3})
        local myScript = 'loadstring(game:HttpGet("https://raw.githubusercontent.com/himangmyid/fishit/refs/heads/main/fish-it.lua"))()'
        if (syn and syn.queue_on_teleport) then
            syn.queue_on_teleport(myScript)
        elseif queue_on_teleport then
            queue_on_teleport(myScript)
        end
        ts:Teleport(game.PlaceId, p)
    end
})

TabSettings:Section({ Title = "Optimization" })
TabSettings:Button({ Title = "Anti-AFK", Desc = "Status: Active (Always On)", Icon = "clock", Callback = function() WindUI:Notify({ Title = "Anti-AFK", Content = "Permanently Active", Duration = 2 }) end })
TabSettings:Button({ Title = "Destroy Fish Popup", Desc = "Permanently removes 'Small Notification' UI", Icon = "trash-2", Callback = function() if SettingsState.PopupDestroyed then WindUI:Notify({Title = "UI", Content = "Already Destroyed!", Duration = 2}) return end; SettingsState.PopupDestroyed = true; ExecuteDestroyPopup(); WindUI:Notify({Title = "UI", Content = "Popup Destroyed!", Duration = 3}) end })
TabSettings:Toggle({ Title = "FPS Boost (Potato)", Desc = "Low Graphics", Icon = "monitor", Value = false, Callback = function(state) ToggleFPSBoost(state) end })
TabSettings:Button({ Title = "Remove VFX (Permanent)", Desc = "Delete Effects", Icon = "trash-2", Callback = function() if SettingsState.VFXRemoved then WindUI:Notify({Title = "VFX", Content = "Already Removed!", Duration = 2}) return end; SettingsState.VFXRemoved = true; ExecuteRemoveVFX(); WindUI:Notify({Title = "VFX", Content = "Deleted!", Duration = 2}) end })
local RarityList = {"Common","Uncommon","Rare","Epic","Legendary","Mythic","Secret",}

TabFavorite:Dropdown({
    Title = "Select Rarity to Favorite",
    Desc = "Choose rarities",
    Values = RarityList,
    Value = {},
    Multi = true,
    AllowNone = true,
    Callback = function(list)
        SetSelectedRarities(list)
    end
})

TabFavorite:Toggle({
    Title = "Active Auto Favorite",
    Desc = "Automatically favorites selected rarities",
    Icon = "star",
    Value = false,
    Callback = function(state)
        SettingsState.AutoFavorite.Active = state
        ToggleAutoFavorite(state)
        if state then
            WindUI:Notify({Title = "Auto Favorite", Content = "Running...", Duration = 2})
        else
            WindUI:Notify({Title = "Auto Favorite", Content = "Stopped", Duration = 2})
        end
    end
})

-------------------------------------------------------
-- WIND UI (MULTI SELECT DROPDOWN)
-------------------------------------------------------
TabWebHook:Section({ Title = "Webhook Rarity Filter" })

TabWebHook:Dropdown({
	Title = "Rarity Filter",
	Desc = "Select multiple rarities (empty = all)",
	Values = RarityList,
	Multi = true,
	AllowNone = true,

	Callback = function(selectedList)
		-- reset
		SettingsState.WebhookFish.SelectedRarities = {}

		warn("[WEBHOOK][DEBUG] Raw selectedList =", selectedList)

		-- CASE 1: map { Rare = true }
		for key, value in pairs(selectedList or {}) do
			if type(key) == "string" and value == true then
				local tier = RARITY_NAME_TO_TIER[key]
				if tier then
					SettingsState.WebhookFish.SelectedRarities[tier] = true
				end
			end
		end

		-- CASE 2: array { "Rare", "Epic" }
		for _, value in ipairs(selectedList or {}) do
			if type(value) == "string" then
				local tier = RARITY_NAME_TO_TIER[value]
				if tier then
					SettingsState.WebhookFish.SelectedRarities[tier] = true
				end
			end
		end

		warn(
			"[WEBHOOK][DEBUG] Normalized SelectedRarities =",
			SettingsState.WebhookFish.SelectedRarities
		)

		if next(SettingsState.WebhookFish.SelectedRarities) == nil then
			WindUI:Notify({
				Title = "Webhook",
				Content = "Rarity filter: All",
				Duration = 2
			})
		else
			WindUI:Notify({
				Title = "Webhook",
				Content = "Rarity filter updated",
				Duration = 2
			})
		end
	end
})



-------------------------------------------------------
-- WIND UI : WEBHOOK URL INPUT
-------------------------------------------------------
local WebhookInputBuffer = ""

TabWebHook:Section({ Title = "Webhook Settings" })

TabWebHook:Input({
	Title = "Discord Webhook URL",
	Desc = "Paste your Discord webhook URL",
	Placeholder = "https://discord.com/api/webhooks/...",
	Callback = function(text)
		WebhookInputBuffer = tostring(text)
		return text
	end
})

TabWebHook:Button({
	Title = "Save Webhook URL",
	Icon = "save",
	Callback = function()
		local url = WebhookInputBuffer:gsub("%s+", "")

		if not url:match("^https://discord.com/api/webhooks/") then
			WindUI:Notify({
				Title = "Webhook",
				Content = "Invalid webhook URL",
				Duration = 2
			})
			return
		end

		SettingsState.WebhookFish.Url = url

		WindUI:Notify({
			Title = "Webhook",
			Content = "Webhook URL saved",
			Duration = 2
		})

		warn("[WEBHOOK] URL SAVED")
	end
})


TabWebHook:Toggle({
	Title = "Fish Webhook Logger",
	Desc = "Enable fish webhook",
	Value = false,
	Callback = function(state)
		if state then
			StartFishWebhook()
		else
			StopFishWebhook()
		end
	end
})



-- Init
task.delay(1, function()
    setElementVisible("Delay Fishing", false); setElementVisible("Delay Catch", false); setElementVisible("Reset Delay", false)
    if instant then setElementVisible("Delay Catch", true)
    elseif superInstant then setElementVisible("Delay Fishing", true); setElementVisible("Reset Delay", true) end
end)

task.spawn(StartAntiAFK)
print("✅ Mangkuy vBeta Loaded! (With AutoFavorite v4.0) by Himang")
