-- WolfichMarket: что нового (раздел «Главная»). Язык - как у аддона: ru или en.
-- При каждом выпуске - новая запись сверху (и тот же текст по-английски в docs/CHANGELOG.md).
local _, ns = ...
ns.CHANGELOG = {
  { v = "2.43.24", d = "16.11.2026",
    ru = { "Исправлено: после аукциона предметы из сумок с действием (спальник и т.п.) блокировались сообщением «доступно только интерфейсу Blizzard». Сумки игры у аукциона теперь только прячутся, а не закрываются аддоном." },
    en = { "Fixed: after visiting the auction house, usable bag items (bedroll etc.) were blocked with \"only available to the Blizzard UI\". The game's bags at the auction house are now only hidden, not closed by the addon." } },
  { v = "2.43.23", d = "16.11.2026",
    ru = {
      "Новое главное окно: слева разделы Главная, Твинки, Профессии, Аукцион, Часы, Настройки; новые шрифты, гладкие рамки и кнопки.",
      "Профессии: карточка рецепта - себестоимость, доход и прибыль на Ф и Общ, кнопки Крафт / Где взять / На аукционе, график; галочка «без уровней - общий список»; можно добавить чужую профессию.",
      "Твинки: золото, уровень, место и профессии каждого персонажа; банк - в отдельном окне.",
      "Аукцион: «Весь аукцион», «Общий» и «Сигналы»; треугольник у предмета - себестоимость, прибыль, график, продано за 24 ч и лоты сейчас; колокольчик - своя цена, звёздочка - избранное.",
      "Часы: кулдауны трансмутаций и других рецептов у всех персонажей; готово - надпись сверху экрана и свечение значка.",
      "У аукциониста: вкладки Избранное, Купить, Продать, Мой крафт, План; окно аукциона и панель сразу на экране; сумка аддона с сумкой ресурсов, прокруткой и кнопкой «Упорядочить» (клик - в панель, ПКМ - на аукцион игры).",
      "Окно профессии игры: компактный блок «Где купить и где продать» с графиком, звёздочкой и колокольчиком; выключается в настройках.",
      "Фарм считает и деньги с добычи (галочки «Предметы» и «Валюта»); у торговца - автопродажа хлама и автопочинка (по умолчанию выключены); в настройках кнопки «Открыть журнал» и «Перезагрузить интерфейс».",
    },
    en = {
      "New main window: Home, Alts, Professions, Auction, Cooldowns, Settings sections on the left; new fonts, smooth frames and buttons.",
      "Professions: recipe card - cost, income and profit on F and N, Craft / Where to get / On the auction buttons, a chart; \"no skill groups - one list\" checkbox; add a profession your character does not have.",
      "Alts: gold, level, location and professions of every character; the bank in a popup.",
      "Auction: \"Whole auction\", \"Neutral\" and \"Alerts\"; the triangle next to an item - cost, profit, chart, sold in 24 h and auctions now; the bell - your own price, the star - favorites.",
      "Cooldowns: transmutes and other recipe cooldowns of all characters; when ready - a message at the top of the screen and a glowing icon.",
      "At the auctioneer: Favorites, Buy, Sell, My crafts, Plan tabs; the auction window and the panel fit on the screen; the addon bag with the reagent bag, scrolling and a Sort button (click - to the panel, right-click - to the game's auction).",
      "Game profession window: a compact \"where to buy and where to sell\" block with a chart, star and bell; can be turned off in Settings.",
      "Farm counts looted money too (\"Items\" and \"Currency\" checkboxes); at a merchant - auto-sell junk and auto-repair (off by default); Settings have Open log and Reload UI buttons.",
    } },
  { v = "2.42.0", d = "16.11.2026",
    ru = {
      "Общий рынок: у цен, которые не поменялись, обновляется время снимка - они больше не выглядят старыми.",
      "Снимок рассылается, даже если цены не изменились: тогда в нём только подтверждение времени.",
      "Пропавшие с аукциона предметы убираются у всех, кто получил снимок.",
    },
    en = {
      "Shared market: prices that did not change get the time of the latest snapshot, so they no longer look old.",
      "A snapshot is sent even when no prices changed: it then carries only a time confirmation.",
      "Items that disappeared from the auction house are removed for everyone who receives the snapshot.",
    } },
  { v = "2.41.7", d = "16.11.2026",
    ru = {
      "Общий рынок: весь аукцион, турбо-режим, плотная упаковка цен, рассылаются только изменения, без вылетов после снимка.",
      "Сигналы со своей ценой: «купить, если не дороже» и «продать, если не дешевле».",
      "Два аукциона - фракционный и общий (Остров Зефрис, Тернистая долина, Танарис), комиссия 5% и 15%.",
      "Окно профессии: прибыль столбиками Ф / Общ, таблица «Где купить и где продать», кнопка «В план».",
      "Сумки: значки на предметах (молоток - аукцион, мешочек - торговцу), сортировка, кнопка «Все» при продаже.",
    },
    en = {
      "Shared market: the whole auction house, turbo mode, dense price packing, only changes are sent, no disconnects after a scan.",
      "Alerts with your own price: \"buy at or below\" and \"sell at or above\".",
      "Two auction houses - faction and neutral (Zephyr Isle, Stranglethorn Vale, Tanaris), fees 5% and 15%.",
      "Profession window: profit in F / N columns, a \"where to buy and where to sell\" table, \"Add to plan\" button.",
      "Bags: icons on items (gavel - auction, coin bag - vendor), sorting, \"All\" button when selling.",
    } },
}
