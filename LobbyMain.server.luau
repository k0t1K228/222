-- ============================================
-- МАГАЗИН БАШЕН + РАЗМЕЩЕНИЕ
-- ПК:     кнопка → призрак за курсором → ЛКМ поставить, ПКМ/Esc отмена.
-- Тач:    кнопка → призрак за пальцем → кнопки «Поставить»/«Отмена».
-- Зелёный круг = можно ставить, красный = нельзя.
-- Окончательную валидацию всё равно делает сервер.
-- ============================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")

local Classes        = ReplicatedStorage:WaitForChild("Classes")
local TowerClass     = require(Classes:WaitForChild("TowerClass"))
local PlacementZones = require(Classes:WaitForChild("PlacementZones"))
local Theme          = require(script.Parent:WaitForChild("Theme"))
local RangeIndicator = require(script.Parent:WaitForChild("RangeIndicator"))

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera    = workspace.CurrentCamera

local templates    = ReplicatedStorage:WaitForChild("TowerTemplates")
local placeTowerRF = ReplicatedStorage:WaitForChild("PlaceTower")
local moneyVal     = player:WaitForChild("leaderstats"):WaitForChild("Money")

local touchEnabled = UserInputService.TouchEnabled

-- ============================================
-- GUI
-- ============================================
local gui = Instance.new("ScreenGui")
gui.Name         = "TowerShop"
gui.ResetOnSpawn = false
gui.Parent       = playerGui

-- Счётчик кредитов (слева сверху)
local moneyFrame = Instance.new("Frame")
moneyFrame.Size     = UDim2.new(0, 180, 0, 42)
moneyFrame.Position = UDim2.new(0, 15, 0, 15)
moneyFrame.Parent   = gui
Theme.stylePanel(moneyFrame, Theme.COLORS.yellow)

local moneyLabel = Instance.new("TextLabel")
moneyLabel.Size       = UDim2.new(1, -16, 1, -8)
moneyLabel.Position   = UDim2.new(0, 8, 0, 4)
moneyLabel.TextScaled = true
moneyLabel.TextXAlignment = Enum.TextXAlignment.Left
moneyLabel.Text       = Theme.money(moneyVal.Value)
moneyLabel.Parent     = moneyFrame
Theme.styleText(moneyLabel, Theme.COLORS.yellow)

moneyVal.Changed:Connect(function()
	moneyLabel.Text = Theme.money(moneyVal.Value)
end)

-- Сообщение об ошибке (над панелью магазина)
local message = Instance.new("TextLabel")
message.AnchorPoint = Vector2.new(0.5, 1)
message.Position    = UDim2.new(0.5, 0, 1, -172) -- над тач-кнопками «Поставить/Отмена»
message.Size        = UDim2.new(0, 420, 0, 32)
message.TextScaled  = true
message.Text        = ""
message.Visible     = false
message.Parent      = gui
Theme.styleText(message, Theme.COLORS.red)

local messageToken = 0
local function showMessage(text)
	messageToken = messageToken + 1
	local token = messageToken
	message.Text = text
	message.Visible = true
	task.delay(2, function()
		if messageToken == token then message.Visible = false end
	end)
end

