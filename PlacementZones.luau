-- ============================================
-- ТЕСТОВАЯ ЛОКАЦИЯ (автогенерация из кубиков)
-- Достраивает второй маршрут, если его нет.
--
-- ⚠️ Зоны размещения (PlacementZones) НЕ генерируются —
-- их расставляет картодел руками под конкретную карту
-- (см. HANDBOOK.md §1.3). Нет папки = ставить можно везде.
--
-- ⚠️ Здания-блокеры обзора ТОЖЕ НЕ генерируются: картодел сам
-- кладёт любые Part'ы в папку workspace.Buildings и решает,
-- где между маршрутами башни не должны «видеть» врагов.
-- Нет папки/пустая папка = обзор ничем не ограничен.
--
-- Route1/Route2 создаются, только если в WaypointsFolder
-- лежат «плоские» точки без папок маршрутов.
--
-- Выключить генерацию: TestMap.ENABLED = false.
-- Вызывается из GameManager ДО разбора маршрутов.
-- ============================================

local TestMap = {}

TestMap.ENABLED = true

local ROUTE2_BULGE = 26 -- насколько второй маршрут выгибается вбок

-- Точки контейнера, отсортированные по числу в имени
local function sortedPoints(container)
	local parts = {}
	for _, obj in ipairs(container:GetChildren()) do
		if obj:IsA("BasePart") then
			table.insert(parts, obj)
		end
	end
	table.sort(parts, function(a, b)
		return (tonumber(a.Name:match("%d+")) or 0) < (tonumber(b.Name:match("%d+")) or 0)
	end)
	return parts
end

function TestMap.build()
	if not TestMap.ENABLED then return end

	local wf = workspace:FindFirstChild("WaypointsFolder")
	if not wf then return end

	-- ============ 1. ВТОРОЙ МАРШРУТ ============
	-- Если точки лежат «плоско» — раскладываем их в Route1
	-- и строим Route2: ту же дорогу, выгнутую дугой вбок
	-- (общие старт и финиш, разная середина).
	local hasRouteFolders = false
	for _, child in ipairs(wf:GetChildren()) do
		if child:IsA("Folder") or child:IsA("Model") then
			hasRouteFolders = true
			break
		end
	end

	if hasRouteFolders then
		return -- маршруты уже разложены картоделом, ничего не трогаем
	end

	local flat = sortedPoints(wf)
	if #flat >= 2 then
		local route1 = Instance.new("Folder")
		route1.Name = "Route1"
		route1.Parent = wf
		for _, p in ipairs(flat) do
			p.Parent = route1
		end

		-- Перпендикуляр к общему направлению маршрута
		local dir = flat[#flat].Position - flat[1].Position
		local perp = dir.Magnitude > 0.1
			and dir.Unit:Cross(Vector3.new(0, 1, 0))
			or Vector3.new(1, 0, 0)

		local route2 = Instance.new("Folder")
		route2.Name = "Route2"
		route2.Parent = wf
		for i, p in ipairs(flat) do
			local t = (i - 1) / (#flat - 1)
			local bulge = ROUTE2_BULGE * math.sin(t * math.pi)
			local clone = p:Clone()
			clone.Position = p.Position + perp * bulge
			clone.Parent = route2
		end
		print("[TestMap] Создано 2 маршрута: Route1 (" .. #flat .. " точек) и Route2 (дуга вбок)")
	end

	-- Здания НЕ строим: папку workspace.Buildings наполняет картодел —
	-- любой Part в ней блокирует обзор башен (TowerClass:hasLineOfSight)
end

return TestMap
