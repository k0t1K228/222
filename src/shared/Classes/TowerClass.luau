-- ============================================
-- КЛАСС БАШНИ
-- Конфиг = «скин»: тип определяется атрибутом TowerType или именем модели.
--
-- attackType:
--   "single" — одна цель
--   "multi"  — до maxTargets целей одновременно
--   "ramp"   — держит одну цель, урон растёт со временем (лазер)
--   "cone"   — бьёт всех врагов в конусе по направлению к ближайшей цели
-- weapon (визуал + особая логика):
--   "rifle" | "flamethrower" | "laser" | "rocket" | "melee" | "sonic"
--
-- РЕЖИМЫ (свитч-моды): если у конфига есть massив modes,
-- башня умеет переключаться между ними прямо в игре.
-- Каждый режим — таблица-оверрайд поверх базового конфига.
-- Текущий режим хранится в атрибутах модели: TowerMode / TowerModeName.
-- ============================================

local TweenService = game:GetService("TweenService")
local RunService   = game:GetService("RunService")

local TOWER_CONFIGS = {
	-- камера с винтовкой: высокий урон по одной цели
	Rust = {
		displayName = "Винтовка",
		price      = 150,
		damage     = 25,
		fireRate   = 1,    -- выстрелов в секунду
		range      = 20,   -- радиус атаки
		attackType = "single",
		weapon     = "rifle",
		beamColor  = Color3.fromRGB(255, 100, 0),
	},
	-- огнемёт: конусная струя, бьёт ВСЕХ врагов в конусе
	RustFlamer = {
		displayName = "Огнемёт",
		price      = 200,
		damage     = 8,
		fireRate   = 2,
		range      = 14,
		attackType = "cone",
		coneAngle  = 70, -- угол конуса в градусах
		weapon     = "flamethrower",
		beamColor  = Color3.fromRGB(255, 60, 0),
	},
	-- лазер: чем дольше держит одну цель, тем больнее
	RustLaser = {
		displayName = "Лазер",
		price             = 250,
		damage            = 6,
		fireRate          = 2,
		range             = 25,
		attackType        = "ramp",
		rampPerSecond     = 0.5, -- +50% урона за каждую секунду на одной цели
		maxRampMultiplier = 5,
		weapon            = "laser",
		beamColor         = Color3.fromRGB(255, 0, 80),
	},
	-- ракетница: редкие выстрелы, урон по площади
	RustRocket = {
		displayName = "Ракетница",
		price        = 300,
		damage       = 40,
		fireRate     = 0.4,
		range        = 30,
		attackType   = "single",
		splashRadius = 8,
		weapon       = "rocket",
		beamColor    = Color3.fromRGB(255, 170, 0),
	},
	-- ближний бой: бьёт всех вокруг себя
	RustMelee = {
		displayName = "Клинок",
		price      = 100,
		damage     = 18,
		fireRate   = 1.2,
		range      = 8,
		attackType = "multi",
		maxTargets = 10,
		weapon     = "melee",
		beamColor  = Color3.fromRGB(180, 180, 255),
	},
	-- звуковой удар: волна, бьющая всех в радиусе
	RustSonic = {
		displayName = "Звуковая",
		price      = 200,
		damage     = 10,
		fireRate   = 0.7,
		range      = 16,
		attackType = "multi",
		maxTargets = 20,
		weapon     = "sonic",
		beamColor  = Color3.fromRGB(0, 200, 255),
	},
	-- гибрид: два режима, переключаются в игре через меню башни
	RustHybrid = {
		displayName = "Гибрид",
		price     = 400,
		beamColor = Color3.fromRGB(255, 120, 40),
		modes = {
			{
				name       = "Огнемёт",
				damage     = 8,
				fireRate   = 2,
				range      = 14,
				attackType = "cone",
				coneAngle  = 70,
				weapon     = "flamethrower",
				beamColor  = Color3.fromRGB(255, 60, 0),
			},
			{
				name         = "Залп ракет",
				damage       = 15,
				fireRate     = 0.4,
				range        = 28,
				attackType   = "multi",
				maxTargets   = 3, -- 3 ракеты по 3 разным целям
				splashRadius = 5,
				weapon       = "rocket",
				beamColor    = Color3.fromRGB(255, 170, 0),
			},
		},
	},
	-- Сюда добавляй новые башни/скины.
	-- Чтобы дать башне свитч-мод — просто добавь ей массив modes по примеру RustHybrid.
}

-- Порядок кнопок в магазине
local SHOP_ORDER = {"Rust", "RustFlamer", "RustLaser", "RustRocket", "RustMelee", "RustSonic", "RustHybrid"}

