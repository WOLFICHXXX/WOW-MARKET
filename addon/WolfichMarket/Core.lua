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
ns.VERSION = "2.4.0"
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
function ns.say(msg) print(PREFIX .. tostring(msg)) end

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
  autoScan = true,        -- сам снимать аукцион, пока открыт аукционист
  autoScanMin = 15,       -- раз в N минут (не чаще 15 - ограничение сервера)
  profitOnly = false,     -- фильтр в окне профессии
  showUnlearned = false,  -- показывать неизученные рецепты
  minProfit = 0,
  tooltip = true,
  bagGlow = true,
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
  DB.alarm = DB.alarm or {}        -- [itemID] = свой порог скачка, %          -- [itemID] = { p, t } - цены из поисков на аукционе
  DB.ahScans = DB.ahScans or {}
  DB.settings = DB.settings or {}
  for k, v in pairs(DEFAULTS) do if DB.settings[k] == nil then DB.settings[k] = v end end
  -- со старых версий: один снимок → по режимам
  if DB.ahScan and not next(DB.ahScans) then DB.ahScans[(DB.ahScan.realmN or "?") .. "|" .. (DB.ahScan.faction or "?")] = DB.ahScan end
  DB._repl = nil
  ns.Fire("DB_READY")
end)

ns.On("PLAYER_LOGIN", function()
  local name = UnitName("player") or "?"
  local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
  ns.charKey = realm ~= "" and (name .. "-" .. realm) or name
  ns.realmKey = (realm ~= "" and realm or "?") .. "|" .. ((UnitFactionGroup and UnitFactionGroup("player")) or "?")
  local DB = ns.DB
  DB.chars[ns.charKey] = DB.chars[ns.charKey] or { profs = {} }
  local c = DB.chars[ns.charKey]
  c.realmKey = ns.realmKey
  c.class = select(2, UnitClass("player"))
  c.name = UnitName("player")
  ns.Fire("LOGIN")
  ns.say("v" .. ns.VERSION .. L" загружен. Цены и прибыль - в окнах аукциона и профессий. /wm - справка.")
end)

ns.On("GET_ITEM_INFO_RECEIVED", function(id)
  if id and pendingNames[id] then pendingNames[id] = nil; ns.itemName(id); ns.Fire("NAMES") end
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
function ns.AHPrice(id)
  local scan = ns.CurrentScan()
  local p, t, q
  local rec = scan and scan.items and scan.items[id]
  if rec and rec[1] and rec[1] > 0 then p, t, q = rec[1], scan.t, rec[2] end
  local s = ns.DB.seen[id]
  if s and s.p and s.p > 0 and (not t or s.t > t) and s.r == (ns.priceRealm or ns.realmKey) then p, t = s.p, s.t; q = s.q or q end
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
  ns.DB.seen[id] = { p = unit, t = time(), q = qty, r = ns.realmKey }
end

-- ---------- история и отметки ----------
local HIST_MAX = 120
function ns.AddHistory(id, p, q, t)
  local h = ns.DB.hist[id]
  if not h then h = {}; ns.DB.hist[id] = h end
  local last = h[#h]
  if last and t - last[1] < 300 then last[2], last[3] = p, q return end -- не чаще раза в 5 минут
  h[#h + 1] = { t, p, q }
  while #h > HIST_MAX do table.remove(h, 1) end
end
-- средняя цена за последние N часов (без последней точки)
function ns.AvgPrice(id, hours)
  local h = ns.DB.hist[id]
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
  end)
end

-- поиск предмета в окне аукциона
function ns.AHIsOpen() return ns.ahOpen == true end
function ns.SearchAH(id)
  if not ns.ahOpen then ns.say(L"откройте окно аукциона, чтобы искать.") return end
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
