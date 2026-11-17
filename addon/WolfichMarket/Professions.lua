-- WolfichMarket: окно профессии — скан рецептов, прибыль на каждом рецепте, фильтр, поиск на аукционе
local _, ns = ...
local L = ns.L
local safe, clean, UI = ns.safe, ns.clean, ns.UI
local M = ns.MEDIA

-- ---------- скан рецептов текущей профессии ----------
local function professionInfo()
  if not C_TradeSkillUI then return nil end
  local info = safe(C_TradeSkillUI.GetChildProfessionInfo)
  if not info or not info.professionName or info.professionName == "" then info = safe(C_TradeSkillUI.GetBaseProfessionInfo) end
  if info and info.professionName and info.professionName ~= "" then return info.professionName, info.skillLevel or 0, info.maxSkillLevel or 0, info.professionID end
end
local function isForeign()
  if not C_TradeSkillUI then return true end
  return safe(C_TradeSkillUI.IsTradeSkillLinked) or safe(C_TradeSkillUI.IsTradeSkillGuild) or safe(C_TradeSkillUI.IsNPCCrafting) or false
end

ns.curProf = nil
function ns.ScanProfession()
  if not ns.DB or not ns.charKey or not C_TradeSkillUI or isForeign() then return end
  local prof, skill, maxSkill, line = professionInfo()
  if not prof then return end
  local ids = safe(C_TradeSkillUI.GetAllRecipeIDs)
  if not ids or #ids == 0 then return end
  local recipes = {}
  for _, rid in ipairs(ids) do
    local ri = safe(C_TradeSkillUI.GetRecipeInfo, rid)
    if ri and not ri.isDummyRecipe and ri.name then
      local sch = safe(C_TradeSkillUI.GetRecipeSchematic, rid, false)
      local rec = { id = rid, name = clean(ri.name), diff = ri.relativeDifficulty, icon = ri.icon, learned = ri.learned and true or false,
        out = sch and sch.outputItemID or nil, qmin = sch and sch.quantityMin or 1, qmax = sch and sch.quantityMax or 1, reag = {} }
      if sch and sch.reagentSlotSchematics then
        for _, slot in ipairs(sch.reagentSlotSchematics) do
          local r = slot.reagents and slot.reagents[1]
          local need = slot.quantityRequired or 0
          if r and r.itemID and need > 0 and slot.required ~= false then table.insert(rec.reag, { r.itemID, need }); ns.itemName(r.itemID) end
        end
      end
      if rec.out then ns.itemName(rec.out) end
      recipes[#recipes + 1] = rec
    end
  end
  ns.ScanSkills() -- свежая книга профессий (уровень мог вырасти)
  local base = safe(C_TradeSkillUI.GetBaseProfessionInfo)
  if not ns.OwnsProfession(prof, base) then
    ns.dbg("чужая профессия не сохранена: " .. prof)
    return
  end
  local c = ns.DB.chars[ns.charKey]
  c.profs[prof] = { skill = skill, max = maxSkill, t = time(), recipes = recipes, line = line, base = base and base.professionID or nil }
  ns.curProf = prof
  ns.Fire("RECIPES")
end

function ns.RemoveProfession(charKey, name)
  local c = ns.DB.chars[charKey]
  if c and c.profs and c.profs[name] then c.profs[name] = nil; ns.say(L"профессия удалена у персонажа: " .. name); ns.Fire("RECIPES") end
end
function ns.ScanSkills()
  if not GetProfessions or not GetProfessionInfo or not ns.charKey then return end
  local list = { safe(GetProfessions) }
  local out = {}
  for i = 1, 6 do
    local idx = list[i]
    if idx then
      local name, _, rank, maxRank, _, _, line = safe(GetProfessionInfo, idx)
      if name then out[#out + 1] = { name = clean(name), skill = rank or 0, max = maxRank or 0, line = line } end
    end
  end
  if #out > 0 then ns.DB.chars[ns.charKey].skills = out end
  return out
end
-- открытое окно профессии - этого персонажа? (а не чужая ссылка/другой персонаж)
-- сверяем номер базовой профессии, имя и уровень с книгой профессий персонажа
function ns.OwnsProfession(prof, base)
  local c = ns.charKey and ns.DB.chars[ns.charKey]
  local sk = c and c.skills
  if not sk or #sk == 0 then return true end -- книга ещё не прочитана - не мешаем
  local id = base and base.professionID
  local bname = base and base.professionName and clean(base.professionName)
  local haveLines = false
  for _, s in ipairs(sk) do
    if s.line then haveLines = true end
    if (id and s.line == id) or s.name == prof or (bname and s.name == bname) then
      -- то же ремесло, но чужой уровень (ссылка на профессию другого персонажа)
      local lv, mx = base and base.skillLevel, base and base.maxSkillLevel
      if lv and mx and mx > 0 and s.max and s.max > 0 and lv ~= s.skill and mx ~= s.max then return false end
      return true
    end
  end
  return not haveLines -- без номеров профессий не уверены - сохраняем
end
-- убрать у текущего персонажа профессии, которых нет в его книге (попали от другого персонажа)
function ns.CleanStrangers()
  local c = ns.charKey and ns.DB.chars[ns.charKey]
  local sk = c and c.skills
  if not c or not c.profs or not sk or #sk == 0 then return end
  local lines, names, levels, haveLines = {}, {}, {}, false
  for _, s in ipairs(sk) do
    if s.line then lines[s.line] = true; haveLines = true end
    names[s.name] = true; levels[(s.skill or 0) .. "/" .. (s.max or 0)] = true
  end
  if not haveLines then return end
  local removed = {}
  for name, p in pairs(c.profs) do
    if p.virtual then -- добавлена вручную для отслеживания - не трогаем
    else
    local own
    if p.base then own = lines[p.base] or names[name]
    else own = names[name] or (p.line and lines[p.line]) or levels[(p.skill or 0) .. "/" .. (p.max or 0)] end -- старые записи: по имени или уровню
    if not own then c.profs[name] = nil; removed[#removed + 1] = name end
    end
  end
  if #removed > 0 then ns.say(L"убраны чужие профессии у этого персонажа: " .. table.concat(removed, ", ")); ns.Fire("RECIPES") end
end

local function scanMerchant()
  local n = safe(GetMerchantNumItems) or 0
  for i = 1, n do
    local id = safe(GetMerchantItemID, i)
    local price, stack, ext
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then local info = safe(C_MerchantFrame.GetItemInfo, i); if info then price, stack, ext = info.price, info.stackCount, info.hasExtendedCost end end
    if not price and GetMerchantItemInfo then local _, _, p, s, _, _, _, e = safe(GetMerchantItemInfo, i); price, stack, ext = p, s, e end
    if id and price and price > 0 and not ext then
      local unit = math.floor(price / math.max(stack or 1, 1) + 0.5)
      if not ns.DB.vendor[id] or unit < ns.DB.vendor[id] then ns.DB.vendor[id] = unit end
    end
  end
end

-- ---------- прибыль ----------
-- { cost, missing, sell, revenue, profit, margin, parts = { {id, n, unit, src} } }
-- stock (необязательно): { [itemID] = сколько есть в банке и сумках } — свои материалы не покупаются,
-- в себестоимость идёт только то, чего не хватает на один крафт; crafts — сколько раз хватит запаса целиком
function ns.Profit(rec, stock, mult)
  mult = math.max(1, math.floor(mult or 1)) -- порций (крафтов) сразу
  local cost, missing, parts, crafts = 0, 0, {}, nil
  for _, r in ipairs(rec.reag or {}) do
    local id, one = r[1], r[2]
    local n = one * mult
    local unit, src = ns.CostPrice(id)
    local have = stock and stock[id] or 0
    local buy = stock and math.max(0, n - have) or n
    if buy > 0 then
      if unit then cost = cost + unit * buy else missing = missing + 1 end
    end
    if stock then local k = math.floor(have / math.max(1, one)); crafts = crafts and math.min(crafts, k) or k end
    parts[#parts + 1] = { id = id, n = n, unit = unit, src = src, have = stock and have or nil, buy = buy }
  end
  local res = { cost = cost, missing = missing, parts = parts, crafts = crafts, stock = stock and true or nil, mult = mult }
  if rec.out then
    local sell = ns.AHPrice(rec.out)
    local q = ((rec.qmin or 1) + (rec.qmax or 1)) / 2 * mult
    res.sell, res.qty = sell, q
    if sell then
      res.revenue = sell * q * (1 - ns.Cut())
      if missing == 0 then
        res.profit = res.revenue - cost
        res.margin = cost > 0 and res.profit / cost * 100 or nil
      end
    end
  end
  return res
end

function ns.OpenRecipeInGame(rec, profName)
  if not rec or not C_TradeSkillUI then return end
  local function open() if C_TradeSkillUI.OpenRecipe then pcall(C_TradeSkillUI.OpenRecipe, rec.id) end end
  local shown = (ProfessionsFrame and ProfessionsFrame:IsShown()) or (TradeSkillFrame and TradeSkillFrame:IsShown())
  if shown and ns.curProf == profName then open() return end
  local p = profName and ns.DB.chars[ns.charKey].profs[profName]
  if p and p.line and C_TradeSkillUI.OpenTradeSkill then
    pcall(C_TradeSkillUI.OpenTradeSkill, p.line)
    ns.After(0.4, open); ns.After(1.2, open) -- окно открывается не мгновенно
  else
    open()
    if not shown then ns.say(L"откройте окно профессии один раз - дальше кнопка «Крафт» будет открывать его сама.") end
  end
end
function ns.IsLearned(rec) return rec.learned ~= false end
-- данные рецепта (RecipeData.lua): номер рецепта = номер заклинания; запасной путь - по названию
function ns.RecipeSourceData(rec)
  if not ns.RS or not rec then return nil end
  return ns.RS.r[rec.id] or (rec.name and ns.RS.names[rec.name] and ns.RS.r[ns.RS.names[rec.name]])
end
-- требуемый навык рецепта (из данных Wowhead) и группа: 1 Ученик, 2 Подмастерье, 3 Умелец, 4 Искусник, 5 - 300+, 9 - неизвестно
function ns.RecipeLevel(rec)
  local d = ns.RecipeSourceData and ns.RecipeSourceData(rec)
  return (d and d.s) or rec.lvl
end
local TIERS = { { 75, "Ученик: навык 1-74" }, { 150, "Подмастерье: навык 75-149" }, { 225, "Умелец: навык 150-224" }, { 300, "Искусник: навык 225-299" }, { 1e9, "Мастер: навык 300+" } }
function ns.SkillTier(lv)
  if not lv then return 9 end
  for i, t in ipairs(TIERS) do if lv < t[1] then return i end end
  return 5
end
function ns.SkillTierName(i) return i == 9 and L"Навык неизвестен" or L(TIERS[i][2]) end
-- все рецепты всех профессий текущего персонажа с прибылью (неизученные — только если попросили)
local function collect(c, profFilter, withUnlearned, stock)
  local out = {}
  for prof, p in pairs(c.profs or {}) do
    if not profFilter or prof == profFilter then
      for _, rec in ipairs(p.recipes or {}) do
        if withUnlearned or p.virtual or ns.IsLearned(rec) then -- добавленная вручную профессия - все рецепты (серым)
          local pr = ns.Profit(rec, stock)
          pr.rec, pr.prof = rec, prof
          out[#out + 1] = pr
        end
      end
    end
  end
  return out
end
-- charKey: другой персонаж — цены берутся из снимка его режима и фракции
function ns.AllRecipeProfits(profFilter, withUnlearned, charKey)
  local c = ns.DB.chars[charKey or ns.charKey]
  if not c then return {} end
  -- «Учитывать банк»: материалы из банка и сумок этого персонажа не покупаются
  local stock = ns.DB.settings.useBank and ns.Stock and ns.Stock(charKey or ns.charKey) or nil
  if charKey and charKey ~= ns.charKey and c.realmKey then return ns.WithRealm(c.realmKey, collect, c, profFilter, withUnlearned, stock) end
  return collect(c, profFilter, withUnlearned, stock)
end
-- лучшая себестоимость предмета среди изученных рецептов всех персонажей: цена за шт, рецепт, расчёт, персонаж, профессия
function ns.CraftCost(id)
  local best, bestRec, bestPr, bestCk, bestProf
  for ck, c in pairs(ns.DB.chars) do
    for pname, p in pairs(c.profs or {}) do
      for _, rec in ipairs(p.recipes or {}) do
        if rec.out == id and ns.IsLearned(rec) then
          local pr = ns.Profit(rec)
          if pr.missing == 0 then
            local unit = pr.cost / math.max(1, ((rec.qmin or 1) + (rec.qmax or 1)) / 2)
            if not best or unit < best then best, bestRec, bestPr, bestCk, bestProf = unit, rec, pr, ck, pname end
          end
        end
      end
    end
  end
  return best, bestRec, bestPr, bestCk, bestProf
end
function ns.BestCraft()
  local best
  for _, pr in ipairs(ns.AllRecipeProfits()) do if pr.profit and (not best or pr.profit > best.profit) then best = pr end end
  return best
end
-- предметы, связанные с рецептами персонажа (для истории)
function ns.RecipeItems()
  local s = {}
  local c = ns.DB.chars[ns.charKey]
  for _, p in pairs(c and c.profs or {}) do
    for _, rec in ipairs(p.recipes or {}) do
      if p.virtual or ns.IsLearned(rec) then -- история цен: изученные рецепты и профессии, добавленные для отслеживания
        if rec.out then s[rec.out] = true end
        for _, r in ipairs(rec.reag or {}) do s[r[1]] = true end
      end
    end
  end
  return s
end

local DIFF = { [0] = "|cffff8040", [1] = "|cffffff00", [2] = "|cff40c040", [3] = "|cff808080" }

-- ---------- панель рядом с окном профессии ----------
local panel, list, detail, selected
local function host() return ProfessionsFrame or TradeSkillFrame end

local function profitText(pr)
  if not pr.rec.out then return L"|cff888888чары|r" end
  if pr.profit then return (pr.profit >= 0 and "|cff78d98a+" or "|cffff7a66") .. ns.money(pr.profit, true):gsub("|r", "|r" .. (pr.profit >= 0 and "|cff78d98a" or "|cffff7a66")) .. "|r" end
  if pr.missing > 0 then return L"|cffaa8866нет цены|r" end
  return "|cff777777-|r"
end

local function refreshList()
  if not panel or not panel:IsShown() then return end
  local S = ns.DB.settings
  local rows = ns.AllRecipeProfits(ns.curProf, S.showUnlearned)
  local data = {}
  for _, pr in ipairs(rows) do
    if not S.profitOnly or (pr.profit and pr.profit > (S.minProfit or 0)) then data[#data + 1] = pr end
  end
  local key = panel.sortKey or "profit"
  table.sort(data, function(a, b)
    local x, y = a[key] or -1e12, b[key] or -1e12
    if x == y then return (a.rec.name or "") < (b.rec.name or "") end
    return x > y
  end)
  list:SetData(data)
  list.empty:SetText(#rows == 0 and L"Рецепты появятся после открытия окна профессии." or L"Нет рецептов под фильтр.\nСнимите «только прибыльные» или обновите цены: окно аукциона > «Сканировать».")
  local scan = ns.CurrentScan()
  local status = scan and (L"Цены: снимок " .. ns.ago(scan.t)) or L"|cffff9966Цен нет - откройте аукцион и нажмите «Сканировать».|r"
  if S.showUnlearned then
    local un = 0
    for _, pr in ipairs(rows) do if not ns.IsLearned(pr.rec) then un = un + 1 end end
    status = status .. (un > 0 and (L"  |cffaaaaaa/ неизученных: " .. un .. "|r") or L"  |cffff9966/ игра не прислала неизученные|r")
  end
  panel.status:SetText(status)
end

local function fillDetail(rec)
  if not detail then return end
  selected = rec
  for _, r in ipairs(detail.rows) do r:Hide() end
  if not rec then detail.title:SetText(L"Выберите рецепт"); detail.total:SetText("") return end
  local pr = ns.Profit(rec)
  pr.rec = rec
  local learned = ns.IsLearned(rec)
  detail.title:SetText((learned and (DIFF[rec.diff] or "|cffffffff") or "|cff9d9d9d") .. rec.name .. "|r" .. (learned and "" or L"  |cffff9966(не изучен)|r"))

  local items = {}
  if rec.out then items[#items + 1] = { id = rec.out, n = pr.qty or 1, unit = pr.sell, out = true } end
  for _, p in ipairs(pr.parts) do items[#items + 1] = p end
  for i, it in ipairs(items) do
    local r = detail.rows[i]
    if not r then break end
    r.id = it.id
    r.icon:SetTexture(ns.itemIcon(it.id))
    r.name:SetText((it.out and "|cffe6b450> |r" or "") .. ns.itemLinkText(it.id) .. (it.n ~= 1 and (" |cffaaaaaa×" .. it.n .. "|r") or ""))
    r.price:SetText(it.unit and ns.money(it.unit * (it.out and 1 or it.n), true) or L"|cffaa8866нет цены|r")
    r.star:SetIcon(ns.IsMarked(it.id) and "star-on" or "star-off")
    r.search:SetEnabled(ns.AHIsOpen()); r.search:SetAlpha(ns.AHIsOpen() and 1 or 0.35)
    r:Show()
  end
  local lines = { L"Себестоимость: " .. (pr.missing > 0 and (">= " .. ns.money(pr.cost)) or ns.money(pr.cost)) }
  if pr.revenue then lines[#lines + 1] = L"Доход" .. " (-" .. ns.CutPct() .. "): " .. ns.money(pr.revenue) end
  if pr.profit then lines[#lines + 1] = L"Прибыль: " .. profitText(pr) .. (pr.margin and ("  |cffaaaaaa(" .. math.floor(pr.margin) .. "%)|r") or "") end
  detail.total:SetText(table.concat(lines, "\n"))
end
ns.FillRecipeDetail = fillDetail

-- В окне профессии игры аддон ничего не меняет (чтобы не мешать другим аддонам) - только кнопка
-- «Открыть в WolfichMarket»: главное окно, раздел «Профессии», выбранный в игре рецепт.
local built = false
local currentRecipe -- рецепт, выбранный в окне профессии игры
local function build()
  local h = host()
  if built or not h then return end
  built = true
  local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
  local form = page and page.SchematicForm
  local b = UI.Button(form or h, L"Открыть в WolfichMarket", 190, 18, function()
    if ns.OpenRecipeInMain then ns.OpenRecipeInMain(currentRecipe) elseif ns.ToggleMain then ns.ToggleMain() end
  end)
  b:FitWidth(170, 240)
  if form then b:SetPoint("BOTTOMLEFT", form, "BOTTOMLEFT", 24, 14) else b:SetPoint("TOPRIGHT", h, "TOPRIGHT", -36, -30) end
  b:SetFrameLevel(((form or h):GetFrameLevel() or 1) + 20)
  b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(L"Себестоимость, прибыль на Ф и Общ и график этого рецепта - в окне WolfichMarket.", 1, 1, 1, true); GameTooltip:Show() end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  ns._openInMainBtn = b
end

-- ---------- прибыль прямо на строках списка рецептов игры ----------
local recipeIndex = {}
local indexDirty = true
function ns.MarkProfitDirty() indexDirty = true end
local function indexRecipes()
  if not indexDirty then return end
  indexDirty = false
  wipe(recipeIndex)
  for _, pr in ipairs(ns.AllRecipeProfits(ns.curProf, ns.DB.settings.showUnlearned)) do recipeIndex[pr.rec.id] = pr end
end
-- ---------- два аукциона: Ф - фракционный, Общ - общий ----------
local KINDS = { "main", "neutral" }
-- выгода рецепта на каждом аукционе: { main = прибыль, neutral = ... }, лучший аукцион
function ns.ProfitByKind(rec)
  local res, best = {}, nil
  for _, k in ipairs(KINDS) do
    local p = ns.ProfitIn(rec, k)
    res[k] = p
    if p and (not best or p > res[best]) then best = k end
  end
  return res, best
end
local function recFromInfo(ri)
  if not ri then return end
  indexRecipes()
  local pr = recipeIndex[ri.recipeID]
  if pr then return pr.rec end
  for _, c in pairs(ns.DB.chars or {}) do for _, p in pairs(c.profs or {}) do for _, r in ipairs(p.recipes or {}) do if r.id == ri.recipeID then return r end end end end
end
local formHooked = false
local function hookForm()
  if formHooked then return end
  local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
  local form = page and page.SchematicForm
  if not form or not form.Init then return end
  formHooked = true
  -- после показа рецепта игрой - только запомнить его (окно игры не трогаем)
  pcall(hooksecurefunc, form, "Init", function(self, recipeInfo) currentRecipe = recFromInfo(recipeInfo) end)
  if form.GetRecipeInfo then currentRecipe = recFromInfo(form:GetRecipeInfo()) end
end
-- раньше здесь были столбики Ф / Общ на строках списка игры - теперь окно игры не меняется
function ns.DecorateRecipeRows() end
local function hookRows()
  ns._hookRowsCalled = true
  hookForm()
end
ns._hookRows = hookRows
ns._currentRecipe = function() return currentRecipe end -- для автотестов

-- ---------- события ----------
local timer
-- Рецепты читаются из игры только если профессия ещё не сохранена или с прошлого чтения
-- был новый снимок аукциона. В остальное время — только пересчёт прибыли по сохранённым рецептам.
local function recipesStale()
  local prof, skill, maxSkill = professionInfo()
  if not prof or not ns.charKey then return false end
  local p = ns.DB.chars[ns.charKey].profs[prof]
  if not p or p.virtual or not p.recipes or #p.recipes == 0 or not p.line then return true end -- профессию выучили - заменить «отслеживаемую» настоящей -- line: номер профессии для кнопки «Крафт»
  -- выучены новые рецепты - перечитать всё; вырос только навык (крафт поднял уровень) - без полного чтения:
  -- обновить уровень и цвет сложности рецептов (полное чтение каждой профессии после каждого крафта подвешивало игру)
  local ids = C_TradeSkillUI and safe(C_TradeSkillUI.GetAllRecipeIDs)
  if ids and #ids > 0 then
    local learned, known = 0, 0
    local infos = {}
    for _, r in ipairs(p.recipes) do if r.learned ~= false then learned = learned + 1 end end
    for _, rid in ipairs(ids) do
      local ri = safe(C_TradeSkillUI.GetRecipeInfo, rid)
      if ri and ri.learned and not ri.isDummyRecipe then known = known + 1 end
      if ri then infos[rid] = ri end
    end
    if known ~= learned then return true end
    if (skill and skill ~= (p.skill or 0)) or (maxSkill and maxSkill ~= (p.max or 0)) then
      p.skill, p.max = skill or p.skill, maxSkill or p.max
      for _, r in ipairs(p.recipes) do local ri = infos[r.id]; if ri then r.diff = ri.relativeDifficulty end end
      ns.MarkProfitDirty()
    end
  elseif (skill and skill ~= (p.skill or 0)) or (maxSkill and maxSkill ~= (p.max or 0)) then return true end
  local scan = ns.CurrentScan()
  return scan and (p.t or 0) < scan.t or false
end
local function onTradeSkill()
  if timer then timer:Cancel() end
  local run = function()
    local prof = professionInfo()
    if prof then ns.curProf = prof end
    if recipesStale() then ns.ScanProfession() end
    build(); hookRows()
    if panel and panel:IsShown() then refreshList() end
    ns.DecorateRecipeRows()
  end
  timer = C_Timer and C_Timer.NewTimer and C_Timer.NewTimer(0.6, run)
  if not timer then run() end
end
ns.On("TRADE_SKILL_SHOW", onTradeSkill)
ns.On("TRADE_SKILL_DATA_SOURCE_CHANGED", onTradeSkill)
-- выучили рецепт или вырос навык при открытом окне - перечитать (с задержкой, событий бывает много подряд)
local relearn
local function onLearn()
  if relearn then return end
  relearn = true
  ns.After(1.5, function()
    relearn = false
    local h = host()
    if h and h:IsShown() and recipesStale() then ns.ScanProfession(); ns.DecorateRecipeRows() end
  end)
end
ns.On("NEW_RECIPE_LEARNED", onLearn)
ns.On("TRADE_SKILL_LIST_UPDATE", onLearn)
ns.On("SKILL_LINES_CHANGED", onLearn)
-- снимок аукциона готов, а окно профессии открыто — перечитать рецепты сразу
ns.Listen("SCAN_DONE", function()
  local h = host()
  if h and h:IsShown() and recipesStale() then ns.ScanProfession() end
end)
ns.On("MERCHANT_SHOW", scanMerchant)
ns.On("SKILL_LINES_CHANGED", function() ns.ScanSkills() end)
ns.Listen("LOGIN", function() ns.ScanSkills(); ns.After(4, function() ns.ScanSkills(); ns.CleanStrangers() end) end)
local function refreshAll() if panel and panel:IsShown() then refreshList(); fillDetail(selected) end; ns.DecorateRecipeRows() end
ns.Listen("PRICES", function() indexDirty = true; refreshAll() end)
ns.Listen("INVENTORY", function() if ns.DB.settings.useBank then indexDirty = true end end)
ns.Listen("MARKS", function() if panel and panel:IsShown() then list:Refresh(); fillDetail(selected) end end)
ns.Listen("RECIPES", function() indexDirty = true; if panel and panel:IsShown() then refreshList() end end)
ns.Listen("AH_STATE", function() if panel and panel:IsShown() then fillDetail(selected) end end)
ns.Listen("NAMES", function() if panel and panel:IsShown() then list:Refresh() end end)

-- ---------- профессии, которых у персонажа нет: добавить для отслеживания (все рецепты - неизученные, серым) ----------
function ns.AllProfessions()
  local out = {}
  for slug, p in pairs(ns.RS and ns.RS.prof or {}) do out[#out + 1] = { slug = slug, name = (ns.Lang() == "ru" and p.ru ~= "" and p.ru) or p.en } end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end
function ns.AddVirtualProfession(charKey, slug)
  local P = ns.RS and ns.RS.prof[slug]
  local c = ns.DB.chars[charKey]
  if not P or not c then return end
  c.profs = c.profs or {}
  local name = (ns.Lang() == "ru" and P.ru ~= "" and P.ru) or P.en
  if c.profs[name] and not c.profs[name].virtual then ns.say(L"эта профессия у персонажа уже есть: " .. name) return name end
  local recipes = {}
  for _, id in ipairs(P.ids) do
    local d = ns.RS.r[id]
    if d and not d.na then
      local rec = { id = id, name = (ns.Lang() == "ru" and d.n and d.n[1] ~= "" and d.n[1]) or (d.n and d.n[2]) or ("#" .. id), learned = false, lvl = d.s, reag = {} }
      if d.cr then rec.out, rec.qmin, rec.qmax = d.cr[1], d.cr[2], d.cr[3]; ns.itemName(d.cr[1]) end
      for _, r in ipairs(d.rg or {}) do rec.reag[#rec.reag + 1] = { r[1], r[2] } end
      recipes[#recipes + 1] = rec
    end
  end
  c.profs[name] = { virtual = true, skill = 0, max = 0, t = time(), recipes = recipes, line = P.line }
  ns.say(string.format(L"профессия добавлена для отслеживания: %s (%d рецептов)", name, #recipes))
  ns.Fire("RECIPES")
  return name
end
