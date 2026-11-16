-- WolfichMarket: что нового (раздел «Главная»). Язык - как у аддона: ru или en.
-- При каждом выпуске - новая запись сверху (и тот же текст по-английски в docs/CHANGELOG.md).
local _, ns = ...
ns.CHANGELOG = {
  { v = "2.43.6", d = "16.11.2026",
    ru = {
      "Профессии: карточка рецепта как на макете - доход и прибыль на Ф и Общ, кнопки Крафт / Где взять / На аукционе, график без прокрутки; окно больше, панель аукциониста длиннее; линии графика сглажены.",
      "Оформление: шрифты нового макета (Inter и Forum), гладкие рамки и кнопки без «лесенки», надписи не залезают на края кнопок, выключенная кнопка читается.",
      "Новое главное окно: слева разделы - Главная, Твинки, Профессии, Аукцион, Часы, Настройки.",
      "Твинки: золото, уровень, место и профессии каждого персонажа; банк - в отдельном окне.",
      "Профессии: галочка «без уровней - общий список» (сортировка по прибыли сквозь все рецепты), сортировка по прибыли на фракционном по умолчанию, столбики Ф и Общ.",
      "Аукцион: «Весь аукцион» и «Сигналы»; у каждого предмета треугольник - себестоимость, прибыль на Ф и Общ и график.",
      "Часы: кулдауны трансмутаций и других рецептов у всех персонажей; когда готово - надпись сверху экрана и свечение значка часов.",
      "Колокольчик у каждого предмета: своя цена покупки или продажи.",
      "Панель у аукциониста: вкладки Избранное, Купить, Продать, Мой крафт, План; график - в каждой строке, настройки - в главном окне.",
      "Настройки: можно выключить таблицу «Где купить и где продать» и столбики в окне профессии игры; журнал сообщений открывается кнопкой.",
    },
    en = {
      "Professions: the recipe card as in the design - income and profit on F and N, Craft / Where to get / On the auction buttons, chart without scrolling; bigger window, longer auctioneer panel; smooth chart lines.",
      "Look: the new design's fonts (Inter and Forum), smooth frames and buttons without jagged edges, labels stay inside buttons, disabled buttons stay readable.",
      "New main window: sections on the left - Home, Alts, Professions, Auction, Cooldowns, Settings.",
      "Alts: gold, level, location and professions of every character; the bank in a popup.",
      "Professions: \"no skill groups - one list\" checkbox (sort by profit across all recipes), faction profit sort by default, F and N columns.",
      "Auction: \"Whole auction\" and \"Alerts\"; every item has a triangle - crafting cost, profit on F and N, and a chart.",
      "Cooldowns: transmutes and other recipe cooldowns of all characters; when ready - a message at the top of the screen and a glowing hourglass.",
      "A bell next to every item: your own buy or sell price.",
      "Auctioneer panel: Favorites, Buy, Sell, My crafts, Plan tabs; the chart is in every row, settings moved to the main window.",
      "Settings: the \"where to buy and where to sell\" table and columns in the game's profession window can be turned off; the message log opens with a button.",
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
