-- ============================================
-- КЛАСС БОССА («вертолёты»)
-- Боссы НЕ ходят по маршрутам: подлетают к башне и КРУЖАТ
-- вокруг неё по орбите, атакуя; потом перелетают к следующей.
-- Приоритет цели — башня, которая нанесла больше всего урона
-- (tower.totalDamage), с шансом случайного выбора.
--
-- BOSS_CONFIGS — шаблоны: добавляй новых боссов как конфиги,
-- по аналогии с TOWER_CONFIGS у башен.
--   stunDuration > 0 — босс глушит башни (станер)
--   damage > 0       — босс сносит HP башен (разрушитель)
--   weapon = "laser" | "rocket" — визуал/тип снаряда
--
-- СВОЯ МОДЕЛЬ БОССА (вместо заглушки):
--   Положи модель в ServerStorage с именем "Boss_<Тип>"
--   (например Boss_StunCopter), либо пропиши templateName в конфиге.
--   Что значат детали модели (см. DOCUMENTATION.md §6.1):
--     * PrimaryPart        — корпус: хитбокс, центр полёта, HP-бар
--     * детали с "Rotor"
--       в имени            — крутятся сами (винты вертолёта)
--     * деталь "Muzzle"    — точка, откуда летят снаряды/лазер
--                            (нет — стреляет из корпуса)
--   Humanoid удаляется автоматически, все детали привариваются
--   к PrimaryPart — двигается только он.
--
-- Интерфейс совместим с EnemyClass (isAlive, rootPart, takeDamage,
-- onDied, killedByDamage), поэтому башни стреляют по боссам
-- тем же кодом, что и по обычным врагам.
-- ============================================

local RunService    = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Effects = require(script.Parent.Effects)

local BOSS_CONFIGS = {
	-- Станер: не наносит урона, но глушит башни лазером
	StunCopter = {
		displayName  = "Вертолёт-станер",
		hp           = 700,  -- радиусы башен подняли — у босса чуть больше HP
		speed        = 22,
		flyHeight    = 12,
		weapon       = "laser",
		attackRange  = 28,
		fireRate     = 0.35, -- атак в секунду (раз в ~3 с)
		stunDuration = 5,
		damage       = 0,
		attacksBeforeMove = 2, -- сколько атак по одной башне до перелёта
		attackCooldown    = 4, -- после серии столько секунд НЕ атакует (окно для башен)
		beamColor    = Color3.fromRGB(255, 220, 0),
		bodyColor    = Color3.fromRGB(200, 165, 40),
	},
	-- Разрушитель: ракетами сносит HP башен (башня 100 HP = 4 попадания)
	DestroyerCopter = {
		displayName  = "Вертолёт-разрушитель",
		hp           = 1100, -- радиусы башен подняли — у босса чуть больше HP
		speed        = 17,
		flyHeight    = 14,
		weapon       = "rocket",
		attackRange  = 34,
		fireRate     = 0.3, -- раз в ~3.3 с
		stunDuration = 0,
		damage       = 25,
		attacksBeforeMove = 3,
		attackCooldown    = 5,
		beamColor    = Color3.fromRGB(255, 70, 70),
		bodyColor    = Color3.fromRGB(120, 45, 45),
	},
	-- Сюда добавляй новых боссов. Своя модель: положи её в ServerStorage
	-- и укажи в конфиге templateName = "ИмяМодели".
}

local DEFAULTS = {
	hp           = 500,
	speed        = 20,
	flyHeight    = 12,
	weapon       = "laser",
	attackRange  = 25,
	fireRate     = 0.5,
	stunDuration = 0,
	damage       = 0,
	attacksBeforeMove = 3,
	attackCooldown    = 3, -- пауза без атак после серии (сек)
	beamColor    = Color3.fromRGB(255, 255, 255),
	bodyColor    = Color3.fromRGB(110, 110, 120),
}

local RANDOM_TARGET_CHANCE = 0.3 -- шанс полететь к случайной башне вместо самой дамажной
local ROTOR_SPIN_SPEED = 18 -- рад/сек вращения винтов

