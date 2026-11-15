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
function ns.CraftCost(id)
  local best, bestRec, bestPr
  for _, c in pairs(ns.DB.chars) do
    for _, p in pairs(c.profs or {}) do
      for _, rec in ipairs(p.recipes or {}) do
        if rec.out == id and ns.IsLearned(rec) then
          local pr = ns.Profit(rec)
          if pr.missing == 0 then
            local unit = pr.cost / math.max(1, ((rec.qmin or 1) + (rec.qmax or 1)) / 2)
            if not best or unit < best then best, bestRec, bestPr = unit, rec, pr end
          end
        end
      end
    end
  end
  return best, bestRec, bestPr
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

-- Отдельной панели у окна профессии больше нет: всё — в главном окне WolfichMarket.
-- На окне профессии остаются суммы прибыли на строках и кнопка-лапа, открывающая главное окно.
local built = false
local function build()
  local h = host()
  if built or not h then return end
  built = true
  local tg = UI.Icon(h, "paw", 22, L"WolfichMarket: прибыль крафта", function() if ns.ToggleMain then ns.ToggleMain() end end)
  tg:SetPoint("TOPRIGHT", h, "TOPRIGHT", -28, -2); tg:SetFrameLevel(h:GetFrameLevel() + 20)
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
local KSHORT = { main = L"Ф", neutral = L"Общ" }
local NK = #KINDS
local COLW = 40
local COLR = -24 -- столбики левее правого края: там у заголовков групп кнопка «свернуть»
-- короткая сумма: золото, а меньше золотого - серебро
local function short(c)
  local a = math.abs(c)
  local t = a >= 10000 and (math.floor(a / 10000) .. L"з") or a >= 100 and (math.floor(a / 100) .. L"с") or (math.floor(a) .. L"м")
  return (c >= 0 and "+" or "-") .. t
end
-- выгода рецепта на каждом аукционе: { main = прибыль, neutral = ..., bm = ... }, лучший аукцион
function ns.ProfitByKind(rec)
  local res, best = {}, nil
  for _, k in ipairs(KINDS) do
    local p = ns.ProfitIn(rec, k)
    res[k] = p
    if p and (not best or p > res[best]) then best = k end
  end
  return res, best
end
local function decorate(frame)
  if not frame or not frame.GetElementData then return end
  local node = frame:GetElementData()
  local data = node and node.GetData and node:GetData()
  local ri = data and data.recipeInfo
  if not frame.wmCols then
    frame.wmCols = {}
    for i, k in ipairs(KINDS) do
      local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      fs:SetPoint("RIGHT", frame, "RIGHT", COLR - (NK - i) * COLW, 0); fs:SetWidth(COLW); fs:SetJustifyH("RIGHT")
      frame.wmCols[k] = fs
    end
    -- название рецепта не должно залезать под столбики
    if type(frame.Label) == "table" and frame.Label.SetPoint then pcall(frame.Label.SetPoint, frame.Label, "RIGHT", frame, "RIGHT", COLR - NK * COLW, 0) end
  end
  local pr = ri and recipeIndex[ri.recipeID]
  if pr and pr.rec.out then
    local by, best = ns.ProfitByKind(pr.rec)
    for _, k in ipairs(KINDS) do
      local v = by[k]
      local fs = frame.wmCols[k]
      if v then
        -- лучший аукцион - ярко, остальные - приглушённо
        local col = v >= 0 and (k == best and "|cff5dff7a" or "|cff4f9a5c") or (k == best and "|cffff7a66" or "|cff9a5a52")
        fs:SetText(col .. short(v) .. "|r")
      else fs:SetText("|cff555555-|r") end
      fs:Show()
    end
    frame:SetAlpha(ns.DB.settings.profitOnly and not (pr.profit and pr.profit > 0) and 0.35 or 1)
  elseif data and data.categoryInfo then
    -- заголовок группы рецептов: подписи столбиков ровно над цифрами
    for _, k in ipairs(KINDS) do frame.wmCols[k]:SetText(ns.ALT_COLOR[k] .. KSHORT[k] .. "|r"); frame.wmCols[k]:Show() end
    frame:SetAlpha(1)
  else
    for _, fs in pairs(frame.wmCols) do fs:Hide() end
    frame:SetAlpha(ri and ns.DB.settings.profitOnly and 0.35 or 1)
  end
