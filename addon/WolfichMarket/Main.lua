-- WolfichMarket: главное окно (крафт по всем персонажам и сигналы) + кнопка у миникарты
local _, ns = ...
local L = ns.L
local UI, M = ns.UI, ns.MEDIA

local win, view, charKey, prof, sel
local setChar
-- окно игры открылось поверх - наше уступает ему место сверху
-- (окно уходит в слой окон игры, пока открыто окно профессии или сумки; клик по нашему окну - снова сверху всего)
local function lower() if win and win:IsShown() then win:SetFrameStrata("MEDIUM"); if win.Lower then win:Lower() end end end
local function raise() if win and win:GetFrameStrata() ~= "HIGH" then win:SetFrameStrata("HIGH"); if win.Raise then win:Raise() end end end
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
      b:ClearAllPoints(); b:SetPoint("TOPLEFT", craft.page, "TOPLEFT", x, -row * 36)
      x = x + w + 6
      b:Show(); b:SetGold(p == prof)
    else b:Hide() end
  end
  -- «+»: добавить профессию, которой у персонажа нет (для отслеживания цен)
  if x > X0 and x + 34 > W then x = X0; row = row + 1 end
  craft.addBtn:ClearAllPoints(); craft.addBtn:SetPoint("TOPLEFT", craft.page, "TOPLEFT", x, -row * 36)
  if craft.charName then craft.charName:SetText(charLabel(charKey)) end
  craft.setTop(row * 36 + 6)
  craft.noProf:SetShown(#names == 0)
end
local function fillCard(rec)
  sel = rec
  local card = craft.card
  if card.fade then ns.After(0, card.fade) end -- после раскладки: диапазон прокрутки и растушёвка
  for _, r in ipairs(card.rows) do r:Hide() end
  if not rec then
    card.title:SetText(L"Выберите рецепт"); card.level:SetText(""); card.total:SetText(""); card.onAH:Hide(); card.craft:Hide(); card.portRow:Hide(); card.chartTitle:SetText(""); card.chart:Hide(); card.chartBox:Hide()
    return
  end
  card.craft:Show(); card.onAH:Show(); card.chart:Show(); card.chartBox:Show(); card.portRow:Show()
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
    if it.out then r.name:SetText(ns.itemLinkText(it.id) .. (it.n ~= 1 and (" |cffaaaaaa×" .. it.n .. "|r") or "") .. "  |cff8a8070» " .. L"продажа" .. "|r") end
    r.search:SetAlpha(ns.AHIsOpen() and 1 or 0.35)
    r:Show()
  end
  local lvl = ns.RecipeLevel and ns.RecipeLevel(rec)
  card.level:SetText(lvl and (ns.SkillTierName(ns.SkillTier(lvl)):gsub(":.*$", "") .. " · " .. L"навык" .. " " .. lvl) or "")
  local lines = { (pr.stock and (N > 1 and string.format(L"Докупить на %d крафтов: ", N) or L"Докупить на 1 крафт: ") or (N > 1 and string.format(L"Себестоимость %d крафтов: ", N) or L"Себестоимость: ")) .. (pr.missing > 0 and (">= " .. ns.money(pr.cost)) or ns.money(pr.cost))
    .. (pr.crafts and ("   |cffaaaaaa" .. L"из запаса хватит на " .. pr.crafts .. "|r") or "") }
  -- доход и прибыль на обоих аукционах: Ф (комиссия 5%) и Общ (15%)
  local q = pr.qty or 1
  local nSell = rec.out and ns.WithRealm(c.realmKey, ns.PriceIn, "neutral", rec.out)
  local nRev = nSell and nSell * q * (1 - ns.Cut("neutral"))
  if pr.revenue or nRev then
    lines[#lines + 1] = L"Доход" .. ": |cfff2c761" .. L"Ф" .. "|r " .. (pr.revenue and ns.money(pr.revenue, true) or "-") .. "  /  |cff66d9cc" .. L"Общ" .. "|r " .. (nRev and ns.money(nRev, true) or "-")
  end
  if pr.revenue or nRev then
    local nProf = nRev and pr.missing == 0 and (nRev - pr.cost) or nil
    lines[#lines + 1] = L"Прибыль" .. ": |cfff2c761" .. L"Ф" .. "|r " .. pfStr(pr.profit) .. (pr.margin and ("  |cffaaaaaa(" .. math.floor(pr.margin) .. "%)|r") or "") .. "   ·   |cff66d9cc" .. L"Общ" .. "|r " .. pfStr(nProf)
  end
  card.total:SetText(table.concat(lines, "\n"))
  -- «Крафт» и «Поставить сигнал» — сразу под последней строкой рецепта
  local n = math.min(#items, #card.rows)
  card.portRow:ClearAllPoints(); card.portRow:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -38 - n * 24 - 4); card.portRow:SetPoint("RIGHT", card, "RIGHT", -12, 0)
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
  local sold, lots, qty = ns.SoldIn(id, 24), ns.LotsNow(id)
  card.chartTitle:SetText("|cfff2c761— " .. L"цена" .. "|r " .. (p and ns.money(p, true) or "-") .. "   |cff66d9cc— " .. L"продано, шт" .. "|r   " .. L"продано за 24 ч" .. ": |cffffffff" .. (sold or "-") .. "|r   " .. L"лотов" .. ": |cffffffff" .. (lots or "-") .. (qty and qty > 0 and (" |cffaaaaaa(" .. qty .. " " .. L"шт" .. ")|r") or "") .. "|r   |cff8a8070" .. ns.itemName(id) .. "|r")
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
  local prevC = UI.Button(f, "‹", 22, 18, function() craft.stepChar(-1) end); prevC:SetPoint("TOPLEFT", 0, -2)
  craft.charName = UI.Font(f, 13, nil, "OVERLAY", "OUTLINE"); craft.charName:SetPoint("LEFT", prevC, "RIGHT", 4, 0); craft.charName:SetWidth(150); craft.charName:SetJustifyH("CENTER")
  local nextC = UI.Button(f, "›", 22, 18, function() craft.stepChar(1) end); nextC:SetPoint("LEFT", craft.charName, "RIGHT", 4, 0)
  for bt, tip in pairs({ [prevC] = L"Предыдущий персонаж", [nextC] = L"Следующий персонаж" }) do
    bt:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(tip, 1, 1, 1); GameTooltip:Show() end)
    bt:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
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
      UI.Skin(m, { theme = "acard", scale = 0.25, alpha = 0.97 })
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
  -- карточка рецепта (как на макете): заголовок и уровень, строки предметов, порции, кнопки, итог и график - без прокрутки
  local box = CreateFrame("Frame", nil, f)
  UI.Box(box)
  local card = box
  card.fade = function() end
  -- второй ряд профессий сдвигает фильтры, список и карточку вниз
  function craft.setTop(dy)
    c1:ClearAllPoints(); c1:SetPoint("TOPLEFT", 0, -34 - dy)
    -- Give full checkbox labels room; keep the recipe panels at their original height.
    c2:ClearAllPoints(); c2:SetPoint("TOPLEFT", 190, -34 - dy)
    c3:ClearAllPoints(); c3:SetPoint("TOPLEFT", 405, -34 - dy)
    c4:ClearAllPoints(); c4:SetPoint("TOPLEFT", 680, -34 - dy)
    sortLbl:ClearAllPoints(); sortLbl:SetPoint("TOPLEFT", 2, -64 - dy)
    sortChecks.main:ClearAllPoints(); sortChecks.main:SetPoint("TOPLEFT", 125, -60 - dy)
    sortChecks.neutral:ClearAllPoints(); sortChecks.neutral:SetPoint("TOPLEFT", 394, -60 - dy)
    sortChecks.margin:ClearAllPoints(); sortChecks.margin:SetPoint("TOPLEFT", 655, -60 - dy)
    -- список и карточка - две панели одной высоты, сверху и снизу на одной линии
    craft.listBox:ClearAllPoints(); craft.listBox:SetPoint("TOPLEFT", 0, -88 - dy); craft.listBox:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -6, 18)
    lh:ClearAllPoints(); lh:SetPoint("TOPLEFT", craft.listBox, "TOPLEFT", 6, -4); lh:SetPoint("RIGHT", craft.listBox, "RIGHT", -12, 0)
    craft.list:ClearAllPoints(); craft.list:SetPoint("TOPLEFT", craft.listBox, "TOPLEFT", 4, -20); craft.list:SetPoint("BOTTOMRIGHT", craft.listBox, "BOTTOMRIGHT", -4, 4)
    box:ClearAllPoints(); box:SetPoint("TOPLEFT", f, "TOP", 6, -88 - dy); box:SetPoint("BOTTOMRIGHT", 0, 18)
  end
  craft.setTop(0)
  card.level = UI.Font(card, 10, UI.DIM); card.level:SetPoint("TOPRIGHT", -12, -12); card.level:SetJustifyH("RIGHT")
  card.title = UI.Font(card, 15, UI.GOLD, "OVERLAY"); UI.SetFont(card.title, UI.BOLD, 15, ""); card.title:SetPoint("TOPLEFT", 14, -10); card.title:SetPoint("RIGHT", card.level, "LEFT", -8, 0)
  card.rows = {}
  for i = 1, 8 do
    local r = CreateFrame("Frame", nil, card); r:SetHeight(22)
    r:SetPoint("TOPLEFT", 10, -38 - (i - 1) * 24); r:SetPoint("RIGHT", -10, 0)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(20, 20); r.icon:SetPoint("LEFT", 2, 0)
    r.search = UI.Icon(r, "search", 16, L"Искать на аукционе (окно аукциона должно быть открыто)", function(self) ns.SearchAH(self:GetParent().id) end); r.search:SetPoint("RIGHT", -2, 0)
    r.bell = UI.Bell(r, 17, function(self) return self:GetParent().id end); r.bell:SetPoint("RIGHT", r.search, "LEFT", -6, 0)
    r.star = UI.Icon(r, "star-off", 15, L"Избранное", function(self) ns.ToggleMark(self:GetParent().id) end); r.star:SetPoint("RIGHT", r.bell, "LEFT", -6, 0)
    r.price = UI.Font(r, 12); r.price:SetPoint("RIGHT", r.star, "LEFT", -10, 0); r.price:SetJustifyH("RIGHT")
    r.name = UI.Font(r, 12); r.name:SetPoint("LEFT", r.icon, "RIGHT", 7, 0); r.name:SetPoint("RIGHT", r.price, "LEFT", -6, 0)
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
  local prow = CreateFrame("Frame", nil, card); prow:SetHeight(34); card.portRow = prow
  local pl = UI.Font(prow, 12); pl:SetPoint("LEFT", 2, 0); pl:SetText(L"Порций:")
  local function setN(v)
    if not sel then return end
    v = math.max(1, math.min(999, math.floor(tonumber(v) or 1)))
    craft.portions = craft.portions or {}; craft.portions[sel.id] = v
    fillCard(sel)
  end
  local function cur() return sel and craft.portions and craft.portions[sel.id] or 1 end
  local minus = UI.Button(prow, "-", 28, 26, function() setN(cur() - 1) end); minus:SetPoint("LEFT", pl, "RIGHT", 8, 0)
  card.portion = CreateFrame("EditBox", nil, prow, "InputBoxTemplate"); card.portion:SetSize(40, 22); card.portion:SetPoint("LEFT", minus, "RIGHT", 8, 0)
  card.portion:SetAutoFocus(false); card.portion:SetNumeric(true); card.portion:SetMaxLetters(3); card.portion:SetJustifyH("CENTER")
  if card.portion.SetFont then UI.SetFont(card.portion, UI.FONT, 13, "") end
  card.portion:SetScript("OnEnterPressed", function(self) self:ClearFocus(); setN(self:GetText()) end)
  card.portion:SetScript("OnEditFocusLost", function(self) setN(self:GetText()) end)
  local plus = UI.Button(prow, "+", 28, 26, function() setN(cur() + 1) end); plus:SetPoint("LEFT", card.portion, "RIGHT", 4, 0)
  local p5 = UI.Button(prow, "+5", 38, 26, function() setN(cur() + 5) end); p5:SetPoint("LEFT", plus, "RIGHT", 4, 0)
  card.plan = UI.Button(prow, L"Запланировать", 150, 26, function() if sel then ns.AddPlan(sel, charKey, prof, craft.portions[sel.id] or 1) end end, true)
  card.plan:SetPoint("RIGHT", 0, 0)
  card.plan:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(L"Сохранить рецепт и число порций в план. У аукциониста во вкладке «План» будет список всего, что нужно докупить.", 1, 1, 1, true); GameTooltip:Show() end)
  card.plan:SetScript("OnLeave", function() GameTooltip:Hide() end)
  -- кнопки: Крафт / На аукционе - на всю ширину карточки, поровну
  local brow = CreateFrame("Frame", nil, card); brow:SetHeight(34)
  brow:SetPoint("TOPLEFT", prow, "BOTTOMLEFT", 0, -6); brow:SetPoint("RIGHT", prow, "RIGHT", 0, 0)
  card.craft = UI.Button(brow, L"Крафт", 100, 28, function() if sel then ns.OpenRecipeInGame(sel, prof) end end, true)
  card.craft:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(self.tip or L"Открыть этот рецепт в окне профессии", 1, 1, 1, true); GameTooltip:Show() end)
  card.craft:SetScript("OnLeave", function() GameTooltip:Hide() end)
  -- «Где взять»: тренер, продавцы, добыча, задания, репутация и карта зоны
  -- «На аукционе»: найти результат у аукциониста и обновить цены всего рецепта
  card.onAH = UI.Button(brow, L"На аукционе", 100, 28, function()
    if not sel then return end
    if not ns.AHIsOpen() then ns.say(L"цены обновляются у аукциониста - откройте аукцион.") return end
    ns.QuickRefresh(ns.RecipePriceIDs(sel))
    if sel.out then ns.SearchAH(sel.out) end
  end)
  card.onAH:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(L"У аукциониста: найти этот предмет и обновить цены всего рецепта (результат и все материалы) без 15-минутного ожидания.", 1, 1, 1, true); GameTooltip:Show() end)
  card.onAH:SetScript("OnLeave", function() GameTooltip:Hide() end)
  card.prices, card.alarm = card.onAH, card.onAH
  local function layoutBtns()
    local w = (brow:GetWidth() or 0); if w < 60 then w = 380 end
    local bw = math.floor((w - 6) / 2)
    for i, b in ipairs({ card.craft, card.onAH }) do b:SetWidth(bw); b:ClearAllPoints(); b:SetPoint("LEFT", brow, "LEFT", (i - 1) * (bw + 6), 0) end
  end
  brow:SetScript("OnSizeChanged", layoutBtns); layoutBtns()
  card.total = UI.Font(card, 12, UI.TEXT); card.total:SetPoint("TOPLEFT", brow, "BOTTOMLEFT", 2, -8); card.total:SetPoint("RIGHT", -12, 0); card.total:SetWordWrap(true); card.total:SetJustifyV("TOP")
  -- график - в своей панели до низа карточки
  local cbox = CreateFrame("Frame", nil, card); UI.Box(cbox, 0.35)
  cbox:SetPoint("TOPLEFT", card.total, "BOTTOMLEFT", -4, -8); cbox:SetPoint("BOTTOMRIGHT", -10, 10)
  card.chartTitle = UI.Font(cbox, 11, UI.GOLD); card.chartTitle:SetPoint("TOPLEFT", 8, -6); card.chartTitle:SetPoint("RIGHT", -8, 0)
  card.chart = UI.Chart(cbox); card.chart.mid = true; card.chart.noLegend = true
  card.chart.onClick = function() if card.chartId then ns.ShowChartDialog(card.chartId) end end -- клик - большой график
  card.chart:SetPoint("TOPLEFT", 0, -16); card.chart:SetPoint("BOTTOMRIGHT", 0, 0)
  card.chartBox = cbox
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
    chartDlg:SetSize(940, 560); chartDlg:SetPoint("CENTER"); chartDlg:SetFrameStrata("DIALOG"); chartDlg:EnableMouse(true); chartDlg:SetToplevel(true)
    chartDlg:SetMovable(true); chartDlg:RegisterForDrag("LeftButton"); chartDlg:SetClampedToScreen(true)
    chartDlg:SetScript("OnDragStart", chartDlg.StartMoving); chartDlg:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    tinsert(UISpecialFrames, "WolfichMarketChartDialog")
    UI.Skin(chartDlg, { theme = "main", scale = 0.6 })
    UI.Title(chartDlg, L"График цены")
    UI.Close(chartDlg)
    chartDlg.icon = chartDlg:CreateTexture(nil, "ARTWORK"); chartDlg.icon:SetSize(34, 34); chartDlg.icon:SetPoint("TOPLEFT", 22, -52)
    chartDlg.name = UI.Font(chartDlg, 15, UI.GOLD); UI.SetFont(chartDlg.name, UI.BOLD, 15, ""); chartDlg.name:SetPoint("TOPLEFT", chartDlg.icon, "TOPRIGHT", 10, -1)
    chartDlg.star = UI.Star(chartDlg, 16, function() return chartDlg.id end); chartDlg.star:SetPoint("LEFT", chartDlg.name, "RIGHT", 8, 0)
    chartDlg.bell = UI.Bell(chartDlg, 16, function() return chartDlg.id end); chartDlg.bell:SetPoint("LEFT", chartDlg.star, "RIGHT", 6, 0)
    chartDlg.info = UI.Font(chartDlg, 11, UI.DIM); chartDlg.info:SetPoint("TOPLEFT", chartDlg.name, "BOTTOMLEFT", 0, -3); chartDlg.info:SetPoint("RIGHT", -20, 0)
    chartDlg.chart = UI.Chart(chartDlg)
    chartDlg.chart:SetPoint("TOPLEFT", 18, -96); chartDlg.chart:SetPoint("BOTTOMRIGHT", -22, 22)
  end
  chartDlg.id = id
  chartDlg.icon:SetTexture(ns.itemIcon(id))
  chartDlg.name:SetText(ns.itemLinkText(id))
  chartDlg.star:Update(id); chartDlg.bell:Update(id)
  local p, avg = ns.AHPrice(id), ns.AvgPrice(id, 24)
  local nt = ns.PriceIn and ns.PriceIn("neutral", id)
  local sold, lots, qty = ns.SoldIn(id, 24), ns.LotsNow(id)
  chartDlg.info:SetText((p and (L"Ф" .. " |cffffffff" .. ns.money(p, true) .. "|r") or L"|cff777777нет цены|r")
    .. (nt and ("   |cff4ab3a6" .. L"Общ" .. "|r |cffffffff" .. ns.money(nt, true) .. "|r") or "")
    .. (avg and ("   |cffaaaaaa" .. L"среднее за 24 ч" .. "|r " .. ns.money(avg, true)) or "")
    .. "   |cffaaaaaa" .. L"продано за 24 ч" .. "|r " .. (sold or "-") .. "   |cffaaaaaa" .. L"лотов" .. "|r " .. (lots or "-") .. (qty and qty > 0 and (" (" .. qty .. " " .. L"шт" .. ")") or ""))
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
      r.star = UI.Star(r, 14, function() local d = r.data; return d and d.id end); r.star:SetPoint("RIGHT", r.chart, "LEFT", -4, 0)
      r.chg = UI.Font(r, 11); r.chg:SetPoint("RIGHT", r.star, "LEFT", -8, 0); r.chg:SetWidth(46); r.chg:SetJustifyH("RIGHT")
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
      r.icon:SetTexture(ns.itemIcon(d.id)); r.name:SetText(ns.itemLinkText(d.id)); r.star:Update(d.id)
      local pr = ns.AHPrice(d.id); r.price:SetText(pr and ns.money(pr, true) or L"|cff777777нет|r")
      local avg = ns.AvgPrice(d.id, 24); r.chg:SetText(pr and avg and ns.pct((pr - avg) / avg * 100) or "")
      local t = ns.DB.target and ns.DB.target[d.id]
      if not r.money:HasFocus() then if t and t[side] then r.money:Set(t[side]) else r.money:Clear() end end
    end)
    list:SetPoint("TOPLEFT", 10, -74); list:SetPoint("BOTTOMRIGHT", -10, 10)
    -- треугольник у предмета: себестоимость, прибыль и график цены
    list:EnableDetail(4, function(det) UI.ItemDetail(det, { leftW = 130, compact = true }) end, function(det, d) det:Set(d.id) end)
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
ns.AucCats, ns.AucCatName = CATS, catName -- для поиска во вкладке «Купить» у аукциониста

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
  -- Keep the existing compact auction controls layout. No decorative toolbar
  -- background: the controls, scan status and table header occupy separate
  -- tight rows, and an added texture can visually cross their boundaries.
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
  for _, v in ipairs({ { "all", L"Весь аукцион", 104 }, { "signals", L"Сигналы", 84 } }) do
    local b = UI.Button(f, v[2], v[3], 26, function() S.aucView = v[1]; if aucp.menu then aucp.menu:Hide() end; refreshAuc() end)
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
      UI.Skin(m, { theme = "acard", scale = 0.25, alpha = 0.97 })
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
    r.star = UI.Star(r, 14, function() local d = r.data; return d and d.id end); r.star:SetPoint("LEFT", 6, 0)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(20, 20); r.icon:SetPoint("LEFT", r.star, "RIGHT", 4, 0)
    r.bell = UI.Bell(r, 16, function(self) local d = self:GetParent().data; return d and d.id end); r.bell:SetPoint("RIGHT", -4, 0)
    r.chg = UI.Font(r, 11); r.chg:SetPoint("RIGHT", -36, 0); r.chg:SetWidth(76); r.chg:SetJustifyH("RIGHT")
    r.q = UI.Font(r, 11, UI.DIM); r.q:SetPoint("RIGHT", -122, 0); r.q:SetWidth(70); r.q:SetJustifyH("RIGHT")
    r.p = UI.Font(r, 11); r.p:SetPoint("RIGHT", -202, 0); r.p:SetWidth(110); r.p:SetJustifyH("RIGHT")
    r.name = UI.Font(r, 11); r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0); r.name:SetPoint("RIGHT", r.p, "LEFT", -8, 0)
    openRow(r)
  end, function(r, x)
    r.icon:SetTexture(ns.itemIcon(x.id)); r.name:SetText(ns.itemLinkText(x.id)); r.bell:Update(x.id); r.star:Update(x.id)
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
      r.star = UI.Star(r, 14, function() local d = r.data; return d and d.id end); r.star:SetPoint("LEFT", 4, 0)
      r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(24, 24); r.icon:SetPoint("LEFT", r.star, "RIGHT", 4, 0)
      r.gain = UI.Font(r, 12); r.gain:SetPoint("TOPRIGHT", -4, -4); r.gain:SetJustifyH("RIGHT"); r.gain:SetWidth(90)
      r.name = UI.Font(r, 11); r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 6, 2); r.name:SetPoint("RIGHT", r.gain, "LEFT", -4, 0)
      r.sub = UI.Font(r, 10, UI.DIM); r.sub:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 6, -3); r.sub:SetPoint("RIGHT", -4, 0)
      openRow(r)
    end, function(r, x)
      local mode = ns.DB.settings.aucMode or "main"
      r.icon:SetTexture(ns.itemIcon(x.id)); r.name:SetText(ns.itemLinkText(x.id)); r.star:Update(x.id)
      r.gain:SetText("|cff78d98a+" .. ns.money(x.gain, true) .. "|r")
      r.sub:SetText(L"здесь" .. " " .. ns.money(x.here, true) .. "   |cff888888" .. L"фракционный" .. "|r " .. ns.money(x.there, true))
    end)
    p.list:SetPoint("TOPLEFT", 8, -30); p.list:SetPoint("BOTTOMRIGHT", -8, 8)
    p.list:EnableDetail(5, function(det) UI.ItemDetail(det, { leftW = 130, compact = true }) end, function(det, d) det:Set(d.id) end)
    return p
  end
  aucp.buy, aucp.dear = panel(true), panel(false)
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
  aucp.cat:SetLabel(catName(cat)); aucp.cat:SetShown(vw == "all")
  aucp.search:SetShown(vw ~= "signals")
  if vw == "lots" then vw = "all"; S.aucView = "all" end
  aucp.sig:SetShown(vw == "signals"); aucp.status:SetShown(vw ~= "signals")
  if vw == "signals" then aucp.all:Hide(); aucp.buy:Hide(); aucp.dear:Hide(); refreshSignals() return end
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
  -- Distinct group backgrounds, all on the parent's background layer so they
  -- cannot intercept mouse input or cover interactive options.
  local function sectionBackdrop(x, top, width, height)
    local panel = f:CreateTexture(nil, "BACKGROUND", nil, -5)
    panel:SetPoint("TOPLEFT", f, "TOPLEFT", x, top)
    panel:SetSize(width, height)
    panel:SetColorTexture(0.070, 0.095, 0.115, 0.83)
    local stripe = f:CreateTexture(nil, "BACKGROUND", nil, -4)
    stripe:SetPoint("TOPLEFT", f, "TOPLEFT", x, top)
    stripe:SetSize(3, height)
    stripe:SetColorTexture(0.72, 0.54, 0.28, 0.75)
  end
  sectionBackdrop(0, 4, 394, 212)
  sectionBackdrop(0, -219, 394, 164)
  sectionBackdrop(411, 4, 548, 239)
  sectionBackdrop(411, -241, 548, 185)
  local function column(x, title)
    local t = UI.Font(f, 13, UI.GOLD); t:SetPoint("TOPLEFT", x + 10, -7); t:SetText(title)
    return { x = x + 10, y = -31 }
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
  local t2 = UI.Font(f, 13, UI.GOLD); t2:SetPoint("TOPLEFT", a.x, a.y - 15); t2:SetText(L"Общий рынок"); a.y = a.y - 39
  chk(a, L"Делиться своими снимками с игроками", "netSend", nil, true)
  chk(a, L"Принимать цены от игроков", "netRecv", nil, true)
  chk(a, L"Турбо: рассылка через 4 имени (в 2-4 раза быстрее)", "netTurbo", nil, true)
  local net = UI.Button(f, L"Проверить связь (/wmnet)", 200, 22, function() if SlashCmdList.WOLFICHMARKET then SlashCmdList.WOLFICHMARKET("net") end end)
  net:SetPoint("TOPLEFT", a.x, a.y - 2)

  local b = column(410, L"Интерфейс")
  chk(b, L"Кнопка у миникарты (после перезагрузки интерфейса)", "minimapShown", function() S.minimapHidden = not S.minimapShown end)
  chk(b, L"Значки в сумках: молоток - на аукцион, мешочек - торговцу", "bagGlow", function() if ns.UpdateBagGlow then ns.UpdateBagGlow() end; if ns.UpdateAHBags then ns.UpdateAHBags() end end)
  chk(b, L"Окошко стоимости сумок (перетаскивается)", "bagValue", function() if ns.UpdateBagValue then ns.UpdateBagValue() end end, true)
  chk(b, L"Окошко денег персонажа (перетаскивается)", "moneyBar", function() if ns.UpdateMoneyBar then ns.UpdateMoneyBar() end end, true)
  local rChat = buttons(b, L"Сообщения:", { { "window", L"в журнал", 80 }, { "main", L"в чат", 64 }, { "off", L"никуда", 70 } }, function() return S.chatMode or "window" end, function(v) S.chatMode = v end)
  local rLang = buttons(b, L"Язык:", { { "auto", L"Авто", 64 }, { "ru", "Русский", 74 }, { "en", "English", 74 } }, function() return S.lang or "auto" end, function(v) S.lang = v; setp.reload:Show(); setp.note:Show() end)
  setp.note = UI.Font(f, 10, UI.GOLD); setp.note:SetPoint("TOPLEFT", b.x + 4, b.y - 2); setp.note:SetText(L"Язык меняется после перезагрузки интерфейса."); setp.note:Hide()
  setp.reload = UI.Button(f, L"Перезагрузить интерфейс", 190, 22, function() if ReloadUI then ReloadUI() end end, true)
  setp.reload:SetPoint("TOPLEFT", b.x, b.y - 18); setp.reload:Hide()
  -- окно профессии игры: таблица цен и столбики можно выключить; кулдауны; журнал
  local t3 = UI.Font(f, 13, UI.GOLD); t3:SetPoint("TOPLEFT", b.x, b.y - 55); t3:SetText(L"Прочее"); b.y = b.y - 79
  chk(b, L"У аукциониста: своя сумка под окном аукциона", "ahBags", function() if ns.UpdateAHBags then ns.UpdateAHBags() end end, true)
  chk(b, L"У аукциониста: графики в окнах покупки и выставления лота", "ahBuyChart", function(v) if ns.SetAHBuyDeco then ns.SetAHBuyDeco(v) end end, true)
  local jb = UI.Button(f, L"Открыть журнал", 170, 22, function() ns.OpenLog() end, true); jb:SetPoint("TOPLEFT", b.x, b.y - 6)
  jb:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(L"Все сообщения аддона: снимки, общий рынок, сигналы и продажи.", 1, 1, 1, true); GameTooltip:Show() end)
  jb:SetScript("OnLeave", function() GameTooltip:Hide() end)
  setp.journal = jb
  -- /reload одной кнопкой (всегда видна)
  local rl = UI.Button(f, L"Перезагрузить интерфейс (/reload)", 230, 22, function() if ReloadUI then ReloadUI() end end)
  rl:SetPoint("LEFT", jb, "RIGHT", 10, 0)
  setp.reloadAlways = rl
  local about = UI.Font(f, 10, UI.DIM); about:SetPoint("BOTTOMLEFT", 4, 4); about:SetPoint("RIGHT", -4, 0); about:SetWordWrap(true)
  about:SetText("WolfichMarket " .. (ns.VERSION or "") .. "  |cff70d6ffDEV DESIGN|r  ·  " .. L"Тестовая сборка GitHub (design-preview). Команды: /wm help")
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
-- журнал сообщений аддона
function ns.OpenLog()
  if not win then return end
  if not pops.log then pops.log = makePopup("WolfichMarketLogPopup", 720, 440, L"Журнал"); buildLog(pops.log.body) end
  pops.log.dim:Show(); refreshLog()
