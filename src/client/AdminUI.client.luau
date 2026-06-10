local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gameData      = ReplicatedStorage:WaitForChild("GameData")
local baseHPVal     = gameData:WaitForChild("BaseHP")
local maxHPVal      = gameData:WaitForChild("MaxBaseHP")
local waveVal       = gameData:WaitForChild("CurrentWave")
local maxWaveVal    = gameData:WaitForChild("MaxWaves")
local enemyCountVal = gameData:WaitForChild("EnemyCount")
local gameOverVal   = gameData:WaitForChild("GameOver")

-- ScreenGui
local gui = Instance.new("ScreenGui")
gui.Name          = "AdminPanel"
gui.ResetOnSpawn  = false
gui.Parent        = playerGui

-- Главная панель
local panel = Instance.new("Frame")
panel.Size                = UDim2.new(0, 300, 0, 160)
panel.Position            = UDim2.new(1, -315, 0, 15)
panel.BackgroundColor3    = Color3.fromRGB(15, 15, 25)
panel.BackgroundTransparency = 0.15
panel.BorderSizePixel     = 0
panel.Parent              = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)

-- Заголовок
local title = Instance.new("TextLabel")
title.Size              = UDim2.new(1, 0, 0, 32)
title.Position          = UDim2.new(0, 0, 0, 0)
title.BackgroundColor3  = Color3.fromRGB(30, 30, 50)
title.BorderSizePixel   = 0
title.TextColor3        = Color3.fromRGB(255, 220, 0)
title.TextScaled        = true
title.Font              = Enum.Font.GothamBold
title.Text              = "⚡  ADMIN PANEL"
title.Parent            = panel
Instance.new("UICorner", title).CornerRadius = UDim.new(0, 10)

-- Подпись HP
local hpTitle = Instance.new("TextLabel")
hpTitle.Size              = UDim2.new(1, -20, 0, 20)
hpTitle.Position          = UDim2.new(0, 10, 0, 38)
hpTitle.BackgroundTransparency = 1
hpTitle.TextColor3        = Color3.fromRGB(180, 180, 180)
hpTitle.TextScaled        = true
hpTitle.Font              = Enum.Font.Gotham
hpTitle.TextXAlignment    = Enum.TextXAlignment.Left
hpTitle.Text              = "БАЗА HP"
hpTitle.Parent            = panel

local hpNumber = Instance.new("TextLabel")
hpNumber.Size             = UDim2.new(1, -20, 0, 20)
hpNumber.Position         = UDim2.new(0, 10, 0, 38)
hpNumber.BackgroundTransparency = 1
hpNumber.TextColor3       = Color3.fromRGB(255, 255, 255)
hpNumber.TextScaled       = true
hpNumber.Font             = Enum.Font.GothamBold
hpNumber.TextXAlignment   = Enum.TextXAlignment.Right
hpNumber.Text             = "10000 / 10000"
hpNumber.Parent           = panel

-- HP бар фон
local hpBg = Instance.new("Frame")
hpBg.Size               = UDim2.new(1, -20, 0, 20)
hpBg.Position           = UDim2.new(0, 10, 0, 62)
hpBg.BackgroundColor3   = Color3.fromRGB(40, 40, 55)
hpBg.BorderSizePixel    = 0
hpBg.Parent             = panel
Instance.new("UICorner", hpBg).CornerRadius = UDim.new(0, 5)

local hpBar = Instance.new("Frame")
hpBar.Size              = UDim2.new(1, 0, 1, 0)
hpBar.BackgroundColor3  = Color3.fromRGB(0, 180, 255)
hpBar.BorderSizePixel   = 0
hpBar.Parent            = hpBg
Instance.new("UICorner", hpBar).CornerRadius = UDim.new(0, 5)

-- Разделитель
local divider = Instance.new("Frame")
divider.Size            = UDim2.new(1, -20, 0, 1)
divider.Position        = UDim2.new(0, 10, 0, 96)
divider.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
divider.BorderSizePixel = 0
divider.Parent          = panel

