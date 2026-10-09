# Changelog

All notable changes to BargainHouse. Versions follow `major.minor.patch`.

## 1.8.0

### Added

- **The addon now learns what actually sells.** Each full scan is compared with the last: an auction that
  disappears while it still had hours left was bought, one that was already nearly over merely expired. That
  gives a real sales-per-day figure per item, which now sets how many of something a deal may include -
  before this it was a guess based on how many were listed.
- **Realised profit, not predicted profit.** What you pay is recorded when you buy through the Deals tab,
  and what you receive is recorded when one of your auctions sells. `/bh profit` shows what you spent, what
  came back, and how often items sold for what the addon predicted or better.
- **Undercut warning**: when your auctions are read at the auction house, you are told once per visit if any
  have been undercut, with the worst one named.
- **The Sell tab is more careful**: it will not chase a lone dumper to the bottom (it undercuts the next
  listing up and says so), and it warns when your price is below what you paid for the item.
- **`/bh check`** inspects what the addon actually built in this client: tabs and their pages, lists that
  would cover the materials panel, lists sharing a frame (and therefore a scroll bar), missing calls between
  modules, readable profession data, and whether anything has taken over the game's bag clicks. These are
  exactly the faults the test suite cannot see, and every one of them reached you at some point.

## 1.7.1

### Fixed - the watchlist now judges finds the same way

- **A watched item added by name could never produce a hit on its first check.** The threshold was worked
  out before the scan told the addon which item it was, so an item with no "alert under" price was compared
  against nothing. It is identified first now.
- **Watch hits assumed you sell at market value.** Like deals, the sale price is capped by the cheapest
  listing you did not buy, and the tooltip names it.
- **Every watch hit claimed High confidence.** It now rates its finds from the same history as deals, so an
  item with two listings a day reads Low instead of pretending to be a sure thing.
- Watch hits also inherit the corrected valuation from 1.7.0, so a "deal" is measured against what the item
  really trades at rather than the overpriced listings.

## 1.7.0

### Fixed - deals were finding bargains that weren't

- **Prices followed the overpriced listings.** An item's value was the median of every asking price, so a
  wall of hopeful sellers dragged it up and ordinary listings looked like bargains. In testing, Saronite Bar
  trading at about 21g was valued at 69g - more than three times too high. Value is now taken a quarter of
  the way up the listings by quantity, which ignores the wall without following a single bargain, and is
  still the middle day of up to seven days so one odd day can't move it.
- **Resale assumed you sell at market value.** After buying the cheapest offers you have to undercut
  whatever is left, which can be well below market. The sale price is now capped by the cheapest listing you
  did not buy, and the tooltip names it.
- **Nothing checked whether the item sells.** A cheap stack of something nobody buys looked like profit. A
  resale deal is now limited to about half of what is normally listed in a day, and says when offers were
  left out for that reason.
- **Thin data could look trustworthy.** Two listings produced a "median" and could reach Medium confidence.
  Fewer than three listings is always Low; High needs several days and at least eight listings.

## 1.6.0

### Fixed

- **Reset in Browse sat outside the window.** The search row added up to 946 px in a 920 px area; it now
  ends at 878 with room to spare.

### Changed - performance

- **Working out a plan was doing the same work hundreds of times.** Prices and reagents were re-read for
  every recipe at every skill point, and each price recomputed market medians. They are now worked out once
  per plan: a full 1-450 plan went from about 270 ms to 6 ms in testing, which is the difference between a
  visible freeze and nothing at all.
- **Profession data no longer sits in memory as thousands of tables.** It is kept as text and unpacked only
  for the profession you are planning: 4.4 MB at rest became 794 KB, and unpacking a profession costs 1-3 ms.
- **The sync loop no longer makes garbage ten times a second.** It built two throwaway tables per tick and
  rebuilt its target list every couple of seconds. Playing for 100 seconds with the window closed made
  212 KB of garbage before and makes 0.3 KB now, with a quarter of the processor time per frame.
- A performance test now guards all of this: plan time, memory per profession, idle allocations and the
  width of the Browse search row.

## 1.5.3

### Added

- **Find recipe on AH** in the Level up tab: select a step and it opens Browse already searching for that
  recipe. It searches the real item name when your client knows it (an exact search), otherwise it adds the
  profession's own wording - Recipe:, Plans:, Pattern:, Schematic:, Formula:, Design:, Technique:, Manual:
  - and searches for that. The button is off for recipes you already know or that only a trainer teaches,
  and says which it is.

### Fixed

- Right-clicking a step used to call a search function that did not exist, which would have thrown an error
  in game. Browse now has a proper entry point that the other tabs share.

## 1.5.2

### Added

- **Reset** button in Browse: clears the search text and every filter (category, rarity, level range, price,
  checkboxes) and leaves how names are matched alone.

### Fixed

- **Buying in Browse could do nothing without saying why.** Clicks were dropped silently when the offer
  hadn't been checked yet, had no buyout, belonged to you, or cost more than you have. Every click now
  either buys or says what is happening.
- **The Buy button is never dead.** If the offer hasn't been looked up, clicking Buy starts the lookup and
  says so, instead of being greyed out.
- **"Locating..." can no longer hang.** A lookup that doesn't answer within ten seconds clears itself with
  "Couldn't check that offer - click Buy to try again", and a lookup interrupted by another scan says so
  and retries.

## 1.5.1

### Fixed

- **Plans asked for far too many materials.** The skill-up chance was modelled as 75% for yellow and about
  25% falling to 5% through green, which is too pessimistic: you reached grey with materials to spare. The
  chance now falls in a straight line from the yellow threshold to grey, the model trade-skill calculators
  use. For a recipe levelled from 10 to 70 at 3 points per skill-up the plan now asks for 55 crafts against
  an average of 54.6 actually needed in 3,000 simulated runs; the old model asked for 76, which is 39% more.