end

-- ---------- раздел «Главная»: что нового в каждой версии (язык - как у аддона) ----------
local home = {}
local function buildHome(f)
  -- Preview: a clearly visible, restrained dashboard header (no custom item icons).
  local banner = CreateFrame("Frame", nil, f)
  banner:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  banner:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
  banner:SetHeight(112)
  local bg = banner:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.055, 0.085, 0.115, 0.94)
  local line = banner:CreateTexture(nil, "BORDER")
  line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT"); line:SetHeight(2)
  line:SetColorTexture(0.75, 0.57, 0.26, 0.95)
  local accent = banner:CreateTexture(nil, "BORDER")
  accent:SetPoint("TOPLEFT", 0, 0); accent:SetPoint("BOTTOMLEFT", 0, 0)
  accent:SetWidth(4); accent:SetColorTexture(0.84, 0.65, 0.32, 1)
  local mark = UI.Font(banner, 12, UI.DIM)
  mark:SetPoint("TOPLEFT", 18, -12)
  mark:SetText("WOLFICHMARKET  /  FOREVER")
  local title = UI.Font(banner, 23, UI.GOLD)
  title:SetPoint("TOPLEFT", 18, -31)
  title:SetText(L"Обзор рынка")
  local caption = UI.Font(banner, 12, UI.TEXT)
  caption:SetPoint("TOPLEFT", 18, -69)
  caption:SetText(L"Цены, профессии и обмен данными в одном месте")
  home.banner = banner
  -- Three read-only summary cards; display only facts already known by the addon.
  home.metrics = {}
  local specs = {
    { L"Снимок аукциона", "scan" },
    { L"Цены игроков", "received" },
    { L"Обмен данными", "network" },
  }
  for i, spec in ipairs(specs) do
    local card = CreateFrame("Frame", nil, f)
    card:SetPoint("TOPLEFT", f, "TOPLEFT", (i - 1) * 324, -122)
    card:SetSize(312, 65)
    local cbg = card:CreateTexture(nil, "BACKGROUND")
    cbg:SetAllPoints()
    cbg:SetColorTexture(0.06, 0.087, 0.11, 1)
    local bar = card:CreateTexture(nil, "BORDER")
    bar:SetPoint("TOPLEFT"); bar:SetPoint("BOTTOMLEFT")
    bar:SetWidth(3)
    bar:SetColorTexture(0.68, 0.52, 0.28, 1)
    local label = UI.Font(card, 10, UI.DIM)
    label:SetPoint("TOPLEFT", 14, -8)
    label:SetText(spec[1])
    local value = UI.Font(card, 13, UI.TEXT)
    value:SetPoint("TOPLEFT", 14, -28)
    value:SetPoint("RIGHT", card, "RIGHT", -10, 0)
    value:SetJustifyH("LEFT")
    value:SetWordWrap(false)
    home.metrics[spec[2]] = value
  end
  local t = UI.Font(f, 16, UI.GOLD); t:SetPoint("TOPLEFT", 2, -205); t:SetText(L"История обновлений")
  local sub = UI.Font(f, 11, UI.DIM); sub:SetPoint("TOPLEFT", 2, -229); sub:SetPoint("RIGHT", -4, 0); sub:SetWordWrap(true)
  sub:SetText(L"Изменения версий WolfichMarket")
  local sf = CreateFrame("ScrollFrame", nil, f); sf:SetPoint("TOPLEFT", 0, -255); sf:SetPoint("BOTTOMRIGHT", 0, 0)
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
  if home.metrics then
    local scan = ns.CurrentScan and ns.CurrentScan()
    local scanStamp = scan and scan.t
    home.metrics.scan:SetText(scanStamp and (L"Снимок " .. ns.ago(scanStamp)) or L"Снимка пока нет")
    local receivedAt = ns.NetInfo and ns.NetInfo()
    home.metrics.received:SetText(receivedAt and (L"Получены " .. ns.ago(receivedAt)) or L"Пока нет данных")
    local settings = ns.DB and ns.DB.settings or {}
    if settings.netSend == false and settings.netRecv == false then
      home.metrics.network:SetText("|cff999999" .. L"Обмен отключён" .. "|r")
    else
      local seen, now = 0, time()
      for _, stamp in pairs(ns._netInChannel or {}) do
        if type(stamp) == "number" and now - stamp >= 0 and now - stamp < 300 then seen = seen + 1 end
      end
      home.metrics.network:SetText("|cff70cf82" .. L"Включён" .. "|r   " .. L"Участников замечено" .. ": " .. seen)
    end
  end
  local lang = ns.Lang()
  local y = 0
  for i, e in ipairs(ns.CHANGELOG or {}) do
    local c = home.cards[i]
    if not c then
      c = CreateFrame("Frame", nil, home.child)
      c.bg = c:CreateTexture(nil, "BACKGROUND"); c.bg:SetAllPoints(); c.bg:SetColorTexture(0.035, 0.045, 0.058, 0.65)
      c.edge = c:CreateTexture(nil, "BORDER"); c.edge:SetPoint("TOPLEFT"); c.edge:SetPoint("BOTTOMLEFT"); c.edge:SetWidth(2)
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

