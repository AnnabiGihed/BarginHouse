local ADDON, ns = ...

local C = {
  bg       = { 0.055, 0.058, 0.075, 0.97 },
  panel    = { 0.085, 0.09, 0.115, 1 },
  header   = { 0.115, 0.12, 0.15, 1 },
  input    = { 0.03, 0.032, 0.042, 1 },
  button   = { 0.145, 0.15, 0.185, 1 },
  border   = { 0.2, 0.21, 0.26, 1 },
  accent   = { 0.2, 0.85, 0.6, 1 },
  accentBg = { 0.07, 0.34, 0.25, 1 },
  goldBg   = { 0.47, 0.34, 0.04, 1 },
  dangerBg = { 0.42, 0.1, 0.1, 1 },
  clear    = { 0, 0, 0, 0 },
}
ns.C = C

local WHITE = "Interface\\Buttons\\WHITE8X8"
ns.WHITE = WHITE
local BACKDROP = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, insets = { left = 0, right = 0, top = 0, bottom = 0 } }

---------------------------------------------------------------------------
-- Fonts
---------------------------------------------------------------------------
local function MakeFont(name, path, size, r, g, b)
  local f = CreateFont(name)
  f:SetFont(path, size)
  f:SetTextColor(r, g, b)
  f:SetShadowColor(0, 0, 0, 1)
  f:SetShadowOffset(1, -1)
end
MakeFont("BHFontNormal", "Fonts\\ARIALN.TTF", 13, 0.9, 0.9, 0.92)
MakeFont("BHFontSmall", "Fonts\\ARIALN.TTF", 12, 0.6, 0.62, 0.68)
MakeFont("BHFontBold", "Fonts\\FRIZQT__.TTF", 11, 1, 1, 1)
MakeFont("BHFontLarge", "Fonts\\FRIZQT__.TTF", 13, 1, 1, 1)
MakeFont("BHFontTitle", "Fonts\\FRIZQT__.TTF", 16, 1, 1, 1)

---------------------------------------------------------------------------
-- Basics
---------------------------------------------------------------------------
function ns.Size(f, w, h)
  f:SetWidth(w)
  f:SetHeight(h)
end

function ns.Skin(f, bg, border)
  f:SetBackdrop(BACKDROP)
  f:SetBackdropColor(unpack(bg or C.panel))
  f:SetBackdropBorderColor(unpack(border or C.border))
end

