-- ============================================
-- ВСПЛЫВАЮЩИЕ ЦИФРЫ УРОНА (стиль Genshin)
-- Вызывается на сервере — реплицируется всем игрокам.
-- Цвет передаёт тип оружия (огонь — оранжевый, лазер — розовый...).
-- ============================================

local TweenService = game:GetService("TweenService")
local Debris       = game:GetService("Debris")

local DamageNumbers = {}
local rng = Random.new()

function DamageNumbers.show(position, amount, color)
	local anchor = Instance.new("Part")
	anchor.Size         = Vector3.new(0.1, 0.1, 0.1)
	anchor.Transparency = 1
	anchor.Anchored     = true
	anchor.CanCollide   = false
	anchor.CanQuery     = false
	anchor.CastShadow   = false
	anchor.Position     = position + Vector3.new(rng:NextNumber(-1.5, 1.5), 0, rng:NextNumber(-1.5, 1.5))
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

	-- взлетает вверх и тает
	TweenService:Create(billboard, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffset = Vector3.new(0, 4, 0),
	}):Play()
	TweenService:Create(label, TweenInfo.new(0.8), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()

	Debris:AddItem(anchor, 0.85)
end

return DamageNumbers
