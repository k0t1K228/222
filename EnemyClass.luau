-- ============================================
-- ГЛАВНЫЙ СЕРВЕРНЫЙ СКРИПТ
-- Здесь: GameData, маршруты, спавн врагов и боссов, цикл волн.
-- Экономика — в модуле Economy, башни — в TowerService,
-- тестовая локация — в TestMap.
-- ============================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")
local Players           = game:GetService("Players")

local EnemyClass   = require(ReplicatedStorage.Classes.EnemyClass)
local BossClass    = require(ReplicatedStorage.Classes.BossClass)
local BaseClass    = require(ReplicatedStorage.Classes.BaseClass)
local Economy      = require(script.Parent.Economy)
local TowerService = require(script.Parent.TowerService)
local TestMap      = require(script.Parent.TestMap)

-- ============================================
-- НАСТРОЙКИ ВОЛН
-- hpMult/speedMult — множители HP и скорости врагов этой волны.
-- stunners — сколько врагов волны умеют глушить башни (жёлтый шар).
-- bosses   — список боссов волны (имена из BossClass.CONFIGS),
--            спавнятся в начале волны и летают по карте вне маршрутов.
-- mapEvent — событие карты ПОСЛЕ волны: открыть/закрыть маршруты
--            (имена = папки внутри WaypointsFolder).
-- Волна считается законченной, когда убиты ВСЕ её враги и боссы
-- (перевербованные союзники не в счёт).
-- ============================================
-- Радиусы башен подняли (~+30%) — поздние волны тоже усилены,
-- чтобы сложность не просела (больше врагов и HP)
local WAVES = {
	{count = 3,  spawnDelay = 2,   pauseAfter = 5},
	{count = 5,  spawnDelay = 1.5, pauseAfter = 8,  hpMult = 1.5, stunners = 2},
	{count = 8,  spawnDelay = 1,   pauseAfter = 10, hpMult = 2.2, speedMult = 1.2, bosses = {"StunCopter"}},
	{count = 12, spawnDelay = 1,   pauseAfter = 10, hpMult = 2.8, speedMult = 1.2, stunners = 3, bosses = {"DestroyerCopter"}},
	{count = 14, spawnDelay = 0.8, pauseAfter = 10, hpMult = 3.4, speedMult = 1.3, stunners = 4, bosses = {"StunCopter", "DestroyerCopter"}},
	-- Пример с событием карты:
	-- {count = 8, spawnDelay = 1, pauseAfter = 10, hpMult = 3,
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
local victoryValue  = makeValue("BoolValue",   "Victory",     false)

-- Хук для будущих кат-сцен: клиент слушает это событие
local mapChangedEvent = Instance.new("RemoteEvent")
mapChangedEvent.Name = "MapChanged"
mapChangedEvent.Parent = ReplicatedStorage

-- Предупреждение «БОСС ПРИБЛИЖАЕТСЯ» за BOSS_WARNING_TIME сек до спавна
local BOSS_WARNING_TIME = 4
local bossWarningEvent = Instance.new("RemoteEvent")
bossWarningEvent.Name = "BossWarning"
bossWarningEvent.Parent = ReplicatedStorage

-- Кнопка «Играть снова» после победы/поражения
local restartEvent = Instance.new("RemoteEvent")
restartEvent.Name = "RequestRestart"
restartEvent.Parent = ReplicatedStorage

Economy.init()

-- Достраиваем тестовую локацию (второй маршрут, зоны, здания)
-- ДО разбора маршрутов, чтобы Route1/Route2 попали в parsing
TestMap.build()

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
-- БАЗА, ВРАГИ И БОССЫ
-- ============================================
local base          = BaseClass.new(workspace:WaitForChild("GeneralTower"))
local activeEnemies = {}

base.onDestroyed = function()
	gameOverValue.Value = true
	TowerService.stopAll()
end

-- Враги в списке могут быть перевербованы (friendly) — такие
-- не считаются «угрозой»: волна их не ждёт, счётчик их не показывает
local function hostilesLeft()
	local n = 0
	for _, e in ipairs(activeEnemies) do
		if not e.friendly then n = n + 1 end
	end
	return n
end

local function removeFromActive(unit)
	for i, e in ipairs(activeEnemies) do
		if e == unit then
			table.remove(activeEnemies, i)
			break
		end
	end
	enemyCountVal.Value = hostilesLeft()
end

-- Шаблон врага: переносим из Workspace в ServerStorage,
-- чтобы он не стоял на карте и башни его не атаковали
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

local function spawnEnemy(waveOpts, isStunner)
	if not enemyTemplate then return end

	local route = pickRoute()
	if not route or #route.waypoints == 0 then return end
	local waypoints = route.waypoints

	local model = enemyTemplate:Clone()

	-- Сначала собираем врага (сварка деталей к rootPart),
	-- потом кладём в мир и ставим на точку спавна
	local enemy = EnemyClass.new(model, waypoints, base, {
		hpMult    = waveOpts.hpMult,
		speedMult = waveOpts.speedMult,
		stunner   = isStunner,
		getTowers = TowerService.getTowers,
	})
	if not enemy then return end

	model.Parent = workspace
	enemy:teleportTo(waypoints[1].Position + Vector3.new(0, 3, 0))

	table.insert(activeEnemies, enemy)
	enemyCountVal.Value = hostilesLeft()

	-- Убираем из списка когда умрёт; за убийство уроном — награда
	-- (за гибель союзника и самоподрыв о базу награды нет)
	enemy.onDied = function()
		removeFromActive(enemy)
		if enemy.killedByDamage and not enemy.friendly then
			Economy.rewardAll(Economy.KILL_REWARD)
		end
	end

	task.spawn(function() enemy:move() end)
end

-- Босс: спавнится над началом маршрута, дальше летает сам
-- (от башни к башне, приоритет — самая дамажная)
local function spawnBoss(bossType)
	local route = pickRoute()
	local spawnPos
	if route and #route.waypoints > 0 then
		spawnPos = route.waypoints[1].Position + Vector3.new(0, 20, 0)
	end

	local boss = BossClass.new(bossType, {
		getTowers = TowerService.getTowers,
		anchor    = base.model:GetPivot().Position,
		spawnPos  = spawnPos,
		base      = base, -- таранит базу, если все башни уничтожены (анти-софтлок)
	})
	if not boss then return end

	table.insert(activeEnemies, boss)
	enemyCountVal.Value = hostilesLeft()
	print("БОСС: " .. (BossClass.CONFIGS[bossType].displayName or bossType))

	boss.onDied = function()
		removeFromActive(boss)
		if boss.killedByDamage then
			Economy.rewardAll(Economy.BOSS_REWARD)
		end
	end
end

-- ============================================
-- СТАРТ И ЦИКЛ ВОЛН (с рестартом после победы/поражения)
-- ============================================
task.wait(1)
TowerService.init({
	getEnemies = function() return activeEnemies end,
})

-- Один прогон всех волн; выходит при победе или гибели базы
local function runWaves()
	for waveIndex, wave in ipairs(WAVES) do
		if not base.isAlive then break end

		waveValue.Value = waveIndex
		print("=== ВОЛНА " .. waveIndex .. " / " .. #WAVES .. " ===")

		-- Боссы волны: сначала предупреждение всем игрокам, потом спавн
		if wave.bosses and #wave.bosses > 0 then
			local names = {}
			for _, bossType in ipairs(wave.bosses) do
				local cfg = BossClass.CONFIGS[bossType]
				table.insert(names, cfg and cfg.displayName or bossType)
			end
			bossWarningEvent:FireAllClients(names)
			task.wait(BOSS_WARNING_TIME)
			for _, bossType in ipairs(wave.bosses) do
				spawnBoss(bossType)
			end
		end

		-- Обычные враги; stunners штук из них раскидываем
		-- равномерно-случайно по волне
		local waveOpts = {hpMult = wave.hpMult, speedMult = wave.speedMult}
		local stunnersLeft = wave.stunners or 0
		for i = 1, wave.count do
			if not base.isAlive then break end

			local remaining = wave.count - i + 1
			local isStunner = stunnersLeft > 0 and math.random() < stunnersLeft / remaining
			if isStunner then stunnersLeft = stunnersLeft - 1 end

			spawnEnemy(waveOpts, isStunner)
			task.wait(wave.spawnDelay)
		end

		-- ждём зачистки волны (или гибели базы);
		-- перевербованные союзники волну не держат
		while base.isAlive and hostilesLeft() > 0 do
			enemyCountVal.Value = hostilesLeft()
			task.wait(0.5)
		end
		enemyCountVal.Value = hostilesLeft()

		-- Событие карты после волны (открытие/закрытие маршрутов)
		applyMapEvent(wave.mapEvent)

		if base.isAlive and waveIndex < #WAVES then
			print("Следующая волна через " .. wave.pauseAfter .. " сек...")
			task.wait(wave.pauseAfter)
		end
	end

	if base.isAlive then
		victoryValue.Value = true
		TowerService.stopAll()
		print("Все волны завершены — ПОБЕДА!")
	end
end

-- Кнопку «Играть снова» принимаем только когда игра реально закончилась
local restartRequested = false
restartEvent.OnServerEvent:Connect(function(player)
	if gameOverValue.Value or victoryValue.Value then
		restartRequested = true
		print("Рестарт запросил: " .. player.Name)
	end
end)

-- Убираем всех оставшихся врагов/боссов/союзников с поля
local function clearBattlefield()
	for _, e in ipairs(table.clone(activeEnemies)) do
		if e.isAlive then
			e:die() -- через onDied сам уберётся из activeEnemies
		end
	end
	table.clear(activeEnemies)
	enemyCountVal.Value = 0
end

-- Сколько секунд даём осмотреться/застроиться перед первой волной
-- (игроки прилетают из лобби-плейса не мгновенно)
local START_DELAY = 10

task.spawn(function()
	-- Не стартуем волны в пустой сервер — ждём первого игрока
	while #Players:GetPlayers() == 0 do
		task.wait(0.5)
	end
	print("Игроки на месте — первая волна через " .. START_DELAY .. " сек")
	task.wait(START_DELAY)

	while true do
		runWaves()

		-- Игра окончена — ждём, пока кто-нибудь нажмёт «Играть снова».
		-- «Чистое поле»: купленные башни убираются с возвратом 100%
		-- вложений, кошелёк (Economy/DataStore) не сбрасывается,
		-- студийные башни чинятся/восстанавливаются.
		while not restartRequested do
			task.wait(0.5)
		end
		restartRequested = false

		clearBattlefield()
		base:reset()
		gameOverValue.Value = false
		victoryValue.Value = false
		waveValue.Value = 0
		TowerService.resetForNewRound()

		print("=== НОВЫЙ РАУНД ===")
		task.wait(3) -- пара секунд осмотреться перед первой волной
	end
end)
