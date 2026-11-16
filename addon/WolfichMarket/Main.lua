-- WolfichMarket: главное окно (крафт по всем персонажам и сигналы) + кнопка у миникарты
local _, ns = ...
local L = ns.L
local UI, M = ns.UI, ns.MEDIA

local win, view, charKey, prof, sel
local setChar
local function sigDir(id) return ns.DB.alarmDir and ns.DB.alarmDir[id] end
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
local function pfStr(v) return v and ((v >= 0 and "|cff78d98a+" or "|cffff7a66") .. ns.money(v, true) .. "|r") or "|cff666666-|r" end
-- прибыль рецепта на фракционном (Ф) и на общем (Общ) аукционе - два столбика
local function profitStr(pr)
  if not pr.rec.out then return L"|cff888888чары|r" end
  if pr.profit then return pfStr(pr.profit) end
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
  local X0 = craft.X0 or 0
  local x, row = X0, 0
  for i, b in ipairs(craft.profBtns) do
    local p = names[i]
    if p then
      local d = c.profs[p]
      b.prof = p
      if d.virtual then b:SetLabel("|cffaaaaaa" .. p .. L" (не изучена)|r") else b:SetLabel(p .. " |cffaaaaaa" .. (d.skill or 0) .. "/" .. (d.max or 0) .. "|r") end
      local w = b:FitWidth(110, 240)
      if x > X0 and x + w > W then x = X0; row = row + 1 end
      b:ClearAllPoints(); b:SetPoint("TOPLEFT", craft.page, "TOPLEFT", x, -row * 30)
      x = x + w + 6
      b:Show(); b:SetGold(p == prof)
    else b:Hide() end
  end
  -- «+»: добавить профессию, которой у персонажа нет (для отслеживания цен)
  if x > X0 and x + 34 > W then x = X0; row = row + 1 end
  craft.addBtn:ClearAllPoints(); craft.addBtn:SetPoint("TOPLEFT", craft.page, "TOPLEFT", x, -row * 30)
  if craft.charName then craft.charName:SetText(charLabel(charKey)) end
  craft.setTop(row * 30)
  craft.noProf:SetShown(#names == 0)
end
local function fillCard(rec)
  sel = rec
  local card = craft.card
  if card.fade then ns.After(0, card.fade) end -- после раскладки: диапазон прокрутки и растушёвка
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
    r.bell:Update(it.id)
    r.search:SetAlpha(ns.AHIsOpen() and 1 or 0.35)
    r:Show()
  end
  local lines = { (pr.stock and (N > 1 and string.format(L"Докупить на %d крафтов: ", N) or L"Докупить на 1 крафт: ") or (N > 1 and string.format(L"Себестоимость %d крафтов: ", N) or L"Себестоимость: ")) .. (pr.missing > 0 and (">= " .. ns.money(pr.cost)) or ns.money(pr.cost))
    .. (pr.crafts and ("   |cffaaaaaa" .. L"из запаса хватит на " .. pr.crafts .. "|r") or "") }
  if pr.revenue then lines[#lines + 1] = L"Доход" .. " (-" .. ns.CutPct() .. "): " .. ns.money(pr.revenue) end
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
  card.chartId = id
  -- заголовок вместо легенды: цвет слов = цвет линий
  card.chartTitle:SetText(L"График: " .. ns.itemLinkText(id) .. "   |cfff2c761" .. L"цена" .. "|r " .. (p and ns.money(p, true) or "-") .. "   |cff66d9cc" .. L"продано, шт" .. "|r")
  local h = ns.History(id)
  ns.After(0, function() card.chart:SetPoints(h) end)
end
-- окно «Сигналы для рецепта»: галочки на предмет и ингредиенты, свой порог у каждого
local dlg
function craft.openAlarms(rec)
  if not dlg then
    dlg = CreateFrame("Frame", "WolfichMarketAlarmDialog", win)
    dlg:SetSize(560, 360); dlg:SetPoint("CENTER", win, "CENTER"); dlg:SetFrameStrata("DIALOG"); dlg:EnableMouse(true); dlg:SetToplevel(true)
    UI.Skin(dlg, { theme = "main", scale = 0.6 })
    dlg.title = select(1, UI.Title(dlg, L"Сигналы для рецепта"))
    UI.Close(dlg)
    dlg.sub = UI.Font(dlg, 11, UI.DIM); dlg.sub:SetPoint("TOPLEFT", 18, -50); dlg.sub:SetPoint("RIGHT", -18, 0); dlg.sub:SetWordWrap(true)
    local h1 = UI.Font(dlg, 10, UI.DIM); h1:SetPoint("TOPRIGHT", -40, -80); h1:SetText(L"Ваша цена")
    local h2 = UI.Font(dlg, 10, UI.DIM); h2:SetPoint("TOPRIGHT", -170, -80); h2:SetText(L"Цена сейчас")
    dlg.rows = {}
    for i = 1, 8 do
      local r = CreateFrame("Frame", nil, dlg); r:SetHeight(24); r:SetPoint("TOPLEFT", 16, -94 - (i - 1) * 26); r:SetPoint("RIGHT", -18, 0)
      r.chk = UI.CheckBox(r, 20); r.chk:SetPoint("LEFT")
      r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(20, 20); r.icon:SetPoint("LEFT", r.chk, "RIGHT", 4, 0)
      r.money = UI.MoneyInput(r, nil, true); r.money:SetPoint("RIGHT", -4, 0)
      r.price = UI.Font(r, 11); r.price:SetPoint("RIGHT", r.money, "LEFT", -10, 0); r.price:SetWidth(80); r.price:SetJustifyH("RIGHT")
      r.name = UI.Font(r, 11); r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0); r.name:SetPoint("RIGHT", r.price, "LEFT", -6, 0)
      r:Hide(); dlg.rows[i] = r
    end
    dlg.all = UI.Button(dlg, L"Отметить все", 120, 24, function() for _, r in ipairs(dlg.rows) do if r:IsShown() then r.chk:SetChecked(true) end end end)
    dlg.all:SetPoint("BOTTOMLEFT", 18, 16)
    dlg.save = UI.Button(dlg, L"Сохранить", 130, 26, function()
      for _, r in ipairs(dlg.rows) do
        if r:IsShown() and r.id then
          -- результат рецепта - в «Продажу» (жду роста), материалы - в «Покупку» (жду снижения); своя цена - порог
          local side = r.out and "sell" or "buy"
          if r.chk:GetChecked() then
            ns.AddSignal(r.id, side)
            ns.DB.target = ns.DB.target or {}
            local t = ns.DB.target[r.id] or {}
            local v = r.money:Get()
            t[side] = (v and v > 0) and v or nil
            ns.DB.target[r.id] = next(t) and t or nil
            if ns.DB.targetHit then ns.DB.targetHit[r.id .. side] = nil end
          else
            local d = sigDir(r.id)
            if d == side or d == "both" or (ns.DB.target and ns.DB.target[r.id] and ns.DB.target[r.id][side]) then ns.RemoveSignal(r.id, side) end
          end
        end
      end
      dlg:Hide(); ns.Fire("MARKS")
    end, true)
    dlg.save:SetPoint("BOTTOMRIGHT", -18, 16)
    local cancel = UI.Button(dlg, L"Отмена", 100, 26, function() dlg:Hide() end); cancel:SetPoint("RIGHT", dlg.save, "LEFT", -8, 0)
  end
  dlg.sub:SetText(rec.name .. " - " .. L"отметьте предметы и впишите свою цену: для результата - цену продажи, для материалов - цену покупки. Уведомление придёт, когда цена до неё дойдёт.")
  local items = {}
  if rec.out then items[#items + 1] = { id = rec.out, out = true } end
  for _, r in ipairs(rec.reag or {}) do items[#items + 1] = { id = r[1], n = r[2] } end
  for i, r in ipairs(dlg.rows) do
    local it = items[i]
    if it then
      r.id, r.out = it.id, it.out
      local d0 = sigDir(it.id); local sd = it.out and "sell" or "buy"
      r.chk:SetChecked(d0 == sd or d0 == "both" or (ns.DB.target and ns.DB.target[it.id] and ns.DB.target[it.id][sd]) and true or false)
      r.icon:SetTexture(ns.itemIcon(it.id))
      r.name:SetText((it.out and "|cffe6b450> |r" or "") .. ns.itemLinkText(it.id) .. (it.n and it.n ~= 1 and (" |cffaaaaaa×" .. it.n .. "|r") or ""))
      local p = ns.AHPrice(it.id); r.price:SetText(p and ns.money(p, true) or L"|cff777777нет|r")
      local t = ns.DB.target and ns.DB.target[it.id]
      local v = t and t[it.out and "sell" or "buy"]
      if v then r.money:Set(v) else r.money:Clear() end
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
  -- сортировка: прибыль на фракционном (Ф, по умолчанию), на общем (Общ) или маржа
  for _, pr in ipairs(data) do pr.nprofit = pr.rec.out and ns.ProfitIn(pr.rec, "neutral") or nil end
  local key = S.craftSort == "neutral" and "nprofit" or S.craftSort == "margin" and "margin" or "profit"
  table.sort(data, function(a, b) local x, y = a[key] or -1e12, b[key] or -1e12; if x == y then return a.rec.name < b.rec.name end return x > y end)
  local out = {}
  if S.craftFlat then
    -- без уровней: один общий список, прибыль сквозь все рецепты
    out = data
  else
    -- группы по требуемому навыку: Ученик 1-74, Подмастерье 75-149, Умелец 150-224, Искусник 225-299, 300+
    local groups, order = {}, {}
    for _, pr in ipairs(data) do
      local lv = ns.RecipeLevel and ns.RecipeLevel(pr.rec)
      local t = ns.SkillTier(lv)
      if not groups[t] then groups[t] = {}; order[#order + 1] = t end
      table.insert(groups[t], pr)
    end
    table.sort(order)
    for _, t in ipairs(order) do
      out[#out + 1] = { header = ns.SkillTierName(t), tier = t, count = #groups[t] }
      if not (craft.collapsed and craft.collapsed[t]) then for _, pr in ipairs(groups[t]) do out[#out + 1] = pr end end
    end
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
  local S = ns.DB.settings
  -- персонаж: < имя > (профессии - правее)
  local prevC = UI.Icon(f, "skin\\mi-left", 22, L"Предыдущий персонаж", function() craft.stepChar(-1) end); prevC:SetPoint("TOPLEFT", 0, -2)
  craft.charName = UI.Font(f, 13, nil, "OVERLAY", "OUTLINE"); craft.charName:SetPoint("LEFT", prevC, "RIGHT", 4, 0); craft.charName:SetWidth(150); craft.charName:SetJustifyH("CENTER")
  local nextC = UI.Icon(f, "skin\\mi-right", 22, L"Следующий персонаж", function() craft.stepChar(1) end); nextC:SetPoint("LEFT", craft.charName, "RIGHT", 4, 0)
  craft.X0 = 210
  function craft.stepChar(d)
    local l = chars()
    for i, ck in ipairs(l) do if ck == charKey then setChar(l[(i - 1 + d) % #l + 1]); return end end
    if l[1] then setChar(l[1]) end
  end
  craft.status = UI.Font(f, 10, UI.DIM); craft.status:SetPoint("BOTTOMLEFT", 2, 0); craft.status:SetPoint("RIGHT", -2, 0)
  -- сортировка по прибыли: на фракционном (по умолчанию), на общем или по марже - одна галочка всегда стоит
  local sortChecks = {}
  local function setSort(k) S.craftSort = k; for kk, c in pairs(sortChecks) do c:SetChecked(kk == k) end; refreshCraft() end
  local sortLbl = UI.Font(f, 11, UI.DIM); sortLbl:SetText(L"Сортировать по:")
  for _, o in ipairs({ { "main", L"прибыли на фракционном" }, { "neutral", L"прибыли на общем" }, { "margin", L"марже" } }) do
    local c = UI.Check(f, o[2], function() return (S.craftSort or "main") == o[1] end, function() setSort(o[1]) end)
    sortChecks[o[1]] = c
  end
  craft.sortMain, craft.sortNt, craft.sortMargin = sortChecks.main, sortChecks.neutral, sortChecks.margin
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
  craft.noProf = UI.Font(f, 11, UI.DIM); craft.noProf:SetPoint("TOPLEFT", 20, -120); craft.noProf:SetText(L"Нет сохранённых профессий у этого персонажа - зайдите им и откройте окна его профессий.")
  local c1 = UI.Check(f, L"только прибыльные", function() return S.profitOnly end, function(v) S.profitOnly = v; refreshCraft(); ns.Fire("RECIPES") end)
  local c2 = UI.Check(f, L"включая неизученные", function() return S.showUnlearned end, function(v) S.showUnlearned = v; refreshCraft(); ns.Fire("RECIPES"); if ns.DecorateRecipeRows then ns.DecorateRecipeRows() end end)
  local c3 = UI.Check(f, L"учитывать свои материалы", function() return S.useBank end, function(v) S.useBank = v; if ns.MarkProfitDirty then ns.MarkProfitDirty() end; refreshCraft(); ns.Fire("RECIPES") end)
  c3:HookScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(L"Материалы из банка и сумок этого персонажа считаются своими: в себестоимость идёт только то, что нужно докупить. Банк запоминается, когда вы открываете его этим персонажем.", 1, 1, 1, true); GameTooltip:Show() end)
  c3:HookScript("OnLeave", function() GameTooltip:Hide() end)
  local c4 = UI.Check(f, L"без уровней - общий список", function() return S.craftFlat end, function(v) S.craftFlat = v; refreshCraft() end)
  c4.label:SetTextColor(UI.GOLD[1], UI.GOLD[2], UI.GOLD[3])
  c4:HookScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(L"Рецепты без групп по навыку: сортировка по прибыли сквозь все рецепты профессии.", 1, 1, 1, true); GameTooltip:Show() end)
  c4:HookScript("OnLeave", function() GameTooltip:Hide() end)
  craft.flat = c4
  craft.listBox = CreateFrame("Frame", nil, f); UI.Box(craft.listBox)
  -- шапка списка: столбики Ф и Общ
  local lh = CreateFrame("Frame", nil, f); lh:SetHeight(14)
  local lh1 = UI.Font(lh, 10, UI.DIM); lh1:SetPoint("LEFT", 26, 0); lh1:SetText(L"Рецепт")
  local lhF = UI.Font(lh, 10, UI.GOLD); lhF:SetPoint("RIGHT", lh, "RIGHT", -92, 0); lhF:SetText(L"Ф")
  local lhO = UI.Font(lh, 10, { 0.4, 0.85, 0.8 }); lhO:SetPoint("RIGHT", lh, "RIGHT", -30, 0); lhO:SetText(L"Общ")
  craft.list = UI.List(f, 22, function(r)
    -- заголовок группы по требуемому навыку (клик - свернуть/развернуть)
    r.hdr = UI.Font(r, 12, UI.GOLD); r.hdr:SetPoint("LEFT", 6, 0); r.hdr:SetPoint("RIGHT", -6, 0)
    r.hdrBg = r:CreateTexture(nil, "BACKGROUND", nil, 1); r.hdrBg:SetAllPoints(); r.hdrBg:SetColorTexture(0.85, 0.62, 0.25, 0.14)
    r.star = UI.Icon(r, "star-off", 14, L"Избранное", function(self) local d = self:GetParent().data; if d and d.rec and d.rec.out then ns.ToggleMark(d.rec.out) end end); r.star:SetPoint("LEFT", 4, 0)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(18, 18); r.icon:SetPoint("LEFT", r.star, "RIGHT", 4, 0)
    r.bell = UI.Bell(r, 15, function(self) local d = self:GetParent().data; return d and d.rec and d.rec.out end); r.bell:SetPoint("RIGHT", -3, 0)
    r.vO = UI.Font(r, 11); r.vO:SetPoint("RIGHT", r.bell, "LEFT", -6, 0); r.vO:SetWidth(58); r.vO:SetJustifyH("RIGHT")
    r.val = UI.Font(r, 11); r.val:SetPoint("RIGHT", r.vO, "LEFT", -4, 0); r.val:SetWidth(62); r.val:SetJustifyH("RIGHT")
    r.name = UI.Font(r, 11); r.name:SetPoint("LEFT", r.icon, "RIGHT", 5, 0); r.name:SetPoint("RIGHT", r.val, "LEFT", -4, 0)
    r:SetScript("OnClick", function(self)
      local d = self.data
      if not d then return end
      if d.header then craft.collapsed = craft.collapsed or {}; craft.collapsed[d.tier] = not craft.collapsed[d.tier]; refreshCraft() return end
      fillCard(d.rec)
    end)
  end, function(r, d)
    local h = d.header ~= nil
    r.hdr:SetShown(h); r.hdrBg:SetShown(h); r.icon:SetShown(not h); r.name:SetShown(not h); r.val:SetShown(not h); r.vO:SetShown(not h); r.bell:SetShown(not h and d.rec and d.rec.out ~= nil)
    if h then
      r.star:Hide()
      r.hdr:SetText((craft.collapsed and craft.collapsed[d.tier] and "+ " or "- ") .. d.header .. "  |cffaaaaaa(" .. d.count .. ")|r")
      return
    end
    r.star:SetShown(d.rec.out ~= nil); r.star:SetIcon(d.rec.out and ns.IsMarked(d.rec.out) and "star-on" or "star-off")
    if d.rec.out then r.bell:Update(d.rec.out) end
    local learned = ns.IsLearned(d.rec)
    r.icon:SetTexture(d.rec.out and ns.itemIcon(d.rec.out) or d.rec.icon or 134400); r.icon:SetDesaturated(not learned)
    r.name:SetText(learned and ((DIFF[d.rec.diff] or "|cffffffff") .. d.rec.name .. "|r") or ("|cff9d9d9d" .. d.rec.name .. L" |cffff9966(не изучен)|r"))
    r.val:SetText(profitStr(d)); r.vO:SetText(d.rec.out and pfStr(d.nprofit) or "")
  end)
  craft.list:SetPoint("TOPLEFT", 0, -78); craft.list:SetPoint("BOTTOMRIGHT", f, "BOTTOM", 0, 0)
  -- карточка рецепта
  -- карточка: рамка (box) с прокруткой; всё содержимое - на прокручиваемом листе card, который на EXTRA выше
  -- видимой части - туда, вниз, вытягивается график. Прокрутка - колёсиком мыши.
  local EXTRA = 210
  local box = CreateFrame("Frame", nil, f)
  box:SetPoint("TOPLEFT", f, "TOP", 10, -86); box:SetPoint("BOTTOMRIGHT", 0, 16)
  local sf = CreateFrame("ScrollFrame", nil, box)
  sf:SetPoint("TOPLEFT", 4, -6); sf:SetPoint("BOTTOMRIGHT", -4, 6)
  -- обрезать всё, что уехало за край рамки при прокрутке
  if sf.SetClipsChildren then sf:SetClipsChildren(true) end
  if box.SetClipsChildren then box:SetClipsChildren(true) end
  local card = CreateFrame("Frame", nil, sf)
  card:SetSize(400, 400)
  sf:SetScrollChild(card)
  local cur, maxScroll = 0, EXTRA
  local FADE, EDGE_T, EDGE_B = 14, 12, 10 -- растушёвка и отступ линии рамки от края
  -- прокрутка ровно до графика: заголовок графика встаёт к верхней линии рамки
  local function range()
    local st, tt = sf:GetTop(), card.chartTitle and card.chartTitle:GetTop()
    if not st or not tt then return EXTRA end
    return math.max(0, math.floor(st - (tt - cur) - EDGE_T - FADE))
  end
  local function resize()
    local w, h = sf:GetWidth(), sf:GetHeight()
    if w and w > 0 then maxScroll = math.min(EXTRA, range()); card:SetSize(w, h + maxScroll) end
  end
  -- растушёвка у верхней и нижней линии рамки (по внутренней линии с уголками): к линии строка гаснет полностью,
  -- за линией её нет; погасшие кнопки не ловят мышь
  local function fade()
    local bt, bb = box:GetTop(), box:GetBottom()
    if not bt or not bb then return end
    local T, B = bt - EDGE_T, bb + EDGE_B
    local objs = { card:GetChildren() }
    for _, rg in ipairs({ card:GetRegions() }) do if rg.GetObjectType and rg:GetObjectType() == "FontString" then objs[#objs + 1] = rg end end
    for _, o in ipairs(objs) do
      if o ~= card.chart and o.GetTop then
        local top, bot = o:GetTop(), o:GetBottom()
        if top and bot then
          local a = math.min((T - top) / FADE, (bot - B) / FADE)
          a = math.max(0, math.min(1, a))
          o:SetAlpha(a)
          if o.EnableMouse and o.IsMouseEnabled then
            if o.wmMouse == nil then o.wmMouse = o:IsMouseEnabled() end
            if o.wmMouse then o:EnableMouse(a > 0.3) end
          end
        end
      end
    end
  end
  card.fade = function() resize(); fade() end
  sf:SetScript("OnSizeChanged", function() resize(); fade() end); resize()
  sf:EnableMouseWheel(true)
  local hint = UI.Font(box, 10, UI.DIM, "OVERLAY"); hint:SetPoint("BOTTOMRIGHT", -16, 8); hint:SetText(L"колёсико мыши - ниже график")
  sf:SetScript("OnMouseWheel", function(self, delta)
    resize()
    cur = math.max(0, math.min(maxScroll, cur - delta * 40))
    self:SetVerticalScroll(cur); hint:SetShown(cur < maxScroll * 0.5)
    fade()
  end)
  card.scroll = sf
  -- второй ряд профессий сдвигает фильтры, список и карточку вниз
  function craft.setTop(dy)
    c1:ClearAllPoints(); c1:SetPoint("TOPLEFT", 0, -34 - dy)
    c2:ClearAllPoints(); c2:SetPoint("TOPLEFT", 150, -34 - dy)
    c3:ClearAllPoints(); c3:SetPoint("TOPLEFT", 320, -34 - dy)
    c4:ClearAllPoints(); c4:SetPoint("TOPLEFT", 530, -34 - dy)
    sortLbl:ClearAllPoints(); sortLbl:SetPoint("TOPLEFT", 2, -64 - dy)
    sortChecks.main:ClearAllPoints(); sortChecks.main:SetPoint("TOPLEFT", 110, -60 - dy)
    sortChecks.neutral:ClearAllPoints(); sortChecks.neutral:SetPoint("TOPLEFT", 320, -60 - dy)
    sortChecks.margin:ClearAllPoints(); sortChecks.margin:SetPoint("TOPLEFT", 500, -60 - dy)
    -- список и карточка - две панели одной высоты, сверху и снизу на одной линии
    craft.listBox:ClearAllPoints(); craft.listBox:SetPoint("TOPLEFT", 0, -88 - dy); craft.listBox:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -6, 18)
    lh:ClearAllPoints(); lh:SetPoint("TOPLEFT", craft.listBox, "TOPLEFT", 6, -4); lh:SetPoint("RIGHT", craft.listBox, "RIGHT", -12, 0)
    craft.list:ClearAllPoints(); craft.list:SetPoint("TOPLEFT", craft.listBox, "TOPLEFT", 4, -20); craft.list:SetPoint("BOTTOMRIGHT", craft.listBox, "BOTTOMRIGHT", -4, 4)
    box:ClearAllPoints(); box:SetPoint("TOPLEFT", f, "TOP", 6, -88 - dy); box:SetPoint("BOTTOMRIGHT", 0, 18)
  end
  craft.setTop(0)
  UI.Skin(box, { theme = "mcard" })
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
    r.bell = UI.Bell(r, 16, function(self) return self:GetParent().id end); r.bell:SetPoint("RIGHT", r.search, "LEFT", -5, 0)
    r.star = UI.Icon(r, "star-off", 16, L"Избранное", function(self) ns.ToggleMark(self:GetParent().id) end); r.star:SetPoint("RIGHT", r.bell, "LEFT", -5, 0)
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
  -- график - полноразмерный, с подписями; карточка прокручивается колёсиком мыши вниз, к графику
  card.chart = UI.Chart(card); card.chart.showPeaks = true; card.chart.noLegend = true
  card.chart:SetPoint("TOPLEFT", card.chartTitle, "BOTTOMLEFT", -8, -4); card.chart:SetPoint("BOTTOMRIGHT", -10, 10)
  craft.card = card
end

-- ---------- вкладка «Сигналы» ----------
local sig = {}
-- направление сигнала: "buy" - жду снижения (покупка), "sell" - жду роста (продажа), "both" - оба
local function refreshSignals()
  if not sig.buy then return end
  local b, s2 = {}, {}
  local ids = {}
  for id in pairs(ns.DB.alarmDir or {}) do ids[id] = true end
  for id in pairs(ns.DB.target or {}) do ids[id] = true end
  for id in pairs(ids) do
    local d, t = sigDir(id), ns.DB.target and ns.DB.target[id] or {}
    if d == "buy" or d == "both" or t.buy then b[#b + 1] = { id = id, side = "buy" } end
    if d == "sell" or d == "both" or t.sell then s2[#s2 + 1] = { id = id, side = "sell" } end
  end
  local byName = function(x, y) return ns.itemName(x.id) < ns.itemName(y.id) end
  table.sort(b, byName); table.sort(s2, byName)
  sig.buy:SetData(b); sig.sell:SetData(s2)
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

-- добавить предмет в список покупки или продажи (если он уже в другом - станет «оба»); избранное не трогается
function ns.AddSignal(id, side)
  if not id then return end
  ns.DB.alarmDir = ns.DB.alarmDir or {}
  local d = ns.DB.alarmDir[id]
  ns.DB.alarmDir[id] = (d == nil or d == side) and side or "both"
  ns.Fire("MARKS")
end
-- убрать из одного списка (если был в обоих - останется в другом)
function ns.RemoveSignal(id, side)
  ns.DB.alarmDir = ns.DB.alarmDir or {}
  local t = ns.DB.target and ns.DB.target[id]
  if t then t[side] = nil; if not next(t) then ns.DB.target[id] = nil end end
  local d = ns.DB.alarmDir[id]
  if d == "both" then ns.DB.alarmDir[id] = side == "buy" and "sell" or "buy"
  elseif d == side then ns.DB.alarmDir[id] = nil end
  ns.Fire("MARKS")
end
local function buildSignals(f)
  local info = UI.Font(f, 11, UI.TEXT); info:SetPoint("TOPLEFT", 4, 0); info:SetPoint("RIGHT", -4, 0); info:SetWordWrap(true)
  info:SetText(L"Слева - что хотите купить, справа - что хотите продать. Впишите свою цену: сигнал придёт, когда цена на аукционе опустится до цены покупки или поднимется до цены продажи. Сигналы общие для всех персонажей: снимок аукциона любым из них проверяет весь список.")
  local ah = UI.Font(f, 10, UI.DIM); ah:SetPoint("TOPLEFT", 4, -42); ah:SetText(L"Добавить: впишите название или Shift+клик по предмету, пока поле в фокусе")
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
    col(L"24 ч", -40); col(L"Цена сейчас", -94)
    -- строка: предмет, цена сейчас, изменение за сутки; ниже - своя цена покупки/продажи (сигнал, когда цена до неё дойдёт)
    local list = UI.List(p, 38, function(r)
      r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(22, 22); r.icon:SetPoint("TOPLEFT", 2, -3)
      r.x = UI.Icon(r, "skin\\ai-x", 14, L"Убрать из списка", function(self) local d = self:GetParent().data; if d then ns.RemoveSignal(d.id, side) end end); r.x:SetPoint("TOPRIGHT", -2, -4)
      r.chart = UI.Icon(r, "chart", 14, L"График цены", function(self) local d = self:GetParent().data; if d then ns.ShowChartDialog(d.id) end end); r.chart:SetPoint("RIGHT", r.x, "LEFT", -4, 0)
      r.chg = UI.Font(r, 11); r.chg:SetPoint("RIGHT", r.chart, "LEFT", -8, 0); r.chg:SetWidth(46); r.chg:SetJustifyH("RIGHT")
      r.price = UI.Font(r, 11); r.price:SetPoint("RIGHT", r.chg, "LEFT", -4, 0); r.price:SetWidth(70); r.price:SetJustifyH("RIGHT")
      r.name = UI.Font(r, 11); r.name:SetPoint("LEFT", r.icon, "RIGHT", 5, 0); r.name:SetPoint("RIGHT", r.price, "LEFT", -4, 0)
      r.tl = UI.Font(r, 10, UI.DIM); r.tl:SetPoint("BOTTOMLEFT", 30, 4)
      r.tl:SetText(side == "buy" and L"купить, если не дороже:" or L"продать, если не дешевле:")
      r.money = UI.MoneyInput(r, function(c)
        if not r.data then return end
        ns.DB.target = ns.DB.target or {}
        local t = ns.DB.target[r.data.id] or {}
        t[side] = (c and c > 0) and c or nil
        ns.DB.target[r.data.id] = next(t) and t or nil
        if ns.DB.targetHit then ns.DB.targetHit[r.data.id .. side] = nil end
      end, true)
      r.money:SetPoint("LEFT", r.tl, "RIGHT", 2, 0)
      r:SetScript("OnEnter", function(self) if self.data then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); pcall(GameTooltip.SetItemByID, GameTooltip, self.data.id); GameTooltip:Show() end end)
      r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end, function(r, d)
      r.icon:SetTexture(ns.itemIcon(d.id)); r.name:SetText(ns.itemLinkText(d.id))
      local pr = ns.AHPrice(d.id); r.price:SetText(pr and ns.money(pr, true) or L"|cff777777нет|r")
      local avg = ns.AvgPrice(d.id, 24); r.chg:SetText(pr and avg and ns.pct((pr - avg) / avg * 100) or "")
      local t = ns.DB.target and ns.DB.target[d.id]
      if not r.money:HasFocus() then if t and t[side] then r.money:Set(t[side]) else r.money:Clear() end end
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
  col(L"Всего", -32); col(L"Цена за шт", -140); col(L"Кол-во", -258)
  bank.list = UI.List(f, 24, function(r)
    r.star = UI.Icon(r, "star-off", 16, L"Избранное", function(self) local d = self:GetParent().data; if d then ns.ToggleMark(d.id) end end); r.star:SetPoint("LEFT", 4, 0)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(20, 20); r.icon:SetPoint("LEFT", r.star, "RIGHT", 6, 0)
    r.bell = UI.Bell(r, 16, function(self) local d = self:GetParent().data; return d and d.id end); r.bell:SetPoint("RIGHT", -4, 0)
    r.sum = UI.Font(r, 11); r.sum:SetPoint("RIGHT", r.bell, "LEFT", -8, 0); r.sum:SetWidth(100); r.sum:SetJustifyH("RIGHT")
    r.unit = UI.Font(r, 11); r.unit:SetPoint("RIGHT", r.sum, "LEFT", -8, 0); r.unit:SetWidth(110); r.unit:SetJustifyH("RIGHT")
    r.cnt = UI.Font(r, 12); r.cnt:SetPoint("RIGHT", r.unit, "LEFT", -8, 0); r.cnt:SetWidth(60); r.cnt:SetJustifyH("RIGHT")
    r.name = UI.Font(r, 12); r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0); r.name:SetPoint("RIGHT", r.cnt, "LEFT", -6, 0)
    r:SetScript("OnClick", function(self) if self.data then ns.ShowChartDialog(self.data.id) end end)
    r:SetScript("OnEnter", function(self) if self.data then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); pcall(GameTooltip.SetItemByID, GameTooltip, self.data.id); GameTooltip:AddLine(L"Клик - график цены", 0.9, 0.7, 0.3); GameTooltip:Show() end end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end, function(r, d)
    r.star:SetIcon(ns.IsMarked(d.id) and "star-on" or "star-off"); r.bell:Update(d.id)
    r.icon:SetTexture(ns.itemIcon(d.id)); r.name:SetText(ns.itemLinkText(d.id))
    r.cnt:SetText(d.n .. (d.inBags and d.inBags > 0 and (" |cffaaaaaa(" .. d.inBags .. ")|r") or ""))
    r.unit:SetText(d.p and ns.money(d.p, true) or L"|cff777777нет|r")
    r.sum:SetText(d.p and ns.money(d.p * d.n, true) or "")
  end)
  bank.list:SetPoint("TOPLEFT", 0, -76); bank.list:SetPoint("BOTTOMRIGHT")
end
function refreshBank()
  if not bank.list then return end
  local c = ns.DB.chars[bank.ck or charKey] or {}
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

-- ---------- вкладка «Аукционы»: фракционный (весь аукцион) и общий (что где выгоднее) ----------
-- Сверху - какой аукцион смотрим, поиск и категория (как на аукционе в игре; у каждого аукциона своя).
local KIND_LIST = { "main", "neutral" }
local KIND_TAB = { main = L"Фракционный", neutral = L"Общий" }
local TEXTS = {
  neutral = { none = L"|cffff9966Общий аукцион ещё не записан - отсканируйте аукцион на Острове Зефрис, в Тернистой долине или Танарисе.|r" },
}
-- категории аукциона игры (классы предметов) в том же порядке, что на аукционе
-- (самоцветы, улучшения и символы в этой версии игры устаревшие - их нет)
local CATS = { 2, 4, 1, 0, 7, 9, 17, 12, 15 }
local CAT_RU = { [2] = "Оружие", [4] = "Доспехи", [1] = "Сумки", [3] = "Самоцветы", [8] = "Улучшения", [0] = "Расходуемые", [16] = "Символы",
  [7] = "Хозяйственные товары", [9] = "Рецепты", [17] = "Боевые питомцы", [12] = "Задания", [15] = "Разное" }
-- предметы профессии: готовые (результаты рецептов) и ингредиенты (материалы), по данным рецептов игры
local profSets = {}
local function profSet(slug)
  local ps = profSets[slug]
  if ps then return ps end
  ps = { out = {}, reag = {} }
  local P = ns.RS and ns.RS.prof and ns.RS.prof[slug]
  for _, id in ipairs(P and P.ids or {}) do
    local d = ns.RS.r[id]
    if d then
      if d.cr and d.cr[1] then ps.out[d.cr[1]] = true end
      for _, r in ipairs(d.rg or {}) do ps.reag[r[1]] = true end
    end
  end
  profSets[slug] = ps
  return ps
end
local function profLabel(slug)
  for _, p in ipairs(ns.AllProfessions()) do if p.slug == slug then return p.name end end
  return slug
end
local PART = { out = L"готовые предметы", reag = L"ингредиенты", all = L"всё" }
local function catName(c)
  if c == nil then return L"Все категории" end
  if type(c) == "string" then
    local slug, part = c:match("^p:(.-):(%a+)$")
    if slug then return profLabel(slug) .. ": " .. (PART[part] or "") end
  end
  local n = (C_Item and C_Item.GetItemClassInfo and ns.safe(C_Item.GetItemClassInfo, c)) or (GetItemClassInfo and ns.safe(GetItemClassInfo, c))
  return (n and n ~= "") and n or L(CAT_RU[c] or ("#" .. c))
end
local classCache = {}
local function itemClass(id)
  local c = classCache[id]
  if c == nil then
    local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    c = f and select(6, ns.safe(f, id)) or false
    classCache[id] = c
  end
  return c or nil
end
ns._itemClass = itemClass

local aucp = {}
local refreshAuc
-- строки сравнения: here - цена на смотримом аукционе, there - на другом (thereKind)
-- общий против фракционного: что лучше купить здесь, что лучше продать здесь
local function compareRows(mode, rk)
  local buy, sell, total, have = {}, {}, 0, false
  ns.WithRealm(rk, function()
    local d = ns.AltData(mode, rk)
    have = d ~= nil
    for id, r in pairs(d and d.items or {}) do
      local ah = ns.RegularPrice(id)
      if ah then
        total = total + 1
        local row = { id = id, here = r.p, there = ah }
        -- комиссия: на фракционном 5%, на общем 15%
        local netMain, netHere = ah * (1 - ns.Cut("main")), r.p * (1 - ns.Cut("neutral"))
        if r.p < netMain then row.gain = netMain - r.p; buy[#buy + 1] = row        -- здесь дешевле: купить здесь, продать на фракционном
        elseif netHere > ah then row.gain = netHere - ah; sell[#sell + 1] = row    -- здесь дороже: купить на фракционном, продать здесь
        end
      end
    end
  end)
  return buy, sell, total, have
end
-- весь фракционный аукцион: предмет, цена, количество, изменение за сутки
local function allRows(rk)
  local out = {}
  ns.WithRealm(rk, function()
    local sc = ns.CurrentScan()
    for id, r in pairs(sc and sc.items or {}) do
      local p = ns.RegularPrice(id)
      if p then out[#out + 1] = { id = id, p = p, q = r[2] or 0, lots = r[3] or 0 } end
    end
  end)
  return out
end
local SORTS = { name = L"Название", p = L"Цена", q = L"Кол-во", chg = L"Изм. 24 ч" }
local function buildAuc(f)
  local S = ns.DB.settings
  S.aucCat = S.aucCat or {}
  -- верхняя строка: какой аукцион, поиск, категория
  aucp.kind = {}
  local x = 0
  for _, k in ipairs(KIND_LIST) do
    local b = UI.Button(f, KIND_TAB[k], 80, 26, function() S.aucMode = k; S.aucView = "all"; if aucp.menu then aucp.menu:Hide() end; refreshAuc() end)
    local w = b:FitWidth(80, 170)
    b:SetPoint("TOPLEFT", x, 0); x = x + w + 6
    aucp.kind[k] = b
  end
  -- что смотрим: весь аукцион, свои лоты всех персонажей или сигналы
  aucp.views = {}
  x = x + 10
  for _, v in ipairs({ { "all", L"Весь аукцион", 104 }, { "lots", L"Мои лоты", 128 }, { "signals", L"Сигналы", 84 } }) do
    local b = UI.Button(f, v[2] .. (v[1] == "lots" and " · 00 ● 0" or ""), v[3], 26, function() S.aucView = v[1]; if aucp.menu then aucp.menu:Hide() end; refreshAuc() end)
    local w = b:FitWidth(v[3], 200)
    b:SetPoint("TOPLEFT", x, 0); x = x + w + 6
    aucp.views[v[1]] = b
  end
  aucp.cat = UI.Button(f, L"Все категории", 160, 26, function(self) aucp.openCats(self) end)
  aucp.cat:SetPoint("TOPRIGHT", 0, 0)
  aucp.search = CreateFrame("EditBox", nil, f, "InputBoxTemplate"); aucp.search:SetHeight(20)
  aucp.search:SetPoint("LEFT", aucp.views.signals, "RIGHT", 10, 0); aucp.search:SetPoint("RIGHT", aucp.cat, "LEFT", -8, 0); aucp.search:SetAutoFocus(false)
  aucp.hint = UI.Font(aucp.search, 10, UI.DIM); aucp.hint:SetPoint("LEFT", 2, 0); aucp.hint:SetText(L"поиск по названию...")
  aucp.search:SetScript("OnTextChanged", function(self) aucp.hint:SetShown(self:GetText() == ""); refreshAuc() end)
  aucp.search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
  aucp.search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  -- меню категорий: слева - категории аукциона, справа - профессии (выбор: готовые предметы / ингредиенты / всё)
  function aucp.openCats(anchor, profSlug)
    local m = aucp.menu
    if not m then
      m = CreateFrame("Frame", "WolfichMarketCatMenu", f); m:SetFrameStrata("DIALOG"); m:EnableMouse(true)
      UI.Skin(m, { theme = "acard", scale = 0.25 })
      m.btns = {}; m.heads = {}
      aucp.menu = m
    end
    if m:IsShown() and not profSlug then m:Hide() return end
    local mode = S.aucMode or "main"
    local used = 0
    local function btn(label, col, row, onClick, gold)
      used = used + 1
      local b = m.btns[used] or UI.Button(m, "", 196, 22); m.btns[used] = b
      b:ClearAllPoints(); b:SetPoint("TOPLEFT", 12 + (col - 1) * 204, -30 - (row - 1) * 24)
      b:SetLabel(label); b:SetGold(gold and true or false); b:SetScript("OnClick", onClick); b:Show()
    end
    local function head(i, text, col)
      local h = m.heads[i] or UI.Font(m, 11, UI.GOLD); m.heads[i] = h
      h:ClearAllPoints(); h:SetPoint("TOPLEFT", 16 + (col - 1) * 204, -12); h:SetText(text); h:Show()
    end
    local cur = S.aucCat[mode]
    local function pick(c) return function() m:Hide(); S.aucCat[mode] = c; refreshAuc() end end
    head(1, L"Категории аукциона", 1)
    btn(L"Все категории", 1, 1, pick(nil), cur == nil)
    for i, c in ipairs(CATS) do btn(catName(c), 1, i + 1, pick(c), cur == c) end
    local rows1 = #CATS + 1
    local rows2
    if type(profSlug) == "string" then
      head(2, profLabel(profSlug), 2)
      btn(L"готовые предметы", 2, 1, pick("p:" .. profSlug .. ":out"), cur == "p:" .. profSlug .. ":out")
      btn(L"ингредиенты", 2, 2, pick("p:" .. profSlug .. ":reag"), cur == "p:" .. profSlug .. ":reag")
      btn(L"всё", 2, 3, pick("p:" .. profSlug .. ":all"), cur == "p:" .. profSlug .. ":all")
      btn("|cffaaaaaa< " .. L"все профессии" .. "|r", 2, 4, function() aucp.openCats(anchor, true) end)
      rows2 = 4
    else
      head(2, L"Профессии", 2)
      local list = ns.AllProfessions()
      for i, p in ipairs(list) do
        local pre = "p:" .. p.slug .. ":"
        local isCur = type(cur) == "string" and cur:sub(1, #pre) == pre
        btn(p.name .. " |cffaaaaaa>|r", 2, i, function() aucp.openCats(anchor, p.slug) end, isCur)
      end
      rows2 = #list
    end
    for i = used + 1, #m.btns do m.btns[i]:Hide() end
    m:SetSize(12 + 2 * 204 + 4, 42 + math.max(rows1, rows2) * 24)
    m:ClearAllPoints(); m:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4); m:Show()
  end
  aucp.status = UI.Font(f, 11, UI.DIM); aucp.status:SetPoint("TOPLEFT", 4, -30); aucp.status:SetPoint("RIGHT", -4, 0); aucp.status:SetWordWrap(true)
  -- клик по строке - раскрыть подробности (себестоимость, прибыль, график) под ней
  local function openRow(r)
    r:SetScript("OnClick", function(self) if self.data and self.box then self.box:Toggle(self.data) end end)
    r:SetScript("OnEnter", function(self) if self.data then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); pcall(GameTooltip.SetItemByID, GameTooltip, self.data.id); GameTooltip:AddLine(L"Клик - подробности и график", 0.9, 0.7, 0.3); GameTooltip:Show() end end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  local function detail(list, n) list:EnableDetail(n, function(det) UI.ItemDetail(det) end, function(det, d) det:Set(d.id) end) end
  -- ФРАКЦИОННЫЙ: весь аукцион, как в игре - заголовки столбцов сортируют
  local all = CreateFrame("Frame", nil, f); all:SetPoint("TOPLEFT", 0, -50); all:SetPoint("BOTTOMRIGHT", 0, 0)
  UI.Skin(all, { theme = "acard", scale = 0.25 })
  aucp.all = all
  local COLS = { { "name", 50, nil }, { "p", -210, 110 }, { "q", -130, 70 }, { "chg", -44, 76 } }
  all.heads = {}
  for _, c in ipairs(COLS) do
    local h = CreateFrame("Button", nil, all); h:SetHeight(18)
    if c[1] == "name" then h:SetPoint("TOPLEFT", c[2], -8); h:SetWidth(220) else h:SetPoint("TOPRIGHT", all, "TOPRIGHT", c[2], -8); h:SetWidth(c[3]) end
    h.fs = UI.Font(h, 11, UI.GOLD); h.fs:SetAllPoints(); h.fs:SetJustifyH(c[1] == "name" and "LEFT" or "RIGHT")
    h:SetScript("OnClick", function()
      if S.aucSort == c[1] then S.aucDesc = not S.aucDesc else S.aucSort = c[1]; S.aucDesc = c[1] ~= "name" end
      refreshAuc()
    end)
    all.heads[c[1]] = h
  end
  all.list = UI.List(all, 24, function(r)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(20, 20); r.icon:SetPoint("LEFT", 6, 0)
    r.bell = UI.Bell(r, 16, function(self) local d = self:GetParent().data; return d and d.id end); r.bell:SetPoint("RIGHT", -4, 0)
    r.chg = UI.Font(r, 11); r.chg:SetPoint("RIGHT", -36, 0); r.chg:SetWidth(76); r.chg:SetJustifyH("RIGHT")
    r.q = UI.Font(r, 11, UI.DIM); r.q:SetPoint("RIGHT", -122, 0); r.q:SetWidth(70); r.q:SetJustifyH("RIGHT")
    r.p = UI.Font(r, 11); r.p:SetPoint("RIGHT", -202, 0); r.p:SetWidth(110); r.p:SetJustifyH("RIGHT")
    r.name = UI.Font(r, 11); r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0); r.name:SetPoint("RIGHT", r.p, "LEFT", -8, 0)
    openRow(r)
  end, function(r, x)
    r.icon:SetTexture(ns.itemIcon(x.id)); r.name:SetText(ns.itemLinkText(x.id)); r.bell:Update(x.id)
    r.p:SetText(ns.money(x.p, true)); r.q:SetText(x.q)
    if x.chg == nil then local a = ns.AvgPrice(x.id, 24); x.chg = a and a > 0 and (x.p - a) / a * 100 or false end
    r.chg:SetText(x.chg and ns.pct(x.chg) or "|cff555555-|r")
  end)
  all.list:SetPoint("TOPLEFT", 4, -28); all.list:SetPoint("BOTTOMRIGHT", -4, 6)
  detail(all.list, 7)
  -- ОБЩИЙ: две колонки - что лучше купить здесь и что лучше продать здесь
  local function panel(left)
    local p = CreateFrame("Frame", nil, f)
    if left then p:SetPoint("TOPLEFT", 0, -50); p:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -6, 0)
    else p:SetPoint("TOPLEFT", f, "TOP", 6, -50); p:SetPoint("BOTTOMRIGHT", 0, 0) end
    UI.Skin(p, { theme = "acard", scale = 0.25 })
    p.title = UI.Font(p, 13, UI.GOLD); p.title:SetPoint("TOPLEFT", 12, -10); p.title:SetPoint("RIGHT", -12, 0)
    p.list = UI.List(p, 36, function(r)
      r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(24, 24); r.icon:SetPoint("LEFT", 4, 0)
      r.gain = UI.Font(r, 12); r.gain:SetPoint("TOPRIGHT", -4, -4); r.gain:SetJustifyH("RIGHT"); r.gain:SetWidth(90)
      r.name = UI.Font(r, 11); r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 6, 2); r.name:SetPoint("RIGHT", r.gain, "LEFT", -4, 0)
      r.sub = UI.Font(r, 10, UI.DIM); r.sub:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 6, -3); r.sub:SetPoint("RIGHT", -4, 0)
      openRow(r)
    end, function(r, x)
      local mode = ns.DB.settings.aucMode or "main"
      r.icon:SetTexture(ns.itemIcon(x.id)); r.name:SetText(ns.itemLinkText(x.id))
      r.gain:SetText("|cff78d98a+" .. ns.money(x.gain, true) .. "|r")
      r.sub:SetText(L"здесь" .. " " .. ns.money(x.here, true) .. "   |cff888888" .. L"фракционный" .. "|r " .. ns.money(x.there, true))
    end)
    p.list:SetPoint("TOPLEFT", 8, -30); p.list:SetPoint("BOTTOMRIGHT", -8, 8)
    p.list:EnableDetail(5, function(det) UI.ItemDetail(det, { leftW = 130, compact = true }) end, function(det, d) det:Set(d.id) end)
    return p
  end
  aucp.buy, aucp.dear = panel(true), panel(false)
  -- МОИ ЛОТЫ: всё, что выставлено всеми персонажами (продано, срок, сколько осталось)
  local lots = CreateFrame("Frame", nil, f); lots:SetPoint("TOPLEFT", 0, -50); lots:SetPoint("BOTTOMRIGHT", 0, 0)
  UI.Skin(lots, { theme = "acard", scale = 0.25 })
  local lh = CreateFrame("Frame", nil, lots); lh:SetPoint("TOPLEFT", 12, -8); lh:SetPoint("TOPRIGHT", -12, -8); lh:SetHeight(16)
  local function lcol(t, x, left) local c = UI.Font(lh, 11, UI.GOLD); c:SetPoint(left and "LEFT" or "RIGHT", lh, left and "LEFT" or "RIGHT", x, 0); c:SetText(t) end
  lcol(L"Персонаж", 4, true); lcol(L"Предмет", 150, true); lcol(L"Кол.", -330); lcol(L"Цена за шт", -228); lcol(L"Состояние", -60)
  lots.list = UI.List(lots, 24, function(r)
    r.who = UI.Font(r, 11); r.who:SetPoint("LEFT", 4, 0); r.who:SetWidth(130)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(18, 18); r.icon:SetPoint("LEFT", 140, 0)
    r.bell = UI.Bell(r, 15, function(self) local d = self:GetParent().data; return d and d.id end); r.bell:SetPoint("RIGHT", -4, 0)
    r.st = UI.Font(r, 11); r.st:SetPoint("RIGHT", r.bell, "LEFT", -8, 0); r.st:SetWidth(170); r.st:SetJustifyH("RIGHT")
    r.p = UI.Font(r, 11); r.p:SetPoint("RIGHT", -228, 0); r.p:SetWidth(90); r.p:SetJustifyH("RIGHT")
    r.q = UI.Font(r, 11, UI.DIM); r.q:SetPoint("RIGHT", -330, 0); r.q:SetWidth(40); r.q:SetJustifyH("RIGHT")
    r.name = UI.Font(r, 11); r.name:SetPoint("LEFT", r.icon, "RIGHT", 5, 0); r.name:SetPoint("RIGHT", r.q, "LEFT", -6, 0)
    openRow(r)
  end, function(r, x)
    r.who:SetText(charLabel(x.ck)); r.icon:SetTexture(ns.itemIcon(x.id)); r.name:SetText(ns.itemLinkText(x.id)); r.bell:Update(x.id)
    r.q:SetText(x.q or 1); r.p:SetText(x.p and ns.money(x.p, true) or "-"); r.st:SetText(ns.LotStatus(x))
  end)
  lots.list:SetPoint("TOPLEFT", 8, -28); lots.list:SetPoint("BOTTOMRIGHT", -8, 8)
  lots.list:EnableDetail(7, function(det) UI.ItemDetail(det) end, function(det, d) det:Set(d.id) end, function(d) return (d.ck or "") .. ":" .. (d.aid or d.id) end)
  lots.list.empty:SetText(L"Выставленных лотов нет. Список обновляется, когда персонаж открывает аукцион.")
  aucp.lots = lots
  -- СИГНАЛЫ: что купить дешевле и что продать дороже (своя цена)
  local sf = CreateFrame("Frame", nil, f); sf:SetPoint("TOPLEFT", 0, -30); sf:SetPoint("BOTTOMRIGHT")
  buildSignals(sf)
  aucp.sig = sf
end
function refreshAuc()
  if not aucp.status then return end
  local S = ns.DB.settings
  local mode = S.aucMode or "main"
  local cat = S.aucCat and S.aucCat[mode]
  local vw = S.aucView or "all"
  for k, b in pairs(aucp.kind) do b:SetGold(vw == "all" and k == mode) end
  for k, b in pairs(aucp.views) do b:SetGold(k == vw) end
  local _, _, newSold = ns.LotsSummary()
  local nLots = ns.LotsSummary()
  aucp.views.lots:SetLabel(L"Мои лоты" .. " · " .. nLots .. (newSold > 0 and (" |cffff9b8a● " .. newSold .. "|r") or ""))
  aucp.cat:SetLabel(catName(cat)); aucp.cat:SetShown(vw == "all")
  aucp.search:SetShown(vw ~= "signals")
  aucp.lots:SetShown(vw == "lots"); aucp.sig:SetShown(vw == "signals"); aucp.status:SetShown(vw ~= "signals")
  if vw == "signals" then aucp.all:Hide(); aucp.buy:Hide(); aucp.dear:Hide(); refreshSignals() return end
  if vw == "lots" then
    aucp.all:Hide(); aucp.buy:Hide(); aucp.dear:Hide()
    local q = ns.lower(aucp.search:GetText() or "")
    local rows = {}
    for _, ck in ipairs(ns.AltList()) do
      for _, l in ipairs(ns.CharLots(ck)) do
        if q == "" or ns.lower(ns.itemName(l.id) or ""):find(q, 1, true) then
          rows[#rows + 1] = { ck = ck, id = l.id, aid = l.aid, q = l.q, p = l.p, ends = l.ends, st = l.st, soldAt = l.soldAt }
        end
      end
    end
    aucp.lots.list:SetData(rows)
    local n, sold = ns.LotsSummary()
    aucp.status:SetText(string.format(L"Лоты всех персонажей: %d, продано: %d. Список персонажа обновляется, когда он открывает аукцион; продажи - по сообщению игры и письмам на почте.", n, sold))
    -- просмотрели - конверты гаснут
    if aucp.lots:IsVisible() then for _, ck in ipairs(ns.AltList()) do local c = ns.DB.chars[ck]; if c and c.lotsNew then c.lotsNew = nil end end end
    return
  end
  local c = ns.DB.chars[charKey] or {}
  local rk = c.realmKey or ns.realmKey or ""
  -- категория (класс предмета или профессия: готовое / ингредиенты) и поиск
  local inCat
  if cat == nil then inCat = function() return true end
  elseif type(cat) == "string" then
    local slug, part = cat:match("^p:(.-):(%a+)$")
    local ps = slug and profSet(slug) or { out = {}, reag = {} }
    inCat = function(id) return (part ~= "reag" and ps.out[id]) or (part ~= "out" and ps.reag[id]) or false end
  else inCat = function(id) return itemClass(id) == cat end end
  local q = ns.lower(aucp.search:GetText() or "")
  local function filter(list)
    local out = {}
    for _, x in ipairs(list) do
      if inCat(x.id) and (q == "" or ns.lower(ns.itemName(x.id) or ""):find(q, 1, true)) then out[#out + 1] = x end
    end
    return out
  end
  local isMain = mode == "main"
  aucp.all:SetShown(isMain); aucp.buy:SetShown(not isMain); aucp.dear:SetShown(not isMain)
  if isMain then
    local rows = filter(allRows(rk))
    local key, desc = S.aucSort or "name", S.aucDesc
    if key == "chg" then for _, x in ipairs(rows) do local a = ns.AvgPrice(x.id, 24); x.chg = a and a > 0 and (x.p - a) / a * 100 or false end end
    table.sort(rows, function(a, b)
      local x, y
      if key == "name" then x, y = ns.itemName(a.id) or "", ns.itemName(b.id) or ""
      else x, y = a[key] or -1e12, b[key] or -1e12; if x == false then x = -1e12 end; if y == false then y = -1e12 end end
      if x == y then return a.id < b.id end
      if desc then return x > y end
      return x < y
    end)
    for k, h in pairs(aucp.all.heads) do h.fs:SetText(SORTS[k] .. (k == key and (desc and " v" or " ^") or "")) end
    aucp.all.list:SetData(rows)
    aucp.all.list.empty:SetText(L"Нет цен - отсканируйте фракционный аукцион.")
    local sc = ns.WithRealm(rk, function() return ns.CurrentScan() end)
    aucp.status:SetText(string.format(L"Фракционный аукцион: %s, предметов: %d. Клик по заголовку - сортировка, по строке - график цены.", sc and (L"снимок " .. ns.ago(sc.t)) or L"снимка нет", #rows))
    return
  end
  local buy, sell, total, have = compareRows(mode, rk)
  buy, sell = filter(buy), filter(sell)
  table.sort(buy, function(a, b) return a.gain > b.gain end)
  table.sort(sell, function(a, b) return a.gain > b.gain end)
  aucp.buy.title:SetText(L"Лучше купить здесь"); aucp.dear.title:SetText(L"Лучше продать здесь")
  aucp.buy.list:SetData(buy); aucp.dear.list:SetData(sell)
  aucp.buy.list.empty:SetText(have and L"Здесь нет ничего дешевле фракционного." or "")
  aucp.dear.list.empty:SetText(have and L"Здесь нет ничего дороже фракционного." or "")
  if not have then aucp.status:SetText(TEXTS[mode].none) return end
  local d = ns.AltData(mode, rk)
  aucp.status:SetText(string.format(L"%s: снимок %s. Слева - здесь дешевле, чем на фракционном, справа - здесь дороже; с учётом комиссии (фракционный 5%%, общий 15%%). Справа число - сколько выгоднее.", KIND_TAB[mode], ns.ago(d.t)))
end

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

-- ---------- вкладка «Настройки» (те же, что у аукциониста) ----------
local setp = {}
local function buildSettings(f)
  local S = ns.DB.settings
  local function hl(b, on) b:SetGold(on) end
  local function column(x, title)
    local t = UI.Font(f, 13, UI.GOLD); t:SetPoint("TOPLEFT", x, 0); t:SetText(title)
    return { x = x, y = -24 }
  end
  local function chk(col, text, key, after, inverted)
    local c = UI.Check(f, text, function() if inverted then return S[key] ~= false end return S[key] end, function(v) S[key] = v; if after then after(v) end end)
    c:SetPoint("TOPLEFT", col.x, col.y); col.y = col.y - 26
    return c
  end
  local function buttons(col, label, list, get, set)
    local l = UI.Font(f, 11); l:SetPoint("TOPLEFT", col.x + 4, col.y - 4); l:SetText(label)
    local bs, x = {}, col.x + 130
    for _, o in ipairs(list) do
      local b = UI.Button(f, o[2], o[3] or 84, 20, function() set(o[1]); setp.refresh() end)
      b:SetPoint("TOPLEFT", x, col.y); b.val = o[1]; x = x + (o[3] or 84) + 4
      bs[#bs + 1] = b
    end
    col.y = col.y - 30
    return function() local v = get(); for _, b in ipairs(bs) do hl(b, b.val == v) end end
  end
  local a = column(0, L"Цены и сигналы")
  chk(a, L"Уведомления сигналов (когда цена дошла до вашей)", "alerts")
  chk(a, L"Звук уведомлений", "alertSound")
  chk(a, L"Уведомление о лучшем крафте после снимка", "bestCraftAlert")
  chk(a, L"Цена и прибыль в подсказке предмета", "tooltip")
  chk(a, L"Снимать аукцион автоматически, пока он открыт", "autoScan")
  local rAuto = buttons(a, L"Автоснимок раз в:", { { 15, "15 " .. L"мин", 64 }, { 30, "30 " .. L"мин", 64 }, { 60, "60 " .. L"мин", 64 } }, function() return S.autoScanMin end, function(v) S.autoScanMin = v end)
  local t2 = UI.Font(f, 13, UI.GOLD); t2:SetPoint("TOPLEFT", a.x, a.y - 8); t2:SetText(L"Общий рынок"); a.y = a.y - 32
  chk(a, L"Делиться своими снимками с игроками", "netSend", nil, true)
  chk(a, L"Принимать цены от игроков", "netRecv", nil, true)
  chk(a, L"Турбо: рассылка через 4 имени (в 2-4 раза быстрее)", "netTurbo", nil, true)
  local net = UI.Button(f, L"Проверить связь (/wmnet)", 200, 22, function() if SlashCmdList.WOLFICHMARKET then SlashCmdList.WOLFICHMARKET("net") end end)
  net:SetPoint("TOPLEFT", a.x, a.y - 2)

  local b = column(410, L"Интерфейс")
  chk(b, L"Кнопка у миникарты (после перезагрузки интерфейса)", "minimapShown", function() S.minimapHidden = not S.minimapShown end)
  chk(b, L"Значки в сумках: молоток - на аукцион, мешочек - торговцу", "bagGlow", function() if ns.UpdateBagGlow then ns.UpdateBagGlow() end end)
  chk(b, L"Сортировка сумок: аукцион наверх, торговцу вниз", "sortByValue")
  chk(b, L"Окошко стоимости сумок (перетаскивается)", "bagValue", function() if ns.UpdateBagValue then ns.UpdateBagValue() end end, true)
  local rChat = buttons(b, L"Сообщения:", { { "window", L"в журнал", 80 }, { "main", L"в чат", 64 }, { "off", L"никуда", 70 } }, function() return S.chatMode or "window" end, function(v) S.chatMode = v end)
  local rLang = buttons(b, L"Язык:", { { "auto", L"Авто", 64 }, { "ru", "Русский", 74 }, { "en", "English", 74 } }, function() return S.lang or "auto" end, function(v) S.lang = v; setp.reload:Show(); setp.note:Show() end)
  setp.note = UI.Font(f, 10, UI.GOLD); setp.note:SetPoint("TOPLEFT", b.x + 4, b.y - 2); setp.note:SetText(L"Язык меняется после перезагрузки интерфейса."); setp.note:Hide()
  setp.reload = UI.Button(f, L"Перезагрузить интерфейс", 190, 22, function() if ReloadUI then ReloadUI() end end, true)
  setp.reload:SetPoint("TOPLEFT", b.x, b.y - 18); setp.reload:Hide()
  -- окно профессии игры: таблица цен и столбики можно выключить; кулдауны; журнал
  local t3 = UI.Font(f, 13, UI.GOLD); t3:SetPoint("TOPLEFT", b.x, b.y - 48); t3:SetText(L"Окно профессии игры и часы"); b.y = b.y - 72
  chk(b, L"Таблица «Где купить и где продать» и столбики Ф / Общ", "profUI", function() if ns.DecorateRecipeRows then ns.DecorateRecipeRows() end; if ns.RefreshMarketTable then ns.RefreshMarketTable() end end, true)
  chk(b, L"Уведомлять, когда готов кулдаун (трансмутации)", "cdNotify", nil, true)
  local jb = UI.Button(f, L"Открыть журнал", 170, 22, function() ns.OpenLog() end, true); jb:SetPoint("TOPLEFT", b.x, b.y - 6)
  jb:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(L"Все сообщения аддона: снимки, общий рынок, сигналы, продажи и кулдауны.", 1, 1, 1, true); GameTooltip:Show() end)
  jb:SetScript("OnLeave", function() GameTooltip:Hide() end)
  setp.journal = jb
  local about = UI.Font(f, 10, UI.DIM); about:SetPoint("BOTTOMLEFT", 4, 4); about:SetPoint("RIGHT", -4, 0); about:SetWordWrap(true)
  about:SetText("WolfichMarket " .. (ns.VERSION or "") .. L"  -  обновление: WolfichMarket-Updater.bat с сайта или CurseForge.  Команды: /wm help")
  setp.refresh = function() rAuto(); rChat(); rLang() end
end
local function refreshSettings() if setp.refresh then setp.refresh() end end
-- ---------- всплывающие окна поверх раздела (банк, лоты, журнал): по центру рамки ----------
local function makePopup(name, w, h, title)
  local content = win.content
  local dim = CreateFrame("Button", nil, content); dim:SetAllPoints(); dim:SetFrameLevel((content:GetFrameLevel() or 1) + 40)
  local shade = dim:CreateTexture(nil, "BACKGROUND"); shade:SetPoint("TOPLEFT", -40, 40); shade:SetPoint("BOTTOMRIGHT", 40, -40); shade:SetColorTexture(0, 0, 0, 0.6)
  dim:SetScript("OnClick", function(self) self:Hide() end) -- клик мимо окна - закрыть
  local p = CreateFrame("Frame", name, dim); p:SetSize(w, h); p:SetPoint("CENTER"); p:EnableMouse(true)
  UI.Skin(p, { theme = "main", scale = 0.6 })
  p.title = UI.Title(p, title)
  UI.Close(p, function() dim:Hide() end)
  p.body = CreateFrame("Frame", nil, p); p.body:SetPoint("TOPLEFT", 26, -58); p.body:SetPoint("BOTTOMRIGHT", -26, 20)
  p.dim = dim
  dim:Hide()
  return p
end
local pops = {}
-- банк персонажа
local function openBank(ck)
  if not pops.bank then pops.bank = makePopup("WolfichMarketBankPopup", 700, 440, L"Банк"); buildBank(pops.bank.body) end
  bank.ck = ck
  local nm = (ns.DB.chars[ck] or {}).name or ck
  pops.bank.title:SetText(L"Банк" .. " - " .. nm)
  pops.bank.dim:Show(); refreshBank()
end
-- лоты персонажа на аукционе
local function fillLotsPopup()
  local p = pops.lots
  if not p or not p.dim:IsShown() then return end
  p.list:SetData(ns.CharLots(p.ck))
  local c = ns.DB.chars[p.ck] or {}
  p.info:SetText(c.lotsT and (L"обновлено" .. " " .. ns.ago(c.lotsT) .. L" |cffaaaaaa(когда персонаж открывал аукцион)|r") or L"|cffff9966Лотов нет или аукцион этим персонажем ещё не открывали.|r")
end
local function openLots(ck)
  local p = pops.lots
  if not p then
    p = makePopup("WolfichMarketLotsPopup", 680, 380, L"Аукцион"); pops.lots = p
    p.info = UI.Font(p.body, 10, UI.DIM); p.info:SetPoint("TOPLEFT", 2, 0); p.info:SetPoint("RIGHT", -2, 0)
    local hd = CreateFrame("Frame", nil, p.body); hd:SetPoint("TOPLEFT", 0, -18); hd:SetPoint("TOPRIGHT", 0, -18); hd:SetHeight(14)
    local function col(t, x, left) local c = UI.Font(hd, 10, UI.GOLD); c:SetPoint(left and "LEFT" or "RIGHT", hd, left and "LEFT" or "RIGHT", x, 0); c:SetText(t) end
    col(L"Предмет", 28, true); col(L"Кол.", -300); col(L"Цена за шт", -196); col(L"Состояние", -28)
    p.list = UI.List(p.body, 22, function(r)
      r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(18, 18); r.icon:SetPoint("LEFT", 4, 0)
      r.bell = UI.Bell(r, 15, function(self) local d = self:GetParent().data; return d and d.id end); r.bell:SetPoint("RIGHT", -2, 0)
      r.st = UI.Font(r, 11); r.st:SetPoint("RIGHT", r.bell, "LEFT", -6, 0); r.st:SetWidth(160); r.st:SetJustifyH("RIGHT")
      r.p = UI.Font(r, 11); r.p:SetPoint("RIGHT", -196, 0); r.p:SetWidth(90); r.p:SetJustifyH("RIGHT")
      r.q = UI.Font(r, 11, UI.DIM); r.q:SetPoint("RIGHT", -300, 0); r.q:SetWidth(40); r.q:SetJustifyH("RIGHT")
      r.name = UI.Font(r, 11); r.name:SetPoint("LEFT", r.icon, "RIGHT", 5, 0); r.name:SetPoint("RIGHT", r.q, "LEFT", -6, 0)
      r:SetScript("OnEnter", function(self) if self.data then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); pcall(GameTooltip.SetItemByID, GameTooltip, self.data.id); GameTooltip:Show() end end)
      r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end, function(r, l)
      r.icon:SetTexture(ns.itemIcon(l.id)); r.name:SetText(ns.itemLinkText(l.id)); r.bell:Update(l.id)
      r.q:SetText(l.q or 1); r.p:SetText(l.p and ns.money(l.p, true) or "-"); r.st:SetText(ns.LotStatus(l))
    end)
    p.list:SetPoint("TOPLEFT", 0, -34); p.list:SetPoint("BOTTOMRIGHT")
    p.list.empty:SetText(L"Лотов нет.")
  end
  p.ck = ck
  local nm = (ns.DB.chars[ck] or {}).name or ck
  p.title:SetText(L"Аукцион" .. " - " .. nm)
  p.dim:Show(); fillLotsPopup()
  ns.SeenLots(ck) -- конверт гаснет
end
-- журнал сообщений аддона
function ns.OpenLog()
  if not win then return end
  if not pops.log then pops.log = makePopup("WolfichMarketLogPopup", 720, 440, L"Журнал"); buildLog(pops.log.body) end
  pops.log.dim:Show(); refreshLog()
end

-- ---------- раздел «Главная»: что нового в каждой версии (язык - как у аддона) ----------
local home = {}
local function buildHome(f)
  local t = UI.Font(f, 18, UI.GOLD, "OVERLAY", "OUTLINE"); t:SetPoint("TOPLEFT", 2, 0); t:SetText(L"Что нового")
  local sub = UI.Font(f, 11, UI.DIM); sub:SetPoint("TOPLEFT", 2, -26); sub:SetPoint("RIGHT", -4, 0); sub:SetWordWrap(true)
  sub:SetText(L"Изменения каждой версии. Язык - как у аддона (по языку игры; можно сменить в настройках).")
  local sf = CreateFrame("ScrollFrame", nil, f); sf:SetPoint("TOPLEFT", 0, -48); sf:SetPoint("BOTTOMRIGHT", 0, 0)
  if sf.SetClipsChildren then sf:SetClipsChildren(true) end
  local child = CreateFrame("Frame", nil, sf); child:SetSize(780, 400); sf:SetScrollChild(child)
  local cur = 0
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function(self, d)
    local max = math.max(0, (child:GetHeight() or 0) - (self:GetHeight() or 0))
    cur = math.max(0, math.min(max, cur - d * 40)); self:SetVerticalScroll(cur)
  end)
  home.child, home.cards, home.sf = child, {}, sf
end
local function refreshHome()
  if not home.child then return end
  local W = (home.sf:GetWidth() or 0) > 100 and home.sf:GetWidth() or 790
  home.child:SetWidth(W)
  local lang = ns.Lang()
  local y = 0
  for i, e in ipairs(ns.CHANGELOG or {}) do
    local c = home.cards[i]
    if not c then
      c = CreateFrame("Frame", nil, home.child)
      c.bg = c:CreateTexture(nil, "BACKGROUND"); c.bg:SetAllPoints(); c.bg:SetColorTexture(0, 0, 0, 0.35)
      c.edge = c:CreateTexture(nil, "BORDER"); c.edge:SetPoint("TOPLEFT"); c.edge:SetPoint("BOTTOMLEFT"); c.edge:SetWidth(3)
      c.v = UI.Font(c, 15, UI.GOLD, "OVERLAY", "OUTLINE"); c.v:SetPoint("TOPLEFT", 16, -10)
      c.d = UI.Font(c, 10, UI.DIM); c.d:SetPoint("LEFT", c.v, "RIGHT", 10, -1)
      c.lines = {}
      home.cards[i] = c
    end
    c:ClearAllPoints(); c:SetPoint("TOPLEFT", 0, -y); c:SetWidth(W - 6)
    c.v:SetText(e.v); c.d:SetText((i == 1 and ("|cffffd24a" .. L"НОВОЕ" .. "|r   ") or "") .. (e.d or ""))
    c.edge:SetColorTexture(i == 1 and 0.95 or 0.45, i == 1 and 0.78 or 0.38, i == 1 and 0.38 or 0.22, 1)
    local list = (lang == "en" and e.en) or e.ru or {}
    local ly = 34
    for k, txt in ipairs(list) do
      local fs = c.lines[k] or UI.Font(c, 12, UI.TEXT); c.lines[k] = fs
      fs:SetWordWrap(true); fs:SetJustifyV("TOP")
      fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", 30, -ly); fs:SetWidth(W - 60); fs:SetText("|cfff2c761•|r  " .. txt); fs:Show()
      local h = fs:GetStringHeight(); if type(h) ~= "number" or h < 12 then h = 15 * math.max(1, math.ceil(#txt / 140)) end
      ly = ly + h + 5
    end
    for k = #list + 1, #c.lines do c.lines[k]:Hide() end
    c:SetHeight(ly + 8); c:Show()
    y = y + ly + 8 + 12
  end
  home.child:SetHeight(math.max(10, y))
end

-- ---------- раздел «Твинки»: персонажи аккаунта ----------
local alts = {}
local function profLines(c)
  local out = {}
  for name, p in pairs(c.profs or {}) do if not p.virtual then out[#out + 1] = { name, p.skill or 0, p.max or 0 } end end
  table.sort(out, function(a, b) return a[1] < b[1] end)
  return out
end
local function buildAlts(f)
  local t = UI.Font(f, 18, UI.GOLD, "OVERLAY", "OUTLINE"); t:SetPoint("TOPLEFT", 2, 0); t:SetText(L"Персонажи аккаунта")
  alts.sum = UI.Font(f, 11, UI.DIM); alts.sum:SetPoint("TOPRIGHT", -4, -4); alts.sum:SetJustifyH("RIGHT")
  local sf = CreateFrame("ScrollFrame", nil, f); sf:SetPoint("TOPLEFT", 0, -32); sf:SetPoint("BOTTOMRIGHT", 0, 0)
  if sf.SetClipsChildren then sf:SetClipsChildren(true) end
  local child = CreateFrame("Frame", nil, sf); child:SetSize(800, 400); sf:SetScrollChild(child)
  local cur = 0
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function(self, d)
    local max = math.max(0, (child:GetHeight() or 0) - (self:GetHeight() or 0))
    cur = math.max(0, math.min(max, cur - d * 40)); self:SetVerticalScroll(cur)
  end)
  alts.child, alts.sf, alts.cards = child, sf, {}
end
local CARD_W, CARD_H = 258, 222
local function altCard(i)
  local c = alts.cards[i]
  if c then return c end
  c = CreateFrame("Frame", nil, alts.child); c:SetSize(CARD_W, CARD_H)
  UI.Skin(c, { theme = "acard", scale = 0.22 })
  c.hl = c:CreateTexture(nil, "BACKGROUND", nil, -6); c.hl:SetPoint("TOPLEFT", 6, -6); c.hl:SetPoint("BOTTOMRIGHT", -6, 6); c.hl:SetColorTexture(0.75, 0.25, 0.18, 0.16)
  c.name = UI.Font(c, 14, nil, "OVERLAY", "OUTLINE"); c.name:SetPoint("TOPLEFT", 16, -14); c.name:SetPoint("RIGHT", -56, 0)
  c.you = UI.Font(c, 10, UI.GOLD); c.you:SetPoint("TOPRIGHT", -16, -16); c.you:SetText(L"ВЫ")
  -- конверт с печатью: что-то продалось (клик - список лотов)
  c.env = CreateFrame("Button", nil, c); c.env:SetSize(40, 30); c.env:SetPoint("TOPRIGHT", -12, -8)
  c.env.tex = c.env:CreateTexture(nil, "ARTWORK"); c.env.tex:SetAllPoints(); UI.WinTex(c.env.tex, "envelope")
  c.env:SetScript("OnClick", function() openLots(c.ck) end)
  c.env:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(L"Есть проданные лоты - заберите деньги на почте", 1, 0.82, 0, true); GameTooltip:Show() end)
  c.env:SetScript("OnLeave", function() GameTooltip:Hide() end)
  c.l2 = UI.Font(c, 11, UI.DIM); c.l2:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -4)
  c.l3 = UI.Font(c, 10, UI.DIM); c.l3:SetPoint("TOPLEFT", c.l2, "BOTTOMLEFT", 0, -3); c.l3:SetPoint("RIGHT", -16, 0)
  c.sep = c:CreateTexture(nil, "ARTWORK"); c.sep:SetHeight(1); c.sep:SetPoint("TOPLEFT", 16, -66); c.sep:SetPoint("TOPRIGHT", -16, -66); c.sep:SetColorTexture(0.55, 0.42, 0.2, 0.6)
  c.rows = {}
  for k = 1, 5 do
    local a = UI.Font(c, 11, UI.DIM); a:SetPoint("TOPLEFT", 16, -74 - (k - 1) * 18)
    local b = UI.Font(c, 11); b:SetPoint("TOPRIGHT", -16, -74 - (k - 1) * 18); b:SetJustifyH("RIGHT")
    c.rows[k] = { a, b }
  end
  c.note = UI.Font(c, 10, { 1, 0.6, 0.54 }); c.note:SetPoint("BOTTOMLEFT", 16, 44); c.note:SetPoint("RIGHT", -16, 0)
  c.bank = UI.Button(c, L"Банк", 108, 24, function() openBank(c.ck) end); c.bank:SetPoint("BOTTOMLEFT", 14, 14)
  c.auc = UI.Button(c, L"Аукцион", 108, 24, function() openLots(c.ck) end); c.auc:SetPoint("BOTTOMRIGHT", -14, 14)
  alts.cards[i] = c
  return c
end
local function refreshAlts()
  if not alts.child then return end
  local list = ns.AltList()
  local W = (alts.sf:GetWidth() or 0) > 100 and alts.sf:GetWidth() or 812
  alts.child:SetWidth(W)
  local per = math.max(1, math.floor((W + 10) / (CARD_W + 10)))
  local gold, lots = 0, 0
  for i, ck in ipairs(list) do
    local c = ns.DB.chars[ck] or {}
    local card = altCard(i)
    card.ck = ck
    local col, row = (i - 1) % per, math.floor((i - 1) / per)
    card:ClearAllPoints(); card:SetPoint("TOPLEFT", col * (CARD_W + 10), -row * (CARD_H + 10))
    card.name:SetText(charLabel(ck))
    card.you:SetShown(ck == ns.charKey)
    card.l2:SetText((c.level and (L"Уровень" .. " " .. c.level) or "") .. ((c.race or c.className) and (", " .. (c.race or "") .. " " .. (c.className or "")) or ""))
    local online = ck == ns.charKey
    card.l3:SetText((c.zone and (c.zone .. " · ") or "") .. (online and ("|cff78d98a" .. L"сейчас в сети" .. "|r") or (L"был в сети" .. " " .. ns.ago(c.seen))))
    local rows = { { L"Золото", c.money and ns.money(c.money, true) or "|cff777777?|r" } }
    for _, p in ipairs(profLines(c)) do if #rows < 5 then rows[#rows + 1] = { p[1], p[2] .. " / " .. p[3] } end end
    for k, r in ipairs(card.rows) do
      local d = rows[k]
      if d then r[1]:SetText(d[1]); r[2]:SetText(d[2]); r[1]:Show(); r[2]:Show() else r[1]:Hide(); r[2]:Hide() end
    end
    local all, sold = 0, 0
    for _, l in ipairs(c.lots or {}) do all = all + 1; if l.st == "sold" then sold = sold + 1 end end
    lots = lots + all; gold = gold + (c.money or 0)
    card.env:SetShown(c.lotsNew and true or false); card.hl:SetShown(c.lotsNew and true or false)
    card.note:SetText(c.lotsNew and string.format(L"Продано лотов: %d - заберите на почте", sold) or (c.bankT and "" or L"|cff999999Банк ещё не открывали|r"))
    card.auc:SetLabel(L"Аукцион" .. " · " .. (all - sold)); card.auc:SetGold(c.lotsNew and true or false)
    card:Show()
  end
  for i = #list + 1, #alts.cards do alts.cards[i]:Hide() end
  alts.child:SetHeight(math.ceil(#list / per) * (CARD_H + 10))
  alts.sum:SetText(L"Всего золота" .. ": " .. ns.money(gold, true) .. "   " .. L"лотов на аукционе" .. ": " .. lots)
end

-- ---------- раздел «Часы»: кулдауны трансмутаций и других рецептов ----------
local cdp = {}
local function buildCds(f)
  local t = UI.Font(f, 18, UI.GOLD, "OVERLAY", "OUTLINE"); t:SetPoint("TOPLEFT", 2, 0); t:SetText(L"Кулдауны трансмутаций")
  local sub = UI.Font(f, 11, UI.DIM); sub:SetPoint("TOPLEFT", 2, -26); sub:SetPoint("RIGHT", -230, 0); sub:SetWordWrap(true)
  sub:SetText(L"Аддон запоминает, когда персонаж провёл трансмутацию, и считает, когда можно снова. Готово - надпись сверху экрана и свечение часов слева.")
  local S = ns.DB.settings
  local chk = UI.Check(f, L"уведомлять, когда готово", function() return S.cdNotify ~= false end, function(v) S.cdNotify = v end)
  chk:SetPoint("TOPRIGHT", -170, -2)
  local hd = CreateFrame("Frame", nil, f); hd:SetPoint("TOPLEFT", 0, -62); hd:SetPoint("TOPRIGHT", 0, -62); hd:SetHeight(14)
  local function col(txt, x) local c = UI.Font(hd, 10, UI.GOLD); c:SetPoint("LEFT", x, 0); c:SetText(txt) end
  col(L"Рецепт", 34); col(L"Персонаж", 360); col(L"Осталось", 500)
  cdp.list = UI.List(f, 36, function(r)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(26, 26); r.icon:SetPoint("LEFT", 4, 0)
    r.name = UI.Font(r, 12); r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0); r.name:SetWidth(320)
    r.who = UI.Font(r, 11); r.who:SetPoint("LEFT", 360, 0); r.who:SetWidth(130)
    r.left = UI.Font(r, 12); r.left:SetPoint("TOPLEFT", 500, -4)
    r.barBg = r:CreateTexture(nil, "ARTWORK"); r.barBg:SetPoint("BOTTOMLEFT", 500, 6); r.barBg:SetSize(180, 7); r.barBg:SetColorTexture(0.1, 0.08, 0.05, 1)
    r.bar = r:CreateTexture(nil, "ARTWORK", nil, 1); r.bar:SetPoint("LEFT", r.barBg, "LEFT"); r.bar:SetHeight(7); r.bar:SetColorTexture(0.95, 0.78, 0.38, 1)
    r.when = UI.Font(r, 10, UI.DIM); r.when:SetPoint("RIGHT", -6, 0); r.when:SetJustifyH("RIGHT")
    r.open = UI.Button(r, L"Открыть профессию", 150, 24, function(self)
      local d = self:GetParent().data
      if d and C_TradeSkillUI and C_TradeSkillUI.OpenRecipe then pcall(C_TradeSkillUI.OpenRecipe, d.rid) end
    end, true)
    r.open:SetPoint("RIGHT", -4, 0)
  end, function(r, d)
    r.icon:SetTexture(d.icon or 134400); r.name:SetText(d.name or "?"); r.who:SetText(charLabel(d.ck))
    local left = (d.ready or 0) - time()
    local e = ns.DB.chars[d.ck] and ns.DB.chars[d.ck].cds and ns.DB.chars[d.ck].cds[d.rid]
    if left <= 0 then
      r.left:SetText("|cff78d98a" .. L"Готово!" .. "|r"); r.barBg:Hide(); r.bar:Hide(); r.when:SetText("")
      r.open:SetShown(d.ck == ns.charKey)
    else
      local dd, h, m = math.floor(left / 86400), math.floor(left % 86400 / 3600), math.floor(left % 3600 / 60)
      r.left:SetText((dd > 0 and (dd .. L" д ") or "") .. h .. L" ч " .. m .. L" м")
      local dur = e and e.dur or 86400 * 2
      r.barBg:Show(); r.bar:Show(); r.bar:SetWidth(math.max(1, 180 * math.max(0, math.min(1, 1 - left / dur))))
      r.when:SetText(date("%d.%m %H:%M", d.ready)); r.open:Hide()
    end
  end)
  cdp.list:SetPoint("TOPLEFT", 0, -78); cdp.list:SetPoint("BOTTOMRIGHT", 0, 20)
  cdp.list.empty:SetText(L"Кулдаунов пока нет. Откройте окно профессии персонажем-алхимиком - трансмутации появятся здесь.")
  local note = UI.Font(f, 10, UI.DIM); note:SetPoint("BOTTOMLEFT", 2, 2); note:SetPoint("RIGHT", -2, 0)
  note:SetText(L"Рецепт попадает в список, когда персонаж открывает окно профессии; время отсчитывается от последнего проведения.")
  -- пока раздел открыт - таймеры идут каждую секунду
  local acc = 0
  f:SetScript("OnUpdate", function(_, el) acc = acc + (el or 0); if acc >= 1 then acc = 0; if cdp.list then cdp.list:Refresh() end end end)
end
local function refreshCds() if cdp.list then cdp.list:SetData(ns.AllCooldowns()) end end

-- ---------- окно ----------
local VIEW_HOME, VIEW_ALTS, VIEW_CRAFT, VIEW_AUC, VIEW_CD, VIEW_SET = 1, 2, 3, 4, 5, 6
local NAV_NAMES = { L"Главная", L"Твинки", L"Профессии", L"Аукцион", L"Часы", L"Настройки" }
local function updateGlow() if win and win.nav then win.nav[VIEW_CD]:SetPulse(ns.AnyCooldownReady and ns.AnyCooldownReady() or false) end end
local function refresh()
  if not win or not win:IsShown() then return end
  if view == VIEW_HOME then refreshHome() elseif view == VIEW_ALTS then refreshAlts() elseif view == VIEW_CRAFT then refreshCraft()
  elseif view == VIEW_AUC then refreshAuc() elseif view == VIEW_CD then refreshCds() else refreshSettings() end
  if pops.bank and pops.bank.dim:IsShown() then refreshBank() end
  if pops.lots and pops.lots.dim:IsShown() then fillLotsPopup() end
  if pops.log and pops.log.dim:IsShown() then refreshLog() end
  updateGlow()
end
local function selectView(i)
  view = i
  for k, b in ipairs(win.nav) do b:SetOn(k == i); win.pages[k]:SetShown(k == i) end
  for _, p in pairs(pops) do p.dim:Hide() end
  win.chromeSub:SetText(NAV_NAMES[i] or "")
  ns.DB.settings.mainView = i
  refresh()
end
function setChar(ck) charKey = ck; prof = nil; sel = nil; refresh() end

local function build()
  if win then return end
  win = CreateFrame("Frame", "WolfichMarketMainFrame", UIParent)
  win:SetPoint("CENTER"); win:SetFrameStrata("HIGH"); win:SetToplevel(true)
  win:SetMovable(true); win:EnableMouse(true); win:SetClampedToScreen(true)
  tinsert(UISpecialFrames, "WolfichMarketMainFrame")
  win.content = UI.MainChrome(win, function(i) selectView(i) end, NAV_NAMES)
  win.chromeSub:SetText("v" .. (ns.VERSION or ""))
  -- разделы по порядку значков колонки
  win.tabs = win.nav
  win.pages = {}
  for i, builder in ipairs({ buildHome, buildAlts, buildCraft, buildAuc, buildCds, buildSettings }) do
    local f = CreateFrame("Frame", nil, win.content); f:SetAllPoints()
    builder(f); f:Hide(); win.pages[i] = f
  end
  win:SetScript("OnShow", refresh)
  charKey = ns.charKey
  selectView(ns.DB.settings.mainView or VIEW_HOME)
  win:Hide() -- новые фреймы видимы сразу; показываем по кнопке
end

ns._mainCraft = craft -- для автотестов
ns._mainSig = sig
ns._mainAlts = alts
ns._mainCd = cdp
ns._mainHome = home
ns._mainPops = pops
ns._openBank, ns._openLots = function(ck) openBank(ck) end, function(ck) openLots(ck) end
function ns.ToggleMain(section)
  if not ns.DB or not ns.charKey then return end
  build()
  if section then win:Show(); selectView(section) return end
  if win:IsShown() then win:Hide() else win:Show(); refresh() end
end
ns.Listen("PRICES", refresh)
ns.Listen("MARKS", refresh)
ns.Listen("RECIPES", refresh)
ns.Listen("NAMES", refresh)
ns.Listen("AH_STATE", refresh)
ns.Listen("ALTS", function() if win and win:IsShown() and (view == VIEW_ALTS or view == VIEW_AUC or (pops.lots and pops.lots.dim:IsShown())) then refresh() end end)
ns.Listen("CD", function() updateGlow(); if win and win:IsShown() and view == VIEW_CD then refreshCds() end end)
ns.Listen("LOG", function() if pops.log and pops.log.dim:IsShown() then refreshLog() end end)
ns.Listen("INVENTORY", function() if (pops.bank and pops.bank.dim:IsShown()) or ns.DB.settings.useBank then refresh() end end)
ns.Listen("ALTAH", function() if view == VIEW_AUC then refresh() end end)
ns._mainAuc = aucp

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
