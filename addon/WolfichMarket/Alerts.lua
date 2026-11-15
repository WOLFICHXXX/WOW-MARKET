-- WolfichMarket: уведомления — скачки цен ТОЛЬКО по отмеченным предметам и лучший крафт
local _, ns = ...
local L = ns.L
local UI = ns.UI

local function sound()
  if not ns.DB.settings.alertSound then return end
  local id = (SOUNDKIT and (SOUNDKIT.UI_ORDERHALL_TALENT_READY_TOAST or SOUNDKIT.RAID_WARNING)) or 8959
  pcall(PlaySound, id, "Master")
end

local function onScan(scan, prev)
  local S = ns.DB.settings
  -- скачки цен по отмеченным
  if S.alerts then
    -- своя цена: покупка - когда цена опустилась до неё, продажа - когда поднялась до неё
    local hits = {}
    ns.DB.targetHit = ns.DB.targetHit or {}
    for id, t in pairs(ns.DB.target or {}) do
      local r = scan.items and scan.items[id]
      local p = r and r[1] and r[1] > 0 and r[1]
      if p then
        for _, side in ipairs({ "buy", "sell" }) do
          local v = t[side]
          if v then
            local ok = (side == "buy" and p <= v) or (side == "sell" and p >= v)
            local key = id .. side
            if ok and not ns.DB.targetHit[key] then hits[#hits + 1] = { id = id, p = p, side = side, v = v } end
            ns.DB.targetHit[key] = ok or nil
          end
        end
      end
    end
    if #hits > 0 then
      for _, h in ipairs(hits) do
        ns.say(string.format("%s %s - %s (%s %s)", h.side == "sell" and "|cff78d98a|TInterface\\AddOns\\WolfichMarket\\media\\up:12:12|t|r" or "|cffff7a66|TInterface\\AddOns\\WolfichMarket\\media\\down:12:12|t|r",
          ns.itemLinkText(h.id), ns.money(h.p), h.side == "sell" and L"ваша цена продажи" or L"ваша цена покупки", ns.money(h.v)), true)
      end
      local top = hits[1]
      UI.Toast(string.format("%s %s", top.side == "sell" and L"Пора продавать:" or L"Пора покупать:", ns.itemName(top.id)),
        ns.money(top.p) .. L" за шт" .. (#hits > 1 and (L"  /  ещё сигналов: " .. (#hits - 1)) or ""), ns.itemIcon(top.id))
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
          UI.Toast(L"Лучший крафт: " .. best.rec.name, L"Прибыль " .. ns.money(best.profit) .. L" за штуку (" .. best.prof .. ")", best.rec.out and ns.itemIcon(best.rec.out))
          ns.say(L"лучший крафт: " .. best.rec.name .. L" - прибыль " .. ns.money(best.profit))
        end)
      end
    end
  end
end
ns.Listen("SCAN_DONE", onScan)
ns.Listen("NET_DONE", onScan) -- цены от других игроков с аддоном тоже проверяют сигналы
