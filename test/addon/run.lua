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
ns.StartScan(); fire("REPLICATE_ITEM_LIST_UPDATE"); for _ = 1, 12 do advance(1) end -- данные приходят частями: ждём, пока число лотов не перестанет расти
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
ns.DB.target[2840] = { sell = 1 } -- своя цена продажи (1 медь): после снимка цена выше - сигнал
ns.StartScan(); fire("REPLICATE_ITEM_LIST_UPDATE"); for _ = 1, 15 do advance(1) end
check(played, "уведомление со звуком: цена дошла до своей цены продажи")
local found = false; for _, e in ipairs(ns.log) do if e.msg:find("Медный слиток") and e.msg:find("media\\up", 1, true) and e.imp then found = true end end
check(found, "строка о подорожании меди в журнале (сигнал)")
-- поиск на аукционе
ns.SearchAH(2835); check(searched == "Грубый камень", "поиск на аукционе по названию")
-- покупка товара
ns.OpenBuy(2840); check(lastQuery and lastQuery.itemID == 2840, "запрос поиска для покупки")
fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2840)
fire("COMMODITY_PRICE_UPDATED", 101, 1010)
-- подсветка в сумках
ns.UpdateBagGlow(); advance(1)
local g1, g2 = BAGBTNS[1].wmSellBadge, BAGBTNS[2].wmSellBadge
check(g1 and g1.shown and g2 and g2.shown, "значки на предметах в сумках появились")
local function bt(g) return g and g.tex or "" end
do
  local old = C_Container.GetContainerItemInfo
  C_Container.GetContainerItemInfo = function(b, s) if s == 2 then return { itemID = 2862, stackCount = 1 } end return old(b, s) end
  ns.UpdateBagGlow(); advance(1)
  C_Container.GetContainerItemInfo = old
  check(bt(g1):find("badge%-ah") and bt(g2):find("badge%-vendor"), "значки: молоток (аукцион) и мешочек (торговец): " .. bt(g1) .. " / " .. bt(g2))
  ns.UpdateBagGlow(); advance(1)
end
check(ns.SellWhere(2840) == "ah" and ns.SellWhere(2862) == "vendor", "медь - на аукцион (зелёный), точило - торговцу (жёлтый)")
-- сортировка сумок: аукцион наверх, торговцу вниз (после обычной сортировки игры)
do
  local bag = { [1] = 2862, [2] = 99999, [3] = 2840, [4] = 2862, [5] = 3470, [6] = nil }
  local oldN, oldI = C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo
  local cursor, from
  C_Container.GetContainerNumSlots = function(b) return b == 0 and 6 or 0 end
  C_Container.GetContainerItemInfo = function(b, s) if b == 0 and bag[s] then return { itemID = bag[s], stackCount = 1 } end end
  C_Container.PickupContainerItem = function(b, s)
    if cursor then bag[from] = bag[s]; bag[s] = cursor; cursor = nil -- как в игре: предметы меняются местами
    else cursor = bag[s]; from = s; bag[s] = nil end
  end
  GetCursorInfo = function() return cursor and "item" or nil end
  ClearCursor = function() cursor = nil end
  C_Container.SortBags = function() end
  check(HOOKS.SortBags ~= nil, "сортировка игры перехвачена")
  HOOKS.SortBags(); for _ = 1, 20 do advance(0.25) end
  local g = {}
  for s = 1, 6 do local id = bag[s]; g[s] = id and (ns.SellWhere(id) == "ah" and "A" or ns.SellWhere(id) == "vendor" and "V" or "o") or "_" end
  local str = table.concat(g)
  check(str == "AAoVV_", "после сортировки: аукцион наверху, торговцу внизу (" .. str .. ")")
  check(not cursor, "на курсоре ничего не осталось")
  check(ns.SortBagsByValue(true) == 0, "повторно переставлять нечего")
  C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo = oldN, oldI
  GetCursorInfo = nil
end
-- все вкладки панели аукциона
for i = 1, 5 do local ok, err = pcall(ns.AHSelectTab, i); check(ok, "вкладка " .. i .. (ok and "" or (": " .. tostring(err)))) end
-- продажа: выбрать предмет и выставить
ns.AHSelectTab(3)
local P = ns._ahPages
local sell = P[3]
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
-- второй клик до подтверждения игрой - не выставляет ещё раз; после подтверждения - следующий лот
do
  local firstId = postedLot and postedLot[1]
  local n0 = 0; for _ in pairs(sell.checked) do n0 = n0 + 1 end
  postedLot = nil; sell.bulk.scripts.OnClick(sell.bulk)
  check(postedLot == nil, "массовое выставление: пока игра не подтвердила лот - второй не уходит")
  fire("AUCTION_HOUSE_AUCTION_CREATED"); advance(1)
  local n1 = 0; for _ in pairs(sell.checked) do n1 = n1 + 1 end
  check(n1 == n0 - 1 and sell.bulk.enabled, "после подтверждения - отметка снята, кнопка снова активна")
  postedLot = nil; sell.bulk.scripts.OnClick(sell.bulk)
  check(postedLot ~= nil, "массовое выставление: третий клик - следующий лот")
  -- игра не подтвердила - через несколько секунд можно нажать снова, лот остаётся в очереди
  advance(5)
  local n2 = 0; for _ in pairs(sell.checked) do n2 = n2 + 1 end
  check(sell.pending == nil and n2 == n1, "без подтверждения - лот остаётся в очереди, кнопку можно нажать снова")
  -- окно «Продать» самой игры занято предметом - массовое выставление не шлёт параллельно
  do
    local oldA = AuctionHouseFrame
    local sellFr = CreateFrame("Frame"); sellFr.GetItem = function() return { bagID = 0, slotIndex = 1 } end; sellFr:Show()
    AuctionHouseFrame = CreateFrame("Frame"); AuctionHouseFrame:Show(); AuctionHouseFrame.CommoditiesSellFrame = sellFr
    postedLot = nil; sell.bulk.scripts.OnClick(sell.bulk)
    check(postedLot == nil and ((sell.bulkInfo.text or ""):find("Продать", 1, true) or (sell.bulkInfo.text or ""):find("Sell", 1, true)), "окно «Продать» игры занято - выставление не уходит, подсказка")
    AuctionHouseFrame = oldA
  end

