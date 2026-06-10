local EnemyClass = require(game.ReplicatedStorage.Classes.EnemyClass)
local BaseClass  = require(game.ReplicatedStorage.Classes.BaseClass)
local TowerClass = require(game.ReplicatedStorage.Classes.TowerClass)

-- ============================================
-- НАСТРОЙКИ ВОЛН
-- ============================================
local WAVES = {
	{count = 3, spawnDelay = 2,   pauseAfter = 5},
	{count = 5, spawnDelay = 1.5, pauseAfter = 8},
	{count = 8, spawnDelay = 1,   pauseAfter = 10},
}
local MAX_SPREAD_SLOTS = 12 -- мест вокруг базы

-- ============================================
-- СОЗДАЁМ GAMEDATA ДЛЯ СИНХРОНИЗАЦИИ С UI
-- ============================================
local gameData = Instance.new("Folder")
gameData.Name = "GameData"
gameData.Parent = game.ReplicatedStorage

local function makeValue(valueType, name, default)
	local v = Instance.new(valueType)
	v.Name = name
	v.Value = default
	v.Parent = gameData
	return v
end

local baseHPValue    = makeValue("NumberValue", "BaseHP",       10000)
local maxHPValue     = makeValue("NumberValue", "MaxBaseHP",    10000)
local waveValue      = makeValue("NumberValue", "CurrentWave",  0)
local maxWaveValue   = makeValue("NumberValue", "MaxWaves",     #WAVES)
local enemyCountVal  = makeValue("NumberValue", "EnemyCount",   0)

-- ============================================
-- WAYPOINTS
-- ============================================
local waypointsFolder = workspace:WaitForChild("WaypointsFolder")
local waypoints = waypointsFolder:GetChildren()
table.sort(waypoints, function(a, b)
	return tonumber(a.Name:match("%d+")) < tonumber(b.Name:match("%d+"))
end)
for _, wp in ipairs(waypoints) do
	wp.CanCollide   = false
	wp.Anchored     = true
	wp.Transparency = 1
end

-- ============================================
-- БАЗА И СПИСКИ
-- ============================================
local base          = BaseClass.new(workspace:WaitForChild("GeneralTower"))
local activeEnemies = {}
local activeTowers  = {}
local enemyCounter  = 0

-- ============================================
-- БАШНИ
-- ============================================
local function activateTower(model)
	local tower = TowerClass.new(model, "Rust")
	table.insert(activeTowers, tower)
	tower:startAttacking(function() return activeEnemies end)
	print("Башня Rust активирована!")
end

local function scanTowers()
	for _, obj in ipairs(workspace:GetChildren()) do
		if obj.Name == "Rust" and obj:IsA("Model") then
			activateTower(obj)
		end
	end
end

workspace.ChildAdded:Connect(function(child)
	task.wait(0.1)
	if child.Name == "Rust" and child:IsA("Model") then
		activateTower(child)
	end
end)

-- ============================================
-- СПАВН ВРАГА
-- ============================================
local function spawnEnemy()
	local template = workspace:FindFirstChild("skibidi toilet")
	if not template then warn("Модель 'skibidi toilet' не найдена!") return end

	local model = template:Clone()
	model.Parent = workspace
	model:MoveTo(Vector3.new(
		waypoints[1].Position.X,
		waypoints[1].Position.Y + 3,
		waypoints[1].Position.Z
		))
	task.wait(0.1)

	local enemy = EnemyClass.new(model, waypoints, base)

	-- Назначаем уникальный угол вокруг базы
	enemyCounter = enemyCounter + 1
	enemy.attackAngle = (enemyCounter % MAX_SPREAD_SLOTS) 
		* (2 * math.pi / MAX_SPREAD_SLOTS)

	table.insert(activeEnemies, enemy)
	enemyCountVal.Value = #activeEnemies

	-- Убираем из списка когда умрёт
	task.spawn(function()
		while enemy.isAlive do task.wait(0.5) end
		for i, e in ipairs(activeEnemies) do
			if e == enemy then
				table.remove(activeEnemies, i)
				break
			end
		end
		enemyCountVal.Value = #activeEnemies
	end)

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

		if waveIndex < #WAVES then
			print("Следующая волна через " .. wave.pauseAfter .. " сек...")
			task.wait(wave.pauseAfter)
		end
	end
	print("Все волны завершены!")
end)
