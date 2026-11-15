-- WolfichMarket: общий рынок — игроки с аддоном делятся свежими ценами через скрытый канал аддона.
-- Кто сделал снимок аукциона — рассылает минимальные цены нужных предметов; остальные принимают их
-- (только для своего аукциона: режим + фракция). Свой снимок всегда важнее чужого.
local _, ns = ...
local L = ns.L
local safe = ns.safe

local PREFIX = "WolfMkt1"
-- «турбо»: у каждого служебного имени аддона свой лимит игры (~1 сообщение в секунду), поэтому цены идут
-- по очереди через 4 имени. Общий объём при этом всё равно ограничен (см. RATE ниже) - разрывов не будет.
local PREFIXES = { "WolfMkt1", "WolfMkt2", "WolfMkt3", "WolfMkt4" }
local IS_PREFIX = {}; for _, p in ipairs(PREFIXES) do IS_PREFIX[p] = true end
local nextOk = {}     -- [имя] = время, когда этим именем снова можно отправлять
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
-- Обычный режим: 400 байт/с (фактически ~1 сообщение в секунду - лимит одного имени).
-- Турбо: 800 байт/с - столько же, сколько у ChatThrottleLib, которой пользуются почти все крупные аддоны.
local OVERHEAD = 40
local function turbo() return S().netTurbo ~= false end
local function limits() if turbo() then return 800, 2000 end return 400, 1000 end
local tokens, tokT = 1000, nil
local function budget(cost)
  local RATE, BURST = limits()
  local now = GetTime()
  if tokT then tokens = math.min(BURST, tokens + (now - tokT) * RATE) else tokens = BURST end
  tokT = now
  -- крупное сообщение (Battle.net) может быть больше запаса - тогда ждём полного запаса и уходим «в долг»
  local need = math.min(cost, BURST)
  if tokens >= need then tokens = tokens - cost return 0 end
  return (need - tokens) / RATE
end
ns._netBudget = function() return limits() end
-- свободное имя: при турбо - то, что раньше освободится; иначе только основное
local function pickPrefix()
  if not turbo() then return PREFIX, nextOk[PREFIX] or 0 end
  local best, bt = PREFIX, nextOk[PREFIX] or 0
  for _, p in ipairs(PREFIXES) do local t = nextOk[p] or 0; if t < bt then best, bt = p, t end end
  return best, bt
