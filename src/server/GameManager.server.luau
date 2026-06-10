local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")
local Players           = game:GetService("Players")

local EnemyClass     = require(ReplicatedStorage.Classes.EnemyClass)
local BaseClass      = require(ReplicatedStorage.Classes.BaseClass)
local TowerClass     = require(ReplicatedStorage.Classes.TowerClass)
local PlacementZones = require(ReplicatedStorage.Classes.PlacementZones)

-- ============================================
-- НАСТРОЙКИ
-- ============================================
local START_MONEY = 400 -- стартовая валюта игрока
local KILL_REWARD = 25  -- награда каждому игроку за убитого врага

-- mapEvent — событие карты ПОСЛЕ волны: открыть/закрыть маршруты.
-- Имена маршрутов = имена папок внутри WaypointsFolder.
local WAVES = {
	{count = 3, spawnDelay = 2,   pauseAfter = 5},
	{count = 5, spawnDelay = 1.5, pauseAfter = 8},
	{count = 8, spawnDelay = 1,   pauseAfter = 10},
	-- Пример с событием карты:
	-- {count = 8, spawnDelay = 1, pauseAfter = 10,
	--  mapEvent = {open = {"Route2"}, close = {"Route1"}}},
}

-- ============================================
-- GAMEDATA ДЛЯ СИНХРОНИЗАЦИИ С UI
-- ============================================
local gameData = Instance.new("Folder")
gameData.Name = "GameData"
gameData.Parent = ReplicatedStorage

local function makeValue(valueType, name, default)
	local v = Instance.new(valueType)
	v.Name = name
	v.Value = default
	v.Parent = gameData
	return v
end

local _baseHPValue  = makeValue("NumberValue", "BaseHP",      10000)
local _maxHPValue   = makeValue("NumberValue", "MaxBaseHP",   10000)
local waveValue     = makeValue("NumberValue", "CurrentWave", 0)
local _maxWaveValue = makeValue("NumberValue", "MaxWaves",    #WAVES)
local enemyCountVal = makeValue("NumberValue", "EnemyCount",  0)
local gameOverValue = makeValue("BoolValue",   "GameOver",    false)

-- Хук для будущих кат-сцен: клиент слушает это событие
local mapChangedEvent = Instance.new("RemoteEvent")
mapChangedEvent.Name = "MapChanged"
mapChangedEvent.Parent = ReplicatedStorage

-- Размещение башни игроком (клиент -> сервер)
local placeTowerRF = Instance.new("RemoteFunction")
placeTowerRF.Name = "PlaceTower"
placeTowerRF.Parent = ReplicatedStorage

-- Переключение режима атаки башни
local switchModeRE = Instance.new("RemoteEvent")
switchModeRE.Name = "SwitchTowerMode"
switchModeRE.Parent = ReplicatedStorage

-- ============================================
-- ВАЛЮТА (leaderstats)
-- ============================================
local function getMoney(player)
	local stats = player:FindFirstChild("leaderstats")
	return stats and stats:FindFirstChild("Money")
end

local function setupPlayer(player)
	if player:FindFirstChild("leaderstats") then return end
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	stats.Parent = player

	local money = Instance.new("IntValue")
	money.Name = "Money"
	money.Value = START_MONEY
	money.Parent = stats
end

Players.PlayerAdded:Connect(setupPlayer)
for _, p in ipairs(Players:GetPlayers()) do setupPlayer(p) end

local function rewardAllPlayers(amount)
	for _, p in ipairs(Players:GetPlayers()) do
		local money = getMoney(p)
		if money then money.Value = money.Value + amount end
	end
end

-- ============================================
-- МАРШРУТЫ
-- WaypointsFolder может содержать:
--   а) просто пронумерованные точки → один маршрут "Main"
--   б) папки (Route1, Route2, ...) с точками → несколько маршрутов,
--      враг выбирает случайный из включённых.
-- Атрибут Enabled = false на папке выключает маршрут.
-- ============================================
local waypointsFolder = workspace:WaitForChild("WaypointsFolder")

local function sortedWaypoints(container)
	local parts = {}
	for _, obj in ipairs(container:GetChildren()) do
		if obj:IsA("BasePart") then
			obj.CanCollide   = false
			obj.Anchored     = true
			obj.Transparency = 1
			obj.CanQuery     = false
			table.insert(parts, obj)
		end
	end
	table.sort(parts, function(a, b)
		return (tonumber(a.Name:match("%d+")) or 0) < (tonumber(b.Name:match("%d+")) or 0)
	end)
	return parts
