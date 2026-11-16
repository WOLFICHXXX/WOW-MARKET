-- WolfichMarket: персонажи аккаунта (золото, уровень, место), их лоты на аукционе и кулдауны рецептов
local _, ns = ...
local L = ns.L
local safe = ns.safe

local function me() return ns.DB and ns.charKey and ns.DB.chars[ns.charKey] end

-- ---------- сведения о персонаже: обновляются, пока им играют ----------
local function snapshot()
  local c = me()
  if not c then return end
  if GetMoney then c.money = safe(GetMoney) or c.money end
  if UnitLevel then c.level = safe(UnitLevel, "player") or c.level end
  if UnitRace then c.race = safe(UnitRace, "player") or c.race end
  if UnitClass then c.className = safe(UnitClass, "player") or c.className end
  local z = (GetRealZoneText and safe(GetRealZoneText)) or (GetZoneText and safe(GetZoneText))
  if z and z ~= "" then c.zone = z end
  c.seen = time()
  ns.Fire("ALTS")
end
ns.SnapshotChar = snapshot
ns.Listen("LOGIN", function() snapshot(); ns.After(3, snapshot) end)
ns.On("PLAYER_MONEY", snapshot)
ns.On("PLAYER_LEVEL_UP", function() ns.After(1, snapshot) end)
ns.On("ZONE_CHANGED_NEW_AREA", snapshot)
ns.On("PLAYER_LOGOUT", function() local c = me(); if c then c.seen = time() end end)

