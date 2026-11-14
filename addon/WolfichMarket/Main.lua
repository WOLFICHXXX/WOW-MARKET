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
      b.prof = p; b:SetLabel(p .. " |cffaaaaaa" .. (d.skill or 0) .. "/" .. (d.max or 0) .. "|r")
      local w = b:FitWidth(120, 260)
      if x > 0 and x + w > W then x = 0; row = row + 1 end
      b:ClearAllPoints(); b:SetPoint("TOPLEFT", craft.page, "TOPLEFT", x, -16 - row * 30)
      x = x + w + 6
      b:Show(); b:SetGold(p == prof)
    else b:Hide() end
  end
  craft.setTop(row * 30)
  craft.noProf:SetShown(#names == 0)
end
local function fillCard(rec)
  sel = rec
  local card = craft.card
  for _, r in ipairs(card.rows) do r:Hide() end
  if not rec then
    card.title:SetText(L"Выберите рецепт"); card.total:SetText(""); card.craft:Hide(); card.alarm:Hide(); card.chartTitle:SetText(""); card.chart:Hide()
    return
  end
  card.craft:Show(); card.alarm:Show(); card.chart:Show()
  if craft.chartRec ~= rec then craft.chartRec = rec; craft.chartId = rec.out or (rec.reag[1] and rec.reag[1][1]) end
  local mine = charKey == ns.charKey
  if not mine then card.craft:Disable(); card.craft.tip = L"Рецепт другого персонажа - зайдите им, чтобы крафтить"
  elseif not ns.IsLearned(rec) then card.craft:Disable(); card.craft.tip = L"Рецепт ещё не изучен"
  else card.craft:Enable(); card.craft.tip = nil end
  local c = ns.DB.chars[charKey] or {}
  local pr = ns.WithRealm(c.realmKey, ns.Profit, rec)
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
    r.name:SetText((it.out and "|cffe6b450> |r" or "") .. ns.itemLinkText(it.id) .. (it.n ~= 1 and (" |cffaaaaaa×" .. it.n .. "|r") or ""))
    r.price:SetText(it.unit and ns.money(it.unit * (it.out and 1 or it.n), true) or L"|cffaa8866нет цены|r")
    r.star:SetIcon(ns.IsMarked(it.id) and "star-on" or "star-off")
    r.search:SetAlpha(ns.AHIsOpen() and 1 or 0.35)
    r:Show()
  end
  local lines = { L"Себестоимость: " .. (pr.missing > 0 and (">= " .. ns.money(pr.cost)) or ns.money(pr.cost)) }
  if pr.revenue then lines[#lines + 1] = L"Доход (-5%): " .. ns.money(pr.revenue) end
  if pr.profit then lines[#lines + 1] = L"Прибыль: " .. profitStr(pr) .. (pr.margin and ("  |cffaaaaaa(" .. math.floor(pr.margin) .. "%)|r") or "") end
  card.total:SetText(table.concat(lines, "\n"))
  -- «Крафт» и «Поставить сигнал» — сразу под последней строкой рецепта
  local n = math.min(#items, #card.rows)
  card.craft:ClearAllPoints(); card.craft:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -34 - n * 22 - 6)
  craft.drawChart()
end
-- график цены выбранного предмета (по умолчанию — результат рецепта)
function craft.drawChart()
  local card, id = craft.card, craft.chartId
  for _, r in ipairs(card.rows) do r.hl:SetShown(r:IsShown() and r.id == id) end
  if not id then card.chartTitle:SetText(""); card.chart:SetPoints(nil); return end
  local p = ns.AHPrice(id)
  card.chartTitle:SetText(L"График: " .. ns.itemLinkText(id) .. (p and ("  |cffaaaaaa" .. L"сейчас" .. "|r " .. ns.money(p, true)) or ""))
  local h = ns.DB.hist[id]
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
          if want ~= ns.IsMarked(r.id) then ns.ToggleMark(r.id) end
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
      r.id = it.id
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
  craft.list:SetData(data)
  craft.list.empty:SetText(L"Откройте окна профессий этим персонажем - здесь появятся его рецепты с прибылью.")
  local c = ns.DB.chars[charKey] or {}
  local scan = ns.priceRealm == nil and ns.DB.ahScans[c.realmKey or ""] or nil
  craft.status:SetText(scan and (L"Цены: снимок " .. ns.ago(scan.t)) or (ns.CurrentScan() and (L"Цены: снимок " .. ns.ago(ns.CurrentScan().t) .. L" |cffaaaaaa(режим текущего персонажа)|r") or L"|cffff9966Цен нет - откройте аукцион и нажмите «Сканировать».|r"))
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
  craft.noProf = UI.Font(f, 11, UI.DIM); craft.noProf:SetPoint("TOPLEFT", 4, -24); craft.noProf:SetText(L"Нет сохранённых профессий у этого персонажа - зайдите им и откройте окна его профессий.")
  local S = ns.DB.settings
  local c1 = UI.Check(f, L"только прибыльные", function() return S.profitOnly end, function(v) S.profitOnly = v; refreshCraft(); ns.Fire("RECIPES") end); c1:SetPoint("TOPLEFT", 0, -48)
  local c2 = UI.Check(f, L"включая неизученные рецепты", function() return S.showUnlearned end, function(v) S.showUnlearned = v; refreshCraft(); ns.Fire("RECIPES"); if ns.DecorateRecipeRows then ns.DecorateRecipeRows() end end); c2:SetPoint("TOPLEFT", 170, -48)
  local bP = UI.Button(f, L"по прибыли", 104, 22, function() craft.sortKey = "profit"; refreshCraft() end); bP:SetPoint("TOPLEFT", 446, -48)
  local bM = UI.Button(f, L"по марже", 104, 22, function() craft.sortKey = "margin"; refreshCraft() end); bM:SetPoint("LEFT", bP, "RIGHT", 6, 0)
  craft.list = UI.List(f, 22, function(r)
    r.star = UI.Icon(r, "star-off", 14, L"Отметить: уведомления о скачках цены", function(self) local d = self:GetParent().data; if d and d.rec.out then ns.ToggleMark(d.rec.out) end end); r.star:SetPoint("LEFT", 4, 0)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(18, 18); r.icon:SetPoint("LEFT", r.star, "RIGHT", 4, 0)
    r.val = UI.Font(r, 11); r.val:SetPoint("RIGHT", -4, 0); r.val:SetJustifyH("RIGHT")
    r.name = UI.Font(r, 11); r.name:SetPoint("LEFT", r.icon, "RIGHT", 5, 0); r.name:SetPoint("RIGHT", -90, 0)
    r:SetScript("OnClick", function(self) if self.data then fillCard(self.data.rec) end end)
  end, function(r, d)
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
    bP:ClearAllPoints(); bP:SetPoint("TOPLEFT", 446, -48 - dy)
    craft.list:ClearAllPoints(); craft.list:SetPoint("TOPLEFT", 0, -78 - dy); craft.list:SetPoint("BOTTOMRIGHT", f, "BOTTOM", 0, 0)
    card:ClearAllPoints(); card:SetPoint("TOPLEFT", f, "TOP", 10, -78 - dy); card:SetPoint("BOTTOMRIGHT")
  end
  UI.Skin(card, { theme = "mcard" })
  card.title = UI.Font(card, 13, UI.GOLD, "OVERLAY", "OUTLINE"); card.title:SetPoint("TOPLEFT", 16, -30); card.title:SetPoint("RIGHT", -16, 0)
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
    r:SetScript("OnEnter", function(self) if self.id then GameTooltip:SetOwner(self, "ANCHOR_LEFT"); pcall(GameTooltip.SetItemByID, GameTooltip, self.id); GameTooltip:AddLine(L"Клик - график цены этого предмета", 0.9, 0.7, 0.3); GameTooltip:Show() end end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:SetScript("OnMouseUp", function(self) if self.id then craft.chartId = self.id; craft.drawChart() end end)
    local hl = r:CreateTexture(nil, "BACKGROUND"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.8, 0.4, 0.12); hl:Hide(); r.hl = hl
    r:Hide(); card.rows[i] = r
  end
  card.craft = UI.Button(card, L"Крафт", 130, 26, function() if sel then ns.OpenRecipeInGame(sel, prof) end end, true)
  card.craft:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(self.tip or L"Открыть этот рецепт в окне профессии", 1, 1, 1, true); GameTooltip:Show() end)
  card.craft:SetScript("OnLeave", function() GameTooltip:Hide() end)
  card.alarm = UI.Button(card, L"Поставить сигнал", 150, 26, function() if sel then craft.openAlarms(sel) end end)
  card.alarm:SetPoint("LEFT", card.craft, "RIGHT", 8, 0)
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
local function refreshSignals()
  if not sig.list then return end
  local d = {}
  for id in pairs(ns.DB.marked) do d[#d + 1] = { id = id } end
  table.sort(d, function(a, b) return ns.itemName(a.id) < ns.itemName(b.id) end)
  sig.list:SetData(d)
  sig.global:SetText(ns.DB.settings.alertPct)
end
-- окно графика цены (из вкладки «Сигналы»): работает и без открытого аукциона
local chartDlg
function ns.ShowChartDialog(id)
  if not id then return end
  if not win then return end -- окно ещё не построено (вызов только из вкладки «Сигналы»)
  if not chartDlg then
    chartDlg = CreateFrame("Frame", "WolfichMarketChartDialog", win)
    chartDlg:SetSize(620, 380); chartDlg:SetPoint("CENTER", win, "CENTER"); chartDlg:SetFrameStrata("DIALOG"); chartDlg:EnableMouse(true); chartDlg:SetToplevel(true)
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
  if not win:IsShown() then win:Show() end
  chartDlg:Show()
  local h = ns.DB.hist[id]
  ns.After(0, function() chartDlg.chart:SetPoints(h) end)
end

local function buildSignals(f)
  local info = UI.Font(f, 11, UI.TEXT); info:SetPoint("TOPLEFT", 4, 0); info:SetPoint("RIGHT", -4, 0); info:SetWordWrap(true)
  info:SetText(L"Уведомления о скачках цены приходят только по отмеченным предметам - после каждого снимка аукциона. Порог можно задать для каждого предмета, пустое поле - общий порог.")
  local gl = UI.Font(f, 11); gl:SetPoint("TOPLEFT", 4, -40); gl:SetText(L"Общий порог, %:")
  sig.global = CreateFrame("EditBox", nil, f, "InputBoxTemplate"); sig.global:SetSize(44, 20); sig.global:SetPoint("LEFT", gl, "RIGHT", 10, 0); sig.global:SetAutoFocus(false); sig.global:SetNumeric(true)
  sig.global:SetScript("OnTextChanged", function(self, user) if user then local v = tonumber(self:GetText()); if v and v > 0 then ns.DB.settings.alertPct = v end end end)
  local al = UI.Font(f, 11); al:SetPoint("LEFT", sig.global, "RIGHT", 24, 0); al:SetText(L"Добавить предмет:")
  sig.add = CreateFrame("EditBox", nil, f, "InputBoxTemplate"); sig.add:SetSize(220, 20); sig.add:SetPoint("LEFT", al, "RIGHT", 10, 0); sig.add:SetAutoFocus(false)
  local ah = UI.Font(f, 10, UI.DIM); ah:SetPoint("LEFT", sig.add, "RIGHT", 8, 0); ah:SetText(L"Shift+клик по предмету или Alt+клик в сумке")
  sig.add:SetScript("OnEnterPressed", function(self) local id = ns.idFromLink(self:GetText()) or tonumber(self:GetText()); if id and not ns.IsMarked(id) then ns.ToggleMark(id) end; self:SetText(""); self:ClearFocus() end)
  sig.add:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  -- Shift+клик по предмету, пока поле в фокусе, — вставить и отметить
  if hooksecurefunc then pcall(hooksecurefunc, "ChatEdit_InsertLink", function(link)
    if sig.add and sig.add:HasFocus() then local id = ns.idFromLink(link); if id and not ns.IsMarked(id) then ns.ToggleMark(id) end; sig.add:SetText(""); sig.add:ClearFocus() end
  end) end
  local hdr = CreateFrame("Frame", nil, f); hdr:SetPoint("TOPLEFT", 0, -66); hdr:SetPoint("TOPRIGHT", 0, -66); hdr:SetHeight(14)
  local function col(t, x) local s = UI.Font(hdr, 10, UI.DIM); s:SetPoint("RIGHT", hdr, "RIGHT", x, 0); s:SetText(t) end
  local h1 = UI.Font(hdr, 10, UI.DIM); h1:SetPoint("LEFT", 46, 0); h1:SetText(L"Предмет")
  col(L"Порог, %", -60); col(L"24 ч", -140); col(L"Цена", -210)
  sig.list = UI.List(f, 24, function(r)
    r.star = UI.Icon(r, "star-on", 16, L"Снять отметку", function(self) local d = self:GetParent().data; if d then ns.ToggleMark(d.id) end end); r.star:SetPoint("LEFT", 4, 0)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(20, 20); r.icon:SetPoint("LEFT", r.star, "RIGHT", 6, 0)
    r.search = UI.Icon(r, "search", 16, L"Найти в окне аукциона", function(self) local d = self:GetParent().data; if d then ns.SearchAH(d.id) end end); r.search:SetPoint("RIGHT", -4, 0)
    r.chart = UI.Icon(r, "chart", 16, L"График цены", function(self) local d = self:GetParent().data; if d then ns.ShowChartDialog(d.id) end end); r.chart:SetPoint("RIGHT", r.search, "LEFT", -6, 0)
    r.thr = CreateFrame("EditBox", nil, r, "InputBoxTemplate"); r.thr:SetSize(40, 18); r.thr:SetPoint("RIGHT", r.chart, "LEFT", -14, 0); r.thr:SetAutoFocus(false); r.thr:SetNumeric(true)
    r.thr:SetScript("OnTextChanged", function(self, user) if user and r.data then local v = tonumber(self:GetText()); ns.DB.alarm[r.data.id] = (v and v > 0) and v or nil end end)
    r.thr:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    r.chg = UI.Font(r, 11); r.chg:SetPoint("RIGHT", r.thr, "LEFT", -18, 0); r.chg:SetWidth(56); r.chg:SetJustifyH("RIGHT")
    r.price = UI.Font(r, 11); r.price:SetPoint("RIGHT", r.chg, "LEFT", -6, 0); r.price:SetWidth(80); r.price:SetJustifyH("RIGHT")
    r.name = UI.Font(r, 11); r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0); r.name:SetPoint("RIGHT", r.price, "LEFT", -6, 0)
  end, function(r, d)
    r.icon:SetTexture(ns.itemIcon(d.id)); r.name:SetText(ns.itemLinkText(d.id))
    local p = ns.AHPrice(d.id); r.price:SetText(p and ns.money(p, true) or L"|cff777777нет|r")
    local avg = ns.AvgPrice(d.id, 24); r.chg:SetText(p and avg and ns.pct((p - avg) / avg * 100) or "")
    if not r.thr:HasFocus() then r.thr:SetText(ns.DB.alarm[d.id] or "") end
  end)
  sig.list:SetPoint("TOPLEFT", 0, -82); sig.list:SetPoint("BOTTOMRIGHT")
  sig.list.empty:SetText(L"Отмеченных предметов нет.\nОтметьте звёздочкой в окне крафта, Alt+клик в сумке или впишите выше.")
end

-- ---------- окно ----------
local function refresh() if not win or not win:IsShown() then return end; if view == 1 then refreshCraft() else refreshSignals() end end
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
  for i, n in ipairs({ L"Крафт", L"Сигналы" }) do
    local b = UI.Button(win, n, 124, 26, function() selectView(i) end)
    b:SetPoint("TOPRIGHT", -24 - (2 - i) * 130, -63); win.tabs[i] = b
  end
  win.pages = {}
  for i, builder in ipairs({ buildCraft, buildSignals }) do
    local f = CreateFrame("Frame", nil, win); f:SetPoint("TOPLEFT", 24, -100); f:SetPoint("BOTTOMRIGHT", -24, 22)
    builder(f); f:Hide(); win.pages[i] = f
  end
  win:SetScript("OnShow", refresh)
  setChar(ns.charKey)
  selectView(1)
  win:Hide() -- новые фреймы видимы сразу; показываем по кнопке
end

ns._mainCraft = craft -- для автотестов
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
