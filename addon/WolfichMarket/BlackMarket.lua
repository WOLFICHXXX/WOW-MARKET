-- WolfichMarket: чёрный рынок - отдельно от обычного аукциона.
-- Когда открыто окно чёрного рынка, запоминаем его лоты (текущая ставка или минимальная, число ставок)
-- и показываем строкой «Чёрный рынок» в подсказке предмета. С ценами обычного аукциона не смешивается.
local _, ns = ...
local L = ns.L
local safe = ns.safe

local function store()
  local B = C_BlackMarket
  if not B or not B.GetNumItems or not B.GetItemInfoByIndex or not ns.realmKey then return end
  local n = safe(B.GetNumItems) or 0
  if n == 0 then return end
  local items = {}
  for i = 1, n do
    -- name, texture, quantity, itemType, usable, level, levelType, sellerName, minBid, minIncrement, currBid, youHaveHighBid, numBids, timeLeft, link, marketID
    local name, _, qty, _, _, _, _, _, minBid, _, curBid, _, numBids, timeLeft, link = safe(B.GetItemInfoByIndex, i)
    local id = link and ns.idFromLink(link)
    if id then
      local price = (curBid and curBid > 0) and curBid or minBid
      local old = items[id]
      if price and price > 0 and (not old or price < old.p) then
        items[id] = { p = price, min = minBid, bids = numBids or 0, left = timeLeft, q = qty or 1 }
      end
    end
  end
  ns.DB.bmah = ns.DB.bmah or {}
  ns.DB.bmah[ns.realmKey] = { t = time(), items = items }
  local cnt = 0; for _ in pairs(items) do cnt = cnt + 1 end
  ns.say(string.format(L"чёрный рынок: %d лотов запомнено - цены видны в подсказке предмета.", cnt))
  ns.Fire("BLACKMARKET")
end

local pendingStore = false
local function later() if pendingStore then return end; pendingStore = true; ns.After(0.5, function() pendingStore = false; store() end) end
ns.On("BLACK_MARKET_OPEN", function() if C_BlackMarket and C_BlackMarket.RequestItems then pcall(C_BlackMarket.RequestItems) end; later() end)
ns.On("BLACK_MARKET_ITEM_UPDATE", later)

-- лот чёрного рынка: { p = цена (ставка или минимальная), bids = ставок, q = кол-во }, время снимка
function ns.BlackMarketPrice(id)
  local d = ns.DB and ns.DB.bmah and ns.DB.bmah[ns.priceRealm or ns.realmKey or ""]
  local r = d and d.items[id]
  if r then return r, d.t end
end
ns._bmStore = store -- для автотестов
