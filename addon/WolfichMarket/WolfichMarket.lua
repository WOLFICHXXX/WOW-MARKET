-- WolfichMarket: скан профессий, рецептов и цен торговцев для сайта WOW-MARKET.
-- Команды: /wm — окно экспорта, /wm reset — очистить данные этого персонажа.
local addonName, ns = ...

local PREFIX = "|cffe6b450WolfichMarket|r: "
local function say(msg) print(PREFIX .. msg) end

local DB          -- WolfichMarketDB
local charKey     -- "Имя-Мир"
local pendingNames = {}

-- ---------- утилиты ----------
local unpack = unpack or table.unpack
local function safe(fn, ...)
  if type(fn) ~= "function" then return nil end
  local r = { pcall(fn, ...) }
  if r[1] then return unpack(r, 2, table.maxn and table.maxn(r) or #r) end
  return nil
end

local function itemName(id)
  if not id then return nil end
  if DB.names[id] then return DB.names[id] end
  local name
  if C_Item and C_Item.GetItemNameByID then name = safe(C_Item.GetItemNameByID, id) end
  if not name and C_Item and C_Item.GetItemInfo then name = safe(C_Item.GetItemInfo, id) end
  if name then DB.names[id] = name return name end
  if C_Item and C_Item.RequestLoadItemDataByID then safe(C_Item.RequestLoadItemDataByID, id) end
  pendingNames[id] = true
  return nil
end

local function clean(s)
  -- наш разделитель ^ и перевод строки не должны попадать в текст
  return (tostring(s or ""):gsub("[%^\r\n]", " "))
end

-- ---------- скан профессии ----------
local function professionInfo()
  if not C_TradeSkillUI then return nil end
  local info = safe(C_TradeSkillUI.GetChildProfessionInfo)
  if not info or not info.professionName or info.professionName == "" then
    info = safe(C_TradeSkillUI.GetBaseProfessionInfo)
  end
  if info and info.professionName and info.professionName ~= "" then
    return info.professionName, info.skillLevel or 0, info.maxSkillLevel or 0
  end
  return nil
end

local function isForeignWindow()
  if not C_TradeSkillUI then return true end
  if safe(C_TradeSkillUI.IsTradeSkillLinked) then return true end
  if safe(C_TradeSkillUI.IsTradeSkillGuild) then return true end
  if safe(C_TradeSkillUI.IsNPCCrafting) then return true end
  return false
end

local lastScan = 0
local function scanProfession(silent)
  if not C_TradeSkillUI or isForeignWindow() then return end
  local prof, skill, maxSkill = professionInfo()
  if not prof then return end
  local ids = safe(C_TradeSkillUI.GetAllRecipeIDs)
  if not ids or #ids == 0 then return end

  local recipes, count = {}, 0
  for _, rid in ipairs(ids) do
    local ri = safe(C_TradeSkillUI.GetRecipeInfo, rid)
    if ri and ri.learned then
      local sch = safe(C_TradeSkillUI.GetRecipeSchematic, rid, false)
      local rec = {
        id = rid,
        name = clean(ri.name),
        diff = ri.relativeDifficulty, -- 0 оранж., 1 жёлт., 2 зел., 3 серый
        out = sch and sch.outputItemID or nil,
        qmin = sch and sch.quantityMin or 1,
        qmax = sch and sch.quantityMax or 1,
        reag = {},
      }
      if sch and sch.reagentSlotSchematics then
        for _, slot in ipairs(sch.reagentSlotSchematics) do
          local r = slot.reagents and slot.reagents[1]
          local need = slot.quantityRequired or 0
          -- обязательные реагенты (необязательные/модификаторы пропускаем)
          if r and r.itemID and need > 0 and (slot.required ~= false) then
            table.insert(rec.reag, { r.itemID, need })
            itemName(r.itemID)
          end
        end
      end
      if rec.out then itemName(rec.out) end
      table.insert(recipes, rec)
      count = count + 1
    end
  end

  DB.chars[charKey] = DB.chars[charKey] or { profs = {} }
  DB.chars[charKey].profs[prof] = { skill = skill, max = maxSkill, t = time(), recipes = recipes }
  if not silent and (GetTime() - lastScan > 5) then
    say(string.format("%s (%d/%d) — сохранено рецептов: %d. Экспорт: /wm", prof, skill, maxSkill, count))
  end
  lastScan = GetTime()
end

-- ---------- собирательские и прочие профессии (без окна рецептов) ----------
local function scanSkillLevels()
  if not GetProfessions or not GetProfessionInfo then return end
  local list = { safe(GetProfessions) }
  local out = {}
  for i = 1, 6 do
    local idx = list[i]
    if idx then
      local name, _, rank, maxRank = safe(GetProfessionInfo, idx)
      if name then table.insert(out, { name = clean(name), skill = rank or 0, max = maxRank or 0 }) end
    end
  end
  DB.chars[charKey] = DB.chars[charKey] or { profs = {} }
  DB.chars[charKey].skills = out
end

-- ---------- цены торговцев ----------
local function scanMerchant()
  local n = safe(GetMerchantNumItems) or 0
  local saved = 0
  for i = 1, n do
    local id = safe(GetMerchantItemID, i)
    local price, stack, extended
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
      local info = safe(C_MerchantFrame.GetItemInfo, i)
      if info then price, stack, extended = info.price, info.stackCount, info.hasExtendedCost end
    end
    if not price and GetMerchantItemInfo then
      local _, _, p, s, _, _, _, ext = safe(GetMerchantItemInfo, i)
      price, stack, extended = p, s, ext
    end
    if id and price and price > 0 and not extended then
      local unit = math.floor(price / math.max(stack or 1, 1) + 0.5)
      if not DB.vendor[id] or unit < DB.vendor[id] then DB.vendor[id] = unit end
      itemName(id)
      saved = saved + 1
    end
  end
  if saved > 0 then DB.vendorSeen = time() end
end

-- ---------- экспорт ----------
local function buildExport()
  scanSkillLevels()
  local lines = { "WM1^" .. clean(charKey) .. "^" .. time() }
  local used = {}
  local c = DB.chars[charKey] or { profs = {} }
  for _, s in ipairs(c.skills or {}) do
    table.insert(lines, table.concat({ "S", s.name, s.skill, s.max }, "^"))
  end
  for prof, p in pairs(c.profs or {}) do
    table.insert(lines, table.concat({ "P", clean(prof), p.skill or 0, p.max or 0, p.t or 0 }, "^"))
    for _, r in ipairs(p.recipes or {}) do
      local reag = {}
      for _, rg in ipairs(r.reag) do
        table.insert(reag, rg[1] .. "x" .. rg[2])
        used[rg[1]] = true
      end
      if r.out then used[r.out] = true end
      table.insert(lines, table.concat({
        "R", clean(prof), r.id or 0, clean(r.name), r.out or 0, r.qmin or 1, r.qmax or 1,
        (r.diff == nil) and -1 or r.diff, table.concat(reag, ","),
      }, "^"))
    end
  end
  for id, price in pairs(DB.vendor) do
    table.insert(lines, "V^" .. id .. "^" .. price)
    used[id] = true
  end
  for id in pairs(used) do
    local n = itemName(id)
    if n then table.insert(lines, "N^" .. id .. "^" .. clean(n)) end
  end
  return table.concat(lines, "\n")
end

local exportFrame
local function showExport()
  if not exportFrame then
    local f = CreateFrame("Frame", "WolfichMarketExportFrame", UIParent, "BackdropTemplate")
    f:SetSize(560, 400)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetBackdrop then
      f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 10, right = 10, top = 10, bottom = 10 },
      })
    end
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 20, -18)
    title:SetText("WolfichMarket — экспорт")
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    hint:SetWidth(510)
    hint:SetJustifyH("LEFT")
    hint:SetText("Текст уже выделен: нажмите Ctrl+C, затем вставьте на сайте во вкладке «Скан».")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    local scroll = CreateFrame("ScrollFrame", "WolfichMarketExportScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -64)
    scroll:SetPoint("BOTTOMRIGHT", -40, 20)
    local eb = CreateFrame("EditBox", nil, scroll)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(true)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(490)
    eb:SetMaxLetters(0)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    eb:SetScript("OnTextChanged", function(self, user) if user then self:SetText(f.payload or "") self:HighlightText() end end)
    scroll:SetScrollChild(eb)
    f.eb = eb
    tinsert(UISpecialFrames, "WolfichMarketExportFrame")
    exportFrame = f
  end
  exportFrame.payload = buildExport()
  exportFrame.eb:SetText(exportFrame.payload)
  exportFrame:Show()
  exportFrame.eb:SetFocus()
  exportFrame.eb:HighlightText()
  local np = 0
  for _ in pairs(pendingNames) do np = np + 1 end
  if np > 0 then say("Часть названий ещё грузится — если на сайте будут «#номер», откройте /wm ещё раз через пару секунд.") end
end

-- ---------- события ----------
local f = CreateFrame("Frame")
local function on(event)
  local ok = pcall(f.RegisterEvent, f, event)
  return ok
end
on("ADDON_LOADED")
on("PLAYER_LOGIN")
on("TRADE_SKILL_SHOW")
on("TRADE_SKILL_LIST_UPDATE")
on("TRADE_SKILL_DATA_SOURCE_CHANGED")
on("MERCHANT_SHOW")
on("MERCHANT_UPDATE")
on("GET_ITEM_INFO_RECEIVED")
on("SKILL_LINES_CHANGED")

local scanTimer
f:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == addonName then
    WolfichMarketDB = WolfichMarketDB or {}
    DB = WolfichMarketDB
    DB.chars = DB.chars or {}
    DB.vendor = DB.vendor or {}
    DB.names = DB.names or {}
  elseif event == "PLAYER_LOGIN" then
    local name = UnitName("player") or "?"
    local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
    charKey = realm ~= "" and (name .. "-" .. realm) or name
    DB.chars[charKey] = DB.chars[charKey] or { profs = {} }
    scanSkillLevels()
    say("загружен. Откройте окна своих профессий и загляните к торговцам, затем /wm — экспорт.")
  elseif not DB or not charKey then
    return
  elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" or event == "TRADE_SKILL_DATA_SOURCE_CHANGED" then
    -- список рецептов приходит частями: сканируем с небольшой задержкой
    if scanTimer then scanTimer:Cancel() end
    if C_Timer and C_Timer.NewTimer then
      scanTimer = C_Timer.NewTimer(0.6, function() scanProfession(false) end)
    else
      scanProfession(false)
    end
  elseif event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
    scanMerchant()
  elseif event == "GET_ITEM_INFO_RECEIVED" then
    if arg1 and pendingNames[arg1] then
      pendingNames[arg1] = nil
      itemName(arg1)
    end
  elseif event == "SKILL_LINES_CHANGED" then
    scanSkillLevels()
  end
end)

SLASH_WOLFICHMARKET1 = "/wm"
SLASH_WOLFICHMARKET2 = "/wolfichmarket"
SlashCmdList.WOLFICHMARKET = function(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if not DB or not charKey then say("ещё не загрузился, попробуйте через пару секунд.") return end
  if msg == "reset" then
    DB.chars[charKey] = { profs = {} }
    DB.vendor = {}
    say("данные этого персонажа и цены торговцев очищены.")
  elseif msg == "status" then
    local c = DB.chars[charKey] or { profs = {} }
    local n = 0
    for prof, p in pairs(c.profs) do say(string.format("%s %d/%d — рецептов: %d", prof, p.skill or 0, p.max or 0, #(p.recipes or {}))) n = n + 1 end
    local v = 0
    for _ in pairs(DB.vendor) do v = v + 1 end
    say(string.format("профессий с рецептами: %d, цен торговцев: %d", n, v))
  else
    showExport()
  end
end
