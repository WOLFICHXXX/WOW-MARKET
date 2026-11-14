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
  if info and info.professionName and info.professionName ~= "" then return info.professionName, info.skillLevel or 0, info.maxSkillLevel or 0 end
end
local function isForeign()
  if not C_TradeSkillUI then return true end
  return safe(C_TradeSkillUI.IsTradeSkillLinked) or safe(C_TradeSkillUI.IsTradeSkillGuild) or safe(C_TradeSkillUI.IsNPCCrafting) or false
end

ns.curProf = nil
function ns.ScanProfession()
  if not ns.DB or not ns.charKey or not C_TradeSkillUI or isForeign() then return end
  local prof, skill, maxSkill = professionInfo()
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
  local c = ns.DB.chars[ns.charKey]
  c.profs[prof] = { skill = skill, max = maxSkill, t = time(), recipes = recipes }
  ns.curProf = prof
  ns.Fire("RECIPES")
end

function ns.ScanSkills()
  if not GetProfessions or not GetProfessionInfo or not ns.charKey then return end
  local list = { safe(GetProfessions) }
  local out = {}
  for i = 1, 6 do
    local idx = list[i]
    if idx then local name, _, rank, maxRank = safe(GetProfessionInfo, idx); if name then out[#out + 1] = { name = clean(name), skill = rank or 0, max = maxRank or 0 } end end
  end
  ns.DB.chars[ns.charKey].skills = out
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

local function build()
  local h = host()
  if panel or not h then return end
  panel = CreateFrame("Frame", "WolfichMarketProfPanel", h)
  panel:SetWidth(330)
  -- справа у окна профессий вертикальные вкладки профессий: отступаем, чтобы их не закрывать
  panel:SetPoint("TOPLEFT", h, "TOPRIGHT", 64, 0); panel:SetPoint("BOTTOMLEFT", h, "BOTTOMRIGHT", 64, 0)
  panel:SetFrameStrata(h:GetFrameStrata()); panel:EnableMouse(true)
  UI.Skin(panel)
  UI.Title(panel, L"Прибыль крафта")
  panel.status = UI.Font(panel, 10, UI.DIM); panel.status:SetPoint("TOPLEFT", 14, -44); panel.status:SetPoint("RIGHT", -12, 0)
  local S = ns.DB.settings
  local chk = UI.Check(panel, L"только прибыльные", function() return S.profitOnly end, function(v) S.profitOnly = v; refreshList(); ns.DecorateRecipeRows() end)
  chk:SetPoint("TOPLEFT", 10, -58)
  local chk2 = UI.Check(panel, L"включая неизученные рецепты", function() return S.showUnlearned end, function(v) S.showUnlearned = v; ns.Fire("RECIPES"); ns.DecorateRecipeRows() end)
  chk2:SetPoint("TOPLEFT", 10, -80)
  local bP = UI.Button(panel, L"по прибыли", 84, 20, function() panel.sortKey = "profit"; refreshList() end); bP:SetPoint("TOPRIGHT", -102, -60)
  local bM = UI.Button(panel, L"по марже", 84, 20, function() panel.sortKey = "margin"; refreshList() end); bM:SetPoint("TOPRIGHT", -14, -60)

  list = UI.List(panel, 22, function(r)
    r.star = UI.Icon(r, "star-off", 14, L"Отметить: уведомления о скачках цены", function(self) local d = self:GetParent().data; if d and d.rec.out then ns.ToggleMark(d.rec.out) end end)
    r.star:SetPoint("LEFT", 4, 0)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(18, 18); r.icon:SetPoint("LEFT", r.star, "RIGHT", 4, 0)
    r.name = UI.Font(r, 11); r.name:SetPoint("LEFT", r.icon, "RIGHT", 5, 0); r.name:SetPoint("RIGHT", -86, 0)
    r.val = UI.Font(r, 11); r.val:SetPoint("RIGHT", -4, 0); r.val:SetJustifyH("RIGHT")
    r:SetScript("OnClick", function(self)
      local d = self.data; if not d then return end
      if C_TradeSkillUI and C_TradeSkillUI.OpenRecipe then pcall(C_TradeSkillUI.OpenRecipe, d.rec.id) end
      fillDetail(d.rec)
    end)
  end, function(r, d)
    r.star:SetIcon(d.rec.out and ns.IsMarked(d.rec.out) and "star-on" or "star-off"); r.star:SetShown(d.rec.out ~= nil)
    r.icon:SetTexture(d.rec.out and ns.itemIcon(d.rec.out) or d.rec.icon or 134400)
    local learned = ns.IsLearned(d.rec)
    r.icon:SetDesaturated(not learned)
    r.name:SetText(learned and ((DIFF[d.rec.diff] or "|cffffffff") .. d.rec.name .. "|r") or ("|cff9d9d9d" .. d.rec.name .. L" |cffff9966(не изучен)|r"))
    r.val:SetText(profitText(d))
  end)
  list:SetPoint("TOPLEFT", 10, -106); list:SetPoint("RIGHT", -10, 0); list:SetPoint("BOTTOM", panel, "BOTTOM", 0, 272)

  -- карточка выбранного рецепта
  detail = CreateFrame("Frame", nil, panel)
  detail:SetPoint("BOTTOMLEFT", 10, 10); detail:SetPoint("BOTTOMRIGHT", -10, 10); detail:SetHeight(256)
  local dbg = detail:CreateTexture(nil, "BACKGROUND"); dbg:SetAllPoints(); dbg:SetColorTexture(0, 0, 0, 0.3)
  local line = detail:CreateTexture(nil, "BORDER"); line:SetPoint("TOPLEFT"); line:SetPoint("TOPRIGHT"); line:SetHeight(1); line:SetColorTexture(0.85, 0.66, 0.32, 0.6)
  detail.title = UI.Font(detail, 12, UI.GOLD, "OVERLAY", "OUTLINE"); detail.title:SetPoint("TOPLEFT", 8, -7); detail.title:SetPoint("RIGHT", -8, 0)
  detail.rows = {}
  for i = 1, 7 do
    local r = CreateFrame("Frame", nil, detail); r:SetHeight(18)
    r:SetPoint("TOPLEFT", 6, -26 - (i - 1) * 19); r:SetPoint("RIGHT", -6, 0)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(16, 16); r.icon:SetPoint("LEFT")
    r.search = UI.Icon(r, "search", 15, L"Искать на аукционе (окно аукциона должно быть открыто)", function(self) ns.SearchAH(self:GetParent().id) end); r.search:SetPoint("RIGHT")
    r.star = UI.Icon(r, "star-off", 15, L"Отметить: уведомления о скачках цены", function(self) ns.ToggleMark(self:GetParent().id) end); r.star:SetPoint("RIGHT", r.search, "LEFT", -4, 0)
    r.price = UI.Font(r, 11); r.price:SetPoint("RIGHT", r.star, "LEFT", -6, 0); r.price:SetJustifyH("RIGHT")
    r.name = UI.Font(r, 11); r.name:SetPoint("LEFT", r.icon, "RIGHT", 4, 0); r.name:SetPoint("RIGHT", r.price, "LEFT", -6, 0)
    r:EnableMouse(true)
    r:SetScript("OnEnter", function(self) if self.id then GameTooltip:SetOwner(self, "ANCHOR_LEFT"); pcall(GameTooltip.SetItemByID, GameTooltip, self.id); GameTooltip:Show() end end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:Hide()
    detail.rows[i] = r
  end
  detail.total = UI.Font(detail, 11, UI.TEXT); detail.total:SetPoint("BOTTOMLEFT", 8, 8); detail.total:SetPoint("RIGHT", -8, 0); detail.total:SetWordWrap(true); detail.total:SetJustifyV("BOTTOM")

  -- кнопка-лапа на окне профессии: показать/скрыть панель
  local tg = UI.Icon(h, "paw", 22, L"WolfichMarket: прибыль крафта", function()
    ns.DB.settings.profPanelHidden = not ns.DB.settings.profPanelHidden
    panel:SetShown(not ns.DB.settings.profPanelHidden)
  end)
  tg:SetPoint("TOPRIGHT", h, "TOPRIGHT", -28, -2); tg:SetFrameLevel(h:GetFrameLevel() + 20)

  panel:SetScript("OnShow", function() refreshList(); fillDetail(selected) end)
  panel:SetShown(not ns.DB.settings.profPanelHidden)

  -- выбор рецепта в окне игры → карточка
  if EventRegistry and EventRegistry.RegisterCallback then
    pcall(EventRegistry.RegisterCallback, EventRegistry, "ProfessionsRecipeListMixin.Event.OnRecipeSelected", function(_, recipeInfo)
      if not recipeInfo or not recipeInfo.recipeID then return end
      local c = ns.DB.chars[ns.charKey]
      for _, p in pairs(c and c.profs or {}) do
        for _, rec in ipairs(p.recipes or {}) do if rec.id == recipeInfo.recipeID then fillDetail(rec) return end end
      end
    end, panel)
  end
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
  if not p or not p.recipes or #p.recipes == 0 then return true end
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
ns.Listen("LOGIN", function() ns.ScanSkills() end)
local function refreshAll() if panel and panel:IsShown() then refreshList(); fillDetail(selected) end; ns.DecorateRecipeRows() end
ns.Listen("PRICES", function() indexDirty = true; refreshAll() end)
ns.Listen("MARKS", function() if panel and panel:IsShown() then list:Refresh(); fillDetail(selected) end end)
ns.Listen("RECIPES", function() indexDirty = true; if panel and panel:IsShown() then refreshList() end end)
ns.Listen("AH_STATE", function() if panel and panel:IsShown() then fillDetail(selected) end end)
ns.Listen("NAMES", function() if panel and panel:IsShown() then list:Refresh() end end)
