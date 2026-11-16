-- WolfichMarket: у торговца - автоматическая продажа хлама и починка снаряжения (настройки в главном окне)
local _, ns = ...
local L = ns.L
local safe = ns.safe

local function repair()
  if not ns.DB.settings.autoRepair or not CanMerchantRepair or not safe(CanMerchantRepair) then return end
  local cost, need = safe(GetRepairAllCost)
  if not need or not cost or cost <= 0 then return end
  local money = GetMoney and GetMoney() or 0
  if money < cost then ns.say(string.format(L"починка: не хватает денег (нужно %s)", ns.money(cost))) return end
  safe(RepairAllItems)
  ns.say(L"снаряжение починено" .. ": " .. ns.money(cost))
end

-- хлам (серые предметы с ценой у торговца): по несколько предметов за раз, чтобы игра успевала
local function sellJunk()
  if not ns.DB.settings.autoJunk or not C_Container then return end
  local list, total = {}, 0
  for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
    for slot = 1, (safe(C_Container.GetContainerNumSlots, bag) or 0) do
      local info = safe(C_Container.GetContainerItemInfo, bag, slot)
      if info and info.itemID and info.quality == 0 and not info.hasNoValue and not info.isLocked then
        local price = ns.VendorSell(info.itemID)
        if price then list[#list + 1] = { bag, slot }; total = total + price * (info.stackCount or 1) end
      end
    end
  end
  if #list == 0 then return end
  local i = 0
  local function step()
    if not (MerchantFrame and MerchantFrame:IsShown()) then return end
    for _ = 1, 8 do
      i = i + 1
      local it = list[i]
      if not it then ns.say(string.format(L"хлам продан: %d шт. - %s", #list, ns.money(total))) return end
      safe(C_Container.UseContainerItem, it[1], it[2])
    end
    ns.After(0.25, step)
  end
  step()
end

ns.On("MERCHANT_SHOW", function()
  if not ns.DB then return end
  ns.After(0.3, function() repair(); sellJunk() end)
end)
