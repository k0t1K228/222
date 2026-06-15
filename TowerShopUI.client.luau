-- ============================================
-- КИБЕРПАНК-ТЕМА ИНТЕРФЕЙСА
-- Единый стиль для всех UI проекта: цвета, шрифты и хелперы.
-- Меняешь здесь — меняется везде (магазин, меню башни, HUD).
--
-- Язык стиля:
--   * почти чёрные панели с холодным синим отливом
--   * неоновые рамки (циан/маджента/жёлтый) + лёгкое свечение
--   * моноширинный «терминальный» шрифт Code, заголовки SciFi
--   * тонкая неоновая линия сверху каждой панели
--   * валюта — «кредиты» ₵
-- ============================================

local TweenService = game:GetService("TweenService")

local Theme = {}

Theme.COLORS = {
	bg        = Color3.fromRGB(8, 10, 20),    -- фон панелей
	bgLight   = Color3.fromRGB(16, 20, 38),   -- кнопки, плашки
	bgHover   = Color3.fromRGB(28, 34, 60),   -- кнопка под курсором

	cyan      = Color3.fromRGB(0, 229, 255),  -- основной неон
	magenta   = Color3.fromRGB(255, 0, 170),  -- акцент
	yellow    = Color3.fromRGB(252, 238, 33), -- деньги/предупреждения
	green     = Color3.fromRGB(0, 255, 159),  -- успех/«можно»
	red       = Color3.fromRGB(255, 45, 85),  -- опасность/«нельзя»

	textMain  = Color3.fromRGB(225, 240, 250),
	textDim   = Color3.fromRGB(125, 140, 170),
}

Theme.FONT_TITLE = Enum.Font.SciFi -- заголовки
Theme.FONT_BODY  = Enum.Font.Code  -- текст, статы, кнопки

Theme.CURRENCY = "₵" -- киберпанк-кредиты

-- Цена/деньги одной строкой
function Theme.money(amount)
	return Theme.CURRENCY .. " " .. tostring(amount)
end

-- Скруглённые углы (у киберпанка — едва заметные)
function Theme.corner(parent, px)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, px or 4)
	c.Parent = parent
	return c
end

-- Неоновая рамка
function Theme.stroke(parent, color, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Color = color or Theme.COLORS.cyan
	s.Thickness = thickness or 1
	s.Transparency = transparency or 0.35
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

-- Стилизует Frame под панель: тёмный фон, неоновая рамка,
-- вертикальный градиент и светящаяся линия сверху
function Theme.stylePanel(frame, accent)
	accent = accent or Theme.COLORS.cyan

	frame.BackgroundColor3 = Theme.COLORS.bg
	frame.BackgroundTransparency = 0.08
	frame.BorderSizePixel = 0
	Theme.corner(frame, 6)
	Theme.stroke(frame, accent, 1, 0.4)

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(20, 26, 48)),
		ColorSequenceKeypoint.new(0.25, Theme.COLORS.bg),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(4, 5, 12)),
	})
	gradient.Parent = frame

	local topline = Instance.new("Frame")
	topline.Name = "NeonTopline"
	topline.Size = UDim2.new(1, 0, 0, 2)
	topline.BackgroundColor3 = accent
	topline.BorderSizePixel = 0
	topline.ZIndex = frame.ZIndex + 1
	topline.Parent = frame

	local lineGradient = Instance.new("UIGradient")
	lineGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	lineGradient.Parent = topline

	return frame
end

-- Стилизует кнопку: тёмная плашка + неоновая рамка,
-- при наведении подсвечивается и «вспыхивает» рамка
function Theme.styleButton(btn, accent)
	accent = accent or Theme.COLORS.cyan

	btn.BackgroundColor3 = Theme.COLORS.bgLight
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.Font = Theme.FONT_BODY
	btn.TextColor3 = Theme.COLORS.textMain
	Theme.corner(btn, 4)
	local stroke = Theme.stroke(btn, accent, 1, 0.5)

	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12), {
			BackgroundColor3 = Theme.COLORS.bgHover,
		}):Play()
		TweenService:Create(stroke, TweenInfo.new(0.12), {
			Transparency = 0,
			Thickness = 1.5,
		}):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.2), {
			BackgroundColor3 = Theme.COLORS.bgLight,
		}):Play()
		TweenService:Create(stroke, TweenInfo.new(0.2), {
			Transparency = 0.5,
			Thickness = 1,
		}):Play()
	end)

	return btn
end

-- Заголовок панели: плашка с неоновым текстом в стиле терминала
function Theme.styleTitle(label, accent)
	accent = accent or Theme.COLORS.cyan
	label.BackgroundColor3 = Color3.fromRGB(14, 18, 34)
	label.BackgroundTransparency = 0.2
	label.BorderSizePixel = 0
	label.Font = Theme.FONT_TITLE
	label.TextColor3 = accent
	Theme.corner(label, 6)
	return label
end

-- Текстовая метка в теле панели
function Theme.styleText(label, color)
	label.BackgroundTransparency = 1
	label.Font = Theme.FONT_BODY
	label.TextColor3 = color or Theme.COLORS.textMain
	return label
end

return Theme
