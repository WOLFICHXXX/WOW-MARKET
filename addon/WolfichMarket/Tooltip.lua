-- WolfichMarket: цена аукциона, тренд и прибыль в подсказке предмета
local _, ns = ...
local L = ns.L
local safe = ns.safe

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

local done = setmetatable({}, { __mode = "k" }) -- подсказка -> предмет, строки которого уже добавлены (своя таблица, без полей в подсказке игры)
ns._ttClear = function(tt) done[tt] = nil end -- для автотестов
local function addLines(tt, id)
  if not id or not ns.DB or not ns.DB.settings.tooltip or done[tt] == id then return end
  done[tt] = id
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
  -- tt:Show() здесь не нужен (строки добавляются до показа подсказки) и задевал код игры
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
GameTooltip:HookScript("OnTooltipCleared", function(tt) done[tt] = nil end)
if ItemRefTooltip then ItemRefTooltip:HookScript("OnTooltipCleared", function(tt) done[tt] = nil end) end

-- ---------- у тренера профессии: «стоит ли учить рецепт» ----------
-- В подсказке рецепта у тренера: себестоимость, цена предмета на аукционе, прибыль за крафт,
-- спрос (продано за 24 ч, лотов сейчас), средняя цена за неделю и за сколько крафтов окупится обучение.
local trainerOpen = false
ns.On("TRAINER_SHOW", function() trainerOpen = true end)
ns.On("TRAINER_CLOSED", function() trainerOpen = false end)
ns._trainerOpen = function(v) trainerOpen = v end -- для автотестов

local function recBySpell(spellID)
  if not spellID then return nil end
  for _, c in pairs(ns.DB.chars or {}) do
    for _, p in pairs(c.profs or {}) do
      for _, rec in ipairs(p.recipes or {}) do if rec.id == spellID and rec.out then return rec end end
    end
  end
end
-- номер услуги тренера по названию рецепта (для цены обучения)
local function trainerCost(name)
  if not name or not GetNumTrainerServices or not GetTrainerServiceInfo then return nil end
  for i = 1, (safe(GetNumTrainerServices) or 0) do
    local n = safe(GetTrainerServiceInfo, i)
    if n == name and GetTrainerServiceCost then return (safe(GetTrainerServiceCost, i)) end
  end
end
-- рецепт из данных тренера (если профессию ещё не открывали): предмет и материалы
local function recFromTrainer(index)
  if not index or not GetTrainerServiceItemLink then return nil end
  local out = ns.idFromLink(safe(GetTrainerServiceItemLink, index))
  if not out then return nil end
  local rec = { out = out, reag = {} }
  for i = 1, (GetTrainerServiceNumReagents and safe(GetTrainerServiceNumReagents, index) or 0) do
    local id = GetTrainerServiceReagentLink and ns.idFromLink(safe(GetTrainerServiceReagentLink, index, i))
    local _, _, cnt = safe(GetTrainerServiceReagentInfo, index, i)
    if id then rec.reag[#rec.reag + 1] = { id, cnt or 1 } end
  end
  return rec, (GetTrainerServiceCost and safe(GetTrainerServiceCost, index))
end

local trainerDone = setmetatable({}, { __mode = "k" })
local function money(v) return v >= 0 and ("|cff78d98a+" .. ns.money(v) .. "|r") or ("|cffff7a66-" .. ns.money(-v) .. "|r") end
-- строки «стоит ли учить»; возвращает true, если что-то добавлено
function ns.TrainerLines(tt, rec, cost)
  if not rec or not rec.out or not ns.DB.settings.tooltip then return false end
  local key = rec.out
  if trainerDone[tt] == key then return false end
  trainerDone[tt] = key
  local id = rec.out
  local pr = ns.Profit(rec)
  local q = pr.qty or 1
  tt:AddLine(" ")
  tt:AddLine("|cffe6b450WolfichMarket|r |cffaaaaaa— " .. L"стоит ли учить" .. "|r")
  tt:AddDoubleLine(L"  Себестоимость крафта", pr.missing == 0 and ns.money(pr.cost) or ("|cff777777" .. L"нет цен материалов: " .. pr.missing .. "|r"))
  tt:AddDoubleLine(L"  На аукционе" .. (q ~= 1 and (" |cffaaaaaa(×" .. (math.floor(q * 10 + 0.5) / 10) .. ")|r") or ""), pr.sell and ns.money(pr.sell * q) or L"|cff777777нет цены - не выставляют|r")
  local vend = ns.VendorSell and ns.VendorSell(id)
  if vend and vend > 0 then tt:AddDoubleLine(L"  |cffaaaaaaторговцу|r", "|cffaaaaaa" .. ns.money(vend * q) .. "|r") end
  if pr.profit then tt:AddDoubleLine(L"  Прибыль за крафт" .. " |cffaaaaaa(-" .. ns.CutPct() .. ")|r", money(pr.profit)) end
  -- спрос: сколько продают и сколько выставлено
  local sold, lots = ns.SoldIn(id, 24), ns.LotsNow(id)
  local avg7 = ns.AvgPrice(id, 24 * 7)
  tt:AddDoubleLine(L"  Продано за 24 ч / лотов сейчас", (sold and tostring(sold) or "?") .. " / " .. (lots and tostring(lots) or "?"))
  if avg7 and pr.sell then tt:AddDoubleLine(L"  Средняя цена за 7 дней", ns.money(avg7) .. "  " .. ns.pct((pr.sell - avg7) / avg7 * 100)) end
  cost = cost or trainerCost(rec.name)
  -- вывод
  local verdict
  if not pr.sell then verdict = L"|cffffd919Предмет не продают на аукционе - выгоду не оценить.|r"
  elseif not pr.profit then verdict = L"|cffffd919Нет цен части материалов - сделайте снимок аукциона.|r"
  elseif pr.profit <= 0 then verdict = L"|cffff7a66В минус: выгоднее продать материалы. Учить - только ради навыка.|r"
  else
    local n = (cost and cost > 0) and math.ceil(cost / pr.profit) or nil
    if sold and sold == 0 then verdict = L"|cffffd919Прибыль есть, но за сутки ничего не продано - спрос слабый.|r"
    elseif n then verdict = string.format(L"|cff78d98aВыгодно: обучение (%s) окупится за %d крафт(ов).|r", ns.money(cost, true):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""), n)
    else verdict = L"|cff78d98aВыгодно: каждый крафт в плюс.|r" end
  end
  tt:AddLine("  " .. verdict, 1, 1, 1, true)
  return true
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Spell then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tt, data)
    if tt ~= GameTooltip or not trainerOpen then return end
    ns.TrainerLines(tt, recBySpell(data and data.id))
  end)
end
-- клиент без данных подсказок или рецепт ещё не известен аддону: берём всё у тренера
if GameTooltip.SetTrainerService then
  hooksecurefunc(GameTooltip, "SetTrainerService", function(tt, index)
    local rec, cost = recFromTrainer(index)
    local known = rec and findRecipe(rec.out)
    if known and known.reag and #known.reag > 0 then rec = known end
    if rec and ns.TrainerLines(tt, rec, cost) and not (InCombatLockdown and InCombatLockdown()) then tt:Show() end
  end)
end
GameTooltip:HookScript("OnTooltipCleared", function(tt) trainerDone[tt] = nil end)
