-- ============================================
-- МАГАЗИН БАШЕН + РАЗМЕЩЕНИЕ
-- Панель с кнопками внизу экрана. Нажал кнопку →
-- за курсором ходит полупрозрачный «призрак» башни с кругом радиуса:
-- зелёный = можно ставить, красный = нельзя (зона/дистанция/деньги).
-- ЛКМ — поставить, ПКМ/Esc — отмена.
-- ============================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")

local Classes        = ReplicatedStorage:WaitForChild("Classes")
local TowerClass     = require(Classes:WaitForChild("TowerClass"))
local PlacementZones = require(Classes:WaitForChild("PlacementZones"))

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera    = workspace.CurrentCamera

local templates    = ReplicatedStorage:WaitForChild("TowerTemplates")
local placeTowerRF = ReplicatedStorage:WaitForChild("PlaceTower")
local moneyVal     = player:WaitForChild("leaderstats"):WaitForChild("Money")

-- ============================================
-- GUI
-- ============================================
local gui = Instance.new("ScreenGui")
gui.Name         = "TowerShop"
gui.ResetOnSpawn = false
gui.Parent       = playerGui

-- Счётчик денег (слева сверху)
local moneyLabel = Instance.new("TextLabel")
moneyLabel.Size                  = UDim2.new(0, 170, 0, 38)
moneyLabel.Position              = UDim2.new(0, 15, 0, 15)
moneyLabel.BackgroundColor3      = Color3.fromRGB(15, 15, 25)
moneyLabel.BackgroundTransparency = 0.15
moneyLabel.BorderSizePixel       = 0
moneyLabel.TextColor3            = Color3.fromRGB(255, 220, 0)
moneyLabel.TextScaled            = true
moneyLabel.Font                  = Enum.Font.GothamBold
moneyLabel.Text                  = "💰 " .. moneyVal.Value
moneyLabel.Parent                = gui
Instance.new("UICorner", moneyLabel).CornerRadius = UDim.new(0, 8)

moneyVal.Changed:Connect(function()
	moneyLabel.Text = "💰 " .. moneyVal.Value
end)

-- Сообщение об ошибке (над панелью магазина)
local message = Instance.new("TextLabel")
message.AnchorPoint            = Vector2.new(0.5, 1)
message.Position               = UDim2.new(0.5, 0, 1, -110)
message.Size                   = UDim2.new(0, 360, 0, 30)
message.BackgroundTransparency = 1
message.TextColor3             = Color3.fromRGB(255, 80, 80)
message.TextScaled             = true
message.Font                   = Enum.Font.GothamBold
message.Text                   = ""
message.Visible                = false
message.Parent                 = gui

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
local BTN_W, BTN_H = 112, 78

local panel = Instance.new("Frame")
panel.AnchorPoint           = Vector2.new(0.5, 1)
panel.Position              = UDim2.new(0.5, 0, 1, -12)
panel.Size                  = UDim2.new(0, #shopTypes * (BTN_W + 6) + 12, 0, BTN_H + 16)
panel.BackgroundColor3      = Color3.fromRGB(15, 15, 25)
panel.BackgroundTransparency = 0.15
panel.BorderSizePixel       = 0
panel.Parent                = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)

local layout = Instance.new("UIListLayout")
layout.FillDirection       = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment   = Enum.VerticalAlignment.Center
layout.Padding             = UDim.new(0, 6)
layout.Parent              = panel

-- ============================================
-- РАЗМЕЩЕНИЕ
-- ============================================
local placing = nil -- {towerType, ghost, circle, price, lastPos, valid}

