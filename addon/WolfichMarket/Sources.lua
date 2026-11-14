-- WolfichMarket: «Где взять» рецепт — тренер, продавцы, добыча, задания, репутация + карта зоны
-- Данные: RecipeSources.lua (Wowhead WoW Forever + Seemeta). Координаты NPC аддон запоминает сам, когда вы их встречаете.
local _, ns = ...
local L = ns.L
local UI = ns.UI
local safe = ns.safe

local RU = function() return ns.Lang() == "ru" end
local function npcName(id) local n = ns.RS and ns.RS.npc[id]; if not n then return "#" .. id end; return RU() and n[1] or (n[2] ~= "" and n[2] or n[1]) end
local function zoneName(id) local z = id and ns.RS and ns.RS.zone[id]; if not z then return nil end; return RU() and z[1] or (z[2] ~= "" and z[2] or z[1]) end
local function questName(id) local q = ns.RS and ns.RS.quest[id]; if not q then return "#" .. id end; return RU() and q[1] or (q[3] ~= "" and q[3] or q[1]), q[2] end
local REPN = { L"Дружелюбие", L"Уважение", L"Почтение", L"Превознесение" }
local FACTION_RU = {
  ["Argent Dawn"] = "Серебряный Рассвет", ["Timbermaw Hold"] = "Древобрюхи", ["Thorium Brotherhood"] = "Братство Тория",
  ["Cenarion Circle"] = "Круг Кенария", ["Zandalar Tribe"] = "Племя Зандалар", ["Hydraxian Waterlords"] = "Гидраксианские Повелители Вод",
  ["Brood of Nozdormu"] = "Род Ноздорму", ["Darkmoon Faire"] = "Ярмарка Новолуния", ["Gelkis Clan Centaur"] = "Кентавры племени Гелкис",
  ["Magram Clan Centaur"] = "Кентавры племени Маграм", ["Ravenholdt"] = "Черный Ворон", ["Wintersaber Trainers"] = "Укротители ледопардов",
  ["Stormwind"] = "Штормград", ["Ironforge"] = "Стальгорн", ["Darnassus"] = "Дарнас", ["Gnomeregan Exiles"] = "Изгнанники Гномрегана",
  ["Orgrimmar"] = "Оргриммар", ["Thunder Bluff"] = "Громовой Утес", ["Undercity"] = "Подгород", ["Darkspear Trolls"] = "Тролли Черного Копья",
}
local function factionName(i) local f = ns.RS.factions[i] or "?"; return RU() and FACTION_RU[f] or f end

-- рецепт из окна профессии -> запись данных (номер рецепта = номер заклинания; запасной путь - по названию)
function ns.RecipeSourceData(rec)
  if not ns.RS or not rec then return nil end
  return ns.RS.r[rec.id] or (rec.name and ns.RS.names[rec.name] and ns.RS.r[ns.RS.names[rec.name]])
end

local myFaction = function() return UnitFactionGroup and UnitFactionGroup("player") end
-- отметка «только для Альянса/Орды»; свои враги - серым
local function factionTag(n)
  if not n then return "", false end
  local a, h = n[4], n[5]
  local alliOnly, hordeOnly = a == 1 and h ~= 1, h == 1 and a ~= 1
  local mine = myFaction()
  local hostile = (mine == "Alliance" and hordeOnly) or (mine == "Horde" and alliOnly)
  return alliOnly and L" |cff5aa0ff(Альянс)|r" or hordeOnly and L" |cffff5050(Орда)|r" or "", hostile
end