end
-- сколько займёт отправка: bytes байт в msgs сообщениях (обычных путей), в секундах - для турбо и обычного режима
function ns.NetSendTime(bytes, msgs)
  local normal = math.max(bytes / 400, msgs * 1.05)
  local fast = math.max(bytes / 800, msgs * 1.05 / #PREFIXES)
  return normal, fast
end
local function pump()
  -- очереди по очереди: Battle.net не забирает весь трафик у канала
  bnTurn = not bnTurn
  local e = (bnTurn and bnQueue[1]) or queue[1] or bnQueue[1]
  if not e then sending = false return end
  local p = PREFIX
  if e[2] ~= "BN" then
    local ready; p, ready = pickPrefix()
    if ready > GetTime() then ns.After(math.max(0.05, ready - GetTime()), pump) return end -- имя ещё «остывает»
  end
  local need = budget(#e[1] + OVERHEAD)
  if need > 0 then ns.After(math.max(0.1, need), pump) return end -- ждём, пока наберётся «бюджет»
  if bnQueue[1] == e then table.remove(bnQueue, 1) else table.remove(queue, 1) end
  local C = C_ChatInfo
  local wait = turbo() and 0.05 or SEND_EVERY
  if e[2] == "BN" then
    local ok = pcall(BNSendGameData, e[3], PREFIX, e[1])
    if ok then ns.netStats.sent = ns.netStats.sent + 1 else ns.netStats.fail = ns.netStats.fail + 1; ns.netStats.lastFail = "BN" end
  elseif C and C.SendAddonMessage then
    local ok, res = pcall(C.SendAddonMessage, p, e[1], e[2], e[3])
    nextOk[p] = GetTime() + 1.05
    if ok and type(res) == "number" and THROTTLED[res] then
      e.tries = (e.tries or 0) + 1
      if e.tries <= 5 then table.insert(queue, 1, e) end -- повторить, когда игра разрешит
      ns.netStats.throttled = (ns.netStats.throttled or 0) + 1
      nextOk[p] = GetTime() + 3
    elseif not ok or res == false or (type(res) == "number" and res ~= 0) then
      ns.netStats.fail = ns.netStats.fail + 1; ns.netStats.lastFail = e[2] .. " " .. tostring(ok and res or "ошибка")
    else ns.netStats.sent = ns.netStats.sent + 1 end
  end
  ns.After(wait, pump)
end
-- msg - для обычных путей (до 255 символов), big - то же крупной пачкой для Battle.net (если есть)
-- t - время снимка: новая рассылка выбрасывает из очереди недосланную старую
-- rest - «остальной аукцион»: только через канал аддона и Battle.net, без копий в гильдию, группу и шёпотом друзьям
-- sendTarget - ответ одному игроку (тому, кто спросил цены): только ему, через Battle.net или шёпотом
local sendTarget
local function send(msg, big, onlyBig, t, rest)
  if sendTarget then
    local short = sendTarget:match("^[^-]+")
    for _, r in ipairs(routes()) do
      if r[1] == "BN" and r[3] and r[3]:match("^[^-]+") == short then
        if big ~= false then bnQueue[#bnQueue + 1] = { big or msg, r[1], r[2], r[3], t = t } end
        if not sending then sending = true; ns.After(0, pump) end
        return
      end
    end
    if not onlyBig then queue[#queue + 1] = { msg, "WHISPER", sendTarget, nil, t = t } end
    if not sending and #queue > 0 then sending = true; ns.After(0, pump) end
    return
  end
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
-- ---------- плотная запись: самоограниченные числа без разделителей ----------
-- Только буквы и цифры (62 символа): знаки препинания игра может не пропустить в служебных сообщениях.
-- 31 «продолжающая» цифра и 31 «последняя» - последняя цифра числа показывает, где оно кончается.
local A = {}
for ch in ("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"):gmatch(".") do A[#A + 1] = ch end
local HALF = 31
local IDX = {}; for i, ch in ipairs(A) do IDX[ch] = i - 1 end
local function zenc(n)
  n = math.max(0, math.floor(n or 0))
  local d = { n % HALF }; n = math.floor(n / HALF)
  while n > 0 do table.insert(d, 1, n % HALF); n = math.floor(n / HALF) end
  local out = {}
  for i, v in ipairs(d) do out[i] = (i == #d) and A[v + HALF + 1] or A[v + 1] end
  return table.concat(out)
end
-- разобрать строку в список чисел
local function zdec(str)
  local nums, cur = {}, 0
  for i = 1, #str do
    local v = IDX[str:sub(i, i)]
    if not v then return nums end
    if v >= HALF then nums[#nums + 1] = cur * HALF + (v - HALF); cur = 0 else cur = cur * HALF + v end
  end
  return nums
end
ns._zenc, ns._zdec = zenc, zdec

-- сообщения из списка предметов: номера по возрастанию, первый - целиком, дальше - разница с предыдущим.
-- withQty - с количеством (сигналы и рецепты), без него - только цена (остальной аукцион)
local function pack(kind, t, ids, items, withQty, maxlen)
  table.sort(ids)
  local head = kind .. "^" .. RK() .. "^" .. enc(t) .. "^"
  local out, buf, len, prev = {}, {}, #head, nil
  for _, id in ipairs(ids) do
    local r = items[id]
    local piece = zenc(prev and (id - prev) or id) .. zenc(r[1]) .. (withQty and zenc(r[2] or 0) or "")
    if len + #piece > maxlen and #buf > 0 then
      out[#out + 1] = head .. table.concat(buf); buf, prev = {}, nil
      piece = zenc(id) .. zenc(r[1]) .. (withQty and zenc(r[2] or 0) or "")
      len = #head
    end
    buf[#buf + 1] = piece; len = len + #piece; prev = id
  end
  if #buf > 0 then out[#out + 1] = head .. table.concat(buf) end
  return out
end

-- что разослано в прошлый раз (в памяти): для «только изменившихся цен»
local lastSent = {}   -- [ключ аукциона] = { t, full = время полной рассылки, p = { [id] = цена } }

-- разослать свой снимок (только свой, не пересланный чужой). full - целиком (по запросу или раз в час)
-- Когда снимки делают многие игроки сразу, рассылки не должны мешать друг другу:
--  * пока кто-то рассылает, свою рассылку откладываем, а потом шлём только то, что отличается от уже пришедшего;
--  * целиком аукцион уходит в сети не чаще раза в час (кто бы его ни прислал) и по запросу, но не чаще раза в 10 минут;
--  * если в сети уже есть снимок свежее нашего - не шлём ничего.
local netSeen = { active = 0, lastFull = 0 }  -- active - когда пришло последнее сообщение чужой рассылки (GetTime), lastFull - время последней полной (time)
ns._netSeen = netSeen
ns._netResetSent = function() for k in pairs(lastSent) do lastSent[k] = nil end; netSeen.active, netSeen.lastFull = -1000, 0 end -- для автотестов
local pending                                  -- отложенная рассылка { scan, full, tries }
local function busy() return GetTime() - netSeen.active < 20 end
-- to - имя игрока: ответ на его запрос - весь аукцион целиком только ему (остальным не мешает)
function ns.ShareScan(scan, full, again, to)
  if not scan or not scan.items or S().netSend == false or not ns.realmKey then return end
  local rk = RK()
  local last = lastSent[rk]
  if to then full, again = "force", true end
  if not to and last and last.t and scan.t < last.t then return end -- уже разослан более свежий снимок
  local net = ns.DB.net and ns.DB.net[ns.realmKey]
  if not full and net and net.t and net.t >= scan.t then return end -- в сети уже есть снимок не хуже
  -- кто-то сейчас рассылает - подождём конца (до ~15 минут), потом разошлём только отличия от пришедшего
  if busy() and not again then
    pending = { scan = scan, full = full, tries = 0 }
    local function retry()
      local pd = pending
      if not pd or pd.scan ~= scan then return end
      pd.tries = pd.tries + 1
      if busy() and pd.tries < 30 then ns.After(20 + math.random() * 20, retry) return end
      pending = nil
      ns.ShareScan(scan, full, true)
    end
    ns.After(20 + math.random() * 20, retry)
    ns.say(L"общий рынок: сейчас рассылает другой игрок - свой снимок отправлю после него, только отличия.")
    return
  end
  if pending and pending.scan.t <= scan.t then pending = nil end
  -- в общую сеть - всегда весь аукцион, но только цены, изменившиеся относительно уже известных;
  -- целиком - только вручную (/wmnetsend) и лично тому, кто спросил
  if full ~= "force" then full = nil end
  -- последняя известная сети цена: из чужих рассылок или из нашей прошлой - что свежее
  local function known(id)
    local x = net and net.items[id]
    local mine = last and last.p and last.p[id]
    if mine and (not x or (last.t or 0) >= (x[3] or 0)) then return mine end
    return x and x[1]
  end
  -- порядок: сначала предметы, на которые игроки поставили сигналы, потом все рецепты игры, потом остальной аукцион
  local seen = {}
  local g0, g1, g2, rest = {}, {}, {}, {}
  local function ok(id) local r = scan.items[id]; return id and not seen[id] and r and r[1] and r[1] > 0 end
  for id in pairs(ns.NetWanted()) do if ok(id) then seen[id] = true; g0[#g0 + 1] = id end end
  for id in pairs(ns.DB.marked) do if ok(id) then seen[id] = true; g1[#g1 + 1] = id end end
  for id in pairs(sharedIDs()) do if ok(id) then seen[id] = true; g2[#g2 + 1] = id end end
  local unchanged = 0
  -- не целиком: и в важном, и в остальном - только цены, отличающиеся от уже известных сети
  if not full then
    for _, g in ipairs({ g0, g1, g2 }) do
      for k = #g, 1, -1 do if known(g[k]) == scan.items[g[k]][1] then table.remove(g, k); unchanged = unchanged + 1 end end
    end
  end
  local pri = #g0 + #g1 + #g2
  for id, r in pairs(scan.items) do
    if ok(id) then
      seen[id] = true
      if full or known(id) ~= r[1] then rest[#rest + 1] = id else unchanged = unchanged + 1 end
    end
  end
  local n = pri + #rest
  if n == 0 then
    if not to then lastSent[rk] = { t = scan.t, full = last and last.full, p = last and last.p or {} } end
    ns.say(L"общий рынок: цены в сети уже такие же, как в вашем снимке - рассылать нечего.")
    return
  end
  -- запомнить разосланное
  local p = {}
  for id, r in pairs(scan.items) do if r[1] and r[1] > 0 then p[id] = r[1] end end
  if not to then lastSent[rk] = { t = scan.t, full = full and time() or (last and last.full), p = p } end
  -- новая рассылка отменяет недосланную старую
  for _, q in ipairs({ queue, bnQueue }) do for k = #q, 1, -1 do if q[k].t and q[k].t < scan.t then table.remove(q, k) end end end
  local priParts = {}
  for _, m in ipairs(pack("C", scan.t, g0, scan.items, true, MAXLEN)) do priParts[#priParts + 1] = m end
  for _, m in ipairs(pack("C", scan.t, g1, scan.items, true, MAXLEN)) do priParts[#priParts + 1] = m end
  for _, m in ipairs(pack("C", scan.t, g2, scan.items, true, MAXLEN)) do priParts[#priParts + 1] = m end
  local restParts = pack("R", scan.t, rest, scan.items, false, MAXLEN)
  -- Battle.net - те же данные крупнее
  local all = {}; for _, id in ipairs(g0) do all[#all + 1] = id end; for _, id in ipairs(g1) do all[#all + 1] = id end; for _, id in ipairs(g2) do all[#all + 1] = id end
  local bigParts = pack("C", scan.t, all, scan.items, true, 2000)
  for _, m in ipairs(pack("R", scan.t, rest, scan.items, false, 2000)) do bigParts[#bigParts + 1] = m end
  ns._lastShare = { items = n, pri = pri, full = full, unchanged = unchanged }
  -- заголовок: время, сколько цен, версия, сколько важных, тип (f - целиком, d - только изменения)
  sendTarget = to
  send("H^" .. rk .. "^" .. enc(scan.t) .. "^" .. enc(n) .. "^" .. (ns.VERSION or "") .. "^" .. enc(pri) .. "^" .. (full and "f" or "d"), nil, nil, scan.t)
  -- обычные пути: сигналы и рецепты - всем путям, остальной аукцион - только каналу
  for _, m in ipairs(priParts) do send(m, false, nil, scan.t) end
  for _, m in ipairs(restParts) do send(m, false, nil, scan.t, true) end
  for _, m in ipairs(bigParts) do send(m, m, true, scan.t) end
  send("E^" .. rk .. "^" .. enc(scan.t), nil, nil, scan.t)
  sendTarget = nil
  if to then ns.say(string.format(L"общий рынок: %s попросил цены - отправляю ему весь аукцион (%d цен).", to:match("^[^-]+") or to, n)) return end
  local parts = {}
  for _, m in ipairs(priParts) do parts[#parts + 1] = m end
  local priCount = #priParts
  for _, m in ipairs(restParts) do parts[#parts + 1] = m end
  local rs = routes()
  local names = {}
  for _, r in ipairs(rs) do names[#names + 1] = r[1] == "CHANNEL" and L"канал" or r[1] == "GUILD" and L"гильдия" or r[1] == "WHISPER" and r[2] or r[1] == "BN" and r[3] or L"группа" end
  ns.say(string.format(L"общий рынок: отправляю %d цен (%s)", n, #names > 0 and table.concat(names, ", ") or L"|cffff6060некому - нет канала, гильдии, группы и друзей онлайн|r")
    .. (full and "" or string.format(L" - только изменившиеся, без изменений: %d", unchanged)))
  local small, bytes, msgs, priBytes, priMsgs = 0, 0, 0, 0, 0
  for _, r in ipairs(rs) do if r[1] ~= "BN" then small = small + 1 end end
  for i, p in ipairs(parts) do
    local k = (i <= priCount) and small or (small > 0 and 1 or 0)
    bytes = bytes + (#p + OVERHEAD) * k; msgs = msgs + k
    if i <= priCount then priBytes = priBytes + (#p + OVERHEAD) * k; priMsgs = priMsgs + k end
  end
  for _, r in ipairs(rs) do if r[1] == "BN" then for _, p in ipairs(bigParts) do bytes = bytes + #p + OVERHEAD end end end
  ns._lastShare.bytes, ns._lastShare.msgs, ns._lastShare.priBytes, ns._lastShare.priMsgs = bytes, msgs, priBytes, priMsgs
  if small > 0 then
    local n1, f1 = ns.NetSendTime(priBytes, priMsgs)
    local n2, f2 = ns.NetSendTime(bytes, msgs)
    local function m(sec) return sec < 60 and (math.ceil(sec) .. L" с") or (math.ceil(sec / 60) .. L" мин") end
    local tb = turbo()
    ns.say(string.format(L"общий рынок: сигналы и рецепты (%d) - за %s, весь аукцион - за %s (%s; %s: %s и %s). Не выходите из игры, пока идёт рассылка.",
      pri, m(tb and f1 or n1), m(tb and f2 or n2), tb and L"турбо" or L"обычный режим", tb and L"без турбо было бы" or L"с турбо было бы", m(tb and n1 or f1), m(tb and n2 or f2)))
  end
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
    ns.say(string.format(inc.delta and L"общий рынок: изменения аукциона от %s (%s) - %d цен, из них свежее ваших: %d." or L"общий рынок: весь аукцион от %s (%s) - %d цен, из них свежее ваших: %d.", who, ns.ago(inc.t), got, inc.newCount or 0))
  end
end

local answered = {}     -- [кто спросил] = когда ему начали отвечать
local alias, bySig = {}, {} -- один снимок, пришедший разными путями: [отправитель] = основное имя; [время/кол-во] = основное имя
local function onMessage(prefix, msg, dist, sender)
  if not IS_PREFIX[prefix] or not msg or not ns.DB then return end
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
  -- кто-то рассылает снимок: свою рассылку придержим (см. ns.ShareScan)
  if kind == "H" or kind == "C" or kind == "R" or kind == "P" then netSeen.active = GetTime() end
  ns.netStats.kinds = ns.netStats.kinds or {}
  ns.netStats.kinds[kind] = (ns.netStats.kinds[kind] or 0) + 1
  if kind == "H" and rest:match("%^f$") then netSeen.lastFull = time() end
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
    -- отвечаем лично ему (весь аукцион целиком); в общую сеть - «я отвечаю», чтобы не отвечали все сразу
    if scan and scan.t > t + 600 and S().netSend ~= false then
      ns.After(1 + math.random() * 4, function()
        if answered[sender] and time() - answered[sender] < 120 then return end
        answered[sender] = time()
        send("A^" .. RK() .. "^" .. sender)
        ns.ShareScan(scan, true, true, sender)
      end)
    end
  elseif kind == "A" then
    answered[rest] = time() -- этому игроку уже отвечает кто-то другой
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
    -- один и тот же снимок мог прийти несколькими путями (канал, гильдия, Battle.net) под разными именами
    -- отправителя - собираем его в одно место: цены с любого пути идут в одну копию
    if lastFrom[sender .. t] then return end
    lastFrom[sender .. t] = time()
    local parts = {}; for x in (rest .. "^"):gmatch("([^%^]*)%^") do parts[#parts + 1] = x end
    local sig = t .. "/" .. (parts[2] or "")
    local same = bySig[sig]
    if same and incoming[same] then alias[sender] = same; return end
    bySig[sig] = sender; alias[sender] = nil
    ns.say(string.format(L"общий рынок: принимаю цены от %s (%s)...", (sender:match("^[^-]+") or sender), ns.ago(t)))
    incoming[sender] = { t = t, items = {}, n = dec(parts[2] or ""), pri = dec(parts[4] or ""), delta = parts[5] == "d", last = (GetTime and GetTime() or time()), msgs = 0 }
    -- сторож: если сообщения перестали приходить на 90 секунд - отправитель вышел, сообщаем, что успело прийти
    local function watch()
      local inc = incoming[sender]
      if not inc or inc.t ~= t then return end
      if (GetTime and GetTime() or time()) - inc.last > 90 then finish(sender, true) return end
      ns.After(15, watch)
    end
    ns.After(15, watch)
  elseif kind == "P" then
    sender = (alias[sender] and incoming[alias[sender]]) and alias[sender] or sender
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
  elseif kind == "C" or kind == "R" then
    -- плотная запись (2.29+): C - номер, цена, количество; R - номер и цена. Номера - разницей с предыдущим
    sender = (alias[sender] and incoming[alias[sender]]) and alias[sender] or sender
    local inc = incoming[sender]
    if not inc then return end
    local tstr, body = rest:match("^([^%^]+)%^(.*)$")
    if not tstr or dec(tstr) ~= inc.t then return end
    local nums = zdec(body)
    local step = kind == "C" and 3 or 2
    local id = 0
    for i = 1, #nums - step + 1, step do
      id = (i == 1) and nums[i] or (id + nums[i])
      local p = nums[i + 1]
      if p and p > 0 then
        local old = inc.items[id]
        inc.items[id] = { p, kind == "C" and nums[i + 2] or (old and old[2]) or (ns.DB.net and ns.DB.net[ns.realmKey] and ns.DB.net[ns.realmKey].items[id] and ns.DB.net[ns.realmKey].items[id][2]) or 0 }
      end
    end
    inc.last = (GetTime and GetTime() or time()); inc.msgs = inc.msgs + 1
    if inc.msgs % 20 == 0 then apply(inc, sender) end
  elseif kind == "E" then
    sender = (alias[sender] and incoming[alias[sender]]) and alias[sender] or sender
    if incoming[sender] and dec(rest) == incoming[sender].t then finish(sender) end
  end
end
ns._netReceive = onMessage -- для автотестов

ns.On("CHAT_MSG_ADDON", onMessage)
-- сообщения от друзей Battle.net
ns.On("BN_CHAT_MSG_ADDON", function(prefix, text, _, gameAccountID)
  if not IS_PREFIX[prefix] then return end
  local g = C_BattleNet and C_BattleNet.GetGameAccountInfoByID and safe(C_BattleNet.GetGameAccountInfoByID, gameAccountID)
  local who = g and g.characterName and (g.characterName .. (g.realmName and g.realmName ~= "" and ("-" .. g.realmName) or "")) or ("bn" .. tostring(gameAccountID))
  onMessage(prefix, text, "BN", who)
end)
ns.Listen("LOGIN", function()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then for _, p in ipairs(PREFIXES) do pcall(C_ChatInfo.RegisterAddonMessagePrefix, p) end end
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
