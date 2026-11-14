-- WolfichMarket: аукцион — снимок по кнопке и по таймеру, панель: отмеченные, крафт, покупка, продажа, график, настройки
local _, ns = ...
local L = ns.L
local safe, UI = ns.safe, ns.UI
local M = ns.MEDIA
local COOLDOWN = 15 * 60

-- ---------- полный снимок аукциона ----------
local busy, processing, wanted = false, false, false
local panel

local function setStatus() ns.Fire("SCAN_STATE") end

local function finishScan()
  if processing then return end
  local n = safe(C_AuctionHouse.GetNumReplicateItems) or 0
  if n == 0 then busy = false; ns.say(L"аукцион ответил пустым списком - попробуйте позже."); setStatus() return end
  processing = true
  local items = {}
  local i = 0
  local function step()
    local last = math.min(i + 2000, n - 1)
    for k = i, last do
      local name, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = safe(C_AuctionHouse.GetReplicateItemInfo, k)
      if itemID then
        count = math.max(count or 1, 1)
        local rec = items[itemID]
        if not rec then rec = { 0, 0, 0 }; items[itemID] = rec end -- мин. цена за шт, количество, лотов
        if buyout and buyout > 0 then local u = math.floor(buyout / count + 0.5); if rec[1] == 0 or u < rec[1] then rec[1] = u end end
        rec[2] = rec[2] + count
        rec[3] = rec[3] + 1
        if name and name ~= "" and not ns.DB.names[itemID] then ns.DB.names[itemID] = ns.clean(name) end
      end
    end
    i = last + 1
    ns.progress = math.floor(i / n * 100)
    setStatus()
    if i < n then ns.After(0, step) return end
    local prev = ns.CurrentScan()
    local scan = { t = time(), lots = n, char = ns.charKey, realm = ns.realmKey, items = items }
    ns.DB.ahScans[ns.realmKey] = scan
    -- история: отмеченные и всё, что связано с рецептами персонажа
    local want = ns.RecipeItems()
    for id in pairs(ns.DB.marked) do want[id] = true end
    for id in pairs(want) do local r = items[id]; if r and r[1] > 0 then ns.AddHistory(id, r[1], r[2], scan.t) end end
    busy, processing, ns.progress = false, false, nil
    local cnt = 0; for _ in pairs(items) do cnt = cnt + 1 end
    ns.say(string.format(L"|cff78d98aснимок аукциона готов|r: %d лотов, %d предметов.", n, cnt))
    setStatus()
    ns.Fire("PRICES")
    ns.Fire("SCAN_DONE", scan, prev)
  end
  step()
end

function ns.StartScan(auto)
  if not (C_AuctionHouse and C_AuctionHouse.ReplicateItems) then ns.say(L"в этой версии игры нет полного скана аукциона.") return end
  if not ns.ahOpen then wanted = true; ns.say(L"откройте окно аукциона - скан начнётся сам.") return end
  if busy then return end
  local left = (ns.DB.ahLastReq or 0) + COOLDOWN - time()
  if left > 0 then if not auto then ns.say(string.format(L"следующий снимок можно через %d:%02d.", math.floor(left / 60), left % 60)) end return end
  busy, wanted = true, false
  ns.DB.ahLastReq = time()
  setStatus()
  local ok = pcall(C_AuctionHouse.ReplicateItems)
  if not ok then busy = false; setStatus(); ns.say(L"сервер отказал - подождите 15 минут.") return end
  ns.After(20, function() if busy and (safe(C_AuctionHouse.GetNumReplicateItems) or 0) > 0 then finishScan() end end)
  ns.After(90, function() if busy and not processing then busy = false; setStatus(); ns.say(L"сервер не прислал аукцион - попробуйте позже.") end end)
end
function ns.ScanBusy() return busy end

local replPending = false
ns.On("REPLICATE_ITEM_LIST_UPDATE", function()
  if busy and not replPending then replPending = true; ns.After(1, function() replPending = false; if busy then finishScan() end end) end
end)

-- автоскан: раз в N минут, пока открыт аукционист
local autoTicker
local function autoTick()
  local S = ns.DB.settings
  if not ns.ahOpen or not S.autoScan or busy then return end
  local every = math.max(15, S.autoScanMin or 15) * 60
  if time() - (ns.DB.ahLastReq or 0) >= every then ns.StartScan(true) end
end

ns.On("AUCTION_HOUSE_SHOW", function()
  ns.ahOpen = true
  ns.Fire("AH_STATE")
  if panel == nil then ns.BuildAHPanel() elseif panel then panel:Show() end -- крестик скрывает панель только до следующего открытия
  if wanted then ns.After(1, function() ns.StartScan() end) else ns.After(2, autoTick) end
  if not autoTicker and C_Timer and C_Timer.NewTicker then autoTicker = C_Timer.NewTicker(30, autoTick) end
end)
ns.On("AUCTION_HOUSE_CLOSED", function()
  ns.ahOpen = false
  ns.Fire("AH_STATE")
  if autoTicker then autoTicker:Cancel(); autoTicker = nil end
end)

-- цены из обычных поисков на аукционе
ns.On("COMMODITY_SEARCH_RESULTS_UPDATED", function(itemID)
  local first = itemID and safe(C_AuctionHouse.GetCommoditySearchResultInfo, itemID, 1)
  if first and first.unitPrice then
    local total = 0
    for k = 1, (safe(C_AuctionHouse.GetNumCommoditySearchResults, itemID) or 0) do local r = safe(C_AuctionHouse.GetCommoditySearchResultInfo, itemID, k); if r then total = total + (r.quantity or 0) end end
    ns.SeenPrice(itemID, first.unitPrice, total)
    ns.Fire("PRICES")
  end
  ns.Fire("SEARCH_RESULTS", itemID, true)
end)
ns.On("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey)
  if not itemKey or not itemKey.itemID then return end
  local best
  for k = 1, (safe(C_AuctionHouse.GetNumItemSearchResults, itemKey) or 0) do
    local r = safe(C_AuctionHouse.GetItemSearchResultInfo, itemKey, k)
    if r and r.buyoutAmount and r.buyoutAmount > 0 then local u = r.buyoutAmount / math.max(1, r.quantity or 1); if not best or u < best then best = u end end
  end
  if best then ns.SeenPrice(itemKey.itemID, math.floor(best + 0.5)); ns.Fire("PRICES") end
  ns.Fire("SEARCH_RESULTS", itemKey.itemID, false, itemKey)
end)

