-- WolfichMarket: значки в сумках — мешочек с монетой, если выгоднее продать торговцу, молоток — если на аукцион
local _, ns = ...
local L = ns.L
local safe = ns.safe


-- куда выгоднее продать предмет: "vendor", "ah" или nil
function ns.SellWhere(id, bound)
  if not id then return nil end
  local vendor = ns.VendorSell(id)
  if bound then return vendor and "vendor" or nil end
  local ah = ns.AHPrice(id)
  local net = ah and ah * (1 - ns.AH_CUT)
  if net and (not vendor or net > vendor) then return "ah", net, vendor end
  if vendor then return "vendor", net, vendor end
  return nil
end

-- значок в правом верхнем углу предмета: молоток - на аукцион, мешочек с монетой - торговцу
local BADGE = { ah = "Interface\\AddOns\\WolfichMarket\\media\\badge-ah", vendor = "Interface\\AddOns\\WolfichMarket\\media\\badge-vendor" }
local function glow(btn, where)
  local g = btn.wmSellBadge
  if btn.wmSellGlow then btn.wmSellGlow:Hide() end -- старая рамка (до 2.26)
  if not where then if g then g:Hide() end return end
  if not g then
    g = btn:CreateTexture(nil, "OVERLAY", nil, 7)
    g:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 3, 3)
    btn.wmSellBadge = g
  end
  local w = math.floor((btn:GetWidth() or 37) * 0.48 + 0.5)
  g:SetSize(w, w)
  g:SetTexture(BADGE[where])
  g:Show()
end

local function paint(btn, bag, slot)
  if not btn then return end
  if not ns.DB or not ns.DB.settings.bagGlow or not bag or not slot then glow(btn, nil) return end
  local info = C_Container and safe(C_Container.GetContainerItemInfo, bag, slot)
  local id = info and info.itemID
  if not id then glow(btn, nil) return end
  local where = ns.SellWhere(id, info.isBound)
  glow(btn, (where == "ah" or where == "vendor") and where or nil)
end

local function eachButton(fn)
  -- современные сумки (в том числе объединённый рюкзак)
  local frames = { ContainerFrameCombinedBags }
  for i = 1, 13 do frames[#frames + 1] = _G["ContainerFrame" .. i] end
  local any = false
  for _, f in ipairs(frames) do
    if f and f:IsShown() and f.EnumerateValidItems then
      any = true
      for _, btn in f:EnumerateValidItems() do
        local bag = btn.GetBagID and btn:GetBagID() or (btn:GetParent() and btn:GetParent():GetID())
        fn(btn, bag, btn:GetID())
      end
    end
  end
  if any then return end
  -- старый вид сумок
  for i = 1, 13 do
    local f = _G["ContainerFrame" .. i]
    if f and f:IsShown() then
      local bag = f:GetID()
      for j = 1, 40 do local btn = _G["ContainerFrame" .. i .. "Item" .. j]; if btn then fn(btn, bag, btn:GetID()) end end
    end
  end
end

local pending = false
function ns.UpdateBagGlow()
  if pending then return end
  pending = true
  ns.After(0.2, function() pending = false; eachButton(paint) end)
end

-- обновления: открытие сумок, изменения в сумках, новые цены
local hookedFrames = {}
local function hookFrames()
  local frames = { ContainerFrameCombinedBags }
  for i = 1, 13 do frames[#frames + 1] = _G["ContainerFrame" .. i] end
  for _, f in ipairs(frames) do
    if f and not hookedFrames[f] then
      hookedFrames[f] = true
      f:HookScript("OnShow", ns.UpdateBagGlow)
      if f.UpdateItems then pcall(hooksecurefunc, f, "UpdateItems", ns.UpdateBagGlow) end
    end
  end
end
ns.Listen("LOGIN", function() hookFrames(); ns.UpdateBagGlow() end)
ns.On("BAG_UPDATE_DELAYED", function() hookFrames(); ns.UpdateBagGlow() end)
ns.On("BAG_OPEN", ns.UpdateBagGlow)
ns.Listen("PRICES", ns.UpdateBagGlow)
