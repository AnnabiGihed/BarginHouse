local ADDON, ns = ...
local C = ns.C
local format = string.format

local T = {}
ns.CharactersTab = T

StaticPopupDialogs["BARGAINHOUSE_REMOVE_CHAR"] = {
  text = "Remove %s from your characters?\n\nSync with it stops and the gold and professions it shared are forgotten.",
  button1 = YES,
  button2 = NO,
  OnAccept = function(self, data) T:Remove(data or self.data) end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
}

function T:Create(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  self.frame = f

  local title = ns.Text(f, "BHFontLarge", "Your characters")
  title:SetPoint("TOPLEFT", 4, -6)
  local hint = ns.Text(f, "BHFontSmall", "Characters on this account appear by themselves. Add your characters from other WoW accounts: while one is online, BargainHouse connects to it and shares professions, recipes, gold and auction scans. Add each other on both accounts.")
  hint:SetPoint("TOPLEFT", 4, -26)
  hint:SetWidth(900)
  hint:SetJustifyH("LEFT")

  local goSync = ns.Button(f, "Link accounts (Sync tab)", 190, 26, "accent")
  goSync:SetPoint("TOPLEFT", 0, -58)
  goSync:SetScript("OnClick", function() ns.main:SelectTab(9) end)

  local syncNow = ns.Button(f, "Sync now", 100, 26)
  syncNow:SetPoint("LEFT", goSync, "RIGHT", 6, 0)
  syncNow:SetScript("OnClick", function() ns.Sync:ConnectNow() end)

  local remove = ns.Button(f, "Forget character", 130, 26, "danger")
  remove:SetPoint("LEFT", syncNow, "RIGHT", 16, 0)
  remove.tooltip = "Forget the selected character (it comes back if its account shares it again)"
  remove:SetScript("OnClick", function()
    local r = T.selected
    if not r or r.playing then return end
    local d = StaticPopup_Show("BARGAINHOUSE_REMOVE_CHAR", r.name)
    if d then d.data = r.name end
  end)
  self.removeBtn = remove

  local status = ns.Text(f, "BHFontSmall", "")
  status:SetPoint("TOPRIGHT", 0, -64)
  status:SetJustifyH("RIGHT")
  ns.Size(status, 250, 14)
  self.status = status

  local cols = {
    { text = "Character", w = 124, key = "name" },
    { text = "Account", w = 132, key = "accountText", font = "BHFontSmall" },
    { text = "Status", w = 100, key = "statusText", font = "BHFontSmall" },
    { text = "Lvl", w = 30, key = "level", j = "RIGHT" },
    { text = "Professions", w = 272, key = "profSort", font = "BHFontSmall" },
    { text = "Gold", w = 112, key = "money", j = "RIGHT" },
    { text = "Updated", w = 70, key = "t", j = "RIGHT", font = "BHFontSmall" },
  }
  local list = ns.List(f, "BargainHouseCharList", 920, 406, 24, cols)
  list:SetPoint("TOPLEFT", 0, -92)
  list.emptyText = "No characters yet. Log in on your other characters once, or add characters from your other accounts above."
  list.sortKey, list.sortAsc = "money", false
  list.onSort = function(k)
    if list.sortKey == k then list.sortAsc = not list.sortAsc
    else list.sortKey, list.sortAsc = k, (k == "name" or k == "accountText") end
    T:Refresh()
  end
  list.update = function(r, row)
    local cc = row.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[row.class]
    local color = cc and format("|cff%02x%02x%02x", cc.r * 255, cc.g * 255, cc.b * 255) or "|cffdddddd"
    r.cols[1]:SetText(color .. row.name .. "|r")
    r.cols[2]:SetText(row.accountText)
    r.cols[3]:SetText(row.statusText)
    r.cols[4]:SetText(row.level and row.level > 0 and row.level or "")
    r.cols[5]:SetText(row.profDisplay)
    r.cols[6]:SetText(row.money and ns.Money(row.playing and GetMoney() or row.money, true) or "|cff555555--|r")
    r.cols[7]:SetText(row.playing and "now" or (row.t and ns.TimeAgo(time() - row.t) or ""))
  end
  list.onClick = function(row, button)
    T.selected = row
    list.selected = row
    list:Refresh()
    ns.Enable(T.removeBtn, not row.playing)
    if button == "RightButton" and row.listed then
      local d = StaticPopup_Show("BARGAINHOUSE_REMOVE_CHAR", row.name)
      if d then d.data = row.name end
    end
  end
  list.onEnter = function(row, r)
    GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
    GameTooltip:SetText(row.name, 1, 1, 1)
    for _, p in ipairs(ns.ParseProfText(row.profText)) do
      GameTooltip:AddDoubleLine(p.name, format("%d / %d", p.rank, p.max), 0.9, 0.9, 0.9, 1, 1, 1)
    end
    local crafts = T:RecipeCount(row.name)
    if crafts > 0 then GameTooltip:AddLine(format("%d recorded recipes", crafts), 0.4, 0.87, 0.53) end
    if row.account == "remote" and not row.waiting then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("Shared by " .. (row.via or "?"), 0.7, 0.7, 0.7)
    end
    if row.listed and not row.online then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("Not connected? Both characters must be online with this BargainHouse version, and each must be in the other's Characters tab. Type /bh sync debug on both to see the messages.", 1, 0.67, 0.2, true)
    end
    if row.listed then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(ns.ACCENT .. "Right-click|r remove from your characters", 0.8, 0.8, 0.8)
    end
    GameTooltip:Show()
  end
  self.list = list

  -- total gold
  local bar = CreateFrame("Frame", nil, f)
  ns.Size(bar, 920, 42)
  bar:SetPoint("BOTTOMLEFT")
  ns.Skin(bar, C.panel)
  local total = ns.Text(bar, "BHFontTitle", "")
  total:SetPoint("LEFT", 14, 0)
  ns.Size(total, 600, 22)
  self.total = total
  local credit = ns.Text(bar, "BHFontSmall", "BargainHouse by Anguish", "RIGHT")
  credit:SetPoint("RIGHT", -14, 0)
  ns.Size(credit, 250, 14)

  f:SetScript("OnShow", function() T:Refresh() end)
  local acc = 0
  f:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc > 2 then acc = 0; T:Refresh() end
  end)
  ns.Enable(remove, false)
  return f