-- Панель магазина (внизу по центру)
local shopTypes = TowerClass.SHOP_ORDER
-- Кнопки компактные: 8 штук должны влезать и на ноутбучные экраны
local BTN_W, BTN_H = 100, 72

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Position    = UDim2.new(0.5, 0, 1, -12)
panel.Size        = UDim2.new(0, #shopTypes * (BTN_W + 6) + 12, 0, BTN_H + 16)
panel.Parent      = gui
Theme.stylePanel(panel, Theme.COLORS.cyan)

-- Кнопки живут во внутреннем контейнере: НА панели лежит декор от
-- stylePanel (NeonTopline), и если повесить UIListLayout прямо на панель,
-- полоска станет «первым элементом» и вытолкнет кнопки за край
local buttonRow = Instance.new("Frame")
buttonRow.Size                   = UDim2.new(1, 0, 1, 0)
buttonRow.BackgroundTransparency = 1
buttonRow.Parent                 = panel

local layout = Instance.new("UIListLayout")
layout.FillDirection       = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment   = Enum.VerticalAlignment.Center
layout.Padding             = UDim.new(0, 6)
layout.Parent              = buttonRow

-- Кнопки подтверждения для тача (видны только в режиме размещения)
local confirmBar = Instance.new("Frame")
confirmBar.AnchorPoint            = Vector2.new(0.5, 1)
confirmBar.Position               = UDim2.new(0.5, 0, 1, -118)
confirmBar.Size                   = UDim2.new(0, 320, 0, 44)
confirmBar.BackgroundTransparency = 1
confirmBar.Visible                = false
confirmBar.Parent                 = gui

local confirmLayout = Instance.new("UIListLayout")
confirmLayout.FillDirection       = Enum.FillDirection.Horizontal
confirmLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
confirmLayout.Padding             = UDim.new(0, 10)
confirmLayout.Parent              = confirmBar

local function makeConfirmButton(text, accent)
	local b = Instance.new("TextButton")
	b.Size       = UDim2.new(0, 150, 0, 44)
	b.TextScaled = true
	b.Text       = text
	b.Parent     = confirmBar
	Theme.styleButton(b, accent)
	b.TextColor3 = accent
	return b
end

local placeBtn  = makeConfirmButton("▸ ПОСТАВИТЬ", Theme.COLORS.green)
local cancelBtn = makeConfirmButton("✕ ОТМЕНА",    Theme.COLORS.red)

-- ============================================
-- РАЗМЕЩЕНИЕ
-- ============================================
local placing = nil -- {towerType, ghost, circle, price, lastPos, valid}
local lastTouchPos = nil -- Vector2 позиции пальца

local function destroyPlacing()
	if placing then
		if placing.ghost then placing.ghost:Destroy() end
		if placing.circle then placing.circle:destroy() end
		placing = nil
	end
	confirmBar.Visible = false
end

-- Делает клон полупрозрачным и «бесплотным»
local function ghostify(model)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Transparency = math.clamp(p.Transparency + 0.5, 0.5, 1)
			p.CanCollide = false
			p.CanQuery = false
			p.Anchored = true
		end
	end
end

-- Ставим модель дном на точку (та же математика, что на сервере)
local function pivotModelToGround(model, position)
	local bbCF, bbSize = model:GetBoundingBox()
	local pivotY = model:GetPivot().Position.Y
	local bottomOffset = pivotY - (bbCF.Position.Y - bbSize.Y / 2)
	model:PivotTo(CFrame.new(position + Vector3.new(0, bottomOffset, 0)))
end

local function startPlacing(towerType)
	destroyPlacing()
	local template = templates:FindFirstChild(towerType)
	if not template then return end

	local cfg = TowerClass.getEffectiveConfig(towerType, 1)
	local def = TowerClass.getConfig(towerType)

	local ghost = template:Clone()
	ghostify(ghost)
	ghost.Parent = workspace

	-- неоновое кольцо радиуса атаки (зелёное = можно, красное = нельзя)
	local circle = RangeIndicator.new(Theme.COLORS.green)
	circle:setRadius(cfg.range)

	placing = {
		towerType = towerType,
		ghost     = ghost,
		circle    = circle,
		price     = def.price or 0,
		lastPos   = nil,
		valid     = false,
	}
	confirmBar.Visible = touchEnabled
end

local function attemptPlace()
	if not placing then return end
	if placing.valid and placing.lastPos then
		local result = placeTowerRF:InvokeServer(placing.towerType, placing.lastPos)
		if result and result.ok then
			destroyPlacing()
		else
			showMessage(result and result.err or "Не удалось поставить башню")
		end
	else
		showMessage("Сюда ставить нельзя")
	end
end

placeBtn.Activated:Connect(attemptPlace)
cancelBtn.Activated:Connect(destroyPlacing)

-- Где сейчас «указатель» (мышь или палец)
local function getPointerPos()
	if touchEnabled then
		return lastTouchPos
	end
	return UserInputService:GetMouseLocation()
end

-- Призрак следует за указателем; проверка валидности — раз в 0.1с
local validityAcc = 0
RunService.RenderStepped:Connect(function(dt)
	if not placing then return end

	local pointer = getPointerPos()
	if not pointer then return end

	local ray = camera:ViewportPointToRay(pointer.X, pointer.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = {placing.ghost, placing.circle.folder}
	if player.Character then table.insert(exclude, player.Character) end
	-- не липнем к крышам существующих башен
	for _, obj in ipairs(workspace:GetChildren()) do
		if obj:IsA("Model") and obj:GetAttribute("TowerActive") then
			table.insert(exclude, obj)
		end
	end
	params.FilterDescendantsInstances = exclude

	local hit = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
	if not hit then
		placing.valid = false
		return
	end

	pivotModelToGround(placing.ghost, hit.Position)
	placing.circle:setPosition(hit.Position + Vector3.new(0, 0.2, 0))
	placing.lastPos = hit.Position

	validityAcc = validityAcc + dt
	if validityAcc >= 0.1 then
		validityAcc = 0
		local okZone = PlacementZones.canPlace(hit.Position)
		local okMoney = moneyVal.Value >= placing.price
		placing.valid = okZone and okMoney
		placing.circle:setColor(placing.valid
			and Theme.COLORS.green
			or Theme.COLORS.red)
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	-- запоминаем позицию пальца (нужно даже если тап по UI)
	if input.UserInputType == Enum.UserInputType.Touch then
		lastTouchPos = Vector2.new(input.Position.X, input.Position.Y)
	end

	if not placing then return end

	-- отмена работает даже если курсор над UI
	if input.UserInputType == Enum.UserInputType.MouseButton2
		or input.KeyCode == Enum.KeyCode.Escape then
		destroyPlacing()
		return
	end

	if processed then return end -- клик/тап пришёлся по кнопке UI

	-- ПК: клик мыши ставит сразу. Тач: только кнопка «Поставить».
	if not touchEnabled and input.UserInputType == Enum.UserInputType.MouseButton1 then
		attemptPlace()
	end
end)

UserInputService.TouchMoved:Connect(function(touch, processed)
	if processed then return end
	lastTouchPos = Vector2.new(touch.Position.X, touch.Position.Y)
end)

-- ============================================
-- КНОПКИ МАГАЗИНА
-- ============================================
for order, towerType in ipairs(shopTypes) do
	local def = TowerClass.getConfig(towerType)
	if def then
		local accent = def.beamColor or Theme.COLORS.cyan

		local btn = Instance.new("TextButton")
		btn.Size        = UDim2.new(0, BTN_W, 0, BTN_H)
		btn.Text        = ""
		btn.LayoutOrder = order
		btn.Parent      = buttonRow
		Theme.styleButton(btn, accent)

		-- неоновая полоска типа оружия слева
		local stripe = Instance.new("Frame")
		stripe.Size             = UDim2.new(0, 3, 1, -10)
		stripe.Position         = UDim2.new(0, 4, 0, 5)
		stripe.BackgroundColor3 = accent
		stripe.BorderSizePixel  = 0
		stripe.Parent           = btn

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size       = UDim2.new(1, -16, 0, 34)
		nameLabel.Position   = UDim2.new(0, 12, 0, 8)
		nameLabel.TextScaled = true
		nameLabel.Text       = def.displayName or towerType
		nameLabel.Parent     = btn
		Theme.styleText(nameLabel, Theme.COLORS.textMain)

		local priceLabel = Instance.new("TextLabel")
		priceLabel.Size       = UDim2.new(1, -16, 0, 22)
		priceLabel.Position   = UDim2.new(0, 12, 1, -28)
		priceLabel.TextScaled = true
		priceLabel.Text       = Theme.money(def.price or 0)
		priceLabel.Parent     = btn
		Theme.styleText(priceLabel, Theme.COLORS.yellow)

		btn.Activated:Connect(function()
			startPlacing(towerType)
		end)
	end
end
