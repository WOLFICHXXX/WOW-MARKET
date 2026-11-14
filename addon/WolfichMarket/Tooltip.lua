-- WolfichMarket: цена аукциона, тренд и прибыль в подсказке предмета
local _, ns = ...
local L = ns.L

local function findRecipe(id)
  local c = ns.DB.chars[ns.charKey or ""]
  for _, p in pairs(c and c.profs or {}) do
    for _, rec in ipairs(p.recipes or {}) do if rec.out == id and rec.learned ~= false then return rec end end
  end
end

local function addLines(tt, id)
  if not id or not ns.DB or not ns.DB.settings.tooltip or tt.wmDone == id then return end
  tt.wmDone = id
  local p, t = ns.AHPrice(id)
  local v = ns.DB.vendor[id]
  if not p and not v and not ns.IsMarked(id) then return end
  local head = "|cffe6b450WolfichMarket|r" .. (ns.IsMarked(id) and " |cfff0c85a|TInterface\\AddOns\\WolfichMarket\\media\\star-on:12:12|t|r" or "")
  if p then
    local avg = ns.AvgPrice(id, 24)
    tt:AddDoubleLine(head, ns.money(p) .. (avg and ("  " .. ns.pct((p - avg) / avg * 100)) or ""))
    tt:AddDoubleLine(L"|cffaaaaaa  аукцион, " .. ns.ago(t) .. "|r", avg and (L"|cffaaaaaaсредняя 24 ч " .. ns.money(avg, true) .. "|r") or "")
  else
    tt:AddLine(head)
  end
  if v then tt:AddDoubleLine(L"|cffaaaaaa  у торговца|r", ns.money(v)) end
  local rec = findRecipe(id)
  if rec then
    local pr = ns.Profit(rec)
    if pr.profit then tt:AddDoubleLine(L"|cffaaaaaa  прибыль крафта|r", (pr.profit >= 0 and "|cff78d98a" or "|cffff7a66") .. ns.money(pr.profit) .. "|r") end
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
