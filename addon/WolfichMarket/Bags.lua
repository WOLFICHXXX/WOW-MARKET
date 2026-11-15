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

-- ===== сортировка: после обычной сортировки сумок - выгодное на аукцион наверх, торговцу вниз =====
-- Порядок внутри групп остаётся как после сортировки игры. Переставляем по одному предмету, ждём, пока игра его «отпустит».
local sorting
local function bagList()
  local out = {}
  local last = NUM_BAG_SLOTS or 4
  for b = 0, last do
    local n = C_Container and safe(C_Container.GetContainerNumSlots, b) or 0
    -- только обычные сумки (сумки для профессий и реагентов не трогаем)
    local fam = 0
    if b ~= 0 and C_Container then fam = select(2, safe(C_Container.GetContainerNumFreeSlots, b)) or 0 end
    if n and n > 0 and (fam == 0 or fam == nil) then out[#out + 1] = { b, n } end
  end
  return out
end
-- порядок ячеек так, как их видно на экране: сверху вниз, слева направо
local function visualOrder()
  local pos, any = {}, false
  eachButton(function(btn, bag, slot)
    local t, l = btn.GetTop and btn:GetTop(), btn.GetLeft and btn:GetLeft()
    if bag and slot and t and l then pos[bag .. ":" .. slot] = { t, l }; any = true end
  end)
  return any and pos or nil
end
local function info(b, s) return C_Container and safe(C_Container.GetContainerItemInfo, b, s) end

function ns.SortBagsByValue(quiet)
  if sorting then return end
  if InCombatLockdown and InCombatLockdown() then return end
  if GetCursorInfo and GetCursorInfo() then return end
  local pos = visualOrder()
  local slots = {}
  for _, bn in ipairs(bagList()) do for s = 1, bn[2] do slots[#slots + 1] = { b = bn[1], s = s, k = #slots } end end
  if pos then
    table.sort(slots, function(a, c)
      local pa, pc = pos[a.b .. ":" .. a.s], pos[c.b .. ":" .. c.s]
      if pa and pc then if math.abs(pa[1] - pc[1]) > 4 then return pa[1] > pc[1] end if pa[2] ~= pc[2] then return pa[2] < pc[2] end end
      if (pa ~= nil) ~= (pc ~= nil) then return pa ~= nil end
      return a.k < c.k
    end)
  end
  -- занятые ячейки и предметы в них
  local filled, items = {}, {}
  for i, sl in ipairs(slots) do
    local it = info(sl.b, sl.s)
    if it and it.itemID then
      local where = ns.SellWhere(it.itemID, it.isBound)
      filled[#filled + 1] = sl
      items[#items + 1] = { id = it.itemID, g = where == "ah" and 1 or where == "vendor" and 3 or 2, i = #items }
    end
  end
  local want = {}
  for i, it in ipairs(items) do want[i] = it end
  table.sort(want, function(a, c) if a.g ~= c.g then return a.g < c.g end return a.i < c.i end)
  -- план перестановок по номерам предметов (одинаковые предметы взаимозаменяемы)
  local cur = {}
  for i, it in ipairs(items) do cur[i] = it.id end
  local moves = {}
  for i = 1, #want do
    if cur[i] ~= want[i].id then
      for j = i + 1, #cur do
        if cur[j] == want[i].id then
          moves[#moves + 1] = { filled[j], filled[i], want[i].id }
          cur[i], cur[j] = cur[j], cur[i]
          break
        end
      end
    end
  end
  if #moves == 0 then return 0 end
  sorting = { moves = moves, n = 0, tries = 0 }
  local function step()
    if not sorting then return end
    if (InCombatLockdown and InCombatLockdown()) or #sorting.moves == 0 then
      local done = sorting.n; sorting = nil; ns.UpdateBagGlow()
      if not quiet then ns.say(L"сумки: аукцион наверху, торговцу внизу (перестановок: " .. done .. ")") end
      return
    end
    local m = sorting.moves[1]
    local a, c = info(m[1].b, m[1].s), info(m[2].b, m[2].s)
    if (a and a.isLocked) or (c and c.isLocked) or (GetCursorInfo and GetCursorInfo()) then
      sorting.tries = sorting.tries + 1
      if sorting.tries > 60 then sorting = nil; return end -- что-то держит предметы - бросаем
      ns.After(0.1, step) return
    end
    sorting.tries = 0
    if not a or a.itemID ~= m[3] then sorting = nil; return end -- сумки изменились во время перестановки - стоп
    table.remove(sorting.moves, 1)
    C_Container.PickupContainerItem(m[1].b, m[1].s)
    C_Container.PickupContainerItem(m[2].b, m[2].s)
    if GetCursorInfo and GetCursorInfo() and ClearCursor then ClearCursor() end
    sorting.n = sorting.n + 1
    ns.After(0.15, step)
  end
  step()
  return #moves
end
function ns.BagSortBusy() return sorting ~= nil end

-- после сортировки игры ждём, пока сумки успокоятся, и досортировываем
local sortWait
local function afterGameSort()
  if not ns.DB or ns.DB.settings.sortByValue == false then return end
  local quietFor, total = 0, 0
  if sortWait then sortWait.stop = true end
  local w = {}; sortWait = w
  local lastUpd = GetTime()
  w.mark = function() lastUpd = GetTime() end
  local function tick()
    if w.stop then return end
    total = total + 0.25
    if GetTime() - lastUpd >= 1.2 or total > 12 then sortWait = nil; ns.SortBagsByValue() return end
    ns.After(0.25, tick)
  end
  ns.After(0.5, tick)
end
ns.On("BAG_UPDATE_DELAYED", function() if sortWait and sortWait.mark then sortWait.mark() end end)
if C_Container and C_Container.SortBags then hooksecurefunc(C_Container, "SortBags", afterGameSort) end
if SortBags then hooksecurefunc("SortBags", afterGameSort) end
