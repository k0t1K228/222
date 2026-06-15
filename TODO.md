-- ============================================
-- КЛАСС БАШНИ
-- Конфиг = «скин»: тип определяется атрибутом TowerType или именем модели.
--
-- attackType:
--   "single"  — одна цель
--   "multi"   — до maxTargets целей одновременно
--   "ramp"    — держит одну цель, урон растёт со временем (лазер)
--   "cone"    — бьёт всех врагов в конусе по направлению к ближайшей цели
--   "convert" — перевербовка: враг становится союзником (см. EnemyClass:convert)
-- weapon (визуал + особая логика):
--   "rifle" | "flamethrower" | "laser" | "rocket" | "melee" | "sonic" | "converter"
--   "rocket" — НЕуправляемый снаряд: летит в точку, где был враг в момент
--              выстрела, и взрывается там (урон по площади splashRadius).
--              Быстрые враги успевают уйти из-под удара.
--
-- РЕЖИМЫ (свитч-моды): если у конфига есть массив modes,
-- башня умеет переключаться между ними прямо в игре.
-- Каждый режим — таблица-оверрайд поверх базового конфига.
-- Текущий режим хранится в атрибутах модели: TowerMode / TowerModeName.
--
-- НОВОЕ:
--   * HP башни (maxHealth) — боссы сносят башни; takeDamage/onDestroyed
--   * Стан — stun(duration): башня не стреляет (боссы и стан-враги)
--   * Магазин — magazine выстрелов, потом reloadTime сек перезарядки
--     (по умолчанию у ближнего боя и звуковой магазина НЕТ)
--   * Обзор — башня НЕ видит врагов за зданиями (Part'ы в папке
--     workspace.Buildings блокируют линию обзора)
--   * Реген — вне боя башня медленно чинится сама (regenPerSecond,
--     начинается через regenDelay сек после последнего урона)
--   * Ремонт — мгновенная починка за деньги (REPAIR_COST_PER_HP за 1 HP)
--   * УРОВНИ — массив upgrades в конфиге: каждое ЧИСЛОВОЕ поле апгрейда
--     ПРИБАВЛЯЕТСЯ к конфигу (damage = 10 значит «+10 к урону»).
--     Уровень 1 = база, upgrades[1] ведёт на уровень 2 и т.д.
-- ============================================

local RunService = game:GetService("RunService")

local Effects = require(script.Parent.Effects)

local BUILDINGS_FOLDER = "Buildings" -- серые кубики, блокирующие обзор