-- ============================================
-- МОДЕЛЬ ПОЛЁТА (плавная, не дёрганая)
-- Вместо телепорта по точкам — скорость с инерцией:
-- вертолёт разгоняется/тормозит, кренится в повороты,
-- наклоняет нос по ходу движения и слегка покачивается.
-- Все сглаживания через exp(-k*dt) — не зависят от FPS.
-- ============================================
local FLIGHT = {
	accel        = 1.6,           -- инерция разгона/торможения (1/сек)
	turnSmooth   = 3.5,           -- сглаживание поворота носа
	tiltSmooth   = 5,             -- сглаживание крена/тангажа
	maxBank      = math.rad(28),  -- максимальный крен в повороте
	bankTurnRef  = 1.6,           -- рад/сек поворота, дающие полный крен
	bankSmooth   = 6,             -- low-pass скорости поворота для крена (анти-дрожь)
	maxPitch     = math.rad(11),  -- наклон носа вперёд на полной скорости
	bobSpeed     = 1.8,           -- частота покачивания
	bobAmplitude = 0.55,          -- амплитуда покачивания (studs)
	orbitLead    = 0.65,          -- насколько вперёд по орбите смотрит цель полёта (рад)
	targetSmooth = 2.5,           -- сглаживание САМОЙ точки назначения: при резкой
	                              -- смене фаз (подлёт → орбита → отлёт) траектория
	                              -- скругляется, рывков нет
}

local function buildConfig(bossType)
	local def = BOSS_CONFIGS[bossType]
	if not def then return nil end
	local cfg = {}
	for k, v in pairs(DEFAULTS) do cfg[k] = v end
	for k, v in pairs(def) do cfg[k] = v end
	return cfg
end

local BossClass = {}
BossClass.__index = BossClass

BossClass.CONFIGS = BOSS_CONFIGS

-- Заглушка-вертолёт из Part'ов (пока нет моделей из задачи 4)
local function buildPlaceholderModel(cfg)
	local model = Instance.new("Model")

	local body = Instance.new("Part")
	body.Name  = "Body"
	body.Size  = Vector3.new(4, 2.5, 7)
	body.Color = cfg.bodyColor
	body.Material = Enum.Material.Metal
	body.Parent = model

	local cockpit = Instance.new("Part")
	cockpit.Name  = "Cockpit"
	cockpit.Shape = Enum.PartType.Ball
	cockpit.Size  = Vector3.new(2.4, 2.4, 2.4)
	cockpit.Color = cfg.beamColor
	cockpit.Material = Enum.Material.Neon
	cockpit.CFrame = body.CFrame * CFrame.new(0, 0.6, -3)
	cockpit.Parent = model

	local rotor = Instance.new("Part")
	rotor.Name  = "Rotor"
	rotor.Size  = Vector3.new(10, 0.3, 1)
	rotor.Color = Color3.fromRGB(60, 60, 60)
	rotor.CFrame = body.CFrame * CFrame.new(0, 1.8, 0)
	rotor.Parent = model

	model.PrimaryPart = body
	return model
end

