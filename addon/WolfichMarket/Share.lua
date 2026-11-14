-- WolfichMarket: общий рынок — игроки с аддоном делятся свежими ценами через скрытый канал аддона.
-- Кто сделал снимок аукциона — рассылает минимальные цены нужных предметов; остальные принимают их
-- (только для своего аукциона: режим + фракция). Свой снимок всегда важнее чужого.
local _, ns = ...
local L = ns.L
local safe = ns.safe

local PREFIX = "WolfMkt1"
local CHANNEL = "WolfichMarketNet"
local SEND_EVERY = 0.3          -- не чаще ~3 сообщений в секунду: сервер не любит частые сообщения
local MAXLEN = 240

-- ---------- компактная запись чисел (36-ричная) ----------
local DIG = "0123456789abcdefghijklmnopqrstuvwxyz"
local function enc(n)
  n = math.floor(n or 0); if n <= 0 then return "0" end
  local s = ""
  while n > 0 do local d = n % 36; s = DIG:sub(d + 1, d + 1) .. s; n = math.floor(n / 36) end
  return s
end
local function dec(s) return tonumber(s, 36) end

local function S() return ns.DB.settings end
-- поля сообщения разделяются «^»; в ключе аукциона «|» заменяем (вертикальная черта в чате - служебный символ)
local function RK() return ns.realmKey and (ns.realmKey:gsub("|", "~")) end
local function netTable(rk)
  ns.DB.net = ns.DB.net or {}
  ns.DB.net[rk] = ns.DB.net[rk] or { items = {} }
  return ns.DB.net[rk]
end

-- ---------- канал ----------
local chanId
local function channel()
  if chanId and chanId > 0 then return chanId end
  local id = GetChannelName and GetChannelName(CHANNEL)
  if id and id > 0 then chanId = id return id end
end
local function join()
  if not JoinTemporaryChannel or channel() then return end
  pcall(JoinTemporaryChannel, CHANNEL)
  ns.After(2, function()
    if channel() and ChatFrame_RemoveChannel then
      for i = 1, (NUM_CHAT_WINDOWS or 10) do local cf = _G["ChatFrame" .. i]; if cf then pcall(ChatFrame_RemoveChannel, cf, CHANNEL) end end
    end
  end)
end
-- сообщения «вы вошли в канал WolfichMarketNet» не показываем
if ChatFrame_AddMessageEventFilter then
  local function hide(_, _, ...) local name = select(9, ...) or select(4, ...); if type(name) == "string" and name:find(CHANNEL, 1, true) then return true end end
  for _, e in ipairs({ "CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_CHANNEL_NOTICE_USER", "CHAT_MSG_CHANNEL_JOIN", "CHAT_MSG_CHANNEL_LEAVE", "CHAT_MSG_CHANNEL" }) do
    pcall(ChatFrame_AddMessageEventFilter, e, hide)
  end
end

-- ---------- очередь отправки ----------
local queue, sending = {}, false
local function pump()
  local msg = table.remove(queue, 1)
  if not msg then sending = false return end
  local id = channel()
  local C = C_ChatInfo
  if id and C and C.SendAddonMessage then pcall(C.SendAddonMessage, PREFIX, msg, "CHANNEL", id)
  elseif IsInGuild and IsInGuild() and C and C.SendAddonMessage then pcall(C.SendAddonMessage, PREFIX, msg, "GUILD") end
  ns.After(SEND_EVERY, pump)
