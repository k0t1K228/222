local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local DamageNumbers = require(script.Parent.DamageNumbers)

local CONFIG = {
	speed         = 15,
	rotateSpeed   = 0.15,
	spawnHeight   = 3,
	waypointReach = 2,
	baseReach     = 7,
	spread        = 4, -- разброс врагов от маршрута
}

local EnemyClass = {}
EnemyClass.__index = EnemyClass

function EnemyClass.new(model, waypoints, base)
	local rootPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not rootPart then
		warn("Враг '" .. model.Name .. "': нет PrimaryPart и ни одной BasePart — спавн отменён")
		model:Destroy()
		return nil
	end

	local self = setmetatable({}, EnemyClass)
	self.model     = model
	self.rootPart  = rootPart
	self.waypoints = waypoints
	self.base      = base
	self.maxHP     = 100
	self.hp        = 100
	self.isAlive   = true
	self.onDied    = nil -- колбэк: GameManager убирает врага из списка

	-- Случайный разброс для каждого врага
	self.offsetX = math.random(-CONFIG.spread, CONFIG.spread)
	self.offsetZ = math.random(-CONFIG.spread, CONFIG.spread)

	-- Humanoid из шаблона-рига не нужен: он вмешивается
	-- в физику и позиционирование. Удаляем.
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then humanoid:Destroy() end

	-- Жёсткая сборка: rootPart — единственный якорь, все остальные
	-- детали привариваются к нему. Двигаем ТОЛЬКО rootPart.CFrame,
	-- поэтому визуал физически не может разъехаться с хитбоксом
	-- (не зависит ни от pivot, ни от Motor6D, ни от PivotOffset).
	rootPart.Anchored   = true
	rootPart.CanCollide = false
	rootPart.CanQuery   = false -- курсор/рейкасты игнорируют врагов
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part ~= rootPart then
			local weld = Instance.new("WeldConstraint")
			weld.Part0  = rootPart
			weld.Part1  = part
			weld.Parent = part
			part.Anchored   = false
			part.CanCollide = false
			part.CanQuery   = false
		end
	end

	self:createHPBar()
	return self
end

-- Мгновенно ставит врага в точку (используется при спавне)
function EnemyClass:teleportTo(position)
	self.rootPart.CFrame = CFrame.new(position)
end

function EnemyClass:createHPBar()
	local billboard = Instance.new("BillboardGui")
	billboard.Size        = UDim2.new(4, 0, 0.5, 0)
	billboard.StudsOffset = Vector3.new(0, 5, 0)
	billboard.AlwaysOnTop = false
	billboard.Parent      = self.rootPart

	local bg = Instance.new("Frame")
	bg.Size             = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	bg.BorderSizePixel  = 0
	bg.Parent           = billboard

	local bar = Instance.new("Frame")
	bar.Name            = "HPBar"
	bar.Size            = UDim2.new(1, 0, 1, 0)
	bar.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
	bar.BorderSizePixel = 0
	bar.Parent          = bg

	local label = Instance.new("TextLabel")
	label.Size                   = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextColor3             = Color3.fromRGB(255, 255, 255)
	label.TextScaled             = true
	label.Text                   = "100 / 100"
	label.Parent                 = bg

	self.hpBar   = bar
	self.hpLabel = label
end

function EnemyClass:updateHPBar()
	if not self.hpBar then return end
	local pct = self.hp / self.maxHP
	self.hpBar.Size = UDim2.new(pct, 0, 1, 0)
	self.hpLabel.Text = math.floor(self.hp) .. " / " .. self.maxHP
	if pct > 0.5 then
		self.hpBar.BackgroundColor3 = Color3.fromRGB(50, 200, 50)
	elseif pct > 0.25 then
		self.hpBar.BackgroundColor3 = Color3.fromRGB(255, 200, 0)
	else
		self.hpBar.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
	end
end

