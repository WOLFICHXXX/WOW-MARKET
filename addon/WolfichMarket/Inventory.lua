-- WolfichMarket: банк и сумки каждого персонажа - материалы «из запаса» для крафта
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

-- ---------- сколько предмета у персонажа: в сумках и в банке ----------
local function itemCount(id, withBank)
  return (C_Item and C_Item.GetItemCount and safe(C_Item.GetItemCount, id, withBank)) or (GetItemCount and safe(GetItemCount, id, withBank)) or nil
end
function ns.HaveSplit(id, charKey)
  charKey = charKey or ns.charKey
  local c = ns.DB.chars[charKey] or {}
  local bags, bank = (c.bags or {})[id] or 0, (c.bank or {})[id] or 0
  if charKey == ns.charKey then
    local b = itemCount(id, false)
    local all = itemCount(id, true)
    if b then bags = b end
    if all and b and all - b > bank then bank = all - b end
  end
  return bags, bank
end
-- подпись «сумки N / банк M» для строк со своими материалами
function ns.HaveText(id, charKey, need)
  local bags, bank = ns.HaveSplit(id, charKey)
  local col = need and (bags + bank >= need and "|cff78d98a" or "|cffffb060") or "|cffcccccc"
  return col .. L"сумки" .. " " .. bags .. " / " .. L"банк" .. " " .. bank .. "|r", bags, bank
end
function ns.HaveCount(id) local a, b = ns.HaveSplit(id); return a + b end

-- ---------- план закупки: рецепты × порции → что докупить ----------
function ns.Plans() ns.DB.plans = ns.DB.plans or {}; return ns.DB.plans end
function ns.AddPlan(rec, charKey, prof, n)
  if not rec then return end
  n = math.max(1, math.floor(n or 1))
  local plans = ns.Plans()
  local reag = {}
  for _, r in ipairs(rec.reag or {}) do reag[#reag + 1] = { r[1], r[2] } end
  for _, p in ipairs(plans) do
    if p.id == rec.id and p.ck == charKey then p.n = n; p.reag = reag; p.t = time(); p.qmin, p.qmax = rec.qmin, rec.qmax; ns.say(string.format(L"план обновлён: %s ×%d", rec.name, n)); ns.Fire("PLAN") return end
  end
  plans[#plans + 1] = { id = rec.id, name = rec.name, out = rec.out, n = n, ck = charKey, prof = prof, reag = reag, t = time(), qmin = rec.qmin, qmax = rec.qmax }
  ns.say(string.format(L"добавлено в план: %s ×%d - список покупок во вкладке «План» у аукциониста.", rec.name, n))
  ns.Fire("PLAN")
end
-- сколько раз скрафтить рецепт плана (поле количества у аукциониста)
function ns.SetPlanCount(i, n)
  local p = ns.Plans()[i]
  n = math.max(1, math.min(999, math.floor(tonumber(n) or 1)))
  if p and p.n ~= n then p.n = n; p.t = time(); ns.Fire("PLAN") end
end
function ns.RemovePlan(i) local plans = ns.Plans(); if plans[i] then table.remove(plans, i); ns.Fire("PLAN") end end
function ns.ClearPlans() wipe(ns.Plans()); ns.Fire("PLAN") end
-- сколько предмета есть у текущего персонажа: сумки + банк (живые данные игры или последняя запись банка)
-- раздельно: сколько в сумках и сколько в банке. Текущий персонаж - живые данные игры, другие - последняя запись
-- итог плана: { {id, need, have, buy, unit}, ... } — сначала то, что нужно докупить (по сумме)
function ns.PlanNeeds()
  local need, order = {}, {}
  for _, p in ipairs(ns.Plans()) do
    for _, r in ipairs(p.reag or {}) do
      if not need[r[1]] then need[r[1]] = 0; order[#order + 1] = r[1] end
      need[r[1]] = need[r[1]] + r[2] * (p.n or 1)
    end
  end
  local out, total = {}, 0
  local useStock = ns.DB.settings.planUseStock ~= false -- «учитывать свои материалы» во вкладке «План»
  for _, id in ipairs(order) do
    local bags, bank = ns.HaveSplit(id)
    local have = useStock and (bags + bank) or 0
    local buy = math.max(0, need[id] - have)
    local unit = ns.AHPrice(id) or ns.DB.vendor[id]
    if unit and buy > 0 then total = total + unit * buy end
    out[#out + 1] = { id = id, need = need[id], have = have, bags = bags, bank = bank, buy = buy, unit = unit }
  end
  table.sort(out, function(a, b)
    if (a.buy > 0) ~= (b.buy > 0) then return a.buy > 0 end
    local x, y = (a.unit or 0) * a.buy, (b.unit or 0) * b.buy
    if x == y then return ns.itemName(a.id) < ns.itemName(b.id) end
    return x > y
  end)
  return out, total
end
-- прибыль плана: по каждому рецепту и всего. Материалы - по рыночной цене (дешевле: торговец или аукцион),
-- выручка - цена результата на аукционе минус 5%
function ns.PlanProfit()
  local rows, tot = {}, { revenue = 0, cost = 0, missing = false }
  for i, p in ipairs(ns.Plans()) do
    local r = { revenue = nil, cost = 0, missing = false }
    for _, m in ipairs(p.reag or {}) do
      local u = ns.CostPrice(m[1])
      if u then r.cost = r.cost + u * m[2] * (p.n or 1) else r.missing = true end
    end
    local sell = p.out and ns.AHPrice(p.out)
    if sell then
      local q = ((p.qmin or 1) + (p.qmax or 1)) / 2
      r.revenue = sell * q * (p.n or 1) * (1 - ns.Cut())
    end
    if r.revenue and not r.missing then r.profit = r.revenue - r.cost end
    rows[i] = r
    if r.revenue then tot.revenue = tot.revenue + r.revenue else tot.missing = true end
    tot.cost = tot.cost + r.cost
    if r.missing then tot.missing = true end
  end
  tot.profit = tot.revenue - tot.cost
  return rows, tot
end
