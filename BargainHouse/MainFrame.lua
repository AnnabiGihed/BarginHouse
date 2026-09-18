local ADDON, ns = ...
local C = ns.C

local TABS = { "Browse", "Shopping", "Crafting", "Deals", "Sell", "Auctions", "Settings", "Characters", "Sync" }
local SETTINGS_TAB = 7

function ns.CreateMain()
  local f = CreateFrame("Frame", "BargainHouseFrame", UIParent)
  ns.main = f
  ns.Size(f, 940, 600)
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  ns.Skin(f, C.bg, C.border)
  f:SetScale(ns.db.scale or 1)
  f:ClearAllPoints()
  local pos = ns.db.pos
  if pos then
    f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
  end
  tinsert(UISpecialFrames, f:GetName())

  -- Title bar ---------------------------------------------------------------
  local tb = CreateFrame("Frame", nil, f)
  tb:SetPoint("TOPLEFT", 1, -1)
  tb:SetPoint("TOPRIGHT", -1, -1)
  tb:SetHeight(36)
  local tbg = tb:CreateTexture(nil, "BACKGROUND")
  tbg:SetTexture(ns.WHITE)
  tbg:SetAllPoints()
  tbg:SetVertexColor(unpack(C.header))
  local line = tb:CreateTexture(nil, "ARTWORK")
  line:SetTexture(ns.WHITE)
  line:SetHeight(1)
  line:SetPoint("BOTTOMLEFT")
  line:SetPoint("BOTTOMRIGHT")
  line:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.45)

  tb:EnableMouse(true)
  tb:RegisterForDrag("LeftButton")
  tb:SetScript("OnDragStart", function() f:StartMoving() end)
  tb:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    local p, _, rp, x, y = f:GetPoint()
    ns.db.pos = { p, rp, x, y }
  end)

  local logo = tb:CreateTexture(nil, "ARTWORK")
  ns.Size(logo, 22, 22)
  logo:SetPoint("LEFT", 10, 0)
  logo:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
  logo:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  local title = ns.Text(tb, "BHFontTitle", ns.ACCENT .. "Bargain|rHouse")
  title:SetPoint("LEFT", logo, "RIGHT", 8, 0)

  -- Tabs
  f.tabs, f.pages = {}, {}
  local prev
  for i, name in ipairs(TABS) do
    local t = ns.Button(tb, name, 68, 34, "flat")
    if i == 1 then t:SetPoint("LEFT", 146, 0) else t:SetPoint("LEFT", prev, "RIGHT", 1, 0) end
    t.bar = t:CreateTexture(nil, "OVERLAY")
    t.bar:SetTexture(ns.WHITE)
    t.bar:SetHeight(2)
    t.bar:SetPoint("BOTTOMLEFT", 10, 0)
    t.bar:SetPoint("BOTTOMRIGHT", -10, 0)
    t.bar:SetVertexColor(unpack(C.accent))
    t.bar:Hide()
    t:SetScript("OnClick", function() f:SelectTab(i) end)
    f.tabs[i] = t
    if i == SETTINGS_TAB then t:Hide() else prev = t end
  end

  local close = ns.Button(tb, "X", 26, 24)
  close:SetPoint("RIGHT", -6, 0)
  close:SetScript("OnClick", function() f:Hide() end)

  local gear = ns.Button(tb, "", 26, 24)
  gear:SetPoint("RIGHT", close, "LEFT", -6, 0)
  gear.tooltip = "Settings"
  local gearIcon = gear:CreateTexture(nil, "ARTWORK")
  gearIcon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
  gearIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  ns.Size(gearIcon, 18, 18)
  gearIcon:SetPoint("CENTER")
  gear:SetScript("OnClick", function() f:SelectTab(f.current == SETTINGS_TAB and 1 or SETTINGS_TAB) end)
  f.gear = gear

  local blizz = ns.Button(tb, "Default", 60, 24)
  blizz:SetPoint("RIGHT", gear, "LEFT", -6, 0)
  blizz.tooltip = "Open Blizzard's auction house for this visit.\n(Bids and other rarely used features live there.)"
  blizz:SetScript("OnClick", function() ns.OpenBlizzard() end)

  local money = ns.Text(tb, "BHFontNormal", "", "RIGHT")
  money:SetPoint("RIGHT", blizz, "LEFT", -14, 0)
  local function UpdateMoney() money:SetText(ns.Money(GetMoney(), true)) end
  f:RegisterEvent("PLAYER_MONEY")
  f:SetScript("OnEvent", UpdateMoney)

  -- Pages -------------------------------------------------------------------
  local content = CreateFrame("Frame", nil, f)
  content:SetPoint("TOPLEFT", 10, -46)
  content:SetPoint("BOTTOMRIGHT", -10, 8)

  f.pages[1] = ns.Browse:Create(content)
  f.pages[2] = ns.Shopping:Create(content)
  f.pages[3] = ns.Crafting:Create(content)
  f.pages[4] = ns.DealsTab:Create(content)
  f.pages[5] = ns.Sell:Create(content)
  f.pages[6] = ns.Auctions:Create(content)
  f.pages[7] = ns.Settings:Create(content)
  f.pages[8] = ns.CharactersTab:Create(content)
  f.pages[9] = ns.SyncTab:Create(content)

  function f:SelectTab(index)
    ns.CloseMenu()
    for i, page in ipairs(self.pages) do
      local t = self.tabs[i]
      if i == index then
        page:Show()
        t.bar:Show()
        t:SetLabelColor(1, 1, 1)
      else
        page:Hide()
        t.bar:Hide()
        t:SetLabelColor(0.55, 0.57, 0.63)
      end
    end
    self.current = index
    f.gear:SetStyle(index == SETTINGS_TAB and "accent" or "normal")
  end
  f:SelectTab(1)

  -- Hide before wiring OnHide so creation doesn't close the auction house
  f:Hide()

  -- At an auctioneer: every tab. Anywhere else: only what works without the AH.
  local OFFLINE_TABS = { [2] = true, [3] = true, [8] = true, [9] = true }
  local awayText = ns.Text(tb, "BHFontSmall", "|cff888888Away from the auction house|r")
  f.awayText = awayText
  function f:SetMode(atAH)
    self.atAHMode = atAH
    local prev
    for i, t in ipairs(self.tabs) do
      if i ~= SETTINGS_TAB then
        if atAH or OFFLINE_TABS[i] then
          t:Show()
          t:ClearAllPoints()
          if prev then t:SetPoint("LEFT", prev, "RIGHT", 1, 0) else t:SetPoint("LEFT", 146, 0) end
          prev = t
        else
          t:Hide()
        end
      end
    end
    if atAH then
      blizz:Show()
      money:Show()
      awayText:Hide()
    else
      blizz:Hide()
      money:Show()
      awayText:ClearAllPoints()
      awayText:SetPoint("LEFT", prev, "RIGHT", 14, 0)
      awayText:Show()
      if self.current ~= SETTINGS_TAB and not OFFLINE_TABS[self.current or 1] then self:SelectTab(3) end
    end
    if ns.Crafting.UpdateMode then ns.Crafting:UpdateMode() end
    if ns.Shopping.UpdateMode then ns.Shopping:UpdateMode() end
    for _, panel in ipairs(ns.panels or {}) do
      if panel.UpdateSummary then panel:UpdateSummary() end
      -- lists checked away from the auction house get priced when you arrive
      if atAH and panel.Check and panel.entries[1] and panel.entries[1].state == "stock" and not panel.scanning then
        panel:Check(panel.entries)
      end
    end
  end

  f:SetScript("OnShow", function()
    UpdateMoney()
    PlaySound(ns.atAH and "AuctionWindowOpen" or "igCharacterInfoOpen")
  end)
  f:SetScript("OnHide", function()
    PlaySound(ns.atAH and "AuctionWindowClose" or "igCharacterInfoClose")
    ns.CloseMenu()
    ns.Browse:Disarm()
    if ns.Browse.queue then ns.Browse.queue:Stop("Stopped.") end
    for _, panel in ipairs(ns.panels or {}) do panel:StopAll("Stopped.") end
    if ns.FullScan.active then ns.FullScan:Stop() end
    ns.Scanner:Stop()
    ns.Sell:ClearSlot()
    if not ns.suppressClose and ns.atAH then
      CloseAuctionHouse()
    end
  end)
end
