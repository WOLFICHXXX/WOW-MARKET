-- WolfichMarket: скан профессий, рецептов и цен торговцев для сайта WOW-MARKET.
-- Команды: /wm — окно экспорта, /wm reset — очистить данные этого персонажа.
local addonName, ns = ...

local VERSION = "1.2.0"
local PREFIX = "|cffe6b450WolfichMarket|r: "
local function say(msg) print(PREFIX .. msg) end

local DB          -- WolfichMarketDB
local charKey     -- "Имя-Мир"
local pendingNames = {}

-- ---------- утилиты ----------
local unpack = unpack or table.unpack
local function pack(...) return { n = select("#", ...), ... } end
local function safe(fn, ...)
  if type(fn) ~= "function" then return nil end
  local r = pack(pcall(fn, ...))
  if r[1] then return unpack(r, 2, r.n) end
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

-- ---------- аукцион: категории и полный снимок ----------
on("AUCTION_HOUSE_SHOW")
on("AUCTION_HOUSE_CLOSED")
on("REPLICATE_ITEM_LIST_UPDATE")
local ahOpen, ahWanted, ahBusy, replPending = false, false, false, false

local function dumpCats(list, depth)
  local out = {}
  if type(list) ~= "table" or depth > 4 then return out end
  for _, c in ipairs(list) do
    local e = { name = clean(c.name), filters = {} }
    for _, fl in ipairs(c.filters or {}) do
      table.insert(e.filters, { fl.classID or -1, fl.subClassID or -1, fl.inventoryType or -1 })
    end
    if c.subCategories then e.sub = dumpCats(c.subCategories, depth + 1) end
    table.insert(out, e)
  end
  return out
end

local function saveCategories()
  if type(AuctionCategories) == "table" then
    DB.ahCats = dumpCats(AuctionCategories, 1)
  end
  -- названия классов и подклассов предметов (как их зовёт игра)
  local getC = (C_Item and C_Item.GetItemClassInfo) or GetItemClassInfo
  local getS = (C_Item and C_Item.GetItemSubClassInfo) or GetItemSubClassInfo
  if getC then
    DB.ahClasses = {}
    for cid = 0, 20 do
      local cn = safe(getC, cid)
      if cn and cn ~= "" then
        local subs = {}
        for sid = 0, 25 do local sn = safe(getS, cid, sid); if sn and sn ~= "" then subs[sid] = clean(sn) end end
        DB.ahClasses[cid] = { name = clean(cn), subs = subs }
      end
    end
  end
end

-- кнопка в окне аукциона
local ahButton
local COOLDOWN = 15 * 60
local function setBtn(text, enabled)
  if not ahButton then return end
  ahButton:SetText(text)
  if enabled then ahButton:Enable() else ahButton:Disable() end
end
local function refreshBtn()
  if not ahButton or ahBusy then return end
  local left = (DB.ahLastReq or 0) + COOLDOWN - time()
  if left > 0 then
    setBtn(string.format("Скан через %d:%02d", math.floor(left / 60), left % 60), false)
    C_Timer.After(1, refreshBtn)
  else
    setBtn("Сканировать аукцион", true)
  end