end
ns._decorateRow = decorate

-- ---------- таблица цен под реагентами в окне профессии ----------
-- для каждого материала - цена на обоих аукционах и у торговца (дешевле - зелёным),
-- для результата - продажа на обоих аукционах (дороже - золотым), внизу - где купить и где продать
function ns.RecipeMarket(rec)
  local rows = {}
  for _, r in ipairs(rec.reag or {}) do
    local row = { id = r[1], n = r[2], p = {} }
    for _, k in ipairs(KINDS) do row.p[k] = ns.PriceIn(k, r[1]) end
    row.vendor = ns.DB.vendor[r[1]]
    row.best, row.bestKind = ns.BestBuy(r[1])
    rows[#rows + 1] = row
  end
  local out
  if rec.out then
    out = { id = rec.out, q = ((rec.qmin or 1) + (rec.qmax or 1)) / 2, p = {} }
    for _, k in ipairs(KINDS) do out.p[k] = ns.PriceIn(k, rec.out) end
  end
  local by, best = ns.ProfitByKind(rec)
  return { rows = rows, out = out, profit = by, best = best }
end
local mt
local function buildMarketTable(form)
  mt = CreateFrame("Frame", nil, form)
  ns._marketTable = mt
  -- сразу под списком реагентов игры, чтобы не налезать на него; высота - по числу строк
  local reag = type(form.Reagents) == "table" and form.Reagents.GetBottom and form.Reagents or nil
  if reag then mt:SetPoint("TOPLEFT", reag, "BOTTOMLEFT", 0, -8); mt:SetPoint("RIGHT", form, "RIGHT", -26, 0)
  else mt:SetPoint("BOTTOMLEFT", form, "BOTTOMLEFT", 26, 46); mt:SetPoint("BOTTOMRIGHT", form, "BOTTOMRIGHT", -26, 46) end
  mt.anchoredTop = reag ~= nil
  mt:SetHeight(160)
  mt.bg = mt:CreateTexture(nil, "BACKGROUND"); mt.bg:SetAllPoints(); mt.bg:SetColorTexture(0, 0, 0, 0.45)
  mt.title = mt:CreateFontString(nil, "OVERLAY", "GameFontNormal"); mt.title:SetPoint("TOPLEFT", 8, -6); mt.title:SetText(L"Где купить и где продать")
  -- «В план»: +1 порция этого рецепта в план закупки (список покупок - во вкладке «План» у аукциониста)
  mt.plan = UI.Button(mt, L"В план", 76, 18, function()
    local rec = mt.rec
    if not rec then return end
    local cur = 0
    for _, p in ipairs(ns.Plans()) do if p.id == rec.id and p.ck == ns.charKey then cur = p.n end end
    ns.AddPlan(rec, ns.charKey, ns.curProf, cur + 1)
  end)
  mt.plan:SetPoint("LEFT", mt.title, "RIGHT", 10, 0)
  mt.plan:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(L"Добавить в план закупки", 1, 0.82, 0)
    GameTooltip:AddLine(L"Каждый клик - ещё одна порция. Список покупок - во вкладке «План» у аукциониста.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  mt.plan:SetScript("OnLeave", function() GameTooltip:Hide() end)
  mt.cols = {}
  local colX = { main = -72, neutral = -14 }
  mt.colX = colX
  for _, k in ipairs(KINDS) do
    local h = mt:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); h:SetPoint("TOPRIGHT", mt, "TOPRIGHT", colX[k], -8); h:SetWidth(56); h:SetJustifyH("RIGHT")
    h:SetText(ns.ALT_COLOR[k] .. KSHORT[k] .. "|r")
  end
  mt.lines = {}
  for i = 1, 9 do
    local ln = {}
    ln.icon = mt:CreateTexture(nil, "ARTWORK"); ln.icon:SetSize(14, 14); ln.icon:SetPoint("TOPLEFT", 8, -8 - i * 15)
    ln.name = mt:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); ln.name:SetPoint("LEFT", ln.icon, "RIGHT", 4, 0); ln.name:SetPoint("RIGHT", mt, "RIGHT", -196, 0); ln.name:SetJustifyH("LEFT"); ln.name:SetWordWrap(false)
    ln.p = {}
    for _, k in ipairs(KINDS) do
      local fs = mt:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); fs:SetPoint("RIGHT", mt, "TOPRIGHT", colX[k], -15 - i * 15); fs:SetWidth(56); fs:SetJustifyH("RIGHT")
      ln.p[k] = fs
    end
    mt.lines[i] = ln
  end
  mt.foot = mt:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); mt.foot:SetPoint("BOTTOMLEFT", 8, 6); mt.foot:SetPoint("BOTTOMRIGHT", -8, 6); mt.foot:SetJustifyH("LEFT"); mt.foot:SetWordWrap(true)
