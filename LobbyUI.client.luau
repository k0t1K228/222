-- ============================================
-- МЕНЮ БАШНИ
-- ПК:  навёл курсор на башню → панель справа внизу.
-- Тач: тапнул по башне → панель; тап в пустоту — закрыть.
-- В панели: имя, уровень, владелец, режим, статы, круг радиуса,
-- кнопки «Сменить режим», «Улучшить», «Починить», «Продать».
-- Кнопки складываются снизу вверх — только видимые, без дыр.
-- ============================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")

local Classes        = ReplicatedStorage:WaitForChild("Classes")
local TowerClass     = require(Classes:WaitForChild("TowerClass"))
local Theme          = require(script.Parent:WaitForChild("Theme"))
local RangeIndicator = require(script.Parent:WaitForChild("RangeIndicator"))

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera    = workspace.CurrentCamera

local switchModeRE   = ReplicatedStorage:WaitForChild("SwitchTowerMode")
local sellTowerRF    = ReplicatedStorage:WaitForChild("SellTower")
local repairTowerRF  = ReplicatedStorage:WaitForChild("RepairTower")
local upgradeTowerRF = ReplicatedStorage:WaitForChild("UpgradeTower")

local touchEnabled = UserInputService.TouchEnabled
local SELL_REFUND = 0.7 -- держать в синхроне с TowerService

-- ============================================
-- GUI (справа внизу)
-- ============================================
local gui = Instance.new("ScreenGui")
gui.Name         = "TowerInfo"
gui.ResetOnSpawn = false
gui.Parent       = playerGui

-- Панель прижата к правому краю, но ВЫШЕ полосы магазина
-- (магазин занимает нижние ~100px по всей ширине) — не налезают
local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(1, 1)
panel.Position    = UDim2.new(1, -15, 1, -130)
panel.Size        = UDim2.new(0, 280, 0, 304)
panel.Visible     = false
panel.Parent      = gui
Theme.stylePanel(panel, Theme.COLORS.cyan)

local title = Instance.new("TextLabel")
title.Size       = UDim2.new(1, -16, 0, 34)
title.Position   = UDim2.new(0, 8, 0, 6)
title.TextScaled = true
title.Text       = "▸ БАШНЯ"
title.Parent     = panel
Theme.styleTitle(title, Theme.COLORS.cyan)

local modeLabel = Instance.new("TextLabel")
modeLabel.Size           = UDim2.new(1, -24, 0, 22)
modeLabel.Position       = UDim2.new(0, 12, 0, 44)
modeLabel.TextScaled     = true
modeLabel.TextXAlignment = Enum.TextXAlignment.Left
modeLabel.Text           = ""
modeLabel.Parent         = panel
Theme.styleText(modeLabel, Theme.COLORS.magenta)

local ownerLabel = Instance.new("TextLabel")
ownerLabel.Size           = UDim2.new(1, -24, 0, 16)
ownerLabel.Position       = UDim2.new(0, 12, 0, 66)
ownerLabel.TextScaled     = true
ownerLabel.TextXAlignment = Enum.TextXAlignment.Left
ownerLabel.Text           = ""
ownerLabel.Parent         = panel
Theme.styleText(ownerLabel, Theme.COLORS.textDim)

local statsLabel = Instance.new("TextLabel")
statsLabel.Size           = UDim2.new(1, -24, 0, 130)
statsLabel.Position       = UDim2.new(0, 12, 0, 86)
statsLabel.TextSize       = 15
statsLabel.TextXAlignment = Enum.TextXAlignment.Left
statsLabel.TextYAlignment = Enum.TextYAlignment.Top
statsLabel.Text           = ""
statsLabel.Parent         = panel
Theme.styleText(statsLabel, Theme.COLORS.textMain)