function ns.Text(parent, font, text, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFontObject(font or "BHFontNormal")
  fs:SetJustifyH(justify or "LEFT")
  fs:SetText(text or "")
  return fs
end

---------------------------------------------------------------------------
-- Button
---------------------------------------------------------------------------
local STYLES = { normal = C.button, accent = C.accentBg, gold = C.goldBg, danger = C.dangerBg, flat = C.clear }

function ns.Button(parent, text, w, h, style)
  local b = CreateFrame("Button", nil, parent)
  ns.Size(b, w, h)
  b:SetBackdrop(BACKDROP)
  b.label = b:CreateFontString(nil, "OVERLAY")
  b.label:SetFontObject("BHFontBold")
  b.label:SetPoint("CENTER")
  b.label:SetText(text or "")

  function b:SetStyle(s)
    self.style = s or "normal"
    self:SetBackdropColor(unpack(STYLES[self.style] or C.button))
    self:SetBackdropBorderColor(unpack(self.style == "flat" and C.clear or C.border))
  end
  function b:SetText(t) self.label:SetText(t) end
  function b:SetLabelColor(r, g, bl)
    self.labelColor = { r, g, bl }
    self.label:SetTextColor(r, g, bl)
  end
  b:SetStyle(style)

  b:SetScript("OnEnter", function(self)
    if self:IsEnabled() then
      if self.style == "flat" then self.label:SetTextColor(1, 1, 1)
      else self:SetBackdropBorderColor(unpack(C.accent)) end
    end
    if self.tooltip then
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(self.tooltip, 1, 1, 1, 1, true)
      GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave", function(self)
    if self.style == "flat" then
      local c = self.labelColor
      if c then self.label:SetTextColor(c[1], c[2], c[3]) else self.label:SetTextColor(1, 1, 1) end
    else
      self:SetBackdropBorderColor(unpack(C.border))
    end
    GameTooltip:Hide()
  end)
  b:SetScript("OnDisable", function(self)
    self.label:SetTextColor(0.45, 0.45, 0.48)
    if self.style ~= "flat" then
      self:SetBackdropColor(C.button[1], C.button[2], C.button[3], 0.6)
      self:SetBackdropBorderColor(unpack(C.border))
    end
  end)
  b:SetScript("OnEnable", function(self)
    local c = self.labelColor
    if c then self.label:SetTextColor(c[1], c[2], c[3]) else self.label:SetTextColor(1, 1, 1) end
    self:SetStyle(self.style)
  end)
  return b
end

function ns.Enable(b, on)
  if on then b:Enable() else b:Disable() end
end

---------------------------------------------------------------------------
-- EditBox
---------------------------------------------------------------------------
function ns.EditBox(parent, w, h, placeholder, numeric)
  local e = CreateFrame("EditBox", nil, parent)
  ns.Size(e, w, h)
  ns.Skin(e, C.input)
  e:SetFontObject("BHFontNormal")
  e:SetTextInsets(7, 7, 0, 0)
  e:SetAutoFocus(false)
  if numeric then e:SetNumeric(true) end

  if placeholder then
    e.ph = ns.Text(e, "BHFontSmall", placeholder)
    e.ph:SetPoint("LEFT", 8, 0)
  end
  local function UpdatePH(self)
    if self.ph then
      if self:GetText() == "" and not self.focused then self.ph:Show() else self.ph:Hide() end
    end
  end

  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    if self.onEnter then self.onEnter(self) end
  end)
  e:SetScript("OnTabPressed", function(self)
    if self.nextBox then self.nextBox:SetFocus() end
  end)
  e:SetScript("OnEditFocusGained", function(self)
    self.focused = true
    ns.focusedBox = self
    self:SetBackdropBorderColor(unpack(C.accent))
    self:HighlightText()
    UpdatePH(self)
  end)
  e:SetScript("OnEditFocusLost", function(self)
    self.focused = false
    if ns.focusedBox == self then ns.focusedBox = nil end
    self:SetBackdropBorderColor(unpack(C.border))
    self:HighlightText(0, 0)
    UpdatePH(self)
  end)
  e:SetScript("OnTextChanged", function(self)
    UpdatePH(self)
    if self.onChange and not self.lock then self.onChange(self) end
  end)
  function e:SetTextSilent(t)
    self.lock = true
    self:SetText(t or "")
    self.lock = false
  end
  return e
end

---------------------------------------------------------------------------
-- Checkbox
---------------------------------------------------------------------------
function ns.Check(parent, label, onClick)
  local c = CreateFrame("CheckButton", nil, parent)
  ns.Size(c, 16, 16)
  ns.Skin(c, C.input)
  c:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  c.label = ns.Text(c, "BHFontNormal", label)
  c.label:SetPoint("LEFT", c, "RIGHT", 5, 0)
  c:SetHitRectInsets(0, -(c.label:GetStringWidth() + 8), 0, 0)
  c:SetScript("OnClick", function(self)
    if onClick then onClick(self, self:GetChecked() and true or false) end
  end)
  c:SetScript("OnEnter", function(self)
    self:SetBackdropBorderColor(unpack(C.accent))
    if self.tooltip then
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(self.tooltip, 1, 1, 1, 1, true)
      GameTooltip:Show()
    end
  end)
  c:SetScript("OnLeave", function(self)
    self:SetBackdropBorderColor(unpack(C.border))
    GameTooltip:Hide()
  end)
  return c
end

---------------------------------------------------------------------------
-- Popup menu (shared)
---------------------------------------------------------------------------
local menu
local ROW_H = 20