-- opts:
--   getTowers — список активных башен (TowerService.getTowers)
--   anchor    — точка «центра карты» для блуждания без целей (Vector3)
--   spawnPos  — где появиться
function BossClass.new(bossType, opts)
	local cfg = buildConfig(bossType)
	if not cfg then
		warn("Неизвестный тип босса: " .. tostring(bossType))
		return nil
	end
	opts = opts or {}

	-- Своя модель из ServerStorage (templateName или "Boss_<Тип>") или заглушка
	local model
	local template = (cfg.templateName and ServerStorage:FindFirstChild(cfg.templateName))
		or ServerStorage:FindFirstChild("Boss_" .. bossType)
	if template then
		model = template:Clone()
	else
		model = buildPlaceholderModel(cfg)
	end
	model.Name = bossType

	local rootPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not rootPart then
		warn("Босс '" .. bossType .. "': нет ни одной BasePart — спавн отменён")
		model:Destroy()
		return nil
	end

	local self = setmetatable({}, BossClass)
	self.model     = model
	self.rootPart  = rootPart
	self.config    = cfg
	self.type      = bossType
	self.maxHP     = cfg.hp
	self.hp        = cfg.hp
	self.isAlive   = true
	self.isBoss    = true
	self.friendly  = false
	self.getTowers = opts.getTowers or function() return {} end
	self.anchor    = opts.anchor or Vector3.new(0, 0, 0)
	self.base      = opts.base -- чтобы таранить базу, если башен не осталось
	self.onDied    = nil

	-- состояние модели полёта (см. FLIGHT)
	self.velocity   = Vector3.zero
	self.yaw        = 0
	self.bank       = 0
	self.pitch      = 0
	self.turnRateLP = 0   -- сглаженная скорость поворота (для крена)
	self.flyTarget  = nil -- сглаженная точка назначения
	self.bobPhase   = math.random() * math.pi * 2

	model:SetAttribute("Boss", true)

	-- Humanoid из чужого шаблона мешает — удаляем
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then humanoid:Destroy() end

	-- Та же жёсткая сборка, что у врагов: якорный rootPart + сварка.
	-- Детали с "Rotor" в имени НЕ привариваются — они крутятся сами
	-- (их позицию каждый кадр задаёт spin-апдейтер относительно корпуса).
	self.rotors = {} -- {part = деталь, offset = CFrame относительно корпуса}
	rootPart.Anchored   = true
	rootPart.CanCollide = false
	rootPart.CanQuery   = false
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part ~= rootPart then
			part.Anchored   = true
			part.CanCollide = false
			part.CanQuery   = false
			if part.Name:lower():find("rotor") then
				table.insert(self.rotors, {
					part   = part,
					offset = rootPart.CFrame:ToObjectSpace(part.CFrame),
				})
			else
				local weld = Instance.new("WeldConstraint")
				weld.Part0  = rootPart
				weld.Part1  = part
				weld.Parent = part
				part.Anchored = false
			end
		end
	end

	-- Точка выстрела: деталь "Muzzle" в модели (если есть)
	self.muzzle = model:FindFirstChild("Muzzle", true)

	self:createHPBar()
	self:startRotorSpin()

	model.Parent = workspace
	rootPart.CFrame = CFrame.new(opts.spawnPos or (self.anchor + Vector3.new(0, cfg.flyHeight + 10, 0)))

	task.spawn(function() self:runBehavior() end)
	return self
end

-- Винты крутятся вокруг своей вертикальной оси, следуя за корпусом
function BossClass:startRotorSpin()
	if #self.rotors == 0 then return end
	local spinAngle = 0
	self.rotorConn = RunService.Heartbeat:Connect(function(dt)
		if not self.isAlive then
			self.rotorConn:Disconnect()
			return
		end
		spinAngle = spinAngle + ROTOR_SPIN_SPEED * dt
		local rootCF = self.rootPart.CFrame
		for _, rotor in ipairs(self.rotors) do
			rotor.part.CFrame = rootCF * rotor.offset * CFrame.Angles(0, spinAngle, 0)
		end
	end)
end

-- Откуда летят снаряды
function BossClass:getMuzzlePos()
	if self.muzzle and self.muzzle.Parent then
		return self.muzzle.Position
	end
	return self.rootPart.Position
end