end

function T:RecipeCount(name)
  local n = 0
  for _, book in pairs(ns.db.recipes or {}) do
    for _, rec in pairs(book) do
      if rec.k and rec.k[name] then n = n + 1 end
    end
  end
  return n
end

function T:Refresh()
  if not self.list then return end
  local rows = ns.Chars:All()
  for _, row in ipairs(rows) do
    if row.account == "local" then
      row.accountText = "|cffddddddThis account|r"
    elseif row.via and strlower(row.via) ~= strlower(row.name) then
      row.accountText = "|cffc79cffOther account|r |cff888888(" .. row.via .. ")|r"
    else
      row.accountText = "|cffc79cffOther account|r"
    end
    if row.playing then row.statusText = "|cff66dd88Playing|r"
    elseif row.listed and row.online then
      local s = ns.Sync.sessions[strlower(row.name)]
      row.statusText = "|cff66dd88Connected|r" .. ((s and s.channel == "GUILD") and " |cff888888(guild)|r" or "")
    elseif row.online then
      local s = ns.Sync.sessions[strlower(row.name)]
      row.statusText = "|cff66dd88Connected|r" .. ((s and s.channel == "GUILD") and " |cff888888(guild)|r" or "")
    elseif row.listed and not ns.db.syncEnabled then row.statusText = "|cff888888Sync off|r"
    elseif row.listed and row.waiting then row.statusText = "|cffffaa33Not connected yet|r"
    elseif row.listed then row.statusText = "|cff888888Not connected|r"
    else row.statusText = "|cff888888Offline|r" end
    local profs = ns.ParseProfText(row.profText)
    local parts = {}
    for _, p in ipairs(profs) do parts[#parts + 1] = format("%s |cff888888%d|r", p.name, p.rank) end
    row.profDisplay = #parts > 0 and table.concat(parts, ", ") or (row.waiting and "|cff888888waiting for first connection|r" or "")
    row.profSort = profs[1] and profs[1].name or "~"
    if self.selected and self.selected.name == row.name then self.selected = row end
  end

  local key, asc = self.list.sortKey, self.list.sortAsc
  table.sort(rows, function(a, b)
    local va, vb = a[key], b[key]
    if key == "money" then va, vb = a.money or -1, b.money or -1 end
    if key == "t" or key == "level" then va, vb = a[key] or 0, b[key] or 0 end
    if type(va) ~= type(vb) or va == nil then va, vb = tostring(va or ""), tostring(vb or "") end
    if va == vb then return a.name < b.name end
    if asc then return va < vb end
    return va > vb
  end)
  self.rows = rows
  self.list.selected = self.selected
  self.list:SetData(rows, true)

  local gold, n = ns.Chars:TotalGold()
  self.total:SetText(format("Total gold  %s  |cff888888across %d character%s|r", ns.Money(gold, true), n, n == 1 and "" or "s"))

  local connected, listed = 0, 0
  for _, name in pairs(ns.Sync:Partners()) do
    listed = listed + 1
    if ns.Sync:IsOnline(name) then connected = connected + 1 end
  end
  if listed > 0 then
    self.status:SetText(format("%d of %d listed character%s connected", connected, listed, listed == 1 and "" or "s"))
  else
    self.status:SetText("")
  end
end

function T:Add()
  local name = strtrim(self.nameBox:GetText() or "")
  if name == "" then return end
  name = name:sub(1, 1):upper() .. name:sub(2):lower()
  if strlower(name) == strlower(UnitName("player") or "") then
    self.status:SetText("|cffff5555That's the character you're playing.|r")
    return
  end
  if ns.Chars:IsLocal(name) then
    self.status:SetText("|cffffaa33" .. name .. " is on this account and already listed.|r")
    return
  end
  if not ns.Sync:IsTrusted(name) then
    local list = ns.db.syncPartners or ""
    ns.db.syncPartners = (list:match("%S") and (list .. ", ") or "") .. name
  end
  self.nameBox:SetTextSilent("")
  self.nameBox:ClearFocus()
  ns.Sync:ConnectNow()
  self.status:SetText("Added " .. name .. ". Add your name on that account too.")
  self:Refresh()
end

function T:Remove(name)
  if not name then return end
  ns.Chars:ForgetRemote(name)
  local realm = ns.db.inventory and ns.db.inventory[GetRealmName() or "?"]
  if realm and realm[name] and name ~= UnitName("player") then realm[name] = nil end
  self.selected = nil
  ns.Enable(self.removeBtn, false)
  self:Refresh()
end
