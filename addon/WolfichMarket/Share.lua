-- WolfichMarket: общий рынок — игроки с аддоном делятся свежими ценами через скрытый канал аддона.
-- Кто сделал снимок аукциона — рассылает минимальные цены нужных предметов; остальные принимают их
-- (только для своего аукциона: режим + фракция). Свой снимок всегда важнее чужого.
local _, ns = ...
local L = ns.L
local safe = ns.safe

local PREFIX = "WolfMkt1"
local CHANNEL = "WolfichMarketNet"
local SEND_EVERY = 0.3          -- пауза для Battle.net; обычные пути - раз в секунду (ограничение игры)
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
-- ключ общего аукциона для сообщений: режим и фракция (см. ns.NormRealmKey в Core.lua)
local function RK() return ns.realmKey and (ns.NormRealmKey(ns.realmKey):gsub("|", "~")) end
ns.NetKey = RK
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
-- маршруты: общий канал аддона + гильдия + группа + друзья онлайн (личным сообщением аддона).
-- Если клиент не пускает служебные сообщения в канал, цены всё равно дойдут до друзей, гильдии и группы.
ns.netStats = { sent = 0, recv = 0, fail = 0 }
local function routes()
  local r = {}
  local id = channel()
  if id then r[#r + 1] = { "CHANNEL", id } end
  if IsInGuild and IsInGuild() then r[#r + 1] = { "GUILD" } end
  if IsInRaid and IsInRaid() then r[#r + 1] = { "RAID" } elseif IsInGroup and IsInGroup() then r[#r + 1] = { "PARTY" } end
  local F = C_FriendList
  local seen = {}
  if F and F.GetNumFriends and F.GetFriendInfoByIndex then
    local n = 0
    for i = 1, (safe(F.GetNumFriends) or 0) do
      local f = safe(F.GetFriendInfoByIndex, i)
      if f and f.connected and f.name and n < 10 then r[#r + 1] = { "WHISPER", f.name }; seen[f.name] = true; n = n + 1 end
    end
  end
  -- друзья Battle.net, которые сейчас в WoW: служебное сообщение через Battle.net (работает и между мирами)
  local B = C_BattleNet
  if B and B.GetFriendNumGameAccounts and B.GetFriendGameAccountInfo and BNGetNumFriends and BNSendGameData then
    local n = 0
    for i = 1, (safe(BNGetNumFriends) or 0) do
      for k = 1, (safe(B.GetFriendNumGameAccounts, i) or 0) do
        local g = safe(B.GetFriendGameAccountInfo, i, k)
        if g and g.isOnline and g.gameAccountID and g.characterName and g.characterName ~= "" and not seen[g.characterName] and n < 10 then
          r[#r + 1] = { "BN", g.gameAccountID, g.characterName }; seen[g.characterName] = true; n = n + 1
        end
      end
    end
  end
  return r
end
ns.NetRoutes = routes
-- Игра ограничивает служебные сообщения аддона: ~10 подряд, дальше около одного в секунду
-- (ответ 3/8 - «слишком часто»). Поэтому обычные сообщения идут раз в секунду, а при отказе
-- сообщение возвращается в начало очереди и повторяется позже. Через Battle.net - крупными пачками.
local THROTTLED = { [3] = true, [8] = true }
local queue, bnQueue, sending = {}, {}, false
local bnTurn = false
-- Общий лимит трафика (байт в секунду) на все пути вместе, включая Battle.net. Сервер разрывает связь
-- (WOW51900319), если аддоны шлют слишком много данных подряд, поэтому держимся заметно ниже его порога
-- и оставляем место чату и другим аддонам.
local RATE, BURST, OVERHEAD = 400, 1000, 40
local tokens, tokT = BURST, nil
local function budget(cost)
  local now = GetTime()
  if tokT then tokens = math.min(BURST, tokens + (now - tokT) * RATE) end
  tokT = now
  if tokens >= cost then tokens = tokens - cost return 0 end
  return (cost - tokens) / RATE
end
ns._netBudget = function() return RATE, BURST end
local function pump()
  -- очереди по очереди: Battle.net не забирает весь трафик у канала
  bnTurn = not bnTurn
  local e = (bnTurn and bnQueue[1]) or queue[1] or bnQueue[1]
  if not e then sending = false return end
  local need = budget(#e[1] + OVERHEAD)
  if need > 0 then ns.After(math.max(0.1, need), pump) return end -- ждём, пока наберётся «бюджет»
  if bnQueue[1] == e then table.remove(bnQueue, 1) else table.remove(queue, 1) end
  local C = C_ChatInfo
  local wait = SEND_EVERY
  if e[2] == "BN" then
    local ok = pcall(BNSendGameData, e[3], PREFIX, e[1])
    if ok then ns.netStats.sent = ns.netStats.sent + 1 else ns.netStats.fail = ns.netStats.fail + 1; ns.netStats.lastFail = "BN" end
  elseif C and C.SendAddonMessage then
    local ok, res = pcall(C.SendAddonMessage, PREFIX, e[1], e[2], e[3])
    if ok and type(res) == "number" and THROTTLED[res] then
      e.tries = (e.tries or 0) + 1
      if e.tries <= 5 then table.insert(queue, 1, e) end -- повторить, когда игра разрешит
      ns.netStats.throttled = (ns.netStats.throttled or 0) + 1
      wait = 2
    elseif not ok or res == false or (type(res) == "number" and res ~= 0) then
      ns.netStats.fail = ns.netStats.fail + 1; ns.netStats.lastFail = e[2] .. " " .. tostring(ok and res or "ошибка")
    else ns.netStats.sent = ns.netStats.sent + 1 end
  end
  ns.After(wait, pump)
end
-- msg - для обычных путей (до 255 символов), big - то же крупной пачкой для Battle.net (если есть)
-- t - время снимка: новая рассылка выбрасывает из очереди недосланную старую
-- rest - «остальной аукцион»: только через канал аддона и Battle.net, без копий в гильдию, группу и шёпотом друзьям
local function send(msg, big, onlyBig, t, rest)
  for _, r in ipairs(routes()) do
    if rest and r[1] ~= "CHANNEL" and r[1] ~= "BN" then
    else
    if r[1] == "BN" then
      if big ~= false then bnQueue[#bnQueue + 1] = { big or msg, r[1], r[2], r[3], t = t } end
    elseif not onlyBig then queue[#queue + 1] = { msg, r[1], r[2], r[3], t = t } end
    end
  end
  if not sending and (#queue > 0 or #bnQueue > 0) then sending = true; ns.After(0, pump) end
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
  -- порядок: сначала предметы, на которые игроки поставили сигналы (из общего снимка аукциона), потом все рецепты игры
  local order, seen = {}, {}
  local function add(id) if id and not seen[id] then local r = scan.items[id]; if r and r[1] and r[1] > 0 then seen[id] = true; order[#order + 1] = id end end end
  for id in pairs(ns.NetWanted()) do add(id) end -- сначала то, на что другие игроки поставили сигналы
  for id in pairs(ns.DB.marked) do add(id) end
  for id in pairs(sharedIDs()) do add(id) end -- затем материалы и результаты всех рецептов игры - от профессий сканирующего не зависит
  local pri = #order                                -- сколько «важных» (сигналы и рецепты) - они уходят первыми
  for id in pairs(scan.items) do add(id) end       -- потом весь остальной аукцион
  -- новая рассылка отменяет недосланную старую
  for _, q in ipairs({ queue, bnQueue }) do for k = #q, 1, -1 do if q[k].t and q[k].t < scan.t then table.remove(q, k) end end end
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
  -- для Battle.net те же цены крупными пачками (до ~3800 символов): в 15 раз меньше сообщений
  local bigParts, bcur = {}, head
  for _, p in ipairs(parts) do
    local body = p:sub(#head + 1)
    if #bcur + #body > 2000 then bigParts[#bigParts + 1] = bcur; bcur = head end
    bcur = bcur .. body
  end
  if bcur ~= head then bigParts[#bigParts + 1] = bcur end
  send("H^" .. RK() .. "^" .. enc(scan.t) .. "^" .. enc(n) .. "^" .. (ns.VERSION or "") .. "^" .. enc(pri), nil, nil, scan.t)
  -- обычные пути: мелкими сообщениями; сигналы и рецепты - всем путям, остальной аукцион - только каналу
  local priParts = 0
  do local c = 0; for i, p in ipairs(parts) do local _, k = p:gsub(";", ""); c = c + k; if c <= pri then priParts = i end end end
  for i, p in ipairs(parts) do send(p, false, nil, scan.t, i > priParts + 1) end
  for _, p in ipairs(bigParts) do send(p, p, true, scan.t) end -- Battle.net: крупнее
  send("E^" .. RK() .. "^" .. enc(scan.t), nil, nil, scan.t)
  local rs = routes()
  local names = {}
  for _, r in ipairs(rs) do names[#names + 1] = r[1] == "CHANNEL" and L"канал" or r[1] == "GUILD" and L"гильдия" or r[1] == "WHISPER" and r[2] or r[1] == "BN" and r[3] or L"группа" end
  ns.say(string.format(L"общий рынок: отправляю %d цен (%s)", n, #names > 0 and table.concat(names, ", ") or L"|cffff6060некому - нет канала, гильдии, группы и друзей онлайн|r"))
  local small, bytes = 0, 0
  for _, r in ipairs(rs) do if r[1] ~= "BN" then small = small + 1 end end
  for i, p in ipairs(parts) do bytes = bytes + (#p + OVERHEAD) * (i <= priParts + 1 and small or 1) end
  for _, r in ipairs(rs) do if r[1] == "BN" then for _, p in ipairs(bigParts) do bytes = bytes + #p + OVERHEAD end end end
  if small > 0 then ns.say(string.format(L"общий рынок: сначала сигналы и рецепты (%d), потом остальной аукцион - около %d мин. Не выходите из игры, пока идёт рассылка.", pri, math.ceil(bytes / RATE / 60))) end
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
-- применить пришедшие цены (по ходу рассылки - частями, чтобы сигналы и рецепты работали сразу)
local function apply(inc, sender)
  local net = netTable(ns.realmKey)
  local scan = { t = inc.t, items = {}, net = true, from = sender }
  local cnt = 0
  inc.applied = inc.applied or {}
  for id, r in pairs(inc.items) do
    if not inc.applied[id] then
      inc.applied[id] = true
      local old = net.items[id]
      if (not old or old[3] < inc.t) and plausible(id, r[1]) then
        net.items[id] = { r[1], r[2], inc.t }
        scan.items[id] = { r[1], r[2], 1 }
        cnt = cnt + 1
      end
    end
  end
  if cnt == 0 then return 0 end
  net.t, net.from = math.max(net.t or 0, inc.t), sender
  -- точки на графиках для отмеченных и предметов рецептов
  local want = ns.RecipeItems and ns.RecipeItems() or {}
  for id in pairs(ns.DB.marked) do want[id] = true end
  for id in pairs(want) do local r = scan.items[id]; if r then ns.AddHistory(id, r[1], r[2], inc.t) end end
  inc.newCount = (inc.newCount or 0) + cnt
  ns.Fire("PRICES")
  ns.Fire("NET_DONE", scan, nil)
  return cnt
end
-- конец рассылки: lost = отправитель замолчал раньше, чем пришёл весь аукцион
local function finish(sender, lost)
  local inc = incoming[sender]; incoming[sender] = nil
  if not inc then return end
  apply(inc, sender)
  local got = 0; for _ in pairs(inc.items) do got = got + 1 end
  local who = sender:match("^[^-]+") or sender
  if lost and inc.n and got < inc.n then
    local priGot = math.min(got, inc.pri or got)
    ns.say(string.format(L"общий рынок: %s вышел из игры (или пропал из сети) раньше, чем к вам попал весь аукцион. Пришло %d из %d цен: сигналы и рецепты - %d из %d, остальной аукцион - %d из %d.",
      who, got, inc.n, priGot, inc.pri or inc.n, math.max(0, got - (inc.pri or 0)), math.max(0, inc.n - (inc.pri or 0))), true)
  else
    ns.say(string.format(L"общий рынок: весь аукцион от %s (%s) - %d цен, из них свежее ваших: %d.", who, ns.ago(inc.t), got, inc.newCount or 0))
  end
end

local function onMessage(prefix, msg, dist, sender)
  if prefix ~= PREFIX or not msg or not ns.DB then return end
  ns.netStats.recv = ns.netStats.recv + 1; ns.netStats.lastFrom = sender
  -- каким путём пришло: по этому видно, работает ли общий канал (он нужен для игроков вне друзей и гильдии)
  ns.netStats.by = ns.netStats.by or {}
  local how = dist or "?"
  ns.netStats.by[how] = (ns.netStats.by[how] or 0) + 1
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
    if (mine and mine.t >= t) or (net.t and net.t >= t) then -- у нас не хуже
      if not lastFrom["old" .. sender] or time() - lastFrom["old" .. sender] > 300 then
        lastFrom["old" .. sender] = time()
        ns.say(string.format(L"общий рынок: %s прислал снимок (%s), но ваши цены свежее - оставлены ваши.", (sender:match("^[^-]+") or sender), ns.ago(t)))
      end
      return
    end
    ns.say(string.format(L"общий рынок: принимаю цены от %s (%s)...", (sender:match("^[^-]+") or sender), ns.ago(t)))
    -- один и тот же снимок мог прийти несколькими путями (канал, гильдия, Battle.net) - берём один раз
    if lastFrom[sender .. t] then return end
    lastFrom[sender .. t] = time()
    local parts = {}; for x in (rest .. "^"):gmatch("([^%^]*)%^") do parts[#parts + 1] = x end
    incoming[sender] = { t = t, items = {}, n = dec(parts[2] or ""), pri = dec(parts[4] or ""), last = (GetTime and GetTime() or time()), msgs = 0 }
    -- сторож: если сообщения перестали приходить на 90 секунд - отправитель вышел, сообщаем, что успело прийти
    local function watch()
      local inc = incoming[sender]
      if not inc or inc.t ~= t then return end
      if (GetTime and GetTime() or time()) - inc.last > 90 then finish(sender, true) return end
      ns.After(15, watch)
    end
    ns.After(15, watch)
  elseif kind == "P" then
    local inc = incoming[sender]
    if not inc then return end
    local tstr, body = rest:match("^([^%^]+)%^(.*)$")
    if not tstr or dec(tstr) ~= inc.t then return end
    for a, b, c in body:gmatch("(%w+),(%w+),(%w+);") do
      local id, p, q = dec(a), dec(b), dec(c)
      if id and p and p > 0 then inc.items[id] = { p, q or 0 } end
    end
    inc.last = (GetTime and GetTime() or time()); inc.msgs = inc.msgs + 1
    -- по ходу: каждые 20 сообщений применяем пришедшее - важное (сигналы, рецепты) идёт первым и работает сразу
    if inc.msgs % 20 == 0 then apply(inc, sender) end
  elseif kind == "E" then
    if incoming[sender] and dec(rest) == incoming[sender].t then finish(sender) end
  end
end
ns._netReceive = onMessage -- для автотестов

ns.On("CHAT_MSG_ADDON", onMessage)
-- сообщения от друзей Battle.net
ns.On("BN_CHAT_MSG_ADDON", function(prefix, text, _, gameAccountID)
  if prefix ~= PREFIX then return end
  local g = C_BattleNet and C_BattleNet.GetGameAccountInfoByID and safe(C_BattleNet.GetGameAccountInfoByID, gameAccountID)
  local who = g and g.characterName and (g.characterName .. (g.realmName and g.realmName ~= "" and ("-" .. g.realmName) or "")) or ("bn" .. tostring(gameAccountID))
  onMessage(prefix, text, "BN", who)
end)
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
