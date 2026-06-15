-- ============================================
-- СЕРВИС БАШЕН (серверный модуль)
-- Шаблоны, активация, покупка/размещение, продажа, свитч режимов.
-- Вся валидация — здесь, клиенту не доверяем:
--   * рейт-лимит на действия игрока
--   * проверка координат (NaN/бесконечность/выход за карту)
--   * посадка на землю серверным рейкастом (Y клиента игнорируется)
--   * зона + мин. дистанция
--   * владелец: продавать и переключать можно только СВОЮ башню
--     (башни с карты, OwnerId = 0, может переключать любой)
-- ============================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local TowerClass     = require(ReplicatedStorage.Classes.TowerClass)
local PlacementZones = require(ReplicatedStorage.Classes.PlacementZones)
local Economy        = require(script.Parent.Economy)

local TowerService = {}

local SELL_REFUND     = 0.7  -- доля цены, возвращаемая при продаже
local ACTION_COOLDOWN = 0.3  -- сек между действиями одного игрока (антиспам)
local MAX_COORD       = 5000 -- координаты больше этого не принимаем

local activeTowers  = {}
local towersByModel = {} -- модель -> объект башни
local getEnemies    = function() return {} end
local lastActionAt  = {} -- [player] = os.clock()
local templatesFolder

-- Снапшоты студийных башен (расставленных на карте): босс может
-- уничтожить такую башню, при рестарте раунда возвращаем её из копии
local studioSnapshots   = {} -- {clone = чистая копия, model = текущая модель}
local suppressSnapshot  = false -- не снапшотить башни, которые сами восстанавливаем

Players.PlayerRemoving:Connect(function(player)
	lastActionAt[player] = nil
end)

-- ============================================
-- ВАЛИДАЦИЯ
-- ============================================

local function rateLimited(player)
	local now = os.clock()
	local last = lastActionAt[player]
	if last and now - last < ACTION_COOLDOWN then
		return true
	end
	lastActionAt[player] = now
	return false
end

local function isSaneVector(v)
	if typeof(v) ~= "Vector3" then return false end
	-- NaN не равен сам себе
	if v.X ~= v.X or v.Y ~= v.Y or v.Z ~= v.Z then return false end
	return math.abs(v.X) < MAX_COORD
		and math.abs(v.Y) < MAX_COORD
		and math.abs(v.Z) < MAX_COORD
end

-- Сервер сам сажает башню на землю — Y от клиента игнорируется,
-- так нельзя поставить башню в воздухе
local function snapToGround(position)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = {}
	for model in pairs(towersByModel) do
		table.insert(exclude, model)
	end
	params.FilterDescendantsInstances = exclude

	local hit = workspace:Raycast(
		Vector3.new(position.X, position.Y + 50, position.Z),
		Vector3.new(0, -300, 0),
		params
	)
	return hit and hit.Position or nil
end

-- Ставим модель дном на точку
local function pivotModelToGround(model, position)
	local bbCF, bbSize = model:GetBoundingBox()
	local pivotY = model:GetPivot().Position.Y
	local bottomOffset = pivotY - (bbCF.Position.Y - bbSize.Y / 2)
	model:PivotTo(CFrame.new(position + Vector3.new(0, bottomOffset, 0)))
end

-- ============================================
-- ШАБЛОНЫ
-- Пока нет своих моделей — клонируем Rust и вешаем цветной
-- кристалл по типу оружия. Лежат в ReplicatedStorage,
-- чтобы клиент мог показывать «призрак» при размещении.
-- ============================================

local function buildTowerTemplates()
	templatesFolder = Instance.new("Folder")
	templatesFolder.Name = "TowerTemplates"
	templatesFolder.Parent = ReplicatedStorage

	local source = workspace:FindFirstChild("Rust")

	for _, towerType in ipairs(TowerClass.SHOP_ORDER) do
		local cfg = TowerClass.getEffectiveConfig(towerType, 1)
		local model

		if source then
			model = source:Clone()
		else
			-- запасной вариант: простая башня-столб
			model = Instance.new("Model")
			local body = Instance.new("Part")
			body.Name = "Body"
			body.Size = Vector3.new(3, 7, 3)
			body.Color = Color3.fromRGB(120, 120, 130)
			body.Parent = model
		end

		model.Name = towerType
		model:SetAttribute("TowerActive", nil)
		model:SetAttribute("TowerType", towerType)

		-- внутри модели Rust сидят старые скрипты — вычищаем
		for _, obj in ipairs(model:GetDescendants()) do
			if obj:IsA("Script") or obj:IsA("LocalScript") then
				obj:Destroy()
			end
		end

		-- якорим всё и назначаем PrimaryPart (самая большая деталь)
		local biggest, biggestVolume = nil, 0
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Anchored = true
				local volume = p.Size.X * p.Size.Y * p.Size.Z
				if volume > biggestVolume then
					biggest, biggestVolume = p, volume
				end
			end
		end
		model.PrimaryPart = biggest

		-- цветной кристалл, чтобы отличать типы, пока нет моделей
		if biggest then
			local bbCF, bbSize = model:GetBoundingBox()
			local crystal = Instance.new("Part")
			crystal.Name = "TypeCrystal"
			crystal.Shape = Enum.PartType.Ball
			crystal.Size = Vector3.new(1.4, 1.4, 1.4)
			crystal.Material = Enum.Material.Neon
			crystal.Color = cfg.beamColor
			crystal.Anchored = true
			crystal.CanCollide = false
			crystal.CanQuery = false
			crystal.Position = bbCF.Position + Vector3.new(0, bbSize.Y / 2 + 1.2, 0)
			crystal.Parent = model
		end

		model.Parent = templatesFolder
	end
