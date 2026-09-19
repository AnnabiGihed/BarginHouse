# BargainHouse

**For World of Warcraft 3.3.5a only (Wrath of the Lich King, client build 12340, interface 30300).**

A complete auction house replacement for WoW **3.3.5a**, built for private servers such as Warmane. It
replaces Blizzard's auction window with a faster one built around three questions: *where is it cheapest*,
*what do I already have*, and *is this worth crafting or flipping*.

Everything works on a stock 3.3.5a client. No libraries, no dependencies.

- **Game version:** 3.3.5a (WotLK) - it will **not** work on Classic, Cataclysm or retail clients
- **Addon version:** 1.1.1 (see [CHANGELOG.md](CHANGELOG.md))
- **Author:** Anguish
- **License:** free to use in game; no modification, reuse or redistribution (see [LICENSE](LICENSE))

---

## Contents

- [Highlights](#highlights)
- [Installation](#installation)
- [First run](#first-run)
- [The window](#the-window)
  - [Browse](#browse)
  - [Shopping](#shopping)
  - [Crafting](#crafting)
  - [Deals](#deals)
  - [Watchlist](#watchlist)
  - [Sell](#sell)
  - [Auctions](#auctions)
  - [Characters](#characters)
  - [Sync](#sync)
  - [Settings](#settings)
- [Where your stock comes from](#where-your-stock-comes-from)
- [Buying: how it protects your gold](#buying-how-it-protects-your-gold)
- [Syncing several WoW accounts](#syncing-several-wow-accounts)
- [Slash commands](#slash-commands)
- [Performance and combat](#performance-and-combat)
- [Data, privacy and storage](#data-privacy-and-storage)
- [Troubleshooting](#troubleshooting)
- [Known limits](#known-limits)
- [Compatibility](#compatibility)
- [For developers](#for-developers)
- [License](#license)

---

## Highlights

- **Smarter search** - contains, exact, starts/ends with, all words, wildcards (`frost*cloth`), with
  category, level, rarity and price filters. Results are grouped per item, cheapest per unit first.
- **Quantity buying** - say how many you need; it picks the combination of stacks with the **lowest total
  cost** (stacks can't be split, so the cheapest per unit isn't always the cheapest overall) and buys them.
- **Shopping lists** - paste `20x Copper Bar` lines, see what you're missing after your bags, bank, alts,
  guild bank and mailbox, then buy the rest.
- **Crafting** - recipes from every profession you've opened, who can craft them, what your stock allows you
  to make, missing materials, and a **profit check** for any recipe.
- **Deals** - scan the whole auction house and find items listed far below their market value or below
  vendor price, with a confidence rating built from your own scan history.
- **Watchlist** - keep an eye on chosen items and get told the moment a cheap offer appears.
- **Selling** - market scan, automatic undercut, multi-stack posting, deposit and vendor-price warnings.
- **Account sync** - share professions, crafters, gold and auction scans between your own WoW accounts.
- **Works away from the auction house** - minimap button opens crafting, stock and characters anywhere.

---

## Installation

Requires a **World of Warcraft 3.3.5a** client. Later game versions changed the auction, trade skill and
addon-message APIs this addon is built on, so it only runs on 3.3.5a.

1. Copy the **BargainHouse** folder from this repository into your AddOns folder, so the path is:
   `World of Warcraft\Interface\AddOns\BargainHouse\BargainHouse.toc`
   (this README, the changelog and the license sit beside that folder in the repository, not inside it)
2. Restart the game (or `/reload`) and enable **BargainHouse** on the character select screen.
3. Talk to any auctioneer: BargainHouse opens instead of the default window.

To use Blizzard's window for one visit, click **Default** in the title bar. `/bh toggle` disables the
replacement completely.

---

## First run

A few one-time steps make everything else work:

| Do this once | What it unlocks |
|---|---|
| Log in on each character | They appear in **Characters** with gold, level and professions |
| Open each profession window (yours, an alt's, or a `[Profession]` link from chat) | Recipes and who can craft them |
| Open your bank | Bank contents count as stock |
| Open the guild bank | Tabs marked *(Full Access)* count as stock |
| Open a vendor that sells reagents (e.g. Imbued Vial) | Real vendor prices instead of inflated auction ones |
| Run a full scan in **Deals** | Market values, better prices everywhere, deal hunting |

None of this is mandatory; the addon simply tells you what it doesn't know yet.

---

## The window

Tabs at an auctioneer: **Browse, Shopping, Crafting, Deals, Sell, Auctions, Characters, Sync**, plus
Settings behind the gear button. Away from an auctioneer only the tabs that work offline are shown.

### Browse

- **Search modes**: *Contains, Exact name, Starts with, Ends with, All words* (in any order) and
  *Wildcard* (`*` = anything, `?` = one character).
- **Filters**: category and subcategory, level range, minimum rarity, usable only, maximum price per unit,
  hide bid-only, and **Deals only** (below the average price you've recorded).
- **Results** are grouped per item and sorted by lowest price per unit, with quantity, number of offers and
  a **vs avg** column comparing today's lowest to your recorded average.
- Click an item to list every offer, cheapest first. Right-click searches for that exact item.
  Shift-click links it in chat.
- **Quantity to buy**: type the amount you need. The addon highlights the cheapest combination of stacks,
  shows the total, and buys them all. If stack sizes make a slightly larger purchase cheaper, the extra is
  shown in orange (this can be turned off in Settings).
- **Favourites and history** for searches you repeat. The whole search row (mode, category, rarity, level
  range, price and checkboxes) is remembered between sessions.

### Shopping

Paste a list, one item per line. All of these work:

```
20x Rough Stone
Linen Cloth x10
26 Copper Bar
[Imbued Vial]: 5
```

**Check & price list** compares it with your stock, prices what's missing and shows the total. Click a row
to skip it, right-click to open it in Browse, then **Buy everything**.

### Crafting

- **Recipes** from every profession window that has been opened, filtered by profession, by crafter or by
  text; **Can craft** hides anything your stock can't make at least once.
- **Crafter column** shows who can make it. Green is confirmed, `Banehart?` in yellow means that character
  has the profession but the recipe hasn't been confirmed yet (open their profession window once).
- **Craft counts** after the recipe name: green is what your bags allow right now, yellow is what all your
  stock allows.
- **Craft queue**: add recipes with a number of crafts; **Find materials** adds up every reagent, subtracts
  your stock and prices the rest.
- **Profit?** answers "if I buy the materials and sell the result, do I gain or lose?" for the selected
  recipe: materials (auction, vendor or your own price), the item's current lowest listing and market
  value, revenue after the 5% auction cut, and the profit or loss per craft and in total.
  Enchanting is handled as scrolls: the product is `Scroll of <recipe>` and the **vellum** is added as a
  material.

### Deals

- **Scan whole AH**: *Fast* downloads everything in one request (the server allows this every 15 minutes)
  or *Page by page*, which is slower but always available and is used automatically as a fallback.
- Each scan stores a **daily price summary per item** for 7 days. An item's market value is the median of
  those days, so a single odd day doesn't distort it. Confidence: *High* (3+ days, 5+ listings),
  *Medium*, *Low* (hidden by default).
- **Deal types**: *Resell* (well below market value, profit counts the 5% cut; the deposit is refunded when
  an item sells so it isn't counted) and *Vendor* (cheaper than a vendor pays, guaranteed profit).
- Columns show the offers, quantity, total cost, **what you pay per item**, what you would sell each for,
  profit and return %.
- Filters for minimum profit, minimum return %, maximum spend per item, confidence and type, plus a
  **search box**. Select rows and **Buy selected**.

### Watchlist

Inside Deals. Add items by name or shift-click, with an optional **Alert under** price (without one, the
item's market value is used, 20% below counts as a deal).

While the auction house is open, one watched item is re-checked per interval (**Check every**: 5s to 5min).
When a cheap offer appears you get a chat message with the item link and price, a sound, and the offers
appear in the deals list marked **Watch**, ready to buy.

Checking only runs when nothing else is scanning or buying, so it never interferes.

### Sell

Drag an item into the slot, **right-click** it in your bags (while you are at an auctioneer; can be turned
off in Settings), or **Alt+Click** it. The addon scans the market for that item,
suggests a price just below the cheapest competitor (flat and/or percentage undercut, configurable),
and shows stack size, number of stacks, duration, deposit and a warning if you're pricing below vendor
value. Clicking any row in the market list matches that price.

### Auctions

Your own auctions with sold/bid status, time left, and a comparison against the last known lowest price so
you can see where you've been undercut. Cancel with confirmation.

### Characters

Every character on this account, and on your linked accounts: class, level, professions with skill levels,
gold, and when it was last updated. The bottom line shows **total gold across all your characters**
(also in the minimap tooltip).

### Sync

Links your WoW accounts together. See [Syncing several WoW accounts](#syncing-several-wow-accounts).

### Settings

Gear button in the title bar: replace the default auction house, tooltip prices, confirmation before
buying, allow extra items when a bigger stack is cheaper, max pages per search, undercut amounts, starting
bid percentage, window scale, and data cleanup.

---

## Where your stock comes from

Before buying anything, the addon subtracts what you already own, in this order:

1. **Bags** of the current character (live).
2. **Mailbox**, including purchases that haven't been collected yet.
3. **Personal bank** (recorded whenever you open your bank).
4. **Alts** on the same realm and faction (recorded when you log in on them).
5. **Guild bank** tabs marked *(Full Access)* (recorded when you open the vault).

Statuses tell you where to go: *In your bank*, *On your alts*, *In guild bank*, *In mailbox*, *Bought*.
The **Stock** button on the results bar turns each source on or off, and shows how old each recording is.

---

## Buying: how it protects your gold

- **Cheapest combination, not cheapest unit price.** Stacks can't be split, so buying 7 items may be
  cheaper as one stack of 12. The addon compares combinations (verified against a brute-force search in the
  test suite) and shows any extra in orange.
- **One confirmation.** Confirm once, and every planned offer is bought.
- **Servers that require a click per purchase** (like Warmane) are detected: each click then buys every
  planned offer on the loaded auction page, and the page is pre-loaded so your *first* click buys.
- **Never more than planned.** Purchases are capped per item, so a retry can't buy a second identical stack.
- **Patient confirmation.** Each purchase waits up to 15 seconds for the server, so a slow answer is never
  mistaken for a failure, and an unconfirmed purchase is never repeated.
- **Vendor items** (vials, thread, flux, parchment, dyes, spices, tools) are bought from the auction house
  only when actually cheaper than the vendor. If their vendor price isn't known yet, they aren't bought at
  all and the addon tells you to visit the vendor once.

---

## Syncing several WoW accounts

Sync shares **professions, recipes, who can craft what, character gold and auction scans** between your own
accounts while characters are online. Nothing is shared with anyone else.

**Linking (three invitations link four accounts)**

1. Open **Sync** on one account, type a character name from another account, click **Invite**.
2. On that account, click **Accept** in the popup.
3. Repeat for each further account, from any already-linked account, in any order.
   Linked accounts exchange their links, so every account ends up connected to every other.

**How it behaves**

- Characters are greeted the moment they appear (login/logout messages and roster updates are used, so a
  connection forms in about a second), and every character of a linked account connects automatically.
- Only what differs is sent; a background check every 5 minutes heals anything missed.
- Lost messages are re-requested, so a dropped piece can't silently break a transfer.
- Messages travel as hidden whispers, or through the guild addon channel **addressed to one character** if
  the server doesn't deliver hidden whispers. Nothing is broadcast and nothing appears in guild chat.
- The **log** in the Sync tab shows connections, transfers and errors; **Detailed log** records every
  message for troubleshooting.

Both characters must be on the **same realm and faction**.

---

## Slash commands

| Command | Effect |
|---|---|
| `/bh show` | Open the window (anywhere; auction features at an auctioneer) |
| `/bh minimap` | Show or hide the minimap button |
| `/bh toggle` | Enable/disable replacing the default auction house |
| `/bh reset` | Reset window position and scale |
| `/bh guild` | Show what is recorded from your guild bank |
| `/bh autobuy` | Re-enable automatic buying after a server block |
| `/bh clearprices` | Wipe recorded price history |

Sync is managed entirely in the **Sync** tab.

---

## Performance and combat

- No script runs every frame while idle; timers switch themselves off.
- Sync checks ten times a second and **pauses completely during combat**: nothing is sent and nothing is
  applied until the fight ends.
- Large incoming data is applied in slices (at most 150 entries per frame).
- Bag, bank and gold recording is deferred during combat and doesn't refresh a closed window.
- Mass crafting doesn't trigger list refreshes while the window is closed.
- Full scans read results in chunks so the client stays responsive.
- Every message received from another account is error-guarded and can never raise a Lua error.

---

## Data, privacy and storage

Everything is stored in `WTF\Account\<ACCOUNT>\SavedVariables\BargainHouse.lua`:

- recipes and crafters, characters (gold, class, level, professions), bag/bank/guild bank/mailbox
  snapshots, vendor prices, market history (7 days), favourites, shopping list, craft queue, watchlist,
  settings, and a private random ID used to recognise your own accounts.

The addon never sends anything to anyone except characters you explicitly invited and linked.

---

## Troubleshooting

**Sync says "not connected"**
Check that both characters are online, both have this version, and the accounts are linked in the Sync tab.
Turn on **Detailed log** on both sides and press **Sync now**; the log shows every message sent and received.

**"Click to buy N / M" appears**
The server refuses purchases that don't come from a mouse click. Each click then buys every planned offer
on the loaded page. `/bh autobuy` re-tries automatic buying.

**A vendor reagent shows "Vendor item"**
Its vendor price isn't recorded yet. Open that vendor once on the character; auction prices are never used
as a substitute, to avoid paying inflated prices.

**Gold shows 0 for a character**
Log in on that character for a minute with this version; gold is read repeatedly after login, since the
server can send it late.

**Crafters show `Name?` instead of a name**
That character has the profession, but the recipe isn't confirmed. Open their profession window once.

---

## Known limits

- **Recipes** can only be read while a profession window is open. Skill levels come from the skills list and
  need no window.
- **Shared scans** include market prices and deal candidates, not every auction; run a scan on an account
  for its complete current listings.
- **Alchemy procs** (extra potions) aren't counted in profit estimates, so real profit can be slightly
  higher.
- **Recorded stock** is a snapshot: bank, alts and guild bank are only as fresh as the last time you opened
  them. Tooltips show the age.
- Cross-faction and cross-realm sync is impossible in 3.3.5a.

---

## Compatibility

| | |
|---|---|
| **Supported** | WoW 3.3.5a (WotLK, build 12340), interface 30300 - Warmane and other 3.3.5a servers |
| **Not supported** | Classic Era / SoD, TBC Classic, WotLK Classic, Cataclysm, retail |
| **Dependencies** | none |
| **Other addons** | no replacement of Blizzard files; the default auction window stays available via the **Default** button |

## For developers

- Pure Lua 5.1 for the 3.3.5a client (interface 30300), no external libraries.
- ~9,600 lines across 25 files; each tab is a module under a shared namespace, with reusable widgets
  (`Widgets.lua`), one auction query engine (`Scanner.lua`) and one purchase engine (`Buyer.lua`).
- The addon is developed against a **mock of the 3.3.5a API**: 26 test suites drive the real addon files
  outside the game and check searching, buying (including servers that block automatic purchases, slow
  confirmations and sold-out offers), shopping, crafting, profit checks, vendor-price protection, guild
  bank, bank/alt stock, deals and scans, the watchlist, multi-account sync (four accounts, packet loss,
  character switching) and idle/combat performance.

Bug reports are most useful with the exact in-game text: the chat line, the status line, or the Sync log
with **Detailed log** enabled.

---

## License

**BargainHouse is not open source.** It is free to use in game, and nothing more:

- **You may** install and use it on your own computers and game accounts, keep backups, change your own
  settings, and quote short code excerpts when reporting a problem.
- **You may not** modify it, reuse any part of its code in another addon or program, or redistribute,
  repackage, host or sell it.

See [LICENSE](LICENSE) for the exact terms. For anything beyond that, ask the author.

BargainHouse is an independent addon and is not made by, endorsed by, or affiliated with Blizzard
Entertainment.
