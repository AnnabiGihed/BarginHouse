local ADDON, ns = ...
local C = ns.C
local format = string.format

local A = { data = {} }
ns.Auctions = A

StaticPopupDialogs["BARGAINHOUSE_CANCEL"] = {
  text = "Cancel your auction of %s?\nThe deposit will not be refunded.",
  button1 = YES,
  button2 = NO,
  OnAccept = function(self, data) A:DoCancel(data or self.data) end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
}

function A:Create(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  self.frame = f

  local title = ns.Text(f, "BHFontLarge", "My auctions")
  title:SetPoint("TOPLEFT", 4, -8)

  local summary = ns.Text(f, "BHFontSmall", "")
  summary:SetPoint("TOPLEFT", 4, -26)
  ns.Size(summary, 600, 14)
  self.summary = summary

  local cancel = ns.Button(f, "Cancel auction", 130, 28, "danger")
  cancel:SetPoint("TOPRIGHT", 0, -4)
  cancel:SetScript("OnClick", function() A:Cancel() end)
  self.cancelBtn = cancel

  local refresh = ns.Button(f, "Refresh", 90, 28)
  refresh:SetPoint("RIGHT", cancel, "LEFT", -6, 0)
  refresh:SetScript("OnClick", function() A:Query() end)

  local cols = {
    { text = "Item", w = 220, key = "name" },
    { text = "Qty", w = 40, key = "count", j = "RIGHT" },
    { text = "Per unit", w = 110, key = "unit", j = "RIGHT" },
    { text = "Buyout", w = 110, key = "buyout", j = "RIGHT" },
    { text = "Current bid", w = 110, key = "bid", j = "RIGHT" },
    { text = "AH lowest", w = 110, key = "low", j = "RIGHT" },
    { text = "Time", w = 44, key = "timeLeft", j = "CENTER" },
    { text = "Status", w = 70, key = "status" },
  }
  local list = ns.List(f, "BargainHouseOwnerList", 920, 506, 22, cols, true)
  list:SetPoint("TOPLEFT", 0, -40)
  list.emptyText = "You have no auctions."
  list.sortKey, list.sortAsc = "name", true
  list.onSort = function(key)
    if list.sortKey == key then list.sortAsc = not list.sortAsc
    else list.sortKey, list.sortAsc = key, true end
    A:Sort()
  end
  list.update = function(r, a)
    r.icon:SetTexture(a.texture)
    r.cols[1]:SetText(ns.QualityHex(a.quality) .. a.name .. "|r")
    r.cols[2]:SetText(a.count)
    r.cols[3]:SetText(ns.Money(a.unit))
    r.cols[4]:SetText(ns.Money(a.buyout))
    r.cols[5]:SetText(a.bid > 0 and ns.Money(a.bid) or "|cff666666none|r")
    if a.low and a.unit then
      local color = (a.low < a.unit) and "|cffff6655" or "|cff66dd88"
      r.cols[6]:SetText(color .. "*|r " .. ns.Money(a.low))
    else
      r.cols[6]:SetText(ns.Money(a.low))
    end
    r.cols[7]:SetText(a.sold and "" or (ns.TIME_LEFT[a.timeLeft] or "?"))
    if a.sold then r.cols[8]:SetText(ns.ACCENT .. "Sold|r")
    elseif a.bid > 0 then r.cols[8]:SetText("|cffffd100Has bid|r")
    else r.cols[8]:SetText("|cffbbbbbbActive|r") end
  end
  list.onClick = function(a, button)
    if button == "LeftButton" and IsModifiedClick() then
      HandleModifiedItemClick(a.link)
    else
      A.selected = a
      list.selected = a
      list:Refresh()
      A:UpdateButtons()
    end
  end
  list.onEnter = function(a, r)
    GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
    if a.link then GameTooltip:SetHyperlink(a.link) end
    if a.low and a.unit then
      GameTooltip:AddLine(" ")
      if a.low < a.unit then
        GameTooltip:AddLine("|cffff6655Undercut:|r someone listed it for " .. ns.Money(a.low) .. " per unit (last scan).", 1, 1, 1, true)
      else
        GameTooltip:AddLine(ns.ACCENT .. "You are the cheapest|r as of the last scan.", 1, 1, 1, true)
      end
    end
    GameTooltip:Show()
  end
  self.list = list

  f:SetScript("OnShow", function(frame)
    frame:RegisterEvent("AUCTION_OWNED_LIST_UPDATE")
    A:Query()
  end)
  f:SetScript("OnHide", function(frame)
    frame:UnregisterEvent("AUCTION_OWNED_LIST_UPDATE")
  end)
  f:SetScript("OnEvent", function() A:Read() end)

  self:UpdateButtons()
  return f
end

function A:Query()
  if not ns.atAH then return end
  GetOwnerAuctionItems()
  self:Read()
end

function A:Read()
  local data = {}
  local batch = GetNumAuctionItems("owner")
  local active, sold, value, soldValue = 0, 0, 0, 0
  for i = 1, batch do
    local name, texture, count, quality, _, _, minBid, _, buyout, bidAmount, highBidder, _, saleStatus =
      GetAuctionItemInfo("owner", i)
    if name then
      local link = GetAuctionItemLink("owner", i)
      local id = ns.ItemID(link)
      local p = id and ns.db.prices[id]
      local a = {
        index = i, name = name, texture = texture, count = count or 1, quality = quality or 1,
        minBid = minBid or 0, buyout = buyout or 0, bid = bidAmount or 0, highBidder = highBidder,
        sold = saleStatus == 1, timeLeft = GetAuctionItemTimeLeft("owner", i), link = link, id = id,
        low = p and p.l or nil,
      }
      a.unit = a.buyout > 0 and (a.buyout / a.count) or nil
      a.status = a.sold and 0 or (a.bid > 0 and 1 or 2)
      if a.sold then
        sold = sold + 1
        soldValue = soldValue + math.max(a.bid, a.buyout)
      else
        active = active + 1
        value = value + a.buyout
      end
      data[#data + 1] = a
    end
  end
  self.data = data
  self.summary:SetText(format("%d active  (buyout value %s)     %d sold  (%s incoming)",
    active, ns.Money(value, true), sold, ns.Money(soldValue, true)))

  -- keep selection if the same auction is still there
  local sel = self.selected
  self.selected = nil
  if sel then
    for _, a in ipairs(data) do
      if a.name == sel.name and a.count == sel.count and a.buyout == sel.buyout and a.sold == sel.sold then
        self.selected = a
        break
      end
    end
  end
  self:Sort()
  self:UpdateButtons()
end

function A:Sort()
  local key, asc = self.list.sortKey, self.list.sortAsc
  table.sort(self.data, function(a, b)
    local default = (key == "name") and "" or 0
    local va, vb = a[key] or default, b[key] or default
    if va == vb then return a.index < b.index end
    if asc then return va < vb end
    return va > vb
  end)
  self.list.selected = self.selected
  self.list:SetData(self.data, true)
end

function A:UpdateButtons()
  local a = self.selected
  ns.Enable(self.cancelBtn, a and not a.sold)
end

function A:Cancel()
  local a = self.selected
  if not a or a.sold then return end
  local dialog = StaticPopup_Show("BARGAINHOUSE_CANCEL", a.link or a.name)
  if dialog then dialog.data = a end
end

function A:DoCancel(a)
  if not a or not ns.atAH then return end
  -- the owner list may have changed; find the matching index again
  local batch = GetNumAuctionItems("owner")
  for i = 1, batch do
    local name, _, count, _, _, _, _, _, buyout, _, _, _, saleStatus = GetAuctionItemInfo("owner", i)
    if name == a.name and count == a.count and buyout == a.buyout and saleStatus ~= 1 then
      CancelAuction(i)
      self.selected = nil
      ns.After(0.5, function() A:Query() end)
      return
    end
  end
  ns.Print("Could not find that auction anymore.")
end