end

-- ============================================
-- АКТИВАЦИЯ И РЕЕСТР
-- ============================================

local function removeTower(tower)
	towersByModel[tower.model] = nil
	for i, t in ipairs(activeTowers) do
		if t == tower then
			table.remove(activeTowers, i)
			break
		end
	end
	tower:destroy()
end

-- Список живых башен — для боссов и стан-врагов
function TowerService.getTowers()
	return activeTowers
end

-- owner: Player, купивший башню (nil для башен, расставленных в Studio)
function TowerService.tryActivate(model, owner)
	if not model:IsA("Model") then return end
	if model:GetAttribute("TowerActive") then return end -- защита от двойной активации

	local towerType = TowerClass.resolveType(model)
	if not towerType then return end

	local pos = model:GetPivot().Position
	if not PlacementZones.isAllowed(pos) then
		warn("Башня '" .. model.Name .. "' стоит вне зоны размещения — не активирована")
		return
	end
	if not owner and not PlacementZones.isFarFromTowers(pos) then
		-- студийные башни не блокируем, но предупреждаем картоделов
		warn("Башня '" .. model.Name .. "' стоит ближе "
			.. PlacementZones.MIN_TOWER_DISTANCE .. " стадов к другой башне")
	end

	model:SetAttribute("TowerActive", true)

	-- Студийная башня: запоминаем чистую копию ДО того, как TowerClass
	-- добавит билборды/скейл — чтобы вернуть её после рестарта раунда
	if not owner and not suppressSnapshot then
		local snap = model:Clone()
		snap:SetAttribute("TowerActive", nil)
		table.insert(studioSnapshots, {clone = snap, model = model})
	end

	local tower = TowerClass.new(model, towerType, owner and owner.UserId or nil)
	if owner then
		model:SetAttribute("OwnerName", owner.Name)
	end

	-- босс снёс HP башни — убираем её из реестра и удаляем модель
	tower.onDestroyed = function()
		removeTower(tower)
	end

	table.insert(activeTowers, tower)
	towersByModel[model] = tower
	tower:startAttacking(getEnemies)
	print("Башня активирована: " .. towerType)
	return tower
end

function TowerService.stopAll()
	for _, tower in ipairs(activeTowers) do
		tower:stopAttacking()
	end
end

-- Рестарт игры — «чистое поле»:
--   * купленные башни убираются, владельцу возвращается 100% вложений
--     (если игрок вышел с сервера — возврат сгорает, см. HANDBOOK ч.3)
--   * студийные башни чинятся; уничтоженные боссом — восстанавливаются
--     из снапшота
function TowerService.resetForNewRound()
	for _, tower in ipairs(table.clone(activeTowers)) do
		if tower.ownerId then
			local owner = Players:GetPlayerByUserId(tower.ownerId)
			if owner then
				Economy.give(owner, TowerClass.getTotalInvested(tower.type, tower.level))
			end
			removeTower(tower)
		else
			tower:resetForNewGame()
			tower:startAttacking(getEnemies)
		end
	end

	-- возвращаем уничтоженные студийные башни на место
	suppressSnapshot = true
	for _, snap in ipairs(studioSnapshots) do
		if not (snap.model and snap.model.Parent) then
			local model = snap.clone:Clone()
			model.Parent = workspace
			TowerService.tryActivate(model)
			snap.model = model
		end
	end
	suppressSnapshot = false
end

-- ============================================
-- РЕМОУТЫ
-- ============================================

