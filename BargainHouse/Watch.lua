local ADDON, ns = ...
local format, floor = string.format, math.floor

-- Keeps an eye on chosen items while the auction house is open.
-- ns.db.watch = { { name = , maxUnit = (copper, optional), id = , link = , ... }, ... }
-- It only scans when nothing else is using the auction house, one item at a
-- time, so it never gets in the way of searching, scanning or buying.

local W = CreateFrame("Frame")
ns.Watch = W
W:Hide()

local DEFAULT_EVERY = 15 -- seconds between two item checks (configurable)
local REALERT = 600      -- don't repeat the same alert within 10 minutes

-- seconds between checks; one item is checked each time, so with 4 watched
-- items and 15s each item comes round about every minute
function W:Interval()
  local v = tonumber(ns.db and ns.db.watchInterval) or DEFAULT_EVERY
  return math.max(5, math.min(600, v))
end

-- how long until the same item is checked again
function W:CycleTime()
  return self:Interval() * math.max(1, #self:List())
end

function W:List()
  ns.db.watch = ns.db.watch or {}
  return ns.db.watch
end

function W:Find(name)
  local lname = strlower(name or "")
  for i, item in ipairs(self:List()) do
    if strlower(item.name) == lname then return i, item end
  end
end

function W:Add(name, maxUnit)
  name = strtrim(name or "")
  if name == "" then return false, "Type an item name." end
  local link
  if name:find("|H") then
    link = name
    name = name:match("%[(.-)%]") or name
  end
  if self:Find(name) then return false, name .. " is already watched." end
  local list = self:List()
  list[#list + 1] = { name = name, maxUnit = maxUnit and maxUnit > 0 and maxUnit or nil,
                      link = link, id = ns.ItemID(link), added = time() }
  self:Kick()
  return true
end

function W:Remove(item)
  local list = self:List()
  for i, w in ipairs(list) do
    if w == item or strlower(w.name) == strlower(item.name or "") then
      table.remove(list, i)
      return true
    end
  end
end

function W:Kick()
  self.nextAt = 0
  if ns.atAH and ns.db.watchEnabled ~= false and #self:List() > 0 then self:Show() else self:Hide() end
end

---------------------------------------------------------------------------
-- Scanning, one item at a time and only when nothing else needs the AH
---------------------------------------------------------------------------
local function Busy()
  if ns.FullScan and ns.FullScan.active then return true end
  if ns.Scanner and ns.Scanner:IsBusy() then return true end
  if ns.Browse and (ns.Browse.scanning or ns.Browse.queue) then return true end
  if ns.DealsTab and ns.DealsTab.queue then return true end
  for _, panel in ipairs(ns.panels or {}) do
    if panel.scanning or panel.queue then return true end
  end
  if ns.ProfitCheck and ns.ProfitCheck.scanning then return true end
  return false
end

W:SetScript("OnUpdate", function(self, elapsed)
  if not ns.db or ns.db.watchEnabled == false or not ns.atAH then self:Hide() return end
  local list = self:List()
  if #list == 0 then self:Hide() return end
  self.timer = (self.timer or 0) - elapsed
  if self.timer > 0 then return end
  self.timer = 1
  if GetTime() < (self.nextAt or 0) or Busy() or self.scanning then return end
  self.index = ((self.index or 0) % #list) + 1
  self:Check(list[self.index])
end)

function W:Check(item)
  if not item or self.scanning then return end
  self.scanning = item
  self.nextAt = GetTime() + self:Interval()
  local lname = strlower(item.name)
  local found = {}
  ns.Scanner:Start({
    params = { name = item.name },
    page = 0,
    maxPages = 3,
    onPage = function(entries)
      for _, a in ipairs(entries) do
        if strlower(a.name) == lname then
          a.unit = a.buyout > 0 and (a.buyout / a.count) or nil
          found[#found + 1] = a
        end
      end
    end,
    onDone = function(aborted)
      W.scanning = nil
      if aborted then return end
      W:Evaluate(item, found)
    end,
  })
end

-- what counts as a deal for this item
function W:Threshold(item)
  if item.maxUnit and item.maxUnit > 0 then return item.maxUnit, "your price" end
  local id = item.id or ns.ResolveItemID(item.link, item.name)
  local value = id and ns.MarketValue(id)
  if value then return floor(value * (1 - (ns.db.watchMargin or 20) / 100)), "market value" end
end

function W:Evaluate(item, auctions)
  item.checked = time()
  item.listed = #auctions
  local me = ns.Me()
  local offers, best = {}, nil
  local limit, why = self:Threshold(item)
  for _, a in ipairs(auctions) do
    if a.unit and a.owner ~= me then
      if not best or a.unit < best then best = a.unit end
      if limit and a.unit <= limit then offers[#offers + 1] = a end
    end
  end
  item.best = best
  if auctions[1] then
    item.link = item.link or auctions[1].link
    item.id = item.id or auctions[1].id
    item.texture = auctions[1].texture
    item.quality = auctions[1].quality
    item.name = auctions[1].name
  end
  table.sort(offers, function(a, b) return a.unit < b.unit end)

  if #offers == 0 then
    item.hit = nil
    if ns.DealsTab and ns.DealsTab.list then ns.DealsTab:Refresh() end
    return
  end

  local qty, cost = 0, 0
  for _, a in ipairs(offers) do
    qty = qty + a.count
    cost = cost + a.buyout
  end
  item.hit = { offers = offers, qty = qty, cost = cost, unit = offers[1].unit, limit = limit, t = time(),
               params = { name = item.name } }

  local key = format("%s:%d:%d", item.name, floor(offers[1].unit), qty)
  self.alerted = self.alerted or {}
  if (self.alerted[key] or 0) + REALERT < time() then
    self.alerted[key] = time()
    ns.Print(format("|cff66dd88Watch:|r %s - %d for %s (%s each, under %s from %s)",
      item.link or item.name, qty, ns.Money(cost), ns.Money(offers[1].unit), ns.Money(limit), why or "your price"))
    PlaySound("AuctionWindowOpen")
  end
  if ns.DealsTab and ns.DealsTab.list then ns.DealsTab:Refresh() end
end

-- watch hits shown in the Deals list (so they can be bought like any deal)
function W:Deals()
  local out = {}
  for _, item in ipairs(self:List()) do
    local hit = item.hit
    if hit and #hit.offers > 0 then
      local value = item.id and ns.MarketValue(item.id)
      local sellUnit = value and value * 0.95 or (hit.limit or hit.unit)
      local d = { id = item.id, name = item.name, link = item.link, texture = item.texture, quality = item.quality,
                  kind = "watch", offers = hit.offers, qty = hit.qty, cost = hit.cost, value = value,
                  sellUnit = sellUnit, confidence = 3, days = 0, listed = item.listed or #hit.offers,
                  params = hit.params, watch = item }
      d.revenue = floor(sellUnit * d.qty)
      d.profit = d.revenue - d.cost
      d.roi = d.cost > 0 and floor(d.profit / d.cost * 100) or 0
      d.offersN = #d.offers
      out[#out + 1] = d
    end
  end
  return out
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("AUCTION_HOUSE_SHOW")
ev:RegisterEvent("AUCTION_HOUSE_CLOSED")
ev:SetScript("OnEvent", function(_, event)
  if event == "AUCTION_HOUSE_SHOW" then
    ns.After(3, function() W:Kick() end)
  else
    W.scanning = nil
    W:Hide()
  end
end)
