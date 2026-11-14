-- WolfichMarket: банк и сумки каждого персонажа (что лежит и сколько стоит), материалы «из запаса» для крафта
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
