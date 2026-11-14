-- WolfichMarket: главное окно (крафт по всем персонажам и сигналы) + кнопка у миникарты
local _, ns = ...
local L = ns.L
local UI, M = ns.UI, ns.MEDIA

local win, view, charKey, prof, sel
local DIFF = { [0] = "|cffff8040", [1] = "|cffffff00", [2] = "|cff40c040", [3] = "|cff808080" }

local function chars()
  local list = {}
  for ck, c in pairs(ns.DB.chars) do if (c.profs and next(c.profs)) or c.realmKey then list[#list + 1] = ck end end
  table.sort(list, function(a, b) if a == ns.charKey then return true elseif b == ns.charKey then return false end return a < b end)
  if #list == 0 and ns.charKey then list[1] = ns.charKey end
  return list
end
local function charLabel(ck)
  local c = ns.DB.chars[ck] or {}
  local col = c.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.class]
  local name, realm = ck:match("^(.-)%-(.+)$")
  name = name or ck
  local mode = realm and realm:match("(PvP)$") or nil
  return (col and ("|c" .. (col.colorStr or "ffffffff")) or "|cffffffff") .. name .. "|r" .. (mode and (" |cffaaaaaa(" .. mode .. ")|r") or "")
end
local function profitStr(pr)
  if not pr.rec.out then return L"|cff888888чары|r" end
  if pr.profit then return (pr.profit >= 0 and "|cff78d98a+" or "|cffff7a66") .. ns.money(pr.profit, true) .. "|r" end
  if pr.missing > 0 then return L"|cffaa8866нет цены|r" end
  return "|cff777777-|r"
end

