local ADDON, ns = ...

-- Throttle-aware, multi-page auction query engine.
-- job = {
--   params   = { name, minLevel, maxLevel, class, subclass, usable, quality },
--   page     = first page (0-based),
--   maxPages = how many pages to read at most,
--   onPage   = function(entries, page, totalPages, totalAuctions) -> return false to stop
--   onDone   = function(aborted, job)
-- }
local S = CreateFrame("Frame")
ns.Scanner = S
S:Hide()

local PER_PAGE = NUM_AUCTION_ITEMS_PER_PAGE or 50
local RESULT_TIMEOUT = 8

function S:IsBusy()
  return self.job ~= nil
end

function S:Start(job)
  -- a whole-AH scan owns the auction list until it's done
  if ns.FullScan and ns.FullScan.active and not job.fullScan then
    if job.onDone then job.onDone(true, job) end
    return
  end
  if self.job then
    local old = self.job
    self.job = nil
    if old.onDone then old.onDone(true, old) end
  end
  job.page = job.page or 0
  job.maxPages = job.maxPages or 1
  job.pagesRead = 0
  self.job = job
  self.state = "SEND"
  self.wait = 0
  self:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
  self:Show()
end

function S:Stop()
  local job = self.job
  self.job = nil
  self:Hide()
  self:UnregisterEvent("AUCTION_ITEM_LIST_UPDATE")
  if job and job.onDone then job.onDone(true, job) end
end

S:SetScript("OnEvent", function(self)
  if self.state == "WAIT" then
    self.state = "READ"
    self.wait = 0.05
    self.retries = 0
  end
end)

local function ReadPage(job, retries)
  local batch, total = GetNumAuctionItems("list")
  local entries, incomplete = {}, false
  for i = 1, batch do
    local name, texture, count, quality, canUse, level, minBid, minInc, buyout, bidAmount, highBidder, owner =
      GetAuctionItemInfo("list", i)
    local link = GetAuctionItemLink("list", i)
    if not name or name == "" or not link then
      incomplete = true
    else
      if not owner and retries < 6 then incomplete = true end
      entries[#entries + 1] = {
        name = name, link = link, id = ns.ItemID(link), texture = texture,
        count = count or 1, quality = quality or 1, canUse = canUse, level = level or 0,
        minBid = minBid or 0, minInc = minInc or 0, buyout = buyout or 0,
        bid = bidAmount or 0, highBidder = highBidder, owner = owner,
        timeLeft = GetAuctionItemTimeLeft("list", i), page = job.page, index = i,
      }
    end
  end
  return entries, incomplete, total or 0
end

S:SetScript("OnUpdate", function(self, elapsed)
  local job = self.job
  if not job then self:Hide() return end
  if not ns.atAH then self:Stop() return end

  self.wait = self.wait - elapsed
  if self.wait > 0 then return end

  if self.state == "SEND" then
    if CanSendAuctionQuery() then
      local p = job.params or {}
      QueryAuctionItems(p.name or "", p.minLevel or "", p.maxLevel or "", nil, p.class, p.subclass,
        job.page, p.usable and 1 or nil, p.quality or -1)
      self.state = "WAIT"
      self.sentAt = GetTime()
    end
    self.wait = 0.05

  elseif self.state == "WAIT" then
    if GetTime() - self.sentAt > RESULT_TIMEOUT then
      self.state = "SEND"
    end
    self.wait = 0.1

  elseif self.state == "READ" then
    local entries, incomplete, total = ReadPage(job, self.retries)
    if incomplete and self.retries < 20 then
      self.retries = self.retries + 1
      self.wait = 0.15
      return
    end

    job.pagesRead = job.pagesRead + 1
    job.totalPages = math.max(1, math.ceil(total / PER_PAGE))
    local keepGoing = true
    if job.onPage then
      keepGoing = job.onPage(entries, job.page, job.totalPages, total) ~= false
    end
    if self.job ~= job then return end -- a new job replaced this one

    if keepGoing and job.page + 1 < job.totalPages and job.pagesRead < job.maxPages then
      job.page = job.page + 1
      self.state = "SEND"
      self.wait = 0
    else
      self.job = nil
      self:Hide()
      self:UnregisterEvent("AUCTION_ITEM_LIST_UPDATE")
      if job.onDone then job.onDone(false, job) end
    end
  end
end)
