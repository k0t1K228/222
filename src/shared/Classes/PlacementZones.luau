-- ============================================
-- ЗОНЫ РАЗМЕЩЕНИЯ БАШЕН
-- В workspace создаётся папка "PlacementZones" с Part'ами —
-- это разрешённые зоны. Башня вне всех зон не активируется.
-- Если папки нет — ограничений нет (ставить можно везде).
-- Модуль общий: его же будет использовать клиентский
-- интерфейс расстановки башен (подсветка можно/нельзя).
-- ============================================

local PlacementZones = {}

local FOLDER_NAME = "PlacementZones"

-- Точка внутри Part'а (по горизонтали; по высоте — с запасом,
-- чтобы башня, стоящая НА зоне, считалась внутри)
local function pointInPart(point, part)
	local localPoint = part.CFrame:PointToObjectSpace(point)
	local half = part.Size / 2
	return math.abs(localPoint.X) <= half.X
		and math.abs(localPoint.Z) <= half.Z
		and math.abs(localPoint.Y) <= half.Y + 10
end

function PlacementZones.getFolder()
	return workspace:FindFirstChild(FOLDER_NAME)
end

function PlacementZones.isAllowed(position)
	local folder = PlacementZones.getFolder()
	if not folder then return true end

	for _, part in ipairs(folder:GetChildren()) do
		if part:IsA("BasePart") and pointInPart(position, part) then
			return true
		end
	end
	return false
end

-- Минимальная дистанция между башнями (по горизонтали)
PlacementZones.MIN_TOWER_DISTANCE = 6

function PlacementZones.isFarFromTowers(position, minDistance)
	minDistance = minDistance or PlacementZones.MIN_TOWER_DISTANCE
	for _, obj in ipairs(workspace:GetChildren()) do
		if obj:IsA("Model") and obj:GetAttribute("TowerActive") then
			local pivot = obj:GetPivot().Position
			local flat = Vector3.new(position.X - pivot.X, 0, position.Z - pivot.Z)
			if flat.Magnitude < minDistance then
				return false
			end
		end
	end
	return true
end

-- Полная проверка точки для размещения башни.
-- Используется и сервером (валидация), и клиентом (подсветка призрака).
function PlacementZones.canPlace(position)
	if not PlacementZones.isAllowed(position) then
		return false, "Вне зоны размещения"
	end
	if not PlacementZones.isFarFromTowers(position) then
		return false, "Слишком близко к другой башне"
	end
	return true, ""
end

return PlacementZones