local function destroyPlacing()
	if placing then
		if placing.ghost then placing.ghost:Destroy() end
		if placing.circle then placing.circle:Destroy() end
		placing = nil
	end
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

	-- круг радиуса атаки
	local circle = Instance.new("Part")
	circle.Shape        = Enum.PartType.Cylinder
	circle.Size         = Vector3.new(0.15, cfg.range * 2, cfg.range * 2)
	circle.Anchored     = true
	circle.CanCollide   = false
	circle.CanQuery     = false
	circle.CastShadow   = false
	circle.Material     = Enum.Material.Neon
	circle.Transparency = 0.7
	circle.Parent       = workspace

	placing = {
		towerType = towerType,
		ghost     = ghost,
		circle    = circle,
		price     = def.price or 0,
		lastPos   = nil,
		valid     = false,
	}
end

-- Призрак следует за мышью
RunService.RenderStepped:Connect(function()
	if not placing then return end

	local mousePos = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = {placing.ghost, placing.circle}
	if player.Character then table.insert(exclude, player.Character) end
	params.FilterDescendantsInstances = exclude

	local hit = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
	if not hit then
		placing.valid = false
		return
	end

	pivotModelToGround(placing.ghost, hit.Position)
	placing.circle.CFrame = CFrame.new(hit.Position + Vector3.new(0, 0.2, 0))
		* CFrame.Angles(0, 0, math.rad(90))

	local okZone = PlacementZones.canPlace(hit.Position)
	local okMoney = moneyVal.Value >= placing.price
	placing.valid = okZone and okMoney
	placing.lastPos = hit.Position
	placing.circle.Color = placing.valid
		and Color3.fromRGB(0, 255, 120)
		or Color3.fromRGB(255, 60, 60)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if not placing then return end

	-- отмена работает даже если курсор над UI
	if input.UserInputType == Enum.UserInputType.MouseButton2
		or input.KeyCode == Enum.KeyCode.Escape then
		destroyPlacing()
		return
	end

	if processed then return end -- клик пришёлся по кнопке UI

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
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
end)

-- ============================================
-- КНОПКИ МАГАЗИНА
-- ============================================
for order, towerType in ipairs(shopTypes) do
	local def = TowerClass.getConfig(towerType)
	if def then
		local btn = Instance.new("TextButton")
		btn.Size             = UDim2.new(0, BTN_W, 0, BTN_H)
		btn.BackgroundColor3 = Color3.fromRGB(30, 30, 50)
		btn.BorderSizePixel  = 0
		btn.Text             = ""
		btn.AutoButtonColor  = true
		btn.LayoutOrder      = order
		btn.Parent           = panel
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)

		-- цветная полоска типа оружия
		local stripe = Instance.new("Frame")
		stripe.Size             = UDim2.new(1, 0, 0, 5)
		stripe.BackgroundColor3 = def.beamColor or Color3.fromRGB(255, 255, 255)
		stripe.BorderSizePixel  = 0
		stripe.Parent           = btn
		Instance.new("UICorner", stripe).CornerRadius = UDim.new(0, 8)

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size                   = UDim2.new(1, -8, 0, 34)
		nameLabel.Position               = UDim2.new(0, 4, 0, 10)
		nameLabel.BackgroundTransparency = 1
		nameLabel.TextColor3             = Color3.fromRGB(255, 255, 255)
		nameLabel.TextScaled             = true
		nameLabel.Font                   = Enum.Font.GothamBold
		nameLabel.Text                   = def.displayName or towerType
		nameLabel.Parent                 = btn

		local priceLabel = Instance.new("TextLabel")
		priceLabel.Size                   = UDim2.new(1, -8, 0, 24)
		priceLabel.Position               = UDim2.new(0, 4, 1, -28)
		priceLabel.BackgroundTransparency = 1
		priceLabel.TextColor3             = Color3.fromRGB(255, 220, 0)
		priceLabel.TextScaled             = true
		priceLabel.Font                   = Enum.Font.Gotham
		priceLabel.Text                   = "💰 " .. (def.price or 0)
		priceLabel.Parent                 = btn

		btn.Activated:Connect(function()
			startPlacing(towerType)
		end)
	end
end