end
local function sm(c) return c and ns.money(c, true) or nil end
local function fillMarketTable(rec)
  if not mt then return end
  for _, ln in ipairs(mt.lines) do ln.icon:Hide(); ln.name:SetText(""); for _, fs in pairs(ln.p) do fs:SetText("") end end
  if not rec then mt:Hide() return end
  mt.rec = rec
  local inPlan = 0
  for _, p in ipairs(ns.Plans()) do if p.id == rec.id and p.ck == ns.charKey then inPlan = p.n end end
  mt.plan:SetLabel(inPlan > 0 and (L"В плане" .. " ×" .. inPlan) or L"В план"); mt.plan:SetGold(inPlan > 0)
  local M = ns.RecipeMarket(rec)
  local i = 0
  for _, r in ipairs(M.rows) do
    i = i + 1; local ln = mt.lines[i]; if not ln then break end
    ln.icon:SetTexture(ns.itemIcon(r.id)); ln.icon:Show()
    ln.name:SetText(ns.itemName(r.id) .. (r.n ~= 1 and (" |cffaaaaaa×" .. r.n .. "|r") or "") .. (r.bestKind == "vendor" and L" |cffaaaaaa(торговец " .. sm(r.vendor * r.n) .. ")|r" or ""))
    for _, k in ipairs(KINDS) do
      local p = r.p[k]
      ln.p[k]:SetText(p and ((r.bestKind == k and "|cff5dff7a" or "|cff9a9a9a") .. sm(p * r.n) .. "|r") or "|cff555555-|r")
    end
  end
  if M.out then
    i = i + 1; local ln = mt.lines[i]
    if ln then
      ln.icon:SetTexture(ns.itemIcon(M.out.id)); ln.icon:Show()
      ln.name:SetText("|cffe6b450" .. L"Продажа: " .. "|r" .. ns.itemName(M.out.id) .. (M.out.q ~= 1 and (" |cffaaaaaa×" .. M.out.q .. "|r") or ""))
      local bestSell
      for _, k in ipairs(KINDS) do local p = M.out.p[k]; if p and (not bestSell or p > M.out.p[bestSell]) then bestSell = k end end
      for _, k in ipairs(KINDS) do
        local p = M.out.p[k]
        ln.p[k]:SetText(p and ((k == bestSell and "|cffffd100" or "|cff9a9a9a") .. sm(p * M.out.q) .. "|r") or "|cff555555-|r")
      end
    end
    i = i + 1; local pl = mt.lines[i]
    if pl then
      pl.name:SetText("|cffe6b450" .. L"Прибыль" .. "|r |cff888888" .. L"(комиссия Ф 5%, Общ 15%)" .. "|r")
      for _, k in ipairs(KINDS) do
        local v = M.profit[k]
        pl.p[k]:SetText(v and ((v >= 0 and (k == M.best and "|cff5dff7a" or "|cff4f9a5c") or "|cffff7a66") .. short(v) .. "|r") or "|cff555555-|r")
      end
    end
  end
  -- итог словами
  local buyAt = {}
  for _, r in ipairs(M.rows) do
    local w = r.bestKind == "vendor" and L"торговец" or r.bestKind and KSHORT[r.bestKind]
    if w then buyAt[w] = (buyAt[w] or 0) + 1 end
  end
  local parts = {}
  for w, n in pairs(buyAt) do parts[#parts + 1] = w .. (n > 1 and (" ×" .. n) or "") end
  table.sort(parts)
  mt:SetHeight(26 + i * 15 + 34)
  mt.foot:SetText((#parts > 0 and (L"Материалы дешевле: " .. table.concat(parts, ", ")) or L"|cffaa8866Нет цен материалов|r")
    .. (M.best and ("\n" .. L"Продать выгоднее: " .. ns.ALT_COLOR[M.best] .. ns.AltName(M.best) .. "|r, " .. L"прибыль " .. short(M.profit[M.best])) or ""))
  mt:Show()
end
ns._fillMarketTable = fillMarketTable
ns._marketTable = nil
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
  buildMarketTable(form)
  pcall(hooksecurefunc, form, "Init", function(self, recipeInfo) fillMarketTable(recFromInfo(recipeInfo)) end)
  if form.GetRecipeInfo then fillMarketTable(recFromInfo(form:GetRecipeInfo())) end
end
ns.Listen("PLAN", function() if mt and mt:IsVisible() and mt.rec then fillMarketTable(mt.rec) end end)
ns.Listen("PRICES", function()
  local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
  local form = page and page.SchematicForm
  if mt and mt:IsVisible() and form and form.GetRecipeInfo then fillMarketTable(recFromInfo(form:GetRecipeInfo())) end
end)
function ns.DecorateRecipeRows()
  local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
  local sb = page and page.RecipeList and page.RecipeList.ScrollBox
  if not sb or not sb.ForEachFrame then return end
  indexRecipes()
  pcall(sb.ForEachFrame, sb, decorate)
end
local hooked = false
local function hookRows()
  ns._hookRowsCalled = true
  if hooked then return end
  local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
  local sb = page and page.RecipeList and page.RecipeList.ScrollBox
  if not sb then return end
  hooked = true
  if ScrollUtil and ScrollUtil.AddInitializedFrameCallback then
    pcall(ScrollUtil.AddInitializedFrameCallback, sb, function(_, frame) decorate(frame) end, panel or sb, true)
  end
  if sb.Update then pcall(hooksecurefunc, sb, "Update", function() ns.DecorateRecipeRows() end) end
  hookForm()
end
ns._hookRows = hookRows

-- ---------- события ----------
local timer
-- Рецепты читаются из игры только если профессия ещё не сохранена или с прошлого чтения
-- был новый снимок аукциона. В остальное время — только пересчёт прибыли по сохранённым рецептам.
local function recipesStale()
  local prof, skill, maxSkill = professionInfo()
  if not prof or not ns.charKey then return false end
  local p = ns.DB.chars[ns.charKey].profs[prof]
  if not p or p.virtual or not p.recipes or #p.recipes == 0 or not p.line then return true end -- профессию выучили - заменить «отслеживаемую» настоящей -- line: номер профессии для кнопки «Крафт»
  -- вырос навык или открылась следующая ступень (225 -> 300), выучены новые рецепты - перечитать
  if (skill and skill ~= (p.skill or 0)) or (maxSkill and maxSkill ~= (p.max or 0)) then return true end
  local ids = C_TradeSkillUI and safe(C_TradeSkillUI.GetAllRecipeIDs)
  if ids and #ids > 0 then
    local learned, known = 0, 0
    for _, r in ipairs(p.recipes) do if r.learned ~= false then learned = learned + 1 end end
    for _, rid in ipairs(ids) do local ri = safe(C_TradeSkillUI.GetRecipeInfo, rid); if ri and ri.learned and not ri.isDummyRecipe then known = known + 1 end end
    if known ~= learned then return true end
  end
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
