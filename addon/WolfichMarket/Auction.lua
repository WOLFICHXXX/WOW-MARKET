-- WolfichMarket: аукцион — снимок по кнопке и по таймеру, панель: избранное, мой крафт, план
local _, ns = ...
local L = ns.L
local safe, UI = ns.safe, ns.UI
local M = ns.MEDIA
local COOLDOWN = 15 * 60

-- ---------- полный снимок аукциона ----------
local busy, processing, wanted = false, false, false
local panel
local tabs, pages = nil, {}
-- вкладки панели у аукциониста
local TAB_PLAN = 3 -- 1 избранное, 2 мой крафт, 3 план

local function setStatus() ns.Fire("SCAN_STATE") end

-- Аукцион принимает запросы по одному: если послать новый, пока не пришёл ответ на прошлый (свой или окна игры),
-- ответ теряется и окно игры зависает на «Поиск...». Поэтому все запросы аддона - только когда аукцион свободен.
function ns.AHReady()
  local f = C_AuctionHouse and C_AuctionHouse.IsThrottledMessageSystemReady
  if not f then return true end
  return safe(f) ~= false
end
-- «аукцион занят» при выставлении: серия начинается с первого отказа и сбрасывается, когда аукцион освободился
-- или окно открыли заново. После полного снимка сервер иногда долго держит флаг «занят», хотя лоты принимает,
-- поэтому через 3 с отказов аддон всё равно пробует выставить (нажатие игрока это разрешает).
local busyStreak
function ns.PostGate()
  if ns.AHReady() then busyStreak = nil return "ready" end
  local now = GetTime()
  if not busyStreak or now - busyStreak.last > 15 then busyStreak = { first = now, last = now } end
  busyStreak.last = now
  if now - busyStreak.first < 3 then return "wait" end
  return "force"
end
ns.On("AUCTION_HOUSE_SHOW", function() busyStreak = nil end)
ns.On("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", function() busyStreak = nil end)
-- снимок всего аукциона закончился недавно - сервер может пару минут отвечать медленно
function ns.AfterScan() return ns.lastScanEnd and (GetTime() - ns.lastScanEnd) < 180 end
-- товар (commodity) или обычный предмет. nil - игра ещё не знает (данные предмета не загружены):
-- выставлять в этот момент нельзя - лот уходит не тем способом и аукцион зависает.
function ns.CommodityStatus(loc, id)
  if not (loc and C_AuctionHouse and C_AuctionHouse.GetItemCommodityStatus and Enum and Enum.ItemCommodityStatus) then return false end
  local st = safe(C_AuctionHouse.GetItemCommodityStatus, loc)
  if st == Enum.ItemCommodityStatus.Commodity then return true end
  if st == Enum.ItemCommodityStatus.Item then return false end
  if id and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
  return nil
end
-- окно «Продать» самой игры с положенным предметом: оно само шлёт запросы - выставлять параллельно нельзя
function ns.BlizzSellBusy()
  local A = AuctionHouseFrame
  if not A or not A.IsShown or not A:IsShown() then return false end
  for _, fr in ipairs({ A.CommoditiesSellFrame, A.ItemSellFrame }) do
    if type(fr) == "table" and fr.IsShown and fr:IsShown() and fr.GetItem and safe(fr.GetItem, fr) then return true end
  end
  return false
end

-- ---------- какой это аукцион: фракционный (основной) или общий (межфракционный) ----------
-- Определяется по зоне: Остров Зефрис, Тернистая долина, Танарис - общий; остальное - фракционный.
-- Если где-то не угадали - кнопками на панели (запоминается для этого аукциониста).
-- Цены общего аукциона хранятся отдельно, не заменяют основные и между игроками не рассылаются.
-- Аукцион в Лесоречье аддон не учитывает вовсе (его цены не записываются).
local ZONES = {
  ["Остров Зефрис"] = "neutral", ["Тернистая долина"] = "neutral", ["Северная Тернистая долина"] = "neutral",
  ["Мыс Тернистой долины"] = "neutral", ["Танарис"] = "neutral",
  ["Stranglethorn Vale"] = "neutral", ["Northern Stranglethorn"] = "neutral", ["The Cape of Stranglethorn"] = "neutral", ["Tanaris"] = "neutral",
  ["Лесоречье"] = "off", ["Riverglades"] = "off",
}
ns.AH_KINDS = { "main", "neutral" }
local KIND_LAST = { main = "ahLastReq", neutral = "ntLastReq", off = "offLastReq" }
local function npcId()
  local guid = UnitGUID and UnitGUID("npc")
  return guid and tonumber(guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)"))
