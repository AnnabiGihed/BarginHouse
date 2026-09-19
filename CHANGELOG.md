# Changelog

All notable changes to BargainHouse. Versions follow `major.minor.patch`.

## 1.1.1

### Fixed

- **"BargainHouse has been blocked from an action only available to the Blizzard UI"** when right-clicking
  items in your bags, including away from the auction house. Taking over the game's bag click function
  permanently made the game treat every later right-click as coming from an addon. It is now taken over
  only while you are at an auctioneer and handed straight back when the auction house closes, so bag
  clicks anywhere else run through Blizzard's own untouched code.
- Items that can't be auctioned (soulbound, quest, conjured) are now left alone with a short message
  instead of being passed on to an action the game would block.

### Added

- Setting: **Right-click a bag item at an auctioneer to sell it**, in case you prefer the normal
  right-click behaviour there.

## 1.1.0

Everything added and fixed since the first working build. If you were testing earlier builds, they all
reported `1.0.0`; from now on each release carries its own number.

### Added

- **Minimap button**: opens the window anywhere. Away from an auctioneer it shows Crafting, Shopping,
  Characters and Sync, with stock checks but no prices or buying.
- **Deals tab**: whole-auction-house scan (fast, or page by page), 7 days of market history per item,
  resell and vendor deals, confidence ratings, filters and a search box.
- **Buy each** column in Deals: what you actually pay per item.
- **Watchlist** (in Deals): chosen items are re-checked while the auction house is open, with a chat alert,
  a sound and buyable entries. Check interval configurable from 5 seconds to 5 minutes.
- **Crafting tab**: recipes from any profession window (yours, alts', or profession links), craft queue,
  materials check, craft counts from your stock, and a **Profit?** check per recipe.
- **Enchanting** handled as scrolls: the product is `Scroll of <recipe>` and the vellum is priced as a
  material.
- **Characters tab**: every character on your accounts with class, level, professions, gold and
  **total gold**.
- **Sync tab**: link your WoW accounts by invitation (three invitations link four accounts), with progress
  and a live log.
- **Stock sources**: bags, mailbox (including uncollected purchases), personal bank, alts and guild bank,
  each switchable from the **Stock** menu.
- **Shopping lists** with a stock check and one-confirmation buying.
- **Vendor prices** learned at merchants, so vendor-sold reagents are never bought at inflated auction
  prices.
- **Right-click a bag item** at an auctioneer to put it in the Create auction slot.
- Browse search row (mode, category, rarity, levels, price, checkboxes) is remembered between sessions.

### Changed

- Buying asks for **one confirmation**, then buys every planned offer. On servers that require a mouse
  click per purchase, each click buys every planned offer on the loaded page, and the page is pre-loaded
  so the first click already buys.
- Purchases are confirmed by server answers (won message, gold change, auction errors) with a 15 second
  allowance, instead of a short timer.
- Sync is event-driven: characters are greeted within about a second of coming online, and logouts are
  noticed immediately.
- Prices are shown with gold/silver/copper coin icons.
- Nothing heavy runs in combat; idle timers switch themselves off; received data is applied in slices.

### Fixed

- Buying more than planned when a purchase was confirmed slowly and an identical stack existed.
- Gold showing 0 for characters, and gold being lost when a character logged out.
- Sync failing after switching characters, needing reloads, or silently dropping lost messages.
- Accounts merging because of identical sync IDs or misattributed character updates.
- Crafters not syncing between accounts; mining recipes recorded under the wrong profession name.
- "Loading page..." getting stuck when another scan interrupted a purchase.
- Guild bank tabs with limited withdrawals wrongly treated as full access, and vice versa.
- Shift-click no longer fails to put an item name in the focused search box.
- Deals header text overlapping the Watchlist button.

## 1.0.0

First working build: auction house replacement with search modes, grouped cheapest-first results,
quantity buying, selling with undercut and multi-stack posting, and the My Auctions tab.