-- Значения по умолчанию для необязательных полей конфига
local DEFAULTS = {
	maxTargets        = 1,
	splashRadius      = 0,
	rampPerSecond     = 0,
	maxRampMultiplier = 1,
	coneAngle         = 60,
	scale             = 1, -- размер башни: 0.5 = маленькая, 1 = средняя, 2 = большая
	price             = 0,
}

-- Собирает рабочий конфиг: умолчания + база + выбранный режим
local function buildConfig(towerType, modeIndex)
	local def = TOWER_CONFIGS[towerType]
	if not def then return nil end

	local cfg = {}
	for k, v in pairs(DEFAULTS) do cfg[k] = v end
	for k, v in pairs(def) do
		if k ~= "modes" then cfg[k] = v end
	end
	if def.modes then
		local mode = def.modes[modeIndex] or def.modes[1]
		for k, v in pairs(mode) do cfg[k] = v end
	end
	return cfg
end

-- ============================================
-- ВИЗУАЛЬНЫЕ ЭФФЕКТЫ (заглушки из Part'ов,
-- потом заменяются на модели/партиклы от Чурюмова)
-- ============================================

local function makeBeam(startPos, endPos, color, thickness, lifetime)
	local length = (startPos - endPos).Magnitude
	if length < 0.1 then return end

	local beam = Instance.new("Part")
	beam.Size         = Vector3.new(thickness, thickness, length)
	beam.CFrame       = CFrame.new((startPos + endPos) / 2, endPos)
	beam.Anchored     = true
	beam.CanCollide   = false
	beam.CanQuery     = false
	beam.Color        = color
	beam.Material     = Enum.Material.Neon
	beam.CastShadow   = false
	beam.Transparency = 0.2
	beam.Parent       = workspace

	task.delay(lifetime, function() beam:Destroy() end)
end

local function makeSphere(pos, color, startSize, endSize, lifetime)
	local s = Instance.new("Part")
	s.Shape        = Enum.PartType.Ball
	s.Size         = Vector3.new(startSize, startSize, startSize)
	s.Position     = pos
	s.Anchored     = true
	s.CanCollide   = false
	s.CanQuery     = false
	s.Color        = color
	s.Material     = Enum.Material.Neon
	s.CastShadow   = false
	s.Transparency = 0.3
	s.Parent       = workspace

	TweenService:Create(s, TweenInfo.new(lifetime), {
		Size = Vector3.new(endSize, endSize, endSize),
		Transparency = 1,
	}):Play()
	task.delay(lifetime + 0.05, function() s:Destroy() end)
end

-- Растягиваем луч между двумя точками
local function stretchBeam(beam, startPos, endPos, thickness)
	local length = math.max((startPos - endPos).Magnitude, 0.1)
	beam.Size   = Vector3.new(thickness, thickness, length)
	beam.CFrame = CFrame.new((startPos + endPos) / 2, endPos)
end

-- Поворот вектора вокруг оси Y
local function rotateY(v, angleRad)
	local c, s = math.cos(angleRad), math.sin(angleRad)
	return Vector3.new(v.X * c - v.Z * s, v.Y, v.X * s + v.Z * c)
end

local VISUALS = {}

function VISUALS.rifle(tower, target)
	makeBeam(tower.rootPart.Position, target.rootPart.Position, tower.config.beamColor, 0.25, 0.12)
end

function VISUALS.flamethrower(tower, target)
	makeBeam(tower.rootPart.Position, target.rootPart.Position, tower.config.beamColor, 1.4, 0.2)
end

function VISUALS.laser(tower, target, rampMult)
	-- Непрерывный луч: один Part живёт, пока башня держит цель.
	-- Каждый кадр его концы обновляет Heartbeat-апдейтер (см. startAttacking).
	local beam = tower.laserBeam
	if not beam or not beam.Parent then
		beam = Instance.new("Part")
		beam.Anchored     = true
		beam.CanCollide   = false
		beam.CanQuery     = false
		beam.CastShadow   = false
		beam.Color        = tower.config.beamColor
		beam.Material     = Enum.Material.Neon
		beam.Transparency = 0.2
		beam.Parent       = workspace
		tower.laserBeam = beam
	end
	-- луч толстеет по мере «разгона»
	tower.laserThickness = 0.2 + 0.2 * rampMult
	stretchBeam(beam, tower.rootPart.Position, target.rootPart.Position, tower.laserThickness)
end

function VISUALS.melee(tower, target)
	makeSphere(tower.rootPart.Position, tower.config.beamColor, 2, tower.config.range * 2, 0.25)
end

function VISUALS.sonic(tower, target)
	makeSphere(tower.rootPart.Position, tower.config.beamColor, 2, tower.config.range * 2, 0.45)
