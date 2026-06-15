-- ============================================
-- UI ЛОББИ: кнопка «ГОТОВ», счётчик готовых, отсчёт до старта.
-- Стиль — киберпанк, как в игре, но без модуля Theme:
-- лобби — отдельный place, туда синкается только src/lobby.
-- ============================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local lobbyData     = ReplicatedStorage:WaitForChild("LobbyData")
local readyCountVal = lobbyData:WaitForChild("ReadyCount")
local totalCountVal = lobbyData:WaitForChild("TotalCount")
local countdownVal  = lobbyData:WaitForChild("Countdown")
local toggleReadyRE = ReplicatedStorage:WaitForChild("ToggleReady")

-- Мини-палитра (копия главных цветов Theme.luau)
local C_BG     = Color3.fromRGB(8, 10, 20)
local C_CYAN   = Color3.fromRGB(0, 229, 255)
local C_GREEN  = Color3.fromRGB(0, 255, 159)
local C_YELLOW = Color3.fromRGB(252, 238, 33)
local C_TEXT   = Color3.fromRGB(220, 230, 245)

local gui = Instance.new("ScreenGui")
gui.Name         = "LobbyUI"
gui.ResetOnSpawn = false
gui.Parent       = playerGui

local panel = Instance.new("Frame")
panel.AnchorPoint      = Vector2.new(0.5, 1)
panel.Position         = UDim2.new(0.5, 0, 1, -30)
panel.Size             = UDim2.new(0, 360, 0, 150)
panel.BackgroundColor3 = C_BG
panel.BackgroundTransparency = 0.1
panel.BorderSizePixel  = 0
panel.Parent           = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 6)
local stroke = Instance.new("UIStroke")
stroke.Color = C_CYAN
stroke.Thickness = 1.5
stroke.Transparency = 0.3
stroke.Parent = panel

local title = Instance.new("TextLabel")
title.Size                   = UDim2.new(1, -24, 0, 30)
title.Position               = UDim2.new(0, 12, 0, 8)
title.BackgroundTransparency = 1
title.TextScaled             = true
title.Font                   = Enum.Font.SciFi
title.TextColor3             = C_CYAN
title.Text                   = "▸ ЛОББИ — ОБОРОНА БАЗЫ"
title.Parent                 = panel

local readyLabel = Instance.new("TextLabel")
readyLabel.Size                   = UDim2.new(1, -24, 0, 24)
readyLabel.Position               = UDim2.new(0, 12, 0, 42)
readyLabel.BackgroundTransparency = 1
readyLabel.TextScaled             = true
readyLabel.Font                   = Enum.Font.Code
readyLabel.TextColor3             = C_TEXT
readyLabel.Text                   = "ГОТОВЫ: 0 / 0"
readyLabel.Parent                 = panel

local readyBtn = Instance.new("TextButton")
readyBtn.Size             = UDim2.new(1, -24, 0, 56)
readyBtn.Position         = UDim2.new(0, 12, 1, -68)
readyBtn.BackgroundColor3 = Color3.fromRGB(16, 20, 38)
readyBtn.BorderSizePixel  = 0
readyBtn.TextScaled       = true
readyBtn.Font             = Enum.Font.SciFi
readyBtn.TextColor3       = C_GREEN
readyBtn.Text             = "✓ ГОТОВ"
readyBtn.Parent           = panel
Instance.new("UICorner", readyBtn).CornerRadius = UDim.new(0, 6)
local btnStroke = Instance.new("UIStroke")
btnStroke.Color = C_GREEN
btnStroke.Thickness = 1.5
btnStroke.Transparency = 0.4
btnStroke.Parent = readyBtn

-- Большой отсчёт по центру экрана
local countdownLabel = Instance.new("TextLabel")
countdownLabel.AnchorPoint            = Vector2.new(0.5, 0.5)
countdownLabel.Position               = UDim2.new(0.5, 0, 0.35, 0)
countdownLabel.Size                   = UDim2.new(0, 400, 0, 120)
countdownLabel.BackgroundTransparency = 1
countdownLabel.TextScaled             = true
countdownLabel.Font                   = Enum.Font.SciFi
countdownLabel.TextColor3             = C_YELLOW
countdownLabel.Text                   = ""
countdownLabel.Parent                 = gui

readyBtn.Activated:Connect(function()
	toggleReadyRE:FireServer()
end)

-- Сервер хранит мою готовность в атрибуте игрока
local function refreshButton()
	if player:GetAttribute("LobbyReady") then
		readyBtn.Text       = "✕ НЕ ГОТОВ"
		readyBtn.TextColor3 = C_YELLOW
		btnStroke.Color     = C_YELLOW
	else
		readyBtn.Text       = "✓ ГОТОВ"
		readyBtn.TextColor3 = C_GREEN
		btnStroke.Color     = C_GREEN
	end
end
player:GetAttributeChangedSignal("LobbyReady"):Connect(refreshButton)
refreshButton()

local function refreshCounts()
	readyLabel.Text = "ГОТОВЫ: " .. readyCountVal.Value .. " / " .. totalCountVal.Value
end
readyCountVal.Changed:Connect(refreshCounts)
totalCountVal.Changed:Connect(refreshCounts)
refreshCounts()

countdownVal.Changed:Connect(function()
	local t = countdownVal.Value
	countdownLabel.Text = t > 0 and ("СТАРТ ЧЕРЕЗ " .. t) or ""
end)
