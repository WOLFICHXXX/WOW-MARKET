# WolfichMarket changelog

Each release takes its notes from the matching "## version" section below; they appear on CurseForge as the file's changelog.

## 2.43.14

- At the auctioneer: the auction window and the addon panel fit on the screen right away; instead of the standard bags - the addon bag under the auction window (click - post, right-click - as in the game).
- Professions: the recipe card as in the design - income and profit on F and N, Craft / Where to get / On the auction buttons, the chart without scrolling; bigger main window, longer auctioneer panel; smooth chart lines.
- Look: the new design's fonts (Inter and Forum, OFL), smooth frames and buttons without jagged edges, labels stay inside buttons, disabled buttons stay readable.
- New main window: section icons on the left - Home, Alts, Professions, Auction, Cooldowns, Settings.
- Home: what's new in every version, in the addon's language.
- Alts: gold, level, location and professions of every character; their bank in a popup.
- Professions: "no skill groups - one list" checkbox sorts by profit across all recipes; faction profit sort is the default; F and N profit columns.
- Auction: "Whole auction" and "Alerts"; a triangle on every item opens crafting cost, profit on F and N, and a price chart.
- Cooldowns: transmutes and other recipe cooldowns of all characters with timers; when ready - a message at the top of the screen and a glowing hourglass.
- A bell next to every item: your own buy or sell price alert. Stars are now favorites only.
- Auctioneer panel: Favorites, Buy, Sell, My crafts, Plan tabs; the Chart and Settings tabs are gone - the chart opens in every row, settings live in the main window.
- Settings: the "where to buy and where to sell" table and F / N columns in the game's profession window can be turned off; the message log opens with a button.

## 2.42.0

- Shared market: when someone's snapshot arrives in full, prices that did not change get the time of that snapshot, so they no longer look old.
- A snapshot is sent even when no prices changed: it then carries only a time confirmation.
- Items that disappeared from the auction house are removed for everyone who receives the snapshot.

## 2.41.7

Everything since 2.21.2:

- Shared market: the whole auction house is shared, with alerts and recipes first. Turbo mode, dense price packing, only changed prices are sent, several scanners take turns, a newcomer gets the whole auction personally.
- Safe traffic limit: no more disconnects after a scan (WOW51900319).
- Alerts with your own price: "buy at or below" and "sell at or above" instead of percentages.
- Two auction houses: faction and neutral (Zephyr Isle, Stranglethorn Vale, Tanaris), detected by zone and kept separately, with their own fees (5% and 15%). The Riverglades auction is ignored.
- Main window "Auctions" tab: the whole faction auction with sorting and categories (including profession crafted items / materials); for the neutral auction - what is better to buy or sell there.
- Profession window: crafting profit in F / N columns, a "where to buy and where to sell" table, sorting recipes by profit, "Add to plan" button.
- Plan: "Plan" button on the auctioneer's Craft tab, a hint where each material is cheapest.
- Price chart: a second line with sold quantity; the recipe card scrolls down to a large chart.
- Bags: icons on items (gavel - auction, coin bag - vendor), sorting puts auction items on top and vendor items at the bottom, "All" quantity button when selling.
- Item tooltip: crafting cost, auction price and profit.
- Posting checked items waits for the game to confirm each lot and no longer hangs the auction house.
- Professions are re-read when the skill grows or new recipes are learned.