end

-- Края конуса огнемёта
function VISUALS.coneEdges(tower, origin, dir)
	local cfg = tower.config
	local half = math.rad(cfg.coneAngle / 2)
	for _, a in ipairs({-half, half}) do
		local edge = rotateY(dir, a)
		makeBeam(origin, origin + edge * cfg.range, cfg.beamColor, 0.15, 0.25)
	end
end

-- ============================================
-- КЛАСС
-- ============================================

local TowerClass = {}
TowerClass.__index = TowerClass

TowerClass.SHOP_ORDER = SHOP_ORDER

-- Определяем тип башни по модели: атрибут TowerType важнее имени.
function TowerClass.resolveType(model)
	local t = model:GetAttribute("TowerType") or model.Name
	return TOWER_CONFIGS[t] and t or nil
end

-- Сырой конфиг (price, displayName, modes...)
function TowerClass.getConfig(towerType)
	return TOWER_CONFIGS[towerType]
end

-- Рабочий конфиг конкретного режима (для UI статов и кругов радиуса)
function TowerClass.getEffectiveConfig(towerType, modeIndex)
	return buildConfig(towerType, modeIndex or 1)
end

-- Имена режимов башни или nil, если режим один
function TowerClass.getModeNames(towerType)
	local def = TOWER_CONFIGS[towerType]
	if not (def and def.modes) then return nil end
	local names = {}
	for _, m in ipairs(def.modes) do
		table.insert(names, m.name)
	end
	return names
end

function TowerClass.new(model, towerType)
	local self    = setmetatable({}, TowerClass)
	self.model    = model
	self.rootPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	self.type     = towerType
	self.isActive = false

	-- Цель и время «разгона» для лазера
	self.currentTarget = nil
	self.lockTime      = 0

	self.modeIndex = 1
	self.config = buildConfig(towerType, 1) or buildConfig("Rust", 1)

	model:SetAttribute("TowerType", towerType)
	model:SetAttribute("TowerMode", 1)
	model:SetAttribute("TowerModeName", self.config.name or self.config.displayName or towerType)

	-- Размер башни (маленькая/средняя/большая)
	if self.config.scale ~= 1 then
		pcall(function() model:ScaleTo(self.config.scale) end)
	end

	return self
end

-- ============================================
-- СВИТЧ-МОДЫ
-- ============================================

