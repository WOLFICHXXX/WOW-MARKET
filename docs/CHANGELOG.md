# WolfichMarket changelog

Each release takes its notes from the matching "## version" section below; they appear on CurseForge as the file's changelog.

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
