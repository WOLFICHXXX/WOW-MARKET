-- WolfichMarket: банк и сумки каждого персонажа - материалы «из запаса» для крафта
local _, ns = ...
local L = ns.L
local safe = ns.safe

-- контейнеры сумок: рюкзак, 4 сумки и сумка реагентов (если есть)
local function bagIDs()
  local ids = {}
  local n = (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4)
  for i = 0, n do ids[#ids + 1] = i end
  return ids
end
-- контейнеры банка: основной, сумки банка, банк реагентов и вкладки банка (новые клиенты)
local function bankIDs()
  local ids, seen = {}, {}
  local function add(i) if i and not seen[i] then seen[i] = true; ids[#ids + 1] = i end end
  local E = Enum and Enum.BagIndex
  add(BANK_CONTAINER or (E and E.Bank) or -1)
  local first = (E and E.BankBag_1) or ((NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) + 1)
  for i = 0, (NUM_BANKBAGSLOTS or 7) - 1 do add(first + i) end
  add(REAGENTBANK_CONTAINER or (E and E.Reagentbank))
  if E then for k = 1, 6 do add(E["CharacterBankTab_" .. k]) end end
  return ids
end

local function read(ids)
  local out, any = {}, false
  local C = C_Container
  for _, b in ipairs(ids) do
    local n = (C and C.GetContainerNumSlots and safe(C.GetContainerNumSlots, b)) or (GetContainerNumSlots and safe(GetContainerNumSlots, b)) or 0
    for s = 1, n do
      any = true
      local id, cnt
      if C and C.GetContainerItemInfo then
        local info = safe(C.GetContainerItemInfo, b, s)
        if info then id, cnt = info.itemID, info.stackCount end
      elseif GetContainerItemInfo then
        local _, c, _, _, _, _, link = safe(GetContainerItemInfo, b, s); cnt = c; id = link and ns.idFromLink(link)
      end
      if id then out[id] = (out[id] or 0) + (cnt or 1); ns.itemName(id) end
    end
  end
  return out, any
end

local bankOpen = false
function ns.ScanBags()
  if not ns.DB or not ns.charKey then return end
  local c = ns.DB.chars[ns.charKey]; if not c then return end
  c.bags = read(bagIDs()); c.bagsT = time()
  ns.Fire("INVENTORY")
end
function ns.ScanBank()
  if not ns.DB or not ns.charKey or not bankOpen then return end
  local c = ns.DB.chars[ns.charKey]; if not c then return end
  local items, any = read(bankIDs())
  if not any then return end -- банк ещё не прогрузился
  c.bank = items; c.bankT = time()
  ns.Fire("INVENTORY")
end

-- запас персонажа: банк + сумки (то, что можно пустить в крафт, не покупая)
function ns.Stock(charKey)
  local c = ns.DB.chars[charKey or ns.charKey]
  if not c then return {} end
  local out = {}
  for id, n in pairs(c.bank or {}) do out[id] = (out[id] or 0) + n end
  for id, n in pairs(c.bags or {}) do out[id] = (out[id] or 0) + n end
  return out
end

local pending
local function later(fn) if pending then return end; pending = true; ns.After(0.5, function() pending = false; fn() end) end
ns.On("BANKFRAME_OPENED", function() bankOpen = true; ns.After(0.3, ns.ScanBank); ns.After(1.5, ns.ScanBank); ns.ScanBags() end)
ns.On("BANKFRAME_CLOSED", function() ns.ScanBank(); bankOpen = false end)
ns.On("PLAYERBANKSLOTS_CHANGED", function() later(ns.ScanBank) end)
ns.On("PLAYERREAGENTBANKSLOTS_CHANGED", function() later(ns.ScanBank) end)
ns.On("BAG_UPDATE_DELAYED", function() later(function() ns.ScanBags(); if bankOpen then ns.ScanBank() end end) end)
ns.Listen("LOGIN", function() ns.After(3, ns.ScanBags) end)
ns._bankOpen = function(v) bankOpen = v end -- для автотестов

-- ---------- сколько предмета у персонажа: в сумках и в банке ----------
local function itemCount(id, withBank)
  return (C_Item and C_Item.GetItemCount and safe(C_Item.GetItemCount, id, withBank)) or (GetItemCount and safe(GetItemCount, id, withBank)) or nil
end
function ns.HaveSplit(id, charKey)
  charKey = charKey or ns.charKey
  local c = ns.DB.chars[charKey] or {}
  local bags, bank = (c.bags or {})[id] or 0, (c.bank or {})[id] or 0
  if charKey == ns.charKey then
    local b = itemCount(id, false)
    local all = itemCount(id, true)
    if b then bags = b end
    if all and b and all - b > bank then bank = all - b end
  end
  return bags, bank
end
-- подпись «сумки N / банк M» для строк со своими материалами
function ns.HaveText(id, charKey, need)
  local bags, bank = ns.HaveSplit(id, charKey)
  local col = need and (bags + bank >= need and "|cff78d98a" or "|cffffb060") or "|cffcccccc"
  return col .. L"сумки" .. " " .. bags .. " / " .. L"банк" .. " " .. bank .. "|r", bags, bank
end
function ns.HaveCount(id) local a, b = ns.HaveSplit(id); return a + b end

-- ---------- оценка сумок над окном сумок: «Сбросить» (считать только новое - для фарма) и «Обновить» (вся стоимость) ----------
-- цена предмета: на аукцион (за вычетом 5%) или торговцу - что выгоднее; персональные - только торговцу
local function unitValue(id, bound)
  local v = ns.VendorSell and ns.VendorSell(id) or 0
  if bound then return v end
  local a = ns.AHPrice(id)
  local net = a and math.floor(a * (1 - ns.Cut())) or 0
  return math.max(net, v or 0)
end
function ns.BagValue()
  local counts, units = {}, {}
  local C = C_Container
  for _, b in ipairs(bagIDs()) do
    local n = (C and C.GetContainerNumSlots and safe(C.GetContainerNumSlots, b)) or 0
    for s = 1, n do
      local info = C and C.GetContainerItemInfo and safe(C.GetContainerItemInfo, b, s)
      if info and info.itemID then
        local id = info.itemID
        counts[id] = (counts[id] or 0) + (info.stackCount or 1)
        local u = unitValue(id, info.isBound)
        if not units[id] or u > units[id] then units[id] = u end
      end
    end
  end
  local c = ns.charKey and ns.DB.chars[ns.charKey]
  local base = c and c.bagBase
  local total = 0
  for id, n in pairs(counts) do
    local k = base and math.max(0, n - (base[id] or 0)) or n
    total = total + k * (units[id] or 0)
  end
  return total, base ~= nil, c and c.bagBaseT
end
-- деньги, поднятые с добычи (мобы, сундуки): прибавка денег, пока открыто окно добычи (и секунду после)
local lootOpen, lootUntil, lastMoney = false, 0, nil
ns.On("LOOT_OPENED", function() lootOpen = true end)
ns.On("LOOT_READY", function() lootOpen = true end)
ns.On("LOOT_CLOSED", function() lootOpen = false; lootUntil = GetTime() + 1.5 end)
ns.On("PLAYER_MONEY", function()
  local m = GetMoney and GetMoney() or 0
  local d = lastMoney and (m - lastMoney) or 0
  lastMoney = m
  local c = ns.charKey and ns.DB.chars[ns.charKey]
  if c and d > 0 and (lootOpen or GetTime() < lootUntil) then
    c.lootMoney = (c.lootMoney or 0) + d
    if ns.UpdateBagValue then ns.UpdateBagValue() end
  end
end)
ns.Listen("LOGIN", function() lastMoney = GetMoney and GetMoney() or 0 end)
-- итог для окошка: предметы и/или поднятые деньги (галочки в меню окошка)
function ns.FarmValue()
  local S = ns.DB.settings
  local items, farm, t = ns.BagValue()
  local c = ns.charKey and ns.DB.chars[ns.charKey] or {}
  local money = farm and (c.lootMoney or 0) or (GetMoney and GetMoney() or 0)
  local total = (S.farmItems ~= false and items or 0) + (S.farmMoney ~= false and money or 0)
  return total, farm, t, items, money
end
function ns.BagReset()
  local c = ns.DB.chars[ns.charKey]; if not c then return end
  c.bagBase = read(bagIDs()); c.bagBaseT = time(); c.lootMoney = 0
  if ns.UpdateBagValue then ns.UpdateBagValue() end
end
function ns.BagFull()
  local c = ns.DB.chars[ns.charKey]; if not c then return end
  c.bagBase = nil; c.bagBaseT = nil
  if ns.UpdateBagValue then ns.UpdateBagValue() end
end

-- маленькое отдельное окошко «стоимость сумок»: перетаскивается мышью, место запоминается, от сумок не зависит
local bar
local function updateBar()
  if not bar then return end
  if not ns.DB or ns.DB.settings.bagValue == false then bar:Hide() return end
  local total, farm, t, items, money = ns.FarmValue()
  bar.text:SetText(farm and (L"Фарм" .. ": |cffffffff" .. ns.money(total, true) .. "|r") or (L"Сумки" .. ": |cffffffff~" .. ns.money(total, true) .. "|r"))
  bar.farmSince, bar.items, bar.moneyV, bar.isFarm = farm and t or nil, items, money, farm
  bar:Show()
end
local function savePos()
  local p, _, rp, x, y = bar:GetPoint()
  ns.DB.settings.bagPos = { p or "CENTER", rp or "CENTER", math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5) }
end
local function buildBar()
  if bar or not ns.UI then return end
  local UI = ns.UI
  bar = CreateFrame("Frame", "WolfichMarketBagValue", UIParent)
  bar:SetSize(214, 24); bar:SetFrameStrata("MEDIUM"); bar:SetClampedToScreen(true)
  bar:SetMovable(true); bar:EnableMouse(true); bar:RegisterForDrag("LeftButton")
  bar:SetScript("OnDragStart", bar.StartMoving)
  bar:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePos() end)
  local p = ns.DB.settings.bagPos
  if p then bar:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else bar:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -320, 260) end
  UI.Skin(bar, { theme = "acard", scale = 0.16 })
  bar.close = UI.Icon(bar, "skin\\ai-x", 12, L"Скрыть (вернуть: Настройки у аукциониста или /wm bags)", function() ns.DB.settings.bagValue = false; bar:Hide() end)
  bar.close:SetPoint("RIGHT", -6, 0)
  -- значки: «сбросить» (считать фарм с этого момента) и «вся стоимость» (восстановить)
  local function icon(name, fn)
    local b = CreateFrame("Button", nil, bar); b:SetSize(16, 16)
    local t = b:CreateTexture(nil, "ARTWORK"); t:SetAllPoints(); UI.WinTex(t, name)
    local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); UI.WinTex(hl, name); hl:SetBlendMode("ADD"); hl:SetAlpha(0.5)
    b:SetScript("OnClick", fn); b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
  end
  bar.full = icon("ic-full", function() ns.BagFull() end); bar.full:SetPoint("RIGHT", bar.close, "LEFT", -6, 0)
  bar.reset = icon("ic-reset", function() ns.BagReset() end); bar.reset:SetPoint("RIGHT", bar.full, "LEFT", -6, 0)
  -- треугольник: что считать - предметы и/или поднятые деньги
  bar.opt = CreateFrame("Button", nil, bar); bar.opt:SetSize(14, 14); bar.opt:SetPoint("LEFT", 6, 0)
  local ot = bar.opt:CreateTexture(nil, "ARTWORK"); ot:SetAllPoints(); UI.WinTex(ot, "tri"); pcall(ot.SetRotation, ot, -math.pi / 2)
  local oh = bar.opt:CreateTexture(nil, "HIGHLIGHT"); oh:SetAllPoints(); UI.WinTex(oh, "tri"); oh:SetBlendMode("ADD"); pcall(oh.SetRotation, oh, -math.pi / 2)
  local menu = CreateFrame("Frame", nil, bar); menu:SetSize(190, 62); menu:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -2); menu:SetFrameStrata("DIALOG"); menu:EnableMouse(true)
  UI.Box(menu, 0.92); menu:Hide()
  local S = ns.DB.settings
  local c1 = UI.Check(menu, L"Предметы (шмот, ресурсы)", function() return S.farmItems ~= false end, function(v) S.farmItems = v; updateBar() end); c1:SetPoint("TOPLEFT", 8, -8)
  local c2 = UI.Check(menu, L"Валюта (деньги с добычи)", function() return S.farmMoney ~= false end, function(v) S.farmMoney = v; updateBar() end); c2:SetPoint("TOPLEFT", 8, -34)
  bar.menu = menu
  bar.opt:SetScript("OnClick", function() menu:SetShown(not menu:IsShown()) end)
  bar.opt:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(L"Что считать: предметы и/или валюту", 1, 1, 1); GameTooltip:Show() end)
  bar.opt:SetScript("OnLeave", function() GameTooltip:Hide() end)
  bar.text = UI.Font(bar, 11, UI.GOLD); bar.text:SetPoint("LEFT", bar.opt, "RIGHT", 4, 0); bar.text:SetPoint("RIGHT", bar.reset, "LEFT", -3, 0)
  bar.reset:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(L"Сбросить", 1, 0.82, 0); GameTooltip:AddLine(L"Перед фармом: то, что уже лежит в сумках, больше не считается - показывается только новое (и деньги, поднятые с добычи).", 1, 1, 1, true); GameTooltip:Show() end)
  bar.reset:SetScript("OnLeave", function() GameTooltip:Hide() end)
  bar.full:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(L"Восстановить", 1, 0.82, 0); GameTooltip:AddLine(L"Снова показывать полную стоимость сумок.", 1, 1, 1, true); GameTooltip:Show() end)
  bar.full:SetScript("OnLeave", function() GameTooltip:Hide() end)
  bar:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(L"Стоимость сумок: каждый предмет по лучшей цене - аукцион (минус 5%) или торговец; персональные - только торговцу. Перетащите мышью, чтобы передвинуть.", 1, 1, 1, true)
    if self.farmSince then GameTooltip:AddLine(string.format(L"Фарм считается с %s", date("%H:%M", self.farmSince)), 0.9, 0.7, 0.3) end
    GameTooltip:AddDoubleLine(L"Предметы", ns.money(self.items or 0, true), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine(self.isFarm and L"Валюта с добычи" or L"Золото", ns.money(self.moneyV or 0, true), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:Show()
  end)
  bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
  bar:Hide()
end
ns.Listen("LOGIN", function() buildBar(); updateBar() end)
-- не чаще раза в полсекунды, сколько бы раз ни нажимали и ни менялись сумки
local barQueued
local function queueBar() if barQueued then return end; barQueued = true; ns.After(0.3, function() barQueued = false; updateBar() end) end
ns.Listen("INVENTORY", queueBar)
ns.Listen("PRICES", queueBar)
ns.UpdateBagValue = queueBar

-- ---------- маленькое окошко «деньги персонажа»: как окошко фарма, только золото этого персонажа ----------
local mbar, sessionStart
local function updateMoney()
  if not mbar then return end
  if not ns.DB or ns.DB.settings.moneyBar == false then mbar:Hide() return end
  local m = GetMoney and GetMoney() or 0
  sessionStart = sessionStart or m
  mbar.text:SetText(ns.coins(m))
  mbar:Show()
end
local function buildMoney()
  if mbar or not ns.UI then return end
  local UI = ns.UI
  mbar = CreateFrame("Frame", "WolfichMarketMoneyBar", UIParent)
  mbar:SetSize(150, 24); mbar:SetFrameStrata("MEDIUM"); mbar:SetClampedToScreen(true)
  mbar:SetMovable(true); mbar:EnableMouse(true); mbar:RegisterForDrag("LeftButton")
  mbar:SetScript("OnDragStart", mbar.StartMoving)
  mbar:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    ns.DB.settings.moneyPos = { p or "CENTER", rp or "CENTER", math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5) }
  end)
  local p = ns.DB.settings.moneyPos
  if p then mbar:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else mbar:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -364, 290) end
  UI.Skin(mbar, { theme = "acard", scale = 0.16 })
  mbar.close = UI.Icon(mbar, "skin\\ai-x", 12, L"Скрыть (вернуть: Настройки или /wm money)", function() ns.DB.settings.moneyBar = false; mbar:Hide() end)
  mbar.close:SetPoint("RIGHT", -6, 0)
  mbar.text = UI.Font(mbar, 12, UI.TEXT); UI.SetFont(mbar.text, UI.BOLD, 12, ""); mbar.text:SetPoint("LEFT", 10, 0); mbar.text:SetPoint("RIGHT", mbar.close, "LEFT", -4, 0); mbar.text:SetJustifyH("LEFT")
  mbar:SetScript("OnEnter", function(self)
    local m = GetMoney and GetMoney() or 0
    local d = m - (sessionStart or m)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(L"Деньги персонажа", 1, 0.82, 0)
    GameTooltip:AddDoubleLine(L"Сейчас", ns.coins(m), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine(L"За эту игру", (d >= 0 and "|cff78d98a+" or "|cffff7a66-") .. ns.money(math.abs(d), true) .. "|r", 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddLine(L"Перетащите мышью, чтобы передвинуть.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  mbar:SetScript("OnLeave", function() GameTooltip:Hide() end)
  mbar:Hide()
end
ns.Listen("LOGIN", function() buildMoney(); updateMoney() end)
ns.On("PLAYER_MONEY", function() updateMoney() end)
ns.UpdateMoneyBar = updateMoney

-- ---------- план закупки: рецепты × порции → что докупить ----------
function ns.Plans() ns.DB.plans = ns.DB.plans or {}; return ns.DB.plans end
function ns.AddPlan(rec, charKey, prof, n)
  if not rec then return end
  n = math.max(1, math.floor(n or 1))
  local plans = ns.Plans()
  local reag = {}
  for _, r in ipairs(rec.reag or {}) do reag[#reag + 1] = { r[1], r[2] } end
  for _, p in ipairs(plans) do
    if p.id == rec.id and p.ck == charKey then p.n = n; p.reag = reag; p.t = time(); p.qmin, p.qmax = rec.qmin, rec.qmax; ns.say(string.format(L"план обновлён: %s ×%d", rec.name, n)); ns.Fire("PLAN") return end
  end
  plans[#plans + 1] = { id = rec.id, name = rec.name, out = rec.out, n = n, ck = charKey, prof = prof, reag = reag, t = time(), qmin = rec.qmin, qmax = rec.qmax }
  ns.say(string.format(L"добавлено в план: %s ×%d - список покупок во вкладке «План» у аукциониста.", rec.name, n))
  ns.Fire("PLAN")
end
-- сколько раз скрафтить рецепт плана (поле количества у аукциониста)
function ns.SetPlanCount(i, n)
  local p = ns.Plans()[i]
  n = math.max(1, math.min(999, math.floor(tonumber(n) or 1)))
  if p and p.n ~= n then p.n = n; p.t = time(); ns.Fire("PLAN") end
end
function ns.RemovePlan(i) local plans = ns.Plans(); if plans[i] then table.remove(plans, i); ns.Fire("PLAN") end end
function ns.ClearPlans() wipe(ns.Plans()); ns.Fire("PLAN") end
-- сколько предмета есть у текущего персонажа: сумки + банк (живые данные игры или последняя запись банка)
-- раздельно: сколько в сумках и сколько в банке. Текущий персонаж - живые данные игры, другие - последняя запись
-- итог плана: { {id, need, have, buy, unit}, ... } — сначала то, что нужно докупить (по сумме)
function ns.PlanNeeds()
  local need, order = {}, {}
  for _, p in ipairs(ns.Plans()) do
    for _, r in ipairs(p.reag or {}) do
      if not need[r[1]] then need[r[1]] = 0; order[#order + 1] = r[1] end
      need[r[1]] = need[r[1]] + r[2] * (p.n or 1)
    end
  end
  local out, total = {}, 0
  local useStock = ns.DB.settings.planUseStock ~= false -- «учитывать свои материалы» во вкладке «План»
  for _, id in ipairs(order) do
    local bags, bank = ns.HaveSplit(id)
    local have = useStock and (bags + bank) or 0
    local buy = math.max(0, need[id] - have)
    local unit = ns.AHPrice(id) or ns.DB.vendor[id]
    if unit and buy > 0 then total = total + unit * buy end
    out[#out + 1] = { id = id, need = need[id], have = have, bags = bags, bank = bank, buy = buy, unit = unit }
  end
  table.sort(out, function(a, b)
    if (a.buy > 0) ~= (b.buy > 0) then return a.buy > 0 end
    local x, y = (a.unit or 0) * a.buy, (b.unit or 0) * b.buy
    if x == y then return ns.itemName(a.id) < ns.itemName(b.id) end
    return x > y
  end)
  return out, total
end
-- прибыль плана: по каждому рецепту и всего. Материалы - по рыночной цене (дешевле: торговец или аукцион),
-- выручка - цена результата на аукционе минус 5%
function ns.PlanProfit()
  local rows, tot = {}, { revenue = 0, cost = 0, missing = false }
  for i, p in ipairs(ns.Plans()) do
    local r = { revenue = nil, cost = 0, missing = false }
    for _, m in ipairs(p.reag or {}) do
      local u = ns.CostPrice(m[1])
      if u then r.cost = r.cost + u * m[2] * (p.n or 1) else r.missing = true end
    end
    local sell = p.out and ns.AHPrice(p.out)
    if sell then
      local q = ((p.qmin or 1) + (p.qmax or 1)) / 2
      r.revenue = sell * q * (p.n or 1) * (1 - ns.Cut())
    end
    if r.revenue and not r.missing then r.profit = r.revenue - r.cost end
    rows[i] = r
    if r.revenue then tot.revenue = tot.revenue + r.revenue else tot.missing = true end
    tot.cost = tot.cost + r.cost
    if r.missing then tot.missing = true end
  end
  tot.profit = tot.revenue - tot.cost
  return rows, tot
end
