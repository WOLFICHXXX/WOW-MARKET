-- Заглушка игрового API для прогона WolfichMarket 2.0
unpack = table.unpack; wipe = function(t) for k in pairs(t) do t[k] = nil end return t end; tinsert = table.insert
time = os.time; date = os.date; local clock = 0; GetTime = function() return clock end
local timers = {}
C_Timer = { After = function(s, fn) timers[#timers + 1] = { at = clock + s, fn = fn } end,
  NewTimer = function(s, fn) local t = { at = clock + s, fn = fn }; timers[#timers + 1] = t; return { Cancel = function() t.fn = nil end } end,
  NewTicker = function(s, fn) local tk = { cancel = false }; return { Cancel = function() tk.cancel = true end } end }
function advance(sec) clock = clock + sec; local again = true
  while again do again = false
    for i = #timers, 1, -1 do local t = timers[i]; if t.at <= clock then table.remove(timers, i); if t.fn then t.fn() end; again = true end end
  end end
local errors = {}
-- универсальный объект-фрейм
local frames = {}
local function newObj(kind, name, parent)
  local o = { kind = kind, name = name, parent = parent, scripts = {}, shown = true, w = 100, h = 100, text = "" }
  return setmetatable(o, { __index = function(t, k)
    local f = rawget(_G, "OBJ_" .. k)
    if f then return f end
    if type(k) == "string" and k:match("^%u") then return function() return nil end end
    return nil
  end })
end
OBJ_SetScript = function(self, s, fn) self.scripts[s] = fn end
OBJ_GetScript = function(self, s) return self.scripts[s] end
OBJ_HookScript = function(self, s, fn) local old = self.scripts[s]; self.scripts[s] = function(...) if old then old(...) end fn(...) end end
OBJ_RegisterEvent = function(self, e) if not self.events then self.events = {}; frames[#frames + 1] = self end; self.events[e] = true end
OBJ_CreateTexture = function(self) return newObj("Texture", nil, self) end
OBJ_CreateLine = function(self) return newObj("Line", nil, self) end
OBJ_CreateFontString = function(self) return newObj("FontString", nil, self) end
OBJ_SetText = function(self, t) self.text = t end
OBJ_GetText = function(self) return self.text end
OBJ_SetSize = function(self, w, h) self.w, self.h = w, h end
OBJ_SetWidth = function(self, w) self.w = w end
OBJ_SetHeight = function(self, h) self.h = h end
OBJ_GetWidth = function(self) return self.w or 100 end
OBJ_GetHeight = function(self) return self.h or 300 end
OBJ_Show = function(self) self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
OBJ_Hide = function(self) self.shown = false end
OBJ_SetShown = function(self, v) if v then self:Show() else self:Hide() end end
OBJ_IsShown = function(self) return self.shown end
OBJ_IsVisible = function(self) return self.shown end
OBJ_GetChecked = function(self) return self.checked end
OBJ_SetChecked = function(self, v) self.checked = v end
OBJ_GetFrameLevel = function() return 1 end
OBJ_GetFrameStrata = function() return "MEDIUM" end
OBJ_SetEnabled = function(self, v) self.enabled = v end
OBJ_Enable = function(self) self.enabled = true end
OBJ_Disable = function(self) self.enabled = false end
OBJ_GetMinMaxValues = function() return 0, 0 end
function CreateFrame(kind, name, parent, tmpl) local o = newObj(kind, name, parent); if name then _G[name] = o end return o end
UIParent = newObj("Frame"); GameTooltip = newObj("GameTooltip"); ItemRefTooltip = newObj("GameTooltip")
GetLocale = function() return LOCALE or "ruRU" end; STANDARD_TEXT_FONT = "x"; UISpecialFrames = {}; NUM_BAG_SLOTS = 4; SlashCmdList = {}
function UnitName() return "Вульфыч" end
function GetNormalizedRealmName() return "CAMWOWEU4Realm6PvP" end
function UnitFactionGroup() return "Alliance" end
function UnitClass() return "Друид", "DRUID" end
RAID_CLASS_COLORS = { DRUID = { colorStr = "ffff7c0a" } }
Minimap = newObj("Frame"); Minimap.GetCenter = function() return 100, 100 end
GetCursorPosition = function() return 0, 0 end
function IsAltKeyDown() return false end; function IsShiftKeyDown() return false end; function IsControlKeyDown() return false end
local hooks = {}
function hooksecurefunc(a, b, c) if type(a) == "string" then hooks[a] = b else end end
function HandleModifiedItemClick(link) if hooks.HandleModifiedItemClick then hooks.HandleModifiedItemClick(link) end end
printed = {}
print = function(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end; local s = table.concat(t, " "); printed[#printed + 1] = s; io.write("CHAT: ", s, "\n") end
PlaySound = function() played = true end
SOUNDKIT = { RAID_WARNING = 8959 }
Enum = { TooltipDataType = { Item = 0 }, AuctionHouseSortOrder = { Price = 0 }, ItemCommodityStatus = { Item = 1, Commodity = 2 } }
local ttcb; TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) ttcb = fn end }
-- предметы
local NAMES = { [2840] = "Медный слиток", [2589] = "Льняная ткань", [3470] = "Грубый шлифовальный камень", [2835] = "Грубый камень", [2862] = "Грубое точило", [6217] = "Медный жезл", [10940] = "Странная пыль", [3575] = "Железный слиток", [7071] = "Железная скоба", [2853] = "Медные наручи" }
local VSELL = { [2840] = 5, [3470] = 10, [2862] = 100 }
C_Item = { GetItemInfo = function(id) return NAMES[id], nil, 1, 1, 1, "", "", 20, "", 1, VSELL[id] end, GetItemNameByID = function(id) return NAMES[id] end, GetItemIconByID = function() return 1 end, GetItemQualityByID = function() return 1 end }
ITEM_QUALITY_COLORS = { [1] = { hex = "|cffffffff" } }
-- профессии
local RECIPES = {
  [3320] = { name = "Грубый шлифовальный камень", out = 3470, d = 3, r = { { 2835, 2 } } },
  [2660] = { name = "Грубое точило", out = 2862, d = 3, r = { { 2835, 1 } } },
  [1245287] = { name = "Медный жезл", out = 6217, d = 3, r = { { 2840, 1 } } },
  [8768] = { name = "Железная скоба", out = 7071, d = 3, q = 2, r = { { 3575, 1 } } },
  [7071] = { name = "Медные наручи", out = 2853, d = 0, r = { { 2840, 2 } }, unlearned = true },
}
C_TradeSkillUI = {
  GetBaseProfessionInfo = function() return { professionName = "Кузнечное дело", skillLevel = 150, maxSkillLevel = 150 } end,
  GetAllRecipeIDs = function() local t = {} for k in pairs(RECIPES) do t[#t + 1] = k end return t end,
  GetRecipeInfo = function(id) local r = RECIPES[id]; return { name = r.name, learned = not r.unlearned, relativeDifficulty = r.d, icon = 1 } end,
  GetRecipeSourceText = function(id) return "|cffffd200Тренер:|r Тед Хаммер|n|cffffd200Место:|r Штормград" end,
  GetRecipeSchematic = function(id) local r = RECIPES[id]; local slots = {}
    for _, x in ipairs(r.r) do slots[#slots + 1] = { quantityRequired = x[2], reagents = { { itemID = x[1] } } } end
    return { outputItemID = r.out, quantityMin = r.q or 1, quantityMax = r.q or 1, reagentSlotSchematics = slots } end,
  OpenRecipe = function(id) openedRecipe = id end,
}
function GetProfessions() return 1, 2 end
function GetProfessionInfo(i) return ({ "Кузнечное дело", "Наложение чар" })[i], nil, 150, 150 end
-- рамки игры
ProfessionsFrame = newObj("Frame"); ProfessionsFrame.CraftingPage = { RecipeList = { ScrollBox = newObj("ScrollBox") }, SchematicForm = newObj("Frame") }
local rowFrames = {}
for rid in pairs(RECIPES) do local fr = newObj("Button"); fr.GetElementData = function() return { GetData = function() return { recipeInfo = { recipeID = rid } } end } end; rowFrames[#rowFrames + 1] = fr end
ProfessionsFrame.CraftingPage.RecipeList.ScrollBox.ForEachFrame = function(self, fn) for _, f in ipairs(rowFrames) do fn(f) end end
AuctionHouseFrame = newObj("Frame"); AuctionHouseFrame.SearchBar = { SetSearchText = function(_, t) searched = t end, StartSearch = function() end }
-- аукцион
local REP = {}
local function lot(id, cnt, buy) REP[#REP + 1] = { id, cnt, buy } end
lot(2840, 20, 20 * 150); lot(2840, 5, 5 * 140); lot(2835, 40, 40 * 30); lot(3470, 10, 10 * 120); lot(2862, 3, 3 * 90); lot(6217, 1, 400); lot(3575, 10, 10 * 200); lot(7071, 20, 20 * 300); lot(2853, 2, 2 * 900)
C_AuctionHouse = {
  ReplicateItems = function() end, GetNumReplicateItems = function() return #REP end,
  GetReplicateItemInfo = function(i) local r = REP[i + 1]; return NAMES[r[1]], 0, r[2], 1, true, 1, 0, 0, 0, r[3], 0, nil, nil, nil, nil, 0, r[1], true end,
  MakeItemKey = function(id) return { itemID = id } end, SendSearchQuery = function(k) lastQuery = k end,
  GetNumCommoditySearchResults = function() return 2 end,
  GetCommoditySearchResultInfo = function(id, i) return { unitPrice = 100 + i, quantity = 10 * i } end,
  StartCommoditiesPurchase = function(id, q) startedBuy = { id, q } end, ConfirmCommoditiesPurchase = function(id, q) confirmedBuy = { id, q } end,
  GetItemCommodityStatus = function() return 2 end, CalculateCommodityDeposit = function() return 15 end,
  PostCommodity = function(loc, d, q, u) postedLot = { d, q, u } end,
}
C_Container = { GetContainerNumSlots = function(b) return b == 0 and 2 or 0 end,
  GetContainerItemInfo = function(b, s) if s == 1 then return { itemID = 2840, stackCount = 12 } end; if s == 2 then return { itemID = 3470, stackCount = 5 } end end }
local bagBtns = {}
for s = 1, 2 do local b = newObj("Button"); b.GetBagID = function() return 0 end; b.GetID = function() return s end; b.GetWidth = function() return 37 end; bagBtns[#bagBtns + 1] = b end
ContainerFrameCombinedBags = newObj("Frame"); ContainerFrameCombinedBags.EnumerateValidItems = function() local i = 0; return function() i = i + 1; if bagBtns[i] then return i, bagBtns[i] end end end
BAGBTNS = bagBtns
ItemLocation = { CreateFromBagAndSlot = function(_, b, s) return { b, s } end }

function fire(e, ...) for _, f in ipairs(frames) do if f.events and f.events[e] and f.scripts.OnEvent then f.scripts.OnEvent(f, e, ...) end end end
function loadAddon(dir)
  local ns = {}
  for line in io.lines(dir .. "/WolfichMarket.toc") do
    if line:match("%.lua$") then local chunk = assert(loadfile(dir .. "/" .. line)); chunk("WolfichMarket", ns) end
  end
  return ns
end
function tooltip(id) GameTooltip.lines = {}; GameTooltip.AddDoubleLine = function(_, a, b) table.insert(GameTooltip.lines, a .. " | " .. b) end; GameTooltip.AddLine = function(_, a) table.insert(GameTooltip.lines, a) end; ttcb(GameTooltip, { id = id }); return GameTooltip.lines end