local function BuildMenu()
  menu = CreateFrame("Frame", "BargainHouseMenu", UIParent)
  menu:SetFrameStrata("FULLSCREEN_DIALOG")
  menu:SetClampedToScreen(true)
  ns.Skin(menu, C.bg, C.accent)
  menu:EnableMouse(true)
  menu:EnableMouseWheel(true)
  menu:Hide()
  menu.rows, menu.items, menu.offset, menu.maxRows = {}, {}, 0, 18

  local catcher = CreateFrame("Button", nil, UIParent)
  catcher:SetAllPoints(UIParent)
  catcher:SetFrameStrata("FULLSCREEN")
  catcher:RegisterForClicks("AnyUp")
  catcher:Hide()
  catcher:SetScript("OnClick", function() menu:Hide() end)

  menu:SetScript("OnShow", function() catcher:Show() end)
  menu:SetScript("OnHide", function() catcher:Hide() menu.owner = nil end)
  menu:SetScript("OnMouseWheel", function(self, delta)
    local maxOff = math.max(0, #self.items - self.maxRows)
    self.offset = math.min(maxOff, math.max(0, self.offset - delta))
    self:Render()
  end)

  function menu:Render()
    local shown = math.min(#self.items, self.maxRows)
    for i = 1, shown do
      local r = self.rows[i]
      if not r then
        r = CreateFrame("Button", nil, self)
        r:SetHeight(ROW_H)
        r:SetPoint("TOPLEFT", 2, -2 - (i - 1) * ROW_H)
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetTexture(WHITE)
        hl:SetAllPoints()
        hl:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.2)
        r.text = ns.Text(r, "BHFontNormal", "")
        r.text:SetPoint("LEFT", 8, 0)
        r.text:SetPoint("RIGHT", -8, 0)
        r:SetScript("OnClick", function(btn, button)
          local it = btn.it
          if not it or it.disabled then return end
          local fn = menu.onPick
          menu:Hide()
          if fn then fn(it.value, button, it) end
        end)
        self.rows[i] = r
      end
      local it = self.items[i + self.offset]
      r.it = it
      r:SetWidth(self:GetWidth() - 4)
      if it.disabled then
        r.text:SetText("|cff808080" .. (it.text or "") .. "|r")
      elseif self.selected ~= nil and it.value == self.selected then
        r.text:SetText(ns.ACCENT .. (it.text or "") .. "|r")
      else
        r.text:SetText(it.text or "")
      end
      r:Show()
    end
    for i = shown + 1, #self.rows do self.rows[i]:Hide() end
    self:SetHeight(shown * ROW_H + 4)
  end
end

function ns.OpenMenu(owner, items, onPick, selected, width)
  if not menu then BuildMenu() end
  if menu:IsShown() and menu.owner == owner then
    menu:Hide()
    return
  end
  menu.items, menu.onPick, menu.selected, menu.offset = items, onPick, selected, 0
  if selected ~= nil then
    for i, it in ipairs(items) do
      if it.value == selected and i > menu.maxRows then
        menu.offset = math.min(i - 1, #items - menu.maxRows)
      end
    end
  end
  menu:SetScale(owner:GetEffectiveScale() / UIParent:GetEffectiveScale())
  menu:SetWidth(math.max(width or 0, owner:GetWidth()))
  menu:ClearAllPoints()
  menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
  menu:Show()
  menu.owner = owner
  menu:Render()
end

function ns.CloseMenu()
  if menu then menu:Hide() end
end

---------------------------------------------------------------------------
-- Dropdown
---------------------------------------------------------------------------
function ns.Dropdown(parent, w, h, onSelect)
  local d = ns.Button(parent, "", w, h)
  d.label:ClearAllPoints()
  d.label:SetPoint("LEFT", 8, 0)
  d.label:SetPoint("RIGHT", -20, 0)
  d.label:SetJustifyH("LEFT")
  d.label:SetFontObject("BHFontNormal")

  local arrow = d:CreateTexture(nil, "OVERLAY")
  arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
  ns.Size(arrow, 18, 18)
  arrow:SetPoint("RIGHT", -2, 0)

  d.items = {}
  function d:SetItems(items) self.items = items end
  function d:SetValue(v, silent)
    self.value = v
    for _, it in ipairs(self.items) do
      if it.value == v then self.label:SetText(it.text) end
    end
    if not silent and onSelect then onSelect(v) end
  end
  d:SetScript("OnClick", function(self)
    ns.OpenMenu(self, self.items, function(v) self:SetValue(v) end, self.value)
  end)
  return d
end

---------------------------------------------------------------------------
-- Money input (gold / silver / copper)
---------------------------------------------------------------------------
function ns.MoneyInput(parent, onChange)
  local f = CreateFrame("Frame", nil, parent)
  ns.Size(f, 172, 22)

  local function Unit(w, icon, anchor)
    local e = ns.EditBox(f, w, 22, nil, true)
    e:SetJustifyH("RIGHT")
    if anchor then e:SetPoint("LEFT", anchor, "RIGHT", 18, 0) else e:SetPoint("LEFT") end
    local tex = f:CreateTexture(nil, "OVERLAY")
    ns.Size(tex, 13, 13)
    tex:SetTexture(icon)
    tex:SetPoint("LEFT", e, "RIGHT", 3, 0)
    return e
  end
  local g = Unit(60, ns.GOLD_ICON)
  local s = Unit(30, ns.SILVER_ICON, g)
  local c = Unit(30, ns.COPPER_ICON, s)
  g:SetMaxLetters(6)
  s:SetMaxLetters(2)
  c:SetMaxLetters(2)
  g.nextBox, s.nextBox, c.nextBox = s, c, g
  f.g, f.s, f.c = g, s, c

  function f:GetCopper()
    return (tonumber(g:GetText()) or 0) * 10000 + (tonumber(s:GetText()) or 0) * 100 + (tonumber(c:GetText()) or 0)
  end
  function f:SetCopper(v)
    v = math.floor(math.max(0, v or 0))
    local gold = math.floor(v / 10000)
    g:SetTextSilent(gold > 0 and gold or "")
    s:SetTextSilent(math.floor(v / 100) % 100)
    c:SetTextSilent(v % 100)
  end
  local function Changed()
    if onChange then onChange(f:GetCopper()) end
  end
  g.onChange, s.onChange, c.onChange = Changed, Changed, Changed
  g.onEnter = function() if f.onEnter then f.onEnter() end end
  s.onEnter, c.onEnter = g.onEnter, g.onEnter
  return f
end

---------------------------------------------------------------------------
-- Progress bar
---------------------------------------------------------------------------
function ns.Progress(parent, w, h)
  local bar = CreateFrame("StatusBar", nil, parent)
  ns.Size(bar, w, h)
  bar:SetStatusBarTexture(WHITE)
  bar:SetStatusBarColor(unpack(C.accent))
  bar:SetMinMaxValues(0, 1)
  bar:SetValue(0)
  local bg = bar:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture(WHITE)
  bg:SetAllPoints()
  bg:SetVertexColor(1, 1, 1, 0.06)
  return bar
end

---------------------------------------------------------------------------
-- Virtual scrolling list with sortable column headers
-- cols = { { text=, w=, key=, j= }, ... }
---------------------------------------------------------------------------
function ns.List(parent, name, width, height, rowH, cols, useIcon)
  local l = CreateFrame("Frame", name, parent)
  ns.Size(l, width, height)
  ns.Skin(l, C.panel)
  l.data, l.rows = {}, {}
  local HEADER_H = 22

  local hbg = l:CreateTexture(nil, "BORDER")
  hbg:SetTexture(WHITE)
  hbg:SetVertexColor(unpack(C.header))
  hbg:SetPoint("TOPLEFT", 1, -1)
  hbg:SetPoint("TOPRIGHT", -1, -1)
  hbg:SetHeight(HEADER_H - 1)

  -- headers
  local x = 8 + (useIcon and (rowH + 2) or 0)
  l.headers = {}
  for i, col in ipairs(cols) do
    col.x = x
    local hb = CreateFrame("Button", nil, l)
    ns.Size(hb, col.w, HEADER_H)
    hb:SetPoint("TOPLEFT", x, 0)
    hb.fs = ns.Text(hb, "BHFontSmall", col.text, col.j)
    hb.fs:SetAllPoints()
    hb.arrow = hb:CreateTexture(nil, "OVERLAY")
    hb.arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
    ns.Size(hb.arrow, 9, 8)
    if col.j == "RIGHT" then hb.arrow:SetPoint("LEFT", hb, "LEFT", -2, 0)
    else hb.arrow:SetPoint("RIGHT", hb, "RIGHT", 0, 0) end
    hb.arrow:Hide()
    hb.col = col
    if col.key then
      hb:SetScript("OnClick", function()
        if l.onSort then l.onSort(col.key) end
      end)
      hb:SetScript("OnEnter", function(self) self.fs:SetTextColor(1, 1, 1) end)
      hb:SetScript("OnLeave", function() l:UpdateHeaders() end)
    end
    l.headers[i] = hb
    x = x + col.w + 6
  end

  function l:UpdateHeaders()
    for _, hb in ipairs(self.headers) do
      if hb.col.key and hb.col.key == self.sortKey then
        hb.fs:SetTextColor(unpack(C.accent))
        hb.arrow:Show()
        if self.sortAsc then hb.arrow:SetTexCoord(0, 0.5625, 1, 0) else hb.arrow:SetTexCoord(0, 0.5625, 0, 1) end
      else
        hb.fs:SetTextColor(0.6, 0.62, 0.68)
        hb.arrow:Hide()
      end
    end
  end

  -- scroll frame
  local numRows = math.floor((height - HEADER_H - 2) / rowH)
  local sf = CreateFrame("ScrollFrame", name .. "Scroll", l, "FauxScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 0, -HEADER_H)
  sf:SetPoint("BOTTOMRIGHT", -12, 1)
  sf:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, rowH, function() l:Refresh() end)
  end)

  local sb = _G[name .. "ScrollScrollBar"]
  if sb then
    sb:ClearAllPoints()
    sb:SetPoint("TOPRIGHT", l, "TOPRIGHT", -3, -HEADER_H - 3)
    sb:SetPoint("BOTTOMRIGHT", l, "BOTTOMRIGHT", -3, 3)
    sb:SetWidth(6)
    local up, down = _G[name .. "ScrollScrollBarScrollUpButton"], _G[name .. "ScrollScrollBarScrollDownButton"]
    if up then up:Hide() end
    if down then down:Hide() end
    local thumb = sb:GetThumbTexture()
    if thumb then
      thumb:SetTexture(WHITE)
      thumb:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.7)
      ns.Size(thumb, 6, 40)
    end
    local track = sb:CreateTexture(nil, "BACKGROUND")
    track:SetTexture(WHITE)
    track:SetAllPoints()
    track:SetVertexColor(1, 1, 1, 0.04)
  end
  l.scrollBar = sb

  l:EnableMouseWheel(true)
  l:SetScript("OnMouseWheel", function(_, delta)
    if sf:IsShown() then ScrollFrameTemplate_OnMouseWheel(sf, delta) end
  end)

  -- rows
  for i = 1, numRows do
    local r = CreateFrame("Button", nil, l)
    ns.Size(r, width - 16, rowH)
    r:SetPoint("TOPLEFT", 2, -HEADER_H - (i - 1) * rowH)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    if i % 2 == 0 then
      local stripe = r:CreateTexture(nil, "BACKGROUND")
      stripe:SetTexture(WHITE)
      stripe:SetAllPoints()
      stripe:SetVertexColor(1, 1, 1, 0.025)
    end
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture(WHITE)
    hl:SetAllPoints()
    hl:SetVertexColor(1, 1, 1, 0.07)

    r.sel = r:CreateTexture(nil, "BORDER")
    r.sel:SetTexture(WHITE)
    r.sel:SetAllPoints()
    r.sel:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.15)
    r.selBar = r:CreateTexture(nil, "ARTWORK")
    r.selBar:SetTexture(WHITE)
    r.selBar:SetWidth(2)
    r.selBar:SetPoint("TOPLEFT")
    r.selBar:SetPoint("BOTTOMLEFT")
    r.selBar:SetVertexColor(unpack(C.accent))

    if useIcon then
      r.icon = r:CreateTexture(nil, "ARTWORK")
      ns.Size(r.icon, rowH - 4, rowH - 4)
      r.icon:SetPoint("LEFT", 6, 0)
      r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    r.cols = {}
    for c, col in ipairs(cols) do
      local fs = r:CreateFontString(nil, "OVERLAY")
      fs:SetFontObject(col.font or "BHFontNormal")
      ns.Size(fs, col.w, rowH)
      fs:SetPoint("LEFT", col.x - 2, 0)
      fs:SetJustifyH(col.j or "LEFT")
      r.cols[c] = fs
    end
    r:SetScript("OnClick", function(self, button)
      if self.item and l.onClick then l.onClick(self.item, button, self) end
    end)
    r:SetScript("OnEnter", function(self)
      if self.item and l.onEnter then l.onEnter(self.item, self) end
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    l.rows[i] = r
  end

  l.empty = ns.Text(l, "BHFontSmall", "", "CENTER")
  l.empty:SetPoint("CENTER", 0, -10)
  l.empty:SetWidth(width - 60)

  function l:SetData(data, keepScroll)
    self.data = data or {}
    if not keepScroll and sb then
      sf.offset = 0
      sb:SetValue(0)
    end
    self:Refresh()
  end

  function l:Refresh()
    local data = self.data
    FauxScrollFrame_Update(sf, #data, numRows, rowH)
    local offset = (#data > numRows) and FauxScrollFrame_GetOffset(sf) or 0
    for i = 1, numRows do
      local r, item = self.rows[i], data[i + offset]
      r.item = item
      if item then
        self.update(r, item)
        if (self.selected ~= nil and self.selected == item) or (self.marked and self.marked[item]) then
          r.sel:Show(); r.selBar:Show()
        else
          r.sel:Hide(); r.selBar:Hide()
        end
        r:Show()
      else
        r:Hide()
      end
    end
    if #data == 0 then
      self.empty:SetText(self.emptyText or "")
      self.empty:Show()
    else
      self.empty:Hide()
    end
    self:UpdateHeaders()
  end

  return l
end