end
function ns.ZoneKind()
  local names = { GetRealZoneText and GetRealZoneText(), GetZoneText and GetZoneText(), GetSubZoneText and GetSubZoneText() }
  local m = C_Map and C_Map.GetBestMapForUnit and safe(C_Map.GetBestMapForUnit, "player")
  local info = m and C_Map.GetMapInfo and safe(C_Map.GetMapInfo, m)
  -- зона и её «родители» на карте (аукцион может стоять в подзоне)
  local guard = 0
  while info and guard < 6 do names[#names + 1] = info.name; info = info.parentMapID and info.parentMapID > 0 and safe(C_Map.GetMapInfo, info.parentMapID) or nil; guard = guard + 1 end
  for _, n in pairs(names) do if n and ZONES[n] then return ZONES[n] end end
end
local function detectKind()
  local id = npcId()
  ns.ahNpc = id
  local z = ns.ZoneKind()
  if z then return z end
  ns.DB.ahNpcKind = ns.DB.ahNpcKind or {}
  return (id and ns.DB.ahNpcKind[id]) or "main"
end
local function applyKind(k)
  ns.ahKind = k or "main"
  ns.ahIsBM = ns.ahKind ~= "main" -- не основной аукцион: цены не попадают в основные и не рассылаются
end
function ns.SetAHKind(k)
  applyKind(k)
  if ns.ahNpc then ns.DB.ahNpcKind = ns.DB.ahNpcKind or {}; ns.DB.ahNpcKind[ns.ahNpc] = ns.ahKind end
  ns.say(ns.ahKind == "neutral" and L"этот аукцион - общий (межфракционный): его цены хранятся отдельно и не заменяют цены основного аукциона."
    or L"этот аукцион - фракционный (основной).")
  ns.Fire("SCAN_STATE"); ns.Fire("AH_STATE"); ns.Fire("PRICES")
end
local function cdKey() return KIND_LAST[ns.ahKind or "main"] or "ahLastReq" end
-- снимок общего аукциона
function ns.AltData(kind, rk)
  if kind ~= "neutral" then return nil, {} end
  ns.DB.ntah = ns.DB.ntah or {}
  return ns.DB.ntah[rk or ns.priceRealm or ns.realmKey or ""], ns.DB.ntah
end
function ns.AltName(kind) return kind == "neutral" and L"Общий аукцион" or kind == "off" and L"Лесоречье (не учитывается)" or L"Фракционный аукцион" end
ns.ALT_COLOR = { neutral = "|cff66d9cc", main = "|cffffd100", off = "|cff888888" }

local function finishScan()
  if processing then return end
  local n = safe(C_AuctionHouse.GetNumReplicateItems) or 0
  if n == 0 then busy = false; ns.say(L"аукцион ответил пустым списком - попробуйте позже."); setStatus() return end
  processing = true
  local items = {}
  local i = 0
  local function step()
    local last = math.min(i + 1000, n - 1)
    for k = i, last do
      local name, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = safe(C_AuctionHouse.GetReplicateItemInfo, k)
      if itemID then
        count = math.max(count or 1, 1)
        local rec = items[itemID]
        if not rec then rec = { 0, 0, 0 }; items[itemID] = rec end -- мин. цена за шт, количество, лотов
        if buyout and buyout > 0 then local u = math.floor(buyout / count + 0.5); if rec[1] == 0 or u < rec[1] then rec[1] = u end end
        rec[2] = rec[2] + count
        rec[3] = rec[3] + 1
        if name and name ~= "" and not ns.DB.names[itemID] then ns.DB.names[itemID] = ns.clean(name) end
      end
    end
    i = last + 1
    ns.progress = math.floor(i / n * 100)
    setStatus()
    if i < n then ns.After(0, step) return end
    if ns.ahKind == "off" then
      busy, processing, ns.progress = false, false, nil
      ns.say(L"аукцион в Лесоречье аддон не учитывает - снимок не сохранён.")
      setStatus()
      return
    end
    if ns.ahIsBM then
      -- снимок общего аукциона - отдельно: без истории, сигналов и общего рынка (личный)
      local bm = {}
      for id, r in pairs(items) do if r[1] > 0 then bm[id] = { p = r[1], bids = 0, q = r[2], lots = r[3] } end end
      local _, tbl = ns.AltData(ns.ahKind)
      tbl[ns.realmKey] = { t = time(), lots = n, items = bm }
      busy, processing, ns.progress = false, false, nil
      local cnt = 0; for _ in pairs(bm) do cnt = cnt + 1 end
      ns.say(string.format(L"%sснимок: %s|r - %d лотов, %d предметов. Цены основного аукциона не тронуты.", ns.ALT_COLOR[ns.ahKind], ns.AltName(ns.ahKind), n, cnt))
      setStatus(); ns.Fire("ALTAH")
      return
    end
    local prev = ns.CurrentScan()
    local scan = { t = time(), lots = n, char = ns.charKey, realm = ns.realmKey, items = items }
    ns.DB.ahScans[ns.realmKey] = scan
    -- история: отмеченные и всё, что связано с рецептами персонажа
    local want = ns.RecipeItems()
    for id in pairs(ns.DB.marked) do want[id] = true end
    for id in pairs(want) do local r = items[id]; if r and r[1] > 0 then ns.AddHistory(id, r[1], r[2], scan.t) end end
    busy, processing, ns.progress = false, false, nil
    ns.lastScanEnd = GetTime()
    local cnt = 0; for _ in pairs(items) do cnt = cnt + 1 end
    ns.say(string.format(L"|cff78d98aснимок аукциона готов|r: %d лотов, %d предметов.", n, cnt))
    setStatus()
    ns.Fire("PRICES")
    ns.Fire("SCAN_DONE", scan, prev)
  end
  step()
end

local scanPrevReq, scanKey -- время прошлого запроса - вернуть, если скан прервали закрытием аукциона
function ns.StartScan(auto)
  if not (C_AuctionHouse and C_AuctionHouse.ReplicateItems) then ns.say(L"в этой версии игры нет полного скана аукциона.") return end
  if not ns.ahOpen then wanted = true; ns.say(L"откройте окно аукциона - скан начнётся сам.") return end
  if busy then return end
  local left = (ns.DB[cdKey()] or 0) + COOLDOWN - time()
  if left > 0 then if not auto then ns.say(string.format(L"следующий снимок можно через %d:%02d.", math.floor(left / 60), left % 60)) end return end
  busy, wanted = true, false
  scanPrevReq, scanKey = ns.DB[cdKey()], cdKey()
  ns.DB[cdKey()] = time()
  setStatus()
  local ok = pcall(C_AuctionHouse.ReplicateItems)
  if not ok then busy = false; setStatus(); ns.say(L"сервер отказал - подождите 15 минут.") return end
  -- сервер присылает аукцион частями: обрабатываем, только когда число лотов перестало расти
  local lastN, stable = -1, 0
  local function poll()
    if not busy or processing then return end
    local n = safe(C_AuctionHouse.GetNumReplicateItems) or 0
    if n > 0 and n == lastN then stable = stable + 1 else stable = 0 end
    lastN = n
    if stable >= 2 then finishScan() else ns.After(2, poll) end
  end
  ns.After(3, poll)
  ns.After(180, function()
    if not busy or processing then return end
    if (safe(C_AuctionHouse.GetNumReplicateItems) or 0) > 0 then finishScan() return end -- что пришло - то и обработаем
    busy = false; setStatus(); ns.say(L"сервер не прислал аукцион - попробуйте позже.")
  end)
end
function ns.ScanBusy() return busy end

local replPending = false
ns.On("REPLICATE_ITEM_LIST_UPDATE", function()
  -- сигнал «список готов» может прийти на каждую часть - сам дождётся, пока число лотов не перестанет расти (poll в StartScan)
  if busy and not replPending then replPending = true; ns.After(1, function() replPending = false end) end
end)

-- автоскан: раз в N минут, пока открыт аукционист
local autoTicker
local function autoTick()
  local S = ns.DB.settings
  if not ns.ahOpen or not S.autoScan or busy then return end
  local every = math.max(15, S.autoScanMin or 15) * 60
  if time() - (ns.DB[cdKey()] or 0) >= every then ns.StartScan(true) end
end

ns.On("AUCTION_HOUSE_SHOW", function()
  ns.ahOpen = true
  applyKind(detectKind())
  ns.Fire("AH_STATE"); if ns.ahIsBM then ns.Fire("PRICES") end
  if panel == nil then ns.BuildAHPanel() elseif panel then panel:Show() end -- крестик скрывает панель только до следующего открытия
  if ns.PlaceAH then ns.After(0, ns.PlaceAH) end
  if wanted then ns.After(1, function() ns.StartScan() end) else ns.After(2, autoTick) end
  if not autoTicker and C_Timer and C_Timer.NewTicker then autoTicker = C_Timer.NewTicker(30, autoTick) end
end)
-- аукцион закрыли во время скана: что успело прийти - обрабатываем; не пришло ничего - скан отменяется,
-- 15-минутное ожидание не засчитывается, и при следующем открытии аукциона скан начнётся сам
local function abortScanOnClose()
  if not busy or processing then return end
  if (safe(C_AuctionHouse.GetNumReplicateItems) or 0) > 0 then finishScan() return end
  busy, ns.progress = false, nil
  if scanKey then ns.DB[scanKey] = scanPrevReq end
  wanted = true
  ns.say(L"скан прерван: окно аукциона закрыто. Откройте аукцион снова - скан начнётся сам.")
  setStatus()
end
ns._abortScanOnClose = abortScanOnClose -- для автотестов
ns.On("AUCTION_HOUSE_CLOSED", function()
  abortScanOnClose()
  ns.ahOpen = false
  local wasBM = ns.ahIsBM
  applyKind("main")
  ns.Fire("AH_STATE"); if wasBM then ns.Fire("PRICES") end
  if autoTicker then autoTicker:Cancel(); autoTicker = nil end
end)

-- ---------- «Обновить цены»: свежие цены поиском, без 15-минутного ожидания ----------
-- что обновлять - зависит от открытой вкладки: выделенные предметы, весь рецепт, план...
local quick, updateQuick
local function addAll(ids, seen, id) if id and not seen[id] then seen[id] = true; ids[#ids + 1] = id end end
local function recipeIDs(rec, ids, seen)
  addAll(ids, seen, rec.out)
  for _, r in ipairs(rec.reag or {}) do addAll(ids, seen, r[1]) end
end
function ns.RecipePriceIDs(rec) local ids, seen = {}, {}; if rec then recipeIDs(rec, ids, seen) end; return ids end
-- всё «моё»: предметы в сумках (кроме персональных), результаты и материалы рецептов моих профессий, отмеченные и план
local function myIDs()
  local ids, seen = {}, {}
  local C = C_Container
  for b = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
    for sl = 1, (C and C.GetContainerNumSlots and safe(C.GetContainerNumSlots, b)) or 0 do
      local info = C.GetContainerItemInfo and safe(C.GetContainerItemInfo, b, sl)
      if info and info.itemID and not info.isBound then addAll(ids, seen, info.itemID) end
    end
  end
  local c = ns.DB.chars[ns.charKey]
  for _, p in pairs(c and c.profs or {}) do
    for _, rec in ipairs(p.recipes or {}) do
      if ns.DB.settings.showUnlearned or ns.IsLearned(rec) then recipeIDs(rec, ids, seen) end
    end
  end
  for id in pairs(ns.DB.marked) do addAll(ids, seen, id) end
  for _, pl in ipairs(ns.Plans and ns.Plans() or {}) do recipeIDs(pl, ids, seen) end
  return ids
end
function ns.QuickRefresh(ids)
  if not ns.ahOpen then ns.say(L"откройте окно аукциона.") return end
  if quick then
    if ids then return end -- уже идёт обновление
    quick = nil; if updateQuick then updateQuick() end; ns.Fire("PRICES") return -- повторное нажатие кнопки - стоп
  end
  local mine = ids == nil
  ids = ids or myIDs()
  if #ids == 0 then ns.say(L"нечего обновлять: откройте окна своих профессий или положите предметы в сумки.") return end
  quick = { ids = ids, i = 0, mine = mine, since = GetTime() }
  local function step()
    if not quick or quick.stepping then return end
    -- Аукцион ещё не ответил на прошлый запрос - ждём сигнала «свободен» (AUCTION_HOUSE_THROTTLED_SYSTEM_READY).
    -- Новый запрос поверх неотвеченного теряет ответ и держит аукцион «занятым» дальше (и окно игры висит на «Поиск...»),
    -- поэтому без готовности не шлём ничего. Ждём не больше 60 с, потом останавливаемся.
    if not ns.AHReady() then
      if GetTime() - quick.since > 60 then
        quick = nil; if updateQuick then updateQuick() end
        ns.say(ns.AfterScan and ns.AfterScan() and L"|cffffb060Аукцион не отвечает: после снимка всего аукциона сервер ещё досылает данные. Подождите пару минут и нажмите «Обновить цены» снова.|r"
          or L"|cffffb060Аукцион не отвечает - обновление цен остановлено. Попробуйте через минуту.|r")
        return
      end
      local my = quick; my.tok = (my.tok or 0) + 1; my.stepping = my.tok; local tok = my.tok
      ns.After(1, function() if quick == my and my.stepping == tok then my.stepping = nil; step() end end) -- запасной опрос, если сигнал не придёт
      return
    end
    quick.since = GetTime()
    quick.i = quick.i + 1
    local id = quick.ids[quick.i]
    if not id or not ns.ahOpen then
      quick = nil
      ns.After(1.5, function() ns.Fire("PRICES") end)
      if updateQuick then updateQuick() end
      return
    end
    local key = C_AuctionHouse.MakeItemKey and safe(C_AuctionHouse.MakeItemKey, id)
    if key then
      local sorts = {}
      if Enum and Enum.AuctionHouseSortOrder then sorts = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } } end
      pcall(C_AuctionHouse.SendSearchQuery, key, sorts, false)
    end
    if updateQuick then updateQuick() end
    -- следующий - когда аукцион ответит (сигнал готовности), но не чаще раза в 0.2 с
    local my = quick; my.tok = (my.tok or 0) + 1; my.stepping = my.tok; my.sent = GetTime(); local tok = my.tok
    ns.After(0.2, function() if quick == my and my.stepping == tok then my.stepping = nil; step() end end)
  end
  quick.step = step
  step()
