-- WolfichMarket: команды чата
local _, ns = ...
local L = ns.L

local function help()
  ns.say("v" .. ns.VERSION .. L". Всё самое нужное - на панелях у окон аукциона и профессий (кнопка-лапа скрывает их).")
  print(L"  |cffe6b450/wm|r - окно крафта и сигналов (или кнопка-лапа у миникарты)")
  print(L"  |cffe6b450/wm help|r - эта справка")
  print(L"  |cffe6b450/wm scan|r - снимок аукциона (у аукциониста, раз в 15 мин)")
  print(L"  |cffe6b450/wm best|r - лучший крафт сейчас")
  print(L"  |cffe6b450/wm marks|r - отмеченные предметы")
  print(L"  Клавиша для выставления по очереди: Настройки > Управление > WolfichMarket (или макрос /click WolfichMarketPostNextButton)")
  print(L"  |cffe6b450/wm reset|r - очистить отметки и историю цен")
  print(L"  Alt+клик по предмету - отметить |TInterface\\AddOns\\WolfichMarket\\media\\star-on:12:12|t (уведомления о скачках цены только по отмеченным)")
end

local function slash(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if not ns.DB or not ns.charKey then ns.say(L"ещё загружается...") return end
  if msg == "scan" or msg == "ah" then ns.StartScan()
  elseif msg == "best" then
    local b = ns.BestCraft()
    if b then ns.say(L"лучший крафт: " .. b.rec.name .. L" - прибыль " .. ns.money(b.profit) .. " (" .. b.prof .. ")") else ns.say(L"нет данных: откройте профессии и сделайте снимок аукциона.") end
  elseif msg == "marks" then
    local n = 0
    for id in pairs(ns.DB.marked) do n = n + 1; local p = ns.AHPrice(id); print("  |TInterface\\AddOns\\WolfichMarket\\media\\star-on:12:12|t " .. ns.itemLinkText(id) .. "  " .. (p and ns.money(p) or L"нет цены")) end
    if n == 0 then ns.say(L"отмеченных нет. Alt+клик по предмету - отметить.") end
  elseif msg == "reset" then
    wipe(ns.DB.marked); wipe(ns.DB.hist); wipe(ns.DB.seen); ns.DB.lastBest = nil
    ns.say(L"отметки и история цен очищены."); ns.Fire("MARKS"); ns.Fire("PRICES")
  elseif msg == "help" or msg == "?" then help()
  elseif msg == "debug" then
    ns.DB.settings.debug = not ns.DB.settings.debug; ns.say(L"отладка: " .. (ns.DB.settings.debug and L"вкл" or L"выкл"))
  else if ns.ToggleMain then ns.ToggleMain() else help() end end
end

SLASH_WOLFICHMARKET1 = "/wm"
SLASH_WOLFICHMARKET2 = "/wolfichmarket"
SlashCmdList.WOLFICHMARKET = function(msg)
  local ok, err = xpcall(function() slash(msg) end, function(e) return tostring(e) .. "\n" .. (debugstack and debugstack(2, 3, 0) or "") end)
  if not ok then ns.say(L"|cffff6060ошибка:|r " .. tostring(err)) end
end
-- привязка клавиши: «Выставить следующий отмеченный лот» (Настройки → Управление → WolfichMarket)
BINDING_HEADER_WOLFICHMARKET = "WolfichMarket"
BINDING_NAME_WOLFICHMARKET_POSTNEXT = L"Выставить следующий отмеченный лот"
BINDING_NAME_WOLFICHMARKET_TOGGLE = L"Окно WolfichMarket (крафт и сигналы)"
function WolfichMarket_Toggle() if ns.ToggleMain then ns.ToggleMain() end end
function WolfichMarket_PostNext() if ns.PostNext then ns.PostNext() end end

SLASH_WOLFICHMARKETAH1 = "/wmah"
SlashCmdList.WOLFICHMARKETAH = function() local p = _G.WolfichMarketAHPanel; if p and ns.AHIsOpen and ns.AHIsOpen() then p:Show() end; SlashCmdList.WOLFICHMARKET("scan") end