-- строки окна: { title, detail, zone, npc, kind }
function ns.RecipeSourceLines(rec)
  local d = ns.RecipeSourceData(rec)
  local out = {}
  local function add(kind, title, detail, zone, npc, dim) out[#out + 1] = { kind = kind, title = title, detail = detail or "", zone = zone, npc = npc, dim = dim } end
  if not d then add("none", L"Нет данных об этом рецепте", L"Его нет в базе Wowhead для WoW Forever.") return out end
  if d.na then add("none", L"|cffff9966Вероятно, недоступен в WoW Forever|r", L"Источника нет ни в файлах игры, ни на Wowhead.") end
  local t = d.t or ""
  if d.a or t:find("A") then add("auto", L"Изучается автоматически", d.s and (L"при навыке " .. d.s) or "") end
  if t:find("T") then add("trainer", L"Тренер профессии", (d.c and (L"цена" .. " " .. ns.money(d.c)) or "") .. (d.s and ("   " .. L"навык" .. " " .. d.s) or "")) end
  if d.rep then add("rep", L"Нужна репутация", (REPN[d.rep[1]] or "?") .. " - " .. factionName(d.rep[2])) end
  for _, ri in ipairs(d.i or {}) do
    local iname = (ns.itemName and ns.DB and ns.DB.names[ri.id]) or ns.RS.item[ri.id] or ("#" .. ri.id)
    add("item", L"Предмет-рецепт" .. ": |cffffd100" .. iname .. "|r", (ri.sk or d.rs) and (L"читается с навыка" .. " " .. (ri.sk or d.rs)) or "", nil, nil)
    for _, v in ipairs(ri.v or {}) do
      local n = ns.RS.npc[v[1]]
      local tag, hostile = factionTag(n)
      local z = n and n[3] and n[3][1]
      add("vendor", L"Продавец" .. ": " .. npcName(v[1]) .. tag,
        (zoneName(z) or L"зона неизвестна") .. ((v[2] and v[2] > 0) and ("   " .. ns.money(v[2])) or "") .. ((v[3] and v[3] > 0) and L"   |cffffb060ограниченный запас|r" or ""), z, v[1], hostile)
    end
    for _, dr in ipairs(ri.d or {}) do
      local n = ns.RS.npc[dr[1]]
      local z = n and n[3] and n[3][1]
      local lv = n and n[6] ~= "" and (" (" .. L"ур." .. " " .. n[6] .. ")") or ""
      add("drop", L"Добыча" .. ": " .. npcName(dr[1]) .. lv, (zoneName(z) or L"зона неизвестна") .. (dr[2] and ("   " .. L"шанс" .. " " .. dr[2] .. "%") or ""), z, dr[1])
    end
    if ri.dn and ri.dn > #(ri.d or {}) then add("drop", string.format(L"и ещё %d существ", ri.dn - #(ri.d or {})), "", nil) end
    if ri.wd then add("world", L"Мировая добыча", L"падает со многих существ подходящего уровня") end
    for _, q in ipairs(ri.q or {}) do
      local name, lvl = questName(q)
      local qz
      for _, x in ipairs(ri.sd or {}) do if x[1] == "z" then qz = x[2] end end
      add("quest", L"Задание" .. ": " .. name, (lvl and (L"ур." .. " " .. lvl .. "   ") or "") .. (zoneName(qz) or ""), qz)
    end
    for _, o in ipairs(ri.o or {}) do add("object", L"Сундук / объект" .. ": " .. o[1], zoneName(o[2]) or "", o[2]) end
    for _, id in ipairs(ri.pp or {}) do
      local n = ns.RS.npc[id]; local z = n and n[3] and n[3][1]
      add("pick", L"Можно украсть у" .. ": " .. npcName(id), zoneName(z) or "", z, id)
    end
    for _, z in ipairs(ri.fz or {}) do add("fish", L"Рыбалка", zoneName(z) or "", z) end
    if not (ri.v or ri.d or ri.wd or ri.q or ri.o or ri.pp or ri.fz) then
      add("none", L"Источник пока неизвестен", L"Новый рецепт Forever - Wowhead ещё не внёс, где он падает или продаётся.")
    end
  end
  for _, x in ipairs(d.sd or {}) do
    if x[1] == "n" then
      local n = ns.RS.npc[x[2]]; local z = x[3] or (n and n[3] and n[3][1])
      add("drop", L"Источник" .. ": " .. npcName(x[2]), zoneName(z) or "", z, x[2])
    elseif x[1] == "q" then local name = questName(x[2]); add("quest", L"Задание" .. ": " .. name, "")
    end
  end
  if #out == 0 then add("none", L"Источник неизвестен", "") end
  return out
end

-- ---------- координаты NPC: запоминаем, где вы их встречали ----------
local function npcIdFromGUID(guid)
  if not guid then return nil end
  local kind, _, _, _, _, id = strsplit("-", guid)
  if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end
local function remember(unit)
  if not ns.DB or not ns.RS or not UnitExists or not UnitExists(unit) then return end
  local id = npcIdFromGUID(UnitGUID(unit))
  if not id or not ns.RS.npc[id] then return end
  local map = C_Map and safe(C_Map.GetBestMapForUnit, "player")
  local pos = map and safe(C_Map.GetPlayerMapPosition, map, "player")
  if not pos then return end
  local x, y
  if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end
  if not x or x == 0 then return end
  ns.DB.npcPos = ns.DB.npcPos or {}
  ns.DB.npcPos[id] = { map, math.floor(x * 1000) / 1000, math.floor(y * 1000) / 1000 }
end
ns.On("MERCHANT_SHOW", function() remember("npc") end)
ns.On("PLAYER_TARGET_CHANGED", function() remember("target") end)
ns.On("UPDATE_MOUSEOVER_UNIT", function() remember("mouseover") end)

-- ---------- зона -> карта игры (по названию зоны в клиенте) ----------
local mapIndex
local function findMap(zoneID)
  if not zoneID or not C_Map or not C_Map.GetMapInfo then return nil end
  if not mapIndex then
    mapIndex = {}
    for id = 1, 2600 do
      local info = safe(C_Map.GetMapInfo, id)
      if info and info.name and (info.mapType == 3 or info.mapType == 4 or info.mapType == 5) then
        local k = info.name:lower()
        if not mapIndex[k] or info.mapType == 3 then mapIndex[k] = id end
      end
    end
  end
  local z = ns.RS.zone[zoneID]
  if not z then return nil end
  return mapIndex[(z[1] or ""):lower()] or mapIndex[(z[2] or ""):lower()]
end
ns.FindZoneMap = findMap

-- ---------- окно ----------
local dlg
local function drawMap(entry)
  local m = dlg.map
  for _, t in ipairs(m.tiles) do t:Hide() end
  m.pin:Hide()
  local mapID = entry and (entry.npc and ns.DB.npcPos and ns.DB.npcPos[entry.npc] and ns.DB.npcPos[entry.npc][1]) or (entry and findMap(entry.zone))
  dlg.mapID = mapID
  dlg.zoneLabel:SetText(entry and (zoneName(entry.zone) or "") or "")
  dlg.openMap:SetShown(mapID ~= nil)
  if not mapID or not C_Map.GetMapArtLayers then m.msg:SetText(entry and entry.zone and L"Карта этой зоны недоступна" or L"Выберите строку с зоной"); m.msg:Show() return end
  local layers = safe(C_Map.GetMapArtLayers, mapID)
  local tex = safe(C_Map.GetMapArtLayerTextures, mapID, 1)
  local Lr = layers and layers[1]
  if not Lr or not tex or #tex == 0 then m.msg:SetText(L"Карта этой зоны недоступна"); m.msg:Show() return end
  m.msg:Hide()
  local W = m:GetWidth()
  local k = W / Lr.layerWidth
  local cols = math.ceil(Lr.layerWidth / Lr.tileWidth)
  for i, fid in ipairs(tex) do
    local t = m.tiles[i] or m:CreateTexture(nil, "ARTWORK"); m.tiles[i] = t
    local c, r = (i - 1) % cols, math.floor((i - 1) / cols)
    t:SetTexture(fid); t:SetSize(Lr.tileWidth * k, Lr.tileHeight * k)
    t:ClearAllPoints(); t:SetPoint("TOPLEFT", m, "TOPLEFT", c * Lr.tileWidth * k, -r * Lr.tileHeight * k); t:Show()
  end
  -- если NPC уже встречали - метка там, где вы его видели
  local p = entry.npc and ns.DB.npcPos and ns.DB.npcPos[entry.npc]
  if p and p[1] == mapID then
    m.pin:ClearAllPoints(); m.pin:SetPoint("CENTER", m, "TOPLEFT", p[2] * Lr.layerWidth * k, -p[3] * Lr.layerHeight * k); m.pin:Show()
    dlg.zoneLabel:SetText((zoneName(entry.zone) or "") .. string.format("   |cffffd100%.1f, %.1f|r", p[2] * 100, p[3] * 100))
  end
end

function ns.ShowSources(rec)
  if not rec then return end
  if not dlg then
    dlg = CreateFrame("Frame", "WolfichMarketSourceDialog", UIParent)
    dlg:SetSize(760, 460); dlg:SetPoint("CENTER"); dlg:SetFrameStrata("DIALOG"); dlg:EnableMouse(true); dlg:SetToplevel(true)
    dlg:SetMovable(true); dlg:RegisterForDrag("LeftButton"); dlg:SetClampedToScreen(true)
    dlg:SetScript("OnDragStart", dlg.StartMoving); dlg:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    tinsert(UISpecialFrames, "WolfichMarketSourceDialog")
    UI.Skin(dlg, { theme = "main", scale = 0.6 })
    dlg.title = UI.Title(dlg, L"Где взять рецепт")
    UI.Close(dlg)
    dlg.recName = UI.Font(dlg, 13, UI.GOLD); dlg.recName:SetPoint("TOPLEFT", 20, -50); dlg.recName:SetPoint("RIGHT", -20, 0)
    dlg.list = UI.List(dlg, 34, function(r)
      r.title = UI.Font(r, 12); r.title:SetPoint("TOPLEFT", 6, -3); r.title:SetPoint("RIGHT", -6, 0)
      r.detail = UI.Font(r, 10, UI.DIM); r.detail:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -3); r.detail:SetPoint("RIGHT", -6, 0)
      local sel = r:CreateTexture(nil, "BACKGROUND"); sel:SetAllPoints(); sel:SetColorTexture(1, 0.8, 0.4, 0.12); sel:Hide(); r.sel = sel
      r:SetScript("OnClick", function(self) if self.data then dlg.cur = self.data; dlg.list:Refresh(); drawMap(self.data) end end)
    end, function(r, d)
      r.title:SetText(d.title); r.detail:SetText(d.detail)
      r.title:SetAlpha(d.dim and 0.5 or 1); r.detail:SetAlpha(d.dim and 0.5 or 1)
      r.sel:SetShown(dlg.cur == d)
    end)
    dlg.list:SetPoint("TOPLEFT", 16, -74); dlg.list:SetPoint("BOTTOMRIGHT", dlg, "BOTTOM", 40, 18)
    -- карта зоны (картинка самой игры) справа
    local m = CreateFrame("Frame", nil, dlg); m:SetPoint("TOPLEFT", dlg, "TOP", 52, -96); m:SetSize(330, 220)
    local bg = m:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.45)
    m.tiles = {}
    m.msg = UI.Font(m, 11, UI.DIM); m.msg:SetPoint("CENTER"); m.msg:SetJustifyH("CENTER")
    m.pin = m:CreateTexture(nil, "OVERLAY"); m.pin:SetTexture(ns.MEDIA .. "paw"); m.pin:SetSize(22, 22); m.pin:Hide()
    dlg.map = m
    dlg.zoneLabel = UI.Font(dlg, 12, UI.GOLD); dlg.zoneLabel:SetPoint("BOTTOMLEFT", m, "TOPLEFT", 0, 6); dlg.zoneLabel:SetPoint("RIGHT", m, "RIGHT", 0, 0)
    dlg.openMap = UI.Button(dlg, L"Открыть карту зоны", 170, 24, function()
      if dlg.mapID then
        if OpenWorldMap then pcall(OpenWorldMap, dlg.mapID) elseif WorldMapFrame then ShowUIPanel(WorldMapFrame); pcall(WorldMapFrame.SetMapID, WorldMapFrame, dlg.mapID) end
      end
    end)
    dlg.openMap:SetPoint("TOPLEFT", m, "BOTTOMLEFT", 0, -10)
    dlg.hint = UI.Font(dlg, 10, UI.DIM); dlg.hint:SetPoint("TOPLEFT", dlg.openMap, "BOTTOMLEFT", 0, -8); dlg.hint:SetPoint("RIGHT", m, "RIGHT", 0, 0); dlg.hint:SetWordWrap(true)
    dlg.hint:SetText(L"Лапа на карте - там, где вы сами встречали этого NPC (аддон запоминает, когда вы наводите мышь, берёте в цель или торгуете).")
  end
  dlg.recName:SetText(rec.name .. (ns.IsLearned(rec) and L"  |cff78d98a(изучен)|r" or L"  |cffff9966(не изучен)|r"))
  local lines = ns.RecipeSourceLines(rec)
  dlg.cur = nil
  for _, e in ipairs(lines) do if e.zone then dlg.cur = e; break end end
  dlg.list:SetData(lines)
  dlg:Show()
  ns.After(0, function() drawMap(dlg.cur) end)
end
