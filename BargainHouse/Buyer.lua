local ADDON, ns = ...

---------------------------------------------------------------------------
-- Locate an auction captured earlier so it's on the currently loaded page.
-- params: the query it was found with (page numbers belong to that query)
---------------------------------------------------------------------------
function ns.Locate(a, params, onFound, onGone)
  if ns.FindInList(a) then onFound() return end

  local attempts = {}
  if params and a.page then
    attempts[#attempts + 1] = { params = params, page = a.page }
    if a.page > 0 then attempts[#attempts + 1] = { params = params, page = a.page - 1 } end
  end
  attempts[#attempts + 1] = { params = { name = a.name }, page = 0, maxPages = 6 }

  local step = 0
  local function NextAttempt()
    step = step + 1
    local at = attempts[step]
    if not at then onGone() return end
    local found = false
    ns.Scanner:Start({
      params = at.params,
      page = at.page,
      maxPages = at.maxPages or 1,
      onPage = function()
        if ns.FindInList(a) then
          found = true
          return false
        end
      end,
      onDone = function(aborted)
        if aborted then
          onGone(true) -- interrupted by another scan: the caller retries
          return
        end
        if found then onFound() else NextAttempt() end
      end,
    })
  end
  NextAttempt()
end

---------------------------------------------------------------------------
-- One confirmation for a whole purchase run
---------------------------------------------------------------------------
StaticPopupDialogs["BARGAINHOUSE_BUY"] = {
  text = "%s",
  button1 = "Buy",
  button2 = CANCEL or "Cancel",
  OnAccept = function(self, data)
    local fn = data or self.data
    if fn then fn() end
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
}

function ns.ConfirmBuy(text, fn)
  -- In page mode every click on the Buy button already shows and confirms
  -- the exact amount, so no extra popup.
  if not ns.db.confirmBuy or ns.db.clickMode then fn() return end
  local dialog = StaticPopup_Show("BARGAINHOUSE_BUY", text)
  if dialog then dialog.data = fn else fn() end
end

-- FindInList, skipping list indexes already taken in this batch
local function FindFree(a, used)
  local batch = GetNumAuctionItems("list")
  for i = 1, batch do
    if not used[i] then
      local name, _, count, _, _, _, _, _, buyout, _, _, owner = GetAuctionItemInfo("list", i)
      if name == a.name and count == a.count and (buyout or 0) == a.buyout
        and (not a.owner or not owner or owner == a.owner)
        and GetAuctionItemLink("list", i) == a.link then
        return i, buyout
      end
    end
  end
end

---------------------------------------------------------------------------
-- Purchase result detection
-- Resolved by server signals (won message, money change, auction errors)
-- with a generous timeout, never by a short timer.
---------------------------------------------------------------------------
local function FormatToPattern(fmt)
  if not fmt then return nil end
  local pat = fmt:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
  pat = pat:gsub("%%%%s", "(.+)"):gsub("%%%%d", "%%d+")
  return "^" .. pat .. "$"
end
local WON_PATTERN = FormatToPattern(ERR_AUCTION_WON_S)

local AUCTION_ERRORS = {}
for _, key in ipairs({ "ERR_ITEM_NOT_FOUND", "ERR_AUCTION_HIGHER_BID", "ERR_AUCTION_BID_OWN",
  "ERR_AUCTION_DATABASE_ERROR", "ERR_AUCTION_MIN_BID", "ERR_RESTRICTED_ACCOUNT" }) do
  if _G[key] then AUCTION_ERRORS[_G[key]] = true end
end

local RESULT_TIMEOUT = 15

local watch = CreateFrame("Frame")
watch:RegisterEvent("CHAT_MSG_SYSTEM")
watch:RegisterEvent("UI_ERROR_MESSAGE")
watch:RegisterEvent("PLAYER_MONEY")
watch:RegisterEvent("ADDON_ACTION_BLOCKED")
watch:RegisterEvent("ADDON_ACTION_FORBIDDEN")
watch:SetScript("OnEvent", function(_, event, a1, a2)
  local p = ns.pendingBid
  if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
    -- Only the buy call itself matters (WoW also blames addons for unrelated actions)
    local func = type(a2) == "string" and a2 or ""
    if func:find("PlaceAuctionBid") then ns.bidBlocks = (ns.bidBlocks or 0) + 1 end
    if p and not p.batch and func:find("PlaceAuctionBid") then
      if not ns.db.clickMode then
        ns.db.clickMode = true
        ns.Print("This server only allows buying during a mouse click. From now on each click buys every planned offer on the loaded auction page. (/bh autobuy to try automatic buying again)")
      end
      p.q:Resolve("blocked")
    end
    return
  end
  if not p then return end

  if p.batch then
    if event == "CHAT_MSG_SYSTEM" and WON_PATTERN and a1 then
      local name = a1:match(WON_PATTERN)
      if name then p.won[name] = (p.won[name] or 0) + 1 end
    end
    return -- batches are settled by the poller
  end

  if event == "CHAT_MSG_SYSTEM" then
    if (WON_PATTERN and a1 and a1:match(WON_PATTERN)) or (ERR_AUCTION_BID_PLACED and a1 == ERR_AUCTION_BID_PLACED) then
      p.q:Resolve("won")
    end
  elseif event == "UI_ERROR_MESSAGE" then
    local msg = type(a1) == "string" and a1 or a2
    if msg == ERR_NOT_ENOUGH_MONEY then
      p.q:Resolve("money")
    elseif msg and AUCTION_ERRORS[msg] then
      p.q:Resolve("failed")
    end
  elseif event == "PLAYER_MONEY" then
    if GetMoney() <= p.before - p.buyout then p.q:Resolve("won") end
  end
end)

---------------------------------------------------------------------------
-- Purchase queue
-- list = { { a = auction, params = query, ... }, ... }
-- handlers: onUpdate(q), onBought(q, item, cost), onGone(q, item),
--           onWaiting(q), onFinish(q), onStop(q, reason)
--
-- Automatic mode: every offer is located and bought without clicks.
-- Page mode (servers that require a mouse click for each buy call):
--   the page with the next offers is loaded, q.waiting describes the batch
--   (q.waitingCount / q.waitingCost) and q:Confirm() - called from a click -
--   buys every planned offer on that page at once.
---------------------------------------------------------------------------
local Queue = {}
Queue.__index = Queue

function ns.NewBuyQueue(list, handlers)
  return setmetatable({
    list = list, i = 0, handled = 0, bought = 0, spent = 0, gone = 0,
    h = handlers or {}, active = false,
  }, Queue)
end

function Queue:Call(name, ...)
  local fn = self.h[name]
  if fn then fn(self, ...) end
end

function Queue:Start()
  self.active = true
  self.startMoney = GetMoney()
  self:Next()
end

function Queue:Arm()
  self.active = true
  self.armed = true
  self:Next()
end

-- Silent cancel (no callbacks), used to throw away an armed queue
function Queue:Cancel()
  self.active = false
  self.waiting = nil
  if ns.pendingBid and ns.pendingBid.q == self then ns.pendingBid = nil end
end

function Queue:Stop(reason)
  if not self.active then return end
  self.active = false
  self.waiting = nil
  if ns.pendingBid and ns.pendingBid.q == self then ns.pendingBid = nil end
  self:Call("onStop", reason)
end

function Queue:MarkHandled(item)
  if not item.handled then
    item.handled = true
    self.handled = self.handled + 1
  end
  self.i = math.min(self.handled + 1, #self.list)
end

function Queue:NextUnhandled()
  for _, item in ipairs(self.list) do
    if not item.handled then return item end
  end
end

function Queue:Next()
  if not self.active then return end
  local item = self:NextUnhandled()
  if not item then
    self.i = #self.list
    self.active = false
    self:Call("onFinish")
    return
  end
  self.current = item
  self.i = self.handled + 1
  self.waiting = nil
  self:Call("onUpdate")
  ns.Locate(item.a, item.params, function()
    if not self.active then return end
    if ns.db.clickMode then
      self:PrepareBatch()
    else
      self:Bid(item)
    end
  end, function(interrupted)
    if not self.active then return end
    if interrupted then
      -- another scan took over the auction house: try this offer again shortly
      item.locateFails = (item.locateFails or 0) + 1
      if item.locateFails <= 5 then
        self.i = self.i - 1
        ns.After(1, function() self:Next() end)
        return
      end
    end
    self.gone = self.gone + 1
    self:MarkHandled(item)
    self:Call("onGone", item)
    self:Next()
  end)
end

-- Page mode: collect every unhandled offer present on the loaded page
function Queue:PrepareBatch()
  local batch, used, cost = {}, {}, 0
  for _, item in ipairs(self.list) do
    if not item.handled then
      local idx, buyout = FindFree(item.a, used)
      if idx then
        used[idx] = true
        batch[#batch + 1] = item
        cost = cost + (buyout or item.a.buyout)
      end
    end
  end
  if #batch == 0 then -- page moved on meanwhile
    self:Next()
    return
  end
  self.waiting = batch
  self.waitingCount, self.waitingCost = #batch, cost
  if not self.armed then self:Call("onWaiting") end
  self:Call("onUpdate")
end

-- Cap: never place more items for one material/plan than planned, so a
-- retry can't buy an identical stack from the same seller a second time.
local function CapAllows(item)
  local cap = item.cap
  return not cap or cap.placed + item.a.count <= cap.limit
end
local function CapAdd(item, n)
  if item.cap then item.cap.placed = item.cap.placed + n end
end

function Queue:Confirm()
  if not self.active or not self.waiting then return end
  if self.armed then
    self.armed = false
    self.startMoney = GetMoney()
    self:Call("onStarted")
  end
  local batch = self.waiting
  self.waiting = nil

  local used, placed, total, money = {}, {}, 0, GetMoney()
  for _, item in ipairs(batch) do
    if not item.handled and not CapAllows(item) then
      self.gone = self.gone + 1
      self:MarkHandled(item)
      self:Call("onGone", item)
    elseif not item.handled then
      local idx, buyout = FindFree(item.a, used)
      if idx and buyout and buyout > 0 then
        if money < total + buyout then break end
        local blocksBefore = ns.bidBlocks or 0
        PlaceAuctionBid("list", idx, buyout)
        if (ns.bidBlocks or 0) > blocksBefore then
          break -- the server allows no more purchases in this click; the rest waits for the next one
        end
        used[idx] = true
        item.tries = (item.tries or 0) + 1
        CapAdd(item, item.a.count)
        placed[#placed + 1] = { item = item, buyout = buyout }
        total = total + buyout
      end
    end
  end
  if #placed == 0 then
    if money < ((batch[1] and batch[1].a.buyout) or 0) then
      UIErrorsFrame:AddMessage(ERR_NOT_ENOUGH_MONEY or "Not enough money", 1, 0.2, 0.2)
      self:Stop("|cffff5555Not enough gold to continue.|r")
    else
      self:Next()
    end
    return
  end

  local p = { q = self, batch = true, placed = placed, before = money, total = total,
              started = GetTime(), won = {} }
  ns.pendingBid = p
  self:Call("onUpdate")

  local function Poll()
    if ns.pendingBid ~= p then return end
    local spent = p.before - GetMoney()
    -- wait for every purchase to be charged (slow servers), up to the timeout
    if spent >= p.total or GetTime() - p.started > RESULT_TIMEOUT then
      self:SettleBatch(p)
    else
      ns.After(0.5, Poll)
    end
  end
  ns.After(0.5, Poll)
end

function Queue:SettleBatch(p)
  ns.pendingBid = nil
  if not self.active then return end
  local budget = p.before - GetMoney()
  for _, pl in ipairs(p.placed) do
    local item, a = pl.item, pl.item.a
    self:MarkHandled(item) -- placed purchases are never retried (no double buying)
    if budget >= pl.buyout then
      budget = budget - pl.buyout
      self.bought = self.bought + a.count
      self.spent = self.spent + pl.buyout
      ns.RecordPurchase(a)
      self:Call("onBought", item, pl.buyout)
    else
      self.gone = self.gone + 1 -- not charged: sold to someone else first
      self:Call("onGone", item)
    end
  end
  PlaySound("LOOTWINDOWCOINSOUND")
  self:Call("onUpdate")
  ns.After(0.5, function() self:Next() end)
end

function Queue:Bid(item)
  self.waiting = nil
  local a = item.a
  if not CapAllows(item) then
    self.gone = self.gone + 1
    self:MarkHandled(item)
    self:Call("onGone", item)
    self:Next()
    return
  end
  local idx = ns.FindInList(a)
  if not idx then
    self:Next() -- the page changed; locate this offer again
    return
  end
  local buyout = select(9, GetAuctionItemInfo("list", idx))
  if not buyout or buyout <= 0 then
    self:MarkHandled(item)
    self:Next()
    return
  end
  if GetMoney() < buyout then
    UIErrorsFrame:AddMessage(ERR_NOT_ENOUGH_MONEY or "Not enough money", 1, 0.2, 0.2)
    self:Stop("|cffff5555Not enough gold to continue.|r")
    return
  end

  item.tries = (item.tries or 0) + 1
  local p = { q = self, item = item, before = GetMoney(), buyout = buyout, started = GetTime() }
  ns.pendingBid = p
  local blocksBefore = ns.bidBlocks or 0
  PlaceAuctionBid("list", idx, buyout)
  if (ns.bidBlocks or 0) > blocksBefore then return end -- handled as "blocked"
  CapAdd(item, a.count)
  self:Call("onUpdate")

  local function Poll()
    if ns.pendingBid ~= p then return end
    if GetMoney() <= p.before - p.buyout then
      self:Resolve("won")
    elseif GetTime() - p.started < RESULT_TIMEOUT then
      ns.After(0.5, Poll)
    else
      self:Resolve("timeout")
    end
  end
  ns.After(0.5, Poll)
end

function Queue:Resolve(result)
  local p = ns.pendingBid
  if not p or p.q ~= self or p.batch then return end
  ns.pendingBid = nil
  if not self.active then return end
  local item = p.item

  if result == "timeout" and GetMoney() <= p.before - p.buyout then result = "won" end

  if result == "won" then
    self.bought = self.bought + item.a.count
    self.spent = self.spent + p.buyout
    self:MarkHandled(item)
    ns.RecordPurchase(item.a)
    PlaySound("LOOTWINDOWCOINSOUND")
    self:Call("onBought", item, p.buyout)
    self:Call("onUpdate")
    ns.After(0.3, function() self:Next() end)
  elseif result == "money" then
    self:Stop("|cffff5555Not enough gold to continue.|r")
  elseif result == "blocked" then
    item.tries = item.tries - 1
    self:PrepareBatch() -- the offer is on the loaded page: wait for a click
  else
    -- failed or no answer: never retried, so an identical stack can't be bought twice
    self.gone = self.gone + 1
    self:MarkHandled(item)
    self:Call("onGone", item)
    ns.After(0.3, function() self:Next() end)
  end
end

