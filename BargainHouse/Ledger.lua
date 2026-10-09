local ADDON, ns = ...
local format, floor = string.format, math.floor

-- Two things the addon could only guess at before:
--
--   What really sells.  Comparing one full scan with the next shows which
--   auctions disappeared. One that vanishes while it still had hours to run was
--   almost certainly bought; one that was already on its last legs probably just
--   expired. That gives a real sale rate per item instead of counting listings.
--
--   Whether a deal was a deal.  What you paid is recorded when you buy, and what
--   you got is recorded when one of your auctions sells, so the profit shown is
--   what happened rather than what was predicted.

local Led = {}
ns.Ledger = Led

local KEEP_DAYS = 30
local SHORT = 2          -- time left 1 (short) or 2 (medium) = it was nearly over

local function Key() return ns.MarketKey and ns.MarketKey() or "?" end
local function Today() return floor(time() / 86400) end

function Led:Book()
  ns.db.ledger = ns.db.ledger or {}
  local key = Key()
  ns.db.ledger[key] = ns.db.ledger[key] or { items = {}, buys = {}, sales = {}, seen = {} }
  return ns.db.ledger[key]
end

---------------------------------------------------------------------------
-- What sells: one scan compared with the next
---------------------------------------------------------------------------
local function Fingerprint(a)
  return format("%s|%d|%d", a.owner or "?", a.count or 1, a.buyout or 0)
end

-- called at the end of a full scan
function Led:AfterScan(groups)
  if not groups then return end
  local book = self:Book()
  local previous, now = book.seen or {}, {}
  local sold, expired, checked = 0, 0, 0

  for id, g in pairs(groups) do
    local here = {}
    for _, a in ipairs(g.auctions) do
      here[Fingerprint(a)] = (a.timeLeft or 4)
    end
    now[id] = here

    local was = previous[id]
    if was then
      checked = checked + 1
      local itemSold, itemGone = 0, 0
      for print_, timeLeft in pairs(was) do
        if not here[print_] then
          itemGone = itemGone + 1
          if timeLeft and timeLeft > SHORT then
            itemSold = itemSold + 1        -- disappeared with time to spare: bought
          else
            expired = expired + 1          -- was nearly over: it ran out
          end
        end
      end
      sold = sold + itemSold
      if itemGone > 0 then self:NoteTurnover(id, itemSold, itemGone) end
    end
  end

  book.seen = now
  book.seenAt = time()
  return sold, expired, checked
end

-- how much of an item goes each day, kept as a short history
function Led:NoteTurnover(id, sold, gone)
  local book = self:Book()
  local rec = book.items[id] or { h = {} }
  book.items[id] = rec
  local today = Today()
  local day = rec.h[#rec.h]
  if day and day[1] == today then
    day[2] = day[2] + sold
    day[3] = day[3] + gone
  else
    rec.h[#rec.h + 1] = { today, sold, gone }
    while #rec.h > KEEP_DAYS do table.remove(rec.h, 1) end
  end
end

-- how many of this item sell in a day, and what share of listings sell at all
function Led:SaleRate(id)
  local rec = self:Book().items[id]
  if not rec or #rec.h == 0 then return nil end
  local sold, gone, days = 0, 0, #rec.h
  for _, d in ipairs(rec.h) do
    sold = sold + d[2]
    gone = gone + d[3]
  end
  return sold / days, (gone > 0) and (sold / gone) or 0, days
end

---------------------------------------------------------------------------
-- What you paid, and what you got
---------------------------------------------------------------------------
function Led:RecordBuy(id, name, count, cost, expected, kind)
  if not id or not count or count <= 0 then return end
  local book = self:Book()
  local rec = book.buys[id] or { n = name, qty = 0, cost = 0, expected = 0, t = time(), kind = kind }
  book.buys[id] = rec
  rec.n = name or rec.n
  rec.qty = rec.qty + count
  rec.cost = rec.cost + (cost or 0)
  rec.expected = rec.expected + (expected or 0)   -- what the addon said it was worth
  rec.t = time()
end

function Led:RecordSale(id, name, count, gross)
  if not id then return end
  local book = self:Book()
  local rec = book.sales[id] or { n = name, qty = 0, gross = 0 }
  book.sales[id] = rec
  rec.n = name or rec.n
  rec.qty = rec.qty + (count or 1)
  rec.gross = rec.gross + (gross or 0)
  rec.t = time()
end

-- everything bought and sold, matched up per item
function Led:Results()
  local book = self:Book()
  local rows, spent, earned, matchedQty = {}, 0, 0, 0
  for id, buy in pairs(book.buys) do
    local sale = book.sales[id]
    local row = { id = id, name = buy.n, bought = buy.qty, cost = buy.cost,
                  expected = buy.expected, sold = sale and sale.qty or 0,
                  gross = sale and sale.gross or 0 }
    row.net = row.gross - row.cost * (row.sold > 0 and math.min(1, row.sold / row.bought) or 0)
    rows[#rows + 1] = row
    spent = spent + buy.cost
    earned = earned + (sale and sale.gross or 0)
    matchedQty = matchedQty + math.min(buy.qty, sale and sale.qty or 0)
  end
  table.sort(rows, function(a, b) return (a.net or 0) > (b.net or 0) end)
  return rows, { spent = spent, earned = earned, profit = earned - spent, matched = matchedQty }
end

-- how often what the addon promised actually happened
function Led:Accuracy()
  local book = self:Book()
  local hits, total, over, under = 0, 0, 0, 0
  for id, buy in pairs(book.buys) do
    local sale = book.sales[id]
    if sale and sale.qty > 0 and buy.qty > 0 and buy.expected > 0 then
      total = total + 1
      local predicted = buy.expected / buy.qty
      local got = sale.gross / sale.qty
      if got >= predicted * 0.9 then hits = hits + 1 end
      if got > predicted then over = over + 1 else under = under + 1 end
    end
  end
  return hits, total, over, under
end

---------------------------------------------------------------------------
-- Your own auctions selling
---------------------------------------------------------------------------
local function ToPattern(fmt)
  if not fmt then return nil end
  local pat = fmt:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
  return (pat:gsub("%%%%s", "(.-)"))
end
local SOLD_PATTERN = ToPattern(ERR_AUCTION_SOLD_S)

-- what we posted, so a sale can be priced
function Led:NotePosted(name, count, unit)
  self.posted = self.posted or {}
  self.posted[strlower(name or "")] = { count = count, unit = unit, t = time() }
end

function Led:OnSystemMessage(msg)
  if not SOLD_PATTERN or type(msg) ~= "string" then return end
  local name = msg:match(SOLD_PATTERN)
  if not name then return end
  name = name:gsub("|H.-|h", ""):gsub("[%[%]|]", "")
  local posted = self.posted and self.posted[strlower(name)]
  local id = ns.db.itemNames and nil
  for itemId, rec in pairs(self:Book().buys) do
    if rec.n and strlower(rec.n) == strlower(name) then id = itemId break end
  end
  local count = posted and posted.count or 1
  local unit = posted and posted.unit or 0
  local gross = floor(unit * count * 0.95)      -- the auction house keeps its cut
  if id then self:RecordSale(id, name, count, gross) end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("CHAT_MSG_SYSTEM")
ev:SetScript("OnEvent", function(_, _, msg) pcall(Led.OnSystemMessage, Led, msg) end)
