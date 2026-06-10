# 📖 RobloxSkibidi TD — документация для разработчиков

Tower Defense на Roblox. Код живёт в файлах этого репозитория и синхронизируется
в Roblox Studio через **Rojo**. Карта (геометрия, модели) живёт в Studio.

> **Золотое правило:** код пишем ТОЛЬКО в VS Code. Скрипты в Studio не редактируем —
> при следующем подключении Rojo их перезапишет файловой версией.

---

## 1. Установка с нуля (новый разработчик)

### 1.1 Инструменты

1. Установи **Rokit** (менеджер тулчейна Roblox): https://github.com/rojo-rbx/rokit
   — скачай релиз, запусти `rokit self-install`.
2. В папке проекта выполни:
   ```powershell
   rokit install
   ```
   Он прочитает `aftman.toml` и поставит нужную версию Rojo (7.6.1).
3. Установи плагин Rojo в Roblox Studio:
   ```powershell
   rojo plugin install
   ```
4. В VS Code поставь расширения: **Rojo** и **Luau Language Server** (JohnnyMorganz).

### 1.2 Проверка, что всё работает

```powershell
cd <папка проекта>
rojo --version    # → Rojo 7.6.1
rojo build -o test.rbxlx   # → "Built project ..." без ошибок
```

---

## 2. Ежедневная работа

```powershell
cd <папка проекта>
rojo serve
```

→ Открой place в Roblox Studio → вкладка **Plugins** → иконка **Rojo** → **Connect**
(хост `localhost`, порт `34872`).

После подключения правки `.luau`-файлов мгновенно прилетают в Studio.
Тестируешь кнопкой **Play** в Studio.

**Типичные проблемы:**

| Симптом | Причина / решение |
|---|---|
| `Failed to find tool 'rojo' in any project manifest` | Пустой/битый `aftman.toml`. В нём должно быть `rojo = "rojo-rbx/rojo@7.6.1"` в секции `[tools]` |
| `error 10048 ... одно использование адреса сокета` | Порт 34872 уже занят другим `rojo serve`. Закрой старый терминал или `Get-Process rojo \| Stop-Process -Force` |
| Логика срабатывает дважды | В Studio остались СТАРЫЕ копии скриптов рядом с теми, что кладёт Rojo. Удали дубликаты из Studio |
| Странные сбои синхронизации | Проект лежит в OneDrive — облако может лочить файлы. Поставь синк OneDrive на паузу или перенеси проект |

---

## 3. Структура проекта

```
RobloxSkibidi/
├── default.project.json   ← маппинг файлов в дерево Roblox
├── aftman.toml            ← версии инструментов (rojo)
├── DOCUMENTATION.md       ← этот файл
├── TODO.md                ← список задач команды со статусами
└── src/
    ├── shared/Classes/    → ReplicatedStorage.Classes
    │   ├── BaseClass.luau       (главная база: HP, HP-бар, смерть)
    │   ├── EnemyClass.luau      (враг: движение, HP, взрыв-камикадзе)
    │   ├── TowerClass.luau      (башни: конфиги-скины, типы атак, оружие)
    │   └── PlacementZones.luau  (проверка зон размещения башен)
    ├── server/            → ServerScriptService.Server
    │   └── GameManager.server.luau  (волны, спавн, маршруты, активация башен)
    └── client/            → StarterPlayer.StarterPlayerScripts.Client
        └── AdminUI.client.luau      (панель: HP базы, волна, счёт врагов)
```

Маппинг **частичный**: Rojo управляет только этими папками. Вся геометрия карты
(башни, маршруты, модели) живёт в Studio и при синке не трогается.

---

## 4. Что должно лежать в Studio (обязательные объекты)

| Объект | Где | Зачем | Требования |
|---|---|---|---|
| `GeneralTower` | Workspace | Главная база | Модель; внутри желателен Part `TowerBase` (иначе возьмётся первая попавшаяся деталь) |
| `WaypointsFolder` | Workspace | Маршруты врагов | См. раздел 7 |
| `skibidi toilet` | ServerStorage (или Workspace — сервер сам перенесёт) | Шаблон врага | **Обязательно выставить PrimaryPart!** Без него pivot модели считается от центра габаритов и поведение менее предсказуемо |
| Модели башен (`Rust`, `RustFlamer`, ...) | Workspace (корень) | Боевые башни | Имя модели ИЛИ атрибут `TowerType` должны совпадать с конфигом из `TowerClass` |
| `PlacementZones` | Workspace | Зоны, где можно ставить башни | Папка с Part'ами. **Опционально** — если папки нет, ставить можно везде |

