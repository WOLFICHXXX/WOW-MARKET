-- WolfichMarket: ядро — база данных, события, цены, история, отметки.
local addonName, ns = ...
-- язык: "ru" / "en"; по умолчанию — по языку клиента игры
function ns.Lang()
  local s = ns.DB and ns.DB.settings and ns.DB.settings.lang
  if s == "ru" or s == "en" then return s end
  return (GetLocale and GetLocale() == "ruRU") and "ru" or "en"
end
function ns.L(s) if ns.Lang() == "en" then return (ns.EN and ns.EN[s]) or s end return s end
local L = ns.L
ns.VERSION = "2.35.1"
ns.MEDIA = "Interface\\AddOns\\WolfichMarket\\media\\"
ns.AH_CUT = 0.05

local unpack = unpack or table.unpack
local function pack(...) return { n = select("#", ...), ... } end
function ns.safe(fn, ...)
  if type(fn) ~= "function" then return nil end
  local r = pack(pcall(fn, ...))
  if r[1] then return unpack(r, 2, r.n) end
  return nil
end
local safe = ns.safe

function ns.clean(s) return (tostring(s or ""):gsub("[%^\r\n]", " ")) end
local PREFIX = "|cffe6b450WolfichMarket|r: "
-- куда писать сообщения аддона: settings.chatMode = "main" (общий чат), "tab" (своя вкладка «WolfichMarket»),
-- "quiet" (только сигналы о ценах), "off" (ничего, кроме ответов на команды)
local CHAT_TAB = "WolfichMarket"
local function chatFrame()
  local mode = ns.DB and ns.DB.settings and ns.DB.settings.chatMode or "window"
  if mode == "tab" and GetChatWindowInfo then
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
      local name, _, _, _, _, _, shown = GetChatWindowInfo(i)
      local f = _G["ChatFrame" .. i]
      if name == CHAT_TAB and f and (shown or (f.isDocked)) then return f end
    end
    -- вкладки ещё нет - создаём один раз; в ней только сообщения аддона
    if FCF_OpenNewWindow and not ns._tabTried then
      ns._tabTried = true
      local ok, f = pcall(FCF_OpenNewWindow, CHAT_TAB)
      if ok and f then
        if ChatFrame_RemoveAllMessageGroups then pcall(ChatFrame_RemoveAllMessageGroups, f) end
        if ChatFrame_RemoveAllChannels then pcall(ChatFrame_RemoveAllChannels, f) end
        return f
      end
    end
  end
  return DEFAULT_CHAT_FRAME
end
-- строка в выбранное окно чата (ответы на команды - всегда)
function ns.out(text)
  local f = chatFrame()
  if f and f.AddMessage then f:AddMessage(tostring(text)) else print(tostring(text)) end
end
function ns.tell(msg) ns.out(PREFIX .. tostring(msg)) end
-- журнал сообщений аддона (вкладка «Журнал» в главном окне): последние 200
ns.log = {}
local function addLog(msg, important)
  table.insert(ns.log, 1, { t = time(), msg = tostring(msg), imp = important })
  while #ns.log > 200 do table.remove(ns.log) end
  if ns.Fire then ns.Fire("LOG") end
end
-- обычное сообщение аддона; important - сигналы о ценах.
-- По умолчанию («window») сообщения идут только в журнал главного окна, а не в чат.
function ns.say(msg, important)
  local mode = ns.DB and ns.DB.settings and ns.DB.settings.chatMode or "window"
  addLog(msg, important)
  if mode == "window" or mode == "off" or (mode == "quiet" and not important) then return end
  ns.out(PREFIX .. tostring(msg))
end
function ns.dbg(msg) if ns.DB and ns.DB.settings and ns.DB.settings.debug then ns.say("|cff888888" .. tostring(msg) .. "|r") end end

