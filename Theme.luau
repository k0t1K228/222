-- ============================================
-- ПРИЁМНИК БОЕВЫХ ЭФФЕКТОВ
-- Сервер шлёт события CombatFX — рисуем эффекты локально.
-- ============================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Effects = require(ReplicatedStorage:WaitForChild("Classes"):WaitForChild("Effects"))

Effects.getRemote().OnClientEvent:Connect(function(kind, ...)
	if kind == "beam" then
		Effects.renderBeam(...)
	elseif kind == "sphere" then
		Effects.renderSphere(...)
	elseif kind == "dmg" then
		Effects.renderDamageNumber(...)
	end
end)
