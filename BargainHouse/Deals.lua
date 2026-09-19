local ADDON, ns = ...
local format, floor = string.format, math.floor

-- Whole auction house scan + market history + deal finder.
--   ns.db.market[realm-faction][itemID] = { n = name, q = quality, h = { { day, median, min, qty, count }, ... } }
--   ns.db.lastScan[realm-faction] = { t = time, auctions = n, items = n, mode = "getall"/"pages" }
-- Scanned auctions themselves stay in memory for the session (ns.FullScan.rows).

local HISTORY_DAYS = 7
local FORGET_DAYS = 21
local AH_CUT = 0.05
local GETALL_COOLDOWN = 15 * 60
local READ_PER_FRAME = 400

local FS = CreateFrame("Frame")
ns.FullScan = FS
FS:Hide()

local function Key()
  return (GetRealmName() or "?") .. " - " .. (UnitFactionGroup("player") or "?")
end
ns.MarketKey = Key

local function Today() return floor(time() / 86400) end

function FS:Info()
  local last = ns.db.lastScan and ns.db.lastScan[Key()]
  return last
end

function FS:GetAllReadyIn()
  local t = ns.db.lastGetAll and ns.db.lastGetAll[Key()]
  if not t then return 0 end
  return math.max(0, GETALL_COOLDOWN - (time() - t))
end

---------------------------------------------------------------------------
-- Scanning
---------------------------------------------------------------------------
function FS:Start(mode, onProgress, onDone)
  if self.active or not ns.atAH then return end
  ns.Scanner:Stop()
  self.rows, self.onProgress, self.onDone = {}, onProgress, onDone
  self.active = true
  self.started = GetTime()

  if mode == "getall" then
    local _, canAll = CanSendAuctionQuery()
    if not canAll then
      local wait = self:GetAllReadyIn()
      self:Progress(0, wait > 0 and format("Fast scan available again in %d min - scanning page by page", math.ceil(wait / 60))
        or "Fast scan not allowed right now - scanning page by page")
      mode = "pages"
    end
  end
  self.mode = mode

  if mode == "getall" then
    ns.db.lastGetAll = ns.db.lastGetAll or {}
    ns.db.lastGetAll[Key()] = time()
    self.state, self.lastEvent, self.lastCount = "wait", GetTime(), -1
    self:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
    QueryAuctionItems("", "", "", nil, nil, nil, 0, nil, -1, true)
    self:Progress(0, "Downloading the whole auction house (the game may freeze briefly)...")
    self:Show()
  else
    self.state = "pages"
    ns.Scanner:Start({
      fullScan = true,
      params = {},
      page = 0,
      maxPages = 100000,
      onPage = function(entries, page, totalPages, total)
        if not FS.active then return false end
        for _, e in ipairs(entries) do FS:AddRow(e) end
        FS:Progress((page + 1) / totalPages, format("Scanning page %d of %d  (%d auctions)", page + 1, totalPages, total))
      end,
      onDone = function(aborted)
        if not FS.active or FS.mode ~= "pages" then return end
        FS:Finish(aborted)
      end,
    })
  end
end

function FS:Stop()
  if not self.active then return end
  if self.mode == "pages" then
    ns.Scanner:Stop() -- calls Finish(aborted)
  else
    self:Finish(true)
  end
end

function FS:Progress(frac, text)
  if self.onProgress then self.onProgress(frac, text) end
end