-- ---------- деньги ----------
function ns.money(c, short)
  if not c then return "|cff777777-|r" end
  local neg = c < 0
  c = math.floor(math.abs(c) + 0.5)
  local g, s, m = math.floor(c / 10000), math.floor(c % 10000 / 100), c % 100
  local out = {}
  if g > 0 then out[#out + 1] = g .. L"|cffffd100з|r" end
  if (g > 0 or s > 0) and not (short and g >= 100) then out[#out + 1] = s .. L"|cffc7c7cfс|r" end
  if g == 0 and not (short and s >= 10) then out[#out + 1] = m .. L"|cffeda55fм|r" end
  return (neg and "|cffff6060-|r" or "") .. table.concat(out, " ")
end
function ns.ago(t)
  if not t or t == 0 then return L"никогда" end
  local m = math.floor((time() - t) / 60)
  if m < 1 then return L"только что" end
  if m < 60 then return m .. L" мин назад" end
  if m < 60 * 24 then return math.floor(m / 60) .. L" ч назад" end
  return math.floor(m / 1440) .. L" дн назад"
end
function ns.pct(v)
  if not v then return "|cff777777-|r" end
  local r = math.floor(v * 10 + (v >= 0 and 0.5 or -0.5)) / 10
  if r > 0 then return "|cff78d98a+" .. r .. "%|r" end
  if r < 0 then return "|cffff7a66" .. r .. "%|r" end
  return "|cffaaaaaa0%|r"
end

-- ---------- предметы ----------
local pendingNames = {}
ns.pendingNames = pendingNames
function ns.itemName(id)
  if not id then return "?" end
  local DB = ns.DB
  if DB and DB.names[id] then return DB.names[id] end
  local name
  if C_Item and C_Item.GetItemNameByID then name = safe(C_Item.GetItemNameByID, id) end
  if not name and C_Item and C_Item.GetItemInfo then name = safe(C_Item.GetItemInfo, id) end
  if not name and GetItemInfo then name = safe(GetItemInfo, id) end
  if name then if DB then DB.names[id] = ns.clean(name) end return name end
  if C_Item and C_Item.RequestLoadItemDataByID then safe(C_Item.RequestLoadItemDataByID, id) end
  pendingNames[id] = true
  return "#" .. id
end
function ns.itemIcon(id)
  local tex
  if C_Item and C_Item.GetItemIconByID then tex = safe(C_Item.GetItemIconByID, id) end
  if not tex and GetItemIcon then tex = safe(GetItemIcon, id) end
  return tex or 134400 -- знак вопроса
end
function ns.itemQualityColor(id)
  local q
  if C_Item and C_Item.GetItemQualityByID then q = safe(C_Item.GetItemQualityByID, id) end
  if q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] then return ITEM_QUALITY_COLORS[q].hex or "|cffffffff" end
  return "|cffffffff"
end
function ns.VendorSell(id)
  local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local v = get and select(11, safe(get, id))
  return (v and v > 0) and v or nil
end
function ns.itemLinkText(id) return ns.itemQualityColor(id) .. ns.itemName(id) .. "|r" end
function ns.idFromLink(link)
  if type(link) ~= "string" then return nil end
  return tonumber(link:match("item:(%d+)"))
end

-- ---------- события (несколько обработчиков на событие) ----------
local handlers = {}
local evFrame = CreateFrame("Frame")
function ns.On(event, fn)
  if not handlers[event] then
    handlers[event] = {}
    pcall(evFrame.RegisterEvent, evFrame, event)
  end
  table.insert(handlers[event], fn)
end
evFrame:SetScript("OnEvent", function(_, event, ...)
  for _, fn in ipairs(handlers[event] or {}) do
    local ok, err = pcall(fn, ...)
    if not ok and ns.DB and ns.DB.settings.debug then ns.say(L"ошибка в " .. event .. ": " .. tostring(err)) end
  end
end)
-- собственные сигналы между модулями
local signals = {}
function ns.Listen(name, fn) signals[name] = signals[name] or {}; table.insert(signals[name], fn) end
function ns.Fire(name, ...) for _, fn in ipairs(signals[name] or {}) do pcall(fn, ...) end end

function ns.After(sec, fn) if C_Timer and C_Timer.After then C_Timer.After(sec, fn) else fn() end end

-- ---------- база данных ----------
local DEFAULTS = {
  alertPct = 20,          -- порог скачка цены, %
  alerts = true,          -- уведомления включены
  alertSound = true,
  bestCraftAlert = true,
  autoScan = false,       -- сам снимать аукцион, пока открыт аукционист (по умолчанию - вручную)
  autoScanMin = 15,       -- раз в N минут (не чаще 15 - ограничение сервера)
  profitOnly = false,     -- фильтр в окне профессии
  showUnlearned = false,  -- показывать неизученные рецепты
  minProfit = 0,
  tooltip = true,
  bagGlow = true,
  sortByValue = true,     -- после сортировки сумок: аукцион наверх, торговцу вниз
  bagValue = true,        -- стоимость сумок над окном сумок
  netSend = true,         -- общий рынок: делиться своими снимками
  netTurbo = true,        -- общий рынок: 4 служебных имени, до 800 байт/с
  netRecv = true,         -- общий рынок: принимать цены других игроков
  minimapShown = true,         -- подсветка в сумках: жёлтый - торговцу, зелёный - аукцион
  debug = false,
}
ns.On("ADDON_LOADED", function(name)
  if name ~= addonName then return end
  WolfichMarketDB = WolfichMarketDB or {}
  local DB = WolfichMarketDB
  ns.DB = DB
  DB.chars = DB.chars or {}
  DB.vendor = DB.vendor or {}
  DB.names = DB.names or {}
  DB.marked = DB.marked or {}      -- [itemID] = true
  DB.hist = DB.hist or {}          -- [itemID] = { {t, min, qty}, ... }
  DB.seen = DB.seen or {}
  DB.target = DB.target or {}      -- [itemID] = { buy = медь, sell = медь } - свои цены сигналов
  DB.alarm = DB.alarm or {}        -- [itemID] = свой порог скачка, %          -- [itemID] = { p, t } - цены из поисков на аукционе
  DB.ahScans = DB.ahScans or {}
  DB.settings = DB.settings or {}
  for k, v in pairs(DEFAULTS) do if DB.settings[k] == nil then DB.settings[k] = v end end
  -- со старых версий: один снимок → по режимам
  if DB.ahScan and not next(DB.ahScans) then DB.ahScans[(DB.ahScan.realmN or "?") .. "|" .. (DB.ahScan.faction or "?")] = DB.ahScan end
  DB._repl = nil
  -- 2.11: снимок аукциона - вручную (автоснимок можно включить в настройках)
  if not DB.settings.manualScanV then DB.settings.autoScan = false; DB.settings.manualScanV = 1 end
  ns.Fire("DB_READY")
end)

-- Аукцион в WoW Forever общий для всех серверов (и «каналов») одного режима: CAMWOWEU4Realm6PvP и
-- CAMWOWEU5Realm4PvP торгуют на одном аукционе. Ключ аукциона = режим (PvP / PvE / обычный) + фракция.
function ns.NormRealmKey(key)
  if not key then return key end
  local realm, faction = key:match("^(.*)|([^|]*)$")
  if not realm then return key end
  if realm == "PvP" or realm == "PvE" or realm == "RP" or realm == "Normal" then return key end -- уже новый вид
  local mode = realm:match("(PvP)$") or realm:match("(PvE)$") or realm:match("(RP)$") or realm:match("Realm%d+(%a+)$") or "Normal"
  return mode .. "|" .. faction
end
-- перевод старых данных (по имени сервера) на новый ключ: снимки, история, цены игроков, персонажи
function ns.MigrateRealmKeys()
  local DB = ns.DB
  if DB.realmKeysV == 1 then return end
  local scans = {}
  for k, sc in pairs(DB.ahScans or {}) do
    local nk = ns.NormRealmKey(k)
    if not scans[nk] or (sc.t or 0) > (scans[nk].t or 0) then sc.realm = nk; scans[nk] = sc end
  end
  DB.ahScans = scans
  for _, h in pairs(DB.hist or {}) do for _, p in ipairs(h) do if p[4] then p[4] = ns.NormRealmKey(p[4]) end end end
  for _, s2 in pairs(DB.seen or {}) do if s2.r then s2.r = ns.NormRealmKey(s2.r) end end
  for _, c in pairs(DB.chars or {}) do if c.realmKey then c.realmKey = ns.NormRealmKey(c.realmKey) end end
  if DB.net then
    local net = {}
    for k, v in pairs(DB.net) do local nk = ns.NormRealmKey(k); if not net[nk] or (v.t or 0) > (net[nk].t or 0) then net[nk] = v end end
    DB.net = net
  end
  DB.realmKeysV = 1
end

-- нижний регистр с русскими буквами (string.lower меняет только латиницу)
local RU_UP = "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ"
local RU_LO = "абвгдеёжзийклмнопрстуфхцчшщъыьэюя"
local RU_MAP = {}
do
  local up, lo = {}, {}
  for ch in RU_UP:gmatch("[%z\1-\127\194-\244][\128-\191]*") do up[#up + 1] = ch end
  for ch in RU_LO:gmatch("[%z\1-\127\194-\244][\128-\191]*") do lo[#lo + 1] = ch end
  for i, ch in ipairs(up) do RU_MAP[ch] = lo[i] end
end
function ns.lower(s)
  if not s then return "" end
  return (s:lower():gsub("[\208\209][\128-\191]", function(ch) return RU_MAP[ch] or ch end))
end
function ns.FixBMScans()
  for rk, sc in pairs(ns.DB.ahScans) do
    if sc.lots and sc.lots < 1000 and sc.items then
      ns.DB.bmah = ns.DB.bmah or {}
      local bm = {}
      for id, r in pairs(sc.items) do if r[1] and r[1] > 0 then bm[id] = { p = r[1], bids = 0, q = r[2], lots = r[3] } end end
      if not ns.DB.bmah[rk] or (ns.DB.bmah[rk].t or 0) < sc.t then ns.DB.bmah[rk] = { t = sc.t, lots = sc.lots, items = bm } end
      ns.DB.ahScans[rk] = nil
      for _, h in pairs(ns.DB.hist) do for i = #h, 1, -1 do if h[i][1] == sc.t then table.remove(h, i) end end end
    end
  end
end
ns.On("PLAYER_LOGIN", function()
  local name = UnitName("player") or "?"
  local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
  ns.charKey = realm ~= "" and (name .. "-" .. realm) or name
  -- одинаковое имя на разных персонажах (другой режим/фракция) не должно сливать их профессии
  local guid = UnitGUID and UnitGUID("player")
  local old = ns.DB.chars[ns.charKey]
  if guid and old and old.guid and old.guid ~= guid then ns.charKey = ns.charKey .. "~" .. guid:sub(-6) end
  ns.realmKey = ns.NormRealmKey((realm ~= "" and realm or "?") .. "|" .. ((UnitFactionGroup and UnitFactionGroup("player")) or "?"))
  ns.MigrateRealmKeys()
  -- до 2.34 снимок чёрного рынка (несколько сотен лотов) мог записаться вместо обычного аукциона (сотни тысяч лотов):
  -- такой маленький «снимок аукциона» переносим в чёрный рынок, а его точки убираем из графиков
  if not ns.DB.bmFixV then ns.FixBMScans() end
  -- 2.35.1 ошибочно переносил большой снимок чёрного рынка в обычный аукцион (у такого снимка нет отметки персонажа) - вернуть
  if ns.DB.bmFixV == 2 then
    for rk, sc in pairs(ns.DB.ahScans) do
      if not sc.char and sc.items and (not ns.DB.bmah or not ns.DB.bmah[rk] or (ns.DB.bmah[rk].t or 0) < (sc.t or 0)) then
        local bm = {}
        for id, r in pairs(sc.items) do if r[1] and r[1] > 0 then bm[id] = { p = r[1], bids = 0, q = r[2], lots = r[3] } end end
        ns.DB.bmah = ns.DB.bmah or {}
        ns.DB.bmah[rk] = { t = sc.t, lots = sc.lots, items = bm }
        ns.DB.ahScans[rk] = nil
      end
    end
  end
  ns.DB.bmFixV = 3
  local DB = ns.DB
  DB.chars[ns.charKey] = DB.chars[ns.charKey] or { profs = {} }
  local c = DB.chars[ns.charKey]
  c.realmKey = ns.realmKey
  c.guid = guid or c.guid
  c.class = select(2, UnitClass("player"))
  c.name = UnitName("player")
  ns.Fire("LOGIN")
  ns.say("v" .. ns.VERSION .. L" загружен. Цены и прибыль - в окнах аукциона и профессий. /wm - справка.")
end)

ns.On("GET_ITEM_INFO_RECEIVED", function(id)
  -- названия приходят пачками - одно обновление окон на пачку, а не на каждый предмет
  if id and pendingNames[id] then
    pendingNames[id] = nil; ns.itemName(id)
    if not ns._namesQueued then ns._namesQueued = true; ns.After(0.5, function() ns._namesQueued = false; ns.Fire("NAMES") end) end
  end
end)

-- ---------- цены ----------
-- снимок аукциона для режима и фракции текущего персонажа
-- ns.priceRealm — временно (расчёт для другого персонажа); если для его режима снимка нет — берём текущий
function ns.CurrentScan()
  local DB = ns.DB
  if not DB then return nil end
  local rk = ns.priceRealm or ns.realmKey
  return (rk and DB.ahScans[rk]) or (ns.realmKey and DB.ahScans[ns.realmKey]) or nil
end
function ns.WithRealm(rk, fn, ...)
  local old = ns.priceRealm
  ns.priceRealm = rk
  local ok, a, b = pcall(fn, ...)
  ns.priceRealm = old
  if not ok then error(a, 0) end
  return a, b
end
-- цена за штуку на аукционе: самая свежая из снимка и поисков. Возвращает цена, время, количество
-- У окна чёрного рынка все цены аддона (списки, прибыль крафта, продажа) берутся из снимка чёрного рынка -
-- так видно, что выгоднее продать там, а что на обычном аукционе. Подсказка и вкладка «Чёрный рынок» показывают оба.
function ns.BMView() return ns.ahIsBM and ns.ahOpen and not ns._regularOnly end
function ns.AHPrice(id)
  if ns.BMView() then
    local d = ns.DB.bmah and ns.DB.bmah[ns.priceRealm or ns.realmKey or ""]
    local r = d and d.items[id]
    if r and r.p and r.p > 0 then return r.p, d.t, r.q end
    return nil
  end
  return ns.RegularPrice(id)
end
-- цена обычного аукциона (всегда, даже у окна чёрного рынка)
function ns.RegularPrice(id)
  local scan = ns.CurrentScan()
  local p, t, q
  local rec = scan and scan.items and scan.items[id]
  if rec and rec[1] and rec[1] > 0 then p, t, q = rec[1], scan.t, rec[2] end
  local s = ns.DB.seen[id]
  if s and s.p and s.p > 0 and (not t or s.t > t) and s.r == (ns.priceRealm or ns.realmKey) then p, t = s.p, s.t; q = s.q or q end
  -- цена от другого игрока с аддоном (общий рынок) - только если она свежее нашей
  if ns.NetPrice then
    local np, nt, nq = ns.NetPrice(id)
    if np and np > 0 and (not t or nt > t) then p, t, q = np, nt, nq or q end
  end
  return p, t, q
end
-- себестоимость материала: дешевле из торговца и аукциона
function ns.CostPrice(id)
  local v = ns.DB.vendor[id]
  local a = ns.AHPrice(id)
  if v and (not a or v <= a) then return v, L"торговец" end
  if a then return a, L"аукцион" end
  return nil, nil
end
-- запомнить цену, увиденную при поиске на аукционе
function ns.SeenPrice(id, unit, qty)
  if not id or not unit or unit <= 0 then return end
  -- поиск на чёрном рынке - в его отдельные цены, обычный аукцион не трогаем
  if ns.ahIsBM and ns.ahOpen then
    ns.DB.bmah = ns.DB.bmah or {}
    local d = ns.DB.bmah[ns.realmKey or ""] or { t = time(), items = {} }
    ns.DB.bmah[ns.realmKey or ""] = d
    d.items[id] = { p = unit, bids = 0, q = qty or 1 }
    ns.Fire("BLACKMARKET")
    return
  end
  ns.DB.seen[id] = { p = unit, t = time(), q = qty, r = ns.realmKey }
  ns.AddHistory(id, unit, qty or 0, time()) -- каждая свежая цена - точка на графике
end

-- ---------- история и отметки ----------
local HIST_MAX = 120
-- история цен общая для всех персонажей; у каждой точки - режим/фракция аукциона (r),
-- чтобы твинк на другом аукционе не смешивал цены и не получал ложных сигналов
function ns.AddHistory(id, p, q, t)
  local h = ns.DB.hist[id]
  if not h then h = {}; ns.DB.hist[id] = h end
  local r = ns.priceRealm or ns.realmKey
  for i = #h, math.max(1, #h - 10), -1 do -- последняя точка этого же аукциона
    local last = h[i]
    if (last[4] or r) == r then
      if t - last[1] < 120 then last[2], last[3], last[4] = p, q, r return end -- не чаще раза в 2 минуты
      break
    end
  end
  h[#h + 1] = { t, p, q, r }
  while #h > HIST_MAX do table.remove(h, 1) end
end
-- точки истории для текущего аукциона (старые точки без пометки - для всех)
function ns.History(id)
  local h = ns.DB.hist[id]
  if not h then return nil end
  local r = ns.priceRealm or ns.realmKey
  local out = {}
  for _, p in ipairs(h) do if (p[4] or r) == r then out[#out + 1] = p end end
  return out
end
-- средняя цена за последние N часов (без последней точки)
function ns.AvgPrice(id, hours)
  if ns.BMView() then return nil end -- история - цены обычного аукциона, с чёрным рынком не сравниваем
  local h = ns.History(id)
  if not h or #h < 2 then return nil end
  local from = time() - hours * 3600
  local sum, n = 0, 0
  for i = 1, #h - 1 do if h[i][1] >= from and h[i][2] > 0 then sum = sum + h[i][2]; n = n + 1 end end
  return n > 0 and sum / n or nil
end
function ns.IsMarked(id) return ns.DB.marked[id] == true end
function ns.ToggleMark(id)
  if not id then return end
  if ns.DB.marked[id] then ns.DB.marked[id] = nil else ns.DB.marked[id] = true end
  ns.say((ns.DB.marked[id] and L"|cfff0c85a|TInterface\\AddOns\\WolfichMarket\\media\\star-on:12:12|t отмечено|r: " or L"отметка снята: ") .. ns.itemLinkText(id))
  ns.Fire("MARKS")
end

-- Alt+клик по предмету (сумки, ссылки, аукцион) — отметить/снять
if hooksecurefunc then
  pcall(hooksecurefunc, "HandleModifiedItemClick", function(link)
    if IsAltKeyDown and IsAltKeyDown() and not (IsShiftKeyDown() or IsControlKeyDown()) then
      local id = ns.idFromLink(link)
      if id and ns.DB then ns.ToggleMark(id) end
    end
    -- Shift+клик по любому предмету (сумки, ссылки) при открытом аукционе - открыть его на аукционе,
    -- если не набирается сообщение в чате и не в фокусе поле ввода
    if IsShiftKeyDown and IsShiftKeyDown() and not (IsAltKeyDown() or IsControlKeyDown()) and ns.ahOpen then
      local typing = (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()) or (GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus())
      local id = ns.idFromLink(link)
      if id and not typing then ns.SearchAH(id, link) end
    end
  end)
end

-- поиск предмета в окне аукциона
function ns.AHIsOpen() return ns.ahOpen == true end
function ns.SearchAH(id)
  if not ns.ahOpen then ns.say(L"откройте окно аукциона, чтобы искать.") return end
  -- товар (ткань, травы, зелья...) - сразу его страница покупки, без поиска по названию
  local AH = AuctionHouseFrame
  if AH and AH.SelectBrowseResult and C_AuctionHouse and C_AuctionHouse.MakeItemKey and C_AuctionHouse.GetItemKeyInfo then
    local key = ns.safe(C_AuctionHouse.MakeItemKey, id)
    local info = key and ns.safe(C_AuctionHouse.GetItemKeyInfo, key)
    if info and info.isCommodity then
      if AH.SetDisplayMode and AuctionHouseFrameDisplayMode and AuctionHouseFrameDisplayMode.Buy then pcall(AH.SetDisplayMode, AH, AuctionHouseFrameDisplayMode.Buy) end
      if pcall(AH.SelectBrowseResult, AH, { itemKey = key }) then return end
    end
  end
  local name = ns.itemName(id)
  if name:sub(1, 1) == "#" then ns.say(L"название предмета ещё грузится, нажмите ещё раз.") return end
  local sb = AuctionHouseFrame and AuctionHouseFrame.SearchBar
  if sb and sb.SetSearchText and sb.StartSearch then
    if AuctionHouseFrame.SetDisplayMode and AuctionHouseFrameDisplayMode and AuctionHouseFrameDisplayMode.Buy then
      pcall(AuctionHouseFrame.SetDisplayMode, AuctionHouseFrame, AuctionHouseFrameDisplayMode.Buy)
    end
    sb:SetSearchText(name)
    pcall(sb.StartSearch, sb)
  elseif BrowseName and AuctionFrameBrowse_Search then
    BrowseName:SetText(name); pcall(AuctionFrameBrowse_Search)
  end
end