-- Волна
local waveLabel = Instance.new("TextLabel")
waveLabel.Size              = UDim2.new(0.5, -15, 0, 30)
waveLabel.Position          = UDim2.new(0, 10, 0, 104)
waveLabel.BackgroundColor3  = Color3.fromRGB(30, 30, 50)
waveLabel.BorderSizePixel   = 0
waveLabel.TextColor3        = Color3.fromRGB(255, 200, 50)
waveLabel.TextScaled        = true
waveLabel.Font              = Enum.Font.GothamBold
waveLabel.Text              = "🌊 ВОЛНА  0 / 3"
waveLabel.Parent            = panel
Instance.new("UICorner", waveLabel).CornerRadius = UDim.new(0, 6)

-- Враги
local enemyLabel = Instance.new("TextLabel")
enemyLabel.Size             = UDim2.new(0.5, -15, 0, 30)
enemyLabel.Position         = UDim2.new(0.5, 5, 0, 104)
enemyLabel.BackgroundColor3 = Color3.fromRGB(30, 30, 50)
enemyLabel.BorderSizePixel  = 0
enemyLabel.TextColor3       = Color3.fromRGB(255, 80, 80)
enemyLabel.TextScaled       = true
enemyLabel.Font             = Enum.Font.GothamBold
enemyLabel.Text             = "☠ ВРАГОВ  0"
enemyLabel.Parent           = panel
Instance.new("UICorner", enemyLabel).CornerRadius = UDim.new(0, 6)

-- Статус базы
local statusLabel = Instance.new("TextLabel")
statusLabel.Size            = UDim2.new(1, -20, 0, 22)
statusLabel.Position        = UDim2.new(0, 10, 0, 140)
statusLabel.BackgroundTransparency = 1
statusLabel.TextColor3      = Color3.fromRGB(0, 255, 150)
statusLabel.TextScaled      = true
statusLabel.Font            = Enum.Font.Gotham
statusLabel.Text            = "● База в порядке"
statusLabel.Parent          = panel

-- ============================================
-- ОБНОВЛЕНИЕ UI
-- ============================================
local function updateUI()
	local hp    = baseHPVal.Value
	local maxHP = maxHPVal.Value
	local pct   = hp / maxHP

	hpNumber.Text = math.floor(hp) .. " / " .. maxHP
	hpBar.Size    = UDim2.new(pct, 0, 1, 0)

	if pct > 0.5 then
		hpBar.BackgroundColor3  = Color3.fromRGB(0, 180, 255)
		statusLabel.Text        = "● База в порядке"
		statusLabel.TextColor3  = Color3.fromRGB(0, 255, 150)
	elseif pct > 0.25 then
		hpBar.BackgroundColor3  = Color3.fromRGB(255, 150, 0)
		statusLabel.Text        = "⚠ База под угрозой!"
		statusLabel.TextColor3  = Color3.fromRGB(255, 200, 0)
	else
		hpBar.BackgroundColor3  = Color3.fromRGB(255, 50, 50)
		statusLabel.Text        = "🔴 КРИТИЧЕСКОЕ СОСТОЯНИЕ!"
		statusLabel.TextColor3  = Color3.fromRGB(255, 50, 50)
	end

	waveLabel.Text  = "🌊 ВОЛНА  " .. waveVal.Value .. " / " .. maxWaveVal.Value
	enemyLabel.Text = "☠ ВРАГОВ  " .. enemyCountVal.Value

	-- Game Over перекрывает любой статус
	if gameOverVal.Value then
		statusLabel.Text       = "💀 БАЗА УНИЧТОЖЕНА — ИГРА ОКОНЧЕНА"
		statusLabel.TextColor3 = Color3.fromRGB(255, 0, 0)
	end
end

baseHPVal.Changed:Connect(updateUI)
waveVal.Changed:Connect(updateUI)
enemyCountVal.Changed:Connect(updateUI)
gameOverVal.Changed:Connect(updateUI)

updateUI()