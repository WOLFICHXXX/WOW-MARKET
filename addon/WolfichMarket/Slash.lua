-- WolfichMarket: команды чата
local _, ns = ...
local L = ns.L

local function help()
  ns.tell("v" .. ns.VERSION .. L". Всё самое нужное - на панелях у окон аукциона и профессий (кнопка-лапа скрывает их).")
  ns.out(L"  |cffe6b450/wm|r - окно крафта и сигналов (или кнопка-лапа у миникарты)")
  ns.out(L"  |cffe6b450/wm help|r - эта справка")
  ns.out(L"  |cffe6b450/wm scan|r - снимок аукциона (у аукциониста, раз в 15 мин)")
  ns.out(L"  |cffe6b450/wm best|r - лучший крафт сейчас")
  ns.out(L"  |cffe6b450/wm marks|r - отмеченные предметы")
  ns.out(L"  |cffe6b450/wm chat|r - куда писать сообщения: window - журнал окна (по умолчанию), main - чат, tab - своя вкладка, off - никуда")
  ns.out(L"  |cffe6b450/wm net|r - проверка общего рынка, |cffe6b450/wm netsend|r - разослать свой снимок ещё раз")
  ns.out(L"  Клавиша для выставления по очереди: Настройки > Управление > WolfichMarket (или макрос /click WolfichMarketPostNextButton)")
  ns.out(L"  |cffe6b450/wm reset|r - очистить отметки и историю цен")
  ns.out(L"  Alt+клик по предмету - отметить |TInterface\\AddOns\\WolfichMarket\\media\\star-on:12:12|t (уведомления о скачках цены только по отмеченным)")
end