local function makeActionButton(text, accent)
	local btn = Instance.new("TextButton")
	btn.Size       = UDim2.new(1, -24, 0, 32)
	btn.TextScaled = true
	btn.Text       = text
	btn.Visible    = false
	btn.Parent     = panel
	Theme.styleButton(btn, accent)
	btn.TextColor3 = accent
	return btn
end

local switchBtn  = makeActionButton("⇄ СМЕНИТЬ РЕЖИМ", Theme.COLORS.cyan)
local upgradeBtn = makeActionButton("▲ УЛУЧШИТЬ",      Theme.COLORS.yellow)
local repairBtn  = makeActionButton("🔧 ПОЧИНИТЬ",     Theme.COLORS.green)
local sellBtn    = makeActionButton("ПРОДАТЬ",         Theme.COLORS.red)

-- Видимые кнопки складываем снизу вверх и подгоняем высоту панели,
-- чтобы между ними не было дыр от скрытых кнопок
local PANEL_TOP_HEIGHT = 226 -- заголовок + режим + владелец + статы
local function layoutButtons()
	local y = -12
	for _, btn in ipairs({sellBtn, repairBtn, upgradeBtn, switchBtn}) do
		if btn.Visible then
			y = y - 32
			btn.Position = UDim2.new(0, 12, 1, y)
			y = y - 8
		end
	end
	panel.Size = UDim2.new(0, 280, 0, PANEL_TOP_HEIGHT - y)
end

-- ============================================
-- СОСТОЯНИЕ
-- ============================================
local hoverModel     = nil
local rangeCircle    = nil
local attrConns      = {} -- подписки на атрибуты выбранной башни
local destroyingConn = nil

-- Атрибуты, при смене которых панель обновляется (живые статы)
local WATCHED_ATTRIBUTES = {"TowerMode", "TowerLevel", "TowerHealth", "TowerAmmo", "TowerReloading", "TowerStunned", "TowerDamageDealt", "TowerUnderAttack"}
local overPanel      = false
local hideAt         = nil

panel.MouseEnter:Connect(function() overPanel = true end)
panel.MouseLeave:Connect(function() overPanel = false end)

local function statText(cfg, model)
	local lines = {}

	-- Здоровье башни (боссы её сносят)
	local hp    = model:GetAttribute("TowerHealth")
	local maxHP = model:GetAttribute("TowerMaxHealth")
	if hp and maxHP then
		table.insert(lines, "❤ HP: " .. hp .. " / " .. maxHP)
	end
	if model:GetAttribute("TowerStunned") then
		table.insert(lines, "💫 ОГЛУШЕНА БОССОМ")
	end

	if cfg.attackType == "convert" then
		table.insert(lines, "Шанс вербовки: " .. math.floor(cfg.convertChance * 100) .. "%")
		table.insert(lines, "Попытка раз в " .. (1 / cfg.fireRate) .. " с")
	else
		table.insert(lines, "Урон: " .. cfg.damage)
		table.insert(lines, "Скорострельность: " .. cfg.fireRate .. "/с")
	end
	table.insert(lines, "Радиус: " .. cfg.range)

	-- Магазин и перезарядка
	if (cfg.magazine or 0) > 0 then
		if model:GetAttribute("TowerReloading") then
			table.insert(lines, "⏳ Перезарядка (" .. cfg.reloadTime .. " с)...")
		else
			local ammo = model:GetAttribute("TowerAmmo") or cfg.magazine
			table.insert(lines, "Магазин: " .. ammo .. " / " .. cfg.magazine)
		end
	end

	if cfg.attackType == "multi" then
		table.insert(lines, "Целей за залп: " .. cfg.maxTargets)
	end
	if cfg.attackType == "cone" then
		table.insert(lines, "Конус: " .. cfg.coneAngle .. "°")
	end
	if cfg.attackType == "ramp" then
		table.insert(lines, "Разгон: +" .. (cfg.rampPerSecond * 100) .. "%/с (макс ×" .. cfg.maxRampMultiplier .. ")")
	end
	if (cfg.splashRadius or 0) > 0 then
		table.insert(lines, "Радиус взрыва: " .. cfg.splashRadius)
	end

	-- по этому значению боссы выбирают, кого атаковать первым
	local dealt = model:GetAttribute("TowerDamageDealt")
	if dealt and dealt > 0 then
		table.insert(lines, "Σ Нанесено урона: " .. dealt)
	end
	return table.concat(lines, "\n")