-- ---------- окно ----------
local VIEW_HOME, VIEW_CRAFT, VIEW_AUC, VIEW_SET = 1, 2, 3, 4
local NAV_NAMES = { L"Главная", L"Профессии", L"Аукцион", L"Настройки" }
local function refresh()
  if not win or not win:IsShown() then return end
  if view == VIEW_HOME then refreshHome() elseif view == VIEW_CRAFT then refreshCraft()
  elseif view == VIEW_AUC then refreshAuc() else refreshSettings() end
  if pops.log and pops.log.dim:IsShown() then refreshLog() end
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
  win.content = UI.MainChromeCompact(win, function(i) selectView(i) end, NAV_NAMES)
  win.chromeVer:SetText("|cff70d6ffDEV DESIGN|r  v" .. (ns.VERSION or ""))
  -- разделы по порядку значков колонки
  win.tabs = win.nav
  win.pages = {}
  for i, builder in ipairs({ buildHome, buildCraft, buildAuc, buildSettings }) do
    local f = CreateFrame("Frame", nil, win.content); f:SetAllPoints()
    builder(f); f:Hide(); win.pages[i] = f
  end
  win:SetScript("OnShow", function() raise(); refresh() end)
  win:HookScript("OnMouseDown", raise)
  if win.content then win.content:EnableMouse(true); win.content:HookScript("OnMouseDown", raise) end
  charKey = ns.charKey
  -- разделов стало меньше (2.44): старый номер раздела не подходит - открыть «Главную»
  if (ns.DB.settings.mainViewV or 1) < 2 then ns.DB.settings.mainView = nil; ns.DB.settings.mainViewV = 2 end
  selectView(ns.DB.settings.mainView or VIEW_HOME)
  win:Hide() -- новые фреймы видимы сразу; показываем по кнопке
