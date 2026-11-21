-- WolfichMarket: значки в сумках - молоток (выгоднее на аукцион) и мешочек с монетой (торговцу); строка в подсказке
local _, ns = ...
local safe = ns.safe

-- куда выгоднее продать предмет: "vendor", "ah" или nil
function ns.SellWhere(id, bound)
  if not id then return nil end
  local vendor = ns.VendorSell(id)
  if bound then return vendor and "vendor" or nil end
  local ah = ns.AHPrice(id)
  local net = ah and ah * (1 - ns.Cut())
  if net and (not vendor or net > vendor) then return "ah", net, vendor end
  if vendor then return "vendor", net, vendor end
  return nil
end

-- Кнопки предметов в сумках игры аддон НЕ трогает: никаких своих полей, текстур и вызовов их Lua-методов
-- (иначе код игры «пачкается» и предметы с действием по ПКМ - камень, спальник - блокируются).
-- Только вызовы движка (GetChildren, GetID, IsShown) и свои рамки поверх, ссылки на них - в своей таблице.
local BADGE = { ah = "Interface\\AddOns\\WolfichMarket\\media\\badge-ah", vendor = "Interface\\AddOns\\WolfichMarket\\media\\badge-vendor" }
local badges = setmetatable({}, { __mode = "k" }) -- кнопка игры -> наша рамка со значком
ns._bagBadge = function(btn) return badges[btn] end -- для автотестов

local function bagFrames()
  local out = { ContainerFrameCombinedBags }
  for i = 1, 13 do out[#out + 1] = _G["ContainerFrame" .. i] end
  return out
end
ns.BagFrames = bagFrames

-- все показанные кнопки предметов: fn(btn, bag, slot)
function ns.EachBagButton(fn, all)
  for _, f in ipairs(bagFrames()) do
    if f and f.GetChildren and (all or f:IsShown()) then
      local fbag = f:GetID()
      for _, btn in ipairs({ f:GetChildren() }) do
        if btn.GetObjectType and btn:GetObjectType() == "Button" and btn:GetID() > 0 and (all or btn:IsShown()) then
          local bag = rawget(btn, "bagID") or fbag
          if f ~= ContainerFrameCombinedBags or rawget(btn, "bagID") then fn(btn, bag, btn:GetID()) end
        end
      end
    end
  end
end

local function glow(btn, where)
  local g = badges[btn]
  if not where then if g then g:Hide() end return end
  if not g then
    g = CreateFrame("Frame", nil, btn)
    g:SetFrameLevel((btn:GetFrameLevel() or 1) + 6)
    g.tex = g:CreateTexture(nil, "OVERLAY")
    g.tex:SetAllPoints()
    g:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 3, 3)
    badges[btn] = g
  end
  local w = math.floor((btn:GetWidth() or 37) * 0.48 + 0.5)
  g:SetSize(w, w)
  g.tex:SetTexture(BADGE[where])
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
  -- спрятанные значки (кнопки ушли в другой слот или сумка закрыта) - сначала скрыть
  for btn, g in pairs(badges) do if not btn:IsVisible() then g:Hide() end end
  ns.EachBagButton(fn)
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
  for _, f in ipairs(bagFrames()) do
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
