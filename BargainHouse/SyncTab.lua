local ADDON, ns = ...
local C = ns.C
local format = string.format

local T = {}
ns.SyncTab = T

StaticPopupDialogs["BARGAINHOUSE_UNLINK"] = {
  text = "Unlink this account?\n\n%s\n\nIt stops sharing with every character of that account.",
  button1 = YES,
  button2 = NO,
  OnAccept = function(self, data) ns.Sync:ForgetAccount(data or self.data) ; T:Refresh() end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
}

function T:Create(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  self.frame = f

  local title = ns.Text(f, "BHFontLarge", "Sync between your accounts")
  title:SetPoint("TOPLEFT", 4, -6)
  local hint = ns.Text(f, "BHFontSmall", "Invite one character of another account and accept the popup there. Linked accounts share their links, so with four accounts three invitations are enough - in any order. Professions, recipes, who can craft what, gold and auction scans are then kept in sync while characters are online.")
  hint:SetPoint("TOPLEFT", 4, -26)
  hint:SetWidth(900)
  hint:SetJustifyH("LEFT")

  local name = ns.EditBox(f, 200, 26, "Character on another account")
  name:SetPoint("TOPLEFT", 0, -62)
  name:SetMaxLetters(12)
  name.onEnter = function() T:DoInvite() end
  self.nameBox = name

  local invite = ns.Button(f, "Invite", 90, 26, "accent")
  invite:SetPoint("LEFT", name, "RIGHT", 6, 0)
  invite:SetScript("OnClick", function() T:DoInvite() end)

  local sync = ns.Button(f, "Sync now", 100, 26)
  sync:SetPoint("LEFT", invite, "RIGHT", 16, 0)
  sync.tooltip = "Contact your accounts and exchange anything that differs"
  sync:SetScript("OnClick", function() ns.Sync:ConnectNow() ; T:Refresh() end)

  local unlink = ns.Button(f, "Unlink", 80, 26, "danger")
  unlink:SetPoint("LEFT", sync, "RIGHT", 6, 0)
  unlink:SetScript("OnClick", function()
    local a = T.selected
    if not a then return end
    local d = StaticPopup_Show("BARGAINHOUSE_UNLINK", table.concat(a.names, ", "))
    if d then d.data = a.id end
  end)
  self.unlinkBtn = unlink

  local auto = ns.Check(f, "Sync automatically", function(_, on)
    ns.db.syncEnabled = on
    if on then ns.Sync:ConnectNow() end
  end)
  auto:SetPoint("LEFT", unlink, "RIGHT", 20, 0)
  auto:SetChecked(ns.db.syncEnabled)

  local verbose = ns.Check(f, "Detailed log", function(_, on) ns.db.syncVerbose = on end)
  verbose:SetPoint("LEFT", auto.label, "RIGHT", 16, 0)
  verbose:SetChecked(ns.db.syncVerbose)
  verbose.tooltip = "Log every message (useful when something doesn't connect)"

  -- linked accounts
  local acols = {
    { text = "Account", w = 250, key = "name" },
    { text = "Status", w = 120, key = "status", font = "BHFontSmall" },
  }
  local list = ns.List(f, "BargainHouseSyncAccounts", 420, 356, 22, acols)
  list:SetPoint("TOPLEFT", 0, -96)
  list.emptyText = "No other account linked yet.\n\nInvite a character of your other account above; accept the popup on that account."
  list.update = function(r, a)
    r.cols[1]:SetText(table.concat(a.names, ", "))
    if a.connected then r.cols[2]:SetText("|cff66dd88" .. a.connected .. "|r")
    elseif a.lastSeen then r.cols[2]:SetText("|cff888888last seen " .. ns.TimeAgo(time() - a.lastSeen) .. "|r")
    else r.cols[2]:SetText("|cff888888not connected|r") end
  end
  list.onClick = function(a)
    T.selected = a
    list.selected = a
    list:Refresh()
    ns.Enable(T.unlinkBtn, true)
  end
  self.list = list

  local progress = ns.Text(f, "BHFontSmall", "")
  progress:SetPoint("TOPLEFT", 0, -458)
  ns.Size(progress, 420, 14)
  self.progress = progress
  self.bar = ns.Progress(f, 420, 4)
  self.bar:SetPoint("TOPLEFT", 0, -476)

  -- log
  local logTitle = ns.Text(f, "BHFontLarge", "Log")
  logTitle:SetPoint("TOPLEFT", 436, -92)
  local logList = ns.List(f, "BargainHouseSyncLog", 484, 380, 20, {
    { text = "Time", w = 46, font = "BHFontSmall" },
    { text = "Event", w = 396, font = "BHFontSmall" },
  })
  logList:SetPoint("TOPLEFT", 436, -112)
  logList.emptyText = "Nothing yet."
  logList.update = function(r, e)
    r.cols[1]:SetText("|cff888888" .. date("%H:%M:%S", e.t):sub(1, 5) .. "|r")
    r.cols[2]:SetText(e.text)
  end
  self.logList = logList

  local clear = ns.Button(f, "Clear log", 90, 22)
  clear:SetPoint("TOPRIGHT", 0, -466)
  clear:SetScript("OnClick", function()
    wipe(ns.Sync.log)
    T:Refresh()
  end)

  f:SetScript("OnShow", function() T:Refresh() end)
  local acc = 0
  f:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc > 1 then acc = 0; T:Refresh() end
  end)
  ns.Enable(unlink, false)
  return f
end

function T:DoInvite()
  local ok, err = ns.Sync:Invite(self.nameBox:GetText())
  if ok then
    self.nameBox:SetTextSilent("")
    self.nameBox:ClearFocus()
  elseif err then
    ns.Sync:Log("|cffff5555" .. err .. "|r")
  end
  self:Refresh()
end

function T:OnLog()
  if self.frame and self.frame:IsVisible() then self:Refresh() end
end

function T:Refresh()
  if not self.list then return end
  local accounts = ns.Sync:AccountList()
  local selId = self.selected and self.selected.id
  self.selected = nil
  for _, a in ipairs(accounts) do
    if a.id == selId then self.selected = a end
  end
  self.list.selected = self.selected
  self.list:SetData(accounts, true)
  ns.Enable(self.unlinkBtn, self.selected ~= nil)
  self.logList:SetData(ns.Sync.log, true)

  local st = ns.Sync:Stats()
  local parts = { format("%d account%s linked, %d connected", st.accounts, st.accounts == 1 and "" or "s", st.connected) }
  if st.queued > 0 then parts[#parts + 1] = format("sending %.1f KB (~%ds)", st.queued / 1024, math.ceil(st.eta)) end
  if st.receiveTotal > 0 then parts[#parts + 1] = format("receiving %d%%", math.floor(st.receiving / st.receiveTotal * 100)) end
  if st.work > 0 then parts[#parts + 1] = format("%d batch%s to apply", st.work, st.work == 1 and "" or "es") end
  if not ns.db.syncEnabled then parts[#parts + 1] = "|cffff5555sync is off|r" end
  self.progress:SetText(table.concat(parts, "   "))
  local frac = 0
  if st.queued > 0 then frac = math.max(0.02, 1 - math.min(1, st.queued / 40000)) end
  if st.receiveTotal > 0 then frac = st.receiving / st.receiveTotal end
  self.bar:SetValue(frac)
end