end
local startReplicate
local function createAHButton()
  if ahButton then refreshBtn() return end
  local parent = AuctionHouseFrame or AuctionFrame
  if not parent then return end
  local b = CreateFrame("Button", "WolfichMarketScanButton", parent, "UIPanelButtonTemplate")
  b:SetSize(170, 22)
  b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -28, -1)
  b:SetFrameStrata("HIGH")
  b:SetScript("OnClick", function() startReplicate() end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:AddLine("WolfichMarket", 0.9, 0.7, 0.3)
    GameTooltip:AddLine("Полный снимок аукциона: цены, количество, категории.", 1, 1, 1, true)
    GameTooltip:AddLine("Сервер разрешает раз в 15 минут.", 0.7, 0.7, 0.7, true)
    if DB.ahScan then GameTooltip:AddLine("Последний снимок: " .. date("%d.%m %H:%M", DB.ahScan.t or 0) .. ", лотов " .. (DB.ahScan.lots or 0), 0.5, 0.9, 0.5) end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  ahButton = b
  refreshBtn()
end

local processing = false
local function finishReplicate()
  if processing then return end
  local n = safe(C_AuctionHouse.GetNumReplicateItems) or 0
  if n > 0 then processing = true end
  if n == 0 then say("аукцион ответил пустым списком — попробуйте ещё раз через минуту.") ahBusy = false refreshBtn() return end
  say(string.format("получено лотов: %d, обрабатываю…", n))
  local items, classes = {}, {}
  local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  local i = 0
  local function step()
    local last = math.min(i + 3000, n - 1)
    for k = i, last do
      local name, _, count, quality, _, level, _, minBid, _, buyout, bidAmount, _, _, _, _, _, itemID = safe(C_AuctionHouse.GetReplicateItemInfo, k)
      if itemID then
        count = math.max(count or 1, 1)
        local rec = items[itemID]
        if not rec then rec = { 0, 0, 0, 0 }; items[itemID] = rec end -- мин. цена за шт, кол-во, лотов, качество
        if buyout and buyout > 0 then
          local unit = math.floor(buyout / count + 0.5)
          if rec[1] == 0 or unit < rec[1] then rec[1] = unit end
        end
        rec[2] = rec[2] + count
        rec[3] = rec[3] + 1
        rec[4] = quality or rec[4]
        if not classes[itemID] and instant then
          local _, _, _, _, _, cid, sid = safe(instant, itemID)
          classes[itemID] = { cid or -1, sid or -1 }
        end
        if name and name ~= "" and not DB.names[itemID] then DB.names[itemID] = clean(name) end
      end
    end
    i = last + 1
    setBtn(string.format("Обработка %d%%", math.floor(i / n * 100)), false)
    if i < n then C_Timer.After(0, step) return end
    local count = 0
    for _ in pairs(items) do count = count + 1 end
    DB.ahScan = {
      t = time(), lots = n, char = charKey,
      realm = clean(GetRealmName and GetRealmName() or ""),
      realmN = clean(GetNormalizedRealmName and GetNormalizedRealmName() or ""),
      faction = UnitFactionGroup and UnitFactionGroup("player") or "",
      items = items, classes = classes,
    }
    ahBusy, processing = false, false
    setBtn("Готово ✓", false)
    C_Timer.After(3, refreshBtn)
    say(string.format("|cff78d98aснимок аукциона готов|r: %d лотов, %d предметов. Наберите /reload — и пришлите файл WolfichMarket.lua из папки WTF.", n, count))
  end
  step()
end

startReplicate = function()
  if not (C_AuctionHouse and C_AuctionHouse.ReplicateItems) then say("в этой версии игры нет полного скана аукциона.") return end
  if not ahOpen then ahWanted = true say("откройте окно аукциона — скан начнётся сам.") return end
  if ahBusy then say("скан уже идёт…") return end
  ahBusy, ahWanted = true, false
  saveCategories()
  DB.ahLastReq = time()
  setBtn("Сканирую…", false)
  say("запрашиваю весь аукцион (сервер разрешает это раз в 15 минут), подождите…")
  local ok = pcall(C_AuctionHouse.ReplicateItems)
  if not ok then ahBusy = false refreshBtn() say("сервер отказал — подождите 15 минут после прошлого скана.") return end
  -- если событие не придёт, проверим сами через 20 секунд
  C_Timer.After(20, function() if ahBusy and (safe(C_AuctionHouse.GetNumReplicateItems) or 0) > 0 then finishReplicate() end end)
  C_Timer.After(90, function()
    if ahBusy and (safe(C_AuctionHouse.GetNumReplicateItems) or 0) == 0 then
      ahBusy = false; refreshBtn()
      say("сервер не прислал аукцион — скорее всего, прошло меньше 15 минут с прошлого скана. Попробуйте позже.")
    end
  end)
end

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
    say("v" .. VERSION .. " загружен. /wm — экспорт профессий, /wm ah — снимок аукциона (окно аукциона должно быть открыто).")
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
  elseif event == "AUCTION_HOUSE_SHOW" then
    ahOpen = true
    pcall(createAHButton)
    saveCategories()
    if ahWanted then C_Timer.After(1, startReplicate) end
  elseif event == "AUCTION_HOUSE_CLOSED" then
    ahOpen = false
  elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
    if ahBusy and not replPending then replPending = true; C_Timer.After(1, function() replPending = false; if ahBusy then finishReplicate() end end) end
  end
end)

SLASH_WOLFICHMARKET1 = "/wm"
SLASH_WOLFICHMARKET2 = "/wolfichmarket"
local function slash(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if not DB or not charKey then say("ещё не загрузился, попробуйте через пару секунд.") return end
  if msg == "reset" then
    DB.chars[charKey] = { profs = {} }
    DB.vendor = {}
    say("данные этого персонажа и цены торговцев очищены.")
  elseif msg == "ah" then
    startReplicate()
  elseif msg == "status" then
    local c = DB.chars[charKey] or { profs = {} }
    local n = 0
    for prof, p in pairs(c.profs) do say(string.format("%s %d/%d — рецептов: %d", prof, p.skill or 0, p.max or 0, #(p.recipes or {}))) n = n + 1 end
    local v = 0
    for _ in pairs(DB.vendor) do v = v + 1 end
    say(string.format("профессий с рецептами: %d, цен торговцев: %d", n, v))
    if DB.ahScan then say(string.format("снимок аукциона: %d лотов, %s", DB.ahScan.lots or 0, date("%d.%m %H:%M", DB.ahScan.t or 0))) end
  else
    showExport()
  end
end

-- ошибки не должны пропадать молча
SlashCmdList.WOLFICHMARKET = function(msg)
  local ok, err = xpcall(function() slash(msg) end, function(e) return tostring(e) .. "\n" .. (debugstack and debugstack(2, 3, 0) or "") end)
  if not ok then say("|cffff6060ошибка:|r " .. tostring(err)) end
end
SLASH_WOLFICHMARKETAH1 = "/wmah"
SlashCmdList.WOLFICHMARKETAH = function() SlashCmdList.WOLFICHMARKET("ah") end