local TOWER_CONFIGS = {
	-- камера с винтовкой: высокий урон по одной цели
	Rust = {
		displayName = "Винтовка",
		price      = 150,
		damage     = 25,
		fireRate   = 1,    -- выстрелов в секунду
		range      = 26,   -- радиус атаки
		attackType = "single",
		weapon     = "rifle",
		magazine   = 8,
		reloadTime = 2.5,
		beamColor  = Color3.fromRGB(255, 100, 0),
		upgrades = {
			{price = 120, damage = 10, range = 3},                 -- уровень 2
			{price = 240, damage = 15, magazine = 4, maxHealth = 30}, -- уровень 3
		},
	},
	-- огнемёт: конусная струя, бьёт ВСЕХ врагов в конусе
	RustFlamer = {
		displayName = "Огнемёт",
		price      = 200,
		damage     = 8,
		fireRate   = 2,
		range      = 18,
		attackType = "cone",
		coneAngle  = 70, -- угол конуса в градусах
		weapon     = "flamethrower",
		magazine   = 14,
		reloadTime = 3,
		beamColor  = Color3.fromRGB(255, 60, 0),
		upgrades = {
			{price = 150, damage = 4, range = 2},
			{price = 300, damage = 6, coneAngle = 15, magazine = 6, maxHealth = 30},
		},
	},
	-- лазер: чем дольше держит одну цель, тем больнее
	RustLaser = {
		displayName = "Лазер",
		price             = 250,
		damage            = 6,
		fireRate          = 2,
		range             = 32,
		attackType        = "ramp",
		rampPerSecond     = 0.5, -- +50% урона за каждую секунду на одной цели
		maxRampMultiplier = 5,
		weapon            = "laser",
		magazine          = 12,
		reloadTime        = 3,
		beamColor         = Color3.fromRGB(255, 0, 80),
		upgrades = {
			{price = 180, damage = 3, range = 4},
			{price = 350, rampPerSecond = 0.25, maxRampMultiplier = 2, magazine = 6, maxHealth = 30},
		},
	},
	-- ракетница: редкие выстрелы, НЕуправляемый снаряд — летит в точку,
	-- где был враг в момент выстрела, взрыв по площади (быстрые враги уворачиваются)
	RustRocket = {
		displayName = "Ракетница",
		price        = 300,
		damage       = 40,
		fireRate     = 0.4,
		range        = 38,
		attackType   = "single",
		splashRadius = 8,
		weapon       = "rocket",
		magazine     = 4,
		reloadTime   = 4,
		beamColor    = Color3.fromRGB(255, 170, 0),
		upgrades = {
			{price = 220, damage = 20, splashRadius = 2},
			{price = 400, damage = 30, range = 5, magazine = 2, maxHealth = 30},
		},
	},
	-- ближний бой: бьёт всех вокруг себя (без перезарядки)
	RustMelee = {
		displayName = "Клинок",
		price      = 100,
		damage     = 18,
		fireRate   = 1.2,
		range      = 10,
		attackType = "multi",
		maxTargets = 10,
		weapon     = "melee",
		beamColor  = Color3.fromRGB(180, 180, 255),
		upgrades = {
			{price = 90,  damage = 8, range = 2},
			{price = 180, damage = 12, fireRate = 0.4, maxHealth = 30},
		},
	},
	-- звуковой удар: волна, бьющая всех в радиусе (без перезарядки)
	RustSonic = {
		displayName = "Звуковая",
		price      = 200,
		damage     = 10,
		fireRate   = 0.7,
		range      = 20,
		attackType = "multi",
		maxTargets = 20,
		weapon     = "sonic",
		beamColor  = Color3.fromRGB(0, 200, 255),
		upgrades = {
			{price = 150, damage = 5, range = 3},
			{price = 280, damage = 8, fireRate = 0.3, maxHealth = 30},
		},
	},
	-- гибрид: два режима, переключаются в игре через меню башни
	RustHybrid = {
		displayName = "Гибрид",
		price     = 400,
		beamColor = Color3.fromRGB(255, 120, 40),
		-- бонусы апгрейда прибавляются ПОВЕРХ активного режима
		upgrades = {
			{price = 250, damage = 5, range = 3},
			{price = 450, damage = 8, fireRate = 0.2, magazine = 3, maxHealth = 30},
		},
		modes = {
			{
				name       = "Огнемёт",
				damage     = 8,
				fireRate   = 2,
				range      = 18,
				attackType = "cone",
				coneAngle  = 70,
				weapon     = "flamethrower",
				magazine   = 14,
				reloadTime = 3,
				beamColor  = Color3.fromRGB(255, 60, 0),
			},
			{
				name         = "Залп ракет",
				damage       = 15,
				fireRate     = 0.4,
				range        = 34,
				attackType   = "multi",
				maxTargets   = 3, -- 3 НЕуправляемые ракеты по 3 разным целям
				                  -- (каждая бьёт в точку, где враг был при пуске)
				splashRadius = 5,
				weapon       = "rocket",
				magazine     = 3,
				reloadTime   = 4,
				beamColor    = Color3.fromRGB(255, 170, 0),
			},
		},
	},
	-- вербовщик: делает врагов союзниками; два режима поведения союзника
	RustConverter = {
		displayName = "Вербовщик",
		price         = 350,
		damage        = 0,
		fireRate      = 0.5, -- попытка вербовки раз в 2 секунды
		range         = 24,
		attackType    = "convert",
		weapon        = "converter",
		convertChance = 0.35,
		-- статы, которые получает завербованный союзник
		allyDamage    = 12,
		allyFireRate  = 1,
		allyRange     = 18,
		beamColor     = Color3.fromRGB(80, 255, 120),
		upgrades = {
			{price = 200, convertChance = 0.1, allyDamage = 4},
			{price = 380, convertChance = 0.15, range = 4, allyDamage = 6, maxHealth = 30},
		},
		modes = {
			{name = "Турель",  convertMode = "turret"}, -- союзник стоит и стреляет
			{name = "Возврат", convertMode = "return"}, -- союзник идёт бить врагов врукопашную
		},
	},
	-- Сюда добавляй новые башни/скины.
	-- Чтобы дать башне свитч-мод — просто добавь ей массив modes по примеру RustHybrid.
}

