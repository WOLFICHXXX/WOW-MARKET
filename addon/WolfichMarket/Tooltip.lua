-- WolfichMarket: цена аукциона, тренд и прибыль в подсказке предмета
local _, ns = ...
local L = ns.L

-- рецепт, который делает этот предмет: сначала у текущего персонажа, потом у остальных (и у добавленных профессий)
local function findRecipe(id)
  local function look(c, learnedOnly)
    for _, p in pairs(c and c.profs or {}) do
      for _, rec in ipairs(p.recipes or {}) do if rec.out == id and (not learnedOnly or rec.learned ~= false) and rec.reag and #rec.reag > 0 then return rec end end
    end
  end
  local cur = ns.DB.chars[ns.charKey or ""]
  local r = look(cur, true)
  if r then return r end
  for _, c in pairs(ns.DB.chars or {}) do r = look(c, true); if r then return r end end
  r = look(cur, false)
  if r then return r end
  for _, c in pairs(ns.DB.chars or {}) do r = look(c, false); if r then return r end end
end

local function addLines(tt, id)
  if not id or not ns.DB or not ns.DB.settings.tooltip or tt.wmDone == id then return end
  tt.wmDone = id
  local p, t = ns.RegularPrice(id)
  local v = ns.DB.vendor[id]
  local rec = findRecipe(id)
  local nt, ntT = ns.AltPrice and ns.AltPrice("neutral", id)
  if not p and not v and not rec and not nt and not ns.IsMarked(id) then return end
  local head = "|cffe6b450WolfichMarket|r" .. (ns.IsMarked(id) and " |cfff0c85a|TInterface\\AddOns\\WolfichMarket\\media\\star-on:12:12|t|r" or "")
  if p then
    local avg = ns.AvgPrice(id, 24)
    tt:AddDoubleLine(head, ns.money(p) .. (avg and ("  " .. ns.pct((p - avg) / avg * 100)) or ""))
    tt:AddDoubleLine(L"|cffaaaaaa  аукцион, " .. ns.ago(t) .. "|r", avg and (L"|cffaaaaaaсредняя 24 ч " .. ns.money(avg, true) .. "|r") or "")
  else
    tt:AddLine(head)
  end
  if v then tt:AddDoubleLine(L"|cffaaaaaa  у торговца|r", ns.money(v)) end
  -- общий аукцион - отдельно от основного
  if nt then
    tt:AddDoubleLine(L"  |cff66d9ccОбщий аукцион|r" .. " |cffaaaaaa(" .. (nt.lots and (L"лотов: " .. nt.lots) or "") .. ", " .. ns.ago(ntT) .. ")|r", ns.money(nt.p))
  end
  local where, net, sell
  if ns.SellWhere then where, net, sell = ns.SellWhere(id) end
  if where == "ah" then tt:AddDoubleLine(L"  |cff40ff4dВыгоднее: на аукцион|r", sell and ("|cffaaaaaa" .. L"торговец" .. " " .. ns.money(sell, true) .. "|r") or "")
  elseif where == "vendor" and net then tt:AddDoubleLine(L"  |cffffd919Выгоднее: торговцу|r", ns.money(ns.VendorSell(id))) end
  if rec then
    -- крафт: себестоимость, цена на аукционе (за вычетом 5%), прибыль
    local pr = ns.Profit(rec)
    local q = pr.qty or 1
    local qs = (q ~= 1) and (" |cffaaaaaa(×" .. (math.floor(q * 10 + 0.5) / 10) .. ")|r") or ""
    tt:AddDoubleLine(L"  Стоимость крафта", pr.missing == 0 and ns.money(pr.cost) or ("|cff777777" .. L"нет цен материалов: " .. pr.missing .. "|r"))
    tt:AddDoubleLine(L"  На аукционе" .. qs, pr.sell and ns.money(pr.sell * q) or L"|cff777777нет|r")
    if pr.profit then
      tt:AddDoubleLine(L"  Прибыль" .. " |cffaaaaaa(-" .. ns.CutPct() .. ")|r", (pr.profit >= 0 and ("|cff78d98a+" .. ns.money(pr.profit)) or ("|cffff7a66-" .. ns.money(-pr.profit))) .. "|r")
    end
  end
  tt:Show()
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
    if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
    local id = data and data.id
    if not id and tt.GetItem then local _, link = tt:GetItem(); id = ns.idFromLink(link) end
    addLines(tt, id)
  end)
else
  GameTooltip:HookScript("OnTooltipSetItem", function(tt) local _, link = tt:GetItem(); addLines(tt, ns.idFromLink(link)) end)
end
GameTooltip:HookScript("OnTooltipCleared", function(tt) tt.wmDone = nil end)
if ItemRefTooltip then ItemRefTooltip:HookScript("OnTooltipCleared", function(tt) tt.wmDone = nil end) end
