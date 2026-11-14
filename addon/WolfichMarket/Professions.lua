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
    local own
    if p.base then own = lines[p.base] or names[name]
    else own = names[name] or (p.line and lines[p.line]) or levels[(p.skill or 0) .. "/" .. (p.max or 0)] end -- старые записи: по имени или уровню
    if not own then c.profs[name] = nil; removed[#removed + 1] = name end
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
function ns.Profit(rec)
  local cost, missing, parts = 0, 0, {}
  for _, r in ipairs(rec.reag or {}) do
    local id, n = r[1], r[2]
    local unit, src = ns.CostPrice(id)
    if unit then cost = cost + unit * n else missing = missing + 1 end
    parts[#parts + 1] = { id = id, n = n, unit = unit, src = src }
  end
  local res = { cost = cost, missing = missing, parts = parts }
  if rec.out then
    local sell = ns.AHPrice(rec.out)
    local q = ((rec.qmin or 1) + (rec.qmax or 1)) / 2
    res.sell, res.qty = sell, q
    if sell then
      res.revenue = sell * q * (1 - ns.AH_CUT)
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
-- все рецепты всех профессий текущего персонажа с прибылью (неизученные — только если попросили)
local function collect(c, profFilter, withUnlearned)
  local out = {}
  for prof, p in pairs(c.profs or {}) do
    if not profFilter or prof == profFilter then
      for _, rec in ipairs(p.recipes or {}) do
        if withUnlearned or ns.IsLearned(rec) then
          local pr = ns.Profit(rec)
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
  if charKey and charKey ~= ns.charKey and c.realmKey then return ns.WithRealm(c.realmKey, collect, c, profFilter, withUnlearned) end
  return collect(c, profFilter, withUnlearned)
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
      if ns.IsLearned(rec) then -- для истории цен берём только изученные рецепты
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
  if pr.revenue then lines[#lines + 1] = L"Доход (-5%): " .. ns.money(pr.revenue) end
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
local function decorate(frame)
  if not frame or not frame.GetElementData then return end
  local node = frame:GetElementData()
  local data = node and node.GetData and node:GetData()
  local ri = data and data.recipeInfo
  if not frame.wmProfit then
    frame.wmProfit = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.wmProfit:SetPoint("RIGHT", frame, "RIGHT", -6, 0)
  end
  local pr = ri and recipeIndex[ri.recipeID]
  if pr and pr.rec.out then
    frame.wmProfit:SetText(profitText(pr)); frame.wmProfit:Show()
    frame:SetAlpha(ns.DB.settings.profitOnly and not (pr.profit and pr.profit > 0) and 0.35 or 1)
  else
    frame.wmProfit:Hide(); frame:SetAlpha(ri and ns.DB.settings.profitOnly and 0.35 or 1)
  end
end
function ns.DecorateRecipeRows()
  local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
  local sb = page and page.RecipeList and page.RecipeList.ScrollBox
  if not sb or not sb.ForEachFrame then return end
  indexRecipes()
  pcall(sb.ForEachFrame, sb, decorate)
end
local hooked = false
local function hookRows()
  if hooked then return end
  local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
  local sb = page and page.RecipeList and page.RecipeList.ScrollBox
  if not sb then return end
  hooked = true
  if ScrollUtil and ScrollUtil.AddInitializedFrameCallback then
    pcall(ScrollUtil.AddInitializedFrameCallback, sb, function(_, frame) decorate(frame) end, panel or sb, true)
  end
  if sb.Update then pcall(hooksecurefunc, sb, "Update", function() ns.DecorateRecipeRows() end) end
end

-- ---------- события ----------
local timer
-- Рецепты читаются из игры только если профессия ещё не сохранена или с прошлого чтения
-- был новый снимок аукциона. В остальное время — только пересчёт прибыли по сохранённым рецептам.
local function recipesStale()
  local prof = professionInfo()
  if not prof or not ns.charKey then return false end
  local p = ns.DB.chars[ns.charKey].profs[prof]
  if not p or not p.recipes or #p.recipes == 0 or not p.line then return true end -- line: номер профессии для кнопки «Крафт»
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
ns.Listen("MARKS", function() if panel and panel:IsShown() then list:Refresh(); fillDetail(selected) end end)
ns.Listen("RECIPES", function() indexDirty = true; if panel and panel:IsShown() then refreshList() end end)
ns.Listen("AH_STATE", function() if panel and panel:IsShown() then fillDetail(selected) end end)
ns.Listen("NAMES", function() if panel and panel:IsShown() then list:Refresh() end end)