---

## 5. Башни

### 5.1 Как работает

`GameManager` сканирует корень Workspace (на старте и через `ChildAdded`).
Модель считается башней, если её **атрибут `TowerType`** или **имя** совпадает
с ключом из `TOWER_CONFIGS` в `src/shared/Classes/TowerClass.luau`.

Конфиг — это «скин»: одна и та же модель камеры с разными конфигами становится
винтовкой, огнемётом или лазером.

### 5.2 Готовые конфиги

| Ключ | Оружие | Тип атаки | Урон | Скорострельность | Радиус | Особенности |
|---|---|---|---|---|---|---|
| `Rust` | винтовка | single | 25 | 1/с | 20 | классика, одна цель |
| `RustFlamer` | огнемёт | multi | 8 | 2/с | 14 | до 4 целей сразу |
| `RustLaser` | лазер | ramp | 6 | 2/с | 25 | урон растёт +50%/сек на одной цели, максимум x5; непрерывный луч |
| `RustRocket` | ракеты | single | 40 | 0.4/с | 30 | летящий снаряд, взрыв по площади (радиус 8) |
| `RustMelee` | ближний бой | multi | 18 | 1.2/с | 8 | бьёт всех вокруг себя |
| `RustSonic` | звуковая волна | multi | 10 | 0.7/с | 16 | волна по всем в радиусе |

### 5.3 Поля конфига (справочник)

```lua
MyTower = {
    damage     = 25,        -- урон за выстрел
    fireRate   = 1,         -- выстрелов в секунду
    range      = 20,        -- радиус атаки (studs)
    attackType = "single",  -- "single" | "multi" | "ramp"
    weapon     = "rifle",   -- "rifle"|"flamethrower"|"laser"|"rocket"|"melee"|"sonic"
    beamColor  = Color3.fromRGB(255, 100, 0), -- цвет эффектов

    -- необязательные (есть значения по умолчанию):
    maxTargets        = 1,  -- для multi: сколько целей одновременно
    splashRadius      = 0,  -- для rocket: радиус взрыва
    rampPerSecond     = 0,  -- для ramp: прирост урона за секунду (0.5 = +50%)
    maxRampMultiplier = 1,  -- для ramp: потолок множителя
    scale             = 1,  -- размер башни: 0.5 маленькая / 1 средняя / 2 большая
}
```

### 5.4 Как добавить новую башню/скин — пошагово

1. Открой `src/shared/Classes/TowerClass.luau`.
2. Добавь новый ключ в `TOWER_CONFIGS` (см. справочник выше).
3. В Studio: возьми модель башни, в **Properties → Attributes** добавь
   атрибут `TowerType` (string) = твой ключ. Либо просто назови модель этим ключом.
4. Поставь модель в корень Workspace (и внутрь зоны, если есть `PlacementZones`).
5. Запусти Play — в Output будет `Башня активирована: <ключ>`.

⚠️ Визуал оружия сейчас — placeholder из неоновых Part'ов. Реальные модели
и партиклы — задача 4 (Чурюмов). Точка крепления эффектов — `PrimaryPart` башни.

---

## 6. Враги

- HP: 100 (поле `maxHP` в `EnemyClass.new`).
- Движение: плавное через `Heartbeat`, скорость и прочее — таблица `CONFIG`
  вверху `EnemyClass.luau` (speed, rotateSpeed, waypointReach, baseReach, spread).
- У каждого врага случайный разброс ±4 studs от маршрута, чтобы толпа не шла строем.
- **Камикадзе:** дойдя до базы, враг наносит ОДИН удар, равный его **текущим** HP,
  взрывается и умирает. Подбитый враг бьёт слабее ⇒ дамажить врагов по пути выгодно,
  даже если не успеваешь добить.
- Шаблон клонируется из `ServerStorage["skibidi toilet"]`.

⚠️ **PrimaryPart у шаблона обязателен** — модель двигается через pivot.

---

