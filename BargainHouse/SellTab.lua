local ADDON, ns = ...
local C = ns.C
local format, floor = string.format, math.floor

local S = { entries = {} }
ns.Sell = S

local DURATIONS = { { 1, "12 hours" }, { 2, "24 hours" }, { 3, "48 hours" } }

local function FindBagLink(name)
  for bag = 0, 4 do
    for slot = 1, GetContainerNumSlots(bag) do
      local link = GetContainerItemLink(bag, slot)
      if link and GetItemInfo(link) == name then return link end
    end
  end
end

function S:Create(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  self.frame = f

  -- Left: create auction ----------------------------------------------------
  local left = CreateFrame("Frame", nil, f)
  ns.Size(left, 330, 546)
  left:SetPoint("TOPLEFT")
  ns.Skin(left, C.panel)

  local title = ns.Text(left, "BHFontLarge", "Create auction")
  title:SetPoint("TOPLEFT", 14, -12)

  local slot = CreateFrame("Button", nil, left)
  ns.Size(slot, 46, 46)
  slot:SetPoint("TOPLEFT", 14, -38)
  ns.Skin(slot, C.input)
  slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  slot.icon = slot:CreateTexture(nil, "ARTWORK")
  slot.icon:SetPoint("TOPLEFT", 2, -2)
  slot.icon:SetPoint("BOTTOMRIGHT", -2, 2)
  slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  slot.count = ns.Text(slot, "BHFontBold", "", "RIGHT")
  slot.count:SetPoint("BOTTOMRIGHT", -3, 3)
  slot:SetScript("OnClick", function() S:SlotClick() end)
  slot:SetScript("OnReceiveDrag", function() S:SlotClick() end)
  slot:SetScript("OnEnter", function(btn)
    btn:SetBackdropBorderColor(unpack(C.accent))
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    if S.item and S.item.link then GameTooltip:SetHyperlink(S.item.link)
    else GameTooltip:SetText("Drop an item here\nor Alt+Click it in your bags.", 1, 1, 1) end
    GameTooltip:Show()
  end)
  slot:SetScript("OnLeave", function(btn)
    btn:SetBackdropBorderColor(unpack(C.border))
    GameTooltip:Hide()
  end)
  self.slot = slot

  local itemName = ns.Text(left, "BHFontNormal", "")
  itemName:SetPoint("TOPLEFT", slot, "TOPRIGHT", 10, -4)
  ns.Size(itemName, 250, 16)
  self.itemName = itemName

  local itemSub = ns.Text(left, "BHFontSmall", "")
  itemSub:SetPoint("BOTTOMLEFT", slot, "BOTTOMRIGHT", 10, 4)
  ns.Size(itemSub, 250, 14)
  self.itemSub = itemSub

  local function Label(text, x, y)
    local fs = ns.Text(left, "BHFontSmall", text)
    fs:SetPoint("TOPLEFT", x, y)
    return fs
  end

  Label("Stack size", 14, -100)
  local stack = ns.EditBox(left, 56, 22, nil, true)
  stack:SetPoint("TOPLEFT", 14, -116)
  stack:SetMaxLetters(4)
  stack.onChange = function() S:UpdateSummary() end
  self.stack = stack
  local stackMax = ns.Button(left, "Max", 42, 22)
  stackMax:SetPoint("LEFT", stack, "RIGHT", 4, 0)
  stackMax:SetScript("OnClick", function()
    if not S.item then return end
    stack:SetText(math.max(1, math.min(S.item.maxStack, S.item.owned)))
  end)

  Label("Number of stacks", 170, -100)
  local stacks = ns.EditBox(left, 56, 22, nil, true)
  stacks:SetPoint("TOPLEFT", 170, -116)
  stacks:SetMaxLetters(3)
  stacks.onChange = function() S:UpdateSummary() end
  stack.nextBox, stacks.nextBox = stacks, stack
  self.stacks = stacks
  local stacksMax = ns.Button(left, "Max", 42, 22)
  stacksMax:SetPoint("LEFT", stacks, "RIGHT", 4, 0)
  stacksMax:SetScript("OnClick", function()
    if not S.item then return end
    local sz = math.max(1, tonumber(stack:GetText()) or 1)
    stacks:SetText(math.max(1, floor(S.item.owned / sz)))
  end)

  Label("Buyout per unit", 14, -150)
  local buyout = ns.MoneyInput(left, function()
    S.userPriced = true
    S:UpdateSummary()
  end)
  buyout:SetPoint("TOPLEFT", 14, -166)
  self.buyout = buyout

  Label("Starting bid per unit", 14, -198)
  local bid = ns.MoneyInput(left, function()
    S.userPriced = true
    S:UpdateSummary()
  end)
  bid:SetPoint("TOPLEFT", 14, -214)
  self.bid = bid

  Label("Duration", 14, -246)
  self.durBtns = {}
  for i, d in ipairs(DURATIONS) do
    local b = ns.Button(left, d[2], 96, 24)
    b:SetPoint("TOPLEFT", 14 + (i - 1) * 101, -262)
    b:SetScript("OnClick", function() S:SetDuration(d[1]) end)
    self.durBtns[d[1]] = b
  end

  -- summary box
  local box = CreateFrame("Frame", nil, left)
  ns.Size(box, 302, 108)
  box:SetPoint("TOPLEFT", 14, -300)
  ns.Skin(box, C.input)
  self.sum = {}
  local labels = { "Buyout per stack", "Total buyout", "Deposit", "Vendor value (unit)" }
  for i, text in ipairs(labels) do
    local l = ns.Text(box, "BHFontSmall", text)
    l:SetPoint("TOPLEFT", 10, -8 - (i - 1) * 20)
    local v = ns.Text(box, "BHFontNormal", "", "RIGHT")
    v:SetPoint("TOPRIGHT", -10, -7 - (i - 1) * 20)
    self.sum[i] = v
  end
  local warn = ns.Text(left, "BHFontSmall", "", "CENTER")
  warn:SetPoint("TOPLEFT", 14, -414)
  ns.Size(warn, 302, 16)
  self.warn = warn

  local under = ns.Button(left, "Undercut lowest", 148, 26)
  under:SetPoint("TOPLEFT", 14, -438)
  under.tooltip = "Price just below the cheapest competing auction (see Settings for the undercut amount)"
  under:SetScript("OnClick", function() S:Undercut() end)

  local avg = ns.Button(left, "Use average", 148, 26)
  avg:SetPoint("TOPLEFT", 168, -438)
  avg.tooltip = "Use the recorded average lowest price of this item"
  avg:SetScript("OnClick", function()
    local p = S.item and S.item.id and ns.db.prices[S.item.id]
    if p then S:SetPrice(p.a) end
  end)

  local post = ns.Button(left, "Post auction", 302, 40, "accent")
  post:SetPoint("BOTTOMLEFT", 14, 14)
  post:SetScript("OnClick", function() S:Post() end)
  self.postBtn = post

  local postStatus = ns.Text(left, "BHFontSmall", "", "CENTER")
  postStatus:SetPoint("BOTTOM", post, "TOP", 0, 6)
  ns.Size(postStatus, 302, 14)
  self.postStatus = postStatus

  -- Right: market ----------------------------------------------------------
  local right = CreateFrame("Frame", nil, f)
  ns.Size(right, 582, 546)
  right:SetPoint("TOPRIGHT")

  local mTitle = ns.Text(right, "BHFontLarge", "Market")
  mTitle:SetPoint("TOPLEFT", 4, -10)
  ns.Size(mTitle, 480, 18)
  self.mTitle = mTitle

  local mInfo = ns.Text(right, "BHFontSmall", "Place an item in the slot to see what it sells for.")
  mInfo:SetPoint("TOPLEFT", 4, -32)
  ns.Size(mInfo, 480, 14)
  self.mInfo = mInfo

  local rescan = ns.Button(right, "Rescan", 84, 26)
  rescan:SetPoint("TOPRIGHT", 0, -10)
  rescan:SetScript("OnClick", function() S:ScanItem() end)

  local cols = {
    { text = "Qty", w = 44, key = "count", j = "RIGHT" },
    { text = "Per unit", w = 130, key = "unit", j = "RIGHT" },
    { text = "Buyout", w = 130, key = "buyout", j = "RIGHT" },
    { text = "Time", w = 50, key = "timeLeft", j = "CENTER" },
    { text = "Seller", w = 150, key = "owner" },
  }
  local list = ns.List(right, "BargainHouseSellList", 582, 490, 22, cols)
  list:SetPoint("TOPLEFT", 0, -56)
  list.emptyText = "No competing auctions."
  list.sortKey, list.sortAsc = "unit", true
  list.onSort = function(key)
    if list.sortKey == key then list.sortAsc = not list.sortAsc
    else list.sortKey, list.sortAsc = key, true end
    S:SortEntries()
    list:Refresh()
  end
  list.update = function(r, e)
    local mine = e.owner and e.owner == ns.Me()
    r.cols[1]:SetText(e.count)
    r.cols[2]:SetText(e.unit and ns.Money(e.unit) or "|cff888888bid only|r")
    r.cols[3]:SetText(e.buyout > 0 and ns.Money(e.buyout) or ns.Money(e.minBid))
    r.cols[4]:SetText(ns.TIME_LEFT[e.timeLeft] or "?")
    r.cols[5]:SetText(mine and (ns.ACCENT .. "You|r") or (e.owner or "|cff777777?|r"))
  end
  list.onClick = function(e)
    if not e.unit then return end
    local mine = e.owner and e.owner == ns.Me()
    S:SetPrice(mine and e.unit or (floor(e.unit) - (ns.db.undercut or 0)))
    S.userPriced = true
  end
  list.onEnter = function(e, r)
    GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
    GameTooltip:SetText("Click to match this price (minus your undercut)", 1, 1, 1)
    GameTooltip:Show()
  end
  self.list = list

  -- Events -----------------------------------------------------------------
  f:RegisterEvent("NEW_AUCTION_UPDATE")
  f:RegisterEvent("AUCTION_MULTISELL_START")
  f:RegisterEvent("AUCTION_MULTISELL_UPDATE")
  f:RegisterEvent("AUCTION_MULTISELL_FAILURE")
  f:RegisterEvent("BAG_UPDATE")
  f:SetScript("OnEvent", function(_, event, a1, a2)
    if event == "NEW_AUCTION_UPDATE" then
      S:OnSellItemChanged()
    elseif event == "AUCTION_MULTISELL_START" then
      S.postStatus:SetText(format("Posting 0 / %d ...", a1 or 0))
    elseif event == "AUCTION_MULTISELL_UPDATE" then
      S.postStatus:SetText(format("Posting %d / %d ...", a1 or 0, a2 or 0))
      if a1 and a2 and a1 >= a2 then S.postStatus:SetText(ns.ACCENT .. "All auctions posted.|r") end
    elseif event == "AUCTION_MULTISELL_FAILURE" then
      S.postStatus:SetText("|cffff5555Posting was interrupted.|r")
    elseif event == "BAG_UPDATE" then
      if ns.atAH and S.item and S.item.link then
        S.item.owned = math.max(GetItemCount(S.item.link), S.item.count)
        S:UpdateItem()
      end
    end
  end)
  -- NEW_AUCTION_UPDATE is also handled while other tabs are visible
  f:SetScript("OnShow", function() S:UpdateItem() end)

  self:SetDuration(ns.db.duration)
  self:UpdateItem()
  list:SetData(self.entries)
  return f
end

---------------------------------------------------------------------------
-- Sell slot
---------------------------------------------------------------------------
function S:SlotClick()
  local ctype, _, link = GetCursorInfo()
  if ctype == "item" then
    self.pendingLink = link
    ClickAuctionSellItemButton()
    ClearCursor()
  elseif self.item then
    ClickAuctionSellItemButton() -- picks the item back up
    ClearCursor()                -- and returns it to the bags
  end
end

function S:SetItemFromBag(bag, slot)
  if not ns.atAH then return end
  ClearCursor()
  self.pendingLink = GetContainerItemLink(bag, slot)
  PickupContainerItem(bag, slot)
  ClickAuctionSellItemButton()
  ClearCursor()
  if ns.main then ns.main:SelectTab(5) end
end

function S:ClearSlot()
  if self.item and ns.atAH and not GetCursorInfo() then
    ClickAuctionSellItemButton()
    ClearCursor()
  end
end

function S:OnSellItemChanged()
  local name, texture, count, quality, _, price = GetAuctionSellItemInfo()
  if not name then
    self.item = nil
    self:UpdateItem()
    return
  end

  local link = self.pendingLink
  if not link or GetItemInfo(link) ~= name then link = FindBagLink(name) end
  self.pendingLink = nil

  local maxStack, sellPrice = 1, nil
  if link then
    local _, _, _, _, _, _, _, stackCount, _, _, vendor = GetItemInfo(link)
    maxStack, sellPrice = stackCount or 1, vendor
  end
  count = count or 1
  if not sellPrice and price and price > 0 then sellPrice = floor(price / count) end

  self.item = {
    name = name, link = link, id = ns.ItemID(link), texture = texture, count = count,
    quality = quality, maxStack = maxStack, sellPrice = sellPrice,
    owned = math.max(link and GetItemCount(link) or 0, count),
  }

  if self.lastName ~= name then
    self.lastName = name
    self.userPriced = false
    self.stack:SetTextSilent(math.min(count, maxStack))
    self.stacks:SetTextSilent(1)
    local p = self.item.id and ns.db.prices[self.item.id]
    if p then
      self:SetPrice(p.l)
    elseif sellPrice and sellPrice > 0 then
      self:SetPrice(sellPrice * 3)
    else
      self.buyout:SetCopper(0)
      self.bid:SetCopper(0)
    end
    self.userPriced = false
    self:ScanItem()
  end
  self.postStatus:SetText("")
  self:UpdateItem()
end

function S:UpdateItem()
  if not self.slot then return end
  local item = self.item
  if item then
    self.slot.icon:SetTexture(item.texture)
    self.slot.count:SetText(item.count > 1 and item.count or "")
    self.itemName:SetText(ns.QualityHex(item.quality) .. item.name .. "|r")
    self.itemSub:SetText(format("In bags: %d   Max stack: %d", item.owned, item.maxStack))
  else
    self.slot.icon:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
    self.slot.count:SetText("")
    self.itemName:SetText("|cff888888No item selected|r")
    self.itemSub:SetText("Drop an item here or Alt+Click it in your bags")
  end
  self:UpdateSummary()
end

---------------------------------------------------------------------------
-- Pricing
---------------------------------------------------------------------------
function S:SetDuration(d)
  ns.db.duration = d
  for k, b in pairs(self.durBtns) do
    b:SetStyle(k == d and "accent" or "normal")
  end
  self:UpdateSummary()
end

function S:SetPrice(unit)
  unit = math.max(1, floor(unit or 0))
  self.buyout:SetCopper(unit)
  self.bid:SetCopper(math.max(1, floor(unit * (ns.db.bidPct or 90) / 100)))
  self:UpdateSummary()
end

function S:LowestOther()
  local me, low = ns.Me(), nil
  for _, e in ipairs(self.entries) do
    if e.unit and e.owner ~= me and (not low or e.unit < low) then low = e.unit end
  end
  return low
end

function S:Undercut()
  local low = self:LowestOther()
  if low then
    local price = low
    if (ns.db.undercutPct or 0) > 0 then price = price * (1 - ns.db.undercutPct / 100) end
    self:SetPrice(floor(price) - (ns.db.undercut or 0))
    return true
  end
end

function S:SortEntries()
  local key, asc = self.list.sortKey, self.list.sortAsc
  table.sort(self.entries, function(a, b)
    if key == "unit" or key == "buyout" then
      local ha, hb = a.buyout > 0, b.buyout > 0
      if ha ~= hb then return ha end
    end
    local va, vb
    if key == "owner" then va, vb = a.owner or "", b.owner or ""
    elseif key == "unit" then va, vb = a.unit or 0, b.unit or 0
    else va, vb = a[key] or 0, b[key] or 0 end
    if va == vb then return a.count < b.count end
    if asc then return va < vb end
    return va > vb
  end)
end

function S:UpdateMarketInfo()
  local n, qty, mine, lowAll = #self.entries, 0, 0, nil
  local me = ns.Me()
  for _, e in ipairs(self.entries) do
    qty = qty + e.count
    if e.owner == me then mine = mine + 1 end
    if e.unit and (not lowAll or e.unit < lowAll) then lowAll = e.unit end
  end
  local low = self:LowestOther()
  local text = format("%d auctions   %d items   Lowest: %s", n, qty, ns.Money(low))
  if mine > 0 then text = text .. format("   %sYours: %d|r", ns.ACCENT, mine) end
  self.mInfo:SetText(text)
end

function S:ScanItem()
  local name = (self.item and self.item.name) or self.lastName
  if not name or not ns.atAH then return end
  local entries = {}
  self.entries = entries
  self.list:SetData(entries)
  self.mTitle:SetText("Market: " .. ((self.item and ns.QualityHex(self.item.quality)) or "") .. name .. "|r")
  self.mInfo:SetText("Scanning...")

  ns.Scanner:Start({
    params = { name = name },
    page = 0,
    maxPages = 10,
    onPage = function(list, page, totalPages)
      if S.entries ~= entries then return false end
      for _, e in ipairs(list) do
        if e.name == name then
          e.unit = e.buyout > 0 and (e.buyout / e.count) or nil
          entries[#entries + 1] = e
        end
      end
      S:SortEntries()
      S.list:SetData(entries, true)
      S.mInfo:SetText(format("Scanning page %d of %d ...", page + 1, math.min(totalPages, 10)))
    end,
    onDone = function(aborted)
      if S.entries ~= entries then return end
      local lowAll, id
      for _, e in ipairs(entries) do
        id = id or e.id
        if e.unit and (not lowAll or e.unit < lowAll) then lowAll = e.unit end
      end
      if not aborted and id and lowAll then ns.RecordPrice(id, lowAll) end
      S:UpdateMarketInfo()
      if aborted then S.mInfo:SetText("Scan stopped. " .. S.mInfo:GetText()) end
      if not S.userPriced then S:Undercut() end
      S.list:Refresh()
    end,
  })
end

function S:ReadInputs()
  return tonumber(self.stack:GetText()) or 0, tonumber(self.stacks:GetText()) or 0,
         self.buyout:GetCopper(), self.bid:GetCopper()
end

function S:UpdateSummary()
  if not self.postBtn then return end
  local item = self.item
  local stack, stacks, unit, bunit = self:ReadInputs()
  local err, note

  if not item then
    err = ""
  elseif stack < 1 then
    err = "Stack size must be at least 1"
  elseif stack > item.maxStack then
    err = "Max stack size for this item is " .. item.maxStack
  elseif stacks < 1 then
    err = "Choose at least one stack"
  elseif stack * stacks > item.owned then
    err = format("You only have %d of this item", item.owned)
  elseif unit <= 0 and bunit <= 0 then
    err = "Set a price"
  elseif unit > 0 and bunit > unit then
    err = "Starting bid is higher than buyout"
  end

  if not err and item.sellPrice and unit > 0 and unit < item.sellPrice then
    note = "|cffffaa33Warning: below vendor price|r"
  end

  self.sum[1]:SetText(ns.Money(unit * math.max(stack, 0)))
  self.sum[2]:SetText(ns.Money(unit * math.max(stack, 0) * math.max(stacks, 0)))
  local deposit
  if item and stack >= 1 and stacks >= 1 then
    local ok, d = pcall(CalculateAuctionDeposit, ns.db.duration, stack, stacks)
    if ok then deposit = d end
  end
  self.sum[3]:SetText(deposit and ns.Money(deposit, true) or "|cff555555--|r")
  self.sum[4]:SetText(item and item.sellPrice and ns.Money(item.sellPrice) or "|cff555555--|r")

  if err and err ~= "" then self.warn:SetText("|cffff5555" .. err .. "|r")
  else self.warn:SetText(note or "") end

  ns.Enable(self.postBtn, not err)
  if item and not err then
    self.postBtn:SetText(stacks > 1 and format("Post %d x %d", stacks, stack) or "Post auction")
  else
    self.postBtn:SetText("Post auction")
  end
end

function S:Post()
  self:UpdateSummary()
  if not self.item or not self.postBtn:IsEnabled() then return end
  local stack, stacks, unit, bunit = self:ReadInputs()
  local buyStack = floor(unit * stack)
  local bidStack = floor(bunit * stack)
  if bidStack <= 0 then bidStack = buyStack end
  if buyStack > 0 and bidStack > buyStack then bidStack = buyStack end
  if bidStack <= 0 then return end

  StartAuction(bidStack, buyStack, ns.db.duration, stack, stacks)
  self.postStatus:SetText(format("Posting %d x %d ...", stacks, stack))

  -- show our new auctions in the market list right away
  local me = ns.Me()
  for _ = 1, stacks do
    self.entries[#self.entries + 1] = {
      name = self.item.name, link = self.item.link, id = self.item.id, count = stack,
      buyout = buyStack, minBid = bidStack, bid = 0, unit = buyStack > 0 and (buyStack / stack) or nil,
      owner = me, timeLeft = ns.db.duration == 1 and 3 or 4,
    }
  end
  self:SortEntries()
  self.list:Refresh()
  self:UpdateMarketInfo()
end