-- Порядок кнопок в магазине
local SHOP_ORDER = {"Rust", "RustFlamer", "RustLaser", "RustRocket", "RustMelee", "RustSonic", "RustHybrid", "RustConverter"}

-- Значения по умолчанию для необязательных полей конфига
local DEFAULTS = {
	maxTargets        = 1,
	splashRadius      = 0,
	rampPerSecond     = 0,
	maxRampMultiplier = 1,
	coneAngle         = 60,
	scale             = 1, -- размер башни: 0.5 = маленькая, 1 = средняя, 2 = большая
	price             = 0,
	maxHealth         = 100, -- HP башни (ракета босса = 25 → 4 попадания)
	magazine          = 0,   -- 0 = бесконечный боезапас, без перезарядки
	reloadTime        = 0,
	convertChance     = 0,
	convertMode       = "turret",
	allyDamage        = 12,
	allyFireRate      = 1,
	allyRange         = 18,
	regenPerSecond    = 2, -- авто-реген HP вне боя
	regenDelay        = 6, -- сек после последнего урона до начала регена
}

-- Цена мгновенного ремонта: за каждый потерянный HP
local REPAIR_COST_PER_HP = 0.5
-- Башню «под огнём» чинить нельзя: блок на N сек после каждого урона
-- (иначе богатый игрок кликает ремонт быстрее, чем босс наносит урон)
local REPAIR_LOCK = 5

