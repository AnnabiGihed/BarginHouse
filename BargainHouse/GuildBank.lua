local ADDON, ns = ...
local format = string.format

-- Records the contents of guild bank tabs the player has FULL access to
-- (viewable, can deposit, unlimited withdrawals - or guild master).
-- ns.db.guildBank["Realm - Guild"] = {
--   tabs  = { [tabIndex] = { name = , t = time, items = { [itemID] = count } } },
--   names = { [itemID] = "lowercase name" },
-- }

local SLOTS = MAX_GUILDBANK_SLOTS_PER_TAB or 98
local G = CreateFrame("Frame")
ns.GuildBank = G
G:Hide()

local function GuildKey()
  local guild = GetGuildInfo("player")
  if not guild then return nil end
  return (GetRealmName() or "?") .. " - " .. guild
end

local function Store()
  local key = GuildKey()
  if not key then return nil end
  ns.db.guildBank = ns.db.guildBank or {}
  local s = ns.db.guildBank[key]
  if not s then
    s = { tabs = {}, names = {} }
    ns.db.guildBank[key] = s
  end
  return s
end

-- Same rule Blizzard uses for the "(Full Access)" label on the tab:
-- you can deposit AND you have withdrawals (any amount, including unlimited).
-- Tabs shown as Locked, Withdraw Only or Deposit Only are not counted.
function G:HasFullAccess(tab)
  local name, _, isViewable, canDeposit, numWithdrawals = GetGuildBankTabInfo(tab)
  if not name or isViewable == false then return false end
  if IsGuildLeader and IsGuildLeader() then return true end
  return (canDeposit and numWithdrawals and numWithdrawals ~= 0) and true or false
end

-- Tab permissions arrive a moment after the vault opens
function G:TabInfoReady()
  local n = GetNumGuildBankTabs() or 0
  if n == 0 then return false end
  for tab = 1, n do
    if not GetGuildBankTabInfo(tab) then return false end
  end
  return true
end

-- Read one tab from the client cache. Returns false if the data isn't loaded.
function G:ReadTab(tab)
  local s = Store()
  if not s then return false end
  local items, stacks, anyTexture = {}, 0, false
  for slot = 1, SLOTS do
    local texture, count = GetGuildBankItemInfo(tab, slot)
    if texture then anyTexture = true end
    local link = GetGuildBankItemLink(tab, slot)
    local id = ns.ItemID(link)
    if id then
      items[id] = (items[id] or 0) + (count or 1)
      s.names[id] = strlower(link:match("%[(.-)%]") or "")
      stacks = stacks + 1
    end
  end
  if anyTexture and stacks == 0 then return false end -- icons known, links not yet
  s.tabs[tab] = { name = (GetGuildBankTabInfo(tab)), t = time(), items = items }
  return true, stacks
end