function FS:AddRow(e)
  if not e.id or e.buyout <= 0 then
    if e.id then self.rows[#self.rows + 1] = e end
    return
  end
  e.unit = e.buyout / e.count
  self.rows[#self.rows + 1] = e
end

FS:SetScript("OnEvent", function(self)
  if self.state == "wait" then self.lastEvent = GetTime() end
end)

FS:SetScript("OnUpdate", function(self)
  if not self.active or self.mode ~= "getall" then self:Hide() return end
  if not ns.atAH then self:Finish(true) return end
  local now = GetTime()

  if self.state == "wait" then
    -- the list arrives in one go; wait until it stops growing
    local batch = GetNumAuctionItems("list")
    if batch ~= self.lastCount then
      self.lastCount, self.lastEvent = batch, now
    elseif batch > 0 and now - self.lastEvent > 2 then
      self.state, self.total, self.i = "read", batch, 0
      self:UnregisterEvent("AUCTION_ITEM_LIST_UPDATE")
    elseif now - self.started > 180 then
      self:Finish(true)
    end
    return
  end

  if self.state == "read" then
    local last = math.min(self.total, self.i + READ_PER_FRAME)
    for i = self.i + 1, last do
      local name, texture, count, quality, _, level, minBid, _, buyout, bid, _, owner = GetAuctionItemInfo("list", i)
      local link = name and GetAuctionItemLink("list", i)
      if link then
        self:AddRow({
          name = name, link = link, id = ns.ItemID(link), texture = texture, count = count or 1,
          quality = quality or 1, level = level or 0, minBid = minBid or 0, buyout = buyout or 0,
          bid = bid or 0, owner = owner, timeLeft = GetAuctionItemTimeLeft("list", i), page = 0,
        })
      end
    end
    self.i = last
    self:Progress(last / self.total, format("Reading %d of %d auctions", last, self.total))
    if last >= self.total then self:Finish(false) end
  end
end)

function FS:Finish(aborted)
  if not self.active then return end
  self.active = false
  self:Hide()
  self:UnregisterEvent("AUCTION_ITEM_LIST_UPDATE")
  local items = self:Aggregate(not aborted)
  ns.db.lastScan = ns.db.lastScan or {}
  if not aborted then
    ns.db.lastScan[Key()] = { t = time(), auctions = #self.rows, items = items, mode = self.mode,
                              cand = self:Candidates() }
    self.remote = nil
    if ns.Sync and ns.Sync.ScanChanged then ns.Sync:ScanChanged() end
  end
  self.scanTime = time()
  if self.onDone then self.onDone(aborted, #self.rows, items) end
end

---------------------------------------------------------------------------
-- Market history
---------------------------------------------------------------------------
local function WeightedMedian(list)
  table.sort(list, function(a, b) return a[1] < b[1] end)
  local total = 0
  for _, x in ipairs(list) do total = total + x[2] end
  local half, acc = total / 2, 0
  for _, x in ipairs(list) do
    acc = acc + x[2]
    if acc >= half then return x[1], total end
  end
  return list[#list] and list[#list][1] or 0, total
end

-- Replaces what we know about one item with a fresh look at the auction house
-- (used right after buying, so the list shows what is actually left).
function FS:ReplaceItem(id, name, auctions)
  if not self.groups then return end
  local g = self.groups[id]
  if not g then
    if #auctions == 0 then return end
    g = { id = id, name = name, link = auctions[1].link, texture = auctions[1].texture,
          quality = auctions[1].quality, auctions = {} }
    self.groups[id] = g
  end
  g.auctions = auctions
  if #auctions == 0 then self.groups[id] = nil end
end

-- Builds self.groups (per item) and, when record is true, stores today's summary
function FS:Aggregate(record)
  local groups = {}
  for _, e in ipairs(self.rows) do
    local g = groups[e.id]
    if not g then
      g = { id = e.id, name = e.name, link = e.link, texture = e.texture, quality = e.quality, auctions = {} }
      groups[e.id] = g
    end
    g.auctions[#g.auctions + 1] = e
  end
  self.groups = groups

  ns.db.market = ns.db.market or {}
  local book = ns.db.market[Key()] or {}
  ns.db.market[Key()] = book
  local today, n = Today(), 0

  for id, g in pairs(groups) do
    n = n + 1
    local prices, low, count = {}, nil, 0
    for _, a in ipairs(g.auctions) do
      if a.unit then
        prices[#prices + 1] = { a.unit, a.count }
        count = count + 1
        if not low or a.unit < low then low = a.unit end
      end
    end
    g.count = count
    if count > 0 then
      local med, qty = WeightedMedian(prices)
      g.median, g.low, g.qty = med, low, qty
      if record then
        ns.RecordPrice(id, low)
        local m = book[id] or { h = {} }
        book[id] = m
        m.n, m.q = g.name, g.quality
        local h = m.h
        local entry = { today, floor(med), floor(low), qty, count }
        if h[#h] and h[#h][1] == today then h[#h] = entry else h[#h + 1] = entry end
        while #h > HISTORY_DAYS do table.remove(h, 1) end
      end
    end
  end

  if record then
    for id, m in pairs(book) do
      local h = m.h
      if not h[#h] or today - h[#h][1] > FORGET_DAYS then book[id] = nil end
    end
  end
  return n
end

-- Market value per unit: median of the daily medians. Returns value, days, avgListings
function ns.MarketValue(id)
  local book = ns.db.market and ns.db.market[Key()]
  local m = book and book[id]
  if not m or #m.h == 0 then return nil, 0, 0 end
  local meds, listings = {}, 0
  for _, d in ipairs(m.h) do
    meds[#meds + 1] = d[2]
    listings = listings + (d[5] or 0)
  end
  table.sort(meds)
  local k = #meds
  local value = (k % 2 == 1) and meds[(k + 1) / 2] or floor((meds[k / 2] + meds[k / 2 + 1]) / 2)
  return value, k, listings / k
end

---------------------------------------------------------------------------
-- Deals
-- opts: minProfit (copper), minROI (percent), maxSpend (copper, 0 = any),
--       minConfidence (1..3), kind ("all"/"resell"/"vendor")
---------------------------------------------------------------------------
local function Confidence(days, listings)
  if days >= 3 and listings >= 5 then return 3 end
  if days >= 2 or listings >= 8 then return 2 end
  return 1
end
ns.CONFIDENCE_TEXT = { "|cffff8866Low|r", "|cffffd100Medium|r", "|cff66dd88High|r" }

function FS:Deals(opts)
  local deals = {}
  if not self.groups then return deals end
  local me = ns.Me()
  local roi = (opts.minROI or 0) / 100

  for id, g in pairs(self.groups) do
    local offers = {}
    for _, a in ipairs(g.auctions) do
      if a.unit and a.owner ~= me then offers[#offers + 1] = a end
    end
    if #offers > 0 then
      table.sort(offers, function(a, b) return a.unit < b.unit end)
      local _, _, _, _, _, _, _, _, _, _, vendor = GetItemInfo(g.link)
      local value, days, listings = ns.MarketValue(id)

      local function Build(kind, sellUnit, conf)
        -- buy every offer that still makes the required return when resold at sellUnit
        local limit = sellUnit / (1 + roi)
        local d = { id = id, name = g.name, link = g.link, texture = g.texture, quality = g.quality, kind = kind,
                    offers = {}, qty = 0, cost = 0, value = value, sellUnit = sellUnit, confidence = conf,
                    days = days, listed = #g.auctions }
        for _, a in ipairs(offers) do
          if a.unit > limit then break end
          if opts.maxSpend and opts.maxSpend > 0 and d.cost + a.buyout > opts.maxSpend then break end
          d.offers[#d.offers + 1] = a
          d.qty = d.qty + a.count
          d.cost = d.cost + a.buyout
        end
        if #d.offers == 0 then return nil end
        d.revenue = floor(sellUnit * d.qty)
        d.profit = d.revenue - d.cost
        d.roi = d.cost > 0 and floor(d.profit / d.cost * 100) or 0
        if d.profit < (opts.minProfit or 0) then return nil end
        return d
      end

      local best
      if vendor and vendor > 0 and opts.kind ~= "resell" then
        best = Build("vendor", vendor, 3)
      end
      local vendorBuy = ns.VendorPrice(id)
      local isVendorItem = ns.IsVendorItem(id, g.name)
      -- nobody pays more on the AH than a vendor charges: cap the resale value,
      -- and skip vendor items whose vendor price is unknown
      if value and vendorBuy then value = math.min(value, vendorBuy) end
      if value and opts.kind ~= "vendor" and not (isVendorItem and not vendorBuy) then
        local conf = Confidence(days, listings)
        if conf >= (opts.minConfidence or 1) then
          local d = Build("resell", value * (1 - AH_CUT), conf)
          if d and (not best or d.profit > best.profit) then best = d end
        end
      end
      if best then deals[#deals + 1] = best end
    end
  end
  return deals
end

---------------------------------------------------------------------------
-- Sharing scans between accounts (see Sync.lua)
-- Candidates = offers that may be deals: at most 90% of market value, or
-- below the vendor sell price. Stored compactly so they can be sent later:
--   "id,count,buyout,quality,owner,name"
---------------------------------------------------------------------------
local CAND_PER_ITEM, CAND_MAX = 15, 3000

local function Clean(s) return (tostring(s or ""):gsub("[,~%^`}|]", " ")) end

function FS:Candidates()
  local out = {}
  for id, g in pairs(self.groups or {}) do
    local value = ns.MarketValue(id)
    local _, _, _, _, _, _, _, _, _, _, vendor = GetItemInfo(g.link)
    local offers = {}
    for _, a in ipairs(g.auctions) do
      if a.unit and ((value and a.unit <= value * 0.9) or (vendor and vendor > 0 and a.unit < vendor)) then
        offers[#offers + 1] = a
      end
    end
    table.sort(offers, function(a, b) return a.unit < b.unit end)
    for i = 1, math.min(#offers, CAND_PER_ITEM) do
      local a = offers[i]
      out[#out + 1] = table.concat({ id, a.count, a.buyout, a.quality or 1, Clean(a.owner), Clean(a.name) }, ",")
      if #out >= CAND_MAX then return out end
    end
  end
  return out
end

-- newest scan this account knows about (its own or a shared one)
function FS:LatestScan()
  local mine = ns.db.lastScan and ns.db.lastScan[Key()]
  local remote = ns.db.remoteScan and ns.db.remoteScan[Key()]
  if remote and (not mine or remote.t > mine.t) then return remote, true end
  return mine, false
end

function FS:RemoteInfo()
  local latest, isRemote = self:LatestScan()
  if isRemote then return latest end
end

-- today's (scan day's) market summary as compact lines "id,median,min,qty,count"
function FS:MarketLines(day)
  local book = ns.db.market and ns.db.market[Key()]
  local out = {}
  for id, m in pairs(book or {}) do
    for _, d in ipairs(m.h) do
      if d[1] == day then
        out[#out + 1] = table.concat({ id, d[2], d[3], d[4], d[5] or 0, Clean(m.n) }, ",")
      end
    end
  end
  return out
end

-- merge another account's day summaries; the more complete one (more listings) wins
function FS:MergeMarket(day, lines)
  ns.db.market = ns.db.market or {}
  local book = ns.db.market[Key()] or {}
  ns.db.market[Key()] = book
  local merged = 0
  for _, line in ipairs(lines) do
    local id, med, low, qty, cnt, name = line:match("^(%d+),(%d+),(%d+),(%d+),(%d+),(.*)$")
    id = tonumber(id)
    if id then
      local entry = { day, tonumber(med), tonumber(low), tonumber(qty), tonumber(cnt) }
      local m = book[id] or { h = {} }
      book[id] = m
      if name ~= "" then m.n = m.n or name end
      local h, placed = m.h, false
      for k, d in ipairs(h) do
        if d[1] == day then
          if (entry[5] or 0) > (d[5] or 0) then h[k] = entry; merged = merged + 1 end
          placed = true
          break
        end
      end
      if not placed then
        h[#h + 1] = entry
        table.sort(h, function(a, b) return a[1] < b[1] end)
        while #h > HISTORY_DAYS do table.remove(h, 1) end
        merged = merged + 1
      end
      if entry[3] and entry[3] > 0 then ns.RecordPrice(id, entry[3]) end
    end
  end
  return merged
end

-- use a scan shared by another account for the Deals tab
function FS:StoreRemote(t, from, cand)
  ns.db.remoteScan = ns.db.remoteScan or {}
  ns.db.remoteScan[Key()] = { t = t, from = from, cand = cand, auctions = #cand }
  self:LoadRemote()
end

function FS:LoadRemote()
  if self.active then return end
  local latest, isRemote = self:LatestScan()
  if not isRemote then return end
  local rows = {}
  for _, line in ipairs(latest.cand or {}) do
    local id, count, buyout, quality, owner, name = line:match("^(%d+),(%d+),(%d+),(%d+),(.-),(.*)$")
    id, count, buyout = tonumber(id), tonumber(count), tonumber(buyout)
    if id and count and count > 0 and buyout and buyout > 0 then
      local _, link, q, _, _, _, _, _, _, texture = GetItemInfo(id)
      q = q or tonumber(quality) or 1
      local color = (ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]) and ns.QualityHex(q):sub(3) or "ffffffff"
      rows[#rows + 1] = {
        id = id, name = name, count = count, buyout = buyout, unit = buyout / count, quality = q,
        owner = owner ~= "" and owner or nil, texture = texture, page = 0, level = 0, minBid = 0, bid = 0,
        link = link or format("|c%s|Hitem:%d:0:0:0:0:0:0:0|h[%s]|h|r", color, id, name),
      }
    end
  end
  self.rows = rows
  self:Aggregate(false)
  self.remote = latest
  self.scanTime = latest.t
end
