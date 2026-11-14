-- Прогон аддона на заглушке игрового API: texlua test/addon/run.lua test/addon addon/WolfichMarket
dofile(arg[1] .. "/harness.lua")
local ns = loadAddon(arg[2])
local function check(c, m) io.write(c and "OK   " or "FAIL ", m, "\n") end
fire("ADDON_LOADED", "WolfichMarket"); ns.DB.settings.debug = true; fire("PLAYER_LOGIN")
check(ns.DB and ns.charKey == "Вульфыч-CAMWOWEU4Realm6PvP", "загрузка и ключ персонажа")
-- окно профессии
fire("TRADE_SKILL_SHOW"); advance(1)
check(WolfichMarketProfPanel == nil, "у окна профессии нет отдельной панели")
local recs = ns.DB.chars[ns.charKey].profs["Кузнечное дело"].recipes
check(#recs == 5, "рецепты записаны (с неизученным): " .. #recs)
local un; for _, r in ipairs(recs) do if r.learned == false then un = r end end
check(un and un.src == nil, "неизученный рецепт сохранён без запроса источника")
ns.DB.settings.showUnlearned = true
local okD, errD = pcall(ns.FillRecipeDetail, un); check(okD, "карточка неизученного рецепта" .. (okD and "" or (": " .. tostring(errD))))
ns.DecorateRecipeRows()
ns.DB.settings.showUnlearned = false
check(#ns.AllRecipeProfits(nil) == 4 and #ns.AllRecipeProfits(nil, true) == 5, "галочка «включая неизученные» в расчётах")
-- аукцион + снимок
fire("AUCTION_HOUSE_SHOW")
check(WolfichMarketAHPanel ~= nil, "панель у окна аукциона создана")
ns.StartScan(); fire("REPLICATE_ITEM_LIST_UPDATE"); advance(2)
local scan = ns.CurrentScan()
check(scan and scan.items[2840] and scan.items[2840][1] == 140 and scan.items[2840][2] == 25, "снимок: медный слиток 140м, 25 шт")
-- прибыль
local best = ns.BestCraft()
check(best and best.rec.name == "Железная скоба", "лучший крафт: " .. (best and best.rec.name or "нет") .. " " .. (best and math.floor(best.profit) or ""))
local pr = ns.Profit(recs[1])
for _, r in ipairs(recs) do local p = ns.Profit(r); io.write("     ", r.name, ": себест ", p.cost, " доход ", tostring(p.revenue), " прибыль ", tostring(p.profit), "\n") end
local okAll = true
for _, r in ipairs(recs) do local ok, err = pcall(ns.FillRecipeDetail, r); if not ok then okAll = false; io.write("     ", tostring(err), "\n") end end
check(okAll, "карточка рецепта пересчитывается для каждого рецепта")
-- метки на строках
ns.DecorateRecipeRows()
-- отметка + скачок
HandleModifiedItemClick("|Hitem:2840::|h[x]|h") -- без Alt — ничего
check(not ns.IsMarked(2840), "клик без Alt не отмечает")
IsAltKeyDown = function() return true end
HandleModifiedItemClick("|Hitem:2840::|h[x]|h")
check(ns.IsMarked(2840), "Alt+клик отмечает")
IsAltKeyDown = function() return false end
-- второй снимок через 16 минут, медь подорожала
advance(16 * 60); os.time = function() return 0 end
local base = time
time = function() return base() + 16 * 60 end
for i, r in ipairs({}) do end
C_AuctionHouse.GetReplicateItemInfo = (function(old) return function(i) local a = { old(i) }; if a[17] == 2840 then a[10] = a[10] * 2 end; return table.unpack(a, 1, 18) end end)(C_AuctionHouse.GetReplicateItemInfo)
ns.DB.ahLastReq = 0
played = false
ns.StartScan(); fire("REPLICATE_ITEM_LIST_UPDATE"); advance(15)
check(played, "уведомление со звуком о скачке цены отмеченного")
local found = false; for _, s in ipairs(printed) do if s:find("Медный слиток") and s:find("media\\up", 1, true) then found = true end end
check(found, "строка о подорожании меди в чате")
-- поиск на аукционе
ns.SearchAH(2835); check(searched == "Грубый камень", "поиск на аукционе по названию")
-- покупка товара
ns.OpenBuy(2840); check(lastQuery and lastQuery.itemID == 2840, "запрос поиска для покупки")
fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2840)
fire("COMMODITY_PRICE_UPDATED", 101, 1010)
-- подсветка в сумках
ns.UpdateBagGlow(); advance(1)
local g1, g2 = BAGBTNS[1].wmSellGlow, BAGBTNS[2].wmSellGlow
check(g1 and g1.shown and g2 and g2.shown, "подсветка в сумках появилась")
check(ns.SellWhere(2840) == "ah" and ns.SellWhere(2862) == "vendor", "медь - на аукцион (зелёный), точило - торговцу (жёлтый)")
-- все вкладки панели аукциона
for i = 1, 6 do local ok, err = pcall(ns.AHSelectTab, i); check(ok, "вкладка " .. i .. (ok and "" or (": " .. tostring(err)))) end
-- продажа: выбрать предмет и выставить
ns.AHSelectTab(4)
local P = ns._ahPages
local sell = P[4]
check(#sell.list.data == 2, "продажа: предметов в сумках " .. #sell.list.data)
sell.select(sell.list.data[1])
check(tonumber(sell.qty:GetText()) == sell.list.data[1].count, "продажа: количество по умолчанию = всё в сумках")
check(sell.money:Get() == ns.AHPrice(sell.list.data[1].id) - 1, "продажа: цена = мин − 1м")
sell.calc(); check(sell.post.enabled, "кнопка «Выставить» активна")
check(sell.analysis:GetText():find("Себестоимость крафта", 1, true) and sell.analysis:GetText():find("Выгодно продавать", 1, true), "продажа: себестоимость и вывод «выгодно»")
io.write("     ", (sell.analysis:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("\n", " // ")), "\n")
sell.doPost(); check(postedLot and postedLot[2] == sell.list.data[1].count, "лот выставлен")
local base = sell.money:Get()
sell.mulBtns[3].scripts.OnClick(sell.mulBtns[3]); check(sell.money:Get() == math.floor(base * 1.1 + 0.5), "кнопка +10%")
sell.mulBtns[2].scripts.OnClick(sell.mulBtns[2]); check(sell.money:Get() == math.floor(base * 1.05 + 0.5), "кнопка +5%")
sell.mulBtns[1].scripts.OnClick(sell.mulBtns[1]); check(sell.money:Get() == base, "кнопка «мин»")
-- массовое выставление
sell.allBtn.scripts.OnClick(sell.allBtn)
local n = 0; for _ in pairs(sell.checked) do n = n + 1 end
check(n == 2 and sell.bulk.enabled, "продажа: отмечены все с ценой (" .. n .. ")")
sell.mulBtns[3].scripts.OnClick(sell.mulBtns[3])
local q1 = sell.queue()[1]
check(q1 and q1.unit == math.floor((ns.AHPrice(q1.d.id) - 1) * 1.10 + 0.5), "«Выставить отмеченные» учитывает +10%")
sell.mulBtns[1].scripts.OnClick(sell.mulBtns[1])
postedLot = nil; sell.bulk.scripts.OnClick(sell.bulk)
check(postedLot ~= nil, "продажа: «Выставить отмеченные» выставил первый лот")
check(sell.durBtns[2].label:GetText() == "8 ч", "сроки 2/8/24 ч")
local buy = P[3]
ns.OpenBuy(2840); fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2840)
check(#buy.list.data == 2, "покупка: строк результатов " .. #buy.list.data)
buy.qty:SetText("5"); buy.price.scripts.OnClick(buy.price)
check(startedBuy and startedBuy[2] == 5, "покупка: запрос цены на 5 шт")
fire("COMMODITY_PRICE_UPDATED", 101, 505)
check(buy.confirm.enabled, "покупка: кнопка подтверждения активна")
buy.confirm.scripts.OnClick(buy.confirm)
check(confirmedBuy and confirmedBuy[2] == 5, "покупка подтверждена: 5 шт")
buy.back.scripts.OnClick(buy.back)
local md = buy.mats.data
check(#md >= 4 and md[1].header == "Кузнечное дело", "покупка: список материалов по профессиям (" .. #md .. " строк)")
ns.OpenChart(2840)
-- подсказка
local tl = tooltip(2840); check(#tl >= 2, "подсказка: " .. (tl[1] or "пусто"))
-- закрытие
fire("AUCTION_HOUSE_CLOSED"); check(not ns.AHIsOpen(), "аукцион закрыт")
-- рецепты перечитываются только после нового снимка аукциона
local function profRecs() return ns.DB.chars[ns.charKey].profs["Кузнечное дело"].recipes end
local r1 = profRecs(); fire("TRADE_SKILL_SHOW"); advance(1)
check(profRecs() == r1, "без нового снимка рецепты не перечитываются")
ns.CurrentScan().t = time() + 100; fire("TRADE_SKILL_SHOW"); advance(1)
check(profRecs() ~= r1, "после нового снимка рецепты перечитаны")
-- главное окно: персонажи, профессии, карточка, сигналы
check(WolfichMarketMinimapButton ~= nil, "кнопка у миникарты")
ns.DB.chars["Альт-CAMWOWEU4Realm6PvP"] = { realmKey = ns.realmKey, class = "DRUID", profs = { ["Алхимия"] = { skill = 50, max = 75, recipes = { { id = 1, name = "Тестовое зелье", out = 2862, qmin = 1, qmax = 1, diff = 1, reag = { { 2835, 1 } } } } } } }
local okW, errW = pcall(ns.ToggleMain); check(okW and WolfichMarketMainFrame and WolfichMarketMainFrame.shown, "окно WolfichMarket открылось" .. (okW and "" or (": " .. tostring(errW))))
local alt = ns.AllRecipeProfits(nil, false, "Альт-CAMWOWEU4Realm6PvP")
check(#alt == 1 and alt[1].profit, "прибыль по рецептам другого персонажа")
local W = WolfichMarketMainFrame
local okS, errS = pcall(W.tabs[2].scripts.OnClick, W.tabs[2]); check(okS, "вкладка «Сигналы»" .. (okS and "" or (": " .. tostring(errS))))
local okC, errC = pcall(W.tabs[1].scripts.OnClick, W.tabs[1]); check(okC, "вкладка «Крафт»" .. (okC and "" or (": " .. tostring(errC))))
-- карточка: выбор рецепта, график, окно сигналов для рецепта
local cr = ns._mainCraft
local row = cr.list.rows[1]
local okF, errF = pcall(row.scripts.OnClick, row); check(okF, "карточка рецепта в главном окне" .. (okF and "" or (": " .. tostring(errF))))
advance(1)
check(cr.card.craft.shown and cr.card.alarm.shown and cr.card.chart.shown, "в карточке «Крафт», «Поставить сигнал» и график")
local recA = row.data.rec
local okA, errA = pcall(cr.openAlarms, recA); check(okA and WolfichMarketAlarmDialog and WolfichMarketAlarmDialog.shown, "окно сигналов для рецепта" .. (okA and "" or (": " .. tostring(errA))))
local D = WolfichMarketAlarmDialog
for _, r in ipairs(D.rows) do if r.shown then r.chk:SetChecked(true); r.thr:SetText("12") end end
D.save.scripts.OnClick(D.save)
local allMarked = true
for _, r in ipairs(D.rows) do if r.shown and r.id and not (ns.IsMarked(r.id) and ns.DB.alarm[r.id] == 12) then allMarked = false end end
check(allMarked and not D.shown, "сигналы на предмет и ингредиенты сохранены с порогом")
SlashCmdList.WOLFICHMARKET("")
check(not WolfichMarketMainFrame.shown, "/wm закрывает окно")
ns.DB.alarm[2840] = 5
-- кнопка «Крафт»: окно профессии открыто — сразу рецепт; закрыто — сначала профессия
openedRecipe = nil; ns.OpenRecipeInGame(recs[1], "Кузнечное дело"); check(openedRecipe == recs[1].id, "«Крафт» открывает рецепт")
ProfessionsFrame.shown = false; openedRecipe, openedLine = nil, nil
ns.OpenRecipeInGame(recs[2], "Кузнечное дело"); advance(2)
check(openedLine == 164 and openedRecipe == recs[2].id, "«Крафт» открывает профессию, затем рецепт")
ProfessionsFrame.shown = true
-- профессии не стираются при повторном входе; удаление — только вручную
local before = 0; for _ in pairs(ns.DB.chars[ns.charKey].profs) do before = before + 1 end
fire("PLAYER_LOGIN"); advance(5)
local after = 0; for _ in pairs(ns.DB.chars[ns.charKey].profs) do after = after + 1 end
check(before > 0 and after == before, "профессии сохраняются после повторного входа")
ns.DB.chars[ns.charKey].profs["Травничество"] = { recipes = {} }
ns.RemoveProfession(ns.charKey, "Травничество")
check(ns.DB.chars[ns.charKey].profs["Травничество"] == nil and ns.DB.chars[ns.charKey].profs["Кузнечное дело"] ~= nil, "профессия удаляется вручную, остальные на месте")
-- вход твинком: у обоих персонажей свои профессии
local mainKey = ns.charKey
local oldName = UnitName; UnitName = function() return "Твинк" end
fire("PLAYER_LOGIN"); ns.CurrentScan().t = time() - 10; fire("TRADE_SKILL_SHOW"); advance(2)
UnitName = oldName; fire("PLAYER_LOGIN")
local tw = ns.DB.chars["Твинк-CAMWOWEU4Realm6PvP"]
check(tw and tw.profs["Кузнечное дело"] and ns.DB.chars[mainKey].profs["Кузнечное дело"], "профессии основы и твинка хранятся раздельно")
-- английский язык
ns.DB.settings.lang = "en"
check(ns.money(15000):find("g", 1, true) and ns.L("Купить") == "Buy" and ns.ago(time()) == "just now", "английский: деньги, кнопки, время")
local miss = 0; for k, v in pairs(ns.EN) do if v == nil or v == "" then miss = miss + 1 end end
check(miss == 0, "все английские строки заполнены")
ns.DB.settings.lang = nil; LOCALE = "enUS"
check(ns.Lang() == "en", "авто: английский клиент -> английский")
LOCALE = "ruRU"; check(ns.Lang() == "ru", "авто: русский клиент -> русский")
SlashCmdList.WOLFICHMARKET("best")
SlashCmdList.WOLFICHMARKET("marks")
SlashCmdList.WOLFICHMARKET("")
-- Shift+клик по предмету при открытом аукционе открывает его на аукционе (но не во время набора в чате)
do
  local got, oldS, oldOpen, oldShift = nil, ns.SearchAH, ns.ahOpen, IsShiftKeyDown
  ns.SearchAH = function(id) got = id end
  ns.ahOpen = true; IsShiftKeyDown = function() return true end
  HandleModifiedItemClick("|Hitem:2840::|h[x]|h")
  check(got == 2840, "Shift+клик открывает предмет на аукционе")
  got = nil; ChatEdit_GetActiveWindow = function() return {} end
  HandleModifiedItemClick("|Hitem:2840::|h[x]|h")
  check(got == nil, "Shift+клик при наборе в чате - не трогаем")
  ChatEdit_GetActiveWindow = nil; ns.SearchAH, ns.ahOpen, IsShiftKeyDown = oldS, oldOpen, oldShift
end
-- профессии другого персонажа не прилипают к текущему
do
  local c = ns.DB.chars[ns.charKey]
  local oldSk, oldProfs = c.skills, c.profs
  c.skills = { { name = "Алхимия", skill = 225, max = 225, line = 171 }, { name = "Кулинария", skill = 225, max = 225, line = 185 } }
  check(ns.OwnsProfession("Алхимия", { professionID = 171, skillLevel = 225, maxSkillLevel = 225 }), "своя профессия сохраняется")
  check(not ns.OwnsProfession("Кузнечное дело", { professionID = 164, skillLevel = 150, maxSkillLevel = 150 }), "чужая профессия не сохраняется")
  check(not ns.OwnsProfession("Кулинария", { professionID = 185, skillLevel = 1, maxSkillLevel = 75 }), "кулинария другого персонажа (1/75) не сохраняется")
  c.profs = { ["Алхимия"] = { skill = 225, max = 225, recipes = {} }, ["Кулинария"] = { skill = 200, max = 225, base = 185, recipes = {} },
    ["Кузнечное дело"] = { skill = 150, max = 150, recipes = {} }, ["Наложение чар"] = { skill = 150, max = 150, base = 333, recipes = {} } }
  ns.CleanStrangers()
  check(c.profs["Алхимия"] and c.profs["Кулинария"] and not c.profs["Кузнечное дело"] and not c.profs["Наложение чар"], "чистка убирает только чужие профессии")
  c.skills, c.profs = oldSk, oldProfs
end
-- график из вкладки «Сигналы» открывается своим окном (аукцион не нужен)
ns.ahOpen = false
if not (WolfichMarketMainFrame and WolfichMarketMainFrame:IsShown()) then ns.ToggleMain() end
ns.ShowChartDialog(2840)
check(WolfichMarketChartDialog and WolfichMarketChartDialog:IsShown(), "график цены из «Сигналов» открывается без аукциона")
-- банк: запоминается у персонажа, материалы из запаса не покупаются, вкладка «Банк»
do
  local oldN, oldI = C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo
  C_Container.GetContainerNumSlots = function(b) return (b == -1 and 1) or (b == 0 and 2) or 0 end
  C_Container.GetContainerItemInfo = function(b, s2) if b == -1 then return { itemID = 2840, stackCount = 30 } end return oldI(b, s2) end
  ns._bankOpen(true); ns.ScanBank(); ns.ScanBags(); ns._bankOpen(false)
  local c = ns.DB.chars[ns.charKey]
  check(c.bank and c.bank[2840] == 30 and c.bankT, "банк персонажа записан")
  check(ns.Stock()[2840] == 42, "запас = банк + сумки")
  local rec = { reag = { { 2840, 2 }, { 3470, 10 } } }
  local full, own = ns.Profit(rec), ns.Profit(rec, ns.Stock())
  check(own.cost < full.cost and own.crafts == 0 and own.parts[1].buy == 0 and own.parts[2].buy == 5, "свои материалы не идут в себестоимость, недостающее - докупить")
  C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo = oldN, oldI
  ns.DB.settings.useBank = true
  WolfichMarketMainFrame.tabs[3].scripts.OnClick(WolfichMarketMainFrame.tabs[3])
  check(WolfichMarketMainFrame.pages[3]:IsShown(), "вкладка «Банк» открывается")
  WolfichMarketMainFrame.tabs[1].scripts.OnClick(WolfichMarketMainFrame.tabs[1])
  local row = ns._mainCraft.list.rows[1]
  if row and row.data then row.scripts.OnClick(row) end
  check(ns._mainCraft.card.total.text ~= "", "карточка рецепта с учётом банка строится")
  ns.DB.settings.useBank = nil
end
-- порции и план закупки
do
  local rec = { id = 9001, name = "Тест-рецепт", out = 2841, reag = { { 2840, 3 }, { 3470, 2 } } }
  local one, five = ns.Profit(rec), ns.Profit(rec, nil, 5)
  check(five.parts[1].n == 15 and math.abs(five.cost - one.cost * 5) < 1, "порции умножают материалы и себестоимость")
  ns.ClearPlans()
  ns.AddPlan(rec, ns.charKey, "Кузнечное дело", 5)
  ns.AddPlan(rec, ns.charKey, "Кузнечное дело", 4) -- тот же рецепт - обновляет порции
  check(#ns.Plans() == 1 and ns.Plans()[1].n == 4, "план: рецепт с порциями сохранён, повтор обновляет")
  local needs = ns.PlanNeeds()
  local byId = {}; for _, d in ipairs(needs) do byId[d.id] = d end
  check(byId[2840] and byId[2840].need == 12 and byId[3470].need == 8, "план: сколько нужно материалов")
  check(byId[3470].buy == math.max(0, 8 - byId[3470].have), "план: докупить = нужно - есть")
  ns.ahOpen = true
  ns.AHSelectTab(7)
  check(ns._ahPages[7]:IsShown() and #ns._ahPages[7].items.data >= 2, "вкладка «План» у аукциониста со списком покупок")
  ns.OpenBuy(3470, 5, true)
  check(ns._ahPages[3].qty:GetText() == 5, "«Купить» из плана подставляет количество")
  ns.ClearPlans()
  check(#ns.Plans() == 0, "план очищается")
  local row = ns._mainCraft.list.rows[1]
  if row and row.data then
    row.scripts.OnClick(row)
    local card = ns._mainCraft.card
    card.portion:SetText("3"); card.portion.scripts.OnEnterPressed(card.portion)
    card.plan.scripts.OnClick(card.plan)
    check(#ns.Plans() == 1 and ns.Plans()[1].n == 3, "«Запланировать» в карточке сохраняет порции")
    ns.ClearPlans()
  end
end
-- «Продать»: лупа и график у выбранного предмета
do
  ns.AHSelectTab(4)
  local f = ns._ahPages[4]
  local row = f.list.rows[1]
  if row and row.data then
    row.scripts.OnClick(row)
    check(f.searchBtn:IsShown() and f.chartBtn:IsShown(), "«Продать»: у выбранного предмета есть лупа и график")
    if WolfichMarketChartDialog then WolfichMarketChartDialog:Hide() end
    f.chartBtn.scripts.OnClick(f.chartBtn)
    check(WolfichMarketChartDialog and WolfichMarketChartDialog:IsShown(), "«Продать»: график цены открывается")
  else check(false, "«Продать»: нет строк для проверки") end
end
-- ручной снимок по умолчанию и быстрое обновление цен отмеченных
do
  check(ns.DB.settings.autoScan == false, "автоснимок выключен - снимок вручную")
  local h = ns.DB.hist[2840] or {}; ns.DB.hist[2840] = h
  if h[#h] then h[#h][1] = time() - 1000 end
  local before = #h
  ns.SeenPrice(2840, 777, 10)
  check(#ns.DB.hist[2840] == before + 1 and ns.DB.hist[2840][#ns.DB.hist[2840]][2] == 777, "свежая цена добавляет точку на график")
end
-- в чат не должно попасть ни одной ошибки аддона (сломанная сборка окон)
local bad
for _, s in ipairs(allPrinted) do if s:find("ошибка в") or s:find("error in") then bad = s end end
check(not bad, "нет ошибок при сборке окон" .. (bad and (": " .. bad) or ""))
