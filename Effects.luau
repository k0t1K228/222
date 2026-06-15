-- ============================================
-- ЭКОНОМИКА (серверный модуль)
-- leaderstats.Money: старт, награды, траты.
-- Все операции с деньгами — ТОЛЬКО через этот модуль.
--
-- СОХРАНЕНИЕ: деньги игрока хранятся в DataStore между сессиями
-- (загрузка при входе, запись при выходе и при закрытии сервера).
-- Рестарт раунда деньги НЕ сбрасывает — это кошелёк игрока.
-- ⚠️ Чтобы работало в Studio: Game Settings → Security →
--    Enable Studio Access to API Services. Без этого pcall просто
--    промолчит и все начнут со стартовой суммы.
-- ============================================

local Players          = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local Economy = {}

Economy.START_MONEY = 400
Economy.KILL_REWARD = 25
Economy.BOSS_REWARD = 100 -- награда каждому за убитого босса

-- pcall: в Studio без доступа к API GetDataStore кидает ошибку
local moneyStore
pcall(function()
	moneyStore = DataStoreService:GetDataStore("PlayerMoney_v1")
end)

-- [player] = true только после УСПЕШНОЙ загрузки сейва. Пока флага нет
-- (загрузка не завершилась или упала), сохранять НЕЛЬЗЯ — иначе при
-- быстром выходе/ошибке API мы затрём реальный баланс стартовыми 400.
local loaded = {}

local function storeKey(player)
	return "p" .. player.UserId
end

local function savePlayer(player)
	if not moneyStore then return end
	if not loaded[player] then return end -- сейв ещё не загружен — не затираем
	local money = Economy.getMoney(player)
	if not money then return end
	local value = money.Value
	pcall(function()
		moneyStore:SetAsync(storeKey(player), value)
	end)
end

local function setupPlayer(player)
	if player:FindFirstChild("leaderstats") then return end

	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	stats.Parent = player

	local money = Instance.new("IntValue")
	money.Name = "Money"
	money.Value = Economy.START_MONEY
	money.Parent = stats

	-- Загрузка сохранения (асинхронно, чтобы не задерживать вход)
	task.spawn(function()
		if not moneyStore then return end
		local ok, saved = pcall(function()
			return moneyStore:GetAsync(storeKey(player))
		end)
		if ok then
			-- saved == number → вернувшийся игрок; nil → новичок (оставляем 400).
			-- В обоих случаях загрузка прошла — сохранять теперь можно.
			if type(saved) == "number" then
				money.Value = saved
			end
			loaded[player] = true
		else
			warn("Economy: не удалось загрузить сейв " .. player.Name
				.. " — сохранение отключено до перезахода (чтобы не затереть баланс)")
		end
	end)
end

function Economy.init()
	Players.PlayerAdded:Connect(setupPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		setupPlayer(p)
	end

	Players.PlayerRemoving:Connect(function(player)
		savePlayer(player)
		loaded[player] = nil
	end)
	-- Сервер выключается — успеваем сохранить всех
	game:BindToClose(function()
		for _, p in ipairs(Players:GetPlayers()) do
			savePlayer(p)
		end
	end)
	-- Автосейв раз в минуту: если сервер упадёт, потеряется максимум минута
	task.spawn(function()
		while true do
			task.wait(60)
			for _, p in ipairs(Players:GetPlayers()) do
				savePlayer(p)
			end
		end
	end)
end

function Economy.getMoney(player)
	local stats = player:FindFirstChild("leaderstats")
	return stats and stats:FindFirstChild("Money")
end

function Economy.canAfford(player, amount)
	local money = Economy.getMoney(player)
	return money ~= nil and money.Value >= amount
end

-- Списывает деньги; вернёт false, если не хватает
function Economy.spend(player, amount)
	local money = Economy.getMoney(player)
	if not money or money.Value < amount then
		return false
	end
	money.Value = money.Value - amount
	return true
end

function Economy.give(player, amount)
	local money = Economy.getMoney(player)
	if money then
		money.Value = money.Value + amount
	end
end

function Economy.rewardAll(amount)
	for _, p in ipairs(Players:GetPlayers()) do
		Economy.give(p, amount)
	end
end

return Economy
