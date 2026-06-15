-- ============================================
-- БОЕВЫЕ ЭФФЕКТЫ И ЦИФРЫ УРОНА
--
-- ПРАВИЛО ПРОЕКТА: сервер НЕ создаёт Part'ы для разовых эффектов.
-- Сервер шлёт одно событие CombatFX, каждый клиент рисует эффект
-- у себя локально. Это разгружает сервер и репликацию.
--
-- Сервер:  Effects.beam(...) / Effects.sphere(...) / Effects.damageNumber(...)
-- Клиент:  EffectsClient.client.luau слушает ремоут и вызывает Effects.render*
--
-- Исключения (живут на сервере осознанно):
--   * луч лазера — один персистентный Part на башню, обновляется каждый кадр
--   * ракета — позиция снаряда решает, кому идёт урон
-- ============================================

local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Effects = {}

-- ============ СЕРВЕРНАЯ ЧАСТЬ ============
if RunService:IsServer() then
	local remote = ReplicatedStorage:FindFirstChild("CombatFX")
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = "CombatFX"
		remote.Parent = ReplicatedStorage
	end

	function Effects.beam(startPos, endPos, color, thickness, lifetime)
		remote:FireAllClients("beam", startPos, endPos, color, thickness, lifetime)
	end

	function Effects.sphere(pos, color, startSize, endSize, lifetime)
		remote:FireAllClients("sphere", pos, color, startSize, endSize, lifetime)
	end

	function Effects.damageNumber(pos, amount, color)
		remote:FireAllClients("dmg", pos, amount, color)
	end

	return Effects
end

-- ============ КЛИЕНТСКАЯ ЧАСТЬ (рендер) ============

local TweenService = game:GetService("TweenService")
local Debris       = game:GetService("Debris")

local rng = Random.new()

-- Бюджет: при больших волнах не даём эффектам забить клиент
local liveCount = 0
local MAX_LIVE = 80

local function takeBudget(lifetime)
	if liveCount >= MAX_LIVE then return false end
	liveCount = liveCount + 1
	task.delay(lifetime + 0.1, function()
		liveCount = liveCount - 1
	end)
	return true
end

function Effects.getRemote()
	return ReplicatedStorage:WaitForChild("CombatFX")
end

function Effects.renderBeam(startPos, endPos, color, thickness, lifetime)
	local length = (startPos - endPos).Magnitude
	if length < 0.1 then return end
	if not takeBudget(lifetime) then return end

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

	Debris:AddItem(beam, lifetime)
end

function Effects.renderSphere(pos, color, startSize, endSize, lifetime)
	if not takeBudget(lifetime) then return end

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
	Debris:AddItem(s, lifetime + 0.05)
end

function Effects.renderDamageNumber(pos, amount, color)
	if not takeBudget(0.85) then return end

	local anchor = Instance.new("Part")
	anchor.Size         = Vector3.new(0.1, 0.1, 0.1)
	anchor.Transparency = 1
	anchor.Anchored     = true
	anchor.CanCollide   = false
	anchor.CanQuery     = false
	anchor.CastShadow   = false
	anchor.Position     = pos + Vector3.new(rng:NextNumber(-1.5, 1.5), 0, rng:NextNumber(-1.5, 1.5))
	anchor.Parent       = workspace

	local billboard = Instance.new("BillboardGui")
	billboard.Size        = UDim2.new(0, 90, 0, 34)
	billboard.AlwaysOnTop = true
	billboard.Parent      = anchor

	local label = Instance.new("TextLabel")
	label.Size                   = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font                   = Enum.Font.GothamBold
	label.TextScaled             = true
	label.Text                   = tostring(math.max(1, math.floor(amount + 0.5)))
	label.TextColor3             = color or Color3.fromRGB(255, 255, 255)
	label.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)
	label.TextStrokeTransparency = 0.2
	label.Parent                 = billboard

	TweenService:Create(billboard, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffset = Vector3.new(0, 4, 0),
	}):Play()
	TweenService:Create(label, TweenInfo.new(0.8), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()

	Debris:AddItem(anchor, 0.85)
end

return Effects
