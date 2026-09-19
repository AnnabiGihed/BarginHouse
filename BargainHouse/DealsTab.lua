local ADDON, ns = ...
local C = ns.C
local format, floor = string.format, math.floor

local D = { deals = {}, selected = {} }
ns.DealsTab = D

function D:Create(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  self.frame = f
  ns.db.dealFilters = ns.db.dealFilters or { minProfit = 50000, minROI = 20, maxSpend = 0, minConfidence = 2, kind = "all", mode = "getall" }
  local opts = ns.db.dealFilters

  -- Row 1: scan -----------------------------------------------------------
  local scan = ns.Button(f, "Scan whole AH", 150, 28, "accent")
  scan:SetPoint("TOPLEFT")
  scan:SetScript("OnClick", function()
    if ns.FullScan.active then ns.FullScan:Stop() else D:StartScan() end
  end)
  self.scanBtn = scan

  local mode = ns.Dropdown(f, 170, 28, function(v) opts.mode = v end)
  mode:SetPoint("LEFT", scan, "RIGHT", 6, 0)
  mode:SetItems({
    { value = "getall", text = "Fast (once / 15 min)" },
    { value = "pages", text = "Page by page (slow)" },
  })
  mode:SetValue(opts.mode, true)
  mode.tooltip = "Fast downloads everything in one request (allowed every 15 minutes; the game can freeze a few seconds on big auction houses). Page by page is slower but always allowed."

  local search = ns.EditBox(f, 190, 28, "Search deals...")
  search:SetPoint("TOPRIGHT")
  search.acceptsLinks = "replace"
  search.onChange = function() D:Sort() end
  search.onEnter = function() D:Sort() end
  self.search = search

  local watchBtn = ns.Button(f, "Watchlist", 90, 28)
  watchBtn:SetPoint("RIGHT", search, "LEFT", -6, 0)
  watchBtn.tooltip = "Keep an eye on chosen items and get told when a cheap offer appears"
  watchBtn:SetScript("OnClick", function()
    if D.watchFrame:IsShown() then D.watchFrame:Hide() else D.watchFrame:Show(); D:RefreshWatch() end
  end)

  local statusBox = CreateFrame("Button", nil, f)
  statusBox:SetPoint("TOPLEFT", mode, "TOPRIGHT", 12, 0)
  statusBox:SetPoint("BOTTOMRIGHT", watchBtn, "BOTTOMLEFT", -10, 0)
  statusBox:SetScript("OnEnter", function(self2)
    if not D.statusTip then return end
    GameTooltip:SetOwner(self2, "ANCHOR_BOTTOM")
    GameTooltip:SetText(D.statusTip[1] or "", 1, 1, 1)
    for i = 2, #D.statusTip do GameTooltip:AddLine(D.statusTip[i], 0.8, 0.8, 0.8, true) end
    GameTooltip:Show()
  end)
  statusBox:SetScript("OnLeave", function() GameTooltip:Hide() end)

  self.statusBox = statusBox

  local status = ns.Text(statusBox, "BHFontSmall", "")
  status:SetPoint("TOPLEFT", 0, -2)
  status:SetPoint("RIGHT", 0, 0)
  status:SetHeight(14)
  self.status = status
  local prog = ns.Progress(statusBox, 10, 4)
  prog:SetPoint("BOTTOMLEFT", 0, 3)
  prog:SetPoint("BOTTOMRIGHT", 0, 3)
  self.prog = prog

  -- Row 2: filters ----------------------------------------------------------
  local function Label(text, anchor, x)
    local l = ns.Text(f, "BHFontSmall", text)
    if anchor then l:SetPoint("LEFT", anchor, "RIGHT", x or 12, 0) else l:SetPoint("TOPLEFT", 0, -42) end
    return l
  end
  local l1 = Label("Min profit")
  local minProfit = ns.MoneyInput(f, function(v) opts.minProfit = v; D:Refresh() end)
  minProfit:SetPoint("LEFT", l1, "RIGHT", 6, 0)
  minProfit:SetCopper(opts.minProfit)

  local l2 = Label("Min return %", minProfit, 16)
  local roi = ns.EditBox(f, 40, 22, nil, true)
  roi:SetPoint("LEFT", l2, "RIGHT", 6, 0)
  roi:SetMaxLetters(4)
  roi:SetTextSilent(opts.minROI)
  roi.onChange = function(self) opts.minROI = tonumber(self:GetText()) or 0; D:Refresh() end

  local l3 = Label("Max spend / item", roi, 16)
  local maxSpend = ns.MoneyInput(f, function(v) opts.maxSpend = v; D:Refresh() end)
  maxSpend:SetPoint("LEFT", l3, "RIGHT", 6, 0)
  maxSpend:SetCopper(opts.maxSpend)

  local conf = ns.Dropdown(f, 118, 22, function(v) opts.minConfidence = v; D:Refresh() end)
  conf:SetPoint("LEFT", maxSpend, "RIGHT", 16, 0)
  conf:SetItems({
    { value = 1, text = "Any confidence" },
    { value = 2, text = "Medium or high" },
    { value = 3, text = "High only" },
  })
  conf:SetValue(opts.minConfidence, true)
  conf.tooltip = "How much price history backs the market value: High = 3+ days of scans with 5+ listings. Vendor deals are always High."

  local kind = ns.Dropdown(f, 96, 22, function(v) opts.kind = v; D:Refresh() end)
  kind:SetPoint("LEFT", conf, "RIGHT", 6, 0)
  kind:SetItems({
    { value = "all", text = "All deals" },
    { value = "resell", text = "Resell" },
    { value = "vendor", text = "Vendor" },
  })
  kind:SetValue(opts.kind, true)

  -- List --------------------------------------------------------------------
  local cols = {
    { text = "Item", w = 176, key = "name" },
    { text = "Type", w = 46, key = "kind" },
    { text = "Offers", w = 40, key = "offersN", j = "RIGHT" },
    { text = "Qty", w = 40, key = "qty", j = "RIGHT" },
    { text = "Cost", w = 100, key = "cost", j = "RIGHT" },
    { text = "Buy each", w = 92, key = "buyUnit", j = "RIGHT" },
    { text = "Sell each", w = 94, key = "sellUnit", j = "RIGHT" },
    { text = "Profit", w = 100, key = "profit", j = "RIGHT" },
    { text = "Return", w = 48, key = "roi", j = "RIGHT" },
    { text = "Confidence", w = 64, key = "confidence", font = "BHFontSmall" },
  }
  local list = ns.List(f, "BargainHouseDealList", 920, 418, 22, cols, true)
  list:SetPoint("TOPLEFT", 0, -72)
  list.emptyText = "Scan the whole auction house, then flip opportunities show up here.\n\nScan once a day or so: market values get more reliable with every day of history."
  list.sortKey, list.sortAsc = "profit", false
  list.onSort = function(k)
    if list.sortKey == k then list.sortAsc = not list.sortAsc
    else list.sortKey, list.sortAsc = k, (k == "name" or k == "kind") end
    D:Sort()
  end
  list.marked = self.selected
  list.update = function(r, d)
    r.icon:SetTexture(d.texture)
    r.cols[1]:SetText((D.selected[d] and (ns.ACCENT .. "> |r") or "") .. ns.QualityHex(d.quality) .. d.name .. "|r")
    if d.kind == "watch" then r.cols[2]:SetText("|cff66bbffWatch|r")
    elseif d.kind == "vendor" then r.cols[2]:SetText("|cff66dd88Vendor|r")
    else r.cols[2]:SetText("|cffe6cc80Resell|r") end
    r.cols[3]:SetText(#d.offers)
    r.cols[4]:SetText(d.qty)
    r.cols[5]:SetText(ns.MoneyShort(d.cost))
    r.cols[6]:SetText(ns.MoneyShort(d.buyUnit))
    r.cols[7]:SetText(ns.MoneyShort(d.sellUnit))
    r.cols[8]:SetText("|cff66dd88+|r" .. ns.MoneyShort(d.profit))
    r.cols[9]:SetText(d.roi .. "%")
    r.cols[10]:SetText(ns.CONFIDENCE_TEXT[d.confidence])
  end
  list.onClick = function(d, button)
    if button == "RightButton" then
      ns.main:SelectTab(1)
      ns.Browse.search:SetTextSilent(d.name)
      ns.Browse.mode:SetValue("EXACT")
      ns.Browse:DoSearch()
      return
    end
    if IsModifiedClick() then HandleModifiedItemClick(d.link) return end
    if D.queue and not D.queue.armed then return end
    D:Disarm()
    D.selected[d] = not D.selected[d] or nil
    D:UpdateBar()
    D:ScheduleArm()
  end
  list.onEnter = function(d, r)
    GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(d.link)
    GameTooltip:AddLine(" ")
    if d.kind == "watch" then
      GameTooltip:AddLine(format("|cff66bbffOn your watchlist:|r offers under %s each.", ns.Money(d.watch and d.watch.hit and d.watch.hit.limit or d.sellUnit)), 1, 1, 1, true)
    elseif d.kind == "vendor" then
      GameTooltip:AddLine("|cff66dd88Vendor flip:|r these offers cost less than a vendor pays for the item.", 1, 1, 1, true)
    else
      GameTooltip:AddLine(format("|cffe6cc80Resell:|r market value %s each (median of %d day%s), %s after the 5%% AH cut.",
        ns.Money(d.value), d.days, d.days == 1 and "" or "s", ns.Money(d.sellUnit)), 1, 1, 1, true)
    end
    GameTooltip:AddLine(" ")
    for i, a in ipairs(d.offers) do
      if i > 10 then GameTooltip:AddLine(format("   ... %d more", #d.offers - 10), 0.7, 0.7, 0.7) break end
      GameTooltip:AddDoubleLine(format("   %dx  %s", a.count, a.owner or "?"), ns.Money(a.unit) .. " each", 0.9, 0.9, 0.9, 1, 1, 1)
    end
    GameTooltip:AddDoubleLine("You pay on average", ns.Money(d.buyUnit or 0) .. " each", 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("Listed on the AH", d.listed, 0.7, 0.7, 0.7, 1, 1, 1)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(ns.ACCENT .. "Click|r select   " .. ns.ACCENT .. "Right-click|r open in Browse", 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end
  self.list = list

  -- Bottom bar ----------------------------------------------------------------
  local bar = CreateFrame("Frame", nil, f)
  ns.Size(bar, 920, 50)
  bar:SetPoint("BOTTOMLEFT")
  ns.Skin(bar, C.panel)

  local sel = ns.Text(bar, "BHFontNormal", "")
  sel:SetPoint("TOPLEFT", 12, -9)
  ns.Size(sel, 420, 16)
  self.selText = sel
  local note = ns.Text(bar, "BHFontSmall", "Market values come from your own scans - prices can move. The deposit is refunded when an item sells.")
  note:SetPoint("BOTTOMLEFT", 12, 8)
  ns.Size(note, 520, 14)
  self.note = note

  local all = ns.Button(bar, "Select all", 84, 24)
  all:SetPoint("LEFT", 470, 0)
  all:SetScript("OnClick", function()
    if D.queue and not D.queue.armed then return end
    D:Disarm()
    for _, d in ipairs(D.deals) do D.selected[d] = true end
    D:UpdateBar()
    D:ScheduleArm()
  end)
  local none = ns.Button(bar, "Clear", 60, 24)
  none:SetPoint("LEFT", all, "RIGHT", 4, 0)
  none:SetScript("OnClick", function()
    if D.queue and not D.queue.armed then return end
    D:Disarm()
    wipe(D.selected)
    D:UpdateBar()
  end)

  local stop = ns.Button(bar, "Stop", 50, 34)
  stop:SetPoint("LEFT", none, "RIGHT", 10, 0)
  stop:SetScript("OnClick", function() if D.queue then D.queue:Stop("Buying stopped.") end end)
  self.stopBtn = stop

  local buy = ns.Button(bar, "Buy selected", 206, 34, "gold")
  buy:SetPoint("RIGHT", -8, 0)
  buy:SetScript("OnClick", function() D:OnBuyClick() end)
  self.buyBtn = buy

  self:CreateWatch(f)

  f:SetScript("OnShow", function()
    if not ns.FullScan.groups and ns.FullScan:RemoteInfo() then ns.FullScan:LoadRemote(); D:Refresh() end
    D:UpdateStatus()
    D:ScheduleArm()
  end)
  f:SetScript("OnHide", function()
    D:Disarm()
    if D.queue then D.queue:Stop("Stopped (tab closed).") end
  end)
  ns.panels[#ns.panels + 1] = { StopAll = function() D:Disarm(); if D.queue then D.queue:Stop("Stopped.") end end, entries = {}, Recount = function() end }

  self:UpdateStatus()
  self:UpdateBar()
  return f
end

---------------------------------------------------------------------------
function D:UpdateStatus()
  if ns.FullScan.active then return end
  local remote = ns.FullScan:RemoteInfo()
  local last = ns.FullScan:Info()
  local tip = {}
  if remote then
    self.status:SetText(format("Shared scan from |cff66dd88%s|r, %s", remote.from or "?", ns.TimeAgo(time() - remote.t)))
    tip[1] = "Scan shared by " .. (remote.from or "?")
    tip[2] = format("%s, %d deal candidates", ns.TimeAgo(time() - remote.t), remote.auctions or 0)
  elseif last then
    self.status:SetText(format("Scanned %s: %s items", ns.TimeAgo(time() - last.t), ns.Commas(last.items or 0)))
    tip[1] = "Last full scan"
    tip[2] = format("%s: %s auctions, %s items (%s)", ns.TimeAgo(time() - last.t),
      ns.Commas(last.auctions or 0), ns.Commas(last.items or 0), last.mode == "getall" and "fast" or "page by page")
    if not ns.FullScan.groups then
      tip[#tip + 1] = "Scan again this session to hunt for deals: the offers themselves aren't kept between reloads."
    end
  else
    self.status:SetText("No full scan yet")
    tip[1] = "No full scan yet on this realm and faction"
    tip[2] = "Scan once a day or so: market values get more reliable with every day of history."
  end
  local wait = ns.FullScan:GetAllReadyIn()
  if wait > 0 and ns.db.dealFilters.mode == "getall" then
    tip[#tip + 1] = format("Fast scan available again in %d min (page by page is used until then).", math.ceil(wait / 60))
  end
  self.statusTip = tip
end

function D:StartScan()
  if not ns.atAH then return end
  self:Disarm()
  if self.queue then self.queue:Stop("Stopped.") end
  wipe(self.selected)
  self.scanBtn:SetText("Stop scan")
  self.scanBtn:SetStyle("danger")
  self.prog:SetValue(0)
  ns.FullScan:Start(ns.db.dealFilters.mode,
    function(frac, text)
      D.prog:SetValue(frac)
      D.status:SetText(text)
    end,
    function(aborted, auctions, items)
      D.scanBtn:SetText("Scan whole AH")
      D.scanBtn:SetStyle("accent")
      D.prog:SetValue(aborted and 0 or 1)
      D:Refresh()
      if aborted then
        D.status:SetText(format("Scan stopped after %d auctions (partial results, history not saved).", auctions))
      else
        D:UpdateStatus()
        ns.Print(format("Full scan done: %d auctions, %d items, %d deals.", auctions, items, #D.deals))
      end
    end)
end

-- what is selected right now, so a refresh can tell whether anything changed
function D:SelectionKey()
  local parts = {}
  for d in pairs(self.selected) do parts[#parts + 1] = format("%s:%d:%d", d.name, d.cost, #d.offers) end
  table.sort(parts)
  return table.concat(parts, "|")
end

function D:Refresh()
  if not self.list then return end
  local before = self:SelectionKey()
  local keep = {}
  for d in pairs(self.selected) do keep[d.id] = true end
  wipe(self.selected)
  self.deals = ns.FullScan:Deals(ns.db.dealFilters)
  if ns.Watch then                           -- watched items you asked to be told about
    for _, d in ipairs(ns.Watch:Deals()) do self.deals[#self.deals + 1] = d end
  end
  for _, d in ipairs(self.deals) do
    d.offersN = #d.offers
    d.buyUnit = d.qty > 0 and (d.cost / d.qty) or 0
    if keep[d.id] then self.selected[d] = true end
  end
  self:Sort()
  self:UpdateBar()
  -- don't disturb a purchase that is already being prepared or running
  if self:SelectionKey() ~= before or not self.queue then
    self:Disarm()
    self:ScheduleArm()
  end
end

function D:Sort()
  local key, asc = self.list.sortKey, self.list.sortAsc
  local filter = strlower(strtrim(self.search and self.search:GetText() or ""))
  local shown = self.deals
  if filter ~= "" then
    shown = {}
    for _, d in ipairs(self.deals) do
      if strlower(d.name):find(filter, 1, true) then shown[#shown + 1] = d end
    end
  end
  table.sort(shown, function(a, b)
    local va, vb = a[key], b[key]
    if key == "name" then va, vb = strlower(a.name), strlower(b.name) end
    if va == vb then return a.profit > b.profit end
    if asc then return va < vb end
    return va > vb
  end)
  self.list:SetData(shown, true)
  self.shown = shown
end

function D:Totals()
  local t = { deals = 0, offers = 0, cost = 0, profit = 0 }
  for d in pairs(self.selected) do
    t.deals = t.deals + 1
    t.offers = t.offers + #d.offers
    t.cost = t.cost + d.cost
    t.profit = t.profit + d.profit
  end
  return t
end

function D:UpdateBar()
  if not self.buyBtn then return end
  local q, buy, t = self.queue, self.buyBtn, self:Totals()
  if #self.deals > 0 then
    self.selText:SetText(format("%d deals found   Selected: %d  (cost %s, expected profit %s)",
      #self.deals, t.deals, ns.Money(t.cost, true), ns.Money(t.profit, true)))
  else
    self.selText:SetText("")
  end

  if q and not q.armed then
    if q.waiting then
      buy:SetText(format("Buy %d  %s", q.waitingCount, ns.Money(q.waitingCost)))
      buy:Enable()
    else
      buy:SetText(format("Buying %d / %d ...", math.max(q.i, 1), #q.list))
      buy:Disable()
    end
    self.stopBtn:Enable()
  else
    self.stopBtn:Disable()
    if t.offers == 0 then
      buy:SetText("Buy selected")
      buy:Disable()
    elseif GetMoney() < t.cost then
      buy:SetText("|cffff5555Need|r " .. ns.Money(t.cost))
      buy:Disable()
    elseif q and q.armed then
      if q.waiting then
        buy:SetText(format("Buy %d  %s", q.waitingCount, ns.Money(q.waitingCost)))
        buy:Enable()
      else
        buy:SetText("Loading page...")
        buy:Disable()
      end
    else
      buy:SetText("Buy selected  " .. ns.Money(t.cost))
      buy:Enable()
    end
  end
  self.list:Refresh()
end

---------------------------------------------------------------------------
-- Buying (same engine and protections as everywhere else)
---------------------------------------------------------------------------
function D:Disarm()
  self.armToken = nil
  if self.queue and self.queue.armed then
    self.queue:Cancel()
    self.queue = nil
  end
end

function D:ScheduleArm()
  if not ns.db.clickMode or self.queue or ns.FullScan.active then return end
  local token = {}
  self.armToken = token
  ns.After(0.4, function()
    if D.armToken ~= token or D.queue or ns.FullScan.active or not D.frame:IsVisible() then return end
    local t = D:Totals()
    if t.offers == 0 or GetMoney() < t.cost then return end
    D:BuyAll(true)
  end)
end

function D:OnBuyClick()
  if self.queue then
    self.queue:Confirm()
    return
  end
  local t = self:Totals()
  if t.offers == 0 or ns.FullScan.active then return end
  ns.ConfirmBuy(format("Buy %d offers from %d deals?\n\nCost: %s\nExpected profit: %s", t.offers, t.deals,
    ns.Money(t.cost), ns.Money(t.profit)), function() D:BuyAll() end)
end

function D:BuyAll(armOnly)
  if self.queue or not ns.atAH then return end
  local list = {}
  for d in pairs(self.selected) do
    local cap = { limit = d.qty, placed = 0 }
    local params = d.params or { name = d.name }
    for _, a in ipairs(d.offers) do
      list[#list + 1] = { a = a, params = params, deal = d, cap = cap }
    end
  end
  if #list == 0 then return end
  local q = ns.NewBuyQueue(list, {
    onUpdate = function() D:UpdateBar() end,
    onStarted = function() D:UpdateBar() end,
    onBought = function(_, item)
      local d = item.deal
      d.bought = (d.bought or 0) + item.a.count
    end,
    onFinish = function(queue) D:BuyFinished(queue) end,
    onStop = function(queue, reason) D:BuyFinished(queue, reason) end,
  })
  self.queue = q
  if armOnly then q:Arm() else q:Start() end
end

function D:BuyFinished(q, reason)
  if self.queue ~= q then return end
  self.queue = nil
  -- remove bought / vanished offers from the deals
  local handled = {}
  for _, item in ipairs(q.list) do
    if item.handled then handled[item.a] = true end
  end
  for _, g in pairs(ns.FullScan.groups or {}) do
    for k = #g.auctions, 1, -1 do
      if handled[g.auctions[k]] then table.remove(g.auctions, k) end
    end
  end
  self:Refresh()
  self.status:SetText(format("%sBought %d items for %s. Resell them from the Sell tab.",
    reason and (reason .. "  ") or "", q.bought, ns.Money(q.spent, true)))
end

---------------------------------------------------------------------------
-- Watchlist panel
---------------------------------------------------------------------------
function D:CreateWatch(parent)
  local w = CreateFrame("Frame", nil, parent)
  ns.Size(w, 520, 420)
  w:SetPoint("TOPRIGHT", 0, -40)
  w:SetFrameLevel(parent:GetFrameLevel() + 20)
  w:EnableMouse(true)
  ns.Skin(w, C.bg, C.accent)
  w:Hide()
  self.watchFrame = w

  local title = ns.Text(w, "BHFontLarge", ns.ACCENT .. "Watchlist|r")
  title:SetPoint("TOPLEFT", 12, -10)
  local hint = ns.Text(w, "BHFontSmall", "Watched items are re-checked while the auction house is open. You are told in chat when an offer appears under your price (or under market value), and it shows up in the deals list.")
  hint:SetPoint("TOPLEFT", 12, -32)
  hint:SetWidth(496)
  hint:SetJustifyH("LEFT")

  local close = ns.Button(w, "X", 26, 22)
  close:SetPoint("TOPRIGHT", -10, -10)
  close:SetScript("OnClick", function() w:Hide() end)

  local name = ns.EditBox(w, 220, 24, "Item name (or shift-click it)")
  name:SetPoint("TOPLEFT", 12, -74)
  name.acceptsLinks = "replace"
  name.onEnter = function() D:AddWatch() end
  self.watchName = name

  local pl = ns.Text(w, "BHFontSmall", "Alert under")
  pl:SetPoint("LEFT", name, "RIGHT", 10, 0)
  local price = ns.MoneyInput(w)
  price:SetPoint("LEFT", pl, "RIGHT", 6, 0)
  self.watchPrice = price

  local add = ns.Button(w, "Watch", 70, 24, "accent")
  add:SetPoint("TOPLEFT", 12, -104)
  add:SetScript("OnClick", function() D:AddWatch() end)

  local remove = ns.Button(w, "Remove", 70, 24, "danger")
  remove:SetPoint("LEFT", add, "RIGHT", 6, 0)
  remove:SetScript("OnClick", function()
    if D.watchSelected then
      ns.Watch:Remove(D.watchSelected)
      D.watchSelected = nil
      D:RefreshWatch()
      D:Refresh()
    end
  end)
  self.watchRemove = remove

  local enabled = ns.Check(w, "Keep checking", function(_, on)
    ns.db.watchEnabled = on
    ns.Watch:Kick()
  end)
  enabled:SetPoint("LEFT", remove, "RIGHT", 16, 0)
  enabled:SetChecked(ns.db.watchEnabled ~= false)

  local el = ns.Text(w, "BHFontSmall", "Check every")
  el:SetPoint("LEFT", enabled.label, "RIGHT", 16, 0)
  local every = ns.Dropdown(w, 96, 24, function(v)
    ns.db.watchInterval = v
    ns.Watch:Kick()
    D:RefreshWatch()
  end)
  every:SetPoint("LEFT", el, "RIGHT", 6, 0)
  every:SetItems({
    { value = 5, text = "5 seconds" },
    { value = 10, text = "10 seconds" },
    { value = 15, text = "15 seconds" },
    { value = 30, text = "30 seconds" },
    { value = 60, text = "1 minute" },
    { value = 120, text = "2 minutes" },
    { value = 300, text = "5 minutes" },
  })
  every:SetValue(ns.Watch:Interval(), true)
  every.tooltip = "Time between two checks. One item is checked each time, so with several watched items each one comes round after interval x number of items."
  self.watchEvery = every

  local cols = {
    { text = "Item", w = 170, key = "name" },
    { text = "Alert under", w = 100, key = "maxUnit", j = "RIGHT" },
    { text = "Cheapest now", w = 100, key = "best", j = "RIGHT" },
    { text = "Status", w = 92, key = "state", font = "BHFontSmall" },
  }
  local list = ns.List(w, "BargainHouseWatchList", 496, 256, 22, cols, true)
  list:SetPoint("TOPLEFT", 12, -136)
  list.emptyText = "Nothing watched yet. Add an item above; shift-clicking an item puts its name in the box."
  list.update = function(r, item)
    r.icon:SetTexture(item.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    r.cols[1]:SetText((item.quality and ns.QualityHex(item.quality) or "|cffdddddd") .. item.name .. "|r")
    r.cols[2]:SetText(item.maxUnit and ns.Money(item.maxUnit) or "|cff888888market value|r")
    r.cols[3]:SetText(item.best and ns.Money(item.best) or "|cff555555--|r")
    if item.hit then r.cols[4]:SetText("|cff66dd88deal now|r")
    elseif item.checked then r.cols[4]:SetText("|cff888888checked " .. ns.TimeAgo(time() - item.checked) .. "|r")
    else r.cols[4]:SetText("|cff888888waiting|r") end
  end
  list.onClick = function(item, button)
    if button == "RightButton" and item.link then HandleModifiedItemClick(item.link) return end
    D.watchSelected = item
    list.selected = item
    list:Refresh()
    ns.Enable(D.watchRemove, true)
    D.watchPrice:SetCopper(item.maxUnit or 0)
  end
  list.onEnter = function(item, r)
    if not item.link then return end
    GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(item.link)
    GameTooltip:Show()
  end
  self.watchList = list

  local note = ns.Text(w, "BHFontSmall", "")
  note:SetPoint("BOTTOMLEFT", 12, 10)
  ns.Size(note, 496, 14)
  self.watchNote = note

  w:SetScript("OnShow", function() D:RefreshWatch() end)
  local acc = 0
  w:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc > 2 then acc = 0; D:RefreshWatch() end
  end)
  ns.Enable(remove, false)
end

function D:AddWatch()
  local ok, err = ns.Watch:Add(self.watchName:GetText(), self.watchPrice:GetCopper())
  if ok then
    self.watchName:SetTextSilent("")
    self.watchPrice:SetCopper(0)
    self.watchName:ClearFocus()
  elseif err then
    self.watchNote:SetText("|cffff5555" .. err .. "|r")
  end
  self:RefreshWatch()
end

function D:RefreshWatch()
  if not self.watchList then return end
  local list = ns.Watch and ns.Watch:List() or {}
  self.watchList.selected = self.watchSelected
  self.watchList:SetData(list, true)
  ns.Enable(self.watchRemove, self.watchSelected ~= nil)
  local hits = 0
  for _, item in ipairs(list) do
    if item.hit then hits = hits + 1 end
  end
  if not ns.atAH then
    self.watchNote:SetText("|cff888888Checking happens at an auctioneer.|r")
  elseif ns.db.watchEnabled == false then
    self.watchNote:SetText("|cffffaa33Checking is off.|r")
  elseif #list == 0 then
    self.watchNote:SetText("")
  else
    local every, cycle = ns.Watch:Interval(), ns.Watch:CycleTime()
    local cycleText = cycle >= 60 and format("%d min %02d s", floor(cycle / 60), cycle % 60) or format("%d s", cycle)
    self.watchNote:SetText(format("%d watched, %d with a deal right now. One item every %d s, so each item about every %s - only while nothing else is scanning or buying.",
      #list, hits, every, cycleText))
  end
end