-- ---------- вкладка «Крафт» ----------
local craft = {}
local function refreshProfs()
  local c = ns.DB.chars[charKey] or { profs = {} }
  local names = {}
  for p in pairs(c.profs or {}) do names[#names + 1] = p end
  table.sort(names)
  if not prof or not c.profs[prof] then prof = names[1] end
  -- кнопки по ширине текста, переносятся во второй ряд, если не влезают
  local W = craft.page:GetWidth() or 0
  if W < 200 then W = 812 end
  local x, row = 0, 0
  for i, b in ipairs(craft.profBtns) do
    local p = names[i]
    if p then
      local d = c.profs[p]
      b.prof = p
      if d.virtual then b:SetLabel("|cffaaaaaa" .. p .. L" (не изучена)|r") else b:SetLabel(p .. " |cffaaaaaa" .. (d.skill or 0) .. "/" .. (d.max or 0) .. "|r") end
      local w = b:FitWidth(120, 260)
      if x > 0 and x + w > W then x = 0; row = row + 1 end
      b:ClearAllPoints(); b:SetPoint("TOPLEFT", craft.page, "TOPLEFT", x, -16 - row * 30)
      x = x + w + 6
      b:Show(); b:SetGold(p == prof)
    else b:Hide() end
  end
  -- «+»: добавить профессию, которой у персонажа нет (для отслеживания цен)
  if x > 0 and x + 34 > W then x = 0; row = row + 1 end
  craft.addBtn:ClearAllPoints(); craft.addBtn:SetPoint("TOPLEFT", craft.page, "TOPLEFT", x, -16 - row * 30)
  craft.setTop(row * 30)
  craft.noProf:SetShown(#names == 0)
end
local function fillCard(rec)
  sel = rec
  local card = craft.card
  for _, r in ipairs(card.rows) do r:Hide() end
  if not rec then
    card.title:SetText(L"Выберите рецепт"); card.total:SetText(""); card.prices:Hide(); card.craft:Hide(); card.alarm:Hide(); card.where:Hide(); card.portRow:Hide(); card.chartTitle:SetText(""); card.chart:Hide()
    return
  end
  card.craft:Show(); card.alarm:Show(); card.where:Show(); card.chart:Show(); card.portRow:Show(); card.prices:Show()
  if craft.chartRec ~= rec then craft.chartRec = rec; craft.chartId = rec.out or (rec.reag[1] and rec.reag[1][1]) end
  local mine = charKey == ns.charKey
  if not mine then card.craft:Disable(); card.craft.tip = L"Рецепт другого персонажа - зайдите им, чтобы крафтить"
  elseif not ns.IsLearned(rec) then card.craft:Disable(); card.craft.tip = L"Рецепт ещё не изучен"
  else card.craft:Enable(); card.craft.tip = nil end
  local c = ns.DB.chars[charKey] or {}
  local stock = ns.DB.settings.useBank and ns.Stock(charKey) or nil
  craft.portions = craft.portions or {}
  local N = craft.portions[rec.id] or 1
  if not card.portion:HasFocus() then card.portion:SetText(N) end
  local pr = ns.WithRealm(c.realmKey, ns.Profit, rec, stock, N)
  pr.rec = rec
  local learned = ns.IsLearned(rec)
  card.title:SetText((learned and (DIFF[rec.diff] or "|cffffffff") or "|cff9d9d9d") .. rec.name .. "|r" .. (learned and "" or L"  |cffff9966(не изучен)|r"))
  local items = {}
  if rec.out then items[#items + 1] = { id = rec.out, n = pr.qty or 1, unit = pr.sell, out = true } end
  for _, p in ipairs(pr.parts) do items[#items + 1] = p end
  for i, it in ipairs(items) do
    local r = card.rows[i]; if not r then break end
    r.id = it.id
    r.icon:SetTexture(ns.itemIcon(it.id))
    -- с «Учитывать банк»: сколько есть в банке и сумках; покупать только недостающее
    local haveTxt = ""
    if not it.out and it.have then haveTxt = "  " .. ns.HaveText(it.id, charKey, it.n) end
    r.need = (not it.out and it.have) and it.n or nil
    r.name:SetText((it.out and "|cffe6b450> |r" or "") .. ns.itemLinkText(it.id) .. (it.n ~= 1 and (" |cffaaaaaa×" .. it.n .. "|r") or "") .. haveTxt)
    local qty = it.out and 1 or (it.buy or it.n)
    r.price:SetText(it.unit and (qty > 0 and ns.money(it.unit * qty, true) or L"|cff78d98aсвоё|r") or (qty > 0 and L"|cffaa8866нет цены|r" or L"|cff78d98aсвоё|r"))
    r.star:SetIcon(ns.IsMarked(it.id) and "star-on" or "star-off")
    r.search:SetAlpha(ns.AHIsOpen() and 1 or 0.35)
    r:Show()
  end
  local lines = { (pr.stock and (N > 1 and string.format(L"Докупить на %d крафтов: ", N) or L"Докупить на 1 крафт: ") or (N > 1 and string.format(L"Себестоимость %d крафтов: ", N) or L"Себестоимость: ")) .. (pr.missing > 0 and (">= " .. ns.money(pr.cost)) or ns.money(pr.cost))
    .. (pr.crafts and ("   |cffaaaaaa" .. L"из запаса хватит на " .. pr.crafts .. "|r") or "") }
  if pr.revenue then lines[#lines + 1] = L"Доход (-5%): " .. ns.money(pr.revenue) end
  if pr.profit then lines[#lines + 1] = L"Прибыль: " .. profitStr(pr) .. (pr.margin and ("  |cffaaaaaa(" .. math.floor(pr.margin) .. "%)|r") or "") end
  card.total:SetText(table.concat(lines, "\n"))
  -- «Крафт» и «Поставить сигнал» — сразу под последней строкой рецепта
  local n = math.min(#items, #card.rows)
  card.portRow:ClearAllPoints(); card.portRow:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -52 - n * 22 - 4); card.portRow:SetPoint("RIGHT", card, "RIGHT", -14, 0)
  craft.drawChart()
end
-- график цены выбранного предмета (по умолчанию — результат рецепта)
function craft.drawChart()
  local card, id = craft.card, craft.chartId
  for _, r in ipairs(card.rows) do r.hl:SetShown(r:IsShown() and r.id == id) end
  if not id then card.chartTitle:SetText(""); card.chart:SetPoints(nil); return end
  local p = ns.AHPrice(id)
  card.chartTitle:SetText(L"График: " .. ns.itemLinkText(id) .. (p and ("  |cffaaaaaa" .. L"сейчас" .. "|r " .. ns.money(p, true)) or ""))
  local h = ns.History(id)
  ns.After(0, function() card.chart:SetPoints(h) end)
end
-- окно «Сигналы для рецепта»: галочки на предмет и ингредиенты, свой порог у каждого
local dlg
function craft.openAlarms(rec)
  if not dlg then
    dlg = CreateFrame("Frame", "WolfichMarketAlarmDialog", win)
    dlg:SetSize(500, 360); dlg:SetPoint("CENTER", win, "CENTER"); dlg:SetFrameStrata("DIALOG"); dlg:EnableMouse(true); dlg:SetToplevel(true)
    UI.Skin(dlg, { theme = "main", scale = 0.6 })
    dlg.title = select(1, UI.Title(dlg, L"Сигналы для рецепта"))
    UI.Close(dlg)
    dlg.sub = UI.Font(dlg, 11, UI.DIM); dlg.sub:SetPoint("TOPLEFT", 18, -50); dlg.sub:SetPoint("RIGHT", -18, 0); dlg.sub:SetWordWrap(true)
    local h1 = UI.Font(dlg, 10, UI.DIM); h1:SetPoint("TOPRIGHT", -26, -80); h1:SetText(L"Порог, %")
    local h2 = UI.Font(dlg, 10, UI.DIM); h2:SetPoint("TOPRIGHT", -102, -80); h2:SetText(L"Цена")
    dlg.rows = {}
    for i = 1, 8 do
      local r = CreateFrame("Frame", nil, dlg); r:SetHeight(24); r:SetPoint("TOPLEFT", 16, -94 - (i - 1) * 26); r:SetPoint("RIGHT", -18, 0)
      r.chk = UI.CheckBox(r, 20); r.chk:SetPoint("LEFT")
      r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(20, 20); r.icon:SetPoint("LEFT", r.chk, "RIGHT", 4, 0)
      r.thr = CreateFrame("EditBox", nil, r, "InputBoxTemplate"); r.thr:SetSize(40, 18); r.thr:SetPoint("RIGHT", -6, 0); r.thr:SetAutoFocus(false); r.thr:SetNumeric(true)
      r.price = UI.Font(r, 11); r.price:SetPoint("RIGHT", r.thr, "LEFT", -18, 0); r.price:SetWidth(80); r.price:SetJustifyH("RIGHT")
      r.name = UI.Font(r, 11); r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0); r.name:SetPoint("RIGHT", r.price, "LEFT", -6, 0)
      r:Hide(); dlg.rows[i] = r
    end
    dlg.all = UI.Button(dlg, L"Отметить все", 120, 24, function() for _, r in ipairs(dlg.rows) do if r:IsShown() then r.chk:SetChecked(true) end end end)
    dlg.all:SetPoint("BOTTOMLEFT", 18, 16)
    dlg.save = UI.Button(dlg, L"Сохранить", 130, 26, function()
      for _, r in ipairs(dlg.rows) do
        if r:IsShown() and r.id then
          local want = r.chk:GetChecked() and true or false
          if want ~= ns.IsMarked(r.id) then
            ns.ToggleMark(r.id)
            -- результат рецепта - в «Продажу» (жду роста), материалы - в «Покупку» (жду снижения)
            ns.DB.alarmDir = ns.DB.alarmDir or {}
            ns.DB.alarmDir[r.id] = want and (r.out and "sell" or "buy") or nil
          end
          local v = tonumber(r.thr:GetText())
          ns.DB.alarm[r.id] = (want and v and v > 0) and v or nil
        end
      end
      dlg:Hide(); ns.Fire("MARKS")
    end, true)
    dlg.save:SetPoint("BOTTOMRIGHT", -18, 16)
    local cancel = UI.Button(dlg, L"Отмена", 100, 26, function() dlg:Hide() end); cancel:SetPoint("RIGHT", dlg.save, "LEFT", -8, 0)
  end
  dlg.sub:SetText(rec.name .. " - " .. L"отметьте, по каким предметам присылать уведомления о скачках цены. Пустой порог - общий (" .. ns.DB.settings.alertPct .. "%).")
  local items = {}
  if rec.out then items[#items + 1] = { id = rec.out, out = true } end
  for _, r in ipairs(rec.reag or {}) do items[#items + 1] = { id = r[1], n = r[2] } end
  for i, r in ipairs(dlg.rows) do
    local it = items[i]
    if it then
      r.id, r.out = it.id, it.out
      r.chk:SetChecked(ns.IsMarked(it.id))
      r.icon:SetTexture(ns.itemIcon(it.id))
      r.name:SetText((it.out and "|cffe6b450> |r" or "") .. ns.itemLinkText(it.id) .. (it.n and it.n ~= 1 and (" |cffaaaaaa×" .. it.n .. "|r") or ""))
      local p = ns.AHPrice(it.id); r.price:SetText(p and ns.money(p, true) or L"|cff777777нет|r")
      r.thr:SetText(ns.DB.alarm[it.id] or "")
      r:Show()
    else r.id = nil; r:Hide() end
  end
  dlg:Show()
end
local function refreshCraft()
  if not craft.list then return end
  refreshProfs()
  local S = ns.DB.settings
  local rows = prof and ns.AllRecipeProfits(prof, S.showUnlearned, charKey) or {}
  local data = {}
  for _, pr in ipairs(rows) do if not S.profitOnly or (pr.profit and pr.profit > 0) then data[#data + 1] = pr end end
  local key = craft.sortKey or "profit"
  table.sort(data, function(a, b) local x, y = a[key] or -1e12, b[key] or -1e12; if x == y then return a.rec.name < b.rec.name end return x > y end)
  -- группы по требуемому навыку: Ученик 1-74, Подмастерье 75-149, Умелец 150-224, Искусник 225-299, 300+
  local groups, order = {}, {}
  for _, pr in ipairs(data) do
    local lv = ns.RecipeLevel and ns.RecipeLevel(pr.rec)
    local t = ns.SkillTier(lv)
    if not groups[t] then groups[t] = {}; order[#order + 1] = t end
    table.insert(groups[t], pr)
  end
  table.sort(order)
  local out = {}
  for _, t in ipairs(order) do
    out[#out + 1] = { header = ns.SkillTierName(t), tier = t, count = #groups[t] }
    if not (craft.collapsed and craft.collapsed[t]) then for _, pr in ipairs(groups[t]) do out[#out + 1] = pr end end
  end
  craft.list:SetData(out)
  craft.list.empty:SetText(L"Откройте окна профессий этим персонажем - здесь появятся его рецепты с прибылью.")
  local c = ns.DB.chars[charKey] or {}
  local scan = ns.priceRealm == nil and ns.DB.ahScans[c.realmKey or ""] or nil
  local nt, nfrom = ns.NetInfo and ns.NetInfo()
  local netTxt = (nt and (not scan or nt > scan.t)) and ("  |cff78d98a" .. L"цены игроков" .. ": " .. ns.ago(nt) .. " (" .. ((nfrom or ""):match("^[^-]+") or "") .. ")|r") or ""
  local own = scan and (L"Цены: снимок " .. ns.ago(scan.t)) or (ns.CurrentScan() and (L"Цены: снимок " .. ns.ago(ns.CurrentScan().t) .. L" |cffaaaaaa(режим текущего персонажа)|r"))
  craft.status:SetText(own and (own .. netTxt) or (netTxt ~= "" and netTxt) or L"|cffff9966Цен нет - откройте аукцион и нажмите «Сканировать».|r")
  fillCard(sel)
end

local function buildCraft(f)
  craft.status = UI.Font(f, 10, UI.DIM); craft.status:SetPoint("TOPLEFT", 4, 0); craft.status:SetPoint("RIGHT", -4, 0)
  craft.profBtns = {}
  craft.page = f
  for i = 1, 10 do
    local b = UI.Button(f, "", 128, 26, function(self, btn)
      if btn == "RightButton" then
        if StaticPopupDialogs and StaticPopup_Show then
          StaticPopupDialogs.WOLFICHMARKET_DELPROF = StaticPopupDialogs.WOLFICHMARKET_DELPROF or {
            text = L"Удалить профессию «%s» у этого персонажа из WolfichMarket? Она вернётся, когда вы снова откроете её окно этим персонажем.",
            button1 = YES or "Да", button2 = NO or "Нет", timeout = 0, whileDead = true, hideOnEscape = true,
            OnAccept = function(_, data) ns.RemoveProfession(data.ck, data.prof) end,
          }
          local dlg = StaticPopup_Show("WOLFICHMARKET_DELPROF", self.prof)
          if dlg then dlg.data = { ck = charKey, prof = self.prof } end
        end
        return
      end
      prof = self.prof; sel = nil; refreshCraft()
    end)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:AddLine(L"Правый клик - удалить профессию у персонажа", 1, 1, 1); GameTooltip:Show() end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetPoint("TOPLEFT", 0, -16); craft.profBtns[i] = b
  end
  craft.addBtn = UI.Button(f, "+", 30, 26, function(self) craft.openAddMenu(self) end)
  craft.addBtn:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:AddLine(L"Добавить профессию, которой нет у персонажа: все её рецепты будут видны серым, а цены - отслеживаться.", 1, 1, 1, true); GameTooltip:Show() end)
  craft.addBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  -- меню профессий для «+»
  function craft.openAddMenu(anchor)
    local m = craft.addMenu
    if not m then
      m = CreateFrame("Frame", "WolfichMarketAddProfMenu", win); m:SetFrameStrata("DIALOG"); m:EnableMouse(true)
      UI.Skin(m, { theme = "acard", scale = 0.25 })
      m.btns = {}
      craft.addMenu = m
    end
    if m:IsShown() then m:Hide() return end
    local list = ns.AllProfessions()
    local have = (ns.DB.chars[charKey] or {}).profs or {}
    for i, p in ipairs(list) do
      local b = m.btns[i] or UI.Button(m, "", 200, 22); m.btns[i] = b
      b:SetPoint("TOPLEFT", 12, -12 - (i - 1) * 24)
      local owned = have[p.name] ~= nil
      b:SetLabel(owned and ("|cff777777" .. p.name .. "|r") or p.name)
      b:SetScript("OnClick", function() m:Hide(); if not owned then local n = ns.AddVirtualProfession(charKey, p.slug); if n then prof = n; sel = nil end; refreshCraft() end end)
      b:Show()
    end
    for i = #list + 1, #m.btns do m.btns[i]:Hide() end
    m:SetSize(224, 24 + #list * 24)
    m:ClearAllPoints(); m:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4); m:Show()
  end
  craft.noProf = UI.Font(f, 11, UI.DIM); craft.noProf:SetPoint("TOPLEFT", 40, -24); craft.noProf:SetText(L"Нет сохранённых профессий у этого персонажа - зайдите им и откройте окна его профессий.")
  local S = ns.DB.settings
  local c1 = UI.Check(f, L"только прибыльные", function() return S.profitOnly end, function(v) S.profitOnly = v; refreshCraft(); ns.Fire("RECIPES") end); c1:SetPoint("TOPLEFT", 0, -48)
  local c2 = UI.Check(f, L"включая неизученные рецепты", function() return S.showUnlearned end, function(v) S.showUnlearned = v; refreshCraft(); ns.Fire("RECIPES"); if ns.DecorateRecipeRows then ns.DecorateRecipeRows() end end); c2:SetPoint("TOPLEFT", 170, -48)
  local c3 = UI.Check(f, L"учитывать свои материалы", function() return S.useBank end, function(v) S.useBank = v; if ns.MarkProfitDirty then ns.MarkProfitDirty() end; refreshCraft(); ns.Fire("RECIPES") end); c3:SetPoint("TOPLEFT", 400, -48)
  c3:HookScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(L"Материалы из банка и сумок этого персонажа считаются своими: в себестоимость идёт только то, что нужно докупить. Банк запоминается, когда вы открываете его этим персонажем.", 1, 1, 1, true); GameTooltip:Show() end)
  c3:HookScript("OnLeave", function() GameTooltip:Hide() end)
  local bM = UI.Button(f, L"по марже", 96, 22, function() craft.sortKey = "margin"; refreshCraft() end); bM:SetPoint("TOPRIGHT", 0, -48)
  local bP = UI.Button(f, L"по прибыли", 104, 22, function() craft.sortKey = "profit"; refreshCraft() end); bP:SetPoint("RIGHT", bM, "LEFT", -6, 0)
  craft.list = UI.List(f, 22, function(r)
    -- заголовок группы по требуемому навыку (клик - свернуть/развернуть)
    r.hdr = UI.Font(r, 12, UI.GOLD); r.hdr:SetPoint("LEFT", 6, 0); r.hdr:SetPoint("RIGHT", -6, 0)
    r.hdrBg = r:CreateTexture(nil, "BACKGROUND", nil, 1); r.hdrBg:SetAllPoints(); r.hdrBg:SetColorTexture(0.85, 0.62, 0.25, 0.14)
    r.star = UI.Icon(r, "star-off", 14, L"Отметить: уведомления о скачках цены", function(self) local d = self:GetParent().data; if d and d.rec and d.rec.out then ns.ToggleMark(d.rec.out) end end); r.star:SetPoint("LEFT", 4, 0)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(18, 18); r.icon:SetPoint("LEFT", r.star, "RIGHT", 4, 0)
    r.val = UI.Font(r, 11); r.val:SetPoint("RIGHT", -4, 0); r.val:SetJustifyH("RIGHT")
    r.name = UI.Font(r, 11); r.name:SetPoint("LEFT", r.icon, "RIGHT", 5, 0); r.name:SetPoint("RIGHT", -90, 0)
    r:SetScript("OnClick", function(self)
      local d = self.data
      if not d then return end
      if d.header then craft.collapsed = craft.collapsed or {}; craft.collapsed[d.tier] = not craft.collapsed[d.tier]; refreshCraft() return end
      fillCard(d.rec)
    end)
  end, function(r, d)
    local h = d.header ~= nil
    r.hdr:SetShown(h); r.hdrBg:SetShown(h); r.icon:SetShown(not h); r.name:SetShown(not h); r.val:SetShown(not h)
    if h then
      r.star:Hide()
      r.hdr:SetText((craft.collapsed and craft.collapsed[d.tier] and "+ " or "- ") .. d.header .. "  |cffaaaaaa(" .. d.count .. ")|r")
      return
    end
    r.star:SetShown(d.rec.out ~= nil); r.star:SetIcon(d.rec.out and ns.IsMarked(d.rec.out) and "star-on" or "star-off")
    local learned = ns.IsLearned(d.rec)
    r.icon:SetTexture(d.rec.out and ns.itemIcon(d.rec.out) or d.rec.icon or 134400); r.icon:SetDesaturated(not learned)
    r.name:SetText(learned and ((DIFF[d.rec.diff] or "|cffffffff") .. d.rec.name .. "|r") or ("|cff9d9d9d" .. d.rec.name .. L" |cffff9966(не изучен)|r"))
    r.val:SetText(profitStr(d))
  end)
  craft.list:SetPoint("TOPLEFT", 0, -78); craft.list:SetPoint("BOTTOMRIGHT", f, "BOTTOM", 0, 0)
  -- карточка рецепта
  local card = CreateFrame("Frame", nil, f)
  card:SetPoint("TOPLEFT", f, "TOP", 10, -78); card:SetPoint("BOTTOMRIGHT")
  -- второй ряд профессий сдвигает фильтры, список и карточку вниз
  function craft.setTop(dy)
    c1:ClearAllPoints(); c1:SetPoint("TOPLEFT", 0, -48 - dy)
    c2:ClearAllPoints(); c2:SetPoint("TOPLEFT", 170, -48 - dy)
    c3:ClearAllPoints(); c3:SetPoint("TOPLEFT", 400, -48 - dy)
    bM:ClearAllPoints(); bM:SetPoint("TOPRIGHT", 0, -48 - dy)
    craft.list:ClearAllPoints(); craft.list:SetPoint("TOPLEFT", 0, -78 - dy); craft.list:SetPoint("BOTTOMRIGHT", f, "BOTTOM", 0, 0)
    card:ClearAllPoints(); card:SetPoint("TOPLEFT", f, "TOP", 10, -78 - dy); card:SetPoint("BOTTOMRIGHT")
  end
  UI.Skin(card, { theme = "mcard" })
  -- «Цены» - обновить цены всего рецепта (результат и материалы) поиском у аукциониста
  card.prices = UI.Button(card, L"Цены", 64, 20, function()
    if not sel then return end
    if not ns.AHIsOpen() then ns.say(L"цены обновляются у аукциониста - откройте аукцион.") return end
    ns.QuickRefresh(ns.RecipePriceIDs(sel))
  end)
  card.prices:SetPoint("TOPRIGHT", -16, -26)
  card.prices:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(L"Обновить цены всего рецепта (результат и все материалы) - когда открыт аукцион, без 15-минутного ожидания.", 1, 1, 1, true); GameTooltip:Show() end)
  card.prices:SetScript("OnLeave", function() GameTooltip:Hide() end)
  card.title = UI.Font(card, 13, UI.GOLD, "OVERLAY", "OUTLINE"); card.title:SetPoint("TOPLEFT", 16, -30); card.title:SetPoint("RIGHT", card.prices, "LEFT", -8, 0)
  card.rows = {}
  for i = 1, 8 do
    local r = CreateFrame("Frame", nil, card); r:SetHeight(20)
    r:SetPoint("TOPLEFT", 14, -52 - (i - 1) * 22); r:SetPoint("RIGHT", -14, 0)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(18, 18); r.icon:SetPoint("LEFT")
    r.search = UI.Icon(r, "search", 16, L"Искать на аукционе (окно аукциона должно быть открыто)", function(self) ns.SearchAH(self:GetParent().id) end); r.search:SetPoint("RIGHT")
    r.star = UI.Icon(r, "star-off", 16, L"Отметить: уведомления о скачках цены", function(self) ns.ToggleMark(self:GetParent().id) end); r.star:SetPoint("RIGHT", r.search, "LEFT", -6, 0)
    r.price = UI.Font(r, 11); r.price:SetPoint("RIGHT", r.star, "LEFT", -8, 0); r.price:SetJustifyH("RIGHT")
    r.name = UI.Font(r, 11); r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0); r.name:SetPoint("RIGHT", r.price, "LEFT", -6, 0)
    r:EnableMouse(true)
    r:SetScript("OnEnter", function(self)
      if not self.id then return end
      GameTooltip:SetOwner(self, "ANCHOR_LEFT"); pcall(GameTooltip.SetItemByID, GameTooltip, self.id)
      local bags, bank = ns.HaveSplit(self.id, charKey)
      GameTooltip:AddLine(L"В сумках" .. ": " .. bags .. "   " .. L"В банке" .. ": " .. bank, 1, 1, 1)
      GameTooltip:AddLine(L"Клик - график цены этого предмета", 0.9, 0.7, 0.3); GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:SetScript("OnMouseUp", function(self) if self.id then craft.chartId = self.id; craft.drawChart() end end)
    local hl = r:CreateTexture(nil, "BACKGROUND"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.8, 0.4, 0.12); hl:Hide(); r.hl = hl
    r:Hide(); card.rows[i] = r
  end
  -- порции: сколько раз крафтить - пересчёт материалов, «докупить» и прибыли; «Запланировать» - в план закупки
  local prow = CreateFrame("Frame", nil, card); prow:SetHeight(26); card.portRow = prow
  local pl = UI.Font(prow, 12); pl:SetPoint("LEFT", 0, 0); pl:SetText(L"Порций:")
  local function setN(v)
    if not sel then return end
    v = math.max(1, math.min(999, math.floor(tonumber(v) or 1)))
    craft.portions = craft.portions or {}; craft.portions[sel.id] = v
    fillCard(sel)
  end
  local function cur() return sel and craft.portions and craft.portions[sel.id] or 1 end
  local minus = UI.Button(prow, "-", 26, 24, function() setN(cur() - 1) end); minus:SetPoint("LEFT", pl, "RIGHT", 8, 0)
  card.portion = CreateFrame("EditBox", nil, prow, "InputBoxTemplate"); card.portion:SetSize(40, 20); card.portion:SetPoint("LEFT", minus, "RIGHT", 8, 0)
  card.portion:SetAutoFocus(false); card.portion:SetNumeric(true); card.portion:SetMaxLetters(3); card.portion:SetJustifyH("CENTER")
  card.portion:SetScript("OnEnterPressed", function(self) self:ClearFocus(); setN(self:GetText()) end)
  card.portion:SetScript("OnEditFocusLost", function(self) setN(self:GetText()) end)
  local plus = UI.Button(prow, "+", 26, 24, function() setN(cur() + 1) end); plus:SetPoint("LEFT", card.portion, "RIGHT", 4, 0)
  local p5 = UI.Button(prow, "+5", 34, 24, function() setN(cur() + 5) end); p5:SetPoint("LEFT", plus, "RIGHT", 4, 0)
  card.plan = UI.Button(prow, L"Запланировать", 140, 24, function() if sel then ns.AddPlan(sel, charKey, prof, craft.portions[sel.id] or 1) end end, true)
  card.plan:SetPoint("RIGHT", 0, 0)
  card.plan:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(L"Сохранить рецепт и число порций в план. У аукциониста во вкладке «План» будет список всего, что нужно докупить.", 1, 1, 1, true); GameTooltip:Show() end)
  card.plan:SetScript("OnLeave", function() GameTooltip:Hide() end)
  card.craft = UI.Button(card, L"Крафт", 100, 26, function() if sel then ns.OpenRecipeInGame(sel, prof) end end, true)
  card.craft:SetPoint("TOPLEFT", prow, "BOTTOMLEFT", 0, -6)
  card.craft:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(self.tip or L"Открыть этот рецепт в окне профессии", 1, 1, 1, true); GameTooltip:Show() end)
  card.craft:SetScript("OnLeave", function() GameTooltip:Hide() end)
  card.alarm = UI.Button(card, L"Поставить сигнал", 140, 26, function() if sel then craft.openAlarms(sel) end end)
  card.alarm:SetPoint("LEFT", card.craft, "RIGHT", 6, 0)
  -- «Где взять»: тренер, продавцы, добыча, задания, репутация и карта зоны
  card.where = UI.Button(card, L"Где взять", 110, 26, function() if sel and ns.ShowSources then ns.ShowSources(sel) end end)
  card.where:SetPoint("LEFT", card.alarm, "RIGHT", 6, 0)
  card.where:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(L"Где взять рецепт: тренер, продавцы, добыча, задания, нужная репутация и карта зоны (данные Wowhead WoW Forever).", 1, 1, 1, true); GameTooltip:Show() end)
  card.where:SetScript("OnLeave", function() GameTooltip:Hide() end)
  card.alarm:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(L"Выбрать галочками предмет и ингредиенты для сигналов о скачках цены", 1, 1, 1, true); GameTooltip:Show() end)
  card.alarm:SetScript("OnLeave", function() GameTooltip:Hide() end)
  card.total = UI.Font(card, 12, UI.TEXT); card.total:SetPoint("TOPLEFT", card.craft, "BOTTOMLEFT", 2, -6); card.total:SetPoint("RIGHT", -10, 0); card.total:SetWordWrap(true); card.total:SetJustifyV("TOP")
  card.chartTitle = UI.Font(card, 11, UI.GOLD); card.chartTitle:SetPoint("TOPLEFT", card.total, "BOTTOMLEFT", 0, -10); card.chartTitle:SetPoint("RIGHT", -10, 0)
  card.chart = UI.Chart(card); card.chart.showPeaks = true
  card.chart:SetPoint("TOPLEFT", card.chartTitle, "BOTTOMLEFT", -8, -4); card.chart:SetPoint("BOTTOMRIGHT", -10, 10)
  craft.card = card
end

-- ---------- вкладка «Сигналы» ----------
local sig = {}
-- направление сигнала: "buy" - жду снижения (покупка), "sell" - жду роста (продажа), nil - оба (старые отметки)
local function sigDir(id) return ns.DB.alarmDir and ns.DB.alarmDir[id] end
local function refreshSignals()
  if not sig.buy then return end
  local b, s2 = {}, {}
  for id in pairs(ns.DB.marked) do
    local d = sigDir(id)
    if d ~= "sell" then b[#b + 1] = { id = id, side = "buy" } end
    if d ~= "buy" then s2[#s2 + 1] = { id = id, side = "sell" } end
  end
  local byName = function(x, y) return ns.itemName(x.id) < ns.itemName(y.id) end
  table.sort(b, byName); table.sort(s2, byName)
  sig.buy:SetData(b); sig.sell:SetData(s2)
  sig.global:SetText(ns.DB.settings.alertPct)
end
-- окно графика цены (из вкладки «Сигналы»): работает и без открытого аукциона
local chartDlg
function ns.ShowChartDialog(id)
  if not id then return end
  if not chartDlg then
    -- отдельное окно (не внутри главного): открывается и из вкладки «Продать» у аукциониста
    chartDlg = CreateFrame("Frame", "WolfichMarketChartDialog", UIParent)
    chartDlg:SetSize(620, 380); chartDlg:SetPoint("CENTER"); chartDlg:SetFrameStrata("DIALOG"); chartDlg:EnableMouse(true); chartDlg:SetToplevel(true)
    chartDlg:SetMovable(true); chartDlg:RegisterForDrag("LeftButton"); chartDlg:SetClampedToScreen(true)
    chartDlg:SetScript("OnDragStart", chartDlg.StartMoving); chartDlg:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    tinsert(UISpecialFrames, "WolfichMarketChartDialog")
    UI.Skin(chartDlg, { theme = "main", scale = 0.6 })
    UI.Title(chartDlg, L"График цены")
    UI.Close(chartDlg)
    chartDlg.icon = chartDlg:CreateTexture(nil, "ARTWORK"); chartDlg.icon:SetSize(28, 28); chartDlg.icon:SetPoint("TOPLEFT", 20, -50)
    chartDlg.name = UI.Font(chartDlg, 13, UI.GOLD); chartDlg.name:SetPoint("TOPLEFT", chartDlg.icon, "TOPRIGHT", 8, -1); chartDlg.name:SetPoint("RIGHT", -20, 0)
    chartDlg.info = UI.Font(chartDlg, 11, UI.DIM); chartDlg.info:SetPoint("TOPLEFT", chartDlg.name, "BOTTOMLEFT", 0, -3); chartDlg.info:SetPoint("RIGHT", -20, 0)
    chartDlg.chart = UI.Chart(chartDlg); chartDlg.chart.showPeaks = true
    chartDlg.chart:SetPoint("TOPLEFT", 16, -88); chartDlg.chart:SetPoint("BOTTOMRIGHT", -20, 18)
  end
  chartDlg.id = id
  chartDlg.icon:SetTexture(ns.itemIcon(id))
  chartDlg.name:SetText(ns.itemLinkText(id))
  local p, avg = ns.AHPrice(id), ns.AvgPrice(id, 24)
  chartDlg.info:SetText((p and (L"сейчас" .. " " .. ns.money(p, true)) or L"|cff777777нет цены|r") .. (avg and ("   |cffaaaaaa" .. L"среднее за 24 ч" .. "|r " .. ns.money(avg, true)) or ""))
  chartDlg:Show()
  local h = ns.History(id)
  ns.After(0, function() chartDlg.chart:SetPoints(h) end)
end

-- добавить предмет в список покупки или продажи (если он уже в другом - станет «оба»)
function ns.AddSignal(id, side)
  if not id then return end
  ns.DB.alarmDir = ns.DB.alarmDir or {}
  if ns.IsMarked(id) then
    local d = ns.DB.alarmDir[id]
    if d and d ~= side then ns.DB.alarmDir[id] = nil end -- был в другом списке - теперь в обоих
  else
    ns.ToggleMark(id); ns.DB.alarmDir[id] = side
  end
  ns.Fire("MARKS")
end
-- убрать из одного списка (если был в обоих - останется в другом)
function ns.RemoveSignal(id, side)
  ns.DB.alarmDir = ns.DB.alarmDir or {}
  local d = ns.DB.alarmDir[id]
  if d == nil then ns.DB.alarmDir[id] = side == "buy" and "sell" or "buy"
  else ns.DB.alarmDir[id] = nil; if ns.IsMarked(id) then ns.ToggleMark(id) end end
  ns.Fire("MARKS")
end
local function buildSignals(f)
  local info = UI.Font(f, 11, UI.TEXT); info:SetPoint("TOPLEFT", 4, 0); info:SetPoint("RIGHT", -4, 0); info:SetWordWrap(true)
  info:SetText(L"Слева - что хотите купить: сигнал, когда цена упадёт. Справа - что хотите продать: сигнал, когда цена вырастет. Сигналы общие для всех персонажей: снимок аукциона любым из них проверяет весь список.")
  local gl = UI.Font(f, 11); gl:SetPoint("TOPLEFT", 4, -40); gl:SetText(L"Общий порог, %:")
  sig.global = CreateFrame("EditBox", nil, f, "InputBoxTemplate"); sig.global:SetSize(44, 20); sig.global:SetPoint("LEFT", gl, "RIGHT", 10, 0); sig.global:SetAutoFocus(false); sig.global:SetNumeric(true)
  sig.global:SetScript("OnTextChanged", function(self, user) if user then local v = tonumber(self:GetText()); if v and v > 0 then ns.DB.settings.alertPct = v; if sig.buy then sig.buy:Refresh(); sig.sell:Refresh() end end end end)
  local ah = UI.Font(f, 10, UI.DIM); ah:SetPoint("LEFT", sig.global, "RIGHT", 16, 0); ah:SetText(L"Добавить: впишите название или Shift+клик по предмету, пока поле в фокусе")
  sig.adds = {}
  local function panel(side, x1, x2, title, color)
    local p = CreateFrame("Frame", nil, f)
    p:SetPoint("TOPLEFT", f, x1 == 0 and "TOPLEFT" or "TOP", x1 == 0 and 0 or 6, -66); p:SetPoint("BOTTOMRIGHT", f, x1 == 0 and "BOTTOM" or "BOTTOMRIGHT", x1 == 0 and -6 or 0, 0)
    UI.Skin(p, { theme = "acard", scale = 0.25 })
    local t = UI.Font(p, 13, color); t:SetPoint("TOPLEFT", 12, -10); t:SetText(title)
    local add = CreateFrame("EditBox", nil, p, "InputBoxTemplate"); add:SetHeight(20); add:SetPoint("TOPLEFT", 16, -32); add:SetPoint("RIGHT", -12, 0); add:SetAutoFocus(false)
    add:SetScript("OnEnterPressed", function(self)
      local txt = self:GetText()
      local id = ns.idFromLink(txt) or tonumber(txt)
      if not id and txt ~= "" then for k, n in pairs(ns.DB.names) do if n:lower() == txt:lower() then id = k; break end end end
      if id then ns.AddSignal(id, side) else ns.say(L"предмет не найден - вставьте ссылку (Shift+клик) или точное название.") end
      self:SetText(""); self:ClearFocus()
    end)
    add:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    sig.adds[side] = add
    local hdr = CreateFrame("Frame", nil, p); hdr:SetPoint("TOPLEFT", 10, -58); hdr:SetPoint("TOPRIGHT", -10, -58); hdr:SetHeight(14)
    local function col(txt, x) local c = UI.Font(hdr, 10, UI.DIM); c:SetPoint("RIGHT", hdr, "RIGHT", x, 0); c:SetText(txt) end
    local h1 = UI.Font(hdr, 10, UI.DIM); h1:SetPoint("LEFT", 26, 0); h1:SetText(L"Предмет")
    col(L"Порог, %", -46); col(L"24 ч", -104); col(L"Цена", -150)
    local list = UI.List(p, 34, function(r)
      r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(22, 22); r.icon:SetPoint("LEFT", 2, 0)
      r.x = UI.Icon(r, "skin\\ai-x", 14, L"Убрать из списка", function(self) local d = self:GetParent().data; if d then ns.RemoveSignal(d.id, side) end end); r.x:SetPoint("RIGHT", -2, 0)
      r.chart = UI.Icon(r, "chart", 14, L"График цены", function(self) local d = self:GetParent().data; if d then ns.ShowChartDialog(d.id) end end); r.chart:SetPoint("RIGHT", r.x, "LEFT", -4, 0)
      r.thr = CreateFrame("EditBox", nil, r, "InputBoxTemplate"); r.thr:SetSize(32, 18); r.thr:SetPoint("RIGHT", r.chart, "LEFT", -8, 0); r.thr:SetAutoFocus(false); r.thr:SetNumeric(true)
      r.thr:SetScript("OnTextChanged", function(self, user)
        if user and r.data then local v = tonumber(self:GetText()); ns.DB.alarm[r.data.id] = (v and v > 0) and v or nil; r.fillTarget(r.data) end
      end)
      r.thr:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
      r.chg = UI.Font(r, 11); r.chg:SetPoint("RIGHT", r.thr, "LEFT", -8, 0); r.chg:SetWidth(46); r.chg:SetJustifyH("RIGHT")
      r.price = UI.Font(r, 11); r.price:SetPoint("RIGHT", r.chg, "LEFT", -4, 0); r.price:SetWidth(64); r.price:SetJustifyH("RIGHT")
      r.name = UI.Font(r, 11); r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 5, 2); r.name:SetPoint("RIGHT", r.price, "LEFT", -4, 0)
      -- вторая строка: при какой цене придёт сигнал (от средней за сутки +/- порог)
      r.target = UI.Font(r, 10, UI.DIM); r.target:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 5, -3); r.target:SetPoint("RIGHT", r.price, "LEFT", -4, 0)
      function r.fillTarget(d)
        local base = ns.AvgPrice(d.id, 24) or ns.AHPrice(d.id)
        local pct = ns.DB.alarm[d.id] or ns.DB.settings.alertPct or 20
        if not base then r.target:SetText(L"|cff777777нет цены - нужен снимок аукциона|r") return end
        local tp = side == "buy" and base * (1 - pct / 100) or base * (1 + pct / 100)
        r.target:SetText((side == "buy" and L"сигнал, если ниже" or L"сигнал, если выше") .. " |cffffd100" .. ns.money(tp, true) .. "|r  |cff888888(" .. (side == "buy" and "-" or "+") .. pct .. "%)|r")
      end
      r:SetScript("OnEnter", function(self) if self.data then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); pcall(GameTooltip.SetItemByID, GameTooltip, self.data.id); GameTooltip:Show() end end)
      r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end, function(r, d)
      r.icon:SetTexture(ns.itemIcon(d.id)); r.name:SetText(ns.itemLinkText(d.id))
      local pr = ns.AHPrice(d.id); r.price:SetText(pr and ns.money(pr, true) or L"|cff777777нет|r")
      local avg = ns.AvgPrice(d.id, 24); r.chg:SetText(pr and avg and ns.pct((pr - avg) / avg * 100) or "")
      if not r.thr:HasFocus() then r.thr:SetText(ns.DB.alarm[d.id] or "") end
      r.fillTarget(d)
    end)
    list:SetPoint("TOPLEFT", 10, -74); list:SetPoint("BOTTOMRIGHT", -10, 10)
    list.empty:SetText(side == "buy" and L"Пусто. Добавьте то, что хотите купить дешевле." or L"Пусто. Добавьте то, что хотите продать дороже.")
    return list
  end
  sig.buy = panel("buy", 0, nil, L"Покупка: жду снижения цены", { 0.47, 0.85, 0.54 })
  sig.sell = panel("sell", 1, nil, L"Продажа: жду роста цены", { 1, 0.75, 0.35 })
  -- Shift+клик по предмету, пока поле в фокусе, - добавить в этот список
  if hooksecurefunc then pcall(hooksecurefunc, "ChatEdit_InsertLink", function(link)
    for side, e in pairs(sig.adds) do
      if e:HasFocus() then local id = ns.idFromLink(link); if id then ns.AddSignal(id, side) end; e:SetText(""); e:ClearFocus() end
    end
  end) end
end

-- ---------- вкладка «Банк» ----------
local bank = {}
local refreshBank
local function buildBank(f)
  local S = ns.DB.settings
  bank.status = UI.Font(f, 11, UI.DIM); bank.status:SetPoint("TOPLEFT", 4, 0); bank.status:SetPoint("RIGHT", -4, 0); bank.status:SetWordWrap(true)
  local cb = UI.Check(f, L"вместе с сумками", function() return S.bankWithBags end, function(v) S.bankWithBags = v; refreshBank() end); cb:SetPoint("TOPLEFT", 0, -30)
  bank.total = UI.Font(f, 13, UI.GOLD); bank.total:SetPoint("TOPRIGHT", -4, -32); bank.total:SetJustifyH("RIGHT")
  local hdr = CreateFrame("Frame", nil, f); hdr:SetPoint("TOPLEFT", 0, -60); hdr:SetPoint("TOPRIGHT", 0, -60); hdr:SetHeight(14)
  local function col(t, x) local s2 = UI.Font(hdr, 10, UI.DIM); s2:SetPoint("RIGHT", hdr, "RIGHT", x, 0); s2:SetText(t) end
  local h1 = UI.Font(hdr, 10, UI.DIM); h1:SetPoint("LEFT", 46, 0); h1:SetText(L"Предмет")
  col(L"Всего", -12); col(L"Цена за шт", -130); col(L"Кол-во", -250)
  bank.list = UI.List(f, 24, function(r)
    r.star = UI.Icon(r, "star-off", 16, L"Отметить: уведомления о скачках цены", function(self) local d = self:GetParent().data; if d then ns.ToggleMark(d.id) end end); r.star:SetPoint("LEFT", 4, 0)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(20, 20); r.icon:SetPoint("LEFT", r.star, "RIGHT", 6, 0)
    r.sum = UI.Font(r, 11); r.sum:SetPoint("RIGHT", -12, 0); r.sum:SetWidth(110); r.sum:SetJustifyH("RIGHT")
    r.unit = UI.Font(r, 11); r.unit:SetPoint("RIGHT", r.sum, "LEFT", -8, 0); r.unit:SetWidth(110); r.unit:SetJustifyH("RIGHT")
    r.cnt = UI.Font(r, 12); r.cnt:SetPoint("RIGHT", r.unit, "LEFT", -8, 0); r.cnt:SetWidth(60); r.cnt:SetJustifyH("RIGHT")
    r.name = UI.Font(r, 12); r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0); r.name:SetPoint("RIGHT", r.cnt, "LEFT", -6, 0)
    r:SetScript("OnClick", function(self) if self.data then ns.ShowChartDialog(self.data.id) end end)
    r:SetScript("OnEnter", function(self) if self.data then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); pcall(GameTooltip.SetItemByID, GameTooltip, self.data.id); GameTooltip:AddLine(L"Клик - график цены", 0.9, 0.7, 0.3); GameTooltip:Show() end end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end, function(r, d)
    r.star:SetIcon(ns.IsMarked(d.id) and "star-on" or "star-off")
    r.icon:SetTexture(ns.itemIcon(d.id)); r.name:SetText(ns.itemLinkText(d.id))
    r.cnt:SetText(d.n .. (d.inBags and d.inBags > 0 and (" |cffaaaaaa(" .. d.inBags .. ")|r") or ""))
    r.unit:SetText(d.p and ns.money(d.p, true) or L"|cff777777нет|r")
    r.sum:SetText(d.p and ns.money(d.p * d.n, true) or "")
  end)
  bank.list:SetPoint("TOPLEFT", 0, -76); bank.list:SetPoint("BOTTOMRIGHT")
end
function refreshBank()
  if not bank.list then return end
  local c = ns.DB.chars[charKey] or {}
  local S = ns.DB.settings
  local items = {}
  for id, n in pairs(c.bank or {}) do items[id] = { id = id, n = n, inBags = 0 } end
  if S.bankWithBags then
    for id, n in pairs(c.bags or {}) do local d = items[id] or { id = id, n = 0, inBags = 0 }; d.n = d.n + n; d.inBags = n; items[id] = d end
  end
  local list, total = {}, 0
  ns.WithRealm(c.realmKey, function()
    for _, d in pairs(items) do d.p = ns.AHPrice(d.id); if d.p then total = total + d.p * d.n end; list[#list + 1] = d end
  end)
  table.sort(list, function(a, b) local x, y = (a.p or 0) * a.n, (b.p or 0) * b.n; if x == y then return ns.itemName(a.id) < ns.itemName(b.id) end return x > y end)
  bank.list:SetData(list)
  bank.list.empty:SetText(L"Банк этого персонажа ещё не записан - зайдите им и откройте банк у банкира.")
  bank.status:SetText(c.bankT and (L"Банк: снимок " .. ns.ago(c.bankT) .. L" |cffaaaaaa(обновляется, когда банк открыт)|r") or L"|cffff9966Банк не записан - откройте банк этим персонажем.|r")
  bank.total:SetText(L"Стоимость по аукциону: " .. ns.money(total))
end

-- ---------- окно ----------
-- ---------- вкладка «Журнал»: сообщения аддона вместо чата ----------
local logp = {}
local function buildLog(f)
  local t = UI.Font(f, 11, UI.DIM); t:SetPoint("TOPLEFT", 4, 0); t:SetPoint("RIGHT", -150, 0); t:SetWordWrap(true)
  t:SetText(L"Сообщения аддона (снимки, общий рынок, сигналы) - здесь, а не в чате. Сигналы о ценах дополнительно всплывают уведомлением.")
  logp.clear = UI.Button(f, L"Очистить", 100, 22, function() wipe(ns.log); logp.list:SetData(ns.log) end); logp.clear:SetPoint("TOPRIGHT", 0, 0)
  logp.list = UI.List(f, 20, function(r)
    r.time = UI.Font(r, 10, UI.DIM); r.time:SetPoint("LEFT", 4, 0); r.time:SetWidth(44)
    r.msg = UI.Font(r, 11); r.msg:SetPoint("LEFT", r.time, "RIGHT", 6, 0); r.msg:SetPoint("RIGHT", -4, 0)
    r:SetScript("OnEnter", function(self) if self.data then GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(self.data.msg, 1, 1, 1, true); GameTooltip:Show() end end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end, function(r, d)
    r.time:SetText(date("%H:%M", d.t)); r.msg:SetText((d.imp and "|cffffd100" or "") .. d.msg .. (d.imp and "|r" or ""))
  end)
  logp.list:SetPoint("TOPLEFT", 0, -34); logp.list:SetPoint("BOTTOMRIGHT")
  logp.list.empty:SetText(L"Сообщений пока нет.")
end
local function refreshLog() if logp.list then logp.list:SetData(ns.log) end end
local function refresh() if not win or not win:IsShown() then return end; if view == 1 then refreshCraft() elseif view == 2 then refreshSignals() elseif view == 3 then refreshBank() else refreshLog() end end
local function selectView(i)
  view = i
  for k, b in ipairs(win.tabs) do
    b:SetGold(k == i)
    win.pages[k]:SetShown(k == i)
  end
  refresh()
end
local function setChar(ck) charKey = ck; prof = nil; sel = nil; win.charName:SetText(charLabel(ck)); refresh() end

local function build()
  if win then return end
  win = CreateFrame("Frame", "WolfichMarketMainFrame", UIParent)
  win:SetSize(860, 600); win:SetPoint("CENTER"); win:SetFrameStrata("HIGH"); win:SetToplevel(true)
  win:SetMovable(true); win:EnableMouse(true); win:RegisterForDrag("LeftButton"); win:SetClampedToScreen(true)
  win:SetScript("OnDragStart", win.StartMoving); win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  UI.Skin(win, { theme = "main" })
  UI.Title(win, "WolfichMarket")
  UI.Close(win)
  tinsert(UISpecialFrames, "WolfichMarketMainFrame")
  -- персонаж
  local prev = UI.Icon(win, "skin\\mi-left", 24, nil, function() local l = chars(); for i, ck in ipairs(l) do if ck == charKey then setChar(l[(i - 2) % #l + 1]); return end end end)
  prev:SetPoint("TOPLEFT", 24, -64)
  win.charName = UI.Font(win, 13, nil, "OVERLAY", "OUTLINE"); win.charName:SetPoint("LEFT", prev, "RIGHT", 8, 0); win.charName:SetWidth(240)
  local nextB = UI.Icon(win, "skin\\mi-right", 24, nil, function() local l = chars(); for i, ck in ipairs(l) do if ck == charKey then setChar(l[i % #l + 1]); return end end end)
  nextB:SetPoint("LEFT", win.charName, "RIGHT", 4, 0)
  -- вкладки
  win.tabs = {}
  for i, n in ipairs({ L"Крафт", L"Сигналы", L"Банк", L"Журнал" }) do
    local b = UI.Button(win, n, 108, 26, function() selectView(i) end)
    b:SetPoint("TOPRIGHT", -24 - (4 - i) * 112, -63); win.tabs[i] = b
  end
  win.pages = {}
  for i, builder in ipairs({ buildCraft, buildSignals, buildBank, buildLog }) do
    local f = CreateFrame("Frame", nil, win); f:SetPoint("TOPLEFT", 24, -100); f:SetPoint("BOTTOMRIGHT", -24, 22)
    builder(f); f:Hide(); win.pages[i] = f
  end
  win:SetScript("OnShow", refresh)
  setChar(ns.charKey)
  selectView(1)
  win:Hide() -- новые фреймы видимы сразу; показываем по кнопке
end

ns._mainCraft = craft -- для автотестов
ns._mainSig = sig
function ns.ToggleMain()
  if not ns.DB or not ns.charKey then return end
  build()
  if win:IsShown() then win:Hide() else win:Show(); refresh() end
end
ns.Listen("PRICES", refresh)
ns.Listen("MARKS", refresh)
ns.Listen("RECIPES", refresh)
ns.Listen("NAMES", refresh)
ns.Listen("AH_STATE", refresh)
ns.Listen("LOG", function() if win and win:IsShown() and view == 4 then refreshLog() end end)
ns.Listen("INVENTORY", function() if view == 3 or ns.DB.settings.useBank then refresh() end end)

-- ---------- кнопка у миникарты ----------
local function placeMini(b)
  local a = math.rad(ns.DB.settings.minimapAngle or 200)
  local r = (Minimap:GetWidth() or 140) / 2 + 6
  b:ClearAllPoints(); b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end
ns.Listen("LOGIN", function()
  if not Minimap or ns.DB.settings.minimapHidden then return end
  local b = CreateFrame("Button", "WolfichMarketMinimapButton", Minimap)
  b:SetSize(32, 32); b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp"); b:RegisterForDrag("LeftButton")
  local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background"); bg:SetSize(22, 22); bg:SetPoint("CENTER")
  local icon = b:CreateTexture(nil, "ARTWORK"); icon:SetTexture(M .. "paw"); icon:SetSize(18, 18); icon:SetPoint("CENTER")
  local border = b:CreateTexture(nil, "OVERLAY"); border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder"); border:SetSize(54, 54); border:SetPoint("TOPLEFT")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  b:SetScript("OnClick", function(_, btn) if btn == "RightButton" and ns.StartScan and ns.AHIsOpen() then ns.StartScan() else ns.ToggleMain() end end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:AddLine("WolfichMarket", 0.9, 0.7, 0.3)
    GameTooltip:AddLine(L"Левый клик - окно крафта и сигналов", 1, 1, 1); GameTooltip:AddLine(L"Правый клик у аукциониста - снимок аукциона", 1, 1, 1)
    GameTooltip:AddLine(L"Перетащите, чтобы передвинуть", 0.7, 0.7, 0.7); GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local s = Minimap:GetEffectiveScale()
      ns.DB.settings.minimapAngle = math.deg(math.atan2(cy / s - my, cx / s - mx))
      placeMini(self)
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  placeMini(b)
end)
