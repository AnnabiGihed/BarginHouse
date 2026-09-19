local ADDON, ns = ...
local C = ns.C
local format, floor = string.format, math.floor

local B = { results = {}, groups = {} }
ns.Browse = B

local MODES = {
  { value = "CONTAINS", text = "Contains" },
  { value = "EXACT",    text = "Exact name" },
  { value = "STARTS",   text = "Starts with" },
  { value = "ENDS",     text = "Ends with" },
  { value = "WORDS",    text = "All words" },
  { value = "WILDCARD", text = "Wildcard  * ?" },
}
ns.MODE_TEXT = {}
for _, m in ipairs(MODES) do ns.MODE_TEXT[m.value] = m.text end

---------------------------------------------------------------------------
-- Sorting
---------------------------------------------------------------------------
local BIG = 2 ^ 52

local function GroupSorter(key, asc)
  return function(a, b)
    local va, vb
    if key == "name" then va, vb = a.name, b.name
    elseif key == "unit" then va, vb = a.unit or BIG, b.unit or BIG
    elseif key == "pct" then va, vb = a.pct or BIG, b.pct or BIG
    else va, vb = a[key] or 0, b[key] or 0 end
    if va == vb then return a.name < b.name end
    if asc then return va < vb end
    return va > vb
  end
end

local function AuctionSorter(key, asc)
  return function(a, b)
    if key == "unit" or key == "buyout" then
      local ha, hb = a.buyout > 0, b.buyout > 0
      if ha ~= hb then return ha end -- bid-only always last
    end
    local va, vb
    if key == "owner" then va, vb = a.owner or "", b.owner or ""
    elseif key == "unit" then va, vb = a.unit or BIG, b.unit or BIG
    else va, vb = a[key] or 0, b[key] or 0 end
    if va == vb then
      if a.count ~= b.count then return a.count < b.count end
      return (a.timeLeft or 0) < (b.timeLeft or 0)
    end
    if asc then return va < vb end
    return va > vb
  end