local function slash(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if not ns.DB or not ns.charKey then ns.tell(L"ещё загружается...") return end
  if msg == "scan" or msg == "ah" then ns.StartScan()
  elseif msg == "best" then
    local b = ns.BestCraft()
    if b then ns.tell(L"лучший крафт: " .. b.rec.name .. L" - прибыль " .. ns.money(b.profit) .. " (" .. b.prof .. ")") else ns.tell(L"нет данных: откройте профессии и сделайте снимок аукциона.") end
  elseif msg == "marks" then
    local n = 0
    for id in pairs(ns.DB.marked) do n = n + 1; local p = ns.AHPrice(id); ns.out("  |TInterface\\AddOns\\WolfichMarket\\media\\star-on:12:12|t " .. ns.itemLinkText(id) .. "  " .. (p and ns.money(p) or L"нет цены")) end
    if n == 0 then ns.tell(L"отмеченных нет. Alt+клик по предмету - отметить.") end
  elseif msg == "reset" then
    wipe(ns.DB.marked); wipe(ns.DB.hist); wipe(ns.DB.seen); ns.DB.lastBest = nil
    ns.tell(L"отметки и история цен очищены."); ns.Fire("MARKS"); ns.Fire("PRICES")
  elseif msg == "help" or msg == "?" then help()
  elseif msg == "net" then
    -- проверка общего рынка: куда уходят и откуда приходят цены
    local st = ns.netStats or {}
    local id = GetChannelName and GetChannelName("WolfichMarketNet")
    ns.tell(L"общий рынок:")
    ns.out("  " .. L"канал аддона" .. ": " .. ((id and id > 0) and ("|cff78d98a#" .. id .. "|r") or L"|cffff6060не подключён|r"))
    local rs = ns.NetRoutes and ns.NetRoutes() or {}
    local names = {}
    for _, r in ipairs(rs) do names[#names + 1] = r[1] == "BN" and ("Battle.net " .. tostring(r[3])) or (r[1] .. (r[2] and (" " .. r[2]) or "")) end
    ns.out("  " .. L"маршруты" .. ": " .. (#names > 0 and table.concat(names, ", ") or L"|cffff6060нет|r"))
    ns.out("  " .. L"отправлено" .. ": " .. (st.sent or 0) .. "   " .. L"ошибок" .. ": " .. (st.fail or 0) .. (st.lastFail and (" (" .. st.lastFail .. ")") or ""))
    ns.out("  " .. L"получено" .. ": " .. (st.recv or 0) .. (st.lastFrom and ("   " .. L"последнее от" .. " " .. st.lastFrom) or ""))
    local by = {}
    for k, v in pairs(st.by or {}) do by[#by + 1] = (k == "CHANNEL" and L"канал" or k == "BN" and "Battle.net" or k == "WHISPER" and L"личные" or k == "GUILD" and L"гильдия" or k) .. " " .. v end
    if #by > 0 then ns.out("  " .. L"пришло через" .. ": " .. table.concat(by, ", ")) end
    local t, from = ns.NetInfo and ns.NetInfo()
    ns.out("  " .. L"цены игроков" .. ": " .. (t and (ns.ago(t) .. " (" .. tostring(from) .. ")") or L"ещё не приходили"))
    ns.out("  " .. L"делиться" .. ": " .. (ns.DB.settings.netSend ~= false and L"вкл" or L"выкл") .. "   " .. L"принимать" .. ": " .. (ns.DB.settings.netRecv ~= false and L"вкл" or L"выкл"))
  elseif msg == "netsend" then
    local scan = ns.DB.ahScans[ns.realmKey]
    if scan and ns.ShareScan then ns.ShareScan(scan) else ns.tell(L"своего снимка аукциона нет - сделайте его у аукциониста.") end
  elseif msg:match("^chat") then
    local m = msg:match("^chat%s+(%a+)")
    local map = { window = "window", main = "main", tab = "tab", quiet = "quiet", off = "off" }
    if map[m] then ns.DB.settings.chatMode = map[m]; ns.tell(L"сообщения аддона: " .. L(({ window = "только в журнале главного окна", main = "в общий чат", tab = "в свою вкладку чата", quiet = "в чат только сигналы", off = "выключены" })[m]))
    else ns.tell(L"/wm chat window | main | tab | quiet | off - журнал окна, общий чат, своя вкладка, только сигналы, выключить") end
  elseif msg == "debug" then
    ns.DB.settings.debug = not ns.DB.settings.debug; ns.tell(L"отладка: " .. (ns.DB.settings.debug and L"вкл" or L"выкл"))
  else if ns.ToggleMain then ns.ToggleMain() else help() end end
end

SLASH_WOLFICHMARKET1 = "/wm"
SLASH_WOLFICHMARKET2 = "/wolfichmarket"
SlashCmdList.WOLFICHMARKET = function(msg)
  local ok, err = xpcall(function() slash(msg) end, function(e) return tostring(e) .. "\n" .. (debugstack and debugstack(2, 3, 0) or "") end)
  if not ok then ns.tell(L"|cffff6060ошибка:|r " .. tostring(err)) end
end
-- привязка клавиши: «Выставить следующий отмеченный лот» (Настройки → Управление → WolfichMarket)
BINDING_HEADER_WOLFICHMARKET = "WolfichMarket"
BINDING_NAME_WOLFICHMARKET_POSTNEXT = L"Выставить следующий отмеченный лот"
BINDING_NAME_WOLFICHMARKET_TOGGLE = L"Окно WolfichMarket (крафт и сигналы)"
function WolfichMarket_Toggle() if ns.ToggleMain then ns.ToggleMain() end end
function WolfichMarket_PostNext() if ns.PostNext then ns.PostNext() end end

-- короткие команды общего рынка (и на случай, если пишут без пробела)
SLASH_WOLFICHMARKETNET1 = "/wmnet"
SlashCmdList.WOLFICHMARKETNET = function() SlashCmdList.WOLFICHMARKET("net") end
SLASH_WOLFICHMARKETNETSEND1 = "/wmnetsend"
SlashCmdList.WOLFICHMARKETNETSEND = function() SlashCmdList.WOLFICHMARKET("netsend") end
SLASH_WOLFICHMARKETAH1 = "/wmah"
SlashCmdList.WOLFICHMARKETAH = function() local p = _G.WolfichMarketAHPanel; if p and ns.AHIsOpen and ns.AHIsOpen() then p:Show() end; SlashCmdList.WOLFICHMARKET("scan") end
