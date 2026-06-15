-- ============================================
-- HUD: HP базы, волна, счётчик врагов, баннер конца игры.
-- Стиль — киберпанк (общая тема: Theme.luau).
-- ⚠️ Пока виден всем игрокам (известный долг — см. HANDBOOK ч.3).
-- ============================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Theme = require(script.Parent:WaitForChild("Theme"))

local bossWarningRE = ReplicatedStorage:WaitForChild("BossWarning")
local restartRE     = ReplicatedStorage:WaitForChild("RequestRestart")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gameData      = ReplicatedStorage:WaitForChild("GameData")
local baseHPVal     = gameData:WaitForChild("BaseHP")
local maxHPVal      = gameData:WaitForChild("MaxBaseHP")
local waveVal       = gameData:WaitForChild("CurrentWave")
local maxWaveVal    = gameData:WaitForChild("MaxWaves")
local enemyCountVal = gameData:WaitForChild("EnemyCount")
local gameOverVal   = gameData:WaitForChild("GameOver")
local victoryVal    = gameData:WaitForChild("Victory")

-- ScreenGui
local gui = Instance.new("ScreenGui")
gui.Name         = "GameHUD"
gui.ResetOnSpawn = false
gui.Parent       = playerGui

-- Главная панель (справа сверху)
local panel = Instance.new("Frame")
panel.Size     = UDim2.new(0, 300, 0, 168)
panel.Position = UDim2.new(1, -315, 0, 15)
panel.Parent   = gui
Theme.stylePanel(panel, Theme.COLORS.cyan)

-- Заголовок
local title = Instance.new("TextLabel")
title.Size       = UDim2.new(1, -16, 0, 30)
title.Position   = UDim2.new(0, 8, 0, 6)
title.TextScaled = true
title.Text       = "▸ ОБОРОНА БАЗЫ"
title.Parent     = panel
Theme.styleTitle(title, Theme.COLORS.cyan)

-- Подпись HP
local hpTitle = Instance.new("TextLabel")
hpTitle.Size           = UDim2.new(1, -24, 0, 18)
hpTitle.Position       = UDim2.new(0, 12, 0, 42)
hpTitle.TextScaled     = true
hpTitle.TextXAlignment = Enum.TextXAlignment.Left
hpTitle.Text           = "БАЗА HP"
hpTitle.Parent         = panel
Theme.styleText(hpTitle, Theme.COLORS.textDim)

local hpNumber = Instance.new("TextLabel")
hpNumber.Size           = UDim2.new(1, -24, 0, 18)
hpNumber.Position       = UDim2.new(0, 12, 0, 42)
hpNumber.TextScaled     = true
hpNumber.TextXAlignment = Enum.TextXAlignment.Right
hpNumber.Text           = "10000 / 10000"
hpNumber.Parent         = panel
Theme.styleText(hpNumber, Theme.COLORS.textMain)

-- HP бар
local hpBg = Instance.new("Frame")
hpBg.Size             = UDim2.new(1, -24, 0, 16)
hpBg.Position         = UDim2.new(0, 12, 0, 64)
hpBg.BackgroundColor3 = Color3.fromRGB(20, 24, 40)
hpBg.BorderSizePixel  = 0
hpBg.Parent           = panel
Theme.corner(hpBg, 3)
Theme.stroke(hpBg, Theme.COLORS.cyan, 1, 0.7)

local hpBar = Instance.new("Frame")
hpBar.Size             = UDim2.new(1, 0, 1, 0)
hpBar.BackgroundColor3 = Theme.COLORS.cyan
hpBar.BorderSizePixel  = 0
hpBar.Parent           = hpBg
Theme.corner(hpBar, 3)

-- Волна и враги — две неоновые плашки
local function makeStatChip(x, accent)
	local chip = Instance.new("TextLabel")
	chip.Size             = UDim2.new(0.5, -16, 0, 28)
	chip.Position         = UDim2.new(x, 12, 0, 90)
	chip.BackgroundColor3 = Theme.COLORS.bgLight
	chip.BorderSizePixel  = 0
	chip.TextScaled       = true
	chip.Font             = Theme.FONT_BODY
	chip.TextColor3       = accent
	chip.Parent           = panel
	Theme.corner(chip, 4)
	Theme.stroke(chip, accent, 1, 0.6)
	return chip
end

local waveLabel  = makeStatChip(0,   Theme.COLORS.yellow)
local enemyLabel = makeStatChip(0.5, Theme.COLORS.red)
waveLabel.Text  = "ВОЛНА 0/3"
enemyLabel.Text = "ВРАГОВ 0"

-- Статус базы
local statusLabel = Instance.new("TextLabel")
statusLabel.Size       = UDim2.new(1, -24, 0, 22)
statusLabel.Position   = UDim2.new(0, 12, 0, 128)
statusLabel.TextScaled = true
statusLabel.Text       = "● СИСТЕМЫ В НОРМЕ"
statusLabel.Parent     = panel
Theme.styleText(statusLabel, Theme.COLORS.green)

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
		hpBar.BackgroundColor3 = Theme.COLORS.cyan
		statusLabel.Text       = "● СИСТЕМЫ В НОРМЕ"
		statusLabel.TextColor3 = Theme.COLORS.green
	elseif pct > 0.25 then
		hpBar.BackgroundColor3 = Theme.COLORS.yellow
		statusLabel.Text       = "▲ БАЗА ПОД УГРОЗОЙ"
		statusLabel.TextColor3 = Theme.COLORS.yellow
	else
		hpBar.BackgroundColor3 = Theme.COLORS.red
		statusLabel.Text       = "■ КРИТИЧЕСКОЕ СОСТОЯНИЕ"
		statusLabel.TextColor3 = Theme.COLORS.red
	end

	waveLabel.Text  = "ВОЛНА " .. waveVal.Value .. "/" .. maxWaveVal.Value
	enemyLabel.Text = "ВРАГОВ " .. enemyCountVal.Value

	-- Game Over перекрывает любой статус
	if gameOverVal.Value then
		statusLabel.Text       = "✕ БАЗА УНИЧТОЖЕНА"
		statusLabel.TextColor3 = Theme.COLORS.red
	end