function TowerClass:setMode(index)
	local def = TOWER_CONFIGS[self.type]
	if not (def and def.modes) then return end

	index = ((index - 1) % #def.modes) + 1
	self.modeIndex = index
	self.config = buildConfig(self.type, index)

	-- сбрасываем боевое состояние
	self.currentTarget = nil
	self.lockTime = 0
	self:clearLaser()

	self.model:SetAttribute("TowerMode", index)
	self.model:SetAttribute("TowerModeName", self.config.name or "Стандарт")
end

function TowerClass:nextMode()
	self:setMode((self.modeIndex or 1) + 1)
end

-- ============================================
-- БОЙ
-- ============================================

function TowerClass:inRange(enemy)
	return enemy.isAlive
		and enemy.rootPart ~= nil
		and (self.rootPart.Position - enemy.rootPart.Position).Magnitude <= self.config.range
end

-- Ищем count ближайших врагов в радиусе
function TowerClass:findTargets(enemies, count)
	local inRange = {}

	for _, enemy in ipairs(enemies) do
		if enemy.isAlive and enemy.rootPart then
			local dist = (self.rootPart.Position - enemy.rootPart.Position).Magnitude
			if dist <= self.config.range then
				table.insert(inRange, {enemy = enemy, dist = dist})
			end
		end
	end

	table.sort(inRange, function(a, b) return a.dist < b.dist end)

	local targets = {}
	for i = 1, math.min(count, #inRange) do
		table.insert(targets, inRange[i].enemy)
	end
	return targets
end

-- Один «тик» атаки по типу башни
function TowerClass:attackTick(enemies)
	local cfg = self.config

	if cfg.attackType == "ramp" then
		-- Держим одну цель, пока она жива и в радиусе
		local target = self.currentTarget
		if not (target and self:inRange(target)) then
			target = self:findTargets(enemies, 1)[1]
			if target ~= self.currentTarget then self:clearLaser() end
			self.currentTarget = target
			self.lockTime = 0
		end
		if target then
			local mult = math.min(1 + self.lockTime * cfg.rampPerSecond, cfg.maxRampMultiplier)
			self:fire(target, cfg.damage * mult, mult)
			self.lockTime = self.lockTime + 1 / cfg.fireRate
		else
			self:clearLaser()
		end

	elseif cfg.attackType == "cone" then
		-- Конус: целимся в ближайшего врага, жжём всех в секторе
		local primary = self:findTargets(enemies, 1)[1]
		if not primary then return end

		local origin = self.rootPart.Position
		local aim = primary.rootPart.Position
		local flatDir = Vector3.new(aim.X - origin.X, 0, aim.Z - origin.Z)
		if flatDir.Magnitude < 0.1 then return end
		flatDir = flatDir.Unit

		local cosHalf = math.cos(math.rad(cfg.coneAngle / 2))
		VISUALS.coneEdges(self, origin, flatDir)

		for _, enemy in ipairs(enemies) do
			if enemy.isAlive and enemy.rootPart then
				local to = enemy.rootPart.Position - origin
				local flat = Vector3.new(to.X, 0, to.Z)
				if to.Magnitude <= cfg.range and flat.Magnitude > 0.1
					and flat.Unit:Dot(flatDir) >= cosHalf then
					enemy:takeDamage(cfg.damage, cfg.beamColor)
					makeBeam(origin, enemy.rootPart.Position, cfg.beamColor, 0.8, 0.18)
				end
			end
		end

	else
		local count = (cfg.attackType == "multi") and cfg.maxTargets or 1
		for _, target in ipairs(self:findTargets(enemies, count)) do
			self:fire(target, cfg.damage, 1)
		end
	end
end

function TowerClass:fire(target, damage, rampMult)
	local weapon = self.config.weapon

	if weapon == "rocket" then
		self:fireRocket(target, damage)
		return
	end

	target:takeDamage(damage, self.config.beamColor)
	local visual = VISUALS[weapon]
	if visual then visual(self, target, rampMult) end
end

-- Ракета: летит к цели, взрывается, урон по площади
function TowerClass:fireRocket(target, damage)
	local cfg = self.config

	local rocket = Instance.new("Part")
	rocket.Size       = Vector3.new(0.6, 0.6, 2.4)
	rocket.Color      = cfg.beamColor
	rocket.Material   = Enum.Material.Neon
	rocket.Anchored   = true
	rocket.CanCollide = false
	rocket.CanQuery   = false
	rocket.CastShadow = false
	rocket.CFrame     = CFrame.new(self.rootPart.Position, target.rootPart.Position)
	rocket.Parent     = workspace

	task.spawn(function()
		local speed = 40
		local pos = rocket.Position
		local flightTime = 0

		while flightTime < 5 do
			local dt = task.wait()
			flightTime = flightTime + dt
			if not target.isAlive or not target.rootPart then break end

			local targetPos = target.rootPart.Position
			local delta = targetPos - pos
			if delta.Magnitude < 3 then break end

			pos = pos + delta.Unit * speed * dt
			rocket.CFrame = CFrame.new(pos, targetPos)
		end

		local impactPos = pos
		rocket:Destroy()
		makeSphere(impactPos, Color3.fromRGB(255, 120, 0), 2, cfg.splashRadius * 2, 0.35)

		-- Урон по площади всем врагам у точки взрыва
		for _, enemy in ipairs(self.getEnemies and self.getEnemies() or {}) do
			if enemy.isAlive and enemy.rootPart
				and (enemy.rootPart.Position - impactPos).Magnitude <= cfg.splashRadius then
				enemy:takeDamage(damage, cfg.beamColor)
			end
		end
	end)
end

-- Убираем луч лазера (цель потеряна/сменилась/башня выключена)
function TowerClass:clearLaser()
	if self.laserBeam then
		self.laserBeam:Destroy()
		self.laserBeam = nil
	end
end

-- Автоатака
function TowerClass:startAttacking(getEnemies)
	if self.isActive then return end
	self.isActive = true
	self.getEnemies = getEnemies

	-- Лазер: каждый кадр приклеиваем концы луча к башне и цели,
	-- чтобы он не мигал между тиками урона
	self.laserConn = RunService.Heartbeat:Connect(function()
		local target = self.currentTarget
		local beam = self.laserBeam
		if not beam or not beam.Parent then return end
		if target and target.isAlive and target.rootPart then
			stretchBeam(beam, self.rootPart.Position, target.rootPart.Position, self.laserThickness or 0.4)
		else
			self:clearLaser()
		end
	end)

	task.spawn(function()
		while self.isActive do
			self:attackTick(getEnemies())
			task.wait(1 / self.config.fireRate)
		end
	end)
end

function TowerClass:stopAttacking()
	self.isActive = false
	if self.laserConn then
		self.laserConn:Disconnect()
		self.laserConn = nil
	end
	self:clearLaser()
end

return TowerClass