end
check(sell.durBtns[2].label:GetText() == "8 ч", "сроки 2/8/24 ч")
local buy = P[2]
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
-- общий аукцион: отдельная строка в подсказке и вкладка «Аукционы»
do
  local ahBefore = ns.AHPrice(2840)
  ns.DB.ntah = ns.DB.ntah or {}
  ns.DB.ntah[ns.realmKey] = { t = time(), lots = 3, items = { [2840] = { p = 50000, q = 1 }, [19019] = { p = 1250000, q = 1 } } }
  GameTooltip.wmDone = nil
  local t1 = table.concat(tooltip(2840), "\n")
  check(t1:find("Общий аукцион", 1, true) or t1:find("Neutral", 1, true), "подсказка: строка «Общий аукцион»")
  check(not t1:find("Чёрный рынок", 1, true), "чёрного рынка в подсказке больше нет")
  check(ns.AHPrice(2840) == ahBefore, "общий аукцион не смешивается с фракционным")
  ns.DB.ntah[ns.realmKey].items[2862] = { p = 1, q = 1 }   -- точило за 1 медь: выгодно купить на общем
  ns.ToggleMain()
  local okT = pcall(WolfichMarketMainFrame.tabs[4].scripts.OnClick, WolfichMarketMainFrame.tabs[4])
  local B = ns._mainAuc
  check(B.kind.bm == nil, "кнопки «Чёрный рынок» больше нет")
  B.kind.neutral.scripts.OnClick(B.kind.neutral)
  local function has(list, id) for _, d in ipairs(list.data or {}) do if d.id == id then return d end end end
  local cheap, dear = has(B.buy.list, 2862), has(B.dear.list, 2840)
  check(okT and WolfichMarketMainFrame.pages[4]:IsShown() and ns.DB.settings.aucMode == "neutral", "вкладка «Аукционы» открывается, выбран общий")
  check(cheap and cheap.gain > 0, "общий: дешёвый лот - в «Лучше купить здесь»")
  check(dear and not has(B.buy.list, 2840), "общий: дорогой лот - в «Лучше продать здесь»")
  -- на общем дороже на 10% - с комиссией 15% продавать там не выгоднее
  do
    local ah = ns.RegularPrice(2862) or 0
    if ah > 0 then
      ns.DB.ntah[ns.realmKey].items[2862] = { p = math.floor(ah * 1.10), q = 1 }
      B.kind.neutral.scripts.OnClick(B.kind.neutral)
      check(not has(B.dear.list, 2862) and not has(B.buy.list, 2862), "общий: +10% к цене не перекрывает комиссию 15% - лота нет")
      ns.DB.ntah[ns.realmKey].items[2862] = { p = 1, q = 1 }
      B.kind.neutral.scripts.OnClick(B.kind.neutral)
    end
  end
  check(not B.all:IsShown(), "у общего - только две колонки")
  ns.DB.names[2862] = "Грубое точило"
  B.search:SetText("ГРУБ"); B.search.scripts.OnTextChanged(B.search, true)
  check(has(B.buy.list, 2862) ~= nil, "поиск: «ГРУБ» находит «Грубое точило»")
  B.search:SetText("нет такого"); B.search.scripts.OnTextChanged(B.search, true)
  check(#(B.buy.list.data or {}) == 0, "поиск: лишнее скрыто")
  B.search:SetText(""); B.search.scripts.OnTextChanged(B.search, true)
  check(ns.lower("ЁЖ Abc") == "ёж abc", "нижний регистр с русскими буквами")
  -- категории: у каждого аукциона своя
  ns.DB.settings.aucCat = { neutral = 7 }
  local oldC = C_Item
  C_Item = { GetItemInfoInstant = function(id) return id, "", "", "", 0, id == 2862 and 7 or 2, 0 end }
  B.kind.neutral.scripts.OnClick(B.kind.neutral)
  check(has(B.buy.list, 2862) ~= nil and not has(B.dear.list, 2840), "категория «Хозяйственные товары»: лишние категории скрыты")
  -- фракционный: весь аукцион одним списком, сортировка по заголовкам
  ns.DB.settings.aucCat.main = nil; B.kind.main.scripts.OnClick(B.kind.main)
  check(B.all:IsShown() and not B.buy:IsShown() and #(B.all.list.data or {}) > 0, "фракционный: весь аукцион одним списком")
  B.all.heads.p.scripts.OnClick(B.all.heads.p)
  local L1 = B.all.list.data
  check(#L1 < 2 or L1[1].p >= L1[2].p, "фракционный: сортировка по цене (дороже сверху)")
  B.all.heads.p.scripts.OnClick(B.all.heads.p)
  L1 = B.all.list.data
  check(#L1 < 2 or L1[1].p <= L1[2].p, "повторный клик - обратный порядок")
  check(pcall(B.all.heads.chg.scripts.OnClick, B.all.heads.chg), "сортировка по изменению за сутки")
  -- категория по профессии: готовые предметы / ингредиенты
  do
    local slug, P = next(ns.RS.prof)
    local outId, reagId
    for _, rid in ipairs(P.ids) do local d = ns.RS.r[rid]; if d and d.cr and d.rg and d.rg[1] then outId, reagId = d.cr[1], d.rg[1][1]; break end end
    if outId then
      ns.DB.ntah[ns.realmKey].items[outId] = { p = 1, q = 1 }; ns.DB.ntah[ns.realmKey].items[reagId] = { p = 1, q = 1 }
      ns.DB.seen[outId] = { p = 999999, t = time(), r = ns.realmKey, q = 1 }; ns.DB.seen[reagId] = { p = 999999, t = time(), r = ns.realmKey, q = 1 }
      ns.DB.settings.aucCat = { neutral = "p:" .. slug .. ":out" }
      B.kind.neutral.scripts.OnClick(B.kind.neutral)
      check(has(B.buy.list, outId) ~= nil, "категория «профессия: готовые предметы»")
      ns.DB.settings.aucCat = { neutral = "p:" .. slug .. ":reag" }
      B.kind.neutral.scripts.OnClick(B.kind.neutral)
      check(has(B.buy.list, reagId) ~= nil, "категория «профессия: ингредиенты»")
      check(pcall(B.openCats, B.cat) and pcall(B.openCats, B.cat, slug), "меню категорий с профессиями открывается")
      ns.DB.ntah[ns.realmKey].items[outId], ns.DB.ntah[ns.realmKey].items[reagId] = nil, nil
      ns.DB.seen[outId], ns.DB.seen[reagId] = nil, nil
    end
  end
  C_Item = oldC; ns.DB.settings.aucCat = {}; ns.DB.settings.aucMode = nil
  WolfichMarketMainFrame.tabs[3].scripts.OnClick(WolfichMarketMainFrame.tabs[3]); ns.ToggleMain()
  ns.DB.ntah[ns.realmKey] = nil
  -- вид аукциона - по зоне: Лесоречье - чёрный рынок; Остров Зефрис, Тернистая долина, Танарис - общий; иначе - фракционный
  local oldUN, oldGUID, oldZ = UnitName, UnitGUID, GetRealZoneText
  UnitName = function(u) if u == "npc" then return "Аукционер Леонус" end return "Вульфыч" end
  UnitGUID = function(u) if u == "npc" then return "Creature-0-1-2-3-99999-00001" end return "Player-1-0001" end
  local scanRef, ahP = ns.DB.ahScans[ns.realmKey], ns.AHPrice(2840)
  local zone = "Штормград"
  GetRealZoneText = function() return zone end
  local function reopen() fire("AUCTION_HOUSE_CLOSED"); fire("AUCTION_HOUSE_SHOW"); advance(1) end
  reopen()
  check(ns.ahKind == "main" and not ns.ahIsBM, "Аукционер Леонус в городе - фракционный (по имени больше не определяем)")
  for _, z in ipairs({ "Лесоречье", "Riverglades" }) do zone = z; reopen(); check(ns.ahKind == "off", z .. " - не учитывается") end
  for _, z in ipairs({ "Остров Зефрис", "Тернистая долина", "Танарис", "Tanaris" }) do zone = z; reopen(); check(ns.ahKind == "neutral", z .. " - общий аукцион") end
  -- общий аукцион: снимок и поиск - отдельно, цены у его окна - его
  ns.DB.ntLastReq = 0
  ns.StartScan(); fire("REPLICATE_ITEM_LIST_UPDATE"); for _ = 1, 15 do advance(1) end
  check(ns.DB.ahScans[ns.realmKey] == scanRef and ns.RegularPrice(2840) == ahP, "снимок общего аукциона не заменил основные цены")
  check(ns.DB.ntah[ns.realmKey] and ns.DB.ntah[ns.realmKey].items[2840] ~= nil, "снимок общего аукциона сохранён отдельно")
  ns.SeenPrice(2840, 9, 1)
  check(ns.AHPrice(2840) == 9 and ns.RegularPrice(2840) == ahP, "у общего аукциона цены аддона - его, основные не тронуты")
  -- Лесоречье: снимок и поиск не сохраняются вовсе
  zone = "Лесоречье"; reopen()
  ns.DB.offLastReq = 0
  local ntBefore = ns.DB.ntah[ns.realmKey]
  ns.StartScan(); fire("REPLICATE_ITEM_LIST_UPDATE"); for _ = 1, 15 do advance(1) end
  check(ns.DB.ahScans[ns.realmKey] == scanRef and ns.DB.ntah[ns.realmKey] == ntBefore and ns.DB.bmah == nil, "Лесоречье: снимок не сохранён никуда")
  ns.SeenPrice(2840, 7, 1)
  check(ns.RegularPrice(2840) == ahP, "Лесоречье: поиск не меняет цены")
  zone = "Танарис"; reopen()
  GameTooltip.wmDone = nil
  local tt = table.concat(tooltip(2840), "\n")
  check(tt:find(ns.money(ahP), 1, true) ~= nil and (tt:find("Общий аукцион", 1, true) or tt:find("Neutral", 1, true)), "подсказка: основная цена и строка общего аукциона")
  -- ручной выбор вне известных зон запоминается для аукциониста
  zone = "Штормград"; reopen()
  ns.SetAHKind("neutral")
  check(ns.DB.ahNpcKind[99999] == "neutral", "ручной выбор запоминается для аукциониста")
  reopen()
  check(ns.ahKind == "neutral", "при следующем открытии - как выбрали")
  ns.SetAHKind("main"); ns.DB.ahNpcKind[99999] = nil
  fire("AUCTION_HOUSE_CLOSED")
  check(ns.AHPrice(2840) == ahP, "аукцион закрыт - цены основные")
  -- выгода крафта на трёх аукционах и таблица «где купить, где продать»
  do
    local rec = { id = 777001, name = "Тест-рецепт", out = 3470, qmin = 1, qmax = 1, reag = { { 2840, 2 } } }
    local nt = ns.DB.ntah[ns.realmKey]
    nt.items[3470] = { p = 90000000, q = 1 }
    nt.items[2840] = { p = 1, q = 9 }        -- медь на общем почти даром
    local by, best = ns.ProfitByKind(rec)
    check(by.main and by.neutral and by.bm == nil and best == "neutral", "выгода по аукционам: лучший - общий (" .. tostring(best) .. ")")
    -- комиссия: фракционный 5%, общий 15%
    check(ns.Cut("main") == 0.05 and ns.Cut("neutral") == 0.15, "комиссия: фракционный 5%, общий 15%")
    local pN, sN, cN = ns.ProfitIn(rec, "neutral")
    check(pN and math.abs(pN - (sN * 0.85 - cN)) < 1, "прибыль на общем - за вычетом 15%")
    local _, where = ns.BestBuy(2840)
    check(where == "neutral", "материал дешевле на общем аукционе")
    local M = ns.RecipeMarket(rec)
    check(#M.rows == 1 and M.rows[1].bestKind == "neutral" and M.out.p.neutral == 90000000 and M.out.p.bm == nil, "таблица: материалы и продажа по двум аукционам")
    -- окно профессии игры: столбики на строках и таблица под реагентами
    local oldPF = ProfessionsFrame
    ProfessionsFrame = CreateFrame("Frame"); ProfessionsFrame.CraftingPage = CreateFrame("Frame")
    local rl = CreateFrame("Frame"); rl.ScrollBox = CreateFrame("Frame"); ProfessionsFrame.CraftingPage.RecipeList = rl
    local form = CreateFrame("Frame"); form.Init = function() end; ProfessionsFrame.CraftingPage.SchematicForm = form
    local okH = pcall(ns._hookRows)
    check(okH, "окно профессии: столбики и таблица подключаются без ошибок")
    -- окно профессии: вырос навык (225 -> 245/300) - рецепты перечитываются
    do
      local p = ns.DB.chars[ns.charKey].profs[ns.curProf or ""]
      if p then
        local old = p.skill; p.skill = 1
        ProfessionsFrame:Show(); p.t = time() + 99999
        local before = ns.DB.chars[ns.charKey].profs[ns.curProf].t
        fire("NEW_RECIPE_LEARNED"); advance(2)
        check(ns.DB.chars[ns.charKey].profs[ns.curProf].t ~= before, "навык вырос - профессия перечитана")
      end
    end
    local okF = pcall(ns._fillMarketTable, rec)
    check(okF, "таблица «где купить, где продать» заполняется без ошибок")
    do
      local m = ns._marketTable
      local ln = m and m.lines[1]
      if ln and ln.id then
        ln.scripts.OnClick(ln)
        check(m.det:IsShown() and m.open == ln.id and ln.star and ln.bell, "окно профессии: клик по строке - график цены под ней; у строки звезда и колокольчик")
        ln.scripts.OnClick(ln)
        check(m.open == nil, "окно профессии: повторный клик сворачивает график")
      end
    end
    -- сортировка списка рецептов игры по прибыли: фиктивное дерево как у игры
    do
      local function node(data, kids) local n = { data = data, nodes = kids or {} }
        function n:GetData() return self.data end
        function n:GetNodes() return self.nodes end
        function n:SetSortComparator(c) self.cmp = c; for _, ch in ipairs(self.nodes) do ch.cmp = c end end
        function n:Sort() local function srt(x) if x.cmp then table.sort(x.nodes, x.cmp) end; for _, ch in ipairs(x.nodes) do srt(ch) end end; srt(self) end
        return n end
      ns.DB.chars[ns.charKey].profs["ТестПроф"] = { recipes = {
        { id = 9001, name = "A", out = 3470, reag = { { 2840, 1 } }, qmin = 1, qmax = 1 },
        { id = 9002, name = "B", out = 2862, reag = { { 2840, 1 } }, qmin = 1, qmax = 1 } }, line = 1, skill = 1, max = 1 }
      local saveProf = ns.curProf; ns.curProf = "ТестПроф"; ns.MarkProfitDirty()
      local cat = node({ categoryInfo = {} }, { node({ recipeInfo = { recipeID = 9002 } }), node({ recipeInfo = { recipeID = 9001 } }) })
      local root = node({}, { cat })
      local dp = { GetRootNode = function() return root end }
      ProfessionsFrame.CraftingPage.RecipeList.ScrollBox.GetDataProvider = function() return dp end
      local nt = ns.DB.ntah[ns.realmKey]
      nt.items[3470] = { p = 90000000, q = 1 }; nt.items[2862] = { p = 1, q = 1 }
      ns.DB.settings.profSort = "neutral"; ns.ApplyRecipeSort()
      check(cat.nodes[1].data.recipeInfo.recipeID == 9001, "окно профессии: сортировка по прибыли на общем")
      -- пришла новая цена от игрока (не свой снимок) - порядок не дёргается
      nt.items[3470] = { p = 1, q = 1 }; ns.ApplyRecipeSort()
      check(cat.nodes[1].data.recipeInfo.recipeID == 9001, "окно профессии: от каждой пришедшей цены строки не меняются местами")
      nt.items[3470] = { p = 90000000, q = 1 }
      ns.DB.settings.profSort = nil; ns.ApplyRecipeSort()
      check(cat.nodes[1].data.recipeInfo.recipeID == 9002, "окно профессии: без галочки - исходный порядок игры")
      local mtb = ns._marketTable
      check(mtb and mtb.sortMain and mtb.sortNt, "окно профессии: галочки «по прибыли Ф» и «по прибыли Общ»")
      ns.ToggleMain()
      local C = ns._mainCraft
      local okS = C and C.sortNt and pcall(C.sortNt.scripts.OnClick, (function() C.sortNt:SetChecked(true); return C.sortNt end)())
      check(okS and ns.DB.settings.craftSort == "neutral", "главное окно: галочка «прибыль по общему»")
      C.sortMain:SetChecked(true); C.sortMain.scripts.OnClick(C.sortMain)
      check(ns.DB.settings.craftSort == "main" and not C.sortNt:GetChecked(), "главное окно: галочки взаимоисключающие")
      check(C.card and C.card.chartBox and C.card.onAH, "карточка рецепта: график в своей панели, кнопка «На аукционе»")
      ns.DB.settings.craftSort = nil; ns.ToggleMain()
      nt.items[2862] = nil
      ns.DB.chars[ns.charKey].profs["ТестПроф"] = nil; ns.curProf = saveProf; ns.MarkProfitDirty()
    end
    -- «В план» из окна профессии: каждый клик +1 порция
    do
      local mtPlan
      for _, p in ipairs(ns.Plans()) do if p.id == rec.id then mtPlan = p end end
      local before = mtPlan and mtPlan.n or 0
      local btn = ns._marketTable and ns._marketTable.plan
      if btn then
        btn.scripts.OnClick(btn); btn.scripts.OnClick(btn)
        local n = 0; for _, p in ipairs(ns.Plans()) do if p.id == rec.id and p.ck == ns.charKey then n = p.n end end
        check(n == before + 2, "окно профессии: «В план» - +1 порция за клик (" .. n .. ")")
        for i, p in ipairs(ns.Plans()) do if p.id == rec.id then ns.RemovePlan(i); break end end
      else check(false, "окно профессии: нет кнопки «В план»") end
    end
    local row = CreateFrame("Frame")
    row.GetElementData = function() return { GetData = function() return { recipeInfo = { recipeID = 777001 } } end } end
    local okD, errD = pcall(ns._decorateRow, row)
    check(okD and row.wmCols and row.wmCols.main, "строка рецепта: столбики Ф / Общ")
    local cat = CreateFrame("Frame")
    cat.GetElementData = function() return { GetData = function() return { categoryInfo = { name = "Избранное" } } end } end
    pcall(ns._decorateRow, cat)
    check(cat.wmCols and (cat.wmCols.main.text or ""):find("Ф", 1, true) or (cat.wmCols and (cat.wmCols.main.text or ""):find("F", 1, true)), "заголовок группы: подписи столбиков над цифрами")
    nt.items[3470], nt.items[2840] = nil, nil
    ProfessionsFrame = oldPF
  end
  -- вкладка «Общий аук.» в главном окне
  ns.ToggleMain()
  WolfichMarketMainFrame.tabs[4].scripts.OnClick(WolfichMarketMainFrame.tabs[4])
  ns._mainAuc.kind.neutral.scripts.OnClick(ns._mainAuc.kind.neutral)
  check(WolfichMarketMainFrame.pages[4]:IsShown() and ns._mainAuc.status.text ~= "", "«Аукционы» - общий аукцион открывается")
  ns.DB.settings.aucMode = nil
  WolfichMarketMainFrame.tabs[3].scripts.OnClick(WolfichMarketMainFrame.tabs[3]); ns.ToggleMain()
  UnitName, UnitGUID, GetRealZoneText = oldUN, oldGUID, oldZ
  -- данные чёрного рынка из прошлых версий удаляются при входе
  ns.DB.bmah = { x = {} }; ns.DB.bmLastReq = 1; fire("PLAYER_LOGIN"); advance(3)
  check(ns.DB.bmah == nil and ns.DB.bmLastReq == nil, "данные чёрного рынка удалены")
end
do
  local outId
  for _, p in pairs(ns.DB.chars[ns.charKey].profs) do for _, r in ipairs(p.recipes or {}) do if not outId and r.out and r.reag and #r.reag > 0 then outId = r.out end end end
  local t2 = table.concat(tooltip(outId or 0), "\n")
  check((t2:find("Стоимость крафта", 1, true) or t2:find("Crafting cost", 1, true)) and (t2:find("На аукционе", 1, true) or t2:find("On the auction", 1, true)), "подсказка крафтового предмета: стоимость крафта и аукцион")
  check(t2:find("Прибыль", 1, true) or t2:find("Profit", 1, true), "подсказка крафтового предмета: прибыль ±")
end
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
ns.DB.settings.aucView = "signals"
local okS, errS = pcall(W.tabs[4].scripts.OnClick, W.tabs[4]); check(okS and ns._mainAuc.sig:IsShown(), "«Аукцион» - «Сигналы»" .. (okS and "" or (": " .. tostring(errS))))
ns.DB.settings.aucView = "all"
for i = 1, 6 do local ok, err = pcall(W.tabs[i].scripts.OnClick, W.tabs[i]); check(ok and W.pages[i]:IsShown(), "раздел " .. i .. (ok and "" or (": " .. tostring(err)))) end
local okC, errC = pcall(W.tabs[3].scripts.OnClick, W.tabs[3]); check(okC, "раздел «Профессии»" .. (okC and "" or (": " .. tostring(errC))))
-- карточка: выбор рецепта, график, окно сигналов для рецепта
local cr = ns._mainCraft
local function recRow(list) for _, r in ipairs(list.rows) do if r.data and r.data.rec then return r end end end
local row = recRow(cr.list)
local okF, errF = pcall(row.scripts.OnClick, row); check(okF, "карточка рецепта в главном окне" .. (okF and "" or (": " .. tostring(errF))))
advance(1)
check(cr.card.craft.shown and cr.card.alarm.shown and cr.card.chart.shown, "в карточке «Крафт», «Поставить сигнал» и график")
local recA = row.data.rec
local okA, errA = pcall(cr.openAlarms, recA); check(okA and WolfichMarketAlarmDialog and WolfichMarketAlarmDialog.shown, "окно сигналов для рецепта" .. (okA and "" or (": " .. tostring(errA))))
local D = WolfichMarketAlarmDialog
for _, r in ipairs(D.rows) do if r.shown then r.chk:SetChecked(true); r.money:Set(1234) end end
D.save.scripts.OnClick(D.save)
local allMarked = true
for _, r in ipairs(D.rows) do
  local t = r.id and ns.DB.target[r.id]
  if r.shown and r.id and not (ns.HasSignal(r.id) and t and t[r.out and "sell" or "buy"] == 1234) then allMarked = false end
end
check(allMarked and not D.shown, "сигналы на предмет и ингредиенты сохранены со своей ценой")
for _, r in ipairs(D.rows) do if r.id then ns.DB.target[r.id] = nil; ns.DB.alarmDir[r.id] = nil end end
SlashCmdList.WOLFICHMARKET("")
check(not WolfichMarketMainFrame.shown, "/wm закрывает окно")
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
  ns._openBank(ns.charKey)
  check(ns._mainPops.bank and ns._mainPops.bank.dim:IsShown(), "окно «Банк» персонажа открывается")
  ns._mainPops.bank.dim:Hide()
  WolfichMarketMainFrame.tabs[3].scripts.OnClick(WolfichMarketMainFrame.tabs[3])
  local row = recRow(ns._mainCraft.list)
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
  -- «План» во вкладке «Крафт» у аукциониста
  do
    ns.AHSelectTab(4)
    local pg = ns._ahPages[4]
    local row = pg.list.rows[1]
    if row and row.data then
      local rid = row.data.pr.rec.id
      local function cnt() for _, p in ipairs(ns.Plans()) do if p.id == rid and p.ck == ns.charKey then return p.n end end return 0 end
      local b0 = cnt()
      row.plan.scripts.OnClick(row.plan)
      check(cnt() == b0 + 1, "«Крафт» у аукциониста: кнопка «План» добавляет порцию")
      for i, p in ipairs(ns.Plans()) do if p.id == rid and p.ck == ns.charKey then if b0 == 0 then ns.RemovePlan(i) else p.n = b0 end break end end
    else check(false, "«Крафт» у аукциониста: нет строк") end
  end
  ns.AHSelectTab(5)
  check(ns._ahPages[5]:IsShown() and #ns._ahPages[5].items.data >= 2, "вкладка «План» у аукциониста со списком покупок")
  do
    ns.DB.ntah = ns.DB.ntah or {}
    ns.DB.ntah[ns.realmKey] = ns.DB.ntah[ns.realmKey] or { t = time(), items = {} }
    ns.DB.ntah[ns.realmKey].items[3470] = { p = 1, q = 5 }
    ns._ahPages[5].refresh()
    local txt
    local ids = {}
    for _, r in ipairs(ns._ahPages[5].items.rows or {}) do if r.data then ids[#ids + 1] = r.data.id .. ":" .. r.data.buy; if r.data.id == 3470 then txt = r.cnt.text end end end
    check(txt and (txt:find("Общ", 1, true) or txt:find("N", 1, true)), "план: пометка, где материал дешевле (" .. tostring(txt) .. ")")
    ns.DB.ntah[ns.realmKey].items[3470] = nil
  end
  ns.OpenBuy(3470, 5, true)
  check(ns._ahPages[2].qty:GetText() == 5, "«Купить» из плана подставляет количество")
  ns.ClearPlans()
  check(#ns.Plans() == 0, "план очищается")
  local row = recRow(ns._mainCraft.list)
  if row and row.data then
    row.scripts.OnClick(row)
    local card = ns._mainCraft.card
    card.portion:SetText("3"); card.portion.scripts.OnEnterPressed(card.portion)
    card.plan.scripts.OnClick(card.plan)
    check(#ns.Plans() == 1 and ns.Plans()[1].n == 3, "«Запланировать» в карточке сохраняет порции")
    ns.ClearPlans()
  end
end
-- «Продать»: лупа у выбранного предмета, график - в раскрытии строки
do
  ns.AHSelectTab(3)
  local f = ns._ahPages[3]
  local row = f.list.rows[1]
  if row and row.data then
    row.scripts.OnClick(row)
    check(f.searchBtn:IsShown() and f.chartBtn == nil, "«Продать»: у выбранного предмета лупа, кнопки графика нет")
    row.tri.scripts.OnClick(row.tri)
    check(f.list.det and f.list.det:IsShown() and f.list.det.id == row.data.id, "«Продать»: треугольник раскрывает подробности и график")
    row.tri.scripts.OnClick(row.tri)
    check(not f.list.det:IsShown(), "«Продать»: повторный клик сворачивает")
    do
      local ch = ns.UI.Chart(UIParent)
      if ch then
        ch:SetPoints({ { 1000, 500, 100 }, { 2000, 480, 70 }, { 3000, 470, 90 }, { 4000, 460, 40 } })
        local shown = 0; for _, l in ipairs(ch.slines) do if l.shown ~= false then shown = shown + 1 end end
        check(#ch.slines == 3 and #ch.bars == 0, "график: вместо столбиков - вторая линия «продано»")
        check(ch.slabels[3] and (ch.slabels[3].text or ""):find("50", 1, true), "график: шкала проданных справа (макс 50 шт)")
      end
    end
    local oldC = C_Item
    C_Item = setmetatable({ GetItemCount = function() return 37 end }, { __index = oldC or {} })
    f.qty:SetText(1); f.qtyAll.scripts.OnClick(f.qtyAll)
    check(tonumber(f.qty:GetText()) == 37, "«Продать»: «Все» ставит всё количество из сумок")
    C_Item = oldC
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
-- покупка товара: цена пересчитывается сама при изменении количества
do
  ns.ahOpen = true
  ns.OpenBuy(2840)
  fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2840)
  local f = ns._ahPages[2]
  startedBuy = nil
  f.qty:SetText("15"); f.qty.scripts.OnTextChanged(f.qty, true)
  check(startedBuy and startedBuy[2] == 15, "при изменении количества цена запрашивается сама")
  check(f.confirm.enabled ~= false, "«Купить» активна сразу после изменения количества")
  startedBuy, confirmedBuy = nil, nil
  f.confirm.scripts.OnClick(f.confirm)
  check(startedBuy and startedBuy[2] == 15 and not confirmedBuy, "первое нажатие без точной цены - узнаёт цену")
  fire("COMMODITY_PRICE_UPDATED", 101, 1515)
  f.confirm.scripts.OnClick(f.confirm)
  check(confirmedBuy and confirmedBuy[2] == 15, "второе нажатие - покупка")
  f.qty:SetText("999"); f.qty.scripts.OnTextChanged(f.qty, true)
  check(f.total.text:find("30", 1, true) ~= nil, "больше, чем есть на аукционе - предупреждение")
end
-- «Обновить цены» по вкладке; «План»: свои материалы - отдельно сумки и банк, галочка
do
  ns.ahOpen = true
  local rec = { id = 9002, name = "Тест", out = 2841, reag = { { 2840, 3 }, { 3470, 2 } } }
  ns.ClearPlans(); ns.AddPlan(rec, ns.charKey, "Кузнечное дело", 2)
  ns.AHSelectTab(5)
  local asked = {}
  local oldQ = C_AuctionHouse.SendSearchQuery
  C_AuctionHouse.SendSearchQuery = function(k) asked[#asked + 1] = k.itemID end
  ns.QuickRefresh()
  for _ = 1, 200 do advance(1) end
  local got = {}; for _, id in ipairs(asked) do got[id] = true end
  local recs = 0; for _, p in pairs(ns.DB.chars[ns.charKey].profs) do for _, r in ipairs(p.recipes or {}) do if r.out and got[r.out] then recs = recs + 1 end end end
  check(got[2840] and got[3470] and got[2841] and recs > 0 and not ns.QuickBusy(), "«Обновить цены»: сумки, рецепты моих профессий и план")
  ns.QuickRefresh(); ns.QuickRefresh()
  check(not ns.QuickBusy(), "повторное нажатие останавливает обновление")
  asked = {}; C_AuctionHouse.SendSearchQuery = function(k) asked[#asked + 1] = k.itemID end
  ns.QuickRefresh(ns.RecipePriceIDs(rec))
  for _ = 1, 20 do advance(1) end
  C_AuctionHouse.SendSearchQuery = oldQ
  check(#asked == 3, "цены рецепта из карточки")
  local d = ns.PlanNeeds()[1]
  check(d.bags ~= nil and d.bank ~= nil, "план: отдельно в сумках и в банке")
  ns.DB.settings.planUseStock = false
  local all = true; for _, x in ipairs(ns.PlanNeeds()) do if x.buy ~= x.need then all = false end end
  check(all, "план без своих материалов - докупить всё")
  ns.DB.settings.planUseStock = nil
  local prs, tot = ns.PlanProfit()
  check(prs[1] and prs[1].cost > 0 and tot.cost == prs[1].cost, "план: стоимость материалов партии")
  check(ns._ahPages[5].profit and ns._ahPages[5].upd, "план: строка прибыли и своя кнопка обновления цен")
  ns.AHSelectTab(5)
  asked = {}; C_AuctionHouse.SendSearchQuery = function(k) asked[#asked + 1] = k.itemID end
  ns._ahPages[5].upd.scripts.OnClick(ns._ahPages[5].upd)
  for _ = 1, 20 do advance(1) end
  C_AuctionHouse.SendSearchQuery = oldQ
  check(#asked == 3, "«Обновить цены плана» - только рецепты плана")
  ns.ClearPlans()
end
-- стоимость сумок: полная, «Сбросить» (только новое), «Обновить»
do
  ns.UpdateBagValue()
  local full = ns.BagValue()
  check(full > 0 and WolfichMarketBagValue and WolfichMarketBagValue:IsShown(), "над сумками строка с оценкой стоимости")
  ns.BagReset()
  check(ns.BagValue() == 0, "«Сбросить»: уже лежащее не считается")
  local oldI = C_Container.GetContainerItemInfo
  C_Container.GetContainerItemInfo = function(b, s2) local r = oldI(b, s2); if r and s2 == 1 then r = { itemID = r.itemID, stackCount = r.stackCount + 4 } end; return r end
  local farmed = ns.BagValue()
  check(farmed > 0 and farmed < full, "после сброса считается только нафармленное")
  C_Container.GetContainerItemInfo = oldI
  ns.BagFull()
  check(ns.BagValue() == full, "«Обновить»: снова полная стоимость")
end
-- снимок приходит частями: обработка только когда число лотов перестало расти
do
  ns.ahOpen = true; ns.DB.ahLastReq = 0
  local oldN = C_AuctionHouse.GetNumReplicateItems
  local full, shown = oldN(), 1
  C_AuctionHouse.GetNumReplicateItems = function() return math.min(shown, full) end
  ns.StartScan(); fire("REPLICATE_ITEM_LIST_UPDATE")
  for _ = 1, full do advance(1); shown = shown + 1 end -- пока растёт - ждём
  for _ = 1, 15 do advance(1) end
  C_AuctionHouse.GetNumReplicateItems = oldN
  check(ns.CurrentScan().lots == full and not ns.ScanBusy(), "снимок ждёт все части аукциона")
end
-- «Где взять»: источники рецепта из данных Wowhead WoW Forever
do
  local rec = { id = 6617, name = "Зелье ярости", learned = false }
  local lines = ns.RecipeSourceLines(rec)
  local vend, item = 0, false
  for _, l in ipairs(lines) do if l.kind == "vendor" then vend = vend + 1 end; if l.kind == "item" then item = true end end
  check(item and vend >= 1, "«Где взять»: предмет-рецепт и продавцы (" .. vend .. ")")
  local tr = ns.RecipeSourceLines({ id = 2329, name = "x" })
  check(tr[1] and tr[1].kind == "trainer", "«Где взять»: рецепт у тренера")
  check(ns.RecipeSourceLines({ id = 1, name = "нет такого" })[1].kind == "none", "«Где взять»: нет данных - так и пишет")
  local hasXY = false
  for _, l in ipairs(lines) do if l.kind == "vendor" and l.detail:find("%d+%.%d, %d+%.%d") then hasXY = true end end
  check(hasXY, "«Где взять»: у продавцов координаты с Wowhead")
  ns.ShowSources(rec)
  check(WolfichMarketSourceDialog and WolfichMarketSourceDialog:IsShown() and #WolfichMarketSourceDialog.list.data > 0, "окно «Где взять» открывается")
end
-- группы по навыку, «чужая» профессия, сигналы покупки/продажи
do
  check(ns.SkillTier(10) == 1 and ns.SkillTier(75) == 2 and ns.SkillTier(230) == 4 and ns.SkillTier(305) == 5 and ns.SkillTier(nil) == 9, "группы рецептов по требуемому навыку")
  local hasHdr = false
  for _, d in ipairs(ns._mainCraft.list.data) do if d.header then hasHdr = true end end
  check(hasHdr, "в списке рецептов есть заголовки групп по навыку")
  local name = ns.AddVirtualProfession(ns.charKey, "tailoring")
  local p = ns.DB.chars[ns.charKey].profs[name]
  check(p and p.virtual and #p.recipes > 100, "добавлена профессия, которой нет: " .. tostring(name) .. " (" .. (p and #p.recipes or 0) .. ")")
  local rows = ns.AllRecipeProfits(name, false)
  check(#rows > 100 and not ns.IsLearned(rows[1].rec), "её рецепты видны (серым) без галочки неизученных")
  ns.CleanStrangers()
  check(ns.DB.chars[ns.charKey].profs[name] ~= nil, "чистка чужих профессий не трогает добавленную вручную")
  ns.RemoveProfession(ns.charKey, name)
  ns.AddSignal(3470, "buy")
  check(ns.DB.alarmDir[3470] == "buy", "сигнал покупки")
  local fav = ns.IsMarked(3470)
  ns.AddSignal(3470, "sell")
  check(ns.DB.alarmDir[3470] == "both" and ns.IsMarked(3470) == fav, "предмет в обоих списках, избранное не тронуто")
  ns.RemoveSignal(3470, "buy")
  check(ns.DB.alarmDir[3470] == "sell", "убран из покупки - остался в продаже")
  ns.RemoveSignal(3470, "sell")
  check(ns.DB.alarmDir[3470] == nil and not ns.HasSignal(3470), "убран из обоих - сигнала нет")
end
-- удалённая профессия сразу пропадает из очереди «Обновить цены»
do
  ns.ahOpen = true
  ns.DB.settings.showUnlearned = true
  local name = ns.AddVirtualProfession(ns.charKey, "tailoring")
  local mine = {}
  for _, r in ipairs(ns.DB.chars[ns.charKey].profs[name].recipes) do if r.out then mine[r.out] = true end end
  local asked = {}
  local oldQ = C_AuctionHouse.SendSearchQuery
  C_AuctionHouse.SendSearchQuery = function(k) asked[#asked + 1] = k.itemID end
  ns.QuickRefresh()
  for _ = 1, 3 do advance(1) end
  ns.RemoveProfession(ns.charKey, name)
  local cut = #asked
  for _ = 1, 600 do advance(1); if not ns.QuickBusy() then break end end
  C_AuctionHouse.SendSearchQuery = oldQ
  local after = 0
  for k = cut + 1, #asked do if mine[asked[k]] then after = after + 1 end end
  check(after < 5 and not ns.QuickBusy(), "удалённая профессия убрана из очереди «Обновить цены» (осталось " .. after .. ")")
  ns.DB.settings.showUnlearned = nil
end
-- сигналы общие для персонажей; у сигнала видна цена срабатывания
do
  ns.AddSignal(3470, "sell")
  ns.DB.settings.aucView = "signals"
  WolfichMarketMainFrame.tabs[4].scripts.OnClick(WolfichMarketMainFrame.tabs[4])
  ns.DB.settings.aucView = "all"
  local row; for _, r in ipairs(ns._mainSig and ns._mainSig.sell.rows or {}) do if r.data and r.data.id == 3470 then row = r end end
  check(row and row.money, "в строке сигнала - поле своей цены продажи")
  -- ввод цены «с клавиатуры»: 1 золотой
  local box = row and row.money.boxes[1]
  if box then box:SetText("1"); box.scripts.OnTextChanged(box, true) end
  check(ns.DB.target[3470] and ns.DB.target[3470].sell == 10000, "своя цена продажи сохранена: " .. tostring(ns.DB.target[3470] and ns.DB.target[3470].sell))
  -- твинк делает снимок - сигнал по отметке основы приходит
  local main = ns.charKey
  ns.charKey = "Твинк-CAMWOWEU4Realm6PvP"; ns.DB.chars[ns.charKey] = ns.DB.chars[ns.charKey] or { profs = {} }
  played = false
  ns.Fire("SCAN_DONE", { t = time(), items = { [3470] = { 9000, 5, 1 } } }, nil)
  check(not played, "цена ниже своей цены продажи - сигнала нет")
  ns.Fire("SCAN_DONE", { t = time(), items = { [3470] = { 12000, 5, 1 } } }, nil)
  check(played, "твинк при снимке получает сигнал по общему списку (цена дошла до своей)")
  played = false
  ns.Fire("SCAN_DONE", { t = time(), items = { [3470] = { 12500, 5, 1 } } }, nil)
  check(not played, "повторно, пока цена выше, сигнал не дублируется")
  -- покупка: цена опустилась до своей
  ns.AddSignal(2840, "buy"); ns.DB.target[2840] = { buy = 500 }
  ns.Fire("SCAN_DONE", { t = time(), items = { [2840] = { 450, 5, 1 } } }, nil)
  check(played, "сигнал покупки - цена опустилась до своей")
  ns.charKey = main
  ns.RemoveSignal(3470, "sell"); ns.RemoveSignal(2840, "buy")
  check(ns.DB.target[3470] == nil and ns.DB.target[2840] == nil, "убранный сигнал забывает свою цену")
  WolfichMarketMainFrame.tabs[3].scripts.OnClick(WolfichMarketMainFrame.tabs[3])
end
-- разбор плотных сообщений C/R (2.29+): список номеров предметов
function zids(m)
  local kind, body = m:match("^([CR])%^[^%^]+%^[^%^]+%^(.*)$")
  if not kind then return {} end
  local nums = ns._zdec(body); local step = kind == "C" and 3 or 2
  local out, id = {}, 0
  for i = 1, #nums - step + 1, step do id = (i == 1) and nums[i] or (id + nums[i]); out[#out + 1] = id end
  return out, kind
end
-- плотная запись: туда-обратно, только изменения, без количества в остальном аукционе
do
  for _, n in ipairs({ 0, 1, 44, 45, 46, 2024, 99999, 3500000, 123456789 }) do
    local d = ns._zdec(ns._zenc(n) .. ns._zenc(7))
    check(d[1] == n and d[2] == 7, "плотная запись числа " .. n .. " -> " .. tostring(d[1]))
  end
  for k in pairs(ns._netQueue) do ns._netQueue[k] = nil end
  local sent = {}
  C_ChatInfo = C_ChatInfo or {}
  local oldS, oldG = C_ChatInfo.SendAddonMessage, GetChannelName
  GetChannelName = function() return 6 end
  C_ChatInfo.SendAddonMessage = function(p, m) sent[#sent + 1] = m; return 0 end
  local items = {}
  for i = 1, 400 do items[600000 + i * 3] = { 1000 + i * 37, i % 9 + 1, 1 } end
  local T = time() + 70000
  ns._netResetSent(); ns.ShareScan({ t = T, items = items })
  for _ = 1, 400 do advance(0.2) end
  local bytes, cnt = 0, 0
  local uniq = {}
  for _, m in ipairs(sent) do local ids = zids(m); if #ids > 0 then bytes = bytes + #m; for _, id in ipairs(ids) do if items[id] and not uniq[id] then uniq[id] = true; cnt = cnt + 1 end end end end
  check(cnt == 400, "плотная запись: ушли все 400 цен (" .. cnt .. ")")
  check(bytes / cnt < 8, string.format("плотная запись: %.1f символа на цену (было ~14)", bytes / cnt))
  local hasR = false; for _, m in ipairs(sent) do if m:sub(1, 2) == "R^" then hasR = true end end
  check(hasR, "остальной аукцион - без количества (R)")
  local clean = true
  for _, m in ipairs(sent) do if m:find("[^%w%^~,;%.]") then clean = false; print("BAD", m) end end
  check(clean, "в сообщениях только буквы, цифры и разделители")
  -- приём: другой игрок разбирает эти же сообщения
  local rk = ns.NetKey()
  for _, m in ipairs(sent) do ns._netReceive("WolfMkt2", m, "CHANNEL", "Зеркало-Realm") end
  local mineNet = ns.DB.net and ns.DB.net[ns.realmKey] or { items = {} }
  local okAll = true
  for id, r in pairs(items) do local x = mineNet.items[id]; if not x or x[1] ~= r[1] then okAll = false end end
  check(okAll, "плотная запись: цены разобраны верно")
  -- вторая рассылка: изменилась одна цена - уходит только она (плюс сигналы и рецепты)
  sent = {}
  local items2 = {}; for id, r in pairs(items) do items2[id] = { r[1], r[2], 1 } end
  items2[600003][1] = 5555
  ns._netSeen.active = -1000 -- чужая рассылка (зеркало) закончилась
  ns.ShareScan({ t = T + 900, items = items2 })
  for _ = 1, 100 do advance(0.2) end
  local restIds = {}
  for _, m in ipairs(sent) do local ids, kind = zids(m); if kind == "R" then for _, id in ipairs(ids) do restIds[#restIds + 1] = id end end end
  check(#restIds == 1 and restIds[1] == 600003, "повторная рассылка - только изменившиеся цены (" .. #restIds .. ")")
  local hd; for _, m in ipairs(sent) do if m:sub(1, 2) == "H^" then hd = m end end
  check(hd and hd:sub(-2) == "^d", "заголовок помечен «только изменения»")
  -- по запросу (Q) - целиком
  sent = {}
  ns.ShareScan({ t = T + 1000, items = items2 }, "force")
  for _ = 1, 400 do advance(0.2) end
  local c2, u2 = 0, {}; for _, m in ipairs(sent) do for _, id in ipairs((zids(m))) do if items2[id] and not u2[id] then u2[id] = true; c2 = c2 + 1 end end end
  check(c2 == 400, "/wmnetsend - весь аукцион целиком (" .. c2 .. ")")
  -- по запросу Q, если целиком было меньше 10 минут назад - только отличия
  sent = {}
  items2[600006][1] = 4444
  ns.ShareScan({ t = T + 1100, items = items2 }, true)
  for _ = 1, 100 do advance(0.2) end
  local c3 = 0; for _, m in ipairs(sent) do c3 = c3 + #(zids(m)) end
  check(c3 == 1, "обычная рассылка - всегда только отличия (" .. c3 .. ")")
  -- пока рассылает другой игрок - своя рассылка ждёт, потом только отличия от пришедшего
  sent = {}
  ns._netReceive("WolfMkt3", "H^" .. ns.NetKey() .. "^" .. "zzzzz0" .. "^1^2.29^0^d", "CHANNEL", "Другой-Realm")
  items2[600009][1] = 3333
  ns.ShareScan({ t = T + 1200, items = items2 })
  advance(1)
  local early = 0; for _, m in ipairs(sent) do early = early + #(zids(m)) end
  check(early == 0, "пока рассылает другой - своя рассылка ждёт")
  for _ = 1, 300 do advance(0.5) end
  local c4 = 0; for _, m in ipairs(sent) do c4 = c4 + #(zids(m)) end
  check(c4 == 1, "после чужой рассылки - отправлены только отличия (" .. c4 .. ")")
  -- в сети цены уже такие же - ничего не шлём
  sent = {}
  ns.ShareScan({ t = T + 1300, items = items2 })
  for _ = 1, 50 do advance(0.2) end
  local priceMsgs = 0; for _, m in ipairs(sent) do if #(zids(m)) > 0 then priceMsgs = priceMsgs + 1 end end
  local hasH = false; for _, m in ipairs(sent) do if m:sub(1, 2) == "H^" then hasH = true end end
  check(priceMsgs == 0 and hasH, "цены в сети такие же - цен не шлём, только подтверждение времени (H/E)")
  -- получатель: рассылка без изменений обновляет время его цен; пропавшие с аукциона - убираются
  do
    local enc = function(x) local D = "0123456789abcdefghijklmnopqrstuvwxyz"; local s2 = ""; x = math.floor(x); repeat local d = x % 36; s2 = D:sub(d + 1, d + 1) .. s2; x = math.floor(x / 36) until x == 0; return s2 end
    local rk2 = ns.NetKey()
    local net = ns.DB.net[ns.realmKey]
    net.items[600012] = { 777, 1, T - 5000 }       -- старое время, цена не менялась
    net.items[600015] = { 888, 1, T - 5000 }       -- пропадёт с аукциона
    local t5 = T + 5000
    ns._netSeen.active = -1000
    ns._netReceive("WolfMkt1", "H^" .. rk2 .. "^" .. enc(t5) .. "^0^2.42^0^d", "CHANNEL", "Сверщик-Realm")
    ns._netReceive("WolfMkt1", "X^" .. rk2 .. "^" .. enc(t5) .. "^" .. ns._zenc(600015), "CHANNEL", "Сверщик-Realm")
    ns._netReceive("WolfMkt1", "E^" .. rk2 .. "^" .. enc(t5), "CHANNEL", "Сверщик-Realm")
    advance(1)
    check(net.items[600012] and net.items[600012][3] == t5 and net.items[600012][1] == 777, "цена без изменений: время обновлено на время снимка")
    check(net.items[600015] == nil, "пропавший с аукциона предмет убран")
    net.items[600012] = nil
  end
  -- новичок спрашивает цены (Q): весь аукцион целиком - лично ему шёпотом; в сеть - только «A» (я отвечаю)
  local log = {}
  C_ChatInfo.SendAddonMessage = function(p, m, ch, target) log[#log + 1] = { m = m, ch = ch, to = target }; return 0 end
  local oldScan = ns.DB.ahScans[ns.realmKey]
  ns.DB.ahScans[ns.realmKey] = { t = T + 1300, items = items2 }
  ns._netReceive("WolfMkt1", "Q^" .. ns.NetKey() .. "^0", "CHANNEL", "Новичок-Realm")
  for _ = 1, 400 do advance(0.25) end
  local toHim, toAll, aMsg = {}, 0, false
  for _, e in ipairs(log) do
    if e.ch == "WHISPER" and e.to == "Новичок-Realm" then for _, id in ipairs((zids(e.m))) do toHim[id] = true end
    elseif e.m:sub(1, 2) == "A^" then aMsg = true
    elseif #(zids(e.m)) > 0 then toAll = toAll + 1 end
  end
  local nHim = 0; for _ in pairs(toHim) do nHim = nHim + 1 end
  check(nHim == 400 and toAll == 0 and aMsg, "запрос новичка: весь аукцион лично ему (" .. nHim .. "), в сеть ничего (" .. toAll .. ")")
  -- второй такой же запрос, когда ему уже отвечает другой (A) - не отвечаем
  log = {}
  ns._netReceive("WolfMkt1", "A^" .. ns.NetKey() .. "^Новичок2-Realm", "CHANNEL", "Кто-то-Realm")
  ns._netReceive("WolfMkt1", "Q^" .. ns.NetKey() .. "^0", "CHANNEL", "Новичок2-Realm")
  for _ = 1, 60 do advance(0.25) end
  local whisp = 0; for _, e in ipairs(log) do if e.ch == "WHISPER" then whisp = whisp + 1 end end
  check(whisp == 0, "новичку уже отвечает другой игрок - второй ответ не шлём")
  ns.DB.ahScans[ns.realmKey] = oldScan
  C_ChatInfo.SendAddonMessage = function(p, m) sent[#sent + 1] = m; return 0 end
  C_ChatInfo.SendAddonMessage, GetChannelName = oldS, oldG
  for k in pairs(ns._netQueue) do ns._netQueue[k] = nil end
  ns._netResetSent()
  local net = ns.DB.net and ns.DB.net[ns.realmKey]; if net then net.t = nil; for id in pairs(items) do net.items[id] = nil end end
end
-- общий рынок: трафик не превышает лимит (иначе сервер разрывает связь), остальной аукцион - только в канал
do
  for k in pairs(ns._netQueue) do ns._netQueue[k] = nil end
  local bytes, byRoute = {}, {}
  local oldS = C_ChatInfo and C_ChatInfo.SendAddonMessage
  C_ChatInfo = C_ChatInfo or {}
  local prefixes = {}
  C_ChatInfo.SendAddonMessage = function(p, m, ch) prefixes[p] = (prefixes[p] or 0) + 1; local now = math.floor(GetTime()); bytes[now] = (bytes[now] or 0) + #m + 40; byRoute[ch] = (byRoute[ch] or 0) + 1 end
  local oldG, oldGuild = GetChannelName, IsInGuild
  GetChannelName = function() return 5 end; IsInGuild = function() return true end
  local items = {}
  for i = 1, 20000 do items[500000 + i * 7] = { 100 + i * 13, 3, 1 } end
  ns._netResetSent(); ns.ShareScan({ t = time() + 1, items = items })
  local t0 = math.floor(GetTime())
  for _ = 1, 1200 do advance(0.1) end
  local total, peak = 0, 0
  for sec, b in pairs(bytes) do total = total + b; if b > peak then peak = b end end
  local rate, burst = ns._netBudget()
  check(total <= rate * 121 + burst, "общий рынок: за 2 мин отправлено " .. total .. " байт - не больше лимита " .. (rate * 121 + burst))
  check(peak <= burst + rate, "общий рынок: нет всплесков (пик " .. peak .. " байт/с)")
  check((byRoute.CHANNEL or 0) > (byRoute.GUILD or 0) and (byRoute.GUILD or 0) >= 1, "общий рынок: остальной аукцион - только в канал (канал " .. tostring(byRoute.CHANNEL) .. ", гильдия " .. tostring(byRoute.GUILD) .. ")")
  local np = 0; for _ in pairs(prefixes) do np = np + 1 end
  check(np == 4, "турбо: рассылка через 4 служебных имени (" .. np .. ")")
  local sentTurbo = 0; for _, v in pairs(byRoute) do sentTurbo = sentTurbo + v end
  for k in pairs(ns._netQueue) do ns._netQueue[k] = nil end
  for _ = 1, 5 do advance(1) end
  -- без турбо: одно имя, медленнее
  ns.DB.settings.netTurbo = false
  prefixes, byRoute, bytes = {}, {}, {}
  ns._netResetSent(); ns.ShareScan({ t = time() + 2, items = items })
  for _ = 1, 1200 do advance(0.1) end
  np = 0; for _ in pairs(prefixes) do np = np + 1 end
  local sentNormal = 0; for _, v in pairs(byRoute) do sentNormal = sentNormal + v end
  check(np == 1 and sentNormal < sentTurbo, "без турбо: одно имя и медленнее (" .. sentNormal .. " против " .. sentTurbo .. " сообщ. за 2 мин)")
  local total2 = 0; for _, b2 in pairs(bytes) do total2 = total2 + b2 end
  local r2, b2 = ns._netBudget()
  check(total2 <= r2 * 121 + b2, "без турбо: не больше лимита")
  local n1, f1 = ns.NetSendTime(28000, 100)
  check(f1 < n1, "оценка времени: турбо быстрее (" .. math.floor(f1) .. " с против " .. math.floor(n1) .. " с)")
  ns.DB.settings.netTurbo = nil
  for k in pairs(ns._netQueue) do ns._netQueue[k] = nil end
  for _ = 1, 5 do advance(1) end
  C_ChatInfo.SendAddonMessage = oldS; GetChannelName = oldG; IsInGuild = oldGuild
end
-- общий рынок: свой снимок рассылается, чужие цены принимаются (только для своего аукциона)
do
  local q = ns._netQueue
  for k in pairs(q) do q[k] = nil end
  local sent = {}
  local oldS = C_ChatInfo and C_ChatInfo.SendAddonMessage
  C_ChatInfo = C_ChatInfo or {}
  C_ChatInfo.SendAddonMessage = function(p, m) sent[#sent + 1] = m end
  local oldG = GetChannelName; GetChannelName = function() return 5 end
  ns._netResetSent(); ns.ShareScan({ t = time(), items = { [2840] = { 150, 30, 2 }, [999999] = { 5, 1, 1 } } })
  for _ = 1, 90 do advance(1) end
  local hasP = false; for _, m in ipairs(sent) do if m:sub(1, 2) == "C^" or m:sub(1, 2) == "R^" then hasP = true end end
  local hasH, hasE = false, false; for _, m in ipairs(sent) do if m:sub(1, 2) == "H^" then hasH = true end; if m:sub(1, 2) == "E^" then hasE = true end end
  check(hasH and hasP and hasE, "общий рынок: снимок рассылается (" .. #sent .. " сообщ.)")
  -- приём от другого игрока
  local enc = function(n) local D = "0123456789abcdefghijklmnopqrstuvwxyz"; local s = ""; n = math.floor(n); repeat local d = n % 36; s = D:sub(d + 1, d + 1) .. s; n = math.floor(n / 36) until n == 0; return s end
  local t = time() + 5000
  local rk = ns.NetKey()
  ns._netReceive("WolfMkt1", "H^" .. rk .. "^" .. enc(t) .. "^1^2.19", "CHANNEL", "Друг-Realm")
  ns._netReceive("WolfMkt1", "P^" .. rk .. "^" .. enc(t) .. "^" .. enc(2840) .. "," .. enc(160) .. "," .. enc(40) .. ";", "CHANNEL", "Друг-Realm")
  ns._netReceive("WolfMkt1", "E^" .. rk .. "^" .. enc(t), "CHANNEL", "Друг-Realm")
  check(ns.AHPrice(2840) == 160, "общий рынок: цена от другого игрока принята")
  ns._netReceive("WolfMkt1", "H^Чужой~PvE^" .. enc(t + 10) .. "^1^2.19", "CHANNEL", "Враг-Realm")
  ns._netReceive("WolfMkt1", "P^Чужой~PvE^" .. enc(t + 10) .. "^" .. enc(2840) .. "," .. enc(9) .. ",1;", "CHANNEL", "Враг-Realm")
  ns._netReceive("WolfMkt1", "E^Чужой~PvE^" .. enc(t + 10), "CHANNEL", "Враг-Realm")
  check(ns.AHPrice(2840) == 160, "общий рынок: цены чужого аукциона не принимаются")
  -- «что нужно»: список сигналов другого игрока - первым в рассылке, найденная поиском цена пересылается
  ns._netReceive("WolfMkt1", "W^" .. rk .. "^" .. enc(3470) .. ",", "CHANNEL", "Друг-Realm")
  check(ns.NetWanted()[3470], "общий рынок: получен список сигналов другого игрока")
  sent = {}
  ns._netResetSent(); ns.ShareScan({ t = time() + 6000, items = { [2840] = { 150, 30, 2 }, [3470] = { 90, 5, 1 } } })
  for _ = 1, 90 do advance(1) end
  local firstP; for _, m in ipairs(sent) do if m:sub(1, 2) == "C^" then firstP = m; break end end
  check(firstP and (function() for _, id in ipairs(zids(firstP)) do if id == 3470 then return true end end end)(), "общий рынок: чужие сигналы рассылаются первыми")
  sent = {}
  ns.SeenPrice(3470, 95, 7)
  for _ = 1, 12 do advance(1) end
  local hasS = false; for _, m in ipairs(sent) do if m:sub(1, 2) == "S^" then hasS = true end end
  check(hasS, "общий рынок: найденная поиском цена нужного предмета пересылается")
  ns._netReceive("WolfMkt1", "S^" .. rk .. "^" .. enc(time() + 9000) .. "^" .. enc(2840) .. "," .. enc(170) .. ",3;", "CHANNEL", "Друг2-Realm")
  check(ns.AHPrice(2840) == 170, "общий рынок: отдельная свежая цена принята")
  ns.DB.net = nil
  C_ChatInfo.SendAddonMessage = oldS; GetChannelName = oldG
end
-- /wm net: проверка общего рынка без ошибок; друзья онлайн - отдельный маршрут
do
  C_FriendList = { GetNumFriends = function() return 1 end, GetFriendInfoByIndex = function() return { connected = true, name = "Друг" } end }
  for k in pairs(ns._netInChannel) do ns._netInChannel[k] = nil end
  local rs = ns.NetRoutes()
  local fr = false; for _, r in ipairs(rs) do if r[1] == "WHISPER" and r[2] == "Друг" then fr = true end end
  check(fr, "общий рынок: друзья онлайн получают цены личным сообщением аддона")
  printed = {}
  SlashCmdList.WOLFICHMARKET("net")
  local okNet = false; for _, l in ipairs(printed) do if l:find("WHISPER Друг", 1, true) then okNet = true end end
  check(okNet, "/wm net показывает маршруты")
  C_FriendList = nil
end
-- друзья Battle.net в WoW - отдельный маршрут; приём через Battle.net
do
  local bnSent = {}
  BNGetNumFriends = function() return 1 end
  BNSendGameData = function(id, p, m) bnSent[#bnSent + 1] = { id, m } end
  C_BattleNet = { GetFriendNumGameAccounts = function() return 1 end,
    GetFriendGameAccountInfo = function() return { isOnline = true, gameAccountID = 77, characterName = "Латыш", realmName = "Realm" } end,
    GetGameAccountInfoByID = function() return { characterName = "Латыш", realmName = "Realm" } end }
  local bn = false; for _, r in ipairs(ns.NetRoutes()) do if r[1] == "BN" and r[2] == 77 then bn = true end end
  check(bn, "общий рынок: друг Battle.net в WoW - получатель")
  -- друг сидит в канале аддона (от него приходили сообщения через канал) - через Battle.net ему не дублируем
  do
    local oldG = GetChannelName; GetChannelName = function() return 5 end
    ns._netReceive("WolfMkt1", "W^" .. ns.NetKey() .. "^1,", "CHANNEL", "Латыш-Realm")
    local bn2 = false; for _, r in ipairs(ns.NetRoutes()) do if r[1] == "BN" then bn2 = true end end
    check(not bn2, "друг из канала аддона - без дубля через Battle.net")
    for k in pairs(ns._netInChannel) do ns._netInChannel[k] = nil end
    GetChannelName = oldG
  end
  ns._netResetSent(); ns.ShareScan({ t = time(), items = { [2840] = { 150, 30, 2 } } })
  for _ = 1, 30 do advance(1) end
  check(#bnSent > 0, "общий рынок: цены уходят через Battle.net (" .. #bnSent .. ")")
  local enc = function(n) local D = "0123456789abcdefghijklmnopqrstuvwxyz"; local s2 = ""; n = math.floor(n); repeat local d = n % 36; s2 = D:sub(d + 1, d + 1) .. s2; n = math.floor(n / 36) until n == 0; return s2 end
  local rk = ns.NetKey(); local t = time() + 20000
  fire("BN_CHAT_MSG_ADDON", "WolfMkt1", "H^" .. rk .. "^" .. enc(t) .. "^1^2.20", "WHISPER", 77)
  fire("BN_CHAT_MSG_ADDON", "WolfMkt1", "P^" .. rk .. "^" .. enc(t) .. "^" .. enc(2840) .. "," .. enc(222) .. ",4;", "WHISPER", 77)
  fire("BN_CHAT_MSG_ADDON", "WolfMkt1", "E^" .. rk .. "^" .. enc(t), "WHISPER", 77)
  check(ns.AHPrice(2840) == 222, "общий рынок: цены через Battle.net приняты")
  ns.DB.net = nil
  -- большой снимок: крупные сообщения Battle.net не застревают (раньше были больше запаса и не уходили никогда)
  bnSent = {}
  local big = {}; for i = 1, 6000 do big[700000 + i * 11] = { 500 + i * 7, 2, 1 } end
  local okBig = pcall(function() ns._netResetSent(); ns.ShareScan({ t = time() + 30000, items = big }) end)
  for _ = 1, 600 do advance(0.5) end
  local bnIds = {}
  for _, e in ipairs(bnSent) do for _, id in ipairs((zids(e[2]))) do bnIds[id] = true end end
  local nb = 0; for id in pairs(bnIds) do if big[id] then nb = nb + 1 end end
  check(okBig and nb == 6000, "Battle.net: большой снимок дошёл целиком (" .. nb .. " из 6000)")
  -- один снимок пришёл двумя путями под разными именами, цены - только одним: принят без «вышел из игры»
  ns.DB.net = nil
  for k in pairs(ns._netQueue) do ns._netQueue[k] = nil end
  local t2 = time() + 40000
  local hdr = "H^" .. rk .. "^" .. enc(t2) .. "^" .. enc(2) .. "^2.31^" .. enc(2) .. "^d"
  printed = {}; for k in pairs(ns.log) do ns.log[k] = nil end; local logStart = 0
  ns._netReceive("WolfMkt1", hdr, "BN", "Сосед Менеджмент")
  ns._netReceive("WolfMkt1", hdr, "CHANNEL", "Сосед-Realm")
  ns._netReceive("WolfMkt2", "C^" .. rk .. "^" .. enc(t2) .. "^" .. ns._zenc(2840) .. ns._zenc(333) .. ns._zenc(5) .. ns._zenc(30) .. ns._zenc(444) .. ns._zenc(6), "CHANNEL", "Сосед-Realm")
  ns._netReceive("WolfMkt1", "E^" .. rk .. "^" .. enc(t2), "CHANNEL", "Сосед-Realm")
  for _ = 1, 20 do advance(10) end
  local lost, took, acc = false, false, 0
  for k = logStart + 1, #ns.log do local m = ns.log[k].msg; if m:find("вышел из игры", 1, true) or m:find("left the game", 1, true) then lost = true end; if m:find("принимаю", 1, true) or m:find("receiving", 1, true) then acc = acc + 1 end end
  check(ns.AHPrice(2840) == 333 and ns.AHPrice(2870) == 444, "снимок двумя путями: цены приняты (" .. tostring(ns.AHPrice(2840)) .. ")")
  check(not lost and acc <= 1, "снимок двумя путями: без «вышел из игры» и одно «принимаю» (" .. acc .. ")")
  ns.DB.net = nil
  BNGetNumFriends, BNSendGameData, C_BattleNet = nil, nil, nil
  printed = {}; SlashCmdList.WOLFICHMARKETNET()
  check(#printed > 2, "/wmnet работает")
end
-- другой сервер того же режима (общий аукцион WoW Forever) - один ключ
do
  local saved = ns.realmKey
  ns.realmKey = "CAMWOWEU4Realm6PvP|Alliance"; local a = ns.NetKey()
  ns.realmKey = "CAMWOWEU5Realm4PvP|Alliance"; local b = ns.NetKey()
  ns.realmKey = "CAMWOWEU5Realm4|Alliance"; local c = ns.NetKey()
  ns.realmKey = "CAMWOWEU5Realm4PvP|Horde"; local d = ns.NetKey()
  ns.realmKey = saved
  check(a == b and a ~= c and a ~= d, "общий рынок: разные сервера одного режима и фракции - один аукцион (" .. a .. ", " .. c .. ", " .. d .. ")")
end
-- старые данные по имени сервера переводятся на общий ключ аукциона
do
  local DB = ns.DB
  local keep = { DB.ahScans, DB.realmKeysV }
  DB.ahScans = { ["CAMWOWEU4Realm6PvP|Alliance"] = { t = 100, items = {} }, ["CAMWOWEU5Realm4PvP|Alliance"] = { t = 200, items = {} } }
  DB.realmKeysV = nil
  ns.MigrateRealmKeys()
  check(DB.ahScans["PvP|Alliance"] and DB.ahScans["PvP|Alliance"].t == 200 and not DB.ahScans["CAMWOWEU4Realm6PvP|Alliance"], "снимки разных серверов одного режима объединены")
  DB.ahScans, DB.realmKeysV = keep[1], keep[2]
end
-- «слишком часто» (ответ 3): сообщение не теряется, а повторяется позже
do
  local got, calls = {}, 0
  local oldS, oldG = C_ChatInfo.SendAddonMessage, GetChannelName
  GetChannelName = function() return 6 end
  C_ChatInfo.SendAddonMessage = function(p, m) calls = calls + 1; if calls % 2 == 1 then return 3 end; got[#got + 1] = m; return 0 end
  ns._netResetSent(); ns.ShareScan({ t = time(), items = { [2840] = { 150, 30, 2 } } })
  for _ = 1, 120 do advance(1) end
  local hasE = false; for _, m in ipairs(got) do if m:sub(1, 2) == "E^" then hasE = true end end
  check(hasE and (ns.netStats.throttled or 0) > 0, "общий рынок: при «слишком часто» сообщения повторяются, а не теряются")
  C_ChatInfo.SendAddonMessage, GetChannelName = oldS, oldG
end
-- вкладка «Настройки» в главном окне
WolfichMarketMainFrame.tabs[6].scripts.OnClick(WolfichMarketMainFrame.tabs[6])
check(WolfichMarketMainFrame.pages[6]:IsShown(), "вкладка «Настройки» в главном окне")
WolfichMarketMainFrame.tabs[3].scripts.OnClick(WolfichMarketMainFrame.tabs[3])
-- весь аукцион: сначала важное; отправитель вышел - сообщение, сколько успело прийти
do
  local enc = function(x) local D = "0123456789abcdefghijklmnopqrstuvwxyz"; local s2 = ""; x = math.floor(x); repeat local d = x % 36; s2 = D:sub(d + 1, d + 1) .. s2; x = math.floor(x / 36) until x == 0; return s2 end
  local sent = {}
  local oldS, oldG = C_ChatInfo.SendAddonMessage, GetChannelName
  GetChannelName = function() return 6 end
  C_ChatInfo.SendAddonMessage = function(p, m) sent[#sent + 1] = m; return 0 end
  ns._netResetSent(); ns.ShareScan({ t = time() + 50000, items = { [2840] = { 150, 30, 2 }, [910001] = { 7, 1, 1 } } })
  for _ = 1, 30 do advance(1) end
  local order = {}
  for _, m in ipairs(sent) do for _, id in ipairs((zids(m))) do order[#order + 1] = id end end
  local pos = {}; for k, id in ipairs(order) do pos[id] = pos[id] or k end
  check(pos[910001] and pos[2840] and pos[2840] < pos[910001], "общий рынок: весь аукцион, рецепты раньше остального")
  C_ChatInfo.SendAddonMessage, GetChannelName = oldS, oldG
  local rk = ns.NetKey(); local t = time() + 60000
  ns._netReceive("WolfMkt1", "H^" .. rk .. "^" .. enc(t) .. "^" .. enc(3) .. "^2.23^" .. enc(1), "CHANNEL", "Ушедший-Realm")
  ns._netReceive("WolfMkt1", "P^" .. rk .. "^" .. enc(t) .. "^" .. enc(2840) .. "," .. enc(175) .. ",3;", "CHANNEL", "Ушедший-Realm")
  for _ = 1, 140 do advance(1) end
  local msg; for _, e in ipairs(ns.log) do if e.msg:find("Ушедший", 1, true) and (e.msg:find("1 из 3", 1, true) or e.msg:find("1 of 3", 1, true)) then msg = e.msg end end
  check(msg and ns.AHPrice(2840) == 175, "общий рынок: отправитель вышел - пришедшее применено и есть сообщение: " .. tostring(msg))
  ns.DB.net = nil
end
-- 2.43: новое главное окно - разделы, твинки, лоты, кулдауны, раскрытие строк, колокольчик
do
  local W = WolfichMarketMainFrame
  -- твинки: золото и место записываются, лоты читаются с аукциона, продажа - по сообщению игры и письму
  GetMoney = function() return 1506100 end; UnitLevel = function() return 10 end; UnitRace = function() return "Человек" end; GetRealZoneText = function() return "Штормград" end
  ns.SnapshotChar()
  local me = ns.DB.chars[ns.charKey]
  check(me.money == 1506100 and me.level == 10 and me.zone == "Штормград" and me.seen, "твинки: золото, уровень и место персонажа записаны")
  -- раздел «Твинки»: карточки и окно банка
  W.tabs[2].scripts.OnClick(W.tabs[2])
  local card; for _, c in ipairs(ns._mainAlts.cards) do if c.ck == ns.charKey then card = c end end
  check(card and card.rows[1][2].text ~= "" and card.env == nil and card.auc == nil, "«Твинки»: карточка персонажа с золотом, без лотов")
  card.bank.scripts.OnClick(card.bank)
  check(ns._mainPops.bank.dim:IsShown(), "окно «Банк» с карточки персонажа")
  ns._mainPops.bank.dim:Hide()
  local A = ns._mainAuc
  ns.DB.settings.aucView = "all"; ns.DB.settings.aucMode = "main"; W.tabs[4].scripts.OnClick(W.tabs[4])
  local r1 = A.all.list.rows[1]
  if r1 and r1.data then
    r1.scripts.OnClick(r1)
    local det = A.all.list.det
    check(det and det:IsShown() and det.id == r1.data.id and det.val[1].text ~= "", "строка аукциона раскрывается: себестоимость, прибыль, график")
    local n0 = #A.all.list.view
    check(n0 == #A.all.list.data + 7, "под раскрытой строкой - место под подробности")
    r1.scripts.OnClick(r1)
    check(not det:IsShown() and #A.all.list.view == #A.all.list.data, "повторный клик сворачивает строку")
  else check(false, "весь аукцион: нет строк") end
  -- колокольчик: своя цена покупки/продажи
  ns.OpenSignalDialog(2840)
  local SD = WolfichMarketSignalDialog
  SD.buy:Set(120); SD.sell:Set(0)
  SD.save.scripts.OnClick(SD.save)
  check(ns.DB.target[2840] and ns.DB.target[2840].buy == 120 and ns.DB.alarmDir[2840] == "buy" and ns.HasSignal(2840), "колокольчик: сигнал покупки со своей ценой")
  ns.OpenSignalDialog(2840); SD.del.scripts.OnClick(SD.del)
  check(not ns.HasSignal(2840) and ns.DB.target[2840] == nil, "колокольчик: сигнал убран")
  -- «Профессии»: без уровней - общий список; сортировка по Ф по умолчанию
  W.tabs[3].scripts.OnClick(W.tabs[3])
  local C = ns._mainCraft
  check(ns.DB.settings.craftSort == "main" or ns.DB.settings.craftSort == nil, "сортировка по прибыли на фракционном по умолчанию")
  C.flat:SetChecked(true); C.flat.scripts.OnClick(C.flat)
  local hdr = false; for _, d in ipairs(C.list.data) do if d.header then hdr = true end end
  check(ns.DB.settings.craftFlat and not hdr and #C.list.data > 0, "«без уровней»: общий список без групп")
  local sorted = true
  for i = 2, #C.list.data do local a, b = C.list.data[i - 1].profit or -1e12, C.list.data[i].profit or -1e12; if a < b then sorted = false end end
  check(sorted, "общий список отсортирован по прибыли сквозь все рецепты")
  C.flat:SetChecked(false); C.flat.scripts.OnClick(C.flat)
  -- «Часы»: кулдаун трансмутации, уведомление сверху экрана, свечение
  local cdLeft = 3600
  local oldIds, oldInfo = C_TradeSkillUI.GetAllRecipeIDs, C_TradeSkillUI.GetRecipeInfo
  C_TradeSkillUI.GetAllRecipeIDs = function() return { 17187 } end
  C_TradeSkillUI.GetRecipeInfo = function() return { name = "Трансмутация: арканит", learned = true, icon = 1 } end
  C_TradeSkillUI.GetRecipeCooldown = function() return cdLeft end
  ns.ScanCooldowns()
  check(me.cds and me.cds[17187] and me.cds[17187].ready > time(), "кулдаун трансмутации записан")
  W.tabs[5].scripts.OnClick(W.tabs[5])
  check(#ns._mainCd.list.data == 1 and not W.nav[5].pulse:IsShown(), "«Часы»: трансмутация в списке, пока не готова - без свечения")
  local notice
  RaidWarningFrame = CreateFrame("Frame"); RaidNotice_AddMessage = function(_, m) notice = m end
  me.cds[17187].ready = time() - 1
  ns.CooldownTick()
  check(notice and notice:find("Арканит", 1, true) and notice:find("трансмутации", 1, true), "уведомление сверху экрана: " .. tostring(notice))
  check(W.nav[5].pulse:IsShown(), "значок часов светится, пока трансмутация доступна")
  notice = nil; ns.CooldownTick()
  check(notice == nil, "уведомление не повторяется")
  C_TradeSkillUI.GetAllRecipeIDs, C_TradeSkillUI.GetRecipeInfo, C_TradeSkillUI.GetRecipeCooldown = oldIds, oldInfo, nil
  me.cds = nil; ns.Fire("CD")
  -- «Главная»: что нового
  W.tabs[1].scripts.OnClick(W.tabs[1])
  local h = ns._mainHome.cards[1]
  check(h and h.v.text == ns.VERSION and h.lines[1] and h.lines[1].text ~= "", "«Главная»: что нового в текущей версии " .. tostring(h and h.v.text))
  -- окно профессии игры: таблицу можно выключить
  ns.DB.settings.profUI = false
  if ns._marketTable then ns.RefreshMarketTable(); check(not ns._marketTable:IsShown(), "настройка выключает таблицу в окне профессии игры") end
  ns.DB.settings.profUI = true
  W.tabs[3].scripts.OnClick(W.tabs[3])
end
-- в чат не должно попасть ни одной ошибки аддона (сломанная сборка окон)
local bad
for _, s in ipairs(allPrinted) do if s:find("ошибка в") or s:find("error in") then bad = s end end
for _, e in ipairs(ns.log) do if e.msg:find("ошибка в") or e.msg:find("error in") then bad = e.msg end end
-- сообщения аддона по умолчанию не идут в чат, а только в журнал главного окна
local leaked; for _, s in ipairs(allPrinted) do if s:find("общий рынок: отправляю", 1, true) then leaked = s end end
check(not leaked, "сообщения аддона не засоряют чат (только журнал окна)")
WolfichMarketMainFrame.tabs[6].scripts.OnClick(WolfichMarketMainFrame.tabs[6])
ns._mainPops = ns._mainPops or {}
local jb = ns._mainPops and WolfichMarketMainFrame.pages[6]
ns.OpenLog()
check(ns._mainPops.log and ns._mainPops.log.dim:IsShown() and #ns.log > 0, "«Журнал» открывается кнопкой в настройках (" .. #ns.log .. ")")
check(not bad, "нет ошибок при сборке окон" .. (bad and (": " .. bad) or ""))