-- персонажи для окна «Твинки»: текущий первым, дальше по имени
function ns.AltList()
  local list = {}
  for ck, c in pairs(ns.DB.chars or {}) do
    if c.realmKey or (c.profs and next(c.profs)) then list[#list + 1] = ck end
  end
  table.sort(list, function(a, b)
    if a == ns.charKey then return true elseif b == ns.charKey then return false end
    return a < b
  end)
  return list
end

-- ---------- лоты на аукционе ----------
-- c.lots = { { aid, id, name, q, p (за шт), ends, st = "active" | "sold", soldAt } }; c.lotsNew - есть непросмотренные продажи
local SOLD_KEEP = 3 * 24 * 3600
local function lotName(id) local n = ns.itemName(id); return n end
local function markSold(c, lot)
  if lot.st == "sold" then return end
  lot.st, lot.soldAt = "sold", time()
  c.lotsNew = true
  ns.say(string.format(L"|cff78d98aпродано|r: %s ×%d - %s", ns.itemLinkText(lot.id), lot.q or 1, ns.money((lot.p or 0) * (lot.q or 1))), true)
  ns.Fire("ALTS")
end
-- свои лоты из игры (аукцион открыт этим персонажем)
function ns.ReadOwnedAuctions()
  local c = me()
  if not c or not C_AuctionHouse or not C_AuctionHouse.GetNumOwnedAuctions then return end
  local n = safe(C_AuctionHouse.GetNumOwnedAuctions) or 0
  local old = {}
  for _, l in ipairs(c.lots or {}) do if l.aid then old[l.aid] = l end end
  local now, list, seen = time(), {}, {}
  for i = 1, n do
    local a = safe(C_AuctionHouse.GetOwnedAuctionInfo, i)
    local id = a and a.itemKey and a.itemKey.itemID
    if id then
      local o = old[a.auctionID] or {}
      local lot = { aid = a.auctionID, id = id, name = lotName(id), q = a.quantity or 1, p = a.buyoutAmount or a.bidAmount or o.p,
        ends = now + (a.timeLeftSeconds or 0), st = o.st or "active", soldAt = o.soldAt, kind = ns.ahKind or "main" }
      list[#list + 1] = lot
      if a.status == 1 then markSold(c, lot) end -- 1 - продан, деньги на почте
      if a.auctionID then seen[a.auctionID] = true end
    end
  end
  -- проданные (уже забранные с почты) держим 3 дня для истории
  for _, l in ipairs(c.lots or {}) do
    if l.st == "sold" and not (l.aid and seen[l.aid]) and now - (l.soldAt or now) < SOLD_KEEP then list[#list + 1] = l end
  end
  c.lots, c.lotsT = list, now
  ns.Fire("ALTS")
end
local function queryOwned()
  if C_AuctionHouse and C_AuctionHouse.QueryOwnedAuctions then safe(C_AuctionHouse.QueryOwnedAuctions, {}) end
end
ns.On("AUCTION_HOUSE_SHOW", function() ns.After(1, queryOwned) end)
ns.On("OWNED_AUCTIONS_UPDATED", ns.ReadOwnedAuctions)
ns.On("AUCTION_HOUSE_AUCTION_CREATED", function() ns.After(1, queryOwned) end)

-- игровое сообщение «Найден покупатель для вашего лота: X»
local soldPat
local function soldPattern()
  if soldPat == nil then
    local f = ERR_AUCTION_SOLD_S
    soldPat = f and ("^" .. f:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)") .. "$") or false
  end
  return soldPat
end
local function soldByName(c, name)
  if not c or not name then return end
  local best
  for _, l in ipairs(c.lots or {}) do
    if l.st ~= "sold" and (l.name == name or ns.itemName(l.id) == name) and (not best or (l.ends or 0) < (best.ends or 0)) then best = l end
  end
  if best then markSold(c, best) end
end
ns.On("CHAT_MSG_SYSTEM", function(msg)
  local pat = soldPattern()
  local name = pat and type(msg) == "string" and msg:match(pat)
  if name then soldByName(me(), name) end
end)
-- письма аукциона о продаже: отмечают лоты, проданные, пока персонаж был не в игре
ns.On("MAIL_INBOX_UPDATE", function()
  if not GetInboxNumItems or not GetInboxInvoiceInfo then return end
  local c = me()
  if not c then return end
  -- событие приходит много раз: каждое письмо учитываем один раз
  c.mailSeen = c.mailSeen or {}
  local now = time()
  for k, t in pairs(c.mailSeen) do if now - t > 31 * 86400 then c.mailSeen[k] = nil end end
  for i = 1, (safe(GetInboxNumItems) or 0) do
    local kind, itemName, buyer, bid, buyout = safe(GetInboxInvoiceInfo, i)
    if kind == "seller" and itemName then
      local key = itemName .. "|" .. tostring(buyer) .. "|" .. tostring(buyout or bid)
      if not c.mailSeen[key] then c.mailSeen[key] = now; soldByName(c, itemName) end
    end
  end
end)

-- ---------- продажи твинков по снимку аукциона другим персонажем ----------
-- В полном снимке у лота нет номера и срока, но есть продавец, предмет, количество и цена. Лот твинка, которого нет в игре,
-- снять с аукциона некому: пропал из снимка до конца срока - значит, куплен.
local function sameAH(c, kind, lot)
  if (lot.kind or "main") ~= kind then return false end
  if kind == "main" then return c.realmKey == ns.realmKey end
  -- общий аукцион один для обеих фракций режима
  return (c.realmKey or ""):match("^[^|]*") == (ns.realmKey or ""):match("^[^|]*")
end
local function lotUnits(l)
  local q = math.max(1, l.q or 1)
  local u = {}
  if l.p then u[#u + 1] = math.floor(l.p + 0.5); u[#u + 1] = math.floor(l.p / q + 0.5) end -- цена за шт или за весь лот
  return u
end
-- что искать в снимке: имена твинков и предметы их активных лотов на этом аукционе
function ns.AltLotWatch(kind)
  local w = { names = {}, items = {}, n = 0 }
  local now = time()
  for ck, c in pairs(ns.DB.chars or {}) do
    if ck ~= ns.charKey and c.name then
      for _, l in ipairs(c.lots or {}) do
        if l.st ~= "sold" and (l.ends or 0) > now and sameAH(c, kind, l) then w.names[c.name] = true; w.items[l.id] = true; w.n = w.n + 1 end
      end
    end
  end
  return w.n > 0 and w or nil
end
function ns.CheckAltLots(kind, watch, seen, total)
  ns.say(string.format(L"снимок: имя продавца пришло у %d из %d лотов%s", seen.withOwner, total,
    seen.withOwner > 0 and L" - продажи твинков видны по снимку" or L" - продажи твинков по снимку определить нельзя"))
  if not watch then return end
  local now, ownerMode = time(), seen.withOwner > 0
  local own, any = {}, {}
  for k, v in pairs(seen.own) do own[k] = v end
  for k, v in pairs(seen.any) do any[k] = v end
  for ck, c in pairs(ns.DB.chars or {}) do
    if ck ~= ns.charKey and c.name and watch.names[c.name] then
      -- сначала лоты, которые кончатся раньше (одинаковые лоты пропадают по одному)
      local list = {}
      for _, l in ipairs(c.lots or {}) do if l.st ~= "sold" and (l.ends or 0) > now and sameAH(c, kind, l) then list[#list + 1] = l end end
      table.sort(list, function(a, b) return (a.ends or 0) > (b.ends or 0) end)
      for _, l in ipairs(list) do
        local found = false
        for _, u in ipairs(lotUnits(l)) do
          local key = l.id .. "|" .. math.max(1, l.q or 1) .. "|" .. u
          local pool = ownerMode and own or any
          local pk = ownerMode and (c.name .. "|" .. key) or key
          if (pool[pk] or 0) > 0 then pool[pk] = pool[pk] - 1; found = true; break end
        end
        if found then l.maybe, l.seenT = nil, now
        elseif ownerMode then markSold(c, l)
        elseif not l.maybe then l.maybe = now; ns.Fire("ALTS") end
      end
    end
  end
end

-- лоты персонажа для показа: активные, срок вышел, проданные
function ns.CharLots(ck)
  local c = ns.DB.chars[ck]
  local out = {}
  for _, l in ipairs(c and c.lots or {}) do out[#out + 1] = l end
  table.sort(out, function(a, b)
    local x, y = a.st == "sold" and 0 or 1, b.st == "sold" and 0 or 1
    if x ~= y then return x < y end
    return (a.ends or 0) < (b.ends or 0)
  end)
  return out
end
-- состояние лота словами
function ns.LotStatus(l)
  if l.st == "sold" then return "|cff78d98a" .. L"Продано" .. "|r" .. ((l.p and l.q) and (" · " .. ns.money(l.p * l.q, true)) or "") end
  local left = (l.ends or 0) - time()
  if left <= 0 then return "|cffaaaaaa" .. L"срок вышел - на почте" .. "|r" end
  if l.maybe then return "|cffffd060" .. L"возможно, продан (нет в снимке)" .. "|r" end
  local h, m = math.floor(left / 3600), math.floor(left % 3600 / 60)
  return L"осталось" .. " " .. (h > 0 and (h .. L" ч ") or "") .. m .. L" м"
end
-- сводка: число лотов и продаж у всех персонажей
function ns.LotsSummary()
  local n, sold, newSold = 0, 0, 0
  for _, c in pairs(ns.DB.chars or {}) do
    for _, l in ipairs(c.lots or {}) do
      n = n + 1
      if l.st == "sold" then sold = sold + 1; if c.lotsNew then newSold = newSold + 1 end end
    end
  end
  return n, sold, newSold
end
function ns.SeenLots(ck) local c = ns.DB.chars[ck]; if c and c.lotsNew then c.lotsNew = nil; ns.Fire("ALTS") end end

-- ---------- кулдауны рецептов (трансмутации и др.) ----------
-- c.cds[recipeID] = { name, icon, ready = время готовности, told = уведомление показано }
local function isTransmute(name) return name and (name:find("Трансмутация", 1, true) or name:find("Transmute", 1, true)) end
function ns.ScanCooldowns()
  local c = me()
  if not c or not C_TradeSkillUI or not C_TradeSkillUI.GetRecipeCooldown then return end
  c.cds = c.cds or {}
  local now = time()
  for _, rid in ipairs(safe(C_TradeSkillUI.GetAllRecipeIDs) or {}) do
    local ri = safe(C_TradeSkillUI.GetRecipeInfo, rid)
    if ri and ri.learned then
      local cd = safe(C_TradeSkillUI.GetRecipeCooldown, rid)
      local e = c.cds[rid]
      if (cd and cd > 0) or isTransmute(ri.name) or e then
        e = e or {}
        e.name, e.icon = ri.name, ri.icon
        if cd and cd > 0 then
          local ready = now + math.floor(cd)
          if not e.ready or math.abs(e.ready - ready) > 90 then e.ready = ready; e.told = nil; e.dur = math.max(math.floor(cd), (e.ready - now)) end
        elseif not e.ready or e.ready > now then
          e.ready = now; e.told = true -- уже готов, когда окно открыли - уведомлять не о чем
        end
        c.cds[rid] = e
      end
    end
  end
  ns.Fire("CD")
end
local cdQueued = false
local function onCraftWindow()
  if cdQueued then return end
  cdQueued = true
  ns.After(1, function() cdQueued = false; ns.ScanCooldowns() end)
end
ns.On("TRADE_SKILL_SHOW", onCraftWindow)
ns.On("TRADE_SKILL_LIST_UPDATE", onCraftWindow)
-- провели рецепт с кулдауном - взять точное время из кулдауна заклинания
local function spellCD(id)
  if C_Spell and C_Spell.GetSpellCooldown then
    local i = safe(C_Spell.GetSpellCooldown, id)
    if type(i) == "table" then return i.startTime, i.duration end
  end
  if GetSpellCooldown then return safe(GetSpellCooldown, id) end
end
ns.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
  local c = me()
  if unit ~= "player" or not c or not c.cds or not spellID or not c.cds[spellID] then return end
  ns.After(1.5, function()
    local st, dur = spellCD(spellID)
    local e = c.cds[spellID]
    if e and st and dur and dur > 2 then
      e.ready = time() + math.floor(st + dur - GetTime()); e.told = nil; e.dur = math.floor(dur)
      ns.Fire("CD")
    end
  end)
end)
-- все кулдауны всех персонажей: { ck, rid, name, icon, ready }
function ns.AllCooldowns()
  local out = {}
  for ck, c in pairs(ns.DB.chars or {}) do
    for rid, e in pairs(c.cds or {}) do out[#out + 1] = { ck = ck, rid = rid, name = e.name, icon = e.icon, ready = e.ready or 0 } end
  end
  table.sort(out, function(a, b) if a.ready ~= b.ready then return a.ready < b.ready end return (a.name or "") < (b.name or "") end)
  return out
end
function ns.AnyCooldownReady()
  local now = time()
  for _, c in pairs(ns.DB.chars or {}) do for _, e in pairs(c.cds or {}) do if (e.ready or 0) <= now then return true end end end
  return false
end
-- «Трансмутация: арканит» -> «Арканит»
function ns.CooldownTitle(name)
  local rest = name and name:match("^[^:]+:%s*(.+)$")
  if rest and isTransmute(name) then return ns.upperFirst(rest) end
  return name or "?"
end
local function charShort(ck) local c = ns.DB.chars[ck]; return (c and c.name) or (ck:match("^(.-)%-") or ck) end
-- раз в 20 секунд: кулдауны, которые подошли, - надпись сверху экрана, звук, запись в журнал
local function tick()
  if not ns.DB then return end
  local now, any = time(), false
  for ck, c in pairs(ns.DB.chars or {}) do
    for _, e in pairs(c.cds or {}) do
      if (e.ready or 0) <= now and not e.told then
        e.told = true; any = true
        if ns.DB.settings.cdNotify ~= false then
          local txt = isTransmute(e.name) and string.format(L"%s - доступно для трансмутации (%s)", ns.CooldownTitle(e.name), charShort(ck))
            or string.format(L"%s - кулдаун прошёл (%s)", e.name or "?", charShort(ck))
          ns.UI.TopNotice(txt, ns.MEDIA .. "win\\howl")
          ns.say(txt, true)
          if ns.DB.settings.alertSound then pcall(PlaySound, (SOUNDKIT and SOUNDKIT.UI_ORDERHALL_TALENT_READY_TOAST) or 8959, "Master") end
        end
      end
    end
  end
  if any then ns.Fire("CD") end
end
ns.CooldownTick = tick
ns.Listen("LOGIN", function()
  if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(20, tick) end
  ns.After(5, tick)
end)
