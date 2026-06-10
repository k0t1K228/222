-- ============================================
-- КЛАСС БАШНИ
-- ============================================

local TOWER_CONFIGS = {
	Rust = {
		damage     = 25,
		fireRate   = 1,    -- выстрелов в секунду
		range      = 20,   -- радиус атаки
		maxTargets = 1,    -- сколько врагов атакует одновременно
		beamColor  = Color3.fromRGB(255, 100, 0), -- цвет луча атаки
	}
	-- Сюда добавляй новые башни
}

local TowerClass = {}
TowerClass.__index = TowerClass

function TowerClass.new(model, towerType)
	local self     = setmetatable({}, TowerClass)
	self.model     = model
	self.rootPart  = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	self.type      = towerType
	self.isActive  = false

	local config      = TOWER_CONFIGS[towerType] or TOWER_CONFIGS.Rust
	self.damage       = config.damage
	self.fireRate     = config.fireRate
	self.range        = config.range
	self.maxTargets   = config.maxTargets
	self.beamColor    = config.beamColor

	return self
end

-- Ищем N ближайших врагов в радиусе
function TowerClass:findTargets(enemies)
	local inRange = {}

	for _, enemy in ipairs(enemies) do
		if enemy.isAlive and enemy.rootPart then
			local dist = (self.rootPart.Position - enemy.rootPart.Position).Magnitude
			if dist <= self.range then
				table.insert(inRange, {enemy = enemy, dist = dist})
			end
		end
	end

	-- Сортируем по расстоянию (ближайший первый)
	table.sort(inRange, function(a, b) return a.dist < b.dist end)

	-- Берём только maxTargets штук
	local targets = {}
	for i = 1, math.min(self.maxTargets, #inRange) do
		table.insert(targets, inRange[i].enemy)
	end

	return targets
end

-- Визуальный луч от башни к врагу
function TowerClass:shootBeam(targetEnemy)
	if not targetEnemy.isAlive or not targetEnemy.rootPart then return end

	local startPos = self.rootPart.Position
	local endPos   = targetEnemy.rootPart.Position

	-- Считаем середину и длину луча
	local midPos   = (startPos + endPos) / 2
	local length   = (startPos - endPos).Magnitude
	local direction = (endPos - startPos).Unit

	-- Создаём луч как тонкий Part
	local beam = Instance.new("Part")
	beam.Size             = Vector3.new(0.3, 0.3, length)
	beam.CFrame           = CFrame.new(midPos, endPos) 
	beam.Anchored         = true
	beam.CanCollide       = false
	beam.BrickColor       = BrickColor.new("Bright orange")
	beam.Material         = Enum.Material.Neon
	beam.CastShadow       = false
	beam.Parent           = workspace

	-- Подсветка цели
	local highlight = Instance.new("SelectionBox")
	highlight.Adornee     = targetEnemy.model
	highlight.Color3      = self.beamColor
	highlight.LineThickness = 0.05
	highlight.Parent      = workspace

	-- Убираем луч и подсветку через 0.15 сек
	task.delay(0.15, function()
		beam:Destroy()
		highlight:Destroy()
	end)
end

-- Автоатака
function TowerClass:startAttacking(getEnemies)
	if self.isActive then return end
	self.isActive = true

	task.spawn(function()
		while self.isActive do
			local targets = self:findTargets(getEnemies())

			for _, target in ipairs(targets) do
				if target.isAlive then
					target:takeDamage(self.damage)
					self:shootBeam(target)
					print("Башня [" .. self.type .. "] → урон " .. self.damage .. " врагу")
				end
			end

			task.wait(1 / self.fireRate)
		end
	end)
end

function TowerClass:stopAttacking()
	self.isActive = false
end

return TowerClass