end

baseHPVal.Changed:Connect(updateUI)
waveVal.Changed:Connect(updateUI)
enemyCountVal.Changed:Connect(updateUI)
gameOverVal.Changed:Connect(updateUI)

-- ============================================
-- БАННЕР КОНЦА ИГРЫ (победа/поражение)
-- ============================================
local banner = Instance.new("Frame")
banner.AnchorPoint = Vector2.new(0.5, 0.5)
banner.Position    = UDim2.new(0.5, 0, 0.38, 0)
banner.Size        = UDim2.new(0, 640, 0, 96)
banner.Visible     = false
banner.Parent      = gui

local bannerText = Instance.new("TextLabel")
bannerText.Size       = UDim2.new(1, -24, 1, -16)
bannerText.Position   = UDim2.new(0, 12, 0, 8)
bannerText.TextScaled = true
bannerText.Font       = Theme.FONT_TITLE
bannerText.BackgroundTransparency = 1
bannerText.Parent     = banner

-- Кнопка «Играть снова» (любой игрок; сервер примет только после конца игры)
local restartBtn = Instance.new("TextButton")
restartBtn.AnchorPoint = Vector2.new(0.5, 0)
restartBtn.Position    = UDim2.new(0.5, 0, 0.38, 62)
restartBtn.Size        = UDim2.new(0, 260, 0, 44)
restartBtn.TextScaled  = true
restartBtn.Text        = "⟳ ИГРАТЬ СНОВА"
restartBtn.Visible     = false
restartBtn.Parent      = gui
Theme.styleButton(restartBtn, Theme.COLORS.green)
restartBtn.TextColor3 = Theme.COLORS.green

restartBtn.Activated:Connect(function()
	restartBtn.Text = "⟳ ЗАПУСК..."
	restartRE:FireServer()
end)

local function checkGameEnd()
	if gameOverVal.Value then
		Theme.stylePanel(banner, Theme.COLORS.red)
		bannerText.Text       = "✕ ПОРАЖЕНИЕ — БАЗА УНИЧТОЖЕНА"
		bannerText.TextColor3 = Theme.COLORS.red
		banner.Visible        = true
		restartBtn.Text       = "⟳ ИГРАТЬ СНОВА"
		restartBtn.Visible    = true
	elseif victoryVal.Value then
		Theme.stylePanel(banner, Theme.COLORS.yellow)
		bannerText.Text       = "▸ ПОБЕДА! ВСЕ ВОЛНЫ ОТБИТЫ"
		bannerText.TextColor3 = Theme.COLORS.yellow
		banner.Visible        = true
		restartBtn.Text       = "⟳ ИГРАТЬ СНОВА"
		restartBtn.Visible    = true
	else
		-- сервер сбросил флаги — начался новый раунд
		banner.Visible     = false
		restartBtn.Visible = false
	end
end

gameOverVal.Changed:Connect(checkGameEnd)
victoryVal.Changed:Connect(checkGameEnd)
checkGameEnd()

-- ============================================
-- БАННЕР «БОСС ПРИБЛИЖАЕТСЯ» (сверху по центру, мигает)
-- ============================================
local bossBanner = Instance.new("Frame")
bossBanner.AnchorPoint = Vector2.new(0.5, 0)
bossBanner.Position    = UDim2.new(0.5, 0, 0.12, 0)
bossBanner.Size        = UDim2.new(0, 560, 0, 64)
bossBanner.Visible     = false
bossBanner.Parent      = gui
Theme.stylePanel(bossBanner, Theme.COLORS.red)

local bossBannerText = Instance.new("TextLabel")
bossBannerText.Size       = UDim2.new(1, -24, 1, -16)
bossBannerText.Position   = UDim2.new(0, 12, 0, 8)
bossBannerText.TextScaled = true
bossBannerText.Font       = Theme.FONT_TITLE
bossBannerText.TextColor3 = Theme.COLORS.red
bossBannerText.BackgroundTransparency = 1
bossBannerText.Parent     = bossBanner

local bossToken = 0 -- защита от наложения двух предупреждений
bossWarningRE.OnClientEvent:Connect(function(names)
	if typeof(names) ~= "table" then names = {} end
	bossToken += 1
	local token = bossToken

	bossBannerText.Text = "⚠ ПРИБЛИЖАЕТСЯ: " .. string.upper(table.concat(names, ", "))
	bossBanner.Visible = true

	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 5 and token == bossToken do
			bossBannerText.TextTransparency = 0
			task.wait(0.3)
			bossBannerText.TextTransparency = 0.5
			task.wait(0.3)
		end
		if token == bossToken then
			bossBannerText.TextTransparency = 0
			bossBanner.Visible = false
		end
	end)
end)

updateUI()