-- ---------- панель у окна аукциона ----------
local tabs, pages = nil, {}
local chartItem, buyItem, sellSel

local function header()
  local S = ns.DB.settings
  panel.scanBtn = UI.Button(panel, L"Сканировать", 120, 22, function() ns.StartScan() end, true)
  panel.scanBtn:SetPoint("TOPRIGHT", -62, -19)
  panel.state = UI.Font(panel, 10, UI.DIM); panel.state:SetPoint("TOPLEFT", 20, -62); panel.state:SetPoint("RIGHT", -22, 0); panel.state:SetWordWrap(true); panel.state:SetMaxLines(2)
end

local function updateHeader()
  if not panel then return end
  local scan = ns.CurrentScan()
  local left = (ns.DB.ahLastReq or 0) + COOLDOWN - time()
  if busy then
    panel.scanBtn:SetLabel(ns.progress and (L"Обработка " .. ns.progress .. "%") or L"Сканирую..."); panel.scanBtn:Disable()
  elseif left > 0 then
    panel.scanBtn:SetLabel(string.format(L"Скан через %d:%02d", math.floor(left / 60), left % 60)); panel.scanBtn:Disable()
  else
    panel.scanBtn:SetLabel(L"Сканировать"); panel.scanBtn:Enable()
  end
  local S = ns.DB.settings
  panel.state:SetText((scan and (L"Снимок: " .. ns.ago(scan.t) .. " / " .. scan.lots .. L" лотов") or L"|cffff9966Снимка ещё нет - нажмите «Сканировать».|r")
    .. (S.autoScan and (L"  /  авто раз в " .. S.autoScanMin .. L" мин") or ""))
end

