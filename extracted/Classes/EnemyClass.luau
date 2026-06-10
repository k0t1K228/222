local RunService = game:GetService("RunService")

local CONFIG = {
	speed         = 15,
	rotateSpeed   = 0.15,
	spawnHeight   = 3,
	waypointReach = 2,
	baseReach     = 6,
	spread        = 4, -- разброс врагов от маршрута
}

local EnemyClass = {}
EnemyClass.__index = EnemyClass

function EnemyClass.new(model, waypoints, base)
	local self = setmetatable({}, EnemyClass)
	self.model       = model
	self.rootPart    = model.PrimaryPart
	self.waypoints   = waypoints
	self.base        = base
	self.maxHP       = 100
	self.hp          = 100
	self.isAlive     = true
	self.isAttacking = false
	self.attackAngle = 0

	-- Случайный разброс для каждого врага
	self.offsetX = math.random(-CONFIG.spread, CONFIG.spread)
	self.offsetZ = math.random(-CONFIG.spread, CONFIG.spread)

	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.Anchored   = true
		end
	end

	self:createHPBar()
	return self
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
	self.hpLabel.Text = self.hp .. " / " .. self.maxHP
	if pct > 0.5 then
		self.hpBar.BackgroundColor3 = Color3.fromRGB(50, 200, 50)
	elseif pct > 0.25 then
		self.hpBar.BackgroundColor3 = Color3.fromRGB(255, 200, 0)
	else
		self.hpBar.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
	end
end

function EnemyClass:takeDamage(amount)
	if not self.isAlive then return end
	self.hp = math.max(0, self.hp - amount)
	self:updateHPBar()
	if self.hp <= 0 then self:die() end
end

function EnemyClass:die()
	self.isAlive = false
	self.model:Destroy()
	print("Враг уничтожен!")
end

function EnemyClass:attackBase()
	if self.isAttacking then return end
	self.isAttacking = true
	task.spawn(function()
		while self.isAlive and self.base.isAlive do
			self.base:takeDamage(self.hp)
			task.wait(1)
		end
	end)
end

-- Плавное движение через Heartbeat с delta time
function EnemyClass:moveTo(targetPos, reachDistance, callback)
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		if not self.isAlive then
			connection:Disconnect()
			return
		end

		local currentPos = self.rootPart.Position
		local flatTarget = Vector3.new(targetPos.X, currentPos.Y, targetPos.Z)
		local dist = (currentPos - flatTarget).Magnitude

		if dist <= reachDistance then
			connection:Disconnect()
			if callback then callback() end
			return
		end

		local direction   = (flatTarget - currentPos).Unit
		local newPos      = currentPos + direction * CONFIG.speed * dt

		-- Плавный поворот
		local currentCF  = self.model:GetPrimaryPartCFrame()
		local targetCF   = CFrame.new(currentPos, flatTarget)
		local smoothCF   = currentCF:Lerp(targetCF, CONFIG.rotateSpeed)

		self.model:SetPrimaryPartCFrame(
			CFrame.new(newPos) * (smoothCF - smoothCF.Position)
		)
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

	local basePos = baseRoot.Position

	-- Двигаемся к базе
	self:moveTo(basePos, 7, function()
		if not self.isAlive then return end

		-- Включаем физику когда дошли — враги толкают друг друга
		for _, part in ipairs(self.model:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored   = false
				part.CanCollide = true
				-- Лёгкое притяжение к базе через физику
				local bodyPos = Instance.new("BodyPosition")
				bodyPos.Position      = Vector3.new(
					basePos.X + math.cos(self.attackAngle) * 6,
					basePos.Y,
					basePos.Z + math.sin(self.attackAngle) * 6
				)
				bodyPos.MaxForce      = Vector3.new(2000, 0, 2000) -- только по горизонтали
				bodyPos.P             = 500
				bodyPos.D             = 50
				bodyPos.Parent        = part
			end
		end

		self:attackBase()
	end)
end

return EnemyClass