function EnemyClass:takeDamage(amount, damageColor)
	if not self.isAlive then return end
	self.hp = math.max(0, self.hp - amount)
	self:updateHPBar()

	-- всплывающая цифра урона (цвет = тип оружия)
	DamageNumbers.show(self.rootPart.Position + Vector3.new(0, 4, 0), amount, damageColor)

	if self.hp <= 0 then
		self.killedByDamage = true -- убит башней, а не самоподрывом — даём награду
		self:die()
	end
end

function EnemyClass:die()
	if not self.isAlive then return end
	self.isAlive = false
	if self.onDied then self.onDied() end
	self.model:Destroy()
end

-- Камикадзе: дошёл до базы — один удар на свои ТЕКУЩИЕ HP и сразу умирает.
-- Подраненный враг бьёт слабее — добивать врагов до базы выгодно.
function EnemyClass:explode()
	if not self.isAlive then return end
	local damage = self.hp

	-- Визуальный взрыв
	local boom = Instance.new("Part")
	boom.Shape        = Enum.PartType.Ball
	boom.Size         = Vector3.new(2, 2, 2)
	boom.Position     = self.rootPart.Position
	boom.Anchored     = true
	boom.CanCollide   = false
	boom.Color        = Color3.fromRGB(255, 100, 0)
	boom.Material     = Enum.Material.Neon
	boom.CastShadow   = false
	boom.Transparency = 0.2
	boom.Parent       = workspace
	TweenService:Create(boom, TweenInfo.new(0.4), {
		Size = Vector3.new(12, 12, 12),
		Transparency = 1,
	}):Play()
	task.delay(0.45, function() boom:Destroy() end)

	self.base:takeDamage(damage)
	self:die()
end

-- Плавное движение через Heartbeat с delta time
function EnemyClass:moveTo(targetPos, reachDistance, callback)
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		if not self.isAlive then
			connection:Disconnect()
			return
		end

		-- Читаем и пишем позицию ТОЛЬКО через rootPart.CFrame.
		-- Все детали модели приварены к rootPart, так что двигается
		-- вся сборка целиком, без рассинхрона хитбокса и визуала.
		local rootCF     = self.rootPart.CFrame
		local currentPos = rootCF.Position
		local flatTarget = Vector3.new(targetPos.X, currentPos.Y, targetPos.Z)
		local dist = (currentPos - flatTarget).Magnitude

		if dist <= reachDistance then
			connection:Disconnect()
			if callback then callback() end
			return
		end

		local direction = (flatTarget - currentPos).Unit
		local newPos    = currentPos + direction * CONFIG.speed * dt

		-- Плавный поворот
		local targetCF = CFrame.new(currentPos, flatTarget)
		local smoothCF = rootCF:Lerp(targetCF, CONFIG.rotateSpeed)

		self.rootPart.CFrame =
			CFrame.new(newPos) * (smoothCF - smoothCF.Position)
	end)
end

function EnemyClass:move()
	local index = 1

	local function nextWaypoint()
		if not self.isAlive then return end
		if index > #self.waypoints then
			self:goToBase()
			return
		end

		local wp = self.waypoints[index]
		index = index + 1

		-- Добавляем случайный разброс к каждой точке
		local target = Vector3.new(
			wp.Position.X + self.offsetX,
			wp.Position.Y,
			wp.Position.Z + self.offsetZ
		)

		self:moveTo(target, CONFIG.waypointReach, nextWaypoint)
	end

	nextWaypoint()
end

function EnemyClass:goToBase()
	if not self.isAlive then return end

	local baseRoot = self.base.model:FindFirstChild("TowerBase")
		or self.base.model:FindFirstChildWhichIsA("BasePart")
	if not baseRoot then return end

	-- Дошёл до базы — взрыв-камикадзе
	self:moveTo(baseRoot.Position, CONFIG.baseReach, function()
		self:explode()
	end)
end

return EnemyClass
