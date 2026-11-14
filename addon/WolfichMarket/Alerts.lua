-- WolfichMarket: уведомления — скачки цен ТОЛЬКО по отмеченным предметам и лучший крафт
local _, ns = ...
local UI = ns.UI

local function sound()
  if not ns.DB.settings.alertSound then return end
  local id = (SOUNDKIT and (SOUNDKIT.UI_ORDERHALL_TALENT_READY_TOAST or SOUNDKIT.RAID_WARNING)) or 8959
  pcall(PlaySound, id, "Master")
end

ns.Listen("SCAN_DONE", function(scan, prev)
  local S = ns.DB.settings
  -- скачки цен по отмеченным
  if S.alerts then
    local hits = {}
    for id in pairs(ns.DB.marked) do
      local r = scan.items[id]
      local p = r and r[1] > 0 and r[1]
      local base = ns.AvgPrice(id, 24)
      if not base and prev and prev.items and prev.items[id] and prev.items[id][1] > 0 then base = prev.items[id][1] end
      if p and base and base > 0 then
        local ch = (p - base) / base * 100
        if math.abs(ch) >= (S.alertPct or 20) then hits[#hits + 1] = { id = id, p = p, ch = ch } end
      end
    end
    table.sort(hits, function(a, b) return math.abs(a.ch) > math.abs(b.ch) end)
    if #hits > 0 then
      for _, h in ipairs(hits) do
        ns.say(string.format("%s %s - %s %s", h.ch > 0 and "|cff78d98a|TInterface\\AddOns\\WolfichMarket\\media\\up:12:12|t|r" or "|cffff7a66|TInterface\\AddOns\\WolfichMarket\\media\\down:12:12|t|r", ns.itemLinkText(h.id), ns.money(h.p), ns.pct(h.ch)))
      end
      local top = hits[1]
      UI.Toast(string.format("%s %s %s", top.ch > 0 and "|TInterface\\AddOns\\WolfichMarket\\media\\up:12:12|t Подорожало:" or "|TInterface\\AddOns\\WolfichMarket\\media\\down:12:12|t Подешевело:", ns.itemName(top.id), ns.pct(top.ch)),
        ns.money(top.p) .. " за шт" .. (#hits > 1 and ("  /  ещё скачков: " .. (#hits - 1)) or ""), ns.itemIcon(top.id))
      sound()
    end
  end
  -- лучший крафт
  if S.bestCraftAlert then
    local best = ns.BestCraft()
    if best and best.profit and best.profit > 0 then
      local last = ns.DB.lastBest
      local changed = not last or last.id ~= best.rec.id or math.abs(best.profit - (last.p or 0)) > math.max(1, (last.p or 0) * 0.15)
      if changed then
        ns.DB.lastBest = { id = best.rec.id, p = best.profit }
        ns.After(S.alerts and 9 or 0, function()
          UI.Toast("Лучший крафт: " .. best.rec.name, "Прибыль " .. ns.money(best.profit) .. " за штуку (" .. best.prof .. ")", best.rec.out and ns.itemIcon(best.rec.out))
          ns.say("лучший крафт: " .. best.rec.name .. " - прибыль " .. ns.money(best.profit))
        end)
      end
    end
  end
end)
