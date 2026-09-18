local ADDON, ns = ...

-- Classic minimap-border button (no libraries needed on 3.3.5)
local RADIUS = 80

function ns.CreateMinimapButton()
  if ns.minimapButton or not Minimap then return end
  ns.db.minimap = ns.db.minimap or { angle = 200, hide = false }

  local b = CreateFrame("Button", "BargainHouseMinimapButton", Minimap)
  ns.minimapButton = b
  b:SetWidth(31)
  b:SetHeight(31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetWidth(20)
  bg:SetHeight(20)
  bg:SetPoint("TOPLEFT", 7, -5)

  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
  icon:SetWidth(20)
  icon:SetHeight(20)
  icon:SetPoint("TOPLEFT", 7, -5)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.icon = icon

  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetWidth(53)
  border:SetHeight(53)
  border:SetPoint("TOPLEFT")

  function b:UpdatePosition()
    local a = math.rad(ns.db.minimap.angle or 200)
    self:ClearAllPoints()
    self:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * RADIUS, math.sin(a) * RADIUS)
  end

  local function Dragging(self)
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    px, py = px / scale, py / scale
    ns.db.minimap.angle = math.deg(math.atan2(py - my, px - mx)) % 360
    self:UpdatePosition()
  end

  b:SetScript("OnDragStart", function(self)
    self.icon:SetTexCoord(0.12, 0.88, 0.12, 0.88)
    self:SetScript("OnUpdate", Dragging)
  end)
  b:SetScript("OnDragStop", function(self)
    self.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    self:SetScript("OnUpdate", nil)
  end)

  b:SetScript("OnClick", function(_, button)
    GameTooltip:Hide()
    if button == "RightButton" then
      ns.ToggleMain(7) -- settings
    else
      ns.ToggleMain()
    end
  end)

  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(ns.ACCENT .. "Bargain|rHouse")
    if ns.atAH then
      GameTooltip:AddLine("Auction house open", 0.4, 0.87, 0.53)
    else
      GameTooltip:AddLine("Crafting, materials and stock (auction features at an auctioneer)", 0.8, 0.8, 0.8, true)
    end
    if ns.Chars then
      local gold, n = ns.Chars:TotalGold()
      if n > 1 then GameTooltip:AddDoubleLine(n .. " characters", ns.Money(gold, true), 0.8, 0.8, 0.8, 1, 1, 1) end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(ns.ACCENT .. "Left-click|r  open / close", 1, 1, 1)
    GameTooltip:AddLine(ns.ACCENT .. "Right-click|r  settings", 1, 1, 1)
    GameTooltip:AddLine(ns.ACCENT .. "Drag|r  move around the minimap", 1, 1, 1)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)

  b:UpdatePosition()
  if ns.db.minimap.hide then b:Hide() else b:Show() end
end

function ns.ToggleMinimapButton()
  ns.db.minimap = ns.db.minimap or {}
  ns.db.minimap.hide = not ns.db.minimap.hide
  if not ns.minimapButton then ns.CreateMinimapButton() end
  if ns.db.minimap.hide then ns.minimapButton:Hide() else ns.minimapButton:Show() end
  ns.Print("Minimap button " .. (ns.db.minimap.hide and "hidden" or "shown") .. ". (/bh minimap)")
end