end
function ns.QuickBusy() return quick ~= nil end
-- аукцион освободился - следующий запрос сразу (но не раньше 0.2 с после прошлого)
ns.On("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", function()
  if quick and quick.step and (not quick.sent or GetTime() - quick.sent >= 0.2) then quick.stepping = nil; quick.step() end
end)
-- профессию удалили/добавили, сняли отметку, поменяли план - пересобрать очередь «Обновить цены» на ходу
local function rebuildQuick()
  if not quick or not quick.mine then return end
  local done = {}
  for k = 1, quick.i do if quick.ids[k] then done[quick.ids[k]] = true end end
  local ids = {}
  for k = 1, quick.i do ids[#ids + 1] = quick.ids[k] end
  for _, id in ipairs(myIDs()) do if not done[id] then ids[#ids + 1] = id end end
  quick.ids = ids
  if updateQuick then updateQuick() end
end
ns.Listen("RECIPES", rebuildQuick)
ns.Listen("MARKS", rebuildQuick)
ns.Listen("PLAN", rebuildQuick)
function updateQuick()
  if not panel or not panel.quickBtn then return end
  if quick then panel.quickBtn:SetLabel(string.format(L"Стоп %d/%d", math.min(quick.i, #quick.ids), #quick.ids)); panel.quickBtn:Enable()
  else panel.quickBtn:SetLabel(L"Обновить цены"); panel.quickBtn:SetEnabled(ns.ahOpen == true) end
end

-- цены из обычных поисков на аукционе
ns.On("COMMODITY_SEARCH_RESULTS_UPDATED", function(itemID)
  local first = itemID and safe(C_AuctionHouse.GetCommoditySearchResultInfo, itemID, 1)
  if first and first.unitPrice then
    local total = 0
    for k = 1, (safe(C_AuctionHouse.GetNumCommoditySearchResults, itemID) or 0) do local r = safe(C_AuctionHouse.GetCommoditySearchResultInfo, itemID, k); if r then total = total + (r.quantity or 0) end end
    ns.SeenPrice(itemID, first.unitPrice, total)
    ns.Fire("PRICES")
  end
  ns.Fire("SEARCH_RESULTS", itemID, true)
end)
ns.On("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey)
  if not itemKey or not itemKey.itemID then return end
  local best
  for k = 1, (safe(C_AuctionHouse.GetNumItemSearchResults, itemKey) or 0) do
    local r = safe(C_AuctionHouse.GetItemSearchResultInfo, itemKey, k)
    if r and r.buyoutAmount and r.buyoutAmount > 0 then local u = r.buyoutAmount / math.max(1, r.quantity or 1); if not best or u < best then best = u end end
  end
  if best then ns.SeenPrice(itemKey.itemID, math.floor(best + 0.5)); ns.Fire("PRICES") end
  ns.Fire("SEARCH_RESULTS", itemKey.itemID, false, itemKey)
end)

-- ---------- панель у окна аукциона ----------

local function header()
  local S = ns.DB.settings
  -- «Сканировать» и «Обновить цены» - компактные (по центру своих строк)
  panel.scanBtn = UI.Button(panel, L"Сканировать", 120, 18, function() ns.StartScan() end, true)
  panel.scanBtn:SetPoint("TOPRIGHT", -42, -11)
  panel.quickBtn = UI.Button(panel, L"Обновить цены", 120, 18, function() ns.QuickRefresh() end, true)
  panel.quickBtn:SetPoint("TOPRIGHT", -14, -52)
  panel.quickBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(L"Свежие цены без 15-минутного ожидания: всё, что лежит в сумках, результаты и материалы рецептов ваших профессий, отмеченные и план. Предметы проверяются по очереди, примерно 2 в секунду; повторное нажатие - стоп.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  panel.quickBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  -- какой это аукцион: три кнопки (горит текущий); нажатие - исправить, запоминается для аукциониста
  panel.kindBtn = {}
  local KB = { { "main", L"Фракционный", 104 }, { "neutral", L"Общий", 72 } }
  local x = 14
  for _, k in ipairs(KB) do
    local b = UI.Button(panel, k[2], k[3], 18, function() ns.SetAHKind(k[1]) end)
    local bw = b:FitWidth(k[3], 160)
    b:SetPoint("TOPLEFT", x, -52); x = x + bw + 6
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      GameTooltip:AddLine(ns.AltName(k[1]), 1, 0.82, 0)
      GameTooltip:AddLine(L"Горит - этот аукцион такого вида. Определяется по зоне: Остров Зефрис, Тернистая долина, Танарис - общий; остальное - фракционный. Снимки общего аукциона личные: хранятся отдельно, не заменяют цены фракционного и не рассылаются. Нажмите, если аддон ошибся - запомнит для этого аукциониста.", 1, 1, 1, true)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    panel.kindBtn[k[1]] = b
  end
  panel.state = UI.Font(panel, 10, UI.DIM); panel.state:SetPoint("TOPLEFT", 14, -112); panel.state:SetPoint("RIGHT", -14, 0); panel.state:SetWordWrap(true); panel.state:SetMaxLines(2)
end

local function updateHeader()
  if not panel then return end
  updateQuick()
  local scan = ns.CurrentScan()
  for k, b in pairs(panel.kindBtn) do b:SetGold((ns.ahKind or "main") == k) end
  if ns.ahIsBM then
    local d = ns.AltData(ns.ahKind, ns.realmKey)
    scan = d and { t = d.t, lots = d.lots or 0 } or nil
  end
  local left = (ns.DB[cdKey()] or 0) + COOLDOWN - time()
  if busy then
    panel.scanBtn:SetLabel(ns.progress and (L"Обработка " .. ns.progress .. "%") or L"Сканирую..."); panel.scanBtn:Disable()
  elseif left > 0 then
    panel.scanBtn:SetLabel(string.format(L"Скан через %d:%02d", math.floor(left / 60), left % 60)); panel.scanBtn:Disable()
  else
    panel.scanBtn:SetLabel(L"Сканировать"); panel.scanBtn:Enable()
  end
  local S = ns.DB.settings
  panel.state:SetText((ns.ahIsBM and (ns.ALT_COLOR[ns.ahKind] .. ns.AltName(ns.ahKind) .. "|r  ") or "") .. (scan and (L"Снимок: " .. ns.ago(scan.t) .. " / " .. scan.lots .. L" лотов") or L"|cffff9966Снимка ещё нет - нажмите «Сканировать».|r")
    .. (S.autoScan and (L"  /  авто раз в " .. S.autoScanMin .. L" мин") or "")
    .. ((ns.NetInfo and ns.NetInfo()) and ("\n" .. L"цены игроков" .. ": " .. ns.ago((ns.NetInfo())) .. " |cff888888(" .. ((select(2, ns.NetInfo()) or ""):match("^[^-]+") or "") .. ")|r") or ""))
end

-- строка списка предметов: звезда, иконка, имя, цена, изменение, кнопки
local function itemRow(r, withBuy)
  r.star = UI.Icon(r, "star-off", 14, L"Избранное", function(self) local d = self:GetParent().data; if d then ns.ToggleMark(d.id) end end); r.star:SetPoint("LEFT", 2, 0)
  r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(18, 18); r.icon:SetPoint("LEFT", r.star, "RIGHT", 4, 0)
  r.bell = UI.Bell(r, 15, function(self) local d = self:GetParent().data; return d and d.id end); r.bell:SetPoint("RIGHT", -2, 0)
  r.search = UI.Icon(r, "search", 15, L"Найти в окне аукциона", function(self) local d = self:GetParent().data; if d then ns.SearchAH(d.id) end end); r.search:SetPoint("RIGHT", r.bell, "LEFT", -4, 0)
  r.chg = UI.Font(r, 10); r.chg:SetPoint("RIGHT", r.search, "LEFT", -6, 0); r.chg:SetWidth(52); r.chg:SetJustifyH("RIGHT")
  r.price = UI.Font(r, 11); r.price:SetPoint("RIGHT", r.chg, "LEFT", -4, 0); r.price:SetJustifyH("RIGHT")
  r.name = UI.Font(r, 11); r.name:SetPoint("LEFT", r.icon, "RIGHT", 5, 0); r.name:SetPoint("RIGHT", r.price, "LEFT", -6, 0)
  r:SetScript("OnEnter", function(self) if self.data then GameTooltip:SetOwner(self, "ANCHOR_LEFT"); pcall(GameTooltip.SetItemByID, GameTooltip, self.data.id); GameTooltip:Show() end end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  -- клик по строке списка с раскрытием - подробности и график
  r:SetScript("OnClick", function(self) local box = self.box; if self.data and box and box.detailN then box:Toggle(self.data) end end)
end
local function fillItemRow(r, d)
  local hdr = d.header ~= nil
  for _, w in ipairs({ r.star, r.icon, r.search, r.chg, r.bell }) do w:SetShown(not hdr) end
  if hdr then
    r.name:SetText("|cffe6b450" .. d.header .. "|r"); r.price:SetText(d.headerRight or "")
    return
  end
  r.star:SetIcon(ns.IsMarked(d.id) and "star-on" or "star-off")
  r.bell:Update(d.id)
  r.icon:SetTexture(ns.itemIcon(d.id))
  r.name:SetText(ns.itemLinkText(d.id) .. (d.extra or ""))
  local p = ns.AHPrice(d.id)
  r.price:SetText(p and ns.money(p, true) or L"|cff777777нет|r")
  local avg = ns.AvgPrice(d.id, 24)
  r.chg:SetText(p and avg and ns.pct((p - avg) / avg * 100) or "")
end
-- раскрытие строки: себестоимость, прибыль на Ф и Общ, график (вместо отдельной вкладки «График»)
local function withDetail(l, n) l:EnableDetail(n or 7, function(det) UI.ItemDetail(det, { leftW = 130, compact = true }) end, function(det, d) det:Set(d.id) end) end

-- вкладка: отмеченные
local function pageMarked(f)
  local l = UI.List(f, 22, itemRow, fillItemRow)
  l:SetAllPoints()
  withDetail(l)
  f.list = l
  ns.Listen("PLAN", function() if f:IsShown() then l:Refresh() end end)
  f.refresh = function()
    local d = {}
    for id in pairs(ns.DB.marked) do d[#d + 1] = { id = id } end
    table.sort(d, function(a, b) return ns.itemName(a.id) < ns.itemName(b.id) end)
    l:SetData(d)
    l.empty:SetText(L"Добавьте предметы в избранное |TInterface\\AddOns\\WolfichMarket\\media\\star-on:12:12|t -\nв главном окне, во вкладке «Мой крафт»\nили Alt+клик по предмету в сумке.")
  end
end

-- вкладка: прибыльный крафт
-- сколько порций рецепта уже в плане у текущего персонажа
local function planCount(rec)
  for _, p in ipairs(ns.Plans()) do if p.id == rec.id and p.ck == ns.charKey then return p.n end end
  return 0
end
local function pageCraft(f)
  local l = UI.List(f, 22, function(r)
    itemRow(r)
    -- «План»: +1 порция рецепта в план закупки (каждый клик - ещё одна)
    r.plan = UI.Button(r, L"План", 54, 18, function()
      local d = r.data
      if d then ns.AddPlan(d.pr.rec, ns.charKey, d.pr.prof, planCount(d.pr.rec) + 1) end
    end)
    r.plan:SetPoint("RIGHT", r.bell, "LEFT", -4, 0)
    r.plan:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:AddLine(L"Добавить в план закупки", 1, 0.82, 0)
      GameTooltip:AddLine(L"Каждый клик - ещё одна порция. Что докупить - во вкладке «План».", 1, 1, 1, true)
      GameTooltip:Show()
    end)
    r.plan:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r.search:ClearAllPoints(); r.search:SetPoint("RIGHT", r.plan, "LEFT", -4, 0)
  end, function(r, d)
    fillItemRow(r, { id = d.id })
    local n = planCount(d.pr.rec)
    r.plan:SetLabel(n > 0 and (L"План" .. " ×" .. n) or L"План"); r.plan:SetGold(n > 0)
    r.name:SetText(ns.itemLinkText(d.id) .. (ns.IsLearned(d.pr.rec) and "" or L" |cffff9966(не изучен)|r"))
    r.chg:SetText(d.pr.profit and ((d.pr.profit >= 0 and "|cff78d98a+" or "|cffff7a66") .. ns.money(d.pr.profit, true) .. "|r") or L"|cffaa8866нет цены|r")
    r.chg:SetWidth(80)
  end)
  local chk = UI.Check(f, L"включая неизученные рецепты", function() return ns.DB.settings.showUnlearned end, function(v)
    ns.DB.settings.showUnlearned = v; ns.Fire("RECIPES"); ns.DecorateRecipeRows()
  end)
  chk:SetPoint("TOPLEFT", -2, 2)
  l:SetPoint("TOPLEFT", 0, -22); l:SetPoint("BOTTOMRIGHT")
  withDetail(l)
  f.list = l
  f.refresh = function()
    chk:SetChecked(ns.DB.settings.showUnlearned)
    local d = {}
    for _, pr in ipairs(ns.AllRecipeProfits(nil, ns.DB.settings.showUnlearned)) do if pr.rec.out then d[#d + 1] = { id = pr.rec.out, pr = pr } end end
    table.sort(d, function(a, b) return (a.pr.profit or -1e12) > (b.pr.profit or -1e12) end)
    l:SetData(d)
    l.empty:SetText(L"Откройте окна своих профессий - здесь появятся рецепты с прибылью.")
  end
end

-- вкладок «Купить» и «Продать» больше нет: покупка и выставление - в окне аукциона игры (кнопка поиска у строк, ПКМ/клик в сумке)
function ns.OpenChart(id) if ns.ShowChartDialog then ns.ShowChartDialog(id) end end

-- «План»: рецепты, запланированные в главном окне, и всё, что для них нужно докупить
local function pagePlan(f)
  f.title = UI.Font(f, 13, UI.GOLD, "OVERLAY", "OUTLINE"); f.title:SetPoint("TOPLEFT", 2, -2); f.title:SetText(L"План закупки")
  f.clear = UI.Button(f, L"Очистить", 90, 20, function() ns.ClearPlans() end); f.clear:SetPoint("TOPRIGHT", 0, 0)
  -- обновить цены только для плана: результаты и материалы всех рецептов плана
  f.upd = UI.Button(f, L"Обновить цены плана", 150, 20, function()
    local ids, seen = {}, {}
    for _, pl in ipairs(ns.Plans()) do recipeIDs(pl, ids, seen) end
    ns.QuickRefresh(ids)
  end); f.upd:SetPoint("RIGHT", f.clear, "LEFT", -6, 0)
  f.recs = UI.List(f, 20, function(r)
    r.x = UI.Icon(r, "skin\\ai-x", 14, L"Убрать из плана", function(self) local d = self:GetParent().data; if d then ns.RemovePlan(d.i) end end); r.x:SetPoint("RIGHT", -2, 0)
    -- количество: [-] [поле] [+], поле можно вписать вручную
    local function setN(v) local d = r.data; if d then ns.SetPlanCount(d.i, v) end end
    r.plus = UI.Button(r, "+", 18, 18, function() local d = r.data; if d then setN(d.p.n + 1) end end); r.plus:SetPoint("RIGHT", r.x, "LEFT", -8, 0)
    r.n = CreateFrame("EditBox", nil, r, "InputBoxTemplate"); r.n:SetSize(30, 18); r.n:SetPoint("RIGHT", r.plus, "LEFT", -4, 0)
    r.n:SetAutoFocus(false); r.n:SetNumeric(true); r.n:SetMaxLetters(3); r.n:SetJustifyH("CENTER")
    if r.n.SetFont then UI.SetFont(r.n, UI.FONT, 11, "") end
    r.n:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    r.n:SetScript("OnEditFocusLost", function(self) setN(self:GetText()) end)
    r.minus = UI.Button(r, "-", 18, 18, function() local d = r.data; if d then setN(d.p.n - 1) end end); r.minus:SetPoint("RIGHT", r.n, "LEFT", -6, 0)
    r.profit = UI.Font(r, 11); r.profit:SetPoint("RIGHT", r.minus, "LEFT", -8, 0); r.profit:SetJustifyH("RIGHT")
    r.star = UI.Star(r, 14, function() local d = r.data; return d and d.p and d.p.out end); r.star:SetPoint("LEFT", 2, 0)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(16, 16); r.icon:SetPoint("LEFT", r.star, "RIGHT", 3, 0)
    r.name = UI.Font(r, 11); r.name:SetPoint("LEFT", r.icon, "RIGHT", 5, 0); r.name:SetPoint("RIGHT", r.profit, "LEFT", -6, 0)
  end, function(r, d)
    local pr = d.pr or {}
    r.profit:SetText(pr.profit and ((pr.profit >= 0 and "|cff78d98a+" or "|cffff7a66") .. ns.money(pr.profit, true) .. "|r") or L"|cffaa8866нет цены|r")
    r.icon:SetTexture(d.p.out and ns.itemIcon(d.p.out) or 134400); r.star:SetShown(d.p.out ~= nil); if d.p.out then r.star:Update(d.p.out) end
    local who = d.p.ck and d.p.ck ~= ns.charKey and (" |cffaaaaaa(" .. (d.p.ck:match("^(.-)%-") or d.p.ck) .. ")|r") or ""
    r.name:SetText(d.p.name .. who); if not r.n:HasFocus() then r.n:SetText(tostring(d.p.n)) end
  end)
  f.recs:SetPoint("TOPLEFT", 0, -24); f.recs:SetPoint("RIGHT"); f.recs:SetHeight(84)
  f.recs.empty:SetText(L"План пуст. В главном окне (/wm) выберите рецепт, задайте порции и нажмите «Запланировать».")
  -- «учитывать свои материалы»: вычитать то, что уже есть в сумках и банке
  f.useStock = UI.Check(f, L"учитывать свои материалы", function() return ns.DB.settings.planUseStock ~= false end, function(v) ns.DB.settings.planUseStock = v; f.refresh() end)
  f.useStock:SetPoint("TOPLEFT", 0, -112)
  local hdr = CreateFrame("Frame", nil, f); hdr:SetPoint("TOPLEFT", 0, -136); hdr:SetPoint("TOPRIGHT", 0, -136); hdr:SetHeight(14)
  local h1 = UI.Font(hdr, 10, UI.DIM); h1:SetPoint("LEFT", 24, 0); h1:SetText(L"Материал")
  local h2 = UI.Font(hdr, 10, UI.DIM); h2:SetPoint("RIGHT", hdr, "RIGHT", -70, 0); h2:SetText(L"Докупить")
  f.items = UI.List(f, 32, function(r)
    r.star = UI.Star(r, 14, function() local d = r.data; return d and d.id end); r.star:SetPoint("LEFT", 2, 0)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(22, 22); r.icon:SetPoint("LEFT", r.star, "RIGHT", 3, 0)
    -- «Купить»: нужное количество прямо отсюда (цена - у сервера, потом подтверждение внизу); лупа - найти в окне аукциона
    r.buyBtn = UI.Button(r, L"Купить", 62, 20, function(self) local d = self:GetParent().data; if d then f.startBuy(d.id, d.buy) end end); r.buyBtn:SetPoint("RIGHT", -2, 0)
    r.find = UI.Icon(r, "search", 15, L"Найти в окне аукциона", function(self) local d = self:GetParent().data; if d then ns.SearchAH(d.id) end end); r.find:SetPoint("RIGHT", r.buyBtn, "LEFT", -6, 0)
    r.buy = UI.Font(r, 11); r.buy:SetPoint("RIGHT", r.find, "LEFT", -6, 0); r.buy:SetWidth(96); r.buy:SetJustifyH("RIGHT")
    r.name = UI.Font(r, 11); r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 6, 2); r.name:SetPoint("RIGHT", r.buy, "LEFT", -4, 0)
    -- вторая строка: нужно, сколько в сумках и сколько в банке
    r.cnt = UI.Font(r, 10, UI.DIM); r.cnt:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 6, -2); r.cnt:SetPoint("RIGHT", r.buy, "LEFT", -4, 0)
    r:SetScript("OnEnter", function(self) if self.data then GameTooltip:SetOwner(self, "ANCHOR_LEFT"); pcall(GameTooltip.SetItemByID, GameTooltip, self.data.id); GameTooltip:Show() end end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end, function(r, d)
    r.icon:SetTexture(ns.itemIcon(d.id)); r.name:SetText(ns.itemLinkText(d.id)); r.star:Update(d.id)
    local col = (d.bags + d.bank) >= d.need and "|cff78d98a" or "|cffffb060"
    -- лёгкая пометка: где этот материал дешевле всего (торговец или один из трёх аукционов)
    local where = ""
    if d.buy > 0 and ns.BestBuy then
      local bp, bk = ns.BestBuy(d.id)
      local cur = ns.ahOpen and (ns.ahKind or "main")
      if bk then
        local tag = bk == "vendor" and ("|cffbbbbbb" .. L"торговец") or (ns.ALT_COLOR[bk] .. ns.KindShort(bk))
        where = "   |cff888888" .. L"дешевле:" .. "|r " .. tag .. "|r |cff888888" .. ns.money(bp, true) .. "|r" .. (bk == cur and (" |cff78d98a" .. L"(здесь)" .. "|r") or "")
      end
    end
    r.cnt:SetText(L"нужно" .. " " .. d.need .. "   " .. col .. L"сумки" .. " " .. d.bags .. " / " .. L"банк" .. " " .. d.bank .. "|r" .. where)
    if d.buy > 0 then
      r.buy:SetText(d.buy .. (d.unit and (" |cffaaaaaa" .. ns.money(d.unit * d.buy, true) .. "|r") or L" |cffaa8866нет цены|r"))
      r.buyBtn:Show(); r.find:Show(); r.buyBtn:SetEnabled(ns.ahOpen == true)
    else r.buy:SetText(L"|cff78d98aготово|r"); r.buyBtn:Hide(); r.find:Hide() end
  end)
  f.items:SetPoint("TOPLEFT", 0, -152); f.items:SetPoint("RIGHT"); f.items:SetPoint("BOTTOM", 0, 44)
  withDetail(f.items, 4)
  f.items.empty:SetText(L"Нечего докупать.")
  f.total = UI.Font(f, 12, UI.TEXT); f.total:SetPoint("BOTTOMLEFT", 2, 24); f.total:SetPoint("RIGHT", -2, 0)
  f.profit = UI.Font(f, 11, UI.TEXT); f.profit:SetPoint("BOTTOMLEFT", 2, 6); f.profit:SetPoint("RIGHT", -2, 0)
  -- покупка материала из плана: 1) запрос цены у сервера  2) «Купить N за ...» - подтверждение (игра требует нажатия на каждый шаг)
  f.buyBar = CreateFrame("Frame", nil, f); f.buyBar:SetPoint("BOTTOMLEFT", 0, 0); f.buyBar:SetPoint("BOTTOMRIGHT", 0, 0); f.buyBar:SetHeight(42); f.buyBar:Hide()
  f.buyText = UI.Font(f.buyBar, 11, UI.TEXT); f.buyText:SetPoint("TOPLEFT", 2, -2); f.buyText:SetPoint("RIGHT", -2, 0); f.buyText:SetJustifyH("LEFT")
  f.buyCancel = UI.Button(f.buyBar, L"Отмена", 80, 20, function() f.endBuy() end); f.buyCancel:SetPoint("BOTTOMRIGHT", 0, 2)
  f.buyOk = UI.Button(f.buyBar, L"Купить", 170, 20, function()
    local b = f.pending
    if b and b.quoted then pcall(C_AuctionHouse.ConfirmCommoditiesPurchase, b.id, b.qty); b.sent = true; f.buyOk:Disable(); f.buyText:SetText(L"покупаю...") end
  end, true); f.buyOk:SetPoint("RIGHT", f.buyCancel, "LEFT", -6, 0)
  f.endBuy = function() f.pending = nil; f.buyBar:Hide(); f.total:Show(); f.profit:Show() end
  f.startBuy = function(id, qty)
    if not ns.ahOpen or not id or not qty or qty <= 0 then return end
    local stack = select(8, (C_Item and C_Item.GetItemInfo or GetItemInfo)(id))
    if not (C_AuctionHouse and C_AuctionHouse.StartCommoditiesPurchase) or (stack and stack <= 1) then
      ns.SearchAH(id) -- не товар (каждый лот отдельно) - выбрать лот в окне аукциона игры
      return
    end
    f.pending = { id = id, qty = qty }
    f.total:Hide(); f.profit:Hide(); f.buyBar:Show()
    f.buyText:SetText(string.format(L"%s ×%d - узнаю цену...", ns.itemName(id), qty))
    f.buyOk:SetLabel(L"Купить"); f.buyOk:Disable()
    pcall(C_AuctionHouse.StartCommoditiesPurchase, id, qty)
  end
  f.onQuote = function(unit, total)
    local b = f.pending; if not b or b.sent then return end
    b.quoted = true
    f.buyText:SetText(string.format(L"%s ×%d: %s  |cffaaaaaa(%s за шт)|r", ns.itemName(b.id), b.qty, ns.money(total), ns.money(unit)))
    f.buyOk:SetLabel(L"Купить за " .. ns.money(total, true):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")); f.buyOk:Enable()
  end
  f.onBought = function(ok)
    if not f.pending then return end
    ns.say(ok and L"|cff78d98aпокупка совершена.|r Предметы придут на почту." or L"покупка не удалась")
    f.endBuy()
  end
  f.refresh = function()
    local plans = ns.Plans()
    local rd = {}
    local prs, tot = ns.PlanProfit()
    for i, p in ipairs(plans) do rd[#rd + 1] = { i = i, p = p, pr = prs[i] } end
    f.recs:SetData(rd); f.clear:SetShown(#plans > 0); f.upd:SetShown(#plans > 0)
    local needs, total = ns.PlanNeeds()
    f.items:SetData(needs)
    local left = 0; for _, d in ipairs(needs) do if d.buy > 0 then left = left + 1 end end
    if #plans == 0 then f.total:SetText(""); f.profit:SetText("") return end
    f.total:SetText(left == 0 and L"|cff78d98aВсё есть - можно крафтить!|r" or string.format(L"Докупить: %d материалов на %s", left, ns.money(total)))
    -- прибыль всей партии: выручка за результаты минус стоимость всех материалов
    f.profit:SetText(L"Выручка" .. " ~" .. ns.money(tot.revenue, true) .. "   " .. L"материалы" .. " " .. ns.money(tot.cost, true) .. "   " .. L"прибыль" .. " "
      .. ((tot.profit >= 0 and "|cff78d98a+" or "|cffff7a66") .. ns.money(tot.profit, true) .. "|r") .. (tot.missing and L" |cffaa8866(не у всего есть цена)|r" or ""))
  end
end

local BUILDERS = { pageMarked, pageCraft, pagePlan }
local function planPage() return pages and pages[TAB_PLAN] end
ns.On("COMMODITY_PRICE_UPDATED", function(unit, total) local f = planPage(); if f and f.onQuote then f.onQuote(unit, total) end end)
ns.On("COMMODITY_PURCHASE_SUCCEEDED", function() local f = planPage(); if f and f.onBought then f.onBought(true) end end)
ns.On("COMMODITY_PURCHASE_FAILED", function() local f = planPage(); if f and f.onBought then f.onBought(false) end end)
ns.On("AUCTION_HOUSE_CLOSED", function() local f = planPage(); if f and f.endBuy and f.pending then f.endBuy() end end)
local NAMES = { "Избранное", "Мой крафт", "План" }

function ns.BuildAHPanel()
  local h = AuctionHouseFrame or AuctionFrame
  if not h or panel then return end
  panel = CreateFrame("Frame", "WolfichMarketAHPanel", h)
  panel:SetWidth(480)
  panel:SetPoint("TOPLEFT", h, "TOPRIGHT", 2, 0); panel:SetPoint("BOTTOMLEFT", h, "BOTTOMRIGHT", 2, -180) -- длиннее окна аукциона: место для раскрытых строк
  panel:EnableMouse(true)
  UI.Skin(panel, { theme = "ah" })
  -- медальон и название, как в главном окне
  local tfs = UI.Title(panel, "WolfichMarket")
  UI.Close(panel, function() panel:Hide() end)
  header()
  -- вкладки в один ряд
  tabs = {}
  for i, n in ipairs(NAMES) do
    local b = UI.Button(panel, L(n), 82, 26, function() tabs.select(i) end)
    b:SetPoint("TOPLEFT", 14 + (i - 1) * 85, -80)
    tabs[i] = b
  end
  for i, build in ipairs(BUILDERS) do
    local f = CreateFrame("Frame", nil, panel)
    f:SetPoint("TOPLEFT", 14, -142); f:SetPoint("BOTTOMRIGHT", -14, 12)
    build(f); f:Hide()
    pages[i] = f
  end
  function tabs.select(i)
    for k, b in ipairs(tabs) do
      b:SetGold(k == i)
      pages[k]:SetShown(k == i)
    end
    tabs.current = i
    ns.DB.settings.ahTab = i
    if pages[i].refresh then pages[i].refresh() end
  end
  -- кнопка-лапа на окне аукциона: показать/скрыть
  local tg = UI.Icon(h, "skin\\ai-paw", 24, L"WolfichMarket: показать/скрыть панель", function() panel:SetShown(not panel:IsShown()) end)
  tg:SetPoint("RIGHT", h, "TOPRIGHT", -36, -16); tg:SetFrameStrata("HIGH")
  ns.DB.settings.ahPanelHidden = nil -- старый флаг «скрыта навсегда» больше не используется
  panel:Show()
  if not ns.DB.settings.ahTabV2 then
    ns.DB.settings.ahTab = ({ 1, 4, 2, 3, 1, 1, 5 })[ns.DB.settings.ahTab or 1] or 1; ns.DB.settings.ahTabV2 = true
  end
  if not ns.DB.settings.ahTabV3 then -- 2.44.8: убраны «Купить» и «Продать»
    ns.DB.settings.ahTab = ({ 1, 1, 1, 2, 3 })[ns.DB.settings.ahTab or 1] or 1; ns.DB.settings.ahTabV3 = true
  end
  if (ns.DB.settings.ahTab or 1) > #NAMES then ns.DB.settings.ahTab = 1 end
  tabs.select(ns.DB.settings.ahTab or 1)
  ns.AHSelectTab = function(i) tabs.select(i) end
  ns._ahPages = pages
  updateHeader()
  if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(1, function() if panel:IsVisible() then updateHeader() end end) end
end

local function refreshCurrent() if panel and tabs and tabs.current and pages[tabs.current]:IsShown() then pages[tabs.current].refresh() end end
ns.Listen("SCAN_STATE", updateHeader)
ns.Listen("PRICES", refreshCurrent)
ns.Listen("MARKS", refreshCurrent)
ns.Listen("RECIPES", refreshCurrent)
ns.Listen("NAMES", refreshCurrent)
ns.Listen("PLAN", refreshCurrent)
ns.Listen("INVENTORY", function() if tabs and tabs.current == TAB_PLAN then refreshCurrent() end end) -- запас нужен только «Плану»

-- ---------- окно покупки товара в аукционе игры ----------
-- В пустом месте под кнопкой «Купить» - свой график цены, рядом с количеством - звезда «Избранное» и колокольчик сигнала.
-- Окно игры не меняется: только свои дочерние рамки и хуки (hooksecurefunc / HookScript).
local buyDeco
local function buyFrame()
  local cf = type(AuctionHouseFrame) == "table" and AuctionHouseFrame.CommoditiesBuyFrame
  if type(cf) == "table" and cf.GetObjectType then return cf end
end
local function buyFrameItem()
  local cf = buyFrame(); if not cf then return nil end
  for _, o in ipairs({ cf, cf.BuyDisplay }) do
    if type(o) == "table" and o.GetItemID then local ok, id = pcall(o.GetItemID, o); if ok and id then return id end end
  end
  return cf.itemID or (cf.BuyDisplay and cf.BuyDisplay.itemID)
end
local function updateBuyDeco()
  if not buyDeco then return end
  local id = buyFrameItem()
  buyDeco.id = id
  buyDeco:SetShown(id ~= nil and not buyDeco.off)
  if not id then return end
  buyDeco.star:Update(id); buyDeco.bell:Update(id)
  local sold, lots, qty = ns.SoldIn(id, 24), ns.LotsNow(id)
  buyDeco.info:SetText("|cfff2c761WolfichMarket|r   " .. L"продано за 24 ч" .. ": |cffffffff" .. (sold or "-") .. "|r   " .. L"лотов" .. ": |cffffffff" .. (lots or "-")
    .. (qty and qty > 0 and (" |cffaaaaaa(" .. qty .. " " .. L"шт" .. ")|r") or "") .. "|r")
  local h = ns.History(id)
  ns.After(0, function() if buyDeco.id == id then buyDeco.chart:SetPoints(h) end end)
end
function ns.DecorateAHBuy()
  local cf = buyFrame()
  if buyDeco or not cf or ns.DB.settings.ahBuyChart == false then return end
  local bd = (type(cf.BuyDisplay) == "table" and cf.BuyDisplay.GetObjectType) and cf.BuyDisplay or cf
  local d = CreateFrame("Frame", nil, bd)
  d:SetAllPoints(bd); d:SetFrameLevel((bd:GetFrameLevel() or 1) + 5)
  buyDeco = d
  -- звезда и колокольчик - справа от поля «Количество»
  local q = bd.QuantityInput
  local anchor = type(q) == "table" and ((type(q.InputBox) == "table" and q.InputBox.GetObjectType and q.InputBox) or (q.GetObjectType and q)) or nil
  d.star = UI.Star(d, 18, function() return buyDeco and buyDeco.id end)
  if anchor then d.star:SetPoint("LEFT", anchor, "RIGHT", 16, 0) else d.star:SetPoint("TOPRIGHT", bd, "TOPRIGHT", -70, -150) end
  d.bell = UI.Bell(d, 18, function() return buyDeco and buyDeco.id end); d.bell:SetPoint("LEFT", d.star, "RIGHT", 8, -1)
  -- график: от кнопки «Купить» до низа окна
  local box = CreateFrame("Frame", nil, d)
  local bb = type(bd.BuyButton) == "table" and bd.BuyButton.GetObjectType and bd.BuyButton
  if bb then box:SetPoint("TOP", bb, "BOTTOM", 0, -12) else box:SetPoint("TOP", bd, "CENTER", 0, -60) end
  box:SetPoint("LEFT", bd, "LEFT", 12, 0); box:SetPoint("RIGHT", bd, "RIGHT", -12, 0); box:SetPoint("BOTTOM", bd, "BOTTOM", 0, 10)
  d.info = UI.Font(box, 10, UI.DIM); d.info:SetPoint("TOPLEFT", 4, 0); d.info:SetPoint("RIGHT", -4, 0); d.info:SetJustifyH("LEFT")
  d.chart = UI.Chart(box); d.chart.mid = true; d.chart.noLegend = true
  d.chart:SetPoint("TOPLEFT", 0, -14); d.chart:SetPoint("BOTTOMRIGHT", 0, 0)
  d.chart.onClick = function() if buyDeco and buyDeco.id then ns.ShowChartDialog(buyDeco.id) end end
  d.box = box
  if type(cf.SetItemIDAndPrice) == "function" then hooksecurefunc(cf, "SetItemIDAndPrice", function() ns.After(0, updateBuyDeco) end) end
  if type(bd) == "table" and bd ~= cf and type(bd.SetItemIDAndPrice) == "function" then hooksecurefunc(bd, "SetItemIDAndPrice", function() ns.After(0, updateBuyDeco) end) end
  if cf.HookScript then cf:HookScript("OnShow", function() ns.After(0, updateBuyDeco) end) end
  updateBuyDeco()
end
ns.UpdateAHBuy = updateBuyDeco
ns._ahBuyDeco = function() return buyDeco end
function ns.SetAHBuyDeco(on)
  ns.DB.settings.ahBuyChart = on ~= false
  if on ~= false then if buyDeco then buyDeco.off = nil; updateBuyDeco() elseif ns.ahOpen then ns.DecorateAHBuy() end
  elseif buyDeco then buyDeco.off = true; buyDeco:Hide() end
  if ns.ahOpen and on ~= false and ns.DecorateAHSell then ns.DecorateAHSell() end
  if ns.UpdateAHSell then ns.UpdateAHSell() end
end
local buyQueued
local function buyRefresh()
  if not buyDeco or buyQueued or not buyDeco:IsVisible() then return end
  buyQueued = true
  ns.After(0.5, function() buyQueued = false; updateBuyDeco() end)
end
ns.Listen("PRICES", buyRefresh)
ns.Listen("MARKS", buyRefresh)
-- окно выставления лота (товары и предметы): тот же график под кнопкой «Объявить аукцион»
local sellDecos = {}
local function sellItem(sf)
  local ok, loc = pcall(sf.GetItem, sf)
  if not ok or type(loc) ~= "table" then return nil end
  local ok2, id = pcall(C_Item.GetItemID, loc)
  return ok2 and id or nil
end
-- место под график: от кнопки «Объявить аукцион» до низа окна. Пока игра не разложила рамки,
-- высота бывает 0 - тогда не прячем (раньше из-за этого график пропадал у части предметов)
local function sellRoom(d)
  local h = d.box:GetHeight() or 0
  if h > 0 then return h end
  local pb, sf = d.sf.PostButton, d.sf
  local a = type(pb) == "table" and pb.GetBottom and pb:GetBottom()
  local b = sf.GetBottom and sf:GetBottom()
  if a and b and a > b then return a - b end
  return 999
end
local function updateSellDeco(d)
  if not d then return end
  local id = d.off == nil and ns.DB.settings.ahBuyChart ~= false and sellItem(d.sf) or nil
  d.id = id
  d:SetShown(id ~= nil and sellRoom(d) >= 50)
  if not d:IsShown() then return end
  local sold, lots, qty = ns.SoldIn(id, 24), ns.LotsNow(id)
  d.info:SetText("|cfff2c761WolfichMarket|r   " .. L"продано за 24 ч" .. ": |cffffffff" .. (sold or "-") .. "|r   " .. L"лотов" .. ": |cffffffff" .. (lots or "-")
    .. (qty and qty > 0 and (" |cffaaaaaa(" .. qty .. " " .. L"шт" .. ")|r") or "") .. "|r")
  local h = ns.History(id)
  ns.After(0, function() if d.id == id then d.chart:SetPoints(h) end end)
end
function ns.DecorateAHSell()
  if type(AuctionHouseFrame) ~= "table" then return end
  for _, key in ipairs({ "CommoditiesSellFrame", "ItemSellFrame" }) do
    local sf = AuctionHouseFrame[key]
    if type(sf) == "table" and sf.GetObjectType and not sellDecos[key] then
      local d = CreateFrame("Frame", nil, sf)
      d:SetAllPoints(sf); d:SetFrameLevel((sf:GetFrameLevel() or 1) + 5)
      d.sf = sf
      local box = CreateFrame("Frame", nil, sf)
      local pb = type(sf.PostButton) == "table" and sf.PostButton.GetObjectType and sf.PostButton
      if pb then box:SetPoint("TOP", pb, "BOTTOM", 0, -14) else box:SetPoint("TOP", sf, "CENTER", 0, -80) end
      box:SetPoint("LEFT", sf, "LEFT", 14, 0); box:SetPoint("RIGHT", sf, "RIGHT", -14, 0); box:SetPoint("BOTTOM", sf, "BOTTOM", 0, 12)
      d.box = box
      local inner = CreateFrame("Frame", nil, d); inner:SetAllPoints(box)
      d.info = UI.Font(inner, 10, UI.DIM); d.info:SetPoint("TOPLEFT", 4, 0); d.info:SetPoint("RIGHT", -4, 0); d.info:SetJustifyH("LEFT")
      d.chart = UI.Chart(inner); d.chart.mid = true; d.chart.noLegend = true
      d.chart:SetPoint("TOPLEFT", 0, -14); d.chart:SetPoint("BOTTOMRIGHT", 0, 0)
      d.chart.onClick = function() if d.id then ns.ShowChartDialog(d.id) end end
      sellDecos[key] = d
      -- обновить сразу и ещё раз чуть позже, когда игра закончит раскладку окна
      local function later() for _, t in ipairs({ 0, 0.3 }) do ns.After(t, function() updateSellDeco(d) end) end end
      if type(sf.SetItem) == "function" then hooksecurefunc(sf, "SetItem", later) end
      -- страховка: предмет в окне сменился другим путём - раз в полсекунды сверяем (рамка видна только вместе с окном)
      local acc = 0
      box:SetScript("OnUpdate", function(_, el)
        acc = acc + (el or 0); if acc < 0.5 then return end; acc = 0
        local id = ns.DB.settings.ahBuyChart ~= false and sellItem(sf) or nil
        if id ~= d.id or (id and not d:IsShown() and sellRoom(d) >= 50) then updateSellDeco(d) end
      end)
      if sf.HookScript then sf:HookScript("OnShow", later) end
      updateSellDeco(d)
    end
  end
end
ns._ahSellDecos = sellDecos -- для автотестов
ns.UpdateAHSell = function() for _, d in pairs(sellDecos) do updateSellDeco(d) end end
ns.Listen("PRICES", function() for _, d in pairs(sellDecos) do if d:IsVisible() then ns.After(0.5, function() updateSellDeco(d) end) end end end)
ns.On("AUCTION_HOUSE_SHOW", function() ns.After(0, function() if ns.DecorateAHBuy then ns.DecorateAHBuy() end; if ns.DecorateAHSell then ns.DecorateAHSell() end end) end)

-- игра запретила вызов (нужно нажатие игрока) - выключаем автозапрос цены
ns.On("ADDON_ACTION_BLOCKED", function(addon) if addon == "WolfichMarket" then ns._quoteBlocked = true end end)
ns.On("ADDON_ACTION_FORBIDDEN", function(addon) if addon == "WolfichMarket" then ns._quoteBlocked = true end end)