end

local function refreshPanel()
	if not hoverModel then return end

	local towerType = hoverModel:GetAttribute("TowerType")
	local modeIdx   = hoverModel:GetAttribute("TowerMode") or 1
	local level     = hoverModel:GetAttribute("TowerLevel") or 1
	local def = towerType and TowerClass.getConfig(towerType)
	local cfg = towerType and TowerClass.getEffectiveConfig(towerType, modeIdx, level)
	if not (def and cfg) then return end

	title.Text = "▸ " .. string.upper(def.displayName or towerType)
		.. (level > 1 and ("  [УР." .. level .. "]") or "")

	local ownerId = hoverModel:GetAttribute("OwnerId") or 0
	local isMine = ownerId == player.UserId
	local canManage = (ownerId == 0 or isMine) -- своя башня или башня с карты
	if ownerId == 0 then
		ownerLabel.Text = "Башня с карты"
	else
		ownerLabel.Text = "Владелец: " .. (hoverModel:GetAttribute("OwnerName") or "?")
	end

	local modeNames = TowerClass.getModeNames(towerType)
	if modeNames then
		modeLabel.Text = "Режим: " .. (modeNames[modeIdx] or "?")
		local nextName = modeNames[(modeIdx % #modeNames) + 1]
		switchBtn.Text = "⇄ РЕЖИМ: " .. nextName
		switchBtn.Visible = canManage
	else
		modeLabel.Text = "Режим: стандартный"
		switchBtn.Visible = false
	end

	-- апгрейд: есть следующий уровень и право управлять
	local upInfo = TowerClass.getUpgradeInfo(towerType, level)
	if upInfo and canManage then
		upgradeBtn.Text = "▲ УР." .. upInfo.nextLevel .. "  −" .. Theme.money(upInfo.price)
		upgradeBtn.Visible = true
	else
		upgradeBtn.Visible = false
	end

	-- ремонт: есть потерянные HP и башня не под огнём
	-- (после урона ремонт заблокирован на REPAIR_LOCK сек; реген тоже ждёт)
	local hp    = hoverModel:GetAttribute("TowerHealth") or 0
	local maxHP = hoverModel:GetAttribute("TowerMaxHealth") or 0
	local underAttack = hoverModel:GetAttribute("TowerUnderAttack") == true
	local lost  = maxHP - hp
	if lost > 0 and canManage and not underAttack then
		local cost = math.ceil(lost * TowerClass.REPAIR_COST_PER_HP)
		repairBtn.Text = "🔧 ПОЧИНИТЬ  −" .. Theme.money(cost)
		repairBtn.Visible = true
	else
		repairBtn.Visible = false
	end

	-- продать можно только СВОЮ купленную башню;
	-- возвращается доля от всех вложений (покупка + апгрейды)
	if isMine and ownerId ~= 0 then
		local invested = TowerClass.getTotalInvested(towerType, level)
		local refund = math.floor(invested * SELL_REFUND)
		sellBtn.Text = "ПРОДАТЬ  +" .. Theme.money(refund)
		sellBtn.Visible = true
	else
		sellBtn.Visible = false
	end

	layoutButtons()
	statsLabel.Text = statText(cfg, hoverModel)

	-- круг радиуса под текущий режим и уровень
	if rangeCircle then
		rangeCircle:setRadius(cfg.range)
		rangeCircle:setColor(cfg.beamColor or Theme.COLORS.cyan)
	end
end

local function setHover(model)
	if model == hoverModel then return end

	for _, conn in ipairs(attrConns) do
		conn:Disconnect()
	end
	table.clear(attrConns)
	if destroyingConn then
		destroyingConn:Disconnect()
		destroyingConn = nil
	end
	if rangeCircle then
		rangeCircle:destroy()
		rangeCircle = nil
	end
	hoverModel = model

	if model then
		-- неоновое кольцо радиуса у подножия башни
		local bbCF, bbSize = model:GetBoundingBox()
		rangeCircle = RangeIndicator.new(Theme.COLORS.cyan)
		rangeCircle:setPosition(Vector3.new(
			bbCF.Position.X,
			bbCF.Position.Y - bbSize.Y / 2 + 0.2,
			bbCF.Position.Z
		))

		for _, attrName in ipairs(WATCHED_ATTRIBUTES) do
			table.insert(attrConns, model:GetAttributeChangedSignal(attrName):Connect(refreshPanel))
		end
		-- башню продали/убрали — закрываем панель
		destroyingConn = model.Destroying:Connect(function()
			if hoverModel == model then setHover(nil) end
		end)

		refreshPanel()
		panel.Visible = true
	else
		panel.Visible = false
	end
end

switchBtn.Activated:Connect(function()
	if hoverModel then
		switchModeRE:FireServer(hoverModel)
	end
end)

sellBtn.Activated:Connect(function()
	if not hoverModel then return end
	local result = sellTowerRF:InvokeServer(hoverModel)
	if result and result.ok then
		setHover(nil) -- модель уничтожена сервером
	elseif result and result.err then
		sellBtn.Text = result.err
		task.delay(1.5, refreshPanel)
	end
end)

upgradeBtn.Activated:Connect(function()
	if not hoverModel then return end
	local result = upgradeTowerRF:InvokeServer(hoverModel)
	if result and not result.ok and result.err then
		upgradeBtn.Text = result.err
		task.delay(1.5, refreshPanel)
	end
	-- при успехе панель обновит атрибут TowerLevel
end)

repairBtn.Activated:Connect(function()
	if not hoverModel then return end
	local result = repairTowerRF:InvokeServer(hoverModel)
	if result and not result.ok and result.err then
		repairBtn.Text = result.err
		task.delay(1.5, refreshPanel)
	end
	-- при успехе панель обновит атрибут TowerHealth
end)

-- ============================================
-- ВЫБОР БАШНИ
-- ============================================

-- Башня под экранной точкой (рейкаст из камеры)
local function towerAtScreenPoint(x, y)
	local ray = camera:ViewportPointToRay(x, y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = {}
	if player.Character then table.insert(exclude, player.Character) end
	if rangeCircle then table.insert(exclude, rangeCircle.folder) end
	params.FilterDescendantsInstances = exclude

	local hit = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
	local inst = hit and hit.Instance
	while inst and inst ~= workspace do
		if inst:IsA("Model") and inst:GetAttribute("TowerActive") then
			return inst
		end
		inst = inst.Parent
	end
	return nil
end

if touchEnabled then
	-- Тач: тап по башне выбирает, тап в пустоту закрывает
	UserInputService.InputBegan:Connect(function(input, processed)
		if input.UserInputType ~= Enum.UserInputType.Touch then return end
		if processed then return end
		local found = towerAtScreenPoint(input.Position.X, input.Position.Y)
		setHover(found)
	end)
else
	-- ПК: наведение курсора (с троттлингом)
	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		acc = acc + dt
		if acc < 0.08 then return end
		acc = 0

		local mousePos = UserInputService:GetMouseLocation()
		local found = towerAtScreenPoint(mousePos.X, mousePos.Y)

		if found then
			setHover(found)
			hideAt = nil
		elseif hoverModel then
			-- не прячем сразу: даём время довести курсор до панели
			if overPanel then
				hideAt = nil
			else
				hideAt = hideAt or os.clock() + 0.5
				if os.clock() >= hideAt then
					setHover(nil)
					hideAt = nil
				end
			end
		end
	end)
end
