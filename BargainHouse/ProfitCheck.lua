local ADDON, ns = ...
local C = ns.C
local format, floor = string.format, math.floor

-- Crafting profit check for ONE recipe the player picks.
--   ns.db.vendorBuy[itemID]   = unit price seen at a merchant (unlimited stock)
--   ns.db.manualPrice[itemID] = unit price typed by the player

local AH_CUT = 0.05
local PC = {}
ns.ProfitCheck = PC

---------------------------------------------------------------------------
-- UI (overlay on the right side of the Crafting tab)
---------------------------------------------------------------------------
function PC:Create(parent)
  local f = CreateFrame("Frame", nil, parent)
  ns.Size(f, 622, 546)
  f:SetPoint("TOPRIGHT")
  f:SetFrameLevel(parent:GetFrameLevel() + 20)
  f:EnableMouse(true)
  ns.Skin(f, C.bg, C.accent)
  f:Hide()
  self.frame = f

  local icon = f:CreateTexture(nil, "ARTWORK")
  ns.Size(icon, 32, 32)
  icon:SetPoint("TOPLEFT", 12, -10)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  self.icon = icon
  local title = ns.Text(f, "BHFontLarge", "")
  title:SetPoint("LEFT", icon, "RIGHT", 10, 6)
  ns.Size(title, 480, 18)
  self.title = title
  local sub = ns.Text(f, "BHFontSmall", "")
  sub:SetPoint("LEFT", icon, "RIGHT", 10, -10)
  ns.Size(sub, 480, 14)
  self.sub = sub

  local close = ns.Button(f, "X", 26, 24)
  close:SetPoint("TOPRIGHT", -10, -10)
  close:SetScript("OnClick", function() PC:Close() end)

  -- crafts / rescan / status
  local cl = ns.Text(f, "BHFontSmall", "Crafts")
  cl:SetPoint("TOPLEFT", 12, -58)
  local crafts = ns.EditBox(f, 50, 22, nil, true)
  crafts:SetPoint("TOPLEFT", 52, -52)
  crafts:SetMaxLetters(4)
  crafts.onChange = function(self)
    local n = tonumber(self:GetText()) or 0
    if n > 0 and PC.recipe then PC.crafts = n; PC:Compute() end
  end
  self.craftsBox = crafts
  local scrollCheck = ns.Check(f, "Sell as scroll (adds vellum)", function(_, on)
    ns.db.scrollVellum = on
    if PC.recipe then PC:Open(PC.recipe, PC.crafts) end
  end)
  scrollCheck:SetPoint("TOPLEFT", 320, -56)
  scrollCheck:SetChecked(ns.db.scrollVellum ~= false)
  scrollCheck.tooltip = "Enchants sell as scrolls, which are written on a vellum. Untick if you already have the vellums, to leave their cost out."
  scrollCheck:Hide()
  self.scrollCheck = scrollCheck

  local rescan = ns.Button(f, "Rescan prices", 110, 22)
  rescan:SetPoint("LEFT", crafts, "RIGHT", 8, 0)
  rescan:SetScript("OnClick", function() PC:Scan() end)
  self.rescanBtn = rescan
  local status = ns.Text(f, "BHFontSmall", "")
  status:SetPoint("LEFT", rescan, "RIGHT", 12, 0)
  ns.Size(status, 320, 14)
  self.status = status
  local prog = ns.Progress(f, 598, 3)
  prog:SetPoint("TOPLEFT", 12, -80)
  self.prog = prog

  -- reagents
  local cols = {
    { text = "Reagent", w = 150, key = "name" },
    { text = "Need", w = 44, key = "need", j = "RIGHT" },
    { text = "Source", w = 66, key = "source" },
    { text = "Price each", w = 104, key = "unit", j = "RIGHT" },
    { text = "Cost", w = 104, key = "cost", j = "RIGHT" },
    { text = "Note", w = 92, key = "note", font = "BHFontSmall" },
  }
  local list = ns.List(f, "BargainHouseProfitList", 598, 200, 22, cols, true)
  list:SetPoint("TOPLEFT", 12, -90)
  list.update = function(r, e)
    r.icon:SetTexture(e.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    r.cols[1]:SetText((e.quality and ns.QualityHex(e.quality) or "|cffdddddd") .. e.name .. "|r"
      .. (e.vellum and "  |cff888888(scroll)|r" or ""))
    r.cols[2]:SetText(e.need)
    local src = { ah = "|cffddddddAuction|r", vendor = "|cff66dd88Vendor|r", ["ah+vendor"] = "|cff66dd88AH+Vendor|r", manual = "|cffe6cc80Manual|r" }
    r.cols[3]:SetText(e.source and src[e.source] or (e.scanning and (ns.ACCENT .. "Scanning|r") or "|cffff5555No price|r"))
    r.cols[4]:SetText(e.unit and ns.Money(e.unit) or "")
    r.cols[5]:SetText(e.cost and ns.Money(e.cost) or "")
    r.cols[6]:SetText(e.note or "")
  end
  list.onClick = function(e)
    PC.selectedReagent = e
    list.selected = e
    list:Refresh()
    PC.manual:SetCopper(ns.db.manualPrice and ns.db.manualPrice[e.id] or (e.unit or 0))
    PC:UpdateManualRow()
  end
  list.onEnter = function(e, r)
    GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
    if e.link then GameTooltip:SetHyperlink(e.link) else GameTooltip:SetText(e.name, 1, 1, 1) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Auction house", e.ahCost and (ns.Money(e.ahCost) .. (e.ahShort and " (not enough listed)" or "")) or "not listed", 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("Vendor", e.vendorUnit and (ns.Money(e.vendorUnit) .. " each") or (e.vendorItem and "sold by vendors - price not recorded yet" or "not seen at a vendor"), 0.8, 0.8, 0.8, 1, 1, 1)
    if e.vendorItem then
      GameTooltip:AddLine("Vendor items are never priced from inflated auction listings: only offers cheaper than the vendor are used.", 0.7, 0.7, 0.7, true)
    end
    GameTooltip:AddLine(ns.ACCENT .. "Click|r to type your own price", 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end
  self.list = list

  -- manual price row
  local ml = ns.Text(f, "BHFontSmall", "Your price for the selected reagent")
  ml:SetPoint("TOPLEFT", 12, -304)
  local manual = ns.MoneyInput(f)
  manual:SetPoint("TOPLEFT", 206, -298)
  self.manual = manual
  local set = ns.Button(f, "Use", 50, 22)
  set:SetPoint("LEFT", manual, "RIGHT", 10, 0)
  set:SetScript("OnClick", function()
    local e = PC.selectedReagent
    if not e or not e.id then return end
    ns.db.manualPrice = ns.db.manualPrice or {}
    local v = manual:GetCopper()
    ns.db.manualPrice[e.id] = v > 0 and v or nil
    PC:Compute()
  end)
  local clear = ns.Button(f, "Auto", 50, 22)
  clear:SetPoint("LEFT", set, "RIGHT", 4, 0)
  clear.tooltip = "Forget your price and use auction / vendor prices again"
  clear:SetScript("OnClick", function()
    local e = PC.selectedReagent
    if e and e.id and ns.db.manualPrice then ns.db.manualPrice[e.id] = nil end
    PC:Compute()
  end)
  self.manualBtns = { set, clear }

  -- product box
  local pbox = CreateFrame("Frame", nil, f)
  ns.Size(pbox, 598, 96)
  pbox:SetPoint("TOPLEFT", 12, -332)
  ns.Skin(pbox, C.input)
  self.plines = {}
  for i = 1, 4 do
    local l = ns.Text(pbox, "BHFontSmall", "")
    l:SetPoint("TOPLEFT", 10, -8 - (i - 1) * 20)
    local v = ns.Text(pbox, "BHFontNormal", "", "RIGHT")
    v:SetPoint("TOPRIGHT", -10, -7 - (i - 1) * 20)
    self.plines[i] = { l, v }
  end

  -- summary
  local sbox = CreateFrame("Frame", nil, f)
  ns.Size(sbox, 598, 96)
  sbox:SetPoint("TOPLEFT", 12, -438)
  ns.Skin(sbox, C.panel)
  local verdict = ns.Text(sbox, "BHFontTitle", "")
  verdict:SetPoint("TOPLEFT", 12, -12)
  ns.Size(verdict, 380, 22)
  self.verdict = verdict
  local detail1 = ns.Text(sbox, "BHFontNormal", "")
  detail1:SetPoint("TOPLEFT", 12, -42)
  ns.Size(detail1, 380, 16)
  self.detail1 = detail1
  local detail2 = ns.Text(sbox, "BHFontSmall", "")
  detail2:SetPoint("TOPLEFT", 12, -64)
  ns.Size(detail2, 380, 26)
  self.detail2 = detail2

  local queue = ns.Button(sbox, "Add to craft queue", 180, 34, "accent")
  queue:SetPoint("RIGHT", -12, 0)
  queue:SetScript("OnClick", function()
    if not PC.recipe then return end
    local e = PC.recipe
    ns.Crafting.selected = e
    ns.Crafting.qty:SetTextSilent(PC.crafts)
    ns.Crafting:AddToQueue()
    PC:Close()
  end)

  return f
end

function PC:Close()
  self.scanToken = nil
  if self.scanning then ns.Scanner:Stop() end
  self.scanning = false
  self.frame:Hide()
end

function PC:UpdateManualRow()
  local on = self.selectedReagent ~= nil
  for _, b in ipairs(self.manualBtns) do ns.Enable(b, on) end
end

---------------------------------------------------------------------------
-- Open for a recipe: build reagent rows and scan prices
---------------------------------------------------------------------------
function PC:Open(entry, crafts)
  if not self.frame or not ns.atAH then return end
  local rec = entry.rec
  self.recipe, self.crafts = entry, math.max(1, crafts or 1)
  self.selectedReagent = nil
  self.list.selected = nil
  self:UpdateManualRow()

  self.icon:SetTexture(rec.i)
  self.title:SetText("Profit check: " .. entry.name)
  local mine = ns.Recipes:Crafters(rec, true)
  local who
  if #mine > 0 then
    who = "crafted by |cff66dd88" .. table.concat(mine, ", ") .. "|r"
  else
    local holders = ns.Chars and ns.Chars:WithProfession(entry.prof) or {}
    who = holders[1] and ("probably |cffe6cc80" .. holders[1].name .. "|r (has " .. entry.prof .. ")")
      or "|cffffaa33none of your characters is known to craft this|r"
  end
  self.sub:SetText(format("%s   makes %d per craft   %s", entry.prof, rec.m or 1, who))
  self.craftsBox:SetTextSilent(self.crafts)
  if ns.ScrollName(entry.prof, entry.name) or entry.prof == "Enchanting" then
    self.scrollCheck:Show()
    self.scrollCheck:SetChecked(ns.db.scrollVellum ~= false)
  else
    self.scrollCheck:Hide()
  end

  self.reagents = {}
  for _, rg in ipairs(rec.r) do
    local name, link, quality, texture
    if rg.id then
      local _
      name, link, quality, _, _, _, _, _, _, texture = GetItemInfo(rg.id)
    end
    self.reagents[#self.reagents + 1] = { name = rg.n, per = rg.c, id = rg.id, link = link, quality = quality, texture = texture, auctions = {} }
  end
  -- Enchanting is sold as a scroll: "Scroll of <recipe>", written on a vellum
  -- that the profession window doesn't list as a reagent.
  local scroll = ns.ScrollName(entry.prof, entry.name)
  if scroll and ns.db.scrollVellum ~= false then
    local vellum = ns.VellumFor(entry.name)
    self.reagents[#self.reagents + 1] = { name = vellum, per = 1, id = nil, auctions = {}, vellum = true }
  end
  if scroll then
    self.product = { name = scroll, auctions = {}, scroll = true }
  else
    self.product = { id = ns.ItemID(rec.l), link = rec.l, name = rec.l and rec.l:match("%[(.-)%]") or entry.name, auctions = {} }
  end
  self.frame:Show()
  self:Compute()
  self:Scan()
end

function PC:Scan()
  if not ns.atAH or not self.reagents then return end
  local todo = {}
  for _, e in ipairs(self.reagents) do todo[#todo + 1] = e end
  if self.product.id or self.product.name then todo[#todo + 1] = self.product end
  for _, e in ipairs(todo) do e.scanning, e.scanned = true, false end
  self.scanning = true
  self.rescanBtn:Disable()
  local token = {}
  self.scanToken = token

  local function Next(i)
    if PC.scanToken ~= token then return end
    local e = todo[i]
    PC.prog:SetValue((i - 1) / #todo)
    if not e then
      PC.scanning = false
      PC.rescanBtn:Enable()
      PC.status:SetText("Prices checked " .. date("%H:%M"))
      PC:Compute()
      return
    end
    PC.status:SetText(format("Checking %d of %d: %s", i, #todo, e.name))
    PC:Compute()
    local lname = strlower(e.name)
    local found = {}
    ns.Scanner:Start({
      params = { name = e.name },
      page = 0,
      maxPages = ns.db.maxPages,
      onPage = function(entries)
        if PC.scanToken ~= token then return false end
        for _, a in ipairs(entries) do
          if strlower(a.name) == lname then
            a.unit = a.buyout > 0 and (a.buyout / a.count) or nil
            found[#found + 1] = a
          end
        end
      end,
      onDone = function(aborted)
        if PC.scanToken ~= token then return end
        if aborted then
          PC.scanning = false
          PC.rescanBtn:Enable()
          PC.status:SetText("|cffff5555Price check interrupted - Rescan prices.|r")
          PC:Compute()
          return
        end
        e.auctions, e.scanning, e.scanned = found, false, true
        if found[1] then
          e.link, e.texture, e.quality, e.name = e.link or found[1].link, found[1].texture, found[1].quality, found[1].name
          e.id = e.id or ns.ItemID(found[1].link)
          local low
          for _, a in ipairs(found) do if a.unit and (not low or a.unit < low) then low = a.unit end end
          if low and e.id then ns.RecordPrice(e.id, low) end
        end
        Next(i + 1)
      end,
    })
  end
  Next(1)
end

---------------------------------------------------------------------------
-- The maths
---------------------------------------------------------------------------
function PC:Compute()
  if not self.reagents then return end
  local crafts, me = self.crafts, ns.Me()
  local total, unknown = 0, 0

  for _, e in ipairs(self.reagents) do
    e.need = e.per * crafts
    e.source, e.unit, e.cost, e.note = nil, nil, nil, nil
    e.ahCost, e.ahShort = nil, nil
    e.vendorUnit = e.id and ns.db.vendorBuy and ns.db.vendorBuy[e.id]

    local options = {}
    local plan, vendorQty, vendorUnit, unknownVendor = ns.PlanWithVendor(e.scanned and e.auctions or {}, e.need, e.id, e.name, me)
    e.vendorUnit, e.vendorItem = vendorUnit, vendorUnit ~= nil or unknownVendor
    if e.scanned and #e.auctions > 0 then
      local full = ns.PlanPurchase(e.auctions, e.need, me)
      if full.count > 0 then e.ahCost, e.ahShort = full.cost, full.short end
    end
    if vendorUnit then
      local fromAH = plan and plan.count or 0
      local cost = (plan and plan.cost or 0) + floor(vendorUnit * vendorQty + 0.5)
      local note = fromAH > 0 and format("%d cheaper on AH", math.min(fromAH, e.need)) or nil
      options[#options + 1] = { fromAH > 0 and "ah+vendor" or "vendor", cost, note }
    elseif not unknownVendor and e.scanned and plan and plan.count > 0 and not plan.short then
      options[#options + 1] = { "ah", plan.cost, (plan.extra or 0) > 0 and format("+%d extra", plan.extra) or nil }
    end
    local manual = e.id and ns.db.manualPrice and ns.db.manualPrice[e.id]
    if manual then options = { { "manual", manual * e.need } } end
    e.unknownVendor = unknownVendor and not manual

    local best
    for _, o in ipairs(options) do
      if not best or o[2] < best[2] then best = o end
    end
    if best then
      e.source, e.cost, e.note = best[1], best[2], best[3]
      e.unit = e.cost / e.need
      total = total + e.cost
    else
      unknown = unknown + 1
      if e.unknownVendor then
        e.note = "|cffffaa33vendor item|r"
      elseif e.scanned then
        e.note = e.ahShort and "|cffff5555not enough|r" or "|cffff5555not listed|r"
      end
    end
  end
  self.list:SetData(self.reagents, true)

  -- product
  local p = self.product
  local rec = self.recipe.rec
  local made = (rec.m or 1) * crafts
  local lowest, listed = nil, 0
  for _, a in ipairs(p.auctions or {}) do
    if a.unit and a.owner ~= me then
      listed = listed + 1
      if not lowest or a.unit < lowest then lowest = a.unit end
    end
  end
  local value, days = nil, 0
  if p.id then value, days = ns.MarketValue(p.id) end
  local undercut = lowest and math.max(1, floor(lowest) - (ns.db.undercut or 0)) or nil
  local sellEach
  if undercut and value then sellEach = math.min(undercut, value)
  else sellEach = undercut or value end

  local pl = self.plines
  if not (p.id or p.scroll) then
    pl[1][1]:SetText("This recipe doesn't create an item that can be sold on the auction house.")
    pl[1][2]:SetText("")
    for i = 2, 4 do pl[i][1]:SetText(""); pl[i][2]:SetText("") end
  else
    pl[1][1]:SetText(format("Lowest listing now  |cff888888(%d listed)|r", listed))
    pl[1][2]:SetText(p.scanning and (ns.ACCENT .. "checking...|r") or (lowest and ns.Money(lowest) or "|cff888888not listed|r"))
    pl[2][1]:SetText(format("Market value  |cff888888(%s)|r", days > 0 and format("%d day%s of full scans", days, days == 1 and "" or "s") or "no full scans yet"))
    pl[2][2]:SetText(value and ns.Money(value) or "|cff888888unknown|r")
    pl[3][1]:SetText("You sell each for  |cff888888(the lower of undercut and market value)|r")
    pl[3][2]:SetText(sellEach and ns.Money(sellEach) or "|cff888888unknown|r")
    pl[4][1]:SetText(format("Revenue for %d item%s after the 5%% AH cut", made, made == 1 and "" or "s"))
    pl[4][2]:SetText(sellEach and ns.Money(floor(sellEach * made * (1 - AH_CUT))) or "|cff888888unknown|r")
  end

  -- verdict
  self.result = nil
  local busy = self.scanning
  if busy then
    self.verdict:SetText(ns.ACCENT .. "Checking prices...|r")
    self.detail1:SetText("")
    self.detail2:SetText("")
  elseif unknown > 0 then
    local vendorNames = {}
    for _, e in ipairs(self.reagents) do
      if not e.source and e.unknownVendor then vendorNames[#vendorNames + 1] = e.name end
    end
    self.verdict:SetText("|cffffaa33Can't tell yet|r")
    self.detail1:SetText(format("%d reagent%s without a price", unknown, unknown == 1 and "" or "s"))
    if #vendorNames > 0 then
      self.detail2:SetText(table.concat(vendorNames, ", ") .. " is sold by vendors: open that vendor once so its real price is known (or type a price).")
    else
      self.detail2:SetText("Visit the vendor that sells it once, or click the reagent and type your own price.")
    end
  elseif not sellEach then
    self.verdict:SetText("|cffffaa33Can't tell yet|r")
    self.detail1:SetText("Materials cost " .. ns.Money(total, true))
    self.detail2:SetText("The crafted item isn't listed and has no market history: run a full scan in the Deals tab.")
  else
    local revenue = floor(sellEach * made * (1 - AH_CUT))
    local profit = revenue - total
    local margin = total > 0 and floor(profit / total * 100) or 0
    self.result = { cost = total, revenue = revenue, profit = profit }
    if profit >= 0 then
      self.verdict:SetText("|cff66dd88Profit  +" .. ns.Money(profit, true) .. "|r")
    else
      self.verdict:SetText("|cffff5555Loss  -" .. ns.Money(-profit, true) .. "|r")
    end
    self.detail1:SetText(format("Materials %s   Revenue %s   Margin %d%%", ns.Money(total, true), ns.Money(revenue, true), margin))
    self.detail2:SetText(format("%s per craft. Assumes every item sells at that price; big quantities can push the price down.",
      (profit >= 0 and "+" or "-") .. ns.Money(math.abs(profit) / crafts, true)))
  end
end