end

local routes = {}
do
	local subfolders = {}
	for _, child in ipairs(waypointsFolder:GetChildren()) do
		if child:IsA("Folder") or child:IsA("Model") then
			table.insert(subfolders, child)
		end
	end

	if #subfolders > 0 then
		for _, folder in ipairs(subfolders) do
			local wps = sortedWaypoints(folder)
			if #wps > 0 then
				table.insert(routes, {name = folder.Name, container = folder, waypoints = wps})
			end
		end
	else
		local wps = sortedWaypoints(waypointsFolder)
		table.insert(routes, {name = "Main", container = waypointsFolder, waypoints = wps})
	end

	if #routes == 0 then
		warn("WaypointsFolder пуст — врагам некуда идти!")
	end
end

local function isRouteEnabled(route)
	return route.container:GetAttribute("Enabled") ~= false
end

-- Случайный маршрут из включённых
local function pickRoute()
	local enabled = {}
	for _, r in ipairs(routes) do
		if isRouteEnabled(r) then table.insert(enabled, r) end
	end
	if #enabled == 0 then return routes[1] end
	return enabled[math.random(#enabled)]
end

local function setRouteEnabled(name, on)
	for _, r in ipairs(routes) do
		if r.name == name then
			r.container:SetAttribute("Enabled", on)
		end
	end
end

local function applyMapEvent(event)
	if not event then return end
	for _, name in ipairs(event.open or {}) do setRouteEnabled(name, true) end
	for _, name in ipairs(event.close or {}) do setRouteEnabled(name, false) end
	mapChangedEvent:FireAllClients(event) -- хук для кат-сцены на клиенте
	print("Карта изменилась! Открыто: " .. table.concat(event.open or {}, ", ")
		.. " | Закрыто: " .. table.concat(event.close or {}, ", "))
end

-- ============================================
-- БАЗА И СПИСКИ
-- ============================================
local base          = BaseClass.new(workspace:WaitForChild("GeneralTower"))
local activeEnemies = {}
local activeTowers  = {}
local towersByModel = {} -- модель -> объект башни (для свитча режимов)

base.onDestroyed = function()
	gameOverValue.Value = true
	for _, tower in ipairs(activeTowers) do
		tower:stopAttacking()
	end
end

-- ============================================
-- БАШНИ: АКТИВАЦИЯ
-- ============================================
local function tryActivateTower(model)
	if not model:IsA("Model") then return end
	if model:GetAttribute("TowerActive") then return end -- защита от двойной активации

	local towerType = TowerClass.resolveType(model)
	if not towerType then return end

	local pos = model:GetPivot().Position
	if not PlacementZones.isAllowed(pos) then
		warn("Башня '" .. model.Name .. "' стоит вне зоны размещения — не активирована")
		return
	end

	model:SetAttribute("TowerActive", true)
	local tower = TowerClass.new(model, towerType)
	table.insert(activeTowers, tower)
	towersByModel[model] = tower
	tower:startAttacking(function() return activeEnemies end)
	print("Башня активирована: " .. towerType)
end

local function scanTowers()
	for _, obj in ipairs(workspace:GetChildren()) do
		tryActivateTower(obj)
	end
end

workspace.ChildAdded:Connect(function(child)
	task.wait(0.1)
	tryActivateTower(child)
end)

-- ============================================
-- ШАБЛОНЫ БАШЕН ДЛЯ МАГАЗИНА
-- Пока нет своих моделей — клонируем Rust и вешаем цветной
-- кристалл по типу оружия. Шаблоны лежат в ReplicatedStorage,
-- чтобы клиент мог показывать «призрак» при размещении.
-- ============================================
local templatesFolder = Instance.new("Folder")
templatesFolder.Name = "TowerTemplates"
templatesFolder.Parent = ReplicatedStorage

local function buildTowerTemplates()
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

buildTowerTemplates()

-- ============================================
-- РАЗМЕЩЕНИЕ БАШНИ ИГРОКОМ
-- Вся валидация на сервере: тип, деньги, зона, дистанция.
-- ============================================

-- Ставим модель дном на точку
local function pivotModelToGround(model, position)
	local bbCF, bbSize = model:GetBoundingBox()
	local pivotY = model:GetPivot().Position.Y
	local bottomOffset = pivotY - (bbCF.Position.Y - bbSize.Y / 2)
	model:PivotTo(CFrame.new(position + Vector3.new(0, bottomOffset, 0)))
end

placeTowerRF.OnServerInvoke = function(player, towerType, position)
	if typeof(towerType) ~= "string" or typeof(position) ~= "Vector3" then
		return {ok = false, err = "Некорректный запрос"}
	end

	local def = TowerClass.getConfig(towerType)
	local template = templatesFolder:FindFirstChild(towerType)
	if not def or not template then
		return {ok = false, err = "Неизвестная башня"}
	end

	local okPlace, reason = PlacementZones.canPlace(position)
	if not okPlace then
		return {ok = false, err = reason}
	end

	local money = getMoney(player)
	local price = def.price or 0
	if not money or money.Value < price then
		return {ok = false, err = "Недостаточно денег (нужно " .. price .. ")"}
	end

	local model = template:Clone()
	pivotModelToGround(model, position)
	model.Parent = workspace

	money.Value = money.Value - price
	tryActivateTower(model)
	return {ok = true}
end

-- ============================================
-- СВИТЧ РЕЖИМА АТАКИ
-- ============================================
switchModeRE.OnServerEvent:Connect(function(_player, model)
	if typeof(model) ~= "Instance" then return end
	local tower = towersByModel[model]
	if tower then
		tower:nextMode()
		print("Башня " .. tower.type .. " переключена в режим: "
			.. tostring(model:GetAttribute("TowerModeName")))
	end
end)

-- ============================================
-- ШАБЛОН ВРАГА
-- Переносим из Workspace в ServerStorage, чтобы шаблон
-- не стоял на карте и башни его не атаковали.
-- ============================================
local enemyTemplate = ServerStorage:FindFirstChild("skibidi toilet")
if not enemyTemplate then
	local t = workspace:FindFirstChild("skibidi toilet")
	if t then
		t.Parent = ServerStorage
		enemyTemplate = t
	end
end
if not enemyTemplate then
	warn("Модель 'skibidi toilet' не найдена ни в ServerStorage, ни в Workspace!")
end

-- ============================================
-- СПАВН ВРАГА
-- ============================================
local function spawnEnemy()
	if not enemyTemplate then return end

	local route = pickRoute()
	if not route or #route.waypoints == 0 then return end
	local waypoints = route.waypoints

	local model = enemyTemplate:Clone()

	-- Сначала собираем врага (сварка деталей к rootPart),
	-- потом кладём в мир и ставим на точку спавна
	local enemy = EnemyClass.new(model, waypoints, base)
	if not enemy then return end

	model.Parent = workspace
	enemy:teleportTo(waypoints[1].Position + Vector3.new(0, 3, 0))

	table.insert(activeEnemies, enemy)
	enemyCountVal.Value = #activeEnemies

	-- Убираем из списка когда умрёт; за убийство башней — награда
	enemy.onDied = function()
		for i, e in ipairs(activeEnemies) do
			if e == enemy then
				table.remove(activeEnemies, i)
				break
			end
		end
		enemyCountVal.Value = #activeEnemies

		if enemy.killedByDamage then
			rewardAllPlayers(KILL_REWARD)
		end
	end

	task.spawn(function() enemy:move() end)
end

-- ============================================
-- ВОЛНЫ
-- ============================================
task.wait(1)
scanTowers()

task.spawn(function()
	for waveIndex, wave in ipairs(WAVES) do
		if not base.isAlive then break end

		waveValue.Value = waveIndex
		print("=== ВОЛНА " .. waveIndex .. " / " .. #WAVES .. " ===")

		for i = 1, wave.count do
			if not base.isAlive then break end
			spawnEnemy()
			task.wait(wave.spawnDelay)
		end

		-- Событие карты после волны (открытие/закрытие маршрутов)
		applyMapEvent(wave.mapEvent)

		if waveIndex < #WAVES then
			print("Следующая волна через " .. wave.pauseAfter .. " сек...")
			task.wait(wave.pauseAfter)
		end
	end

	if base.isAlive then
		print("Все волны завершены — ПОБЕДА!")
	end
end)
