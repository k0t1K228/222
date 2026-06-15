-- ============================================
-- ИНДИКАТОР РАДИУСА БАШНИ (чисто клиентский визуал)
-- Полупрозрачная «силовая» заливка + неоновое кольцо из штрихов,
-- которое медленно вращается и пульсирует. Используется в меню
-- башни (TowerInfoUI) и при размещении призрака (TowerShopUI).
--
-- API:
--   local ind = RangeIndicator.new(color)
--   ind:setPosition(vec3)  -- центр круга (точка на земле)
--   ind:setRadius(r)
--   ind:setColor(color)    -- зелёный/красный при размещении
--   ind:destroy()
-- ============================================

local RunService = game:GetService("RunService")

local SEGMENTS    = 36   -- штрихов в кольце
local DASH_FILL   = 0.55 -- доля дуги под штрихом (остальное — зазор)
local SPIN_SPEED  = 0.35 -- рад/сек вращения кольца
local PULSE_SPEED = 2.4  -- частота пульсации прозрачности

local RangeIndicator = {}
RangeIndicator.__index = RangeIndicator

local function basePart()
	local p = Instance.new("Part")
	p.Anchored   = true
	p.CanCollide = false
	p.CanQuery   = false
	p.CastShadow = false
	return p
end

function RangeIndicator.new(color)
	local self = setmetatable({}, RangeIndicator)
	self.color  = color or Color3.fromRGB(0, 229, 255)
	self.radius = 10
	self.center = nil -- круг не виден, пока не задали позицию
	self.angle  = 0

	self.folder = Instance.new("Folder")
	self.folder.Name = "RangeIndicator"
	self.folder.Parent = workspace

	-- Заливка: тонкий цилиндр с «силовым полем»
	local fill = basePart()
	fill.Shape        = Enum.PartType.Cylinder
	fill.Material     = Enum.Material.ForceField
	fill.Color        = self.color
	fill.Transparency = 0.55
	fill.Parent       = self.folder
	self.fill = fill

	-- Кольцо из неоновых штрихов
	self.segments = {}
	for i = 1, SEGMENTS do
		local seg = basePart()
		seg.Material = Enum.Material.Neon
		seg.Color    = self.color
		seg.Parent   = self.folder
		self.segments[i] = seg
	end

	self.conn = RunService.Heartbeat:Connect(function(dt)
		self:_update(dt)
	end)
	return self
end

function RangeIndicator:setPosition(pos)
	self.center = pos
end

function RangeIndicator:setRadius(r)
	self.radius = math.max(r, 1)
end

function RangeIndicator:setColor(color)
	if color == self.color then return end
	self.color = color
	self.fill.Color = color
	for _, seg in ipairs(self.segments) do
		seg.Color = color
	end
end

function RangeIndicator:_update(dt)
	local c = self.center
	if not c then return end

	self.angle = self.angle + SPIN_SPEED * dt
	local pulse = 0.5 + 0.5 * math.sin(os.clock() * PULSE_SPEED)
	local segTransparency = 0.05 + 0.35 * pulse

	local r = self.radius
	self.fill.Size = Vector3.new(0.05, r * 2, r * 2)
	self.fill.CFrame = CFrame.new(c) * CFrame.Angles(0, 0, math.rad(90))

	local arc = (2 * math.pi) / SEGMENTS
	local dashLen = math.max(arc * r * DASH_FILL, 0.4)
	for i, seg in ipairs(self.segments) do
		local a = self.angle + arc * i
		local pos = c + Vector3.new(math.cos(a) * r, 0.15, math.sin(a) * r)
		local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
		seg.Size = Vector3.new(dashLen, 0.12, 0.3)
		-- штрих лежит вдоль касательной к окружности
		seg.CFrame = CFrame.lookAt(pos, pos + tangent) * CFrame.Angles(0, math.rad(90), 0)
		seg.Transparency = segTransparency
	end
end

function RangeIndicator:destroy()
	if self.conn then
		self.conn:Disconnect()
		self.conn = nil
	end
	self.folder:Destroy()
end

return RangeIndicator