## 7. Маршруты и события карты

### 7.1 Формат WaypointsFolder

Два варианта:

```
WaypointsFolder/            WaypointsFolder/
├── 1   (Part)              ├── Route1/  (Folder)
├── 2   (Part)              │   ├── 1, 2, 3...  (Part'ы)
└── 3   (Part)              ├── Route2/
                            │   └── 1, 2, 3...
один маршрут "Main"         └── Route3/ ...
                            каждый враг выбирает СЛУЧАЙНЫЙ включённый маршрут
```

- Точки сортируются по числу в имени (`1`, `2`, `Point3` — главное чтобы была цифра).
- Сервер сам делает точки невидимыми и некликабельными.

### 7.2 Включение/выключение маршрутов

На папке маршрута атрибут **`Enabled`** (bool). Нет атрибута = включён.
`Enabled = false` — враги этот маршрут не выбирают.

### 7.3 События карты между волнами

В `GameManager.server.luau`, таблица `WAVES`:

```lua
{count = 8, spawnDelay = 1, pauseAfter = 10,
 mapEvent = {open = {"Route2"}, close = {"Route1"}}},
```

После окончания этой волны `Route1` закроется, `Route2` откроется, и всем клиентам
прилетит `ReplicatedStorage.MapChanged` (RemoteEvent) с этим событием —
**это точка подключения кат-сцен** (задача 2.1): клиентский скрипт слушает
`MapChanged.OnClientEvent` и показывает камеру/анимацию.

### 7.4 Настройка волн

```lua
local WAVES = {
    {count = 3, spawnDelay = 2, pauseAfter = 5},
    -- count      — сколько врагов
    -- spawnDelay — пауза между спавнами (сек)
    -- pauseAfter — пауза после волны (сек)
    -- mapEvent   — опционально, см. выше
}
```

---

## 8. Зоны размещения башен

1. Создай в Workspace папку **`PlacementZones`**.
2. Накидай в неё плоских Part'ов поверх площадок, где башни ставить МОЖНО
   (можно сделать прозрачными).
3. Башня вне всех зон **не активируется** (в Output будет warning).
4. Нет папки — ограничений нет.

Проверка точки: `PlacementZones.isAllowed(position)` из
`ReplicatedStorage.Classes.PlacementZones` — модуль общий, его же будет
использовать клиентский UI расстановки (подсветка можно/нельзя).

---

## 9. GameData (сервер → клиент)

`GameManager` создаёт в `ReplicatedStorage` папку `GameData`:

| Value | Тип | Что хранит |
|---|---|---|
| `BaseHP` | NumberValue | текущее HP базы |
| `MaxBaseHP` | NumberValue | максимум HP |
| `CurrentWave` | NumberValue | номер текущей волны |
| `MaxWaves` | NumberValue | всего волн |
| `EnemyCount` | NumberValue | живых врагов сейчас |
| `GameOver` | BoolValue | база уничтожена |

`AdminUI.client.luau` подписан на эти значения. Новые элементы UI делаем так же:
сервер пишет в Value, клиент слушает `.Changed`.

---

## 10. Проверка кода перед коммитом

```powershell
# структура собирается?
rojo build -o test.rbxlx

# типы и синтаксис (luau-lsp должен быть установлен):
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --definitions=<путь к globalTypes.d.luau> --sourcemap=sourcemap.json src
```

Определения Roblox API: https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.RobloxScriptSecurity.d.luau

> Если `rokit add` падает с GitHub 403 — это лимит API. Качай бинари напрямую
> со страницы релизов github.com.

---

## 11. Архитектурные соглашения

- **Источник правды — файлы.** Скрипты в Studio не редактируем.
- Классы — таблицы с `__index`-метатаблицей, конструктор `Class.new(...)`.
- Связь объектов — колбэки: `enemy.onDied`, `base.onDestroyed`.
- Сервер — вся игровая логика; клиент — только UI и (в будущем) кат-сцены.
  Никакого урона/денег на клиенте — это база анти-эксплойта (задача 5).
- Баланс (урон, HP, скорости) — только в конфиг-таблицах вверху файлов
  (`TOWER_CONFIGS`, `CONFIG`, `WAVES`), не в логике.

Список задач и текущие статусы — в [TODO.md](TODO.md).
