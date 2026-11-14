-- WolfichMarket: подсветка в сумках — жёлтым, если выгоднее продать торговцу, зелёным — если на аукцион
local _, ns = ...
local L = ns.L
local safe = ns.safe

local YELLOW = { 1, 0.85, 0.1 }
local GREEN = { 0.25, 1, 0.3 }

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

local function glow(btn, color)
  local g = btn.wmSellGlow
  if not color then if g then g:Hide() end return end
  if not g then
    g = btn:CreateTexture(nil, "OVERLAY", nil, 7)
    g:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    g:SetBlendMode("ADD")
    g:SetPoint("CENTER")
    btn.wmSellGlow = g
  end
  local w = (btn:GetWidth() or 37) * 1.85
  g:SetSize(w, w)
  g:SetVertexColor(color[1], color[2], color[3], 1)
  g:Show()
end

local function paint(btn, bag, slot)
  if not btn then return end
  if not ns.DB or not ns.DB.settings.bagGlow or not bag or not slot then glow(btn, nil) return end
  local info = C_Container and safe(C_Container.GetContainerItemInfo, bag, slot)
  local id = info and info.itemID
  if not id then glow(btn, nil) return end
  local where = ns.SellWhere(id, info.isBound)
  glow(btn, where == "ah" and GREEN or where == "vendor" and YELLOW or nil)
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