end

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------
function B:Create(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  self.frame = f

  -- Row 1: search ---------------------------------------------------------
  local search = ns.EditBox(f, 230, 26, "Search items...  (Enter)")
  search:SetPoint("TOPLEFT", 0, 0)
  search.onEnter = function() B:DoSearch() end
  search.onChange = function() B:UpdateFavButton() end
  search.acceptsLinks = "replace"
  self.search = search

  local mode = ns.Dropdown(f, 118, 26, function(v)
    ns.db.searchMode = v
    B:SaveFilters()
    B:UpdateFavButton()
  end)
  mode:SetPoint("LEFT", search, "RIGHT", 6, 0)
  mode:SetItems(MODES)
  mode:SetValue(ns.db.searchMode, true)
  mode.tooltip = "How the name is matched.\nWildcard: * = anything, ? = one character (e.g. frost*cloth)"
  self.mode = mode

  local cat = ns.Dropdown(f, 132, 26, function() B:UpdateSubclasses() B:SaveFilters() end)
  cat:SetPoint("LEFT", mode, "RIGHT", 6, 0)
  local catItems = { { value = 0, text = "All categories" } }
  for i, name in ipairs({ GetAuctionItemClasses() }) do
    catItems[#catItems + 1] = { value = i, text = name }
  end
  cat:SetItems(catItems)
  cat:SetValue(0, true)
  self.cat = cat

  local sub = ns.Dropdown(f, 132, 26, function() B:SaveFilters() end)
  sub:SetPoint("LEFT", cat, "RIGHT", 6, 0)
  self.sub = sub
  self:UpdateSubclasses()

  local go = ns.Button(f, "Search", 100, 26, "accent")
  go:SetPoint("LEFT", sub, "RIGHT", 6, 0)
  go:SetScript("OnClick", function()
    if B.scanning then ns.Scanner:Stop() else B:DoSearch() end
  end)
  self.go = go

  local saved = ns.Button(f, "Saved", 76, 26)
  saved:SetPoint("LEFT", go, "RIGHT", 6, 0)
  saved.tooltip = "Favorite and recent searches"
  saved:SetScript("OnClick", function(btn) B:OpenSaved(btn) end)

  local fav = ns.Button(f, "+ Fav", 58, 26)
  fav:SetPoint("LEFT", saved, "RIGHT", 6, 0)
  fav.tooltip = "Save the current search (text + mode) as a favorite"
  fav:SetScript("OnClick", function()
    ns.ToggleFavorite(strtrim(B.search:GetText()), B.mode.value)
    B:UpdateFavButton()
  end)
  self.fav = fav

  -- Row 2: filters --------------------------------------------------------
  local lvl = ns.Text(f, "BHFontSmall", "Level")
  lvl:SetPoint("TOPLEFT", 0, -38)
  local minL = ns.EditBox(f, 34, 22, nil, true)
  minL:SetPoint("TOPLEFT", 36, -34)
  minL:SetMaxLetters(2)
  local maxL = ns.EditBox(f, 34, 22, nil, true)
  maxL:SetPoint("LEFT", minL, "RIGHT", 12, 0)
  maxL:SetMaxLetters(2)
  local dash = ns.Text(f, "BHFontSmall", "-")
  dash:SetPoint("LEFT", minL, "RIGHT", 3, 0)
  minL.onEnter, maxL.onEnter = search.onEnter, search.onEnter
  minL.onChange = function() B:SaveFilters() end
  maxL.onChange = function() B:SaveFilters() end
  minL.nextBox, maxL.nextBox = maxL, search
  self.minL, self.maxL = minL, maxL

  local rarity = ns.Dropdown(f, 112, 22, function() B:SaveFilters() end)
  rarity:SetPoint("LEFT", maxL, "RIGHT", 12, 0)
  local rItems = { { value = -1, text = "Any rarity" } }
  for q = 0, 5 do
    rItems[#rItems + 1] = { value = q, text = ns.QualityHex(q) .. (_G["ITEM_QUALITY" .. q .. "_DESC"] or q) .. "|r+" }
  end
  rarity:SetItems(rItems)
  rarity:SetValue(-1, true)
  self.rarity = rarity

  local maxLabel = ns.Text(f, "BHFontSmall", "Max / unit")
  maxLabel:SetPoint("LEFT", rarity, "RIGHT", 12, 0)
  local maxPrice = ns.MoneyInput(f, function() B:BuildGroups() B:SaveFilters() end)
  maxPrice:SetPoint("LEFT", maxLabel, "RIGHT", 6, 0)
  self.maxPrice = maxPrice

  local usable = ns.Check(f, "Usable", function() B:SaveFilters() end)
  usable:SetPoint("LEFT", maxPrice, "RIGHT", 14, 0)
  usable.tooltip = "Only items your character can use (applies on next search)"
  self.usable = usable

  local hideBid = ns.Check(f, "Hide bid-only", function(_, on)
    ns.db.hideBidOnly = on
    B:BuildGroups()
    B:SaveFilters()
  end)
  hideBid:SetPoint("LEFT", usable.label, "RIGHT", 14, 0)
  hideBid:SetChecked(ns.db.hideBidOnly)
  self.hideBid = hideBid

  local deals = ns.Check(f, "Deals only", function() B:BuildGroups() B:SaveFilters() end)
  deals:SetPoint("LEFT", hideBid.label, "RIGHT", 14, 0)
  deals.tooltip = "Only show items currently listed below their recorded average price"
  self.deals = deals

  -- Result lists ---------------------------------------------------------
  local gcols = {
    { text = "Item", w = 172, key = "name" },
    { text = "Lvl", w = 26, key = "level", j = "RIGHT" },
    { text = "Qty", w = 44, key = "qty", j = "RIGHT" },
    { text = "#", w = 30, key = "num", j = "RIGHT" },
    { text = "Lowest / unit", w = 110, key = "unit", j = "RIGHT" },
    { text = "vs avg", w = 48, key = "pct", j = "RIGHT" },
  }
  local groups = ns.List(f, "BargainHouseGroupList", 520, 432, 22, gcols, true)
  groups:SetPoint("TOPLEFT", 0, -64)
  groups.emptyText = "Search for an item to see the cheapest offers.\n\nTip: pick a category and leave the name empty to browse it."
  groups.sortKey, groups.sortAsc = "unit", true
  groups.onSort = function(key)
    if groups.sortKey == key then groups.sortAsc = not groups.sortAsc
    else groups.sortKey, groups.sortAsc = key, not (key == "qty" or key == "num" or key == "level") end
    B:SortGroups()
  end
  groups.update = function(r, g)
    r.icon:SetTexture(g.texture)
    r.cols[1]:SetText(ns.QualityHex(g.quality) .. g.name .. "|r")
    r.cols[2]:SetText(g.level > 0 and g.level or "")
    r.cols[3]:SetText(g.qty)
    r.cols[4]:SetText(g.num)
    r.cols[5]:SetText(g.unit and ns.Money(g.unit) or "|cff888888bid only|r")
    local pct = g.pct
    if not pct then r.cols[6]:SetText("|cff555555--|r")
    elseif pct <= 80 then r.cols[6]:SetText("|cff33ff66" .. pct .. "%|r")
    elseif pct < 100 then r.cols[6]:SetText("|cffa8e6a0" .. pct .. "%|r")
    elseif pct <= 120 then r.cols[6]:SetText("|cffdddddd" .. pct .. "%|r")
    else r.cols[6]:SetText("|cffff6655" .. pct .. "%|r") end
  end
  groups.onClick = function(g, button)
    if button == "LeftButton" and IsModifiedClick() then
      HandleModifiedItemClick(g.link)
    elseif button == "RightButton" then
      B.search:SetTextSilent(g.name)
      B.mode:SetValue("EXACT")
      B:DoSearch()
    else
      B:SelectGroup(g)
    end
  end
  groups.onEnter = function(g, r)
    GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(g.link)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(ns.ACCENT .. "Click|r view offers   " .. ns.ACCENT .. "Right-click|r exact search", 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end
  self.groupList = groups

  local acols = {
    { text = "Qty", w = 34, key = "count", j = "RIGHT" },
    { text = "Per unit", w = 104, key = "unit", j = "RIGHT" },
    { text = "Buyout", w = 104, key = "buyout", j = "RIGHT" },
    { text = "Time", w = 34, key = "timeLeft", j = "CENTER" },
    { text = "Seller", w = 62, key = "owner" },
  }
  local auctions = ns.List(f, "BargainHouseAuctionList", 392, 432, 22, acols)
  auctions:SetPoint("TOPLEFT", groups, "TOPRIGHT", 8, 0)
  auctions.emptyText = "Select an item on the left to see every offer,\ncheapest first."
  auctions.sortKey, auctions.sortAsc = "unit", true
  auctions.onSort = function(key)
    if auctions.sortKey == key then auctions.sortAsc = not auctions.sortAsc
    else auctions.sortKey, auctions.sortAsc = key, key ~= "count" end
    B:SortAuctions()
  end
  auctions.update = function(r, a)
    r.cols[1]:SetText(a.count)
    if a.buyout > 0 then
      r.cols[2]:SetText(ns.Money(a.unit))
      r.cols[3]:SetText(ns.Money(a.buyout))
    else
      r.cols[2]:SetText("|cff888888bid only|r")
      r.cols[3]:SetText(ns.Money(a.bid > 0 and a.bid or a.minBid))
    end
    r.cols[4]:SetText(ns.TIME_LEFT[a.timeLeft] or "?")
    if a.owner and a.owner == ns.Me() then r.cols[5]:SetText(ns.ACCENT .. "You|r")
    else r.cols[5]:SetText(a.owner or "|cff777777?|r") end
  end
  auctions.onClick = function(a, button)
    if button == "LeftButton" and IsModifiedClick() then
      HandleModifiedItemClick(a.link)
    else
      if B.queue then return end
      if B.plan then B.qty:SetTextSilent(""); B:Replan() end
      B:SelectAuction(a)
    end
  end
  auctions.onEnter = function(a, r)
    GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(a.link)
    GameTooltip:AddLine(" ")
    if a.buyout > 0 then
      GameTooltip:AddDoubleLine("Buyout (" .. a.count .. ")", ns.Money(a.buyout), 0.8, 0.8, 0.8, 1, 1, 1)
      GameTooltip:AddDoubleLine("Per unit", ns.Money(a.unit), 0.8, 0.8, 0.8, 1, 1, 1)
    end
    GameTooltip:AddDoubleLine(a.bid > 0 and "Current bid" or "Starting bid", ns.Money(a.bid > 0 and a.bid or a.minBid), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:Show()
  end
  self.auctionList = auctions

  -- Bottom bar ------------------------------------------------------------
  local bar = CreateFrame("Frame", nil, f)
  ns.Size(bar, 920, 44)
  bar:SetPoint("TOPLEFT", 0, -502)
  ns.Skin(bar, C.panel)

  local status = ns.Text(bar, "BHFontSmall", "Ready.")
  status:SetPoint("TOPLEFT", 10, -9)
  ns.Size(status, 230, 14)
  self.status = status

  local prog = ns.Progress(bar, 230, 4)
  prog:SetPoint("BOTTOMLEFT", 10, 11)
  self.prog = prog

  local qtyLabel = ns.Text(bar, "BHFontSmall", "Quantity to buy")
  qtyLabel:SetPoint("TOPLEFT", 252, -3)
  local qty = ns.EditBox(bar, 84, 20, "any", true)
  qty:SetPoint("BOTTOMLEFT", 252, 4)
  qty:SetMaxLetters(5)
  qty.onChange = function()
    B:Replan()
    if not B.plan and not B.queue and B.selAuction and not B.scanning then B:PrepareBuy(B.selAuction) end
  end
  qty:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("How many items you need", 1, 1, 1)
    GameTooltip:AddLine("The cheapest combination of stacks is picked and highlighted; Buy purchases all of them. Leave empty to buy a single offer.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  qty:SetScript("OnLeave", function() GameTooltip:Hide() end)
  self.qty = qty

  local selIcon = bar:CreateTexture(nil, "ARTWORK")
  ns.Size(selIcon, 32, 32)
  selIcon:SetPoint("LEFT", 348, 0)
  selIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  self.selIcon = selIcon

  local selName = ns.Text(bar, "BHFontNormal", "")
  selName:SetPoint("TOPLEFT", selIcon, "TOPRIGHT", 8, 1)
  ns.Size(selName, 262, 16)
  self.selName = selName

  local selInfo = ns.Text(bar, "BHFontSmall", "")
  selInfo:SetPoint("BOTTOMLEFT", selIcon, "BOTTOMRIGHT", 8, -1)
  ns.Size(selInfo, 262, 14)
  self.selInfo = selInfo

  local buy = ns.Button(bar, "Buy", 206, 32, "gold")
  buy:SetPoint("RIGHT", -6, 0)
  buy:SetScript("OnClick", function() B:OnBuyClick() end)
  self.buyBtn = buy

  local bid = ns.Button(bar, "Bid", 50, 32)
  bid:SetPoint("RIGHT", buy, "LEFT", -6, 0)
  bid.tooltip = "Place the minimum bid on the selected offer (Stop while buying a quantity)"
  bid:SetScript("OnClick", function()
    if B.queue then B:QueueStop("Buying stopped.") else B:Buy(true) end
  end)
  self.bidBtn = bid

  f:SetScript("OnShow", function()
    B:LoadFilters()
    B:Replan()
  end)
  f:SetScript("OnHide", function()
    B:Disarm()
    if B.queue then B:QueueStop("Stopped (tab closed).") end
  end)

  self:LoadFilters()
  self:UpdateFavButton()
  self:UpdateBuyBar()
  groups:SetData(self.groups)
  auctions:SetData({})
  return f
end

-- the search row is remembered between sessions
function B:SaveFilters()
  if self.loadingFilters or not self.mode then return end
  ns.db.browse = {
    mode = self.mode.value,
    cat = self.cat.value,
    sub = self.sub.value,
    rarity = self.rarity.value,
    minLevel = self.minL:GetText(),
    maxLevel = self.maxL:GetText(),
    usable = self.usable:GetChecked() and true or false,
    deals = self.deals:GetChecked() and true or false,
    maxPrice = self.maxPrice:GetCopper(),
  }
  ns.db.searchMode = self.mode.value
end

function B:LoadFilters()
  if not self.mode then return end
  local f = ns.db.browse or {}
  self.loadingFilters = true
  self.mode:SetValue(f.mode or ns.db.searchMode or "CONTAINS", true)
  self.cat:SetValue(f.cat or 0, true)
  self:UpdateSubclasses()
  if f.sub and f.sub > 0 then self.sub:SetValue(f.sub, true) end
  self.rarity:SetValue(f.rarity or -1, true)
  self.minL:SetTextSilent(f.minLevel or "")
  self.maxL:SetTextSilent(f.maxLevel or "")
  self.usable:SetChecked(f.usable)
  self.deals:SetChecked(f.deals)
  self.hideBid:SetChecked(ns.db.hideBidOnly)
  self.maxPrice:SetCopper(f.maxPrice or 0)
  self.loadingFilters = false
  self:UpdateFavButton()
end

function B:SetStatus(text)
  self.status:SetText(text)
end

function B:UpdateSubclasses()
  local items = { { value = 0, text = "All subcategories" } }
  local c = self.cat.value or 0
  if c > 0 then
    for i, name in ipairs({ GetAuctionItemSubClasses(c) }) do
      items[#items + 1] = { value = i, text = name }
    end
  end
  self.sub:SetItems(items)
  self.sub:SetValue(0, true)
  ns.Enable(self.sub, #items > 1)
end

function B:UpdateFavButton()
  local text = strtrim(self.search:GetText() or "")
  if text ~= "" and ns.IsFavorite(text, self.mode.value) then
    self.fav:SetText("- Fav")
  else
    self.fav:SetText("+ Fav")
  end
  ns.Enable(self.fav, text ~= "")
end

function B:OpenSaved(owner)
  local items = {}
  local favs, hist = ns.db.favorites, ns.db.history
  if #favs > 0 then
    items[#items + 1] = { text = "Favorites  (right-click removes)", disabled = true }
    for _, v in ipairs(favs) do
      items[#items + 1] = { text = "  |cffffd100" .. v.t .. "|r  |cff777777" .. (ns.MODE_TEXT[v.m] or "") .. "|r", value = v, fav = true }
    end
  end
  if #hist > 0 then
    items[#items + 1] = { text = "Recent searches", disabled = true }
    for _, v in ipairs(hist) do
      items[#items + 1] = { text = "  " .. v.t .. "  |cff777777" .. (ns.MODE_TEXT[v.m] or "") .. "|r", value = v }
    end
  end
  if #items == 0 then
    items[1] = { text = "No saved searches yet", disabled = true }
  end
  ns.OpenMenu(owner, items, function(v, button, it)
    if it.fav and button == "RightButton" then
      ns.ToggleFavorite(v.t, v.m)
      B:UpdateFavButton()
      return
    end
    B.search:SetTextSilent(v.t)
    B.mode:SetValue(v.m or "CONTAINS", true)
    B:DoSearch()
  end, nil, 300)
end

---------------------------------------------------------------------------
-- Searching
---------------------------------------------------------------------------
function B:SetScanning(on)
  self.scanning = on
  if on then
    self.go:SetText("Stop")
    self.go:SetStyle("danger")
  else
    self.go:SetText("Search")
    self.go:SetStyle("accent")
  end
  self:UpdateBuyBar()
end

function B:DoSearch()
  if not ns.atAH then return end
  local text = strtrim(self.search:GetText() or "")
  local mode = self.mode.value or "CONTAINS"
  local serverName, matcher = ns.BuildMatcher(text, mode)
  local cat, sub = self.cat.value or 0, self.sub.value or 0

  local params = {
    name = serverName,
    minLevel = tonumber(self.minL:GetText()),
    maxLevel = tonumber(self.maxL:GetText()),
    class = cat > 0 and cat or nil,
    subclass = (cat > 0 and sub > 0) and sub or nil,
    usable = self.usable:GetChecked() and true or false,
    quality = self.rarity.value or -1,
  }

  ns.AddHistory(text, mode)
  self.search:ClearFocus()
  ns.CloseMenu()

  self:Disarm()
  if self.queue then self:QueueStop() end
  local results = {}
  self.results = results
  self.lastParams = params
  self.selGroup = nil
  self.groups = {}
  self:SelectAuction(nil)
  self.groupList.selected = nil
  self.groupList:SetData(self.groups)
  self.auctionList:SetData({})
  self.prog:SetValue(0)
  self:SetStatus("Searching...")

  local maxPages = ns.db.maxPages
  local lastTotal = 1
  self:SetScanning(true)

  ns.Scanner:Start({
    params = params,
    page = 0,
    maxPages = maxPages,
    onPage = function(entries, page, totalPages, total)
      if B.results ~= results then return false end
      for _, e in ipairs(entries) do
        if matcher(e.name) then results[#results + 1] = e end
      end
      lastTotal = totalPages
      local pages = math.min(totalPages, maxPages)
      B:SetStatus(format("Scanning page %d of %d  (%d auctions)", page + 1, pages, total))
      B.prog:SetValue((page + 1) / pages)
      B:BuildGroups()
    end,
    onDone = function(aborted)
      if B.results ~= results then return end
      B:SetScanning(false)
      B.prog:SetValue(1)

      -- record lowest unit price per item
      local lows = {}
      for _, e in ipairs(results) do
        if e.buyout > 0 and e.id then
          local u = e.buyout / e.count
          if not lows[e.id] or u < lows[e.id] then lows[e.id] = u end
        end
      end
      for id, u in pairs(lows) do ns.RecordPrice(id, u) end

      B:BuildGroups()
      local msg = format("%d items in %d offers", #B.groups, #results)
      if aborted then msg = "Stopped - " .. msg
      elseif lastTotal > maxPages then msg = msg .. "  |cffffaa33(page limit - refine search)|r" end
      if #results == 0 and not aborted then msg = "No matching auctions found." end
      B:SetStatus(msg)
      if B.selAuction and not B.plan then B:PrepareBuy(B.selAuction) end
    end,
  })
end

function B:BuildGroups()
  local hideBid = ns.db.hideBidOnly
  local maxUnit = self.maxPrice:GetCopper()
  local dealsOnly = self.deals:GetChecked()
  local map, list = {}, {}

  for _, e in ipairs(self.results) do
    e.unit = e.buyout > 0 and (e.buyout / e.count) or nil
    local ok = not (hideBid and not e.unit)
    if ok and maxUnit > 0 and not (e.unit and e.unit <= maxUnit) then ok = false end
    if ok then
      local g = map[e.name]
      if not g then
        g = { name = e.name, link = e.link, id = e.id, texture = e.texture, quality = e.quality,
              level = e.level, auctions = {}, qty = 0 }
        map[e.name] = g
        list[#list + 1] = g
      end
      g.auctions[#g.auctions + 1] = e
      g.qty = g.qty + e.count
      if e.unit and (not g.unit or e.unit < g.unit) then g.unit = e.unit end
    end
  end

  local groups = {}
  for _, g in ipairs(list) do
    g.num = #g.auctions
    local p = g.id and ns.db.prices[g.id]
    g.avg = p and p.n > 1 and p.a or nil
    g.pct = (g.unit and g.avg and g.avg > 0) and floor(g.unit / g.avg * 100 + 0.5) or nil
    if not dealsOnly or (g.pct and g.pct < 100) then
      groups[#groups + 1] = g
    end
  end
  self.groups = groups

  -- keep the selected group across rebuilds
  local selName = self.selGroup and self.selGroup.name
  self.selGroup = nil
  if selName then
    for _, g in ipairs(groups) do
      if g.name == selName then self.selGroup = g break end
    end
  end
  if self.selAuction then
    local found = false
    if self.selGroup then
      for _, a in ipairs(self.selGroup.auctions) do
        if a == self.selAuction then found = true break end
      end
    end
    if not found then self:SelectAuction(nil) end
  end

  self:SortGroups()
  self:SortAuctions()
  self:Replan()
end

function B:SortGroups()
  local l = self.groupList
  table.sort(self.groups, GroupSorter(l.sortKey, l.sortAsc))
  l.selected = self.selGroup
  l:SetData(self.groups, true)
end

function B:SortAuctions()
  local l = self.auctionList
  local g = self.selGroup
  if g then
    table.sort(g.auctions, AuctionSorter(l.sortKey, l.sortAsc))
    l:SetData(g.auctions, true)
  else
    l:SetData({}, true)
  end
end

function B:SelectGroup(g, noPrepare)
  self.selGroup = g
  self.groupList.selected = g
  self.groupList:Refresh()
  if not g then
    self.auctionList:SetData({})
    self:SelectAuction(nil)
    return
  end
  table.sort(g.auctions, AuctionSorter(self.auctionList.sortKey, self.auctionList.sortAsc))
  self.auctionList:SetData(g.auctions)
  local best
  for _, a in ipairs(g.auctions) do
    if a.unit and (not best or a.unit < best.unit) then best = a end
  end
  self:SelectAuction(best or g.auctions[1], noPrepare)
end

function B:RemoveAuction(a)
  for i = #self.results, 1, -1 do
    if self.results[i] == a then table.remove(self.results, i) break end
  end
  if self.selAuction == a then
    self.selAuction = nil
    self.auctionList.selected = nil
  end
  self:BuildGroups()
end

---------------------------------------------------------------------------
-- Buying
---------------------------------------------------------------------------
function B:SelectAuction(a, noPrepare)
  self.selAuction = a
  self.buyState = nil
  self.auctionList.selected = a
  self.auctionList:Refresh()
  self:UpdateBuyBar()
  if a and not self.scanning and not noPrepare and not self.plan and not self.queue then
    self:PrepareBuy(a)
  end
end

---------------------------------------------------------------------------
-- Quantity plan
---------------------------------------------------------------------------
function B:Disarm()
  self.armToken = nil
  if self.queue and self.queue.armed then
    self.queue:Cancel()
    self.queue = nil
  end
end

-- Page mode: load the first page of the plan in the background so the very
-- first click on Buy purchases.
function B:ScheduleArm()
  if not (ns.db.clickMode and self.plan and #self.plan.auctions > 0) then return end
  local token = {}
  self.armToken = token
  ns.After(0.4, function()
    if B.armToken ~= token or B.queue or B.scanning or not B.plan or not B.frame:IsVisible() then return end
    if GetMoney() < B.plan.cost then return end
    B:StartQueue(true)
  end)
end

function B:Replan()
  if not self.qty then return end
  if self.queue and not self.queue.armed then return end
  self:Disarm()
  local need = tonumber(self.qty:GetText()) or 0
  local g = self.selGroup
  self.plan = nil
  local marked
  if need > 0 and g then
    self.plan = ns.PlanPurchase(g.auctions, need, ns.Me())
    marked = {}
    for _, a in ipairs(self.plan.auctions) do marked[a] = true end
  end
  self.auctionList.marked = marked
  self.auctionList:Refresh()
  self:UpdateBuyBar()
  self:ScheduleArm()
end

---------------------------------------------------------------------------
-- Bottom bar
---------------------------------------------------------------------------
function B:UpdateBuyBar()
  if not self.buyBtn then return end
  local buy, bid, q, plan, g = self.buyBtn, self.bidBtn, self.queue, self.plan, self.selGroup

  -- buying a quantity right now
  if q and not q.armed then
    local first = q.list[1] and q.list[1].a
    self.selIcon:SetTexture(first and first.texture)
    self.selName:SetText(format("Buying %s%s|r", ns.QualityHex(first and first.quality), first and first.name or ""))
    self.selInfo:SetText(format("Got %d / %d   Spent %s", q.bought, q.need, ns.Money(q.spent, true)))
    if q.waiting then
      buy:SetText(format("Buy %d  %s", q.waitingCount, ns.Money(q.waitingCost)))
      buy:Enable()
      self:SetStatus(ns.ACCENT .. format("Click Buy: %d offer%s on this page|r", q.waitingCount, q.waitingCount == 1 and "" or "s"))
    elseif ns.pendingBid and ns.pendingBid.q == q then
      buy:SetText("Waiting for server...")
      buy:Disable()
    else
      buy:SetText(format("Finding %d / %d ...", math.max(q.i, 1), #q.list))
      buy:Disable()
    end
    bid:SetText("Stop")
    bid:Enable()
    return
  end
  bid:SetText("Bid")

  -- quantity mode: show the cheapest combination and its total
  if plan and g then
    self.selIcon:SetTexture(g.texture)
    local n = #plan.auctions
    if n == 0 then
      self.selName:SetText(ns.QualityHex(g.quality) .. g.name .. "|r")
      self.selInfo:SetText("|cffff5555No buyout offers from other sellers|r")
      buy:SetText("Nothing to buy")
      buy:Disable()
      bid:Disable()
      return
    end
    local extra = plan.count - plan.need
    local name = format("%s%s|r  |cffaaaaaax%d|r", ns.QualityHex(g.quality), g.name, plan.count)
    if extra > 0 then name = name .. format("  |cff888888(+%d extra)|r", extra) end
    self.selName:SetText(name)
    local info = format("%d offer%s   avg %s each", n, n == 1 and "" or "s", ns.Money(plan.cost / plan.count))
    if plan.short then info = format("|cffffaa33Only %d available|r   ", plan.count) .. info end
    local vendorUnit = ns.VendorPrice(g.id)
    if vendorUnit and plan.cost / plan.count > vendorUnit then
      info = "|cffff5555Vendors sell this for " .. ns.Money(vendorUnit) .. " each|r"
    elseif not vendorUnit and ns.IsVendorItem(g.id, g.name) then
      info = "|cffffaa33Usually sold by vendors - compare first|r   " .. info
    end
    self.selInfo:SetText(info)
    buy:SetText("Buy  " .. ns.Money(plan.cost))
    if q and q.armed then
      if q.waiting then
        buy:SetText(format("Buy %d  %s", q.waitingCount, ns.Money(q.waitingCost)))
        buy:Enable()
        if q.waitingCount < #q.list then
          self:SetStatus(ns.ACCENT .. format("%d of %d offers on this page|r", q.waitingCount, #q.list))
        end
      else
        buy:SetText("Loading page...")
        buy:Disable()
      end
    elseif self.scanning then
      buy:SetText("Scanning...")
      buy:Disable()
    elseif GetMoney() < plan.cost then
      buy:SetText("|cffff5555Need|r " .. ns.Money(plan.cost))
      buy:Disable()
    else
      buy:Enable()
    end
    bid:Disable()
    return
  end

  -- single offer mode
  local a = self.selAuction
  if not a then
    self.selIcon:SetTexture(nil)
    self.selName:SetText("")
    self.selInfo:SetText("")
    buy:SetText("Select an offer")
    buy:Disable()
    bid:Disable()
    return
  end

  self.selIcon:SetTexture(a.texture)
  self.selName:SetText(format("%s%s|r  |cffaaaaaax%d|r", ns.QualityHex(a.quality), a.name, a.count))
  local vendorUnit = ns.VendorPrice(a.id)
  if a.unit and vendorUnit and a.unit > vendorUnit then
    self.selInfo:SetText(ns.Money(a.unit) .. " each   |cffff5555Vendors sell it for " .. ns.Money(vendorUnit) .. "|r")
  elseif a.unit then
    self.selInfo:SetText(ns.Money(a.unit) .. " each   Seller: " .. (a.owner or "?"))
  else
    self.selInfo:SetText("Bid only   Next bid: " .. ns.Money(a.bid > 0 and (a.bid + a.minInc) or a.minBid))
  end

  local st, mine = self.buyState, (a.owner and a.owner == ns.Me())
  if self.scanning then
    buy:SetText("Scanning...")
    buy:Disable()
  elseif mine then
    buy:SetText("Your auction")
    buy:Disable()
  elseif st == "LOCATING" then
    buy:SetText("Locating...")
    buy:Disable()
  elseif st == "NOTFOUND" then
    buy:SetText("Offer is gone")
    buy:Disable()
  elseif a.buyout <= 0 then
    buy:SetText("No buyout")
    buy:Disable()
  elseif st == "READY" then
    buy:SetText("Buy  " .. ns.Money(a.buyout))
    buy:Enable()
  else
    buy:SetText("Buy")
    buy:Disable()
  end
  ns.Enable(bid, st == "READY" and not mine and not self.scanning)
end

function B:OnBuyClick()
  if self.queue then
    self.queue:Confirm()
  elseif self.plan and #self.plan.auctions > 0 and not self.scanning then
    local plan, g = self.plan, self.selGroup
    local text = format("Buy %d x %s%s|r\nfrom %d offer%s for %s?", plan.count, ns.QualityHex(g.quality), g.name,
      #plan.auctions, #plan.auctions == 1 and "" or "s", ns.Money(plan.cost))
    ns.ConfirmBuy(text, function()
      if B.plan == plan and not B.queue then B:StartQueue() end
    end)
  else
    self:Buy(false)
  end
end

-- Single offer: pre-locate so the Buy button is one click
function B:PrepareBuy(a)
  if not a or not ns.atAH or self.queue then return end
  local token = {}
  self.locateToken = token
  self.buyState = "LOCATING"
  self:UpdateBuyBar()
  ns.Locate(a, self.lastParams, function()
    if B.locateToken ~= token or B.selAuction ~= a then return end
    B.buyState = "READY"
    B:UpdateBuyBar()
  end, function(interrupted)
    if B.locateToken ~= token or B.selAuction ~= a then return end
    if interrupted then
      -- another scan interrupted us: try again in a moment
      B.buyState = nil
      ns.After(1.5, function()
        if B.locateToken == token and B.selAuction == a and not B.scanning then B:PrepareBuy(a) end
      end)
      return
    end
    B.buyState = "NOTFOUND"
    B:SetStatus("That offer was already sold or expired.")
    B:RemoveAuction(a)
    ns.After(0.6, function()
      if not B.selAuction and B.selGroup and not B.scanning and not B.queue then B:SelectGroup(B.selGroup) end
    end)
  end)
end

function B:Buy(isBid)
  local a = self.selAuction
  if not a or self.buyState ~= "READY" or self.scanning or self.queue then return end
  if GetTime() < (self.buyLock or 0) then return end

  local idx = ns.FindInList(a)
  if not idx then
    self:PrepareBuy(a)
    return
  end

  local _, _, _, _, _, _, minBid, minInc, buyout, bidAmount = GetAuctionItemInfo("list", idx)
  local amount
  if isBid then
    amount = (bidAmount and bidAmount > 0) and (bidAmount + (minInc or 0)) or minBid
    if buyout and buyout > 0 and amount >= buyout then
      amount, isBid = buyout, false
    end
  else
    amount = buyout
  end
  if not amount or amount <= 0 then return end
  if GetMoney() < amount then
    UIErrorsFrame:AddMessage(ERR_NOT_ENOUGH_MONEY or "Not enough money", 1, 0.2, 0.2)
    return
  end

  PlaceAuctionBid("list", idx, amount)
  self.buyLock = GetTime() + 0.5
  if not isBid then ns.RecordPurchase(a) end

  if isBid then
    a.bid = amount
    self:SetStatus("Bid placed: " .. ns.Money(amount))
    self:UpdateBuyBar()
    self.auctionList:Refresh()
    return
  end

  self.sessionSpent = (self.sessionSpent or 0) + amount
  self:SetStatus(format("Bought %dx %s for %s", a.count, a.name, ns.Money(amount)))
  PlaySound("LOOTWINDOWCOINSOUND")

  self:RemoveAuction(a)
  if self.selGroup then
    self:SelectGroup(self.selGroup, true)
    local nextA = self.selAuction
    if nextA then
      self.buyState = "LOCATING"
      self:UpdateBuyBar()
      ns.After(0.6, function()
        if B.selAuction == nextA and not B.scanning then B:PrepareBuy(nextA) end
      end)
    end
  end
end

---------------------------------------------------------------------------
-- Quantity purchase queue
---------------------------------------------------------------------------
function B:StartQueue(armOnly)
  local plan = self.plan
  if not plan or #plan.auctions == 0 or self.scanning then return end
  if GetMoney() < plan.cost then
    if armOnly then return end
    UIErrorsFrame:AddMessage(ERR_NOT_ENOUGH_MONEY or "Not enough money", 1, 0.2, 0.2)
    return
  end
  local list = {}
  local cap = { limit = plan.count, placed = 0 }
  for i, a in ipairs(plan.auctions) do list[i] = { a = a, params = self.lastParams, cap = cap } end
  self.locateToken = nil
  local q = ns.NewBuyQueue(list, {
    onUpdate = function() B:UpdateBuyBar() end,
    onStarted = function() B:UpdateBuyBar() end,
    onBought = function(_, item, cost)
      B.sessionSpent = (B.sessionSpent or 0) + cost
      B:RemoveAuction(item.a)
    end,
    onGone = function(_, item) B:RemoveAuction(item.a) end,
    onWaiting = function() PlaySound("igMainMenuOptionCheckBoxOn") end,
    onFinish = function(queue) B:QueueFinish(queue) end,
    onStop = function(queue, reason) B:QueueStopped(queue, reason) end,
  })
  q.need = plan.need
  self.queue = q
  if armOnly then q:Arm() else q:Start() end
end

function B:QueueFinish(q)
  if self.queue ~= q then return end
  self.queue = nil
  local remaining = q.need - q.bought
  local msg = format("Bought %d for %s", q.bought, ns.Money(q.spent, true))
  if q.bought > 0 then msg = msg .. "  (" .. ns.Money(q.spent / q.bought) .. " each)" end
  if remaining > 0 then
    msg = msg .. format("  |cffffaa33%d still needed - Buy again|r", remaining)
    self.qty:SetTextSilent(remaining)
  else
    self.qty:SetTextSilent("")
  end
  self:SetStatus(msg)
  self:Replan()
  if not self.plan and self.selGroup then self:SelectGroup(self.selGroup) end
end

function B:QueueStop(reason)
  if self.queue then self.queue:Stop(reason or "Stopped.") end
end

function B:QueueStopped(q, reason)
  if self.queue ~= q then return end
  self.queue = nil
  if q.bought > 0 then
    local remaining = q.need - q.bought
    self.qty:SetTextSilent(remaining > 0 and remaining or "")
    reason = (reason or "Stopped.") .. format("  Bought %d for %s", q.bought, ns.Money(q.spent, true))
  end
  if reason then self:SetStatus(reason) end
  self:Replan()
end
