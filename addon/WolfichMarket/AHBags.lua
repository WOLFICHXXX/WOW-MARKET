-- WolfichMarket: у аукциониста - окно аукциона и панель аддона рядом, на экране целиком;
-- вместо стандартных сумок - своя сумка в оформлении аддона, под окном аукциона.
local _, ns = ...
local L = ns.L
local UI, safe = ns.UI, ns.safe

-- ---------- расположение: окно аукциона сдвигается влево, чтобы панель справа влезла ----------
function ns.PlaceAH()
  local h = AuctionHouseFrame or AuctionFrame
  local p = WolfichMarketAHPanel
  if not h or not h:IsShown() or not p or not p:IsShown() then return end
  if ns.DB.settings.ahPlace == false then return end
  local sw = UIParent:GetWidth() or 0
  if sw <= 0 then return end
  local s = (h:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
  local total = (h:GetWidth() or 0) * s + 2 + (p:GetWidth() or 0) * s
  -- по ширине - по центру, по высоте - почти у верхнего края экрана (место снизу - для сумки)
  local x = math.max(8, (sw - total) / 2) / s
  pcall(h.ClearAllPoints, h)
  pcall(h.SetPoint, h, "TOPLEFT", UIParent, "TOPLEFT", x, -12 / s)
  if ns.UpdateAHBags then ns.UpdateAHBags() end
end

-- ---------- своя сумка ----------
local bagf
local SLOT, GAP = 36, 3
local QUALITY = ITEM_QUALITY_COLORS
local function build()
  if bagf then return bagf end
  local h = AuctionHouseFrame or AuctionFrame
  bagf = CreateFrame("Frame", "WolfichMarketAHBags", h)
  bagf:SetFrameStrata("HIGH")
  UI.Skin(bagf, { theme = "ah", frame = 0.42 })
  local t = UI.Font(bagf, 13, UI.GOLD); UI.SetFont(t, UI.TITLE_FONT, 15, ""); t:SetPoint("TOPLEFT", 30, -24); t:SetText(L"Сумки")
  bagf.money = UI.Font(bagf, 11); bagf.money:SetPoint("LEFT", t, "RIGHT", 14, 0)
  bagf.value = UI.Font(bagf, 11, UI.DIM); bagf.value:SetPoint("LEFT", bagf.money, "RIGHT", 16, 0)
  -- «Упорядочить»: сортировка игры, затем аддон кладёт выгодное на аукцион наверх, торговцу - вниз
  bagf.sort = UI.Button(bagf, L"Упорядочить", 110, 20, function()
    if C_Container and C_Container.SortBags then pcall(C_Container.SortBags) elseif SortBags then pcall(SortBags) end
  end)
  bagf.sort:SetPoint("TOPRIGHT", -52, -20)
  local hint = UI.Font(bagf, 10, UI.DIM); hint:SetPoint("RIGHT", bagf.sort, "LEFT", -10, 0); hint:SetJustifyH("RIGHT")
  hint:SetText(L"клик - выставить в панели аддона, ПКМ - на аукционе игры")
  bagf.btns = {}
  -- прокрутка колёсиком, если все ячейки не помещаются до низа экрана
  bagf.offset = 0
  bagf:EnableMouseWheel(true)
  bagf:SetScript("OnMouseWheel", function(self, d)
    self.offset = math.max(0, math.min(self.maxOffset or 0, self.offset - d)); ns.UpdateAHBags()
  end)
  bagf.bar = bagf:CreateTexture(nil, "OVERLAY"); bagf.bar:SetWidth(4); bagf.bar:SetColorTexture(0.85, 0.66, 0.32, 0.9)
  bagf.track = bagf:CreateTexture(nil, "ARTWORK"); bagf.track:SetWidth(4); bagf.track:SetColorTexture(0, 0, 0, 0.5)
  return bagf
end
local function slotButton(i)
  local b = bagf.btns[i]
  if b then return b end
  b = CreateFrame("Button", nil, bagf)
  b:SetSize(SLOT, SLOT)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp"); b:RegisterForDrag("LeftButton")
  -- ячейка: скруглённая бронзовая рамка; у предмета хорошего качества рамка - цвета качества
  b.border = b:CreateTexture(nil, "BACKGROUND"); b.border:SetAllPoints(); UI.WinTex(b.border, "slot")
  b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetPoint("TOPLEFT", 4, -4); b.icon:SetPoint("BOTTOMRIGHT", -4, 4); b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.count = UI.Font(b, 10); b.count:SetPoint("BOTTOMRIGHT", -2, 2); b.count:SetJustifyH("RIGHT")
  b.badge = b:CreateTexture(nil, "OVERLAY"); b.badge:SetSize(15, 15); b.badge:SetPoint("TOPRIGHT", 3, 3)
  local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.85, 0.45, 0.18)
  b:SetScript("OnEnter", function(self)
    if not self.bag then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if GameTooltip.SetBagItem then pcall(GameTooltip.SetBagItem, GameTooltip, self.bag, self.slot) end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:SetScript("OnDragStart", function(self) if self.bag and C_Container then safe(C_Container.PickupContainerItem, self.bag, self.slot) end end)
  b:SetScript("OnReceiveDrag", function(self) if self.bag and C_Container then safe(C_Container.PickupContainerItem, self.bag, self.slot) end end)
  b:SetScript("OnClick", function(self, btn)
    if not self.bag then return end
    if GetCursorInfo and GetCursorInfo() then safe(C_Container.PickupContainerItem, self.bag, self.slot) return end
    if IsModifiedClick and IsModifiedClick() and self.link and HandleModifiedItemClick then HandleModifiedItemClick(self.link) return end
    if btn == "RightButton" then
      -- ПКМ - выставить на стандартном аукционе игры (как правый клик в сумке игры у аукциониста)
      local AH = AuctionHouseFrame
      local loc = ItemLocation and ItemLocation:CreateFromBagAndSlot(self.bag, self.slot)
      if AH and AH.SetPostItem and loc then
        local ok = pcall(AH.SetPostItem, AH, loc)
        if ok then return end
      end
      if AH and AH.SetDisplayMode and AuctionHouseFrameDisplayMode then
        -- запасной путь: вкладка «Продать» игры и предмет на курсор - его можно положить в ячейку
        local isC = loc and C_AuctionHouse and C_AuctionHouse.GetItemCommodityStatus and C_AuctionHouse.GetItemCommodityStatus(loc) == 2
        pcall(AH.SetDisplayMode, AH, isC and AuctionHouseFrameDisplayMode.CommoditiesSell or AuctionHouseFrameDisplayMode.ItemSell)
      end
      safe(C_Container.PickupContainerItem, self.bag, self.slot)
      return
    end
    if self.id and ns.SellSelect then ns.SellSelect(self.id) end
  end)
  bagf.btns[i] = b
  return b
end

function ns.UpdateAHBags()
  local h = AuctionHouseFrame or AuctionFrame
  if not ns.DB or ns.DB.settings.ahBags == false or not h or not h:IsShown() or not C_Container then if bagf then bagf:Hide() end return end
  build()
  -- все сумки, включая сумку реагентов (травы, руда)
  local items = {}
  for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
    for slot = 1, (safe(C_Container.GetContainerNumSlots, bag) or 0) do items[#items + 1] = { bag, slot } end
  end
  local W = math.max(400, h:GetWidth() or 800)
  local cols = math.max(8, math.floor((W - 60 + GAP) / (SLOT + GAP)))
  local rows = math.ceil(#items / cols)
  -- сколько рядов влезает до низа экрана; остальное - прокруткой
  local hb = h:GetBottom()
  local s = (h:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
  local avail = hb and (hb * s - 34 * s - 8) / s or 600
  local vis = math.max(2, math.min(rows, math.floor((avail - 92) / (SLOT + GAP))))
  bagf.maxOffset = math.max(0, rows - vis)
  bagf.offset = math.min(bagf.offset or 0, bagf.maxOffset)
  bagf:SetSize(W, 62 + vis * (SLOT + GAP) + 30)
  -- под вкладками окна аукциона (Купить / Продать / Аукционы ...), их не закрываем
  bagf:ClearAllPoints(); bagf:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -34)
  local x0 = math.floor((W - cols * (SLOT + GAP) + GAP) / 2)
  if bagf.maxOffset > 0 then
    local th = vis * (SLOT + GAP) - GAP
    bagf.track:ClearAllPoints(); bagf.track:SetPoint("TOPRIGHT", -(x0 - 10), -50); bagf.track:SetHeight(th); bagf.track:Show()
    local bh = math.max(16, th * vis / rows)
    bagf.bar:ClearAllPoints(); bagf.bar:SetPoint("TOP", bagf.track, "TOP", 0, -(th - bh) * bagf.offset / bagf.maxOffset); bagf.bar:SetHeight(bh); bagf.bar:Show()
  else bagf.track:Hide(); bagf.bar:Hide() end
  local first = bagf.offset * cols
  local value = 0
  -- стоимость - по всем сумкам, ячейки - только видимые ряды
  for _, it in ipairs(items) do
    local info = safe(C_Container.GetContainerItemInfo, it[1], it[2])
    local p = info and info.itemID and not info.isBound and ns.AHPrice(info.itemID)
    if p then value = value + p * (info.stackCount or 1) end
  end
  local shown = 0
  for i = first + 1, math.min(#items, first + vis * cols) do
    local it = items[i]
    shown = shown + 1
    local b = slotButton(shown)
    b.bag, b.slot = it[1], it[2]
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", x0 + ((shown - 1) % cols) * (SLOT + GAP), -50 - math.floor((shown - 1) / cols) * (SLOT + GAP))
    local info = safe(C_Container.GetContainerItemInfo, it[1], it[2])
    b.id, b.link = info and info.itemID, info and info.hyperlink
    if b.id then
      b.icon:SetTexture(info.iconFileID or ns.itemIcon(b.id)); b.icon:Show(); b.icon:SetDesaturated(info.isLocked and true or false)
      b.count:SetText((info.stackCount or 1) > 1 and info.stackCount or "")
      local q = info.quality and QUALITY and QUALITY[info.quality]
      if q and info.quality >= 2 then b.border:SetVertexColor(q.r * 1.2, q.g * 1.2, q.b * 1.2) else b.border:SetVertexColor(1, 1, 1) end
      local where = ns.DB.settings.bagGlow ~= false and ns.SellWhere(b.id, info.isBound) or nil
      if where == "ah" or where == "vendor" then b.badge:SetTexture(ns.MEDIA .. (where == "ah" and "badge-ah" or "badge-vendor")); b.badge:Show() else b.badge:Hide() end
    else
      b.icon:Hide(); b.count:SetText(""); b.badge:Hide(); b.border:SetVertexColor(0.7, 0.62, 0.5)
    end
    b:Show()
  end
  for i = shown + 1, #bagf.btns do bagf.btns[i]:Hide() end
  bagf.money:SetText(ns.money(GetMoney and GetMoney() or 0, true))
  bagf.value:SetText(L"по аукциону" .. ": " .. ns.money(value, true))
  bagf:Show()
end

-- при открытии аукциона игра открывает свои сумки - закрываем их, показываем свою
local function onShow()
  if ns.DB.settings.ahBags == false then return end
  ns.After(0.05, function()
    if CloseAllBags then pcall(CloseAllBags) end
    ns.UpdateAHBags()
    if ns.PlaceAH then ns.PlaceAH() end
  end)
end
ns.On("AUCTION_HOUSE_SHOW", onShow)
ns.On("AUCTION_HOUSE_CLOSED", function() if bagf then bagf:Hide() end end)
local queued = false
local function later()
  if queued or not bagf or not bagf:IsShown() then return end
  queued = true
  ns.After(0.2, function() queued = false; ns.UpdateAHBags() end)
end
ns.On("BAG_UPDATE_DELAYED", later)
ns.On("ITEM_LOCK_CHANGED", later)
ns.On("PLAYER_MONEY", later)
ns.Listen("PRICES", later)
