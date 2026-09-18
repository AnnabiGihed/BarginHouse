local ADDON, ns = ...
local C = ns.C

local L = {}
ns.Shopping = L

---------------------------------------------------------------------------
-- Parsing
---------------------------------------------------------------------------
local function Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- Accepts "20x Rough Stone", "20 x Rough Stone", "20 Rough Stone",
-- "Rough Stone x20", "Rough Stone: 20", shift-clicked item links and bullets.
function ns.ParseShoppingList(text)
  local list, byName = {}, {}
  for raw in (text or ""):gmatch("[^\r\n]+") do
    local line = raw:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", "")
    line = Trim(line:gsub("^[%-%*%s]+", ""))
    local qty, name
    qty, name = line:match("^(%d+)%s*[xX%*]%s*(.+)$")
    if not qty then name, qty = line:match("^(.-)%s*[xX%*:]%s*(%d+)$") end
    if not qty then qty, name = line:match("^(%d+)%s+(.+)$") end
    if not qty then name, qty = line, 1 end
    if name then
      name = Trim((name:gsub("^%[(.-)%]$", "%1")))
      qty = tonumber(qty) or 1
      if name ~= "" and qty > 0 then
        local key = strlower(name)
        local e = byName[key]
        if e then
          e.need = e.need + qty
        else
          e = { name = name, need = qty }
          byName[key] = e
          list[#list + 1] = e
        end
      end
    end
  end
  return list
end

function L:Create(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  self.frame = f

  -- Left: the list -----------------------------------------------------------
  local left = CreateFrame("Frame", nil, f)
  ns.Size(left, 290, 546)
  left:SetPoint("TOPLEFT")
  ns.Skin(left, C.panel)

  local title = ns.Text(left, "BHFontLarge", "Shopping list")
  title:SetPoint("TOPLEFT", 12, -12)
  local hint = ns.Text(left, "BHFontSmall", "One item per line, e.g.  20x Copper Bar")
  hint:SetPoint("TOPLEFT", 12, -30)

  local boxBg = CreateFrame("Frame", nil, left)
  boxBg:SetPoint("TOPLEFT", 10, -48)
  ns.Size(boxBg, 270, 400)
  ns.Skin(boxBg, C.input)
  boxBg:EnableMouse(true)

  local sf = CreateFrame("ScrollFrame", "BargainHouseShopScroll", boxBg, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 6, -6)
  sf:SetPoint("BOTTOMRIGHT", -18, 6)
  local sb = _G["BargainHouseShopScrollScrollBar"]
  if sb then
    sb:ClearAllPoints()
    sb:SetPoint("TOPRIGHT", boxBg, "TOPRIGHT", -4, -4)
    sb:SetPoint("BOTTOMRIGHT", boxBg, "BOTTOMRIGHT", -4, 4)
    sb:SetWidth(6)
    local up, down = _G["BargainHouseShopScrollScrollBarScrollUpButton"], _G["BargainHouseShopScrollScrollBarScrollDownButton"]
    if up then up:SetAlpha(0) end
    if down then down:SetAlpha(0) end
    local thumb = sb:GetThumbTexture()
    if thumb then
      thumb:SetTexture(ns.WHITE)
      thumb:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.7)
      ns.Size(thumb, 6, 40)
    end
  end

  local eb = CreateFrame("EditBox", nil, sf)
  eb:SetMultiLine(true)
  eb:SetAutoFocus(false)
  eb:SetMaxLetters(20000)
  eb:SetFontObject("BHFontNormal")
  eb:SetWidth(240)
  eb:SetHeight(384)
  eb:SetText(ns.db.shoppingText or "")
  sf:SetScrollChild(eb)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  eb.acceptsLinks = "insert"
  eb:SetScript("OnEditFocusGained", function(self)
    ns.focusedBox = self
    boxBg:SetBackdropBorderColor(unpack(C.accent))
  end)
  eb:SetScript("OnEditFocusLost", function(self)
    if ns.focusedBox == self then ns.focusedBox = nil end
    boxBg:SetBackdropBorderColor(unpack(C.border))
  end)
  eb:SetScript("OnTextChanged", function(self)
    ns.db.shoppingText = self:GetText()
    if ScrollingEdit_OnTextChanged then ScrollingEdit_OnTextChanged(self, sf) end
  end)
  if ScrollingEdit_OnCursorChanged then eb:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged) end
  if ScrollingEdit_OnUpdate then
    eb:SetScript("OnUpdate", function(self, elapsed) ScrollingEdit_OnUpdate(self, elapsed, sf) end)
  end
  boxBg:SetScript("OnMouseDown", function() eb:SetFocus() end)
  self.editBox = eb

  local clear = ns.Button(left, "Clear", 80, 26)
  clear:SetPoint("TOPLEFT", 10, -462)
  clear:SetScript("OnClick", function()
    eb:SetText("")
    L.panel:Clear()
  end)

  local check = ns.Button(left, "Check & price list", 184, 26, "accent")
  check:SetPoint("LEFT", clear, "RIGHT", 6, 0)
  check:SetScript("OnClick", function()
    if L.panel.scanning then L.panel:StopScan() else L:CheckList() end
  end)
  self.checkBtn = check

  local mailNote = ns.Text(left, "BHFontSmall", "Purchases arrive in your mailbox.", "CENTER")
  mailNote:SetPoint("BOTTOM", 0, 14)
  ns.Size(mailNote, 270, 14)

  self.panel = ns.MaterialsPanel(f, "Shop", {
    emptyText = "Paste your list on the left, then press 'Check & price list'.\n\nClick a row to skip / include it.   Right-click to open it in Browse.",
    confirmText = function() return "your shopping list" end,
    onScanState = function(on)
      check:SetText(on and "Stop" or (ns.atAH and "Check & price list" or "Check list"))
      check:SetStyle(on and "danger" or "accent")
    end,
  })
  return f
end

function L:UpdateMode()
  if self.checkBtn and not self.panel.scanning then
    self.checkBtn:SetText(ns.atAH and "Check & price list" or "Check list")
  end
end

function L:CheckList()
  local parsed = ns.ParseShoppingList(self.editBox:GetText())
  self.editBox:ClearFocus()
  if #parsed == 0 then
    self.panel.status:SetText("|cffff5555The list is empty.|r")
    return
  end
  self.panel:Check(parsed)
end