end
local function send(msg)
  queue[#queue + 1] = msg
  if not sending then sending = true; ns.After(0, pump) end
end
ns._netQueue = queue -- для автотестов

-- какие предметы рассылать: материалы и результаты всех рецептов из данных Wowhead + отмеченные
local shareSet
local function sharedIDs()
  if shareSet then return shareSet end
  local set = {}
  for _, d in pairs(ns.RS and ns.RS.r or {}) do
    if d.cr then set[d.cr[1]] = true end
    for _, r in ipairs(d.rg or {}) do set[r[1]] = true end
  end
  shareSet = set
  return set
end

-- разослать свой снимок (только свой, не пересланный чужой)
function ns.ShareScan(scan)
  if not scan or not scan.items or S().netSend == false or not ns.realmKey then return end
  -- порядок: сначала предметы с сигналами, потом рецепты моих профессий, потом остальные рецепты игры
  local order, seen = {}, {}
  local function add(id) if id and not seen[id] then local r = scan.items[id]; if r and r[1] and r[1] > 0 then seen[id] = true; order[#order + 1] = id end end end
  for id in pairs(ns.NetWanted()) do add(id) end -- сначала то, на что другие игроки поставили сигналы
  for id in pairs(ns.DB.marked) do add(id) end
  for id in pairs(ns.RecipeItems and ns.RecipeItems() or {}) do add(id) end
  for id in pairs(sharedIDs()) do add(id) end
  local parts, n = {}, 0
  local head = "P^" .. RK() .. "^" .. enc(scan.t) .. "^"
  local cur = head
  for _, id in ipairs(order) do
    local r = scan.items[id]
    local item = enc(id) .. "," .. enc(r[1]) .. "," .. enc(r[2] or 0) .. ";"
    if #cur + #item > MAXLEN then parts[#parts + 1] = cur; cur = head end
    cur = cur .. item; n = n + 1
  end
  if cur ~= head then parts[#parts + 1] = cur end
  if n == 0 then return end
  send("H^" .. RK() .. "^" .. enc(scan.t) .. "^" .. enc(n) .. "^" .. (ns.VERSION or ""))
  for _, p in ipairs(parts) do send(p) end
  send("E^" .. RK() .. "^" .. enc(scan.t))
  ns.dbg(string.format("общий рынок: отправлено %d цен (%d сообщений)", n, #parts))
end

-- ---------- «что нужно»: каждый сообщает в канал свои предметы с сигналами ----------
-- тот, кто сканирует, рассылает их первыми, а цены, найденные обычным поиском, пересылает сразу
local wants = {}        -- [игрок] = { t, ids = { [id] = true } }
function ns.NetWanted()
  local out, now = {}, time()
  for who, w in pairs(wants) do
    if now - w.t > 3 * 3600 then wants[who] = nil else for id in pairs(w.ids) do out[id] = true end end
  end
  return out
end
local function sendWants()
  if S().netRecv == false or not ns.realmKey then return end
  local ids = {}
  for id in pairs(ns.DB.marked) do ids[#ids + 1] = enc(id) end
  for _, d in ipairs(ns.PlanNeeds and (ns.PlanNeeds()) or {}) do if d.buy and d.buy > 0 then ids[#ids + 1] = enc(d.id) end end
  if #ids == 0 then return end
  local head = "W^" .. RK() .. "^"
  local cur = head
  for _, e in ipairs(ids) do
    if #cur + #e + 1 > MAXLEN then send(cur); cur = head end
    cur = cur .. e .. ","
  end
  if cur ~= head then send(cur) end
end
ns._netSendWants = sendWants
local wantsQueued
ns.Listen("MARKS", function() if wantsQueued then return end; wantsQueued = true; ns.After(30, function() wantsQueued = false; sendWants() end) end)
-- цены, увиденные обычным поиском на аукционе: если их кто-то ждёт - переслать (пачкой раз в 10 секунд)
local seenOut, seenQueued = {}, false
local origSeen = ns.SeenPrice
ns.SeenPrice = function(id, unit, qty)
  origSeen(id, unit, qty)
  if S().netSend == false or not id or not unit or unit <= 0 then return end
  if not ns.NetWanted()[id] then return end
  seenOut[id] = { unit, qty or 0 }
  if seenQueued then return end
  seenQueued = true
  ns.After(10, function()
    seenQueued = false
    local head = "S^" .. RK() .. "^" .. enc(time()) .. "^"
    local cur = head
    for k, r in pairs(seenOut) do
      local item = enc(k) .. "," .. enc(r[1]) .. "," .. enc(r[2]) .. ";"
      if #cur + #item > MAXLEN then send(cur); cur = head end
      cur = cur .. item
    end
    if cur ~= head then send(cur) end
    wipe(seenOut)
  end)
end

-- ---------- приём ----------
local incoming = {}     -- [sender] = { t, items = {} }
local lastFrom = {}     -- защита от спама: не чаще раза в 5 минут от одного игрока
local function plausible(id, p)
  -- явно ненормальная цена (в 30 раз выше/ниже известной) - отбрасываем
  local mine = ns.AHPrice(id)
  if not mine or mine <= 0 then return true end
  return p < mine * 30 and p > mine / 30
end
local function finish(sender)
  local inc = incoming[sender]; incoming[sender] = nil
  if not inc or not next(inc.items) then return end
  local net = netTable(ns.realmKey)
  local scan = { t = inc.t, items = {}, net = true, from = sender }
  local cnt = 0
  for id, r in pairs(inc.items) do
    local old = net.items[id]
    if (not old or old[3] < inc.t) and plausible(id, r[1]) then
      net.items[id] = { r[1], r[2], inc.t }
      scan.items[id] = { r[1], r[2], 1 }
      cnt = cnt + 1
    end
  end
  if cnt == 0 then return end
  net.t, net.from = math.max(net.t or 0, inc.t), sender
  -- точки на графиках для отмеченных и предметов рецептов
  local want = ns.RecipeItems and ns.RecipeItems() or {}
  for id in pairs(ns.DB.marked) do want[id] = true end
  for id in pairs(want) do local r = scan.items[id]; if r then ns.AddHistory(id, r[1], r[2], inc.t) end end
  ns.say(string.format(L"общий рынок: %d свежих цен от %s (%s)", cnt, (sender:match("^[^-]+") or sender), ns.ago(inc.t)))
  ns.Fire("PRICES")
  ns.Fire("NET_DONE", scan, nil)
end

local function onMessage(prefix, msg, _, sender)
  if prefix ~= PREFIX or not msg or not ns.DB then return end
  if S().netRecv == false then return end
  local me = UnitName and UnitName("player")
  if sender and me and (sender == me or sender:match("^[^-]+") == me) then return end
  local kind, rk, rest = msg:match("^(%a)%^([^%^]+)%^(.*)$")
  if not kind or rk ~= RK() then return end -- чужой аукцион (другой режим или фракция)
  if kind == "W" then
    local w = wants[sender] or { ids = {} }
    if not wants[sender] or time() - w.t > 60 then w.ids = {} end -- новый список - заменяет старый
    w.t = time()
    for e in rest:gmatch("(%w+),") do local id = dec(e); if id then w.ids[id] = true end end
    wants[sender] = w
    return
  elseif kind == "S" then
    -- отдельные цены из поиска на аукционе: принимаем каждую, если свежее нашей
    local tstr, body = rest:match("^([^%^]+)%^(.*)$")
    local t = tstr and dec(tstr)
    if not t or (lastFrom["S" .. sender] and time() - lastFrom["S" .. sender] < 5) then return end
    lastFrom["S" .. sender] = time()
    local net = netTable(ns.realmKey)
    local scan, cnt = { t = t, items = {}, net = true, from = sender }, 0
    for a, b, c in body:gmatch("(%w+),(%w+),(%w+);") do
      local id, p, q = dec(a), dec(b), dec(c)
      local _, myT = ns.AHPrice(id)
      if id and p and p > 0 and (not myT or myT < t) and plausible(id, p) then
        net.items[id] = { p, q or 0, t }; scan.items[id] = { p, q or 0, 1 }; cnt = cnt + 1
        if ns.IsMarked(id) then ns.AddHistory(id, p, q or 0, t) end
      end
    end
    if cnt > 0 then net.t, net.from = math.max(net.t or 0, t), sender; ns.Fire("PRICES"); ns.Fire("NET_DONE", scan, nil) end
    return
  elseif kind == "Q" then
    -- кто-то спрашивает свежие цены: отвечаем, если наш снимок новее на 10+ минут (со случайной задержкой, чтобы не отвечали все)
    local t = dec(rest) or 0
    local scan = ns.DB.ahScans[ns.realmKey]
    if scan and scan.t > t + 600 and S().netSend ~= false then
      local my = scan.t
      ns.After(1 + math.random() * 4, function() if not ns._netAnswered or ns._netAnswered < my then ns._netAnswered = my; ns.ShareScan(scan) end end)
    end
  elseif kind == "H" then
    local t = dec(rest:match("^([^%^]+)")) or 0
    ns._netAnswered = math.max(ns._netAnswered or 0, t) -- кто-то уже рассылает такой снимок - сами не отвечаем
    local mine = ns.DB.ahScans[ns.realmKey]
    local net = netTable(ns.realmKey)
    if (mine and mine.t >= t) or (net.t and net.t >= t) then return end -- у нас не хуже
    if lastFrom[sender] and time() - lastFrom[sender] < 300 then return end
    lastFrom[sender] = time()
    incoming[sender] = { t = t, items = {} }
    ns.After(120, function() if incoming[sender] then finish(sender) end end) -- конец потерялся - берём что пришло
  elseif kind == "P" then
    local inc = incoming[sender]
    if not inc then return end
    local tstr, body = rest:match("^([^%^]+)%^(.*)$")
    if not tstr or dec(tstr) ~= inc.t then return end
    for a, b, c in body:gmatch("(%w+),(%w+),(%w+);") do
      local id, p, q = dec(a), dec(b), dec(c)
      if id and p and p > 0 then inc.items[id] = { p, q or 0 } end
    end
  elseif kind == "E" then
    if incoming[sender] and dec(rest) == incoming[sender].t then finish(sender) end
  end
end
ns._netReceive = onMessage -- для автотестов

ns.On("CHAT_MSG_ADDON", onMessage)
ns.Listen("LOGIN", function()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
  ns.After(8, function()
    join()
    -- спросить у других свежие цены, если своих нет или они старше 15 минут
    ns.After(4, function()
      if S().netRecv == false or not ns.realmKey then return end
      local mine = ns.DB.ahScans[ns.realmKey]
      local net = ns.DB.net and ns.DB.net[ns.realmKey]
      local t = math.max(mine and mine.t or 0, net and net.t or 0)
      sendWants() -- сообщить, какие предметы нам нужны
      if time() - t > 900 then send("Q^" .. RK() .. "^" .. enc(t)) end
    end)
  end)
end)
-- свой снимок готов - поделиться
ns.Listen("SCAN_DONE", function(scan) if scan and not scan.net then ns.After(3, function() ns.ShareScan(scan) end) end end)

-- цена от других игроков (для AHPrice): { цена, количество, время снимка }
function ns.NetPrice(id)
  local rk = ns.priceRealm or ns.realmKey
  local net = ns.DB.net and ns.DB.net[rk]
  local r = net and net.items[id]
  if r then return r[1], r[3], r[2] end
end
function ns.NetInfo()
  local net = ns.DB.net and ns.DB.net[ns.priceRealm or ns.realmKey]
  if net and net.t then return net.t, net.from end
end
