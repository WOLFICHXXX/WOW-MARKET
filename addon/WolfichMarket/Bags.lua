-- WolfichMarket: куда выгоднее продать предмет - на аукцион или торговцу (строка в подсказке предмета)
local _, ns = ...

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
