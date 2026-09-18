local ADDON, ns = ...
local C = ns.C
local format = string.format

-- A results panel that takes a list of { name, need, link? } entries,
-- compares it with your bags, prices what's missing at the lowest total cost
-- and buys everything after one confirmation.
-- Used by the Shopping List and Crafting tabs.

local Panel = {}
Panel.__index = Panel
ns.panels = ns.panels or {}

function ns.FindBagLink(name)
  local lname = strlower(name)
  for bag = 0, 4 do
    for slot = 1, GetContainerNumSlots(bag) do
      local link = GetContainerItemLink(bag, slot)
      local n = link and link:match("%[(.-)%]")
      if n and strlower(n) == lname then return link end
    end
  end
end

function ns.MaterialsPanel(parent, key, opts)
  opts = opts or {}
  local P = setmetatable({ entries = {}, key = key, opts = opts }, Panel)
  ns.panels[#ns.panels + 1] = P

  local right = CreateFrame("Frame", nil, parent)
  ns.Size(right, 622, 546)
  right:SetPoint("TOPRIGHT")
  P.frame = right

  local cols = {
    { text = "Item", w = 124, key = "name" },
    { text = "Need", w = 32, key = "need", j = "RIGHT" },
    { text = "Have", w = 32, key = "have", j = "RIGHT" },
    { text = "Bank", w = 32, key = "bank", j = "RIGHT" },
    { text = "Alts", w = 32, key = "alts", j = "RIGHT" },
    { text = "Guild", w = 34, key = "guild", j = "RIGHT" },
    { text = "Miss", w = 36, key = "missing", j = "RIGHT" },
    { text = "Buy", w = 34, key = "buying", j = "RIGHT" },
    { text = "Cost", w = 94, key = "cost", j = "RIGHT" },
    { text = "Status", w = 70, key = "order", font = "BHFontSmall" },
  }
  local list = ns.List(right, "BargainHouse" .. key .. "List", 622, 458, 22, cols, true)
  list:SetPoint("TOPLEFT")
  list.emptyText = opts.emptyText or ""
  list.sortKey, list.sortAsc = "index", true
  list.onSort = function(k)
    if list.sortKey == k then list.sortAsc = not list.sortAsc
    else list.sortKey, list.sortAsc = k, true end
    P:Sort()
  end
  list.update = function(r, e)
    r.icon:SetTexture(e.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    local color = e.quality and ns.QualityHex(e.quality) or "|cffdddddd"
    if e.skip then color = "|cff666666" end
    r.cols[1]:SetText(color .. e.name .. "|r")
    r.cols[2]:SetText(e.need)
    r.cols[3]:SetText(e.have or "")
    local function Src(v, color) return (v or 0) > 0 and (color .. v .. "|r") or "" end
    r.cols[4]:SetText(Src(e.bank, "|cffe6cc80"))
    r.cols[5]:SetText(Src(e.alts, "|cffc79cff"))
    r.cols[6]:SetText(Src(e.guild, "|cff66bbff"))
    local missing = e.missing or 0
    if e.have then
      r.cols[7]:SetText(missing > 0 and ("|cffffd100" .. missing .. "|r") or "|cff66dd880|r")
    else
      r.cols[7]:SetText("")
    end
    local plan = e.plan
    if plan and plan.count > 0 then
      r.cols[8]:SetText((plan.extra or 0) > 0 and ("|cffffaa33" .. plan.count .. "|r") or plan.count)
    else
      r.cols[8]:SetText("")
    end
    if plan and plan.cost > 0 then
      r.cols[9]:SetText(ns.MoneyShort(plan.cost))
    elseif (e.vendorQty or 0) > 0 and e.vendorUnit then
      r.cols[9]:SetText("|cff66dd88" .. ns.MoneyShort(e.vendorUnit * e.vendorQty) .. "|r")
    else
      r.cols[9]:SetText("")
    end
    r.cols[10]:SetText(P:StatusText(e))
  end
  list.onClick = function(e, button)
    if button == "RightButton" then
      ns.main:SelectTab(1)
      ns.Browse.search:SetTextSilent(e.name)
      ns.Browse.mode:SetValue("EXACT")
      ns.Browse:DoSearch()
      return
    end
    if IsModifiedClick() and e.link then
      HandleModifiedItemClick(e.link)
      return
    end
    if P.queue and not P.queue.armed then return end
    P:Disarm()
    e.skip = not e.skip
    P:UpdateSummary()
    P:ScheduleArm()
  end
  list.onEnter = function(e, r)
    GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
    if e.link then GameTooltip:SetHyperlink(e.link) else GameTooltip:SetText(e.name, 1, 1, 1) end
    local shown = false
    local function Header() if not shown then GameTooltip:AddLine(" "); shown = true end end
    if (e.mail or 0) > 0 then
      Header()
      GameTooltip:AddLine(format("|cffdddddd%d in your bags, %d in your mailbox|r%s", e.bags or 0, e.mail,
        (e.mailBought or 0) > 0 and format("  |cff888888(%d bought, not collected)|r", e.mailBought) or ""), 1, 1, 1)
    end
    if (e.fromBank or 0) > 0 then
      Header()
      local _, t = ns.CountBank()
      GameTooltip:AddLine(format("|cffe6cc80Take %d from your bank|r%s", e.fromBank,
        t and ("  |cff888888(recorded " .. ns.TimeAgo(time() - t) .. ")|r") or ""), 1, 1, 1)
    end
    if (e.fromAlts or 0) > 0 then
      Header()
      GameTooltip:AddLine(format("|cffc79cffGet %d from your alts:|r", e.fromAlts), 1, 1, 1)
      for _, d in ipairs(e.altDetails or {}) do
        local where = {}
        if d.bags > 0 then where[#where + 1] = d.bags .. " in bags" end
        if d.bank > 0 then where[#where + 1] = d.bank .. " in bank" end
        GameTooltip:AddLine(format("   %s: %s  |cff888888(%s)|r", d.name, table.concat(where, ", "), ns.TimeAgo(time() - d.t)), 0.9, 0.9, 0.9)
      end
    end
    if (e.fromGuild or 0) > 0 then
      Header()
      local info = ns.GuildBankInfo()
      GameTooltip:AddLine(format("|cff66bbffTake %d from the guild bank|r%s", e.fromGuild,
        info and ("  |cff888888(recorded " .. ns.TimeAgo(time() - info.t) .. ")|r") or ""), 1, 1, 1)
    end
    if (e.vendorQty or 0) > 0 then
      GameTooltip:AddLine(" ")
      if e.vendorUnit then
        GameTooltip:AddLine(format("|cff66dd88Buy %d at a vendor|r for %s each (%s)", e.vendorQty, ns.Money(e.vendorUnit), ns.Money(e.vendorUnit * e.vendorQty)), 1, 1, 1, true)
        GameTooltip:AddLine("Only auction offers cheaper than the vendor are bought.", 0.7, 0.7, 0.7, true)
      else
        GameTooltip:AddLine("|cffffaa33Sold by vendors.|r Open the vendor once so its price is known. It is not bought from the auction house meanwhile.", 1, 1, 1, true)
      end
    end
    if e.usedBy then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("Used by: " .. e.usedBy, 0.8, 0.8, 0.8, true)
    end
    local plan = e.plan
    if plan and plan.count > 0 then
      GameTooltip:AddLine(" ")
      GameTooltip:AddDoubleLine(format("Buying %d in %d offer%s", plan.count, #plan.auctions, #plan.auctions == 1 and "" or "s"),
        ns.Money(plan.cost), 0.8, 0.8, 0.8, 1, 1, 1)
      GameTooltip:AddDoubleLine("Average each", ns.Money(plan.cost / plan.count), 0.8, 0.8, 0.8, 1, 1, 1)
      if (plan.extra or 0) > 0 then
        GameTooltip:AddLine(format("|cffffaa33%d more than needed: whole stacks make this the cheapest total.|r", plan.extra), 1, 1, 1, true)
        GameTooltip:AddLine("Turn off 'Allow extra items' in Settings to buy exact amounts.", 0.7, 0.7, 0.7, true)
      end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(ns.ACCENT .. "Click|r skip / include   " .. ns.ACCENT .. "Right-click|r open in Browse", 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end
  P.list = list

  local bar = CreateFrame("Frame", nil, right)
  ns.Size(bar, 622, 80)
  bar:SetPoint("BOTTOMLEFT")
  ns.Skin(bar, C.panel)

  P.status = ns.Text(bar, "BHFontSmall", "")
  P.status:SetPoint("TOPLEFT", 12, -10)
  ns.Size(P.status, 236, 14)

  local stock = ns.Button(bar, "", 118, 18)
  stock:SetPoint("TOPLEFT", 254, -8)
  stock.label:SetFontObject("BHFontSmall")
  stock.label:SetWidth(110)
  stock.label:SetHeight(18)
  stock.tooltip = "Choose what you already own is counted: bags, personal bank, alts, guild bank"
  stock:SetScript("OnClick", function(btn) P:OpenStockMenu(btn) end)
  P.stockBtn = stock

  P.line1 = ns.Text(bar, "BHFontNormal", "")
  P.line1:SetPoint("TOPLEFT", 12, -30)
  ns.Size(P.line1, 370, 16)

  P.line2 = ns.Text(bar, "BHFontNormal", "")
  P.line2:SetPoint("TOPLEFT", 12, -50)
  ns.Size(P.line2, 370, 16)

  P.prog = ns.Progress(bar, 598, 3)
  P.prog:SetPoint("BOTTOMLEFT", 12, 6)

  local buy = ns.Button(bar, "Buy everything", 220, 40, "gold")
  buy:SetPoint("TOPRIGHT", -10, -12)
  buy:SetScript("OnClick", function() P:OnBuyClick() end)
  P.buyBtn = buy

  local stop = ns.Button(bar, "Stop", 220, 14)
  stop:SetPoint("TOP", buy, "BOTTOM", 0, -4)
  stop.label:SetFontObject("BHFontSmall")
  stop:SetScript("OnClick", function() P:StopAll() end)
  P.stopBtn = stop

  right:SetScript("OnShow", function() P:ScheduleArm() end)
  right:SetScript("OnHide", function()
    P:Disarm()
    if P.queue then P.queue:Stop("Stopped (tab closed).") end
  end)

  P:UpdateSummary()
  list:SetData(P.entries)
  return P
end

---------------------------------------------------------------------------
-- Stock sources (bags always; bank, guild bank optional)
---------------------------------------------------------------------------
function Panel:StockLabel()
  if ns.db.shoppingIgnoreHave then return "Stock: ignored" end
  local parts = {}
  if ns.db.useBank then parts[#parts + 1] = "bank" end
  if ns.db.useAlts then parts[#parts + 1] = "alts" end
  if ns.db.useGuildBank then parts[#parts + 1] = "guild" end
  if #parts == 3 then return "Stock: all" end
  if #parts == 0 then return "Stock: bags" end
  return "Stock: +" .. table.concat(parts, "+")
end

function Panel:OpenStockMenu(owner)
  local function Mark(on) return on and (ns.ACCENT .. "[x]|r ") or "|cff777777[  ]|r " end
  local inv = ns.InventoryInfo()
  local bline = "   |cff888888" .. (inv.bankT and ("Recorded " .. ns.TimeAgo(time() - inv.bankT)) or "Not recorded yet - visit a banker once") .. "|r"
  local aline = "   |cff888888" .. (inv.alts > 0 and format("%d alt%s recorded (log in on each alt once)", inv.alts, inv.alts == 1 and "" or "s") or "No alts recorded yet - log in on each alt once") .. "|r"
  local info, why = ns.GuildBankInfo()
  local gline = info and format("   |cff888888%s: %d items in %d tab%s, %s|r", info.guild, info.items, info.tabs,
    info.tabs == 1 and "" or "s", ns.TimeAgo(time() - info.t)) or ("   |cff888888" .. (why or "") .. "|r")
  local items = {
    { text = "Count what I already have", disabled = true },
    { text = Mark(ns.db.useBank) .. "Include my bank", value = "bank" },
    { text = bline, disabled = true },
    { text = Mark(ns.db.useAlts) .. "Include my alts on this realm (same faction)", value = "alts" },
    { text = aline, disabled = true },
    { text = Mark(ns.db.useGuildBank) .. "Include guild bank (tabs marked Full Access)", value = "guild" },
    { text = gline, disabled = true },
    { text = Mark(ns.db.shoppingIgnoreHave) .. "Ignore everything I have (buy full amounts)", value = "ignore" },
  }
  ns.OpenMenu(owner, items, function(v)
    if v == "bank" then ns.db.useBank = not ns.db.useBank
    elseif v == "alts" then ns.db.useAlts = not ns.db.useAlts
    elseif v == "guild" then ns.db.useGuildBank = not ns.db.useGuildBank
    elseif v == "ignore" then ns.db.shoppingIgnoreHave = not ns.db.shoppingIgnoreHave end
    for _, panel in ipairs(ns.panels) do panel:Recount() end
  end, nil, 330)
end

-- Re-apply stock counts to the current results without rescanning the AH
function Panel:Recount()
  if not self.buyBtn then return end
  self:Disarm()
  if self.queue or self.scanning or #self.entries == 0 then
    self:UpdateSummary()
    return
  end
  local needScan = false
  for _, e in ipairs(self.entries) do
    if e.have then
      self:ApplyStock(e)
      if e.state == "done" then e.state = "priced" end
      if e.state == "stock" or not ns.atAH then
        e.state = ns.atAH and e.state or "stock"
      end
      if e.missing > 0 then
        if e.auctions then
          self:PlanEntry(e)
          e.state = "priced"
        else
          needScan = true
        end
      else
        e.plan, e.vendorQty = nil, 0
      end
    end
  end
  if needScan then
    self:Check(self.entries)
  else
    self:UpdateSummary()
    self:ScheduleArm()
  end
end

-- Auction plan + vendor part for what's missing (vendor items are never
-- bought from the auction house above the vendor price)
function Panel:PlanEntry(e)
  e.plan, e.vendorQty, e.vendorUnit, e.vendorUnknown = nil, 0, nil, false
  if (e.missing or 0) <= 0 then return end
  local id = e.id or ns.ResolveItemID(e.link, e.name)
  e.id = id
  local plan, vendorQty, vendorUnit, unknown = ns.PlanWithVendor(e.auctions or {}, e.missing, id, e.name, ns.Me())
  e.plan, e.vendorQty, e.vendorUnit, e.vendorUnknown = plan, vendorQty, vendorUnit, unknown
  if e.plan and #e.plan.auctions == 0 then e.plan = nil end
end

function Panel:ApplyStock(e)
  local bags, mail, mailBought
  bags, mail, mailBought, e.bank, e.alts, e.guild, e.altDetails = self:CountOwned(e)
  e.bags, e.mail, e.mailBought = bags, mail, mailBought
  e.have = bags + mail
  e.fromMail = math.min(mail, math.max(0, e.need - bags))
  local left = math.max(0, e.need - e.have)            -- bags + mailbox first
  e.fromBank = math.min(e.bank, left); left = left - e.fromBank    -- then your bank
  e.fromAlts = math.min(e.alts, left); left = left - e.fromAlts    -- then your alts
  e.fromGuild = math.min(e.guild, left); left = left - e.fromGuild -- then the guild bank
  e.missing = left
end

function Panel:Disarm()
  self.armToken = nil
  if self.queue and self.queue.armed then
    self.queue:Cancel()
    self.queue = nil
  end
end

function Panel:ScheduleArm()
  if not ns.db.clickMode or self.queue or self.scanning then return end
  local token = {}
  self.armToken = token
  ns.After(0.4, function()
    if self.armToken ~= token or self.queue or self.scanning or not self.frame:IsVisible() then return end
    local t = self:Totals()
    if t.offers == 0 or GetMoney() < t.cost then return end
    self:BuyAll(true)
  end)
end

function Panel:StopAll(reason)
  self:Disarm()
  if self.queue then self.queue:Stop(reason or "Buying stopped.")
  elseif self.scanning then self:StopScan() end
end

function Panel:Clear()
  self:Disarm()
  if self.queue or self.scanning then return end
  self.entries = {}
  self.list:SetData(self.entries)
  self.status:SetText("")
  self.prog:SetValue(0)
  self:UpdateSummary()
end

function Panel:SetScanState(on)
  self.scanning = on
  if self.opts.onScanState then self.opts.onScanState(on) end
end

function Panel:StatusText(e)
  if e.skip then return "|cff777777Skipped|r" end
  if e.state == "pending" then return "|cff888888Waiting|r" end
  if e.state == "scanning" then return ns.ACCENT .. "Scanning...|r" end
  if e.state == "buying" then return "|cffffd100Buying...|r" end
  if e.state == "done" then
    local left = (e.missing or 0) - (e.bought or 0)
    if left <= 0 then return "|cff66dd88Bought|r" end
    return format("|cffffaa33Short %d|r", left)
  end
  if (e.missing or 0) <= 0 and e.state then
    if (e.fromGuild or 0) > 0 then return "|cff66bbffIn guild bank|r" end
    if (e.fromAlts or 0) > 0 then return "|cffc79cffOn your alts|r" end
    if (e.fromBank or 0) > 0 then return "|cffe6cc80In your bank|r" end
    if (e.fromMail or 0) > 0 then
      if (e.mailBought or 0) > 0 then return "|cff66dd88Bought|r" end
      return "|cffddddddIn mailbox|r"
    end
    return "|cff66dd88Have enough|r"
  end
  if e.state == "stock" then
    if ns.IsVendorItem(e.id or ns.ResolveItemID(e.link, e.name), e.name) then
      return format("|cff66dd88Vendor: %d|r", e.missing)
    end
    return format("|cffffd100Missing %d|r", e.missing)
  end
  if e.state == "priced" then
    if (e.vendorQty or 0) > 0 then
      if e.vendorUnknown then return "|cffffaa33Vendor item|r" end
      if e.plan and e.plan.count > 0 then return format("|cff66dd88+%d at vendor|r", e.vendorQty) end
      return "|cff66dd88Buy at vendor|r"
    end
    if not e.found then return "|cffff5555Not on AH|r" end
    if e.plan and e.plan.short then return format("|cffffaa33Only %d listed|r", e.plan.count) end
    return "|cffddddddReady|r"
  end
  return ""
end

function Panel:Sort()
  local key, asc = self.list.sortKey, self.list.sortAsc
  table.sort(self.entries, function(a, b)
    local va, vb
    if key == "name" then va, vb = strlower(a.name), strlower(b.name)
    elseif key == "buying" then va, vb = a.plan and a.plan.count or 0, b.plan and b.plan.count or 0
    elseif key == "cost" then va, vb = a.plan and a.plan.cost or 0, b.plan and b.plan.cost or 0
    elseif key == "order" then va, vb = (a.skip and 1 or 0), (b.skip and 1 or 0)
    else va, vb = a[key] or 0, b[key] or 0 end
    if va == vb then return a.index < b.index end
    if asc then return va < vb end
    return va > vb
  end)
  self.list:SetData(self.entries, true)
end

---------------------------------------------------------------------------
-- Checking & pricing
---------------------------------------------------------------------------
-- Returns bags (live), personal bank, alts, guild bank, alt details
-- Stock of an item from every enabled source (works away from the auction house)
-- Returns bags (live), mailbox (+ uncollected purchases), bought part, personal bank, alts, guild bank, alt details
function ns.StockCount(link, name, id)
  if ns.db.shoppingIgnoreHave then return 0, 0, 0, 0, 0, 0, {} end
  local ref = link or (name and ns.FindBagLink(name)) or name or id
  local bags = ref and GetItemCount(ref) or 0
  id = id or ns.ResolveItemID(link, name)
  local mail, bought = 0, 0
  if id then mail, bought = ns.CountMail(id) end
  local bank = (ns.db.useBank and id) and ns.CountBank(id) or 0
  local alts, details = 0, {}
  if ns.db.useAlts and id then alts, details = ns.CountAlts(id) end
  local guild = ns.db.useGuildBank and ns.GuildBankCount(link, name) or 0
  return bags, mail, bought, bank, alts, guild, details
end

function Panel:CountOwned(e)
  return ns.StockCount(e.link, e.name, e.id)
end

-- entries: { { name = , need = , link = (optional), usedBy = (optional) }, ... }
function Panel:Check(entries)
  self:Disarm()
  if self.queue then self.queue:Stop("Stopped.") end -- a new check replaces any open purchase run
  if #entries == 0 then
    self.status:SetText("|cffff5555Nothing to check.|r")
    return
  end

  local oldSkip = {}
  for _, e in ipairs(self.entries) do
    if e.skip then oldSkip[strlower(e.name)] = true end
  end

  for i, e in ipairs(entries) do
    e.index = i
    e.skip = oldSkip[strlower(e.name)]
    e.link = e.link or ns.FindBagLink(e.name)
    self:ApplyStock(e)
    e.state = e.missing > 0 and "pending" or "priced"
    e.plan, e.found = nil, nil
    if e.link then
      local _, _, quality, _, _, _, _, _, _, texture = GetItemInfo(e.link)
      e.quality, e.texture = quality, texture or e.texture
    end
  end
  self.entries = entries
  self.list.sortKey, self.list.sortAsc = "index", true
  self:Sort()

  if not ns.atAH then
    -- away from the auction house: stock only, no prices, no buying
    for _, e in ipairs(entries) do
      e.state, e.plan, e.auctions = "stock", nil, nil
      e.vendorQty = 0
    end
    self.prog:SetValue(1)
    self:UpdateSummary()
    self.status:SetText("Stock checked. Prices and buying at the auction house.")
    return
  end

  local todo = {}
  for _, e in ipairs(entries) do
    if e.missing > 0 then todo[#todo + 1] = e end
  end
  self:SetScanState(true)
  self:ScanNext(todo, 1)
end

function Panel:StopScan()
  self.scanToken = nil
  ns.Scanner:Stop()
  self:ScanFinished(true)
end

function Panel:ScanNext(todo, i)
  local token = {}
  self.scanToken = token
  local e = todo[i]
  self.prog:SetValue((i - 1) / math.max(1, #todo))
  if not e then
    self:ScanFinished(false)
    return
  end
  e.state = "scanning"
  self.status:SetText(format("Pricing %d of %d:  %s", i, #todo, e.name))
  self:UpdateSummary()

  local lname = strlower(e.name)
  local auctions = {}
  local params = { name = e.name }
  ns.Scanner:Start({
    params = params,
    page = 0,
    maxPages = ns.db.maxPages,
    onPage = function(found)
      if self.scanToken ~= token then return false end
      for _, a in ipairs(found) do
        if strlower(a.name) == lname then
          a.unit = a.buyout > 0 and (a.buyout / a.count) or nil
          auctions[#auctions + 1] = a
        end
      end
    end,
    onDone = function(aborted)
      if self.scanToken ~= token then return end
      if aborted then
        self.scanToken = nil
        self:ScanFinished(true)
        return
      end
      e.auctions, e.params = auctions, params
      e.found = #auctions > 0
      if e.found then
        local a = auctions[1]
        e.name, e.link, e.texture, e.quality = a.name, a.link, a.texture, a.quality
        self:ApplyStock(e)
        local low
        for _, x in ipairs(auctions) do
          if x.unit and (not low or x.unit < low) then low = x.unit end
        end
        if low then ns.RecordPrice(a.id, low) end
      end
      self:PlanEntry(e)
      e.state = "priced"
      self:UpdateSummary()
      self:ScanNext(todo, i + 1)
    end,
  })
end

function Panel:ScanFinished(aborted)
  self:SetScanState(false)
  for _, e in ipairs(self.entries) do
    if e.state == "pending" or e.state == "scanning" then e.state = nil end
  end
  self.prog:SetValue(aborted and 0 or 1)
  self.status:SetText(aborted and "Check stopped." or "Prices checked. Click a row to skip items you don't want to buy.")
  self:UpdateSummary()
  if not aborted then self:ScheduleArm() end
end

---------------------------------------------------------------------------
-- Totals & buying
---------------------------------------------------------------------------
function Panel:Totals()
  local t = { items = #self.entries, complete = 0, missingLines = 0, cost = 0, buying = 0, offers = 0, short = 0, notFound = 0, guildLines = 0, vendorCost = 0, vendorUnknown = 0 }
  for _, e in ipairs(self.entries) do
    if (e.fromGuild or 0) + (e.fromBank or 0) + (e.fromAlts or 0) > 0 then t.guildLines = t.guildLines + 1 end
    if (e.missing or 0) <= 0 and e.have then
      t.complete = t.complete + 1
    else
      t.missingLines = t.missingLines + 1
      if not e.skip and e.plan then
        t.cost = t.cost + e.plan.cost
        t.buying = t.buying + e.plan.count
        t.offers = t.offers + #e.plan.auctions
        if e.plan.short and e.plan.count > 0 and (e.vendorQty or 0) == 0 then t.short = t.short + 1 end
      end
      if not e.skip and (e.vendorQty or 0) > 0 then
        if e.vendorUnit then
          t.vendorCost = t.vendorCost + math.floor(e.vendorUnit * e.vendorQty + 0.5)
        else
          t.vendorUnknown = t.vendorUnknown + 1
        end
      end
      if not e.skip and e.state == "priced" and not e.found and (e.vendorQty or 0) == 0 then t.notFound = t.notFound + 1 end
    end
  end
  return t
end

function Panel:UpdateSummary()
  if not self.buyBtn then return end
  self.stockBtn:SetText(self:StockLabel())
  local q, buy, stop = self.queue, self.buyBtn, self.stopBtn
  local t = self:Totals()

  if #self.entries == 0 then
    self.line1:SetText("")
    self.line2:SetText("")
  else
    local g = t.guildLines > 0 and format("   |cffe6cc80%d from bank/alts/guild|r", t.guildLines) or ""
    self.line1:SetText(format("%d materials   %s%d covered|r   |cffffd100%d to buy|r%s",
      t.items, "|cff66dd88", t.complete, t.missingLines, g))
    local extra = ""
    if t.short > 0 then extra = extra .. format("   |cffffaa33%d not fully available|r", t.short) end
    if t.notFound > 0 then extra = extra .. format("   |cffff5555%d not listed|r", t.notFound) end
    if t.vendorCost > 0 then extra = extra .. "   |cff66dd88+ " .. ns.Money(t.vendorCost) .. " at vendors|r" end
    if t.vendorUnknown > 0 then extra = extra .. format("   |cffffaa33%d vendor item%s (price unknown)|r", t.vendorUnknown, t.vendorUnknown == 1 and "" or "s") end
    self.line2:SetText("Total cost:  " .. ns.Money(t.cost, true) .. extra)
  end

  if q and not q.armed then
    local item = q.current
    if q.waiting then
      buy:SetText(format("Buy %d  %s", q.waitingCount, ns.Money(q.waitingCost)))
      buy:Enable()
      self.status:SetText(ns.ACCENT .. format("Click Buy: %d offer%s on this page|r", q.waitingCount, q.waitingCount == 1 and "" or "s"))
    elseif ns.pendingBid and ns.pendingBid.q == q then
      buy:SetText("Waiting for server...")
      buy:Disable()
      self.status:SetText(format("Buying...   spent %s", ns.Money(q.spent, true)))
    else
      buy:SetText(format("Finding %d / %d ...", math.max(q.i, 1), #q.list))
      buy:Disable()
      self.status:SetText(format("Finding %s   spent %s", item and item.entry.name or "", ns.Money(q.spent, true)))
    end
    self.prog:SetValue(math.max(0, q.i - 1) / math.max(1, #q.list))
    stop:Enable()
  elseif not ns.atAH then
    buy:SetText("Auction house needed")
    buy:Disable()
    stop:Disable()
    if #self.entries > 0 then
      self.line2:SetText(t.missingLines > 0 and "|cff888888Visit an auctioneer to price and buy what's missing.|r" or "|cff66dd88You have everything.|r")
    end
  else
    if t.offers > 0 and GetMoney() < t.cost then
      buy:SetText("|cffff5555Need|r " .. ns.Money(t.cost))
      buy:Disable()
    elseif q and q.armed then
      if q.waiting then
        buy:SetText(format("Buy %d  %s", q.waitingCount, ns.Money(q.waitingCost)))
        buy:Enable()
        self.status:SetText(ns.ACCENT .. format("%d of %d offers on this page - one click buys them|r", q.waitingCount, #q.list))
      else
        buy:SetText("Loading page...")
        buy:Disable()
      end
    elseif t.offers > 0 and not self.scanning then
      buy:SetText("Buy everything  " .. ns.Money(t.cost))
      buy:Enable()
    else
      buy:SetText("Buy everything")
      buy:Disable()
    end
    ns.Enable(stop, self.scanning)
  end
  self.list:Refresh()
end

function Panel:OnBuyClick()
  if self.queue then
    self.queue:Confirm()
    return
  end
  local t = self:Totals()
  if t.offers == 0 or self.scanning then return end
  local what = self.opts.confirmText and self.opts.confirmText() or "your list"
  ns.ConfirmBuy(format("Buy %d items (%d offers) for %s?\n\nTotal: %s", t.buying, t.offers, what, ns.Money(t.cost)),
    function() self:BuyAll() end)
end

function Panel:BuyAll(armOnly)
  if self.queue or self.scanning or not ns.atAH then return end
  local t = self:Totals()
  if t.offers == 0 then return end
  if GetMoney() < t.cost then
    if armOnly then return end
    UIErrorsFrame:AddMessage(ERR_NOT_ENOUGH_MONEY or "Not enough money", 1, 0.2, 0.2)
    return
  end

  local list = {}
  for _, e in ipairs(self.entries) do
    if not e.skip and e.plan and #e.plan.auctions > 0 and (e.missing or 0) > 0 then
      local cap = { limit = e.plan.count, placed = 0 }
      for _, a in ipairs(e.plan.auctions) do
        list[#list + 1] = { a = a, params = e.params, entry = e, cap = cap }
      end
    end
  end

  local function EntryDone(e)
    for _, item in ipairs(self.queue and self.queue.list or {}) do
      if item.entry == e and not item.handled then return end
    end
    e.state = "done"
  end

  local function MarkBuying()
    for _, item in ipairs(list) do
      local e = item.entry
      if e.state ~= "buying" then
        e.bought, e.spent, e.state = 0, 0, "buying"
      end
    end
  end

  local q = ns.NewBuyQueue(list, {
    onUpdate = function() self:UpdateSummary() end,
    onStarted = function() MarkBuying(); self:UpdateSummary() end,
    onBought = function(_, item, cost)
      local e = item.entry
      for k = #(e.auctions or {}), 1, -1 do
        if e.auctions[k] == item.a then table.remove(e.auctions, k) break end
      end
      e.bought = e.bought + item.a.count
      e.spent = e.spent + cost
      EntryDone(e)
    end,
    onGone = function(_, item)
      local e = item.entry
      for k = #(e.auctions or {}), 1, -1 do
        if e.auctions[k] == item.a then table.remove(e.auctions, k) break end
      end
      EntryDone(item.entry)
    end,
    onFinish = function(queue) self:BuyFinished(queue) end,
    onStop = function(queue, reason) self:BuyFinished(queue, reason) end,
  })
  self.queue = q
  if armOnly then
    q:Arm()
  else
    MarkBuying()
    self.status:SetText("Buying...")
    q:Start()
  end
end

function Panel:BuyFinished(q, reason)
  if self.queue ~= q then return end
  self.queue = nil
  local shortLines = 0
  for _, e in ipairs(self.entries) do
    if e.state == "buying" or e.state == "done" then
      e.state = "done"
      e.plan = nil
      e.bought = 0
      self:ApplyStock(e) -- purchases now count (mailbox), so missing is what's really left
      if e.missing > 0 then shortLines = shortLines + 1 end
    end
  end
  local msg = format("%sBought %d items for %s.", reason and (reason .. "  ") or "", q.bought, ns.Money(q.spent, true))
  if shortLines > 0 then
    msg = msg .. format("  |cffffaa33%d still short - check again.|r", shortLines)
  end
  self.prog:SetValue(1)
  self:UpdateSummary()
  self.status:SetText(msg)
  if self.opts.onBought then self.opts.onBought(q) end
end