- Because the chance near grey is now correctly small, the planner also moves off a recipe sooner when a
  cheaper one per skill point exists.

## 1.5.0

### Fixed

- **The shopping list asked you to buy materials the plan makes itself.** If a plan smelted bars and then
  used them, both the ore and the bars were on the list. Production is now credited against later steps, and
  the total is the cost of the list you actually buy.

### Added

- **Only what you can actually get is suggested.** Recipes that come from drops, quests, discovery,
  reputation or events are left out unless you already know them; a recipe that comes as an item is only
  used if that item is on the auction house. Materials must be in your bags, sold by a vendor, or on the
  auction house. If you have never scanned, prices are treated as unknown rather than unobtainable, and the
  plan says so.
- **Reject step**: pick a step you can't or won't do and the plan is worked out again without it, with
  **Clear rejections** to undo. If rejecting leaves no route, the tab says so instead of showing nothing.
- The starting skill is read from your character and no longer editable, and the target defaults to the
  profession's cap (450).

## 1.4.6

### Added

- **Get their scan** button in the Sync tab: asks every connected account for its latest auction house
  scan, instead of waiting for the automatic exchange (which only triggers when the other scan is clearly
  newer than yours).
- `/bh diag` now also reports scan sharing: when your own last scan was, your realm and faction key, and
  for each linked account whether it is connected, how old its scan is, and whether it is on the same realm
  and faction.

### Fixed

- A flaw in the test harness hid two-account behaviour: events were dispatched while handlers were creating
  frames, so one account silently received nothing. Scan sharing between accounts is now covered by a test
  (scan on one account, received on two others).

## 1.4.5

### Fixed

- **The plan's Cost column was drawn outside its list**, on top of the materials grid: the columns added up
  to more than the list is wide. They now fit inside it with room for the scroll bar.
- **The plan list and the materials list shared a scroll bar.** Both were created with the same frame name,
  and WoW's scroll template works through that global name, so scrolling one moved the other. The plan list
  has its own name now, and a test checks every list in the addon for duplicate names.
- After **Find materials** finishes, the plan is worked out again on the prices just read from the auction
  house, and says whether that made it cheaper or dearer than the estimate.

## 1.4.4

### Fixed

- **"Work out the plan" appeared to do nothing.** It rebuilt the same plan with no visible change, and any
  failure inside it was swallowed. The button now reads **Plan updated** for a moment after it runs, and
  anything that goes wrong is said plainly in the tab and printed to chat instead of failing silently.
- **Text was cut off** under the plan: the total is on its own line, the crafts and points-per-skill-up
  detail sits beneath it, and the advice box holds two lines instead of running past the edge. The whole
  column is measured in the tests now.

## 1.4.3

### Fixed

- **The Level up tab overlapped itself.** The plan list was built 700 px wide, but the materials panel is a
  fixed 622 px anchored to the right, so the two sat on top of each other and the panel's text bled through
  the plan. The plan now lives in the 292 px left column like the Crafting tab, with cost per skill point
  and where the recipe comes from moved into the row tooltip. Vertical spacing was fixed too: the note no
  longer runs into the Find materials button.
- Tests now measure both the width of each tab's left column against the materials panel and the vertical
  stack against the window height, so this class of overlap fails the suite instead of shipping.

## 1.4.2

### Fixed

- **The Level up tab was invisible.** With ten tabs the row reached under the gold display and the buttons
  in the title bar, which are drawn on top of it, so the last tab was hidden. Your gold now sits on the
  left beside the logo, the tabs are slightly narrower, and the row ends 70 px clear of the buttons. A test
  now measures the row and fails if a future tab would run under them.

## 1.4.1

### Changed

- `tools/generate_profession_data.py` now contains the whole pipeline that built the shipped data: client
  files, world database (trainer, recipe item, discovery and quest requirements), AtlasLoot sources, band
  clamping and the threshold estimator. Before this it only read the two client files and would have
  produced a poorer table than the one in the addon.
- The shipped `ProfessionData.lua` is now exactly what that script produces, so the data can be
  regenerated for any server or patch. Four estimated thresholds moved by 1-2 skill points, because the
  estimator is now fitted on all the known recipes rather than a sample.

## 1.4.0

### Added

- **Points per skill-up is configurable** in the Level up tab: retail rules give 1 point per successful
  craft, Warmane's Icecrown gives 3. Left on **Auto**, it is worked out from your own skill-ups as you
  play. Plans change accordingly - three points per craft costs roughly a third as much.
- The plan summary now shows the total number of crafts and the rate in use, and the last skill-up no
  longer overshoots the target.

## 1.3.0

### Added

- **Level up tab**: pick a profession and a target skill and get the cheapest route there, worked out from
  what the materials cost right now. It shows each step (skill range, what to make, how many crafts, cost,
  cost per skill point and where the recipe comes from), the total, and feeds straight into **Find
  materials** and the normal buying flow. Works away from an auctioneer using recorded prices.
- **Profession data for all eleven professions**, Cooking and First Aid included: 3,567 recipes with
  reagents, quantities, what each craft makes and the orange/yellow/green/grey thresholds. Generated from
  the 3.3.5a client files plus the world database (skill requirements) and AtlasLoot (recipe sources);
  96.3% of thresholds are confirmed, the rest are marked as estimated in the interface.
- Thresholds are corrected automatically from your own profession windows: recipe colours seen in game
  override the table for good.

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
