-- ============================================
-- ЛОББИ (отдельный place в том же experience)
-- Игроки жмут «ГОТОВ» в UI; когда готовы ВСЕ (и их >= MIN_PLAYERS),
-- идёт отсчёт и вся компания телепортируется в игровой place.
--
-- НАСТРОЙКА (см. DOCUMENTATION §12):
--   1. В Roblox Creator Hub у experience создай второй place «Lobby».
--   2. Открой его в Studio и подключи Rojo к ЭТОМУ проекту:
--      rojo serve lobby.project.json
--   3. Впиши ниже GAME_PLACE_ID — это PlaceId ОСНОВНОГО (игрового)
--      плейса (виден в Creator Hub или в Studio: Game Settings → Basic Info).
--
-- ⚠️ TeleportService НЕ работает в Studio — проверяется только
--    в опубликованной игре. В Studio выводим warn и никого не телепортируем.
-- ============================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService   = game:GetService("TeleportService")
local RunService        = game:GetService("RunService")

local GAME_PLACE_ID = 0  -- ← ВПИШИ PlaceId игрового плейса!
local MIN_PLAYERS   = 1  -- минимум готовых для старта
local COUNTDOWN     = 5  -- сек отсчёта перед телепортом

-- ============================================
-- ДАННЫЕ ДЛЯ UI (клиент читает эти Value)
-- ============================================
local lobbyData = Instance.new("Folder")
lobbyData.Name = "LobbyData"
lobbyData.Parent = ReplicatedStorage

local readyCountVal = Instance.new("NumberValue")
readyCountVal.Name = "ReadyCount"
readyCountVal.Parent = lobbyData

local totalCountVal = Instance.new("NumberValue")
totalCountVal.Name = "TotalCount"
totalCountVal.Parent = lobbyData

local countdownVal = Instance.new("NumberValue")
countdownVal.Name = "Countdown" -- 0 = отсчёта нет
countdownVal.Parent = lobbyData

local toggleReadyRE = Instance.new("RemoteEvent")
toggleReadyRE.Name = "ToggleReady"
toggleReadyRE.Parent = ReplicatedStorage

-- ============================================
-- ГОТОВНОСТЬ
-- ============================================
local readyPlayers = {} -- [player] = true

local function refreshCounts()
	local ready = 0
	for player in pairs(readyPlayers) do
		if player.Parent then
			ready = ready + 1
		else
			readyPlayers[player] = nil -- вышел — забываем
		end
	end
	readyCountVal.Value = ready
	totalCountVal.Value = #Players:GetPlayers()
end

toggleReadyRE.OnServerEvent:Connect(function(player)
	readyPlayers[player] = not readyPlayers[player] or nil
	player:SetAttribute("LobbyReady", readyPlayers[player] == true)
	refreshCounts()
end)

Players.PlayerAdded:Connect(refreshCounts)
Players.PlayerRemoving:Connect(function(player)
	readyPlayers[player] = nil
	refreshCounts()
end)

-- ============================================
-- ОТСЧЁТ И ТЕЛЕПОРТ
-- ============================================
local function everyoneReady()
	local total = #Players:GetPlayers()
	return total >= MIN_PLAYERS and readyCountVal.Value >= total
end

local function teleportAll()
	local players = Players:GetPlayers()
	if GAME_PLACE_ID == 0 then
		warn("ЛОББИ: GAME_PLACE_ID не задан — впиши PlaceId игрового плейса в LobbyMain!")
		return
	end
	if RunService:IsStudio() then
		warn("ЛОББИ: TeleportService не работает в Studio — опубликуй игру для проверки")
		return
	end

	local ok, err = pcall(function()
		TeleportService:TeleportAsync(GAME_PLACE_ID, players)
	end)
	if not ok then
		warn("ЛОББИ: телепорт не удался: " .. tostring(err))
	end
end

task.spawn(function()
	while true do
		task.wait(0.5)
		refreshCounts()

		if everyoneReady() then
			-- Отсчёт; прерывается, если кто-то передумал или вышел
			local aborted = false
			for t = COUNTDOWN, 1, -1 do
				countdownVal.Value = t
				task.wait(1)
				if not everyoneReady() then
					aborted = true
					break
				end
			end
			countdownVal.Value = 0
			if not aborted then
				teleportAll()
				-- после телепорта сбрасываем готовность оставшихся
				table.clear(readyPlayers)
				refreshCounts()
			end
		end
	end
end)