-- Собирает рабочий конфиг: умолчания + база + выбранный режим + уровни.
-- Каждое числовое поле апгрейда ПРИБАВЛЯЕТСЯ к собранному конфигу.
local function buildConfig(towerType, modeIndex, level)
	local def = TOWER_CONFIGS[towerType]
	if not def then return nil end

	local cfg = {}
	for k, v in pairs(DEFAULTS) do cfg[k] = v end
	for k, v in pairs(def) do
		if k ~= "modes" and k ~= "upgrades" then cfg[k] = v end
	end
	if def.modes then
		local mode = def.modes[modeIndex] or def.modes[1]
		for k, v in pairs(mode) do cfg[k] = v end
	end
	if def.upgrades then
		for lvl = 2, math.min(level or 1, #def.upgrades + 1) do
			for k, v in pairs(def.upgrades[lvl - 1]) do
				if k ~= "price" and type(v) == "number" then
					cfg[k] = (cfg[k] or 0) + v
				end
			end
		end
	end
	return cfg
end

-- ============================================
-- ВИЗУАЛЬНЫЕ ЭФФЕКТЫ
-- Разовые эффекты рисует КЛИЕНТ (через Effects), сервер только
-- шлёт события. Исключение — персистентный луч лазера (один Part
-- на башню, обновляется каждый кадр — дешевле держать на сервере).
-- ============================================

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
	Effects.beam(tower.rootPart.Position, target.rootPart.Position, tower.config.beamColor, 0.25, 0.12)
end

function VISUALS.flamethrower(tower, target)
	Effects.beam(tower.rootPart.Position, target.rootPart.Position, tower.config.beamColor, 1.4, 0.2)
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
	Effects.sphere(tower.rootPart.Position, tower.config.beamColor, 2, tower.config.range * 2, 0.25)
end

function VISUALS.sonic(tower, target)
	Effects.sphere(tower.rootPart.Position, tower.config.beamColor, 2, tower.config.range * 2, 0.45)
end

-- Края конуса огнемёта
function VISUALS.coneEdges(tower, origin, dir)
	local cfg = tower.config
	local half = math.rad(cfg.coneAngle / 2)
	for _, a in ipairs({-half, half}) do
		local edge = rotateY(dir, a)
		Effects.beam(origin, origin + edge * cfg.range, cfg.beamColor, 0.15, 0.25)
	end
end

-- ============================================
-- КЛАСС
-- ============================================

local TowerClass = {}
TowerClass.__index = TowerClass

TowerClass.SHOP_ORDER = SHOP_ORDER
TowerClass.REPAIR_COST_PER_HP = REPAIR_COST_PER_HP
TowerClass.REPAIR_LOCK = REPAIR_LOCK

-- Определяем тип башни по модели: атрибут TowerType важнее имени.
function TowerClass.resolveType(model)
	local t = model:GetAttribute("TowerType") or model.Name
	return TOWER_CONFIGS[t] and t or nil
end

-- Сырой конфиг (price, displayName, modes...)
function TowerClass.getConfig(towerType)
	return TOWER_CONFIGS[towerType]
end

-- Рабочий конфиг конкретного режима и уровня (для UI статов и кругов радиуса)
function TowerClass.getEffectiveConfig(towerType, modeIndex, level)
	return buildConfig(towerType, modeIndex or 1, level or 1)
end

-- Следующий апгрейд башни уровня level или nil, если уровень максимальный
function TowerClass.getUpgradeInfo(towerType, level)
	local def = TOWER_CONFIGS[towerType]
	if not (def and def.upgrades) then return nil end
	local nextUp = def.upgrades[level] -- upgrades[1] ведёт на уровень 2
	if not nextUp then return nil end
	return {price = nextUp.price or 0, nextLevel = level + 1, maxLevel = #def.upgrades + 1}
end

-- Сколько всего вложено в башню (покупка + апгрейды) — база для продажи
function TowerClass.getTotalInvested(towerType, level)
	local def = TOWER_CONFIGS[towerType]
	if not def then return 0 end
	local total = def.price or 0
	for lvl = 2, level or 1 do
		local up = def.upgrades and def.upgrades[lvl - 1]
		total = total + (up and up.price or 0)
	end
	return total
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

-- Использует ли башня (любой её режим) лазер — тогда нужен Heartbeat-апдейтер луча
local function configUsesLaser(towerType)
	local def = TOWER_CONFIGS[towerType]
	if not def then return false end
	if def.weapon == "laser" then return true end
	for _, mode in ipairs(def.modes or {}) do
		if mode.weapon == "laser" then return true end
	end
	return false
end

-- ownerId: UserId купившего игрока; nil = башня расставлена в Studio
function TowerClass.new(model, towerType, ownerId)
	local self    = setmetatable({}, TowerClass)
	self.model    = model
	self.rootPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	self.type     = towerType
	self.isActive = false
	self.ownerId  = ownerId

	-- Цель и время «разгона» для лазера
	self.currentTarget = nil
	self.lockTime      = 0

	self.modeIndex = 1
	self.level     = 1
	self.config = buildConfig(towerType, 1, 1) or buildConfig("Rust", 1, 1)

	-- HP, стан, магазин
	self.maxHealth     = self.config.maxHealth
	self.health        = self.maxHealth
	self.stunnedUntil  = 0
	self.lastDamagedAt = 0 -- для авто-регена: чинимся только вне боя
	self.shotsLeft     = self.config.magazine
	self.totalDamage   = 0 -- сколько урона нанесла башня (приоритет цели у боссов)
	self.onDestroyed   = nil -- колбэк: TowerService убирает башню из реестра

	model:SetAttribute("TowerType", towerType)
	model:SetAttribute("TowerMode", 1)
	model:SetAttribute("TowerLevel", 1)
	model:SetAttribute("TowerModeName", self.config.name or self.config.displayName or towerType)
	model:SetAttribute("OwnerId", ownerId or 0)
	model:SetAttribute("TowerHealth", self.health)
	model:SetAttribute("TowerMaxHealth", self.maxHealth)
	model:SetAttribute("TowerAmmo", self.shotsLeft)
	model:SetAttribute("TowerReloading", false)
	model:SetAttribute("TowerStunned", false)

	-- Размер башни (маленькая/средняя/большая)
	if self.config.scale ~= 1 then
		pcall(function() model:ScaleTo(self.config.scale) end)
	end

	self:createStatusBar()

	return self
end

-- HP-бар башни + значок стана (персистентное состояние — живёт на сервере,
-- как и HP-бары врагов; это не разовый эффект)
function TowerClass:createStatusBar()
	if not self.rootPart then return end

	local billboard = Instance.new("BillboardGui")
	billboard.Name        = "TowerStatus"
	billboard.Size        = UDim2.new(4, 0, 1.4, 0)
	billboard.StudsOffset = Vector3.new(0, 5.5, 0)
	billboard.AlwaysOnTop = false
	billboard.Parent      = self.rootPart

	local stunLabel = Instance.new("TextLabel")
	stunLabel.Size                   = UDim2.new(1, 0, 0.6, 0)
	stunLabel.BackgroundTransparency = 1
	stunLabel.TextColor3             = Color3.fromRGB(255, 220, 0)
	stunLabel.TextScaled             = true
	stunLabel.Font                   = Enum.Font.GothamBold
	stunLabel.Text                   = "💫 СТАН"
	stunLabel.Visible                = false
	stunLabel.Parent                 = billboard

	local bg = Instance.new("Frame")
	bg.Size             = UDim2.new(1, 0, 0.3, 0)
	bg.Position         = UDim2.new(0, 0, 0.65, 0)
	bg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	bg.BorderSizePixel  = 0
	bg.Parent           = billboard

	local bar = Instance.new("Frame")
	bar.Size             = UDim2.new(1, 0, 1, 0)
	bar.BackgroundColor3 = Color3.fromRGB(0, 200, 120)
	bar.BorderSizePixel  = 0
	bar.Parent           = bg

	-- Уровень башни (видно издалека, скрыт на уровне 1)
	local levelLabel = Instance.new("TextLabel")
	levelLabel.Size                   = UDim2.new(0.3, 0, 0.5, 0)
	levelLabel.Position               = UDim2.new(0, 0, 0.05, 0)
	levelLabel.BackgroundTransparency = 1
	levelLabel.TextColor3             = Color3.fromRGB(0, 229, 255)
	levelLabel.TextScaled             = true
	levelLabel.Font                   = Enum.Font.GothamBold
	levelLabel.Text                   = ""
	levelLabel.Parent                 = billboard

	self.healthBar  = bar
	self.stunLabel  = stunLabel
	self.levelLabel = levelLabel
end

function TowerClass:updateStatusBar()
	if self.levelLabel then
		self.levelLabel.Text = (self.level or 1) > 1 and ("УР." .. self.level) or ""
	end
	if self.healthBar then
		local pct = self.health / self.maxHealth
		self.healthBar.Size = UDim2.new(pct, 0, 1, 0)
		if pct > 0.5 then
			self.healthBar.BackgroundColor3 = Color3.fromRGB(0, 200, 120)
		elseif pct > 0.25 then
			self.healthBar.BackgroundColor3 = Color3.fromRGB(255, 200, 0)
		else
			self.healthBar.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
		end
	end
	if self.stunLabel then
		self.stunLabel.Visible = self:isStunned()
	end
end

-- ============================================
-- HP И СТАН (боссы и стан-враги бьют башни)
-- ============================================

function TowerClass:takeDamage(amount, damageColor)
	if self.health <= 0 then return end
	self.health = math.max(0, self.health - amount)
	self.lastDamagedAt = os.clock()
	self.model:SetAttribute("TowerHealth", self.health)

	-- «Под огнём»: UI прячет кнопку ремонта, сервер отклоняет запрос
	self.model:SetAttribute("TowerUnderAttack", true)
	task.delay(REPAIR_LOCK, function()
		if self.model.Parent and os.clock() - self.lastDamagedAt >= REPAIR_LOCK then
			self.model:SetAttribute("TowerUnderAttack", false)
		end
	end)

	self:updateStatusBar()

	Effects.damageNumber(self.rootPart.Position + Vector3.new(0, 4, 0), amount, damageColor)

	if self.health <= 0 then
		Effects.sphere(self.rootPart.Position, Color3.fromRGB(255, 90, 40), 3, 14, 0.5)
		if self.onDestroyed then
			self.onDestroyed() -- TowerService уберёт из реестра и удалит модель
		else
			self:destroy()
		end
	end
end

function TowerClass:isStunned()
	return os.clock() < self.stunnedUntil
end

function TowerClass:stun(duration)
	self.stunnedUntil = os.clock() + duration
	self.model:SetAttribute("TowerStunned", true)
	self:clearLaser()
	self:updateStatusBar()

	task.delay(duration, function()
		if not self:isStunned() and self.model.Parent then
			self.model:SetAttribute("TowerStunned", false)
			self:updateStatusBar()
		end
	end)
end

-- Учёт нанесённого урона — боссы летят к самой дамажной башне
function TowerClass:registerDamage(amount)
	self.totalDamage = self.totalDamage + amount
	self.model:SetAttribute("TowerDamageDealt", math.floor(self.totalDamage))
end

-- ============================================
-- РЕМОНТ, АПГРЕЙД, НОВЫЙ РАУНД
-- (проверка денег и владельца — на стороне TowerService)
-- ============================================

-- Можно ли чинить: башня не «под огнём» (REPAIR_LOCK сек после урона)
function TowerClass:canRepairNow()
	return os.clock() - self.lastDamagedAt >= REPAIR_LOCK
end

-- Мгновенный ремонт до полного HP
function TowerClass:repairFull()
	self.health = self.maxHealth
	self.model:SetAttribute("TowerHealth", self.health)
	self:updateStatusBar()
end

-- Апгрейд на следующий уровень
function TowerClass:upgrade()
	if not TowerClass.getUpgradeInfo(self.type, self.level) then return false end
	self.level = self.level + 1

	local oldMax = self.maxHealth
	self.config = buildConfig(self.type, self.modeIndex, self.level)
	self.maxHealth = self.config.maxHealth
	if self.maxHealth > oldMax then
		-- бонусные HP апгрейда даются сразу
		self.health = self.health + (self.maxHealth - oldMax)
	end
	self.shotsLeft = self.config.magazine

	self.model:SetAttribute("TowerLevel", self.level)
	self.model:SetAttribute("TowerMaxHealth", self.maxHealth)
	self.model:SetAttribute("TowerHealth", self.health)
	self.model:SetAttribute("TowerAmmo", self.shotsLeft)
	self.model:SetAttribute("TowerReloading", false)
	Effects.sphere(self.rootPart.Position, Color3.fromRGB(0, 229, 255), 2, 10, 0.4)
	self:updateStatusBar()
	return true
end

-- Рестарт игры: полные HP, без стана, полный магазин, счёт урона с нуля
function TowerClass:resetForNewGame()
	self.health = self.maxHealth
	self.stunnedUntil = 0
	self.lastDamagedAt = 0
	self.shotsLeft = self.config.magazine
	self.totalDamage = 0
	self.model:SetAttribute("TowerHealth", self.health)
	self.model:SetAttribute("TowerUnderAttack", false)
	self.model:SetAttribute("TowerStunned", false)
	self.model:SetAttribute("TowerAmmo", self.shotsLeft)
	self.model:SetAttribute("TowerReloading", false)
	self.model:SetAttribute("TowerDamageDealt", 0)
	self:updateStatusBar()
end

-- ============================================
-- СВИТЧ-МОДЫ
-- ============================================

function TowerClass:setMode(index)
	local def = TOWER_CONFIGS[self.type]
	if not (def and def.modes) then return end

	index = ((index - 1) % #def.modes) + 1
	self.modeIndex = index
	self.config = buildConfig(self.type, index, self.level)

	-- сбрасываем боевое состояние
	self.currentTarget = nil
	self.lockTime = 0
	self:clearLaser()
	self.shotsLeft = self.config.magazine

	self.model:SetAttribute("TowerMode", index)
	self.model:SetAttribute("TowerModeName", self.config.name or "Стандарт")
	self.model:SetAttribute("TowerAmmo", self.shotsLeft)
	self.model:SetAttribute("TowerReloading", false)
end

function TowerClass:nextMode()
	self:setMode((self.modeIndex or 1) + 1)
end

-- ============================================
-- ОБЗОР: враг за зданием (workspace.Buildings) невидим для башни
-- ============================================

function TowerClass:hasLineOfSight(enemy)
	local buildings = workspace:FindFirstChild(BUILDINGS_FOLDER)
	if not buildings then return true end

	if not self.losParams then
		self.losParams = RaycastParams.new()
		self.losParams.FilterType = Enum.RaycastFilterType.Include
	end
	self.losParams.FilterDescendantsInstances = {buildings}

	local origin = self.rootPart.Position + Vector3.new(0, 1, 0)
	local toEnemy = enemy.rootPart.Position - origin
	-- если рейкаст до врага упёрся в здание — обзора нет
	return workspace:Raycast(origin, toEnemy, self.losParams) == nil
end

-- ============================================
-- БОЙ
-- ============================================

-- Враг — допустимая цель: жив, не союзник, в радиусе и в прямой видимости
function TowerClass:inRange(enemy)
	return enemy.isAlive
		and not enemy.friendly
		and enemy.rootPart ~= nil
		and (self.rootPart.Position - enemy.rootPart.Position).Magnitude <= self.config.range
		and self:hasLineOfSight(enemy)
end

-- Ищем count ближайших допустимых целей
function TowerClass:findTargets(enemies, count)
	local inRange = {}

	for _, enemy in ipairs(enemies) do
		if enemy.isAlive and not enemy.friendly and enemy.rootPart then
			local dist = (self.rootPart.Position - enemy.rootPart.Position).Magnitude
			if dist <= self.config.range and self:hasLineOfSight(enemy) then
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

-- Один «тик» атаки по типу башни. Возвращает true, если башня
-- действительно атаковала (тогда тратится патрон из магазина).
function TowerClass:attackTick(enemies)
	local cfg = self.config

	if cfg.attackType == "ramp" then
		-- Держим одну цель, пока она жива, в радиусе и видна
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
			return true
		else
			self:clearLaser()
			return false
		end

	elseif cfg.attackType == "cone" then
		-- Конус: целимся в ближайшего врага, жжём всех в секторе
		local primary = self:findTargets(enemies, 1)[1]
		if not primary then return false end

		local origin = self.rootPart.Position
		local aim = primary.rootPart.Position
		local flatDir = Vector3.new(aim.X - origin.X, 0, aim.Z - origin.Z)
		if flatDir.Magnitude < 0.1 then return false end
		flatDir = flatDir.Unit

		local cosHalf = math.cos(math.rad(cfg.coneAngle / 2))
		VISUALS.coneEdges(self, origin, flatDir)

		-- по снимку: takeDamage может убить врага → onDied уберёт его из
		-- activeEnemies во время ipairs и собьёт индексы (пропуск целей)
		for _, enemy in ipairs(table.clone(enemies)) do
			if enemy.isAlive and not enemy.friendly and enemy.rootPart then
				local to = enemy.rootPart.Position - origin
				local flat = Vector3.new(to.X, 0, to.Z)
				if to.Magnitude <= cfg.range and flat.Magnitude > 0.1
					and flat.Unit:Dot(flatDir) >= cosHalf
					and self:hasLineOfSight(enemy) then
					enemy:takeDamage(cfg.damage, cfg.beamColor)
					self:registerDamage(cfg.damage)
					Effects.beam(origin, enemy.rootPart.Position, cfg.beamColor, 0.8, 0.18)
				end
			end
		end
		return true

	elseif cfg.attackType == "convert" then
		-- Вербовка: пытаемся перевербовать ближайшего ОБЫЧНОГО врага
		-- (боссов вербовать нельзя). convertMode задаётся режимом башни.
		for _, enemy in ipairs(self:findTargets(enemies, 5)) do
			if enemy.convert and not enemy.isBoss then
				Effects.beam(self.rootPart.Position, enemy.rootPart.Position, cfg.beamColor, 0.4, 0.3)
				if math.random() < cfg.convertChance then
					enemy:convert(cfg.convertMode, {
						damage   = cfg.allyDamage,
						fireRate = cfg.allyFireRate,
						range    = cfg.allyRange,
					}, self.getEnemies)
				end
				return true
			end
		end
		return false

	else
		local count = (cfg.attackType == "multi") and cfg.maxTargets or 1
		local targets = self:findTargets(enemies, count)
		for _, target in ipairs(targets) do
			self:fire(target, cfg.damage, 1)
		end
		return #targets > 0
	end
end

function TowerClass:fire(target, damage, rampMult)
	local weapon = self.config.weapon

	if weapon == "rocket" then
		self:fireRocket(target, damage)
		return
	end

	target:takeDamage(damage, self.config.beamColor)
	self:registerDamage(damage)
	local visual = VISUALS[weapon]
	if visual then visual(self, target, rampMult) end
end

-- Ракета: НЕ самонаводящаяся. Летит по ПРЯМОЙ в точку, где враг был
-- в момент выстрела (точка фиксируется здесь и не меняется в полёте),
-- взрывается там — урон по площади всем, кто окажется рядом.
-- Быстрый враг успевает уйти из-под удара.
function TowerClass:fireRocket(target, damage)
	local cfg = self.config
	local origin    = self.rootPart.Position
	local impactPos = target.rootPart.Position -- запоминаем позицию врага в момент пуска

	local rocket = Instance.new("Part")
	rocket.Size       = Vector3.new(0.6, 0.6, 2.4)
	rocket.Color      = cfg.beamColor
	rocket.Material   = Enum.Material.Neon
	rocket.Anchored   = true
	rocket.CanCollide = false
	rocket.CanQuery   = false
	rocket.CastShadow = false
	rocket.CFrame     = CFrame.new(origin, impactPos)
	rocket.Parent     = workspace

	task.spawn(function()
		local speed = 40
		local pos = origin
		local flightTime = 0

		-- Летим к зафиксированной точке (цель больше не отслеживаем)
		while flightTime < 5 do
			local dt = task.wait()
			flightTime = flightTime + dt

			local delta = impactPos - pos
			if delta.Magnitude < 3 then break end

			pos = pos + delta.Unit * speed * dt
			rocket.CFrame = CFrame.new(pos, impactPos)
		end

		rocket:Destroy()
		Effects.sphere(impactPos, Color3.fromRGB(255, 120, 0), 2, cfg.splashRadius * 2, 0.35)

		-- Урон по площади всем врагам у точки взрыва.
		-- Снимок: takeDamage убивает врага → onDied мутирует activeEnemies
		-- во время ipairs (сбой индексов, пропуск целей).
		local splashSnapshot = self.getEnemies and self.getEnemies() or {}
		for _, enemy in ipairs(table.clone(splashSnapshot)) do
			if enemy.isAlive and not enemy.friendly and enemy.rootPart
				and (enemy.rootPart.Position - impactPos).Magnitude <= cfg.splashRadius then
				enemy:takeDamage(damage, cfg.beamColor)
				self:registerDamage(damage)
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

-- Перезарядка: магазин пуст — пауза reloadTime, потом полный магазин
function TowerClass:reload()
	self.model:SetAttribute("TowerReloading", true)
	self:clearLaser()
	self.currentTarget = nil
	self.lockTime = 0

	task.wait(self.config.reloadTime)

	self.shotsLeft = self.config.magazine
	self.model:SetAttribute("TowerAmmo", self.shotsLeft)
	self.model:SetAttribute("TowerReloading", false)
end

-- Автоатака
function TowerClass:startAttacking(getEnemies)
	if self.isActive then return end
	self.isActive = true
	self.getEnemies = getEnemies

	-- Лазер: каждый кадр приклеиваем концы луча к башне и цели,
	-- чтобы он не мигал между тиками урона. Апдейтер нужен только
	-- башням, у которых есть лазерный режим.
	if configUsesLaser(self.type) then
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
	end

	-- Авто-реген: вне боя башня медленно чинится сама
	task.spawn(function()
		while self.isActive do
			task.wait(1)
			if self.health > 0 and self.health < self.maxHealth
				and os.clock() - self.lastDamagedAt >= self.config.regenDelay then
				self.health = math.min(self.maxHealth, self.health + self.config.regenPerSecond)
				self.model:SetAttribute("TowerHealth", self.health)
				self:updateStatusBar()
			end
		end
	end)

	task.spawn(function()
		while self.isActive do
			if self:isStunned() then
				-- Оглушена боссом/стан-врагом: не стреляем
				self:clearLaser()
				task.wait(0.15)
			else
				local fired = self:attackTick(getEnemies())

				-- Магазин: тратим патрон только на реальный выстрел
				if fired and self.config.magazine > 0 then
					self.shotsLeft = self.shotsLeft - 1
					self.model:SetAttribute("TowerAmmo", self.shotsLeft)
					if self.shotsLeft <= 0 then
						self:reload()
					end
				end

				task.wait(1 / self.config.fireRate)
			end
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

-- Полное удаление башни (продажа или уничтожение боссом)
function TowerClass:destroy()
	self:stopAttacking()
	self.model:Destroy()
end

return TowerClass
