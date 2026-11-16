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
  local s = (h:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
  local total = (h:GetWidth() or 0) * s + 2 + (p:GetWidth() or 0) * s
  local left, top = h:GetLeft(), h:GetTop()
  if not left or not top or sw <= 0 then return end
  if left * s + total <= sw - 8 then return end
  local x = math.max(8, (sw - total) / 2) / s
  pcall(h.ClearAllPoints, h)
  pcall(h.SetPoint, h, "TOPLEFT", UIParent, "TOPLEFT", x, (top - (UIParent:GetTop() or top * s) / s))
  if ns.UpdateAHBags then ns.UpdateAHBags() end
end

-- ---------- своя сумка ----------
local bagf
local SLOT, GAP = 34, 3
local QUALITY = ITEM_QUALITY_COLORS
local function build()
  if bagf then return bagf end
  local h = AuctionHouseFrame or AuctionFrame
  bagf = CreateFrame("Frame", "WolfichMarketAHBags", h)
  bagf:SetFrameStrata("HIGH")
  UI.Skin(bagf, { theme = "ah", frame = 0.42 })
  local t = UI.Font(bagf, 13, UI.GOLD); UI.SetFont(t, UI.TITLE_FONT, 15, ""); t:SetPoint("TOPLEFT", 26, -12); t:SetText(L"Сумки")
  bagf.money = UI.Font(bagf, 11); bagf.money:SetPoint("LEFT", t, "RIGHT", 14, 0)
  bagf.value = UI.Font(bagf, 11, UI.DIM); bagf.value:SetPoint("LEFT", bagf.money, "RIGHT", 16, 0)
  local hint = UI.Font(bagf, 10, UI.DIM); hint:SetPoint("TOPRIGHT", -44, -14); hint:SetJustifyH("RIGHT")
  hint:SetText(L"клик - выставить в панели аддона, ПКМ - как в игре")
  bagf.btns = {}
  return bagf
end
local function slotButton(i)
  local b = bagf.btns[i]
  if b then return b end
  b = CreateFrame("Button", nil, bagf)
  b:SetSize(SLOT, SLOT)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp"); b:RegisterForDrag("LeftButton")
  local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.03, 0.03, 0.04, 0.85)
  b.border = b:CreateTexture(nil, "BORDER"); b.border:SetPoint("TOPLEFT", -1, 1); b.border:SetPoint("BOTTOMRIGHT", 1, -1); b.border:SetColorTexture(0.42, 0.33, 0.17, 0.9)
  local inner = b:CreateTexture(nil, "BORDER", nil, 1); inner:SetAllPoints(); inner:SetColorTexture(0.05, 0.05, 0.06, 1)
  b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetPoint("TOPLEFT", 2, -2); b.icon:SetPoint("BOTTOMRIGHT", -2, 2); b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
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
    if btn == "RightButton" then safe(C_Container.UseContainerItem, self.bag, self.slot) return end
    if self.id and ns.SellSelect then ns.SellSelect(self.id) end
  end)
  bagf.btns[i] = b
  return b
end

function ns.UpdateAHBags()
  local h = AuctionHouseFrame or AuctionFrame
  if not ns.DB or ns.DB.settings.ahBags == false or not h or not h:IsShown() or not C_Container then if bagf then bagf:Hide() end return end
  build()
  local items = {}
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    for slot = 1, (safe(C_Container.GetContainerNumSlots, bag) or 0) do items[#items + 1] = { bag, slot } end
  end
  local W = math.max(400, h:GetWidth() or 800)
  local cols = math.max(8, math.floor((W - 44 + GAP) / (SLOT + GAP)))
  local rows = math.ceil(#items / cols)
  bagf:SetSize(W, 52 + rows * (SLOT + GAP) + 26)
  bagf:ClearAllPoints(); bagf:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -2)
  local x0 = math.floor((W - cols * (SLOT + GAP) + GAP) / 2)
  local value = 0
  for i, it in ipairs(items) do
    local b = slotButton(i)
    b.bag, b.slot = it[1], it[2]
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", x0 + ((i - 1) % cols) * (SLOT + GAP), -40 - math.floor((i - 1) / cols) * (SLOT + GAP))
    local info = safe(C_Container.GetContainerItemInfo, it[1], it[2])
    b.id, b.link = info and info.itemID, info and info.hyperlink
    if b.id then
      b.icon:SetTexture(info.iconFileID or ns.itemIcon(b.id)); b.icon:Show(); b.icon:SetDesaturated(info.isLocked and true or false)
      b.count:SetText((info.stackCount or 1) > 1 and info.stackCount or "")
      local q = info.quality and QUALITY and QUALITY[info.quality]
      if q and info.quality >= 2 then b.border:SetColorTexture(q.r, q.g, q.b, 0.95) else b.border:SetColorTexture(0.42, 0.33, 0.17, 0.9) end
      local where = ns.DB.settings.bagGlow ~= false and ns.SellWhere(b.id, info.isBound) or nil
      if where == "ah" or where == "vendor" then b.badge:SetTexture(ns.MEDIA .. (where == "ah" and "badge-ah" or "badge-vendor")); b.badge:Show() else b.badge:Hide() end
      local p = not info.isBound and ns.AHPrice(b.id)
      if p then value = value + p * (info.stackCount or 1) end
    else
      b.icon:Hide(); b.count:SetText(""); b.badge:Hide(); b.border:SetColorTexture(0.30, 0.24, 0.13, 0.7)
    end
    b:Show()
  end
  for i = #items + 1, #bagf.btns do bagf.btns[i]:Hide() end
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
