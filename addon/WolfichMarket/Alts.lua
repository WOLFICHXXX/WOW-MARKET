-- WolfichMarket: персонажи аккаунта (золото, уровень, место) и кулдауны рецептов
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
