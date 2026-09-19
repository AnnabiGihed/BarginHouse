# Changelog

All notable changes to BargainHouse. Versions follow `major.minor.patch`.

## 1.2.0

### Added

- **Check now** button in the Deals tab (and **Check all now** in the watchlist panel): re-checks every
  watched item straight away instead of waiting for the timer. It shows progress while it runs, then says
  what it found, and any deals appear in the list ready to buy. Items whose offers are gone are cleared.

## 1.1.5

### Fixed

- **Right-click still didn't put an item in the sell slot.** The hidden helper window was showing
  Blizzard's Auctions frame directly, which leaves the window's own `selectedTab` on Browse - and that
  state is what the game checks when you right-click. The tab is now selected through Blizzard's own tab
  button, re-checked shortly after the auction house opens and whenever you open the Sell tab.

### Added

- `/bh diag` prints what the game currently sees (helper active, auction UI loaded, window shown, selected
  tab, item in the slot), to pin down right-click selling if it still misbehaves.

## 1.1.4

### Added

- **Right-click a bag item at an auctioneer to put it in the Create auction slot**, and the Sell tab comes
  forward. This is done by the game itself: the placement check lives in Blizzard's code and only applies
  when its own auction window is open, so that window is kept loaded but invisible and parked off-screen
  on its Auctions tab while you use BargainHouse. No addon code touches the bag click, so nothing can be
  tainted or blocked.
- Setting: **Right-click a bag item to put it in the sell slot** (on by default), which turns the hidden
  helper window off if you'd rather not have it.

## 1.1.3

### Fixed

- **"BargainHouse has been blocked from an action only available to the Blizzard UI" on right-click, for
  the rest of the session.** 1.1.1 only restored the game's bag click function when the auction house
  closed, which isn't enough: in WoW, a frame whose click handler has once run addon code stays tainted
  until you restart the game, so bag right-clicks kept being blocked afterwards, even with the auction
  house shut and only the auctioneer targeted. The bag click function is no longer touched at all.

### Changed

- Sending an item to the Sell tab from your bags is done with **Alt+Click** (a secure hook, which cannot
  taint anything) or by dragging it into the slot. Right-click keeps its normal game behaviour everywhere.
- The setting "Right-click a bag item at an auctioneer to sell it" is gone with the feature.

## 1.1.2

### Fixed

- **Deals were not refreshed after buying.** The list kept showing the snapshot from the last full scan,
  so bought offers lingered and newly posted ones were missing. After a purchase the items you bought are
  now re-queried and their rows rebuilt from what the auction house actually has: emptied rows disappear,
  remaining offers show their real quantity and price, and cheap stacks posted in the meantime appear.
  Watchlist rows are refreshed the same way.

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