end

ns._mainCraft = craft -- для автотестов
ns._mainSig = sig
ns._mainHome = home
ns._mainPops = pops
-- «Открыть в WolfichMarket» из окна профессии игры: раздел «Профессии», этот персонаж, эта профессия, этот рецепт
function ns.OpenRecipeInMain(rec)
  if not ns.DB or not ns.charKey then return end
  build()
  charKey = ns.charKey
  if ns.curProf and prof ~= ns.curProf then prof = ns.curProf; sel = nil end
  win:Show(); selectView(VIEW_CRAFT); raise()
  if rec then craft.chartRec = nil; fillCard(rec) end
end
function ns.ToggleMain(section)
  if not ns.DB or not ns.charKey then return end
  build()
  if section then win:Show(); selectView(section) return end
  if win:IsShown() then win:Hide() else win:Show(); refresh() end
end
-- открылось окно игры (профессия, сумки, банк, почта) - наше окно уступает ему место сверху
for _, e in ipairs({ "TRADE_SKILL_SHOW", "BAG_OPEN" }) do ns.On(e, function() ns.After(0, lower) end) end
if hooksecurefunc then
  for _, fn in ipairs({ "ToggleAllBags", "OpenAllBags", "ToggleBackpack", "OpenBackpack", "ToggleBag" }) do if _G[fn] then pcall(hooksecurefunc, fn, function() ns.After(0, lower) end) end end
end
-- окно профессии и сумки закрыты - наше снова над всем
ns.On("TRADE_SKILL_CLOSE", function() ns.After(0.1, function()
  local bagsOpen = (ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown()) or (ContainerFrame1 and ContainerFrame1:IsShown())
  if not bagsOpen then raise() end
end) end)
ns.On("BAG_CLOSED", function() ns.After(0.1, function()
  local prof = (ProfessionsFrame and ProfessionsFrame:IsShown()) or (TradeSkillFrame and TradeSkillFrame:IsShown())
  local bagsOpen = (ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown()) or (ContainerFrame1 and ContainerFrame1:IsShown())
  if not prof and not bagsOpen then raise() end
end) end)
ns.Listen("PRICES", refresh)
ns.Listen("MARKS", refresh)
ns.Listen("RECIPES", refresh)
ns.Listen("NAMES", refresh)
ns.Listen("AH_STATE", refresh)
ns.Listen("LOG", function() if pops.log and pops.log.dim:IsShown() then refreshLog() end end)
ns.Listen("INVENTORY", function() if ns.DB.settings.useBank then refresh() end end)
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