---------------------------------------------------------------------------
-- Full scan when the vault is opened
---------------------------------------------------------------------------
function G:StartScan(attempt)
  local s = Store()
  if not s or not self.open or self.scan then return end
  attempt = attempt or 1
  if not self:TabInfoReady() then
    if attempt < 8 then
      ns.After(1, function() G:StartScan(attempt + 1) end)
    end
    return
  end
  self.scannedThisVisit = true
  local tabs = {}
  local n = GetNumGuildBankTabs() or 0
  for tab = 1, n do
    if self:HasFullAccess(tab) then
      tabs[#tabs + 1] = tab
    else
      s.tabs[tab] = nil -- no (longer) full access: don't count it
    end
  end
  for tab in pairs(s.tabs) do
    if tab > n then s.tabs[tab] = nil end
  end
  if #tabs == 0 then
    ns.Print("Guild bank: none of your tabs show (Full Access), nothing recorded.")
    return
  end
  self.scan = { tabs = tabs, i = 0, stacks = 0, read = 0 }
  self:NextTab()
end

function G:NextTab()
  local scan = self.scan
  if not scan then return end
  scan.i = scan.i + 1
  local tab = scan.tabs[scan.i]
  if not tab then
    self.scan = nil
    self:Hide()
    local current = GetCurrentGuildBankTab and GetCurrentGuildBankTab()
    if current and current > 0 then QueryGuildBankTab(current) end
    ns.Print(format("Guild bank recorded: %d of %d full-access tab%s, %d stacks.",
      scan.read, #scan.tabs, #scan.tabs == 1 and "" or "s", scan.stacks))
    G:Notify()
    return
  end
  scan.tab, scan.waited, scan.gotEvent = tab, 0, false
  QueryGuildBankTab(tab)
  self:Show()
end

G:SetScript("OnUpdate", function(self, elapsed)
  local scan = self.scan
  if not scan then self:Hide() return end
  scan.waited = scan.waited + elapsed
  -- give the server a moment after the data arrives; give up on a tab after 4s
  if (scan.gotEvent and scan.waited > 0.4) or scan.waited > 4 then
    local ok, stacks = self:ReadTab(scan.tab)
    if ok then
      scan.read = scan.read + 1
      scan.stacks = scan.stacks + stacks
    elseif scan.waited <= 4 then
      return -- links not ready yet, keep waiting
    end
    self:NextTab()
  end
end)

G:RegisterEvent("GUILDBANKFRAME_OPENED")
G:RegisterEvent("GUILDBANKFRAME_CLOSED")
G:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED")
G:RegisterEvent("GUILDBANK_UPDATE_TABS")
G:SetScript("OnEvent", function(self, event)
  if not ns.db then return end
  if event == "GUILDBANKFRAME_OPENED" then
    self.open = true
    self.scannedThisVisit = false
    ns.After(0.8, function() if G.open and not G.scan and not G.scannedThisVisit then G:StartScan() end end)
  elseif event == "GUILDBANK_UPDATE_TABS" then
    if self.open and not self.scan and not self.scannedThisVisit then G:StartScan() end
  elseif event == "GUILDBANKFRAME_CLOSED" then
    self.open = false
    if self.scan then
      self.scan = nil
      self:Hide()
      G:Notify()
    end
  elseif event == "GUILDBANKBAGSLOTS_CHANGED" then
    if self.scan then
      self.scan.gotEvent = true
    elseif self.open then
      -- safety net: re-record whatever full-access tab the player is looking at
      local tab = GetCurrentGuildBankTab and GetCurrentGuildBankTab()
      if tab and tab > 0 and self:HasFullAccess(tab) and self:ReadTab(tab) then G:Notify() end
    end
  end
end)

function G:Notify()
  for _, panel in ipairs(ns.panels or {}) do
    if panel.Recount then panel:Recount() end
  end
end

---------------------------------------------------------------------------
-- Lookups
---------------------------------------------------------------------------
-- Count of an item (by link, item ID or name) in recorded full-access tabs
function ns.GuildBankCount(link, name)
  local key = GuildKey()
  local s = key and ns.db.guildBank and ns.db.guildBank[key]
  if not s then return 0 end
  local id = ns.ItemID(link)
  if not id and name then
    local lname = strlower(name)
    for itemID, n in pairs(s.names) do
      if n == lname then id = itemID break end
    end
  end
  if not id then return 0 end
  local total = 0
  for _, tab in pairs(s.tabs) do
    total = total + (tab.items[id] or 0)
  end
  return total
end

-- Summary for the UI: items, tabs, oldest scan time
function ns.GuildBankInfo()
  local key = GuildKey()
  local s = key and ns.db.guildBank and ns.db.guildBank[key]
  if not key then return nil, "Not in a guild" end
  if not s or not next(s.tabs) then return nil, "Not recorded yet - open your guild bank" end
  local tabs, stacks, oldest = 0, 0, nil
  for _, tab in pairs(s.tabs) do
    tabs = tabs + 1
    for _, c in pairs(tab.items) do stacks = stacks + c end
    if not oldest or tab.t < oldest then oldest = tab.t end
  end
  return { tabs = tabs, items = stacks, t = oldest, guild = GetGuildInfo("player") }
end