-- строка списка предметов: звезда, иконка, имя, цена, изменение, кнопки
local function itemRow(r, withBuy)
  r.star = UI.Icon(r, "star-off", 14, L"Отметить / снять", function(self) local d = self:GetParent().data; if d then ns.ToggleMark(d.id) end end); r.star:SetPoint("LEFT", 2, 0)
  r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(18, 18); r.icon:SetPoint("LEFT", r.star, "RIGHT", 4, 0)
  r.buy = UI.Icon(r, "bag", 16, L"Купить", function(self) local d = self:GetParent().data; if d then ns.OpenBuy(d.id) end end); r.buy:SetPoint("RIGHT", -2, 0)
  r.search = UI.Icon(r, "search", 15, L"Найти в окне аукциона", function(self) local d = self:GetParent().data; if d then ns.SearchAH(d.id) end end); r.search:SetPoint("RIGHT", r.buy, "LEFT", -4, 0)
  r.chart = UI.Icon(r, "chart", 15, L"График цены", function(self) local d = self:GetParent().data; if d then ns.OpenChart(d.id) end end); r.chart:SetPoint("RIGHT", r.search, "LEFT", -4, 0)
  r.chg = UI.Font(r, 10); r.chg:SetPoint("RIGHT", r.chart, "LEFT", -6, 0); r.chg:SetWidth(52); r.chg:SetJustifyH("RIGHT")
  r.price = UI.Font(r, 11); r.price:SetPoint("RIGHT", r.chg, "LEFT", -4, 0); r.price:SetJustifyH("RIGHT")
  r.name = UI.Font(r, 11); r.name:SetPoint("LEFT", r.icon, "RIGHT", 5, 0); r.name:SetPoint("RIGHT", r.price, "LEFT", -6, 0)
  r:SetScript("OnEnter", function(self) if self.data then GameTooltip:SetOwner(self, "ANCHOR_LEFT"); pcall(GameTooltip.SetItemByID, GameTooltip, self.data.id); GameTooltip:Show() end end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
local function fillItemRow(r, d)
  local hdr = d.header ~= nil
  for _, w in ipairs({ r.star, r.icon, r.buy, r.search, r.chart, r.chg }) do w:SetShown(not hdr) end
  if hdr then
    r.name:SetText("|cffe6b450" .. d.header .. "|r"); r.price:SetText(d.headerRight or "")
    return
  end
  r.star:SetIcon(ns.IsMarked(d.id) and "star-on" or "star-off")
  r.icon:SetTexture(ns.itemIcon(d.id))
  r.name:SetText(ns.itemLinkText(d.id) .. (d.extra or ""))
  local p = ns.AHPrice(d.id)
  r.price:SetText(p and ns.money(p, true) or L"|cff777777нет|r")
  local avg = ns.AvgPrice(d.id, 24)
  r.chg:SetText(p and avg and ns.pct((p - avg) / avg * 100) or "")
end

-- вкладка: отмеченные
local function pageMarked(f)
  local l = UI.List(f, 22, itemRow, fillItemRow)
  l:SetAllPoints()
  f.list = l
  f.refresh = function()
    local d = {}
    for id in pairs(ns.DB.marked) do d[#d + 1] = { id = id } end
    table.sort(d, function(a, b) return ns.itemName(a.id) < ns.itemName(b.id) end)
    l:SetData(d)
    l.empty:SetText(L"Отметьте нужные материалы и предметы |TInterface\\AddOns\\WolfichMarket\\media\\star-on:12:12|t -\nв окне профессии, во вкладке «Крафт»\nили Alt+клик по предмету в сумке.\nУведомления о скачках цены приходят только по ним.")
  end
end

-- вкладка: прибыльный крафт
local function pageCraft(f)
  local l = UI.List(f, 22, function(r)
    itemRow(r)
  end, function(r, d)
    fillItemRow(r, { id = d.id })
    r.name:SetText(ns.itemLinkText(d.id) .. (ns.IsLearned(d.pr.rec) and "" or L" |cffff9966(не изучен)|r"))
    r.chg:SetText(d.pr.profit and ((d.pr.profit >= 0 and "|cff78d98a+" or "|cffff7a66") .. ns.money(d.pr.profit, true) .. "|r") or L"|cffaa8866нет цены|r")
    r.chg:SetWidth(80)
  end)
  local chk = UI.Check(f, L"включая неизученные рецепты", function() return ns.DB.settings.showUnlearned end, function(v)
    ns.DB.settings.showUnlearned = v; ns.Fire("RECIPES"); ns.DecorateRecipeRows()
  end)
  chk:SetPoint("TOPLEFT", -2, 2)
  l:SetPoint("TOPLEFT", 0, -22); l:SetPoint("BOTTOMRIGHT")
  f.refresh = function()
    chk:SetChecked(ns.DB.settings.showUnlearned)
    local d = {}
    for _, pr in ipairs(ns.AllRecipeProfits(nil, ns.DB.settings.showUnlearned)) do if pr.rec.out then d[#d + 1] = { id = pr.rec.out, pr = pr } end end
    table.sort(d, function(a, b) return (a.pr.profit or -1e12) > (b.pr.profit or -1e12) end)
    l:SetData(d)
    l.empty:SetText(L"Откройте окна своих профессий - здесь появятся рецепты с прибылью.")
  end
end

-- вкладка: покупка
local function pageBuy(f)
  f.icon = f:CreateTexture(nil, "ARTWORK"); f.icon:SetSize(32, 32); f.icon:SetPoint("TOPLEFT", 4, -2)
  f.title = UI.Font(f, 13, UI.GOLD, "OVERLAY", "OUTLINE"); f.title:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 8, -2); f.title:SetPoint("RIGHT", -4, 0)
  f.sub = UI.Font(f, 10, UI.DIM); f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3); f.sub:SetPoint("RIGHT", -4, 0)
  f.list = UI.List(f, 20, function(r)
    r.price = UI.Font(r, 11); r.price:SetPoint("LEFT", 6, 0)
    r.qty = UI.Font(r, 11, UI.DIM); r.qty:SetPoint("LEFT", 150, 0)
    r.btn = UI.Button(r, L"Купить", 70, 18, function(self)
      local d = self:GetParent().data
      if d and d.auctionID and d.buyout then pcall(C_AuctionHouse.PlaceBid, d.auctionID, d.buyout) end
    end); r.btn:SetPoint("RIGHT", -2, 0)
  end, function(r, d)
    r.price:SetText(ns.money(d.unit) .. (d.commodity and L" |cffaaaaaaза шт|r" or ""))
    r.qty:SetText("× " .. (d.qty or 1))
    r.btn:SetShown(not d.commodity)
  end)
  f.list:SetPoint("TOPLEFT", 0, -42); f.list:SetPoint("RIGHT"); f.list:SetPoint("BOTTOM", 0, 64)
  -- покупка «товара» (стакается): количество → цена → подтверждение
  f.qtyLabel = UI.Font(f, 11); f.qtyLabel:SetPoint("BOTTOMLEFT", 4, 40); f.qtyLabel:SetText(L"Количество:")
  f.qty = CreateFrame("EditBox", nil, f, "InputBoxTemplate"); f.qty:SetSize(60, 20); f.qty:SetPoint("LEFT", f.qtyLabel, "RIGHT", 10, 0); f.qty:SetAutoFocus(false); f.qty:SetNumeric(true); f.qty:SetText("1")
  f.price = UI.Button(f, L"Узнать цену", 110, 22, function()
    local q = tonumber(f.qty:GetText()) or 0
    if buyItem and q > 0 then f.confirm:Disable(); f.total:SetText(L"запрос цены..."); pcall(C_AuctionHouse.StartCommoditiesPurchase, buyItem, q) end
  end); f.price:SetPoint("LEFT", f.qty, "RIGHT", 10, 0)
  f.confirm = UI.Button(f, L"Купить", 130, 22, function()
    local q = tonumber(f.qty:GetText()) or 0
    if buyItem and q > 0 then pcall(C_AuctionHouse.ConfirmCommoditiesPurchase, buyItem, q); f.confirm:Disable() end
  end, true); f.confirm:SetPoint("BOTTOMRIGHT", -4, 8); f.confirm:Disable()
  f.total = UI.Font(f, 11); f.total:SetPoint("BOTTOMLEFT", 4, 12); f.total:SetPoint("RIGHT", f.confirm, "LEFT", -8, 0)
  f.list.empty:SetText(L"На аукционе сейчас нет.")
  f.setCommodity = function(c)
    for _, w in ipairs({ f.qtyLabel, f.qty, f.price, f.confirm, f.total }) do w:SetShown(c) end
  end
  f.setCommodity(false)
  -- список материалов для всех рецептов персонажа, по профессиям
  f.back = UI.Button(f, L"< К материалам", 130, 20, function() buyItem = nil; f.refresh() end)
  f.back:SetPoint("TOPRIGHT", 0, 0)
  f.mats = UI.List(f, 22, itemRow, fillItemRow)
  f.mats:SetPoint("TOPLEFT", 0, -42); f.mats:SetPoint("BOTTOMRIGHT")
  f.mats.empty:SetText(L"Откройте окна своих профессий - здесь появятся\nвсе материалы для ваших рецептов.")
  local function count(id)
    local n = (C_Item and C_Item.GetItemCount and safe(C_Item.GetItemCount, id, true)) or (GetItemCount and safe(GetItemCount, id, true))
    return n or 0
  end
  f.matsData = function()
    local d = {}
    local c = ns.DB.chars[ns.charKey]
    local profs = {}
    for prof in pairs(c and c.profs or {}) do profs[#profs + 1] = prof end
    table.sort(profs)
    for _, prof in ipairs(profs) do
      local seen, items = {}, {}
      for _, rec in ipairs(c.profs[prof].recipes or {}) do
        if ns.DB.settings.showUnlearned or ns.IsLearned(rec) then for _, r in ipairs(rec.reag or {}) do
          local id = r[1]
          if not seen[id] then seen[id] = { id = id, recipes = 0 }; items[#items + 1] = seen[id] end
          seen[id].recipes = seen[id].recipes + 1
        end end
      end
      if #items > 0 then
        table.sort(items, function(a, b) return ns.itemName(a.id) < ns.itemName(b.id) end)
        d[#d + 1] = { header = prof, headerRight = L"|cffaaaaaaматериалов: " .. #items .. "|r" }
        for _, it in ipairs(items) do
          local have = count(it.id)
          local v = ns.DB.vendor[it.id]
          it.extra = (have > 0 and (L" |cff78d98a(есть " .. have .. ")|r") or "") .. (v and L" |cffaaaaaa(торговец)|r" or "")
          d[#d + 1] = it
        end
      end
    end
    return d
  end
  f.refresh = function()
    local item = buyItem ~= nil
    f.mats:SetShown(not item); f.list:SetShown(item); f.back:SetShown(item)
    if not item then
      f.setCommodity(false)
      f.icon:SetTexture(ns.MEDIA .. "bag")
      f.title:SetText(L"Материалы для ваших рецептов")
      f.sub:SetText(L"Нажмите на сумку у материала, чтобы купить. Зелёным - сколько уже есть.")
      f.mats:SetData(f.matsData())
    end
  end
end

local function searchItem(id)
  local key = C_AuctionHouse.MakeItemKey and C_AuctionHouse.MakeItemKey(id)
  if not key then return end
  local sorts = {}
  if Enum and Enum.AuctionHouseSortOrder then sorts = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } } end
  pcall(C_AuctionHouse.SendSearchQuery, key, sorts, false)
end

function ns.OpenBuy(id)
  if not panel then return end
  if not ns.ahOpen then ns.say(L"покупка доступна у аукциониста.") return end
  buyItem = id
  tabs.select(3)
  local f = pages[3]
  f.icon:SetTexture(ns.itemIcon(id)); f.title:SetText(ns.itemLinkText(id)); f.sub:SetText(L"ищу на аукционе...")
  f.list:SetData({}); f.total:SetText(""); f.confirm:Disable(); f.setCommodity(false)
  searchItem(id)
end

ns.Listen("SEARCH_RESULTS", function(itemID, commodity, itemKey)
  if not panel or itemID ~= buyItem then return end
  local f = pages[3]
  local d = {}
  if commodity then
    for k = 1, math.min(50, safe(C_AuctionHouse.GetNumCommoditySearchResults, itemID) or 0) do
      local r = safe(C_AuctionHouse.GetCommoditySearchResultInfo, itemID, k)
      if r then d[#d + 1] = { unit = r.unitPrice, qty = r.quantity, commodity = true } end
    end
  else
    for k = 1, math.min(50, safe(C_AuctionHouse.GetNumItemSearchResults, itemKey) or 0) do
      local r = safe(C_AuctionHouse.GetItemSearchResultInfo, itemKey, k)
      if r and r.buyoutAmount then d[#d + 1] = { unit = r.buyoutAmount, buyout = r.buyoutAmount, qty = r.quantity, auctionID = r.auctionID } end
    end
  end
  f.setCommodity(commodity)
  f.sub:SetText(#d > 0 and (commodity and L"Товар: укажите количество и нажмите «Узнать цену»" or L"Выберите лот и нажмите «Купить»") or L"На аукционе сейчас нет")
  f.list:SetData(d)
end)
ns.On("COMMODITY_PRICE_UPDATED", function(unitPrice, totalPrice)
  if not panel then return end
  local f = pages[3]
  f.total:SetText(L"Итого: " .. ns.money(totalPrice) .. "  |cffaaaaaa(" .. ns.money(unitPrice) .. L" за шт)|r")
  f.confirm:SetLabel(L"Купить за " .. ns.money(totalPrice, true):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
  f.confirm:Enable()
end)
local function bought(ok, msg)
  ns.say(ok and L"|cff78d98aпокупка совершена.|r Предметы придут на почту." or (L"покупка не удалась" .. (msg and (": " .. msg) or "")))
  if buyItem then searchItem(buyItem) end
end
ns.On("COMMODITY_PURCHASE_SUCCEEDED", function() bought(true) end)
ns.On("COMMODITY_PURCHASE_FAILED", function() bought(false) end)
ns.On("AUCTION_HOUSE_PURCHASE_COMPLETED", function() bought(true) end)

-- вкладка: продажа
local function bagItems()
  local out, byId = {}, {}
  if not C_Container then return out end
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    for slot = 1, (safe(C_Container.GetContainerNumSlots, bag) or 0) do
      local info = safe(C_Container.GetContainerItemInfo, bag, slot)
      if info and info.itemID and not info.isBound then
        local loc = ItemLocation and ItemLocation:CreateFromBagAndSlot(bag, slot)
        local valid = not (C_AuctionHouse.IsSellItemValid and loc) or safe(C_AuctionHouse.IsSellItemValid, loc, false)
        if valid then
          local e = byId[info.itemID]
          if not e then e = { id = info.itemID, count = 0, loc = loc, stack = info.stackCount or 1 }; byId[info.itemID] = e; out[#out + 1] = e end
          e.count = e.count + (info.stackCount or 1)
        end
      end
    end
  end
  table.sort(out, function(a, b) return ns.itemName(a.id) < ns.itemName(b.id) end)
  return out
end
local DURS = { { 1, "2 ч" }, { 2, "8 ч" }, { 3, "24 ч" } } -- сроки аукциона в Forever
-- выгодно ли продавать: unit — цена за шт, которую вы ставите
local function sellVerdict(id, unit)
  local cost = ns.CraftCost(id)
  local vendor = ns.VendorSell(id)
  local net = unit and unit > 0 and unit * (1 - ns.AH_CUT) or nil
  local r = { cost = cost, vendor = vendor, net = net }
  if net and cost then r.profit = net - cost end
  if net and vendor and vendor >= net then r.text, r.color = L"Торговцу выгоднее, чем на аукцион", "|cffffd060"
  elseif r.profit and r.profit > 0 then r.text, r.color = L"Выгодно продавать сейчас", "|cff78d98a"
  elseif r.profit then r.text, r.color = L"Невыгодно: дешевле, чем материалы", "|cffff7a66"
  elseif net then r.text, r.color = L"Не крафтится вами - сравните с ценой аукциона", "|cffaaaaaa"
  else r.text, r.color = L"Нет цены на аукционе - сделайте снимок", "|cffaaaaaa" end
  return r
end

local function pageSell(f)
  -- шапка колонок
  local hdr = CreateFrame("Frame", nil, f); hdr:SetPoint("TOPLEFT"); hdr:SetPoint("TOPRIGHT"); hdr:SetHeight(16)
  local function col(text, x) local t = UI.Font(hdr, 10, UI.DIM); t:SetPoint("RIGHT", hdr, "RIGHT", x, 0); t:SetJustifyH("RIGHT"); t:SetText(text) end
  local h1 = UI.Font(hdr, 10, UI.DIM); h1:SetPoint("LEFT", 46, 0); h1:SetText(L"Предмет")
  col(L"Прибыль", -12); col(L"Аукцион", -84); col(L"Себест.", -156)
  f.list = UI.List(f, 22, function(r)
    r.chk = UI.CheckBox(r, 18); r.chk:SetPoint("LEFT", 1, 0)
    r.chk:SetScript("OnClick", function(self) local d = self:GetParent().data; if d then f.checked[d.id] = self:GetChecked() and true or nil; f.updateBulk() end end)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(18, 18); r.icon:SetPoint("LEFT", r.chk, "RIGHT", 2, 0)
    r.prof = UI.Font(r, 11); r.prof:SetPoint("RIGHT", -4, 0); r.prof:SetWidth(68); r.prof:SetJustifyH("RIGHT")
    r.price = UI.Font(r, 11); r.price:SetPoint("RIGHT", r.prof, "LEFT", -4, 0); r.price:SetWidth(68); r.price:SetJustifyH("RIGHT")
    r.cost = UI.Font(r, 11, UI.DIM); r.cost:SetPoint("RIGHT", r.price, "LEFT", -4, 0); r.cost:SetWidth(68); r.cost:SetJustifyH("RIGHT")
    r.name = UI.Font(r, 11); r.name:SetPoint("LEFT", r.icon, "RIGHT", 5, 0); r.name:SetPoint("RIGHT", r.cost, "LEFT", -6, 0)
    r:SetScript("OnClick", function(self) if self.data then f.select(self.data) end end)
    r:SetScript("OnEnter", function(self) if self.data then GameTooltip:SetOwner(self, "ANCHOR_LEFT"); pcall(GameTooltip.SetItemByID, GameTooltip, self.data.id); GameTooltip:Show() end end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end, function(r, d)
    r.chk:SetChecked(f.checked[d.id] == true)
    r.icon:SetTexture(ns.itemIcon(d.id))
    r.name:SetText(ns.itemLinkText(d.id) .. " |cffaaaaaa×" .. d.count .. "|r" .. (sellSel and sellSel.id == d.id and " |cffe6b450<|r" or ""))
    local p = ns.AHPrice(d.id)
    local v = sellVerdict(d.id, p)
    r.cost:SetText(v.cost and ns.money(v.cost, true) or "|cff555555-|r")
    r.price:SetText(p and ns.money(p, true) or L"|cff777777нет|r")
    if v.profit then r.prof:SetText((v.profit >= 0 and "|cff78d98a+" or "|cffff7a66") .. ns.money(v.profit, true) .. "|r")
    elseif v.vendor and v.net and v.vendor >= v.net then r.prof:SetText(L"|cffffd060торговцу|r")
    else r.prof:SetText("|cff555555-|r") end
  end)
  f.list:SetPoint("TOPLEFT", 0, -18); f.list:SetPoint("RIGHT"); f.list:SetPoint("BOTTOM", 0, 240)
  f.checked = {}
  f.allBtn = UI.Button(f, L"Отметить все", 110, 22, function()
    local any = next(f.checked) ~= nil
    wipe(f.checked)
    if not any then for _, d in ipairs(f.list.data) do if ns.AHPrice(d.id) then f.checked[d.id] = true end end end
    f.list:Refresh(); f.updateBulk()
  end); f.allBtn:SetPoint("BOTTOMLEFT", 0, 212)
  f.bulk = UI.Button(f, L"Выставить отмеченные", 220, 22, function() f.postNext() end, true); f.bulk:SetPoint("BOTTOMRIGHT", 0, 212)
  _G.WolfichMarketPostNextButton = f.bulk
  ns.PostNext = function() if f:IsVisible() then f.postNext() else ns.say(L"откройте вкладку «Продать» у аукциониста.") end end
  f.bulkInfo = UI.Font(f, 10, UI.DIM); f.bulkInfo:SetPoint("TOPLEFT", f.allBtn, "BOTTOMLEFT", 2, -3); f.bulkInfo:SetPoint("RIGHT", f, "RIGHT", -2, 0); f.bulkInfo:SetWordWrap(true); f.bulkInfo:SetMaxLines(2)
  f.list.empty:SetText(L"В сумках нет предметов, которые можно выставить.")
  local box = CreateFrame("Frame", nil, f); box:SetPoint("BOTTOMLEFT"); box:SetPoint("BOTTOMRIGHT"); box:SetHeight(180)
  UI.Skin(box, { theme = "acard" })
  f.sel = UI.Font(box, 12, UI.GOLD); f.sel:SetPoint("TOPLEFT", 8, -6); f.sel:SetPoint("RIGHT", -8, 0)
  -- разбор: себестоимость / аукцион / торговец / итог
  f.analysis = UI.Font(box, 11); f.analysis:SetPoint("TOPLEFT", 8, -24); f.analysis:SetPoint("RIGHT", -8, 0); f.analysis:SetWordWrap(true); f.analysis:SetJustifyV("TOP"); f.analysis:SetHeight(64)
  local pl = UI.Font(box, 11); pl:SetPoint("TOPLEFT", 8, -94); pl:SetText(L"Цена за шт:")
  f.money = UI.MoneyInput(box, function() f.calc() end); f.money:SetPoint("LEFT", pl, "RIGHT", 4, 0)
  -- быстрые наценки к начальной цене (минимальная на аукционе − 1м)
  -- наценка действует и на выбранный предмет, и на «Выставить отмеченные»
  f.markup = 1
  local function setMul(k)
    f.markup = k
    for i, b in ipairs(f.mulBtns or {}) do
      local on = ({ 1, 1.05, 1.10 })[i] == k
      b:SetGold(on)
    end
    if f.basePrice and f.basePrice > 0 then f.money:Set(math.floor(f.basePrice * k + 0.5)); f.calc() end
    if f.updateBulk then f.updateBulk() end
  end
  local bMin = UI.Button(box, L"мин", 40, 20, function() setMul(1) end); bMin:SetPoint("LEFT", f.money, "RIGHT", 0, 0)
  local b5 = UI.Button(box, "+5%", 40, 20, function() setMul(1.05) end); b5:SetPoint("LEFT", bMin, "RIGHT", 3, 0)
  local b10 = UI.Button(box, "+10%", 44, 20, function() setMul(1.10) end); b10:SetPoint("LEFT", b5, "RIGHT", 3, 0)
  f.mulBtns = { bMin, b5, b10 }
  setMul(1)
  local ql = UI.Font(box, 11); ql:SetPoint("TOPLEFT", 8, -120); ql:SetText(L"Количество:")
  f.qty = CreateFrame("EditBox", nil, box, "InputBoxTemplate"); f.qty:SetSize(54, 20); f.qty:SetPoint("LEFT", ql, "RIGHT", 10, 0); f.qty:SetAutoFocus(false); f.qty:SetNumeric(true)
  f.qty:SetScript("OnTextChanged", function() f.calc() end)
  f.durBtns = {}
  for i, d in ipairs(DURS) do
    local b = UI.Button(box, L(d[2]), 46, 20, function() f.dur = d[1]; f.calc(); f.updateBulk() end)
    b:SetPoint("LEFT", f.qty, "RIGHT", 12 + (i - 1) * 50, 0); f.durBtns[i] = b
  end
  f.dur = 2
  f.info = UI.Font(box, 10, UI.DIM); f.info:SetPoint("BOTTOMLEFT", 8, 10); f.info:SetPoint("RIGHT", -140, 0); f.info:SetWordWrap(true)
  f.post = UI.Button(box, L"Выставить", 124, 24, function() f.doPost() end, true); f.post:SetPoint("BOTTOMRIGHT", -8, 8); f.post:Disable()
  f.select = function(d)
    sellSel = d
    f.sel:SetText(ns.itemLinkText(d.id) .. L" |cffaaaaaa(в сумках " .. d.count .. ")|r")
    local p = ns.AHPrice(d.id)
    f.basePrice = p and math.max(1, p - 1) or nil
    f.money:Set(f.basePrice and math.floor(f.basePrice * (f.markup or 1) + 0.5) or 0)
    d.commodity = d.loc and C_AuctionHouse.GetItemCommodityStatus and Enum and Enum.ItemCommodityStatus
      and safe(C_AuctionHouse.GetItemCommodityStatus, d.loc) == Enum.ItemCommodityStatus.Commodity
    f.qty:SetText(d.commodity and d.count or 1)
    f.list:Refresh(); f.calc()
  end
  f.calc = function()
    for i, b in ipairs(f.durBtns) do b:SetGold(DURS[i][1] == f.dur) end
    local d = sellSel
    if not d then f.analysis:SetText(""); f.info:SetText(L"Выберите предмет в списке."); f.post:Disable() return end
    local q, unit = tonumber(f.qty:GetText()) or 0, f.money:Get()
    local p = ns.AHPrice(d.id)
    local v = sellVerdict(d.id, unit)
    local lines = {}
    local _, rec = ns.CraftCost(d.id)
    lines[#lines + 1] = L"Себестоимость крафта: " .. (v.cost and (ns.money(v.cost) .. (rec and ("  |cffaaaaaa(" .. rec.name .. ")|r") or "")) or L"|cffaaaaaaвы не крафтите этот предмет|r")
    lines[#lines + 1] = L"На аукционе: " .. (p and (L"мин " .. ns.money(p)) or L"|cffaaaaaaнет цены|r") .. (v.vendor and (L"   |cffaaaaaaторговцу: " .. ns.money(v.vendor) .. "|r") or "")
    if v.net then lines[#lines + 1] = L"Вам за шт после 5%: " .. ns.money(v.net) .. (v.profit and (L"   прибыль: " .. (v.profit >= 0 and "|cff78d98a+" or "|cffff7a66") .. ns.money(v.profit) .. L"|r за шт") or "") end
    lines[#lines + 1] = v.color .. v.text .. "|r"
    f.analysis:SetText(table.concat(lines, "\n"))
    local dep
    if d.commodity then dep = safe(C_AuctionHouse.CalculateCommodityDeposit, d.id, f.dur, q)
    else dep = d.loc and safe(C_AuctionHouse.CalculateItemDeposit, d.loc, f.dur, q) end
    f.info:SetText(string.format(L"Выручка за %d шт: %s / залог: %s%s", q, ns.money(unit * q * (1 - ns.AH_CUT)), dep and ns.money(dep) or "?",
      v.profit and (L"\nПрибыль всего: " .. (v.profit >= 0 and "|cff78d98a+" or "|cffff7a66") .. ns.money(v.profit * q) .. "|r") or ""))
    if q > 0 and q <= d.count and unit > 0 then f.post:Enable() else f.post:Disable() end
  end
  f.doPost = function()
    local d = sellSel; if not d or not d.loc then return end
    local q, unit = tonumber(f.qty:GetText()) or 0, f.money:Get()
    local ok, err
    if d.commodity then ok, err = pcall(C_AuctionHouse.PostCommodity, d.loc, f.dur, q, unit)
    else ok, err = pcall(C_AuctionHouse.PostItem, d.loc, f.dur, q, nil, unit) end
    if not ok then ns.say(L"не удалось выставить: " .. tostring(err)) end
    f.post:Disable()
  end
  -- очередь «выставить всё»: игра разрешает одно выставление на одно нажатие, поэтому кнопка выставляет по лоту за клик
  f.queue = function()
    local q = {}
    for _, d in ipairs(bagItems()) do
      if f.checked[d.id] then
        local p = ns.AHPrice(d.id)
        if p then q[#q + 1] = { d = d, unit = math.floor(math.max(1, p - 1) * (f.markup or 1) + 0.5) } end
      end
    end
    return q
  end
  f.updateBulk = function()
    local q = f.queue()
    local n = 0; for _ in pairs(f.checked) do n = n + 1 end
    f.allBtn:SetLabel(n > 0 and L"Снять все" or L"Отметить все")
    if #q == 0 then
      f.bulk:SetLabel(L"Выставить отмеченные"); f.bulk:Disable()
      f.bulkInfo:SetText(n > 0 and L"У отмеченных нет цены - сделайте снимок." or L"Отметьте предметы галочками.")
    else
      f.bulk:SetLabel(L"Выставить: " .. ns.itemName(q[1].d.id) .. (#q > 1 and (" (+" .. (#q - 1) .. ")") or "")); f.bulk:Enable()
      local key = GetBindingKey and GetBindingKey("WOLFICHMARKET_POSTNEXT")
      f.bulkInfo:SetText(L"Одно нажатие - один лот (так требует игра)" .. (key and (L", клавиша |cffe6b450" .. key .. "|r") or L", можно назначить клавишу в настройках управления") .. L". Цена на 1м ниже минимальной" .. ((f.markup or 1) > 1 and (" +" .. math.floor((f.markup - 1) * 100 + 0.5) .. "%") or "") .. L", срок " .. L(DURS[f.dur][2]) .. ".")
    end
  end
  f.postNext = function()
    local q = f.queue()
    local it = q[1]; if not it then f.updateBulk() return end
    local d = it.d
    d.commodity = d.loc and C_AuctionHouse.GetItemCommodityStatus and Enum and Enum.ItemCommodityStatus
      and safe(C_AuctionHouse.GetItemCommodityStatus, d.loc) == Enum.ItemCommodityStatus.Commodity
    local qty = d.commodity and d.count or 1
    local ok, err
    if d.commodity then ok, err = pcall(C_AuctionHouse.PostCommodity, d.loc, f.dur, qty, it.unit)
    else ok, err = pcall(C_AuctionHouse.PostItem, d.loc, f.dur, qty, nil, it.unit) end
    if ok then
      if d.commodity or d.count <= 1 then f.checked[d.id] = nil end
      ns.say(string.format(L"выставлено: %s ×%d по %s", ns.itemLinkText(d.id), qty, ns.money(it.unit)))
    else ns.say(L"не удалось выставить: " .. tostring(err)) end
    f.bulk:Disable()
    ns.After(1, function() f.list:SetData(bagItems()); f.updateBulk() end)
  end
  f.refresh = function() f.list:SetData(bagItems()); f.calc(); f.updateBulk() end
end
local function posted() ns.say(L"|cff78d98aлот выставлен.|r"); sellSel = nil; if pages[4] and pages[4]:IsShown() then pages[4].sel:SetText(""); pages[4].refresh() end end
ns.On("AUCTION_HOUSE_AUCTION_CREATED", posted)
ns.On("BAG_UPDATE_DELAYED", function() if pages[4] and pages[4]:IsShown() then pages[4].refresh() end end)

-- вкладка: график
local function pageChart(f)
  f.icon = f:CreateTexture(nil, "ARTWORK"); f.icon:SetSize(28, 28); f.icon:SetPoint("TOPLEFT", 4, -2)
  f.title = UI.Font(f, 13, UI.GOLD, "OVERLAY", "OUTLINE"); f.title:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 8, 0); f.title:SetPoint("RIGHT", -4, 0)
  f.stats = UI.Font(f, 10, UI.DIM); f.stats:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3); f.stats:SetPoint("RIGHT", -4, 0)
  f.chart = UI.Chart(f); f.chart:SetPoint("TOPLEFT", 0, -40); f.chart:SetPoint("BOTTOMRIGHT", 0, 30)
  f.star = UI.Button(f, "", 140, 22, function() if chartItem then ns.ToggleMark(chartItem) end end); f.star:SetPoint("BOTTOMLEFT", 2, 2)
  f.search = UI.Button(f, L"Найти на аукционе", 140, 22, function() if chartItem then ns.SearchAH(chartItem) end end); f.search:SetPoint("BOTTOMRIGHT", -2, 2)
  f.refresh = function()
    if not chartItem then local k = next(ns.DB.marked); chartItem = k end
    if not chartItem then f.title:SetText(L"Выберите предмет: кнопка графика в списках"); f.stats:SetText(""); f.chart:SetPoints(nil); f.star:Hide(); f.search:Hide() return end
    f.star:Show(); f.search:Show()
    f.icon:SetTexture(ns.itemIcon(chartItem)); f.title:SetText(ns.itemLinkText(chartItem))
    local h = ns.DB.hist[chartItem] or {}
    local p = ns.AHPrice(chartItem)
    local a24, a7 = ns.AvgPrice(chartItem, 24), ns.AvgPrice(chartItem, 24 * 7)
    local lo, hi
    for _, x in ipairs(h) do lo = math.min(lo or x[2], x[2]); hi = math.max(hi or x[2], x[2]) end
    f.stats:SetText(string.format(L"Сейчас %s / средняя 24 ч %s / 7 дн %s / мин %s / макс %s / точек %d",
      p and ns.money(p, true) or "-", a24 and ns.money(a24, true) or "-", a7 and ns.money(a7, true) or "-", lo and ns.money(lo, true) or "-", hi and ns.money(hi, true) or "-", #h))
    f.star:SetLabel(ns.IsMarked(chartItem) and L"|TInterface\\AddOns\\WolfichMarket\\media\\star-on:12:12|t Снять отметку" or L"|TInterface\\AddOns\\WolfichMarket\\media\\star-off:12:12|t Отметить")
    ns.After(0, function() f.chart:SetPoints(h) end)
  end
end
function ns.OpenChart(id) chartItem = id; if panel then tabs.select(5) end end

-- вкладка: настройки
local function pageSettings(f)
  local S = ns.DB.settings
  local y = -4
  local function chk(text, key, after)
    local c = UI.Check(f, text, function() return S[key] end, function(v) S[key] = v; if after then after() end end)
    c:SetPoint("TOPLEFT", 2, y); y = y - 26
  end
  chk(L"Уведомления о скачках цен (только отмеченные)", "alerts")
  chk(L"Звук уведомлений", "alertSound")
  chk(L"Уведомление о лучшем крафте после снимка", "bestCraftAlert")
  chk(L"Цена и прибыль в подсказке предмета", "tooltip")
  chk(L"Кнопка у миникарты (после перезагрузки интерфейса)", "minimapShown", function() ns.DB.settings.minimapHidden = not ns.DB.settings.minimapShown end)
  chk(L"Подсветка в сумках: жёлтая - торговцу, зелёная - на аукцион", "bagGlow", function() if ns.UpdateBagGlow then ns.UpdateBagGlow() end end)
  chk(L"Снимать аукцион автоматически, пока он открыт", "autoScan", updateHeader)
  local l1 = UI.Font(f, 11); l1:SetPoint("TOPLEFT", 6, y - 4); l1:SetText(L"Автоснимок раз в:")
  local x = 130
  for _, m in ipairs({ 15, 30, 60 }) do
    local b = UI.Button(f, m .. L" мин", 60, 20, function() S.autoScanMin = m; f.refresh(); updateHeader() end)
    b:SetPoint("TOPLEFT", x, y); b.min = m; x = x + 64
    f["m" .. m] = b
  end
  y = y - 32
  local l2 = UI.Font(f, 11); l2:SetPoint("TOPLEFT", 6, y - 4); l2:SetText(L"Порог скачка цены, %:")
  local e = CreateFrame("EditBox", nil, f, "InputBoxTemplate"); e:SetSize(50, 20); e:SetPoint("TOPLEFT", 160, y); e:SetAutoFocus(false); e:SetNumeric(true)
  e:SetScript("OnShow", function(self) self:SetText(S.alertPct) end)
  e:SetScript("OnTextChanged", function(self, user) if user then local v = tonumber(self:GetText()); if v and v > 0 then S.alertPct = v end end end)
  y = y - 34
  -- язык
  local l3 = UI.Font(f, 11); l3:SetPoint("TOPLEFT", 6, y - 4); l3:SetText(L"Язык / Language:")
  f.langBtns = {}
  local lx = 130
  for _, o in ipairs({ { nil, L"авто" }, { "ru", "Русский" }, { "en", "English" } }) do
    local b = UI.Button(f, o[2], 72, 20, function() S.lang = o[1]; f.refresh(); f.langNote:Show(); f.reload:Show() end)
    b:SetPoint("TOPLEFT", lx, y); b.lang = o[1] or "auto"; lx = lx + 76
    f.langBtns[#f.langBtns + 1] = b
  end
  y = y - 26
  f.langNote = UI.Font(f, 10, UI.GOLD); f.langNote:SetPoint("TOPLEFT", 6, y - 4); f.langNote:SetText(L"Язык меняется после перезагрузки интерфейса."); f.langNote:Hide()
  f.reload = UI.Button(f, L"Перезагрузить интерфейс", 170, 20, function() if ReloadUI then ReloadUI() end end, true)
  f.reload:SetPoint("TOPRIGHT", -2, y); f.reload:Hide()
  y = y - 30
  local note = UI.Font(f, 10, UI.DIM); note:SetPoint("TOPLEFT", 6, y); note:SetPoint("RIGHT", -6, 0); note:SetWordWrap(true)
  note:SetText(L"Сервер разрешает полный снимок аукциона не чаще раза в 15 минут. Это те же данные Blizzard, что и в API, только свежее.\nAlt+клик по предмету - отметить или снять отметку.")
  local function hl(b, on) b:SetGold(on) end
  f.refresh = function()
    for _, m in ipairs({ 15, 30, 60 }) do hl(f["m" .. m], S.autoScanMin == m) end
    for _, b in ipairs(f.langBtns) do hl(b, (S.lang or "auto") == b.lang) end
  end
end

local BUILDERS = { pageMarked, pageCraft, pageBuy, pageSell, pageChart, pageSettings }
local NAMES = { "Отмеченные", "Крафт", "Купить", "Продать", "График", "Настройки" }

function ns.BuildAHPanel()
  local h = AuctionHouseFrame or AuctionFrame
  if not h or panel then return end
  panel = CreateFrame("Frame", "WolfichMarketAHPanel", h)
  panel:SetWidth(440)
  panel:SetPoint("TOPLEFT", h, "TOPRIGHT", 2, 0); panel:SetPoint("BOTTOMLEFT", h, "BOTTOMRIGHT", 2, 0)
  panel:EnableMouse(true)
  UI.Skin(panel, { theme = "ah" })
  UI.Title(panel, "WolfichMarket")
  UI.Close(panel, function() panel:Hide() end)
  header()
  -- вкладки в два ряда по три
  tabs = {}
  for i, n in ipairs(NAMES) do
    local b = UI.Button(panel, L(n), 128, 24, function() tabs.select(i) end)
    b:SetPoint("TOPLEFT", 20 + ((i - 1) % 3) * 132, i <= 3 and -88 or -114)
    tabs[i] = b
  end
  for i, build in ipairs(BUILDERS) do
    local f = CreateFrame("Frame", nil, panel)
    f:SetPoint("TOPLEFT", 20, -146); f:SetPoint("BOTTOMRIGHT", -24, 16)
    build(f); f:Hide()
    pages[i] = f
  end
  function tabs.select(i)
    for k, b in ipairs(tabs) do
      b:SetGold(k == i)
      pages[k]:SetShown(k == i)
    end
    tabs.current = i
    ns.DB.settings.ahTab = i
    if pages[i].refresh then pages[i].refresh() end
  end
  -- кнопка-лапа на окне аукциона: показать/скрыть
  local tg = UI.Icon(h, "skin\\ai-paw", 24, L"WolfichMarket: показать/скрыть панель", function() panel:SetShown(not panel:IsShown()) end)
  tg:SetPoint("RIGHT", h, "TOPRIGHT", -36, -16); tg:SetFrameStrata("HIGH")
  ns.DB.settings.ahPanelHidden = nil -- старый флаг «скрыта навсегда» больше не используется
  panel:Show()
  tabs.select(ns.DB.settings.ahTab or 1)
  ns.AHSelectTab = function(i) tabs.select(i) end
  ns._ahPages = pages
  updateHeader()
  if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(1, function() if panel:IsVisible() then updateHeader() end end) end
end

local function refreshCurrent() if panel and tabs and tabs.current and pages[tabs.current]:IsShown() then pages[tabs.current].refresh() end end
ns.Listen("SCAN_STATE", updateHeader)
ns.Listen("PRICES", refreshCurrent)
ns.Listen("MARKS", refreshCurrent)
ns.Listen("RECIPES", refreshCurrent)
ns.Listen("NAMES", refreshCurrent)