local function setupRemotes()
	local placeTowerRF = Instance.new("RemoteFunction")
	placeTowerRF.Name = "PlaceTower"
	placeTowerRF.Parent = ReplicatedStorage

	local sellTowerRF = Instance.new("RemoteFunction")
	sellTowerRF.Name = "SellTower"
	sellTowerRF.Parent = ReplicatedStorage

	local switchModeRE = Instance.new("RemoteEvent")
	switchModeRE.Name = "SwitchTowerMode"
	switchModeRE.Parent = ReplicatedStorage

	local repairTowerRF = Instance.new("RemoteFunction")
	repairTowerRF.Name = "RepairTower"
	repairTowerRF.Parent = ReplicatedStorage

	local upgradeTowerRF = Instance.new("RemoteFunction")
	upgradeTowerRF.Name = "UpgradeTower"
	upgradeTowerRF.Parent = ReplicatedStorage

	-- ПОКУПКА И РАЗМЕЩЕНИЕ
	placeTowerRF.OnServerInvoke = function(player, towerType, position)
		if rateLimited(player) then
			return {ok = false, err = "Слишком часто, подожди"}
		end
		if typeof(towerType) ~= "string" or not isSaneVector(position) then
			return {ok = false, err = "Некорректный запрос"}
		end

		local def = TowerClass.getConfig(towerType)
		local template = templatesFolder and templatesFolder:FindFirstChild(towerType)
		if not def or not template then
			return {ok = false, err = "Неизвестная башня"}
		end

		local ground = snapToGround(position)
		if not ground then
			return {ok = false, err = "Здесь нет земли"}
		end

		local okPlace, reason = PlacementZones.canPlace(ground)
		if not okPlace then
			return {ok = false, err = reason}
		end

		local price = def.price or 0
		if not Economy.spend(player, price) then
			return {ok = false, err = "Недостаточно денег (нужно " .. price .. ")"}
		end

		local model = template:Clone()
		pivotModelToGround(model, ground)
		model.Parent = workspace
		TowerService.tryActivate(model, player)
		return {ok = true}
	end

	-- ПРОДАЖА (только своя башня)
	sellTowerRF.OnServerInvoke = function(player, model)
		if rateLimited(player) then
			return {ok = false, err = "Слишком часто"}
		end
		if typeof(model) ~= "Instance" then
			return {ok = false, err = "Некорректный запрос"}
		end

		local tower = towersByModel[model]
		if not tower then
			return {ok = false, err = "Это не башня"}
		end
		if not tower.ownerId then
			return {ok = false, err = "Башню с карты продать нельзя"}
		end
		if tower.ownerId ~= player.UserId then
			return {ok = false, err = "Это не твоя башня"}
		end

		-- возвращаем долю от ВСЕХ вложений: покупка + апгрейды
		local invested = TowerClass.getTotalInvested(tower.type, tower.level)
		local refund = math.floor(invested * SELL_REFUND)
		Economy.give(player, refund)
		removeTower(tower)
		return {ok = true, refund = refund}
	end

	-- РЕМОНТ (своя башня или башня с карты; платит тот, кто чинит)
	repairTowerRF.OnServerInvoke = function(player, model)
		if rateLimited(player) then
			return {ok = false, err = "Слишком часто"}
		end
		if typeof(model) ~= "Instance" then
			return {ok = false, err = "Некорректный запрос"}
		end

		local tower = towersByModel[model]
		if not tower then
			return {ok = false, err = "Это не башня"}
		end
		if tower.ownerId and tower.ownerId ~= player.UserId then
			return {ok = false, err = "Это не твоя башня"}
		end

		local lost = tower.maxHealth - tower.health
		if lost <= 0 then
			return {ok = false, err = "Башня цела"}
		end
		if not tower:canRepairNow() then
			return {ok = false, err = "Башня под огнём!"}
		end

		local cost = math.ceil(lost * TowerClass.REPAIR_COST_PER_HP)
		if not Economy.spend(player, cost) then
			return {ok = false, err = "Недостаточно денег (нужно " .. cost .. ")"}
		end

		tower:repairFull()
		return {ok = true}
	end

	-- АПГРЕЙД (своя башня или башня с карты; платит тот, кто качает)
	upgradeTowerRF.OnServerInvoke = function(player, model)
		if rateLimited(player) then
			return {ok = false, err = "Слишком часто"}
		end
		if typeof(model) ~= "Instance" then
			return {ok = false, err = "Некорректный запрос"}
		end

		local tower = towersByModel[model]
		if not tower then
			return {ok = false, err = "Это не башня"}
		end
		if tower.ownerId and tower.ownerId ~= player.UserId then
			return {ok = false, err = "Это не твоя башня"}
		end

		local info = TowerClass.getUpgradeInfo(tower.type, tower.level)
		if not info then
			return {ok = false, err = "Максимальный уровень"}
		end
		if not Economy.spend(player, info.price) then
			return {ok = false, err = "Недостаточно денег (нужно " .. info.price .. ")"}
		end

		tower:upgrade()
		return {ok = true}
	end

	-- СВИТЧ РЕЖИМА (своя башня или башня с карты)
	switchModeRE.OnServerEvent:Connect(function(player, model)
		if rateLimited(player) then return end
		if typeof(model) ~= "Instance" then return end

		local tower = towersByModel[model]
		if not tower then return end
		if tower.ownerId and tower.ownerId ~= player.UserId then return end

		tower:nextMode()
	end)
end

-- ============================================
-- ИНИЦИАЛИЗАЦИЯ
-- ============================================

function TowerService.init(opts)
	getEnemies = opts.getEnemies or getEnemies

	buildTowerTemplates()
	setupRemotes()

	-- активируем башни, расставленные в Studio
	for _, obj in ipairs(workspace:GetChildren()) do
		TowerService.tryActivate(obj)
	end
	workspace.ChildAdded:Connect(function(child)
		task.wait(0.1)
		TowerService.tryActivate(child)
	end)
end

return TowerService