function BossClass:createHPBar()
	local billboard = Instance.new("BillboardGui")
	billboard.Size        = UDim2.new(8, 0, 1.4, 0)
	billboard.StudsOffset = Vector3.new(0, 4, 0)
	billboard.AlwaysOnTop = false
	billboard.Parent      = self.rootPart

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size                   = UDim2.new(1, 0, 0.5, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextColor3             = self.config.beamColor
	nameLabel.TextScaled             = true
	nameLabel.Font                   = Enum.Font.GothamBold
	nameLabel.Text                   = "👑 " .. self.config.displayName
	nameLabel.Parent                 = billboard

	local bg = Instance.new("Frame")
	bg.Size             = UDim2.new(1, 0, 0.4, 0)
	bg.Position         = UDim2.new(0, 0, 0.55, 0)
	bg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	bg.BorderSizePixel  = 0
	bg.Parent           = billboard

	local bar = Instance.new("Frame")
	bar.Size             = UDim2.new(1, 0, 1, 0)
	bar.BackgroundColor3 = Color3.fromRGB(200, 50, 200)
	bar.BorderSizePixel  = 0
	bar.Parent           = bg

	local label = Instance.new("TextLabel")
	label.Size                   = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextColor3             = Color3.fromRGB(255, 255, 255)
	label.TextScaled             = true
	label.Text                   = self.maxHP .. " / " .. self.maxHP
	label.Parent                 = bg

	self.hpBar   = bar
	self.hpLabel = label
end

function BossClass:takeDamage(amount, damageColor)
	if not self.isAlive then return end
	self.hp = math.max(0, self.hp - amount)

	if self.hpBar then
		self.hpBar.Size = UDim2.new(self.hp / self.maxHP, 0, 1, 0)
		self.hpLabel.Text = math.floor(self.hp) .. " / " .. self.maxHP
	end
	Effects.damageNumber(self.rootPart.Position + Vector3.new(0, 3, 0), amount, damageColor)

	if self.hp <= 0 then
		self.killedByDamage = true
		self:die()
	end
end

function BossClass:die()
	if not self.isAlive then return end
	self.isAlive = false
	Effects.sphere(self.rootPart.Position, self.config.beamColor, 4, 24, 0.8)
	if self.onDied then self.onDied() end
	self.model:Destroy()
end

-- ============================================
-- ВЫБОР ЦЕЛИ
-- Приоритет — башня с максимальным нанесённым уроном (totalDamage);
-- иногда летим к случайной, чтобы движение было «от башни к башне».
-- ============================================

function BossClass:pickTarget()
	local candidates = {}
	for _, tower in ipairs(self.getTowers()) do
		if tower.health and tower.health > 0 and tower.rootPart and tower.model.Parent then
			table.insert(candidates, tower)
		end
	end
	if #candidates == 0 then return nil end

	-- стараемся не зависать на одной башне
	if #candidates > 1 and self.lastTarget then
		for i, t in ipairs(candidates) do
			if t == self.lastTarget then
				table.remove(candidates, i)
				break
			end
		end
	end

	local target
	if math.random() < RANDOM_TARGET_CHANCE then
		target = candidates[math.random(#candidates)]
	else
		target = candidates[1]
		for _, t in ipairs(candidates) do
			if (t.totalDamage or 0) > (target.totalDamage or 0) then
				target = t
			end
		end
	end
	self.lastTarget = target
	return target
end

-- ============================================
-- ПОЛЁТ
-- ============================================

local function isTowerValid(tower)
	return tower and tower.health > 0 and tower.rootPart and tower.model.Parent
end

-- Один кадр полёта к точке. Возвращает оставшуюся дистанцию.
-- Скорость с инерцией; нос — по ходу движения; крен — из скорости
-- поворота (в орбите вертолёт сам ложится в вираж); нос наклоняется
-- вперёд тем сильнее, чем быстрее летим; плюс лёгкое покачивание.
function BossClass:stepFlight(dt, targetPos)
	local pos = self.rootPart.Position

	-- Сглаживаем саму точку назначения: когда поведение резко меняет
	-- цель (подлёт → орбита → отлёт), вертолёт не дёргается, а плавно
	-- перекладывает курс по дуге
	if not self.flyTarget then
		self.flyTarget = targetPos
	end
	local targetAlpha = 1 - math.exp(-FLIGHT.targetSmooth * dt)
	self.flyTarget = self.flyTarget:Lerp(targetPos, targetAlpha)

	local toTarget = self.flyTarget - pos
	local dist = toTarget.Magnitude

	-- Желаемая скорость: к цели, у самой цели — мягко гасим
	local desiredVel = Vector3.zero
	if dist > 0.5 then
		local speedCap = math.min(self.config.speed, dist * 1.2) -- торможение у цели
		desiredVel = toTarget.Unit * speedCap
	end
	local accelAlpha = 1 - math.exp(-FLIGHT.accel * dt)
	self.velocity = self.velocity:Lerp(desiredVel, accelAlpha)

	-- Позиция + вертикальное покачивание (производная синуса)
	self.bobPhase = self.bobPhase + FLIGHT.bobSpeed * dt
	local bobVelY = FLIGHT.bobAmplitude * FLIGHT.bobSpeed * math.cos(self.bobPhase)
	local newPos = pos + self.velocity * dt + Vector3.new(0, bobVelY * dt, 0)

	-- Нос по горизонтальному направлению полёта (плавный yaw)
	local flatVel = Vector3.new(self.velocity.X, 0, self.velocity.Z)
	local speedFrac = math.min(flatVel.Magnitude / self.config.speed, 1)
	if flatVel.Magnitude > 1 then
		local targetYaw = math.atan2(-flatVel.X, -flatVel.Z)
		local dyaw = targetYaw - self.yaw
		dyaw = math.atan2(math.sin(dyaw), math.cos(dyaw)) -- кратчайший поворот через ±180°
		local turnAlpha = 1 - math.exp(-FLIGHT.turnSmooth * dt)
		local applied = dyaw * turnAlpha
		self.yaw = self.yaw + applied

		-- Крен — в сторону поворота, пропорционально его скорости.
		-- Скорость поворота дополнительно прогоняем через low-pass:
		-- мгновенный applied/dt дрожит от кадра к кадру и при смене цели
		local rawRate = applied / math.max(dt, 1e-4)
		local lpAlpha = 1 - math.exp(-FLIGHT.bankSmooth * dt)
		self.turnRateLP = self.turnRateLP + (rawRate - self.turnRateLP) * lpAlpha

		local targetBank = math.clamp(self.turnRateLP / FLIGHT.bankTurnRef, -1, 1) * FLIGHT.maxBank
		local tiltAlpha = 1 - math.exp(-FLIGHT.tiltSmooth * dt)
		self.bank = self.bank + (targetBank - self.bank) * tiltAlpha
	else
		-- зависли: выравниваем крен
		local tiltAlpha = 1 - math.exp(-FLIGHT.tiltSmooth * dt)
		self.turnRateLP = self.turnRateLP + (0 - self.turnRateLP) * tiltAlpha
		self.bank = self.bank + (0 - self.bank) * tiltAlpha
	end

	-- Тангаж: нос вперёд-вниз на скорости
	local targetPitch = -FLIGHT.maxPitch * speedFrac
	local tiltAlpha = 1 - math.exp(-FLIGHT.tiltSmooth * dt)
	self.pitch = self.pitch + (targetPitch - self.pitch) * tiltAlpha

	self.rootPart.CFrame = CFrame.new(newPos)
		* CFrame.fromOrientation(self.pitch, self.yaw, self.bank)

	-- дистанцию возвращаем до НАСТОЯЩЕЙ цели (не сглаженной),
	-- чтобы проверки «долетел?» в flyTo не зависели от сглаживания
	return (targetPos - newPos).Magnitude
end

-- Летим к точке; выходим по достижении, смерти или таймауту
function BossClass:flyTo(point, reach, timeout)
	local elapsed = 0
	timeout = timeout or 10
	while self.isAlive and elapsed < timeout do
		local dt = task.wait()
		elapsed = elapsed + dt
		if self:stepFlight(dt, point) <= reach then
			return true
		end
	end
	return false
end

-- ============================================
-- АТАКИ
-- ============================================

function BossClass:attackTower(tower)
	local cfg = self.config
	local from = self:getMuzzlePos()
	local to = tower.rootPart.Position

	if cfg.weapon == "rocket" then
		-- Ракета сверху вниз по башне
		local rocket = Instance.new("Part")
		rocket.Size       = Vector3.new(0.6, 0.6, 2.4)
		rocket.Color      = cfg.beamColor
		rocket.Material   = Enum.Material.Neon
		rocket.Anchored   = true
		rocket.CanCollide = false
		rocket.CanQuery   = false
		rocket.CastShadow = false
		rocket.CFrame     = CFrame.new(from, to)
		rocket.Parent     = workspace

		task.spawn(function()
			local speed = 50
			local pos = from
			local flightTime = 0
			while flightTime < 4 do
				local dt = task.wait()
				flightTime = flightTime + dt
				local delta = to - pos
				if delta.Magnitude < 3 then break end
				pos = pos + delta.Unit * speed * dt
				rocket.CFrame = CFrame.new(pos, to)
			end
			rocket:Destroy()
			Effects.sphere(to, cfg.beamColor, 2, 10, 0.35)
			if isTowerValid(tower) then
				tower:takeDamage(cfg.damage, cfg.beamColor)
			end
		end)
	else
		-- Лазер: мгновенный луч
		Effects.beam(from, to, cfg.beamColor, 0.5, 0.25)
		if cfg.damage > 0 then
			tower:takeDamage(cfg.damage, cfg.beamColor)
		end
	end

	if cfg.stunDuration > 0 then
		tower:stun(cfg.stunDuration)
	end
end

-- Кружим вокруг башни по орбите и атакуем по таймеру.
-- Точка полёта всегда чуть впереди по дуге — вертолёт сам входит
-- в вираж с креном (крен считает stepFlight из скорости поворота).
function BossClass:orbitAndAttack(target)
	local cfg = self.config
	local radius = cfg.attackRange * 0.55
	local orbitSpeed = cfg.speed / radius -- угловая скорость: линейная ≈ speed
	local direction = (math.random(2) == 1) and 1 or -1 -- по/против часовой

	-- начинаем орбиту с того угла, где уже находимся
	local toBoss = self.rootPart.Position - target.rootPart.Position
	local angle = math.atan2(toBoss.Z, toBoss.X)

	local attacks = 0
	local nextAttackAt = os.clock() + 0.4 -- небольшая пауза на «заход»

	while self.isAlive and attacks < cfg.attacksBeforeMove and isTowerValid(target) do
		local dt = task.wait()
		angle = angle + orbitSpeed * direction * dt

		-- летим в точку впереди по дуге — получается плавный вираж
		local aim = angle + FLIGHT.orbitLead * direction
		local center = target.rootPart.Position
		local desired = center + Vector3.new(
			math.cos(aim) * radius,
			cfg.flyHeight,
			math.sin(aim) * radius
		)
		self:stepFlight(dt, desired)

		if os.clock() >= nextAttackAt then
			self:attackTower(target)
			attacks = attacks + 1
			nextAttackAt = os.clock() + 1 / cfg.fireRate

			-- станер не долбит уже оглушённую башню — летит дальше
			if cfg.stunDuration > 0 and isTowerValid(target) and target:isStunned() then
				break
			end
		end
	end
end

-- ============================================
-- ПОВЕДЕНИЕ: цель → подлёт → орбита с атаками → следующая башня
-- ============================================

function BossClass:runBehavior()
	-- База погибла (game over) — босс прекращает поведение, чтобы не
	-- крутиться и не «бить» уже остановленные башни до рестарта
	while self.isAlive and (not self.base or self.base.isAlive) do
		local target = self:pickTarget()

		if not target then
			-- Башен нет: чтобы волна не зависла навсегда (босс не находит
			-- цель и не может быть убит), летим к базе и тараним её.
			-- Станер с damage=0 таранит фиксированным уроном.
			-- Итог: нет башен → база падает → game over, а не софт-лок.
			if self.base and self.base.isAlive and self.base.rootPart then
				local basePos = self.base.rootPart.Position
				self:flyTo(basePos + Vector3.new(0, self.config.flyHeight, 0), 8, 8)
				if self.base.isAlive then
					local dmg = self.config.damage > 0 and self.config.damage or 50
					self.base:takeDamage(dmg)
					Effects.sphere(basePos, self.config.beamColor, 3, 16, 0.5)
				end
				task.wait(1 / math.max(self.config.fireRate, 0.2))
			else
				-- базы нет (нестандартная карта) — просто кружим над центром
				local wander = self.anchor + Vector3.new(
					math.random(-40, 40),
					self.config.flyHeight + math.random(0, 6),
					math.random(-40, 40)
				)
				self:flyTo(wander, 5, 6)
				task.wait(0.5)
			end
			continue
		end

		-- Подлетаем к кольцу орбиты вокруг башни
		local approach = target.rootPart.Position + Vector3.new(
			math.random(-8, 8),
			self.config.flyHeight,
			math.random(-8, 8)
		)
		self:flyTo(approach, self.config.attackRange * 0.6, 12)

		-- Кружим и атакуем, потом перелёт к следующей башне
		if isTowerValid(target) then
			self:orbitAndAttack(target)

			-- Кулдаун после серии: отлетаем в сторону и НЕ атакуем —
			-- окно, в которое башни могут спокойно расстреливать босса
			if self.config.attackCooldown > 0 then
				local retreat = self.anchor + Vector3.new(
					math.random(-40, 40),
					self.config.flyHeight + 8,
					math.random(-40, 40)
				)
				local t0 = os.clock()
				self:flyTo(retreat, 6, self.config.attackCooldown)

				-- долетел раньше — зависаем (с покачиванием) до конца кулдауна
				while self.isAlive and os.clock() - t0 < self.config.attackCooldown do
					local dt = task.wait()
					self:stepFlight(dt, retreat)
				end
			end
		end
	end
end

return BossClass
