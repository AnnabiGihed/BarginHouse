local ADDON, ns = ...
local C = ns.C

local T = {}
ns.Settings = T

function T:Create(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()

  local box = CreateFrame("Frame", nil, f)
  ns.Size(box, 520, 546)
  box:SetPoint("TOPLEFT")
  ns.Skin(box, C.panel)

  local y = -14
  local function Header(text)
    y = y - 6
    local fs = ns.Text(box, "BHFontLarge", ns.ACCENT .. text .. "|r")
    fs:SetPoint("TOPLEFT", 16, y)
    y = y - 26
  end
  local function Row(label)
    local fs = ns.Text(box, "BHFontNormal", label)
    fs:SetPoint("TOPLEFT", 16, y - 4)
    local yy = y
    y = y - 32
    return yy
  end
  local function NumberBox(label, key, minV, maxV)
    local yy = Row(label)
    local e = ns.EditBox(box, 70, 22, nil, true)
    e:SetPoint("TOPLEFT", 340, yy)
    e:SetMaxLetters(4)
    e:SetTextSilent(ns.db[key])
    e.onChange = function(self)
      local v = tonumber(self:GetText())
      if v then ns.db[key] = math.max(minV, math.min(maxV, v)) end
    end
    e:SetScript("OnEditFocusLost", function(self)
      self.focused = false
      self:SetBackdropBorderColor(unpack(C.border))
      self:SetTextSilent(ns.db[key])
    end)
    return e
  end

  Header("General")
  local rep = ns.Check(box, "Replace the default auction house window", function(_, on)
    ns.db.replaceBlizzard = on
    ns.ApplyReplace()
  end)
  rep:SetPoint("TOPLEFT", 16, y)
  rep:SetChecked(ns.db.replaceBlizzard)
  y = y - 26

  local tips = ns.Check(box, "Show recorded auction prices in item tooltips", function(_, on)
    ns.db.tooltipPrices = on
  end)
  tips:SetPoint("TOPLEFT", 16, y)
  tips:SetChecked(ns.db.tooltipPrices)
  y = y - 26

  local confirm = ns.Check(box, "Ask once before buying a quantity or a shopping list", function(_, on)
    ns.db.confirmBuy = on
  end)
  confirm:SetPoint("TOPLEFT", 16, y)
  confirm:SetChecked(ns.db.confirmBuy)
  y = y - 26

  local rclick = ns.Check(box, "Right-click a bag item at an auctioneer to sell it", function(_, on)
    ns.db.rightClickSell = on
    if on then
      if ns.atAH then ns.InstallBagClick() end
    else
      ns.RemoveBagClick()
    end
  end)
  rclick:SetPoint("TOPLEFT", 16, y)
  rclick:SetChecked(ns.db.rightClickSell ~= false)
  rclick.tooltip = "Only active while the auction house is open. Turn it off if you'd rather right-click keep its normal behaviour there."
  y = y - 26

  local extra = ns.Check(box, "Allow extra items when a bigger stack is cheaper in total", function(_, on)
    ns.db.allowExtra = on
    for _, panel in ipairs(ns.panels or {}) do
      for _, e in ipairs(panel.entries) do e.plan = nil end
      panel:Recount()
    end
    if ns.Browse.Replan then ns.Browse:Replan() end
  end)
  extra:SetPoint("TOPLEFT", 16, y)
  extra:SetChecked(ns.db.allowExtra)
  extra.tooltip = "Stacks can't be split. When on, BargainHouse may buy e.g. a stack of 12 instead of 7 single items if that costs less in total. When off, it buys exactly what you need (or the smallest possible overshoot)."
  y = y - 30

  Header("Searching")
  NumberBox("Max pages per search  |cff888888(50 auctions / page)|r", "maxPages", 1, 200)

  Header("Selling")
  local yy = Row("Undercut by (flat amount)")
  local under = ns.MoneyInput(box, function(v) ns.db.undercut = v end)
  under:SetPoint("TOPLEFT", 340, yy)
  under:SetCopper(ns.db.undercut)
  NumberBox("Undercut by (percent)", "undercutPct", 0, 50)
  NumberBox("Starting bid  |cff888888(% of buyout)|r", "bidPct", 1, 100)

  Header("Window")
  yy = Row("Scale")
  local scaleText = ns.Text(box, "BHFontNormal", "", "CENTER")
  ns.Size(scaleText, 50, 22)
  scaleText:SetPoint("TOPLEFT", 374, yy)
  local function SetScale(v)
    v = math.max(0.6, math.min(1.4, math.floor(v * 20 + 0.5) / 20))
    ns.db.scale = v
    scaleText:SetText(string.format("%.2f", v))
    if ns.main then ns.main:SetScale(v) end
  end
  local minus = ns.Button(box, "-", 30, 22)
  minus:SetPoint("TOPLEFT", 340, yy)
  minus:SetScript("OnClick", function() SetScale(ns.db.scale - 0.05) end)
  local plus = ns.Button(box, "+", 30, 22)
  plus:SetPoint("TOPLEFT", 428, yy)
  plus:SetScript("OnClick", function() SetScale(ns.db.scale + 0.05) end)
  scaleText:SetText(string.format("%.2f", ns.db.scale))

  Header("Data")
  local count = ns.Text(box, "BHFontSmall", "")
  count:SetPoint("TOPLEFT", 16, y)
  y = y - 24
  local function UpdateCount()
    local n = 0
    for _ in pairs(ns.db.prices) do n = n + 1 end
    count:SetText(n .. " items in the price database,  " .. #ns.db.history .. " recent searches,  " .. #ns.db.favorites .. " favorites")
  end
  local clearHist = ns.Button(box, "Clear search history", 160, 26)
  clearHist:SetPoint("TOPLEFT", 16, y)
  clearHist:SetScript("OnClick", function() wipe(ns.db.history); UpdateCount() end)
  local clearPrices = ns.Button(box, "Clear price database", 160, 26, "danger")
  clearPrices:SetPoint("LEFT", clearHist, "RIGHT", 8, 0)
  local forgetAlts = ns.Button(box, "Forget other characters", 160, 26, "danger")
  forgetAlts:SetPoint("LEFT", clearPrices, "RIGHT", 8, 0)
  forgetAlts.tooltip = "Remove recorded bags and banks of every character on this realm except the current one"
  forgetAlts:SetScript("OnClick", function() ns.ForgetAlts() end)
  clearPrices:SetScript("OnClick", function() wipe(ns.db.prices); UpdateCount() end)
  f:SetScript("OnShow", UpdateCount)

  -- Quick guide ------------------------------------------------------------------
  local help = CreateFrame("Frame", nil, f)
  ns.Size(help, 392, 546)
  help:SetPoint("TOPRIGHT")
  ns.Skin(help, C.panel)

  local gt = ns.Text(help, "BHFontLarge", ns.ACCENT .. "Quick guide|r")
  gt:SetPoint("TOPLEFT", 16, -16)
  local body = ns.Text(help, "BHFontSmall", table.concat({
    "|cffffd100Browse|r  search modes, cheapest first. Quantity to buy picks the cheapest stacks.",
    "|cffffd100Shopping / Crafting|r  paste a list or queue recipes: bags, bank, alts and guild bank are used first, the rest is bought after one confirmation. |cffffd100Profit?|r checks if a craft pays off.",
    "|cffffd100Deals|r  scan the whole AH daily; offers far below market or vendor value.",
    "|cffffd100Watchlist|r  (Deals tab) items you choose are re-checked while the auction house is open, at an interval you set; you are told when an offer appears under your price.",
    "|cffffd100Who crafts it|r  open each profession window once per crafter; the Crafting tab's crafter filter and tooltips show who can make each recipe (synced across accounts).",
    "|cffffd100Vendor items|r  (vials, thread...) open the vendor once per character; never bought above the vendor price.",
    "|cffffd100Stock|r  open your bank, guild bank and mailbox once in a while so they're recorded.",
    "|cffffd100Click-only servers|r  each click on Buy purchases every planned offer on the loaded page.",
    "|cffffd100Shift-click|r an item to put its name in the focused search box.",
    "",
    "|cffffd100Sync|r  invite one character of each other account in the Sync tab; accounts share their links, so three invitations link four accounts. The log there shows everything.",
    "",
    "/bh show  /bh minimap  /bh toggle  /bh reset  /bh guild  /bh autobuy",
    "",
    "|cff888888BargainHouse " .. ns.VERSION .. " for WoW 3.3.5a - by Anguish|r",
  }, "\n\n"))
  body:SetPoint("TOPLEFT", 16, -42)
  body:SetWidth(360)
  body:SetJustifyH("LEFT")
  body:SetJustifyV("TOP")

  UpdateCount()
  return f
end
