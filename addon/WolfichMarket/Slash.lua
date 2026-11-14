-- WolfichMarket: команды чата
local _, ns = ...

local function help()
  ns.say("v" .. ns.VERSION .. ". Всё самое нужное - на панелях у окон аукциона и профессий (кнопка-лапа скрывает их).")
  print("  |cffe6b450/wm scan|r - снимок аукциона (у аукциониста, раз в 15 мин)")
  print("  |cffe6b450/wm best|r - лучший крафт сейчас")
  print("  |cffe6b450/wm marks|r - отмеченные предметы")
  print("  |cffe6b450/wm reset|r - очистить отметки и историю цен")
  print("  Alt+клик по предмету - отметить |TInterface\\AddOns\\WolfichMarket\\media\\star-on:12:12|t (уведомления о скачках цены только по отмеченным)")
end

local function slash(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if not ns.DB or not ns.charKey then ns.say("ещё загружается...") return end
  if msg == "scan" or msg == "ah" then ns.StartScan()
  elseif msg == "best" then
    local b = ns.BestCraft()
    if b then ns.say("лучший крафт: " .. b.rec.name .. " - прибыль " .. ns.money(b.profit) .. " (" .. b.prof .. ")") else ns.say("нет данных: откройте профессии и сделайте снимок аукциона.") end
  elseif msg == "marks" then
    local n = 0
    for id in pairs(ns.DB.marked) do n = n + 1; local p = ns.AHPrice(id); print("  |TInterface\\AddOns\\WolfichMarket\\media\\star-on:12:12|t " .. ns.itemLinkText(id) .. "  " .. (p and ns.money(p) or "нет цены")) end
    if n == 0 then ns.say("отмеченных нет. Alt+клик по предмету - отметить.") end
  elseif msg == "reset" then
    wipe(ns.DB.marked); wipe(ns.DB.hist); wipe(ns.DB.seen); ns.DB.lastBest = nil
    ns.say("отметки и история цен очищены."); ns.Fire("MARKS"); ns.Fire("PRICES")
  elseif msg == "debug" then
    ns.DB.settings.debug = not ns.DB.settings.debug; ns.say("отладка: " .. (ns.DB.settings.debug and "вкл" or "выкл"))
  else help() end
end

SLASH_WOLFICHMARKET1 = "/wm"
SLASH_WOLFICHMARKET2 = "/wolfichmarket"
SlashCmdList.WOLFICHMARKET = function(msg)
  local ok, err = xpcall(function() slash(msg) end, function(e) return tostring(e) .. "\n" .. (debugstack and debugstack(2, 3, 0) or "") end)
  if not ok then ns.say("|cffff6060ошибка:|r " .. tostring(err)) end
end
SLASH_WOLFICHMARKETAH1 = "/wmah"
SlashCmdList.WOLFICHMARKETAH = function() SlashCmdList.WOLFICHMARKET("scan") end
