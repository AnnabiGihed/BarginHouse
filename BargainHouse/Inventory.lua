local ADDON, ns = ...
local format = string.format

-- Records bags (always) and the personal bank (whenever it is open) for every
-- character, so stock can be counted even when you're away from a banker.
-- ns.db.inventory[realm][character] = {
--   faction = "Horde"/"Alliance",
--   bags = { [itemID] = count }, bagsT = time,
--   bank = { [itemID] = count }, bankT = time,   -- bank slots + bank bags
-- }
-- ns.db.itemNames[itemID] = "lowercase name"

local BANK_CONTAINER = BANK_CONTAINER or -1
local NUM_BAGS = NUM_BAG_SLOTS or 4
local NUM_BANK_BAGS = NUM_BANKBAGSLOTS or 7

local I = CreateFrame("Frame")
ns.Inventory = I
I:Hide()

local function Realm() return GetRealmName() or "?" end
local function Me() return UnitName("player") end

function I:Char(name)
  if not ns.db then return nil end
  ns.db.inventory = ns.db.inventory or {}
  local realm = ns.db.inventory[Realm()]
  if not realm then
    realm = {}
    ns.db.inventory[Realm()] = realm
  end
  name = name or Me()
  if not name then return nil end
  local c = realm[name]
  if not c then
    c = {}
    realm[name] = c
  end
  return c
end

local function ReadContainers(ids)
  ns.db.itemNames = ns.db.itemNames or {}
  local items = {}
  for _, bag in ipairs(ids) do
    for slot = 1, (GetContainerNumSlots(bag) or 0) do
      local link = GetContainerItemLink(bag, slot)
      local id = ns.ItemID(link)
      if id then
        local _, count = GetContainerItemInfo(bag, slot)
        items[id] = (items[id] or 0) + (count or 1)
        ns.db.itemNames[id] = strlower(link:match("%[(.-)%]") or "")
      end
    end
  end
  return items
end

local function Same(a, b)
  if not a or not b then return false end
  for k, v in pairs(a) do if b[k] ~= v then return false end end
  for k, v in pairs(b) do if a[k] ~= v then return false end end
  return true
end

function I:RecordBags()
  local c = self:Char()
  if not c then return false end
  local ids = {}
  for bag = 0, NUM_BAGS do ids[#ids + 1] = bag end
  local items = ReadContainers(ids)
  local changed = not Same(c.bags, items)
  c.bags, c.bagsT, c.faction = items, time(), UnitFactionGroup("player")
  return changed
end

function I:RecordBank()
  if not self.bankOpen then return false end
  local c = self:Char()
  if not c then return false end
  local ids = { BANK_CONTAINER }
  for bag = NUM_BAGS + 1, NUM_BAGS + NUM_BANK_BAGS do ids[#ids + 1] = bag end
  local items = ReadContainers(ids)
  local changed = not Same(c.bank, items)
  c.bank, c.bankT = items, time()
  return changed
end

-- debounce: containers fire many events in a row
function I:Schedule(what)
  self.pending = self.pending or {}
  self.pending[what] = true
  self.delay = 0.6
  self:Show()
end

I:SetScript("OnUpdate", function(self, elapsed)
  self.delay = self.delay - elapsed
  if self.delay > 0 then return end
  if InCombatLockdown and InCombatLockdown() then
    self.delay = 1 -- bags change a lot in fights: record once combat is over
    return
  end
  self:Hide()
  local pending = self.pending or {}
  self.pending = {}
  local changed = false
  if pending.bags and self:RecordBags() then changed = true end
  if pending.bank and self:RecordBank() then changed = true end
  if changed and ns.main and ns.main:IsShown() then
    for _, panel in ipairs(ns.panels or {}) do
      if panel.Recount and not panel.queue then panel:Recount() end
    end
  end
end)

I:RegisterEvent("PLAYER_ENTERING_WORLD")
I:RegisterEvent("BAG_UPDATE")
I:RegisterEvent("BANKFRAME_OPENED")
I:RegisterEvent("BANKFRAME_CLOSED")
I:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
I:RegisterEvent("PLAYERBANKBAGSLOTS_CHANGED")
I:SetScript("OnEvent", function(self, event, bag)
  if not ns.db then return end
  if event == "PLAYER_ENTERING_WORLD" then
    self:Schedule("bags")
  elseif event == "BAG_UPDATE" then
    if bag and bag > NUM_BAGS then
      if self.bankOpen then self:Schedule("bank") end
    else
      self:Schedule("bags")
    end
  elseif event == "BANKFRAME_OPENED" then
    self.bankOpen = true
    self:Schedule("bank")
    self:Schedule("bags")
  elseif event == "BANKFRAME_CLOSED" then
    -- bank contents are no longer readable once it closes: keep what was
    -- recorded while it was open (every change was recorded then)
    if self.pending then self.pending.bank = nil end
    self.bankOpen = false
  elseif event == "PLAYERBANKSLOTS_CHANGED" or event == "PLAYERBANKBAGSLOTS_CHANGED" then
    if self.bankOpen then self:Schedule("bank") end
  end
end)

---------------------------------------------------------------------------
-- Lookups
---------------------------------------------------------------------------
function ns.ResolveItemID(link, name)
  local id = ns.ItemID(link)
  if id or not name then return id end
  local lname = strlower(name)
  for itemID, n in pairs(ns.db.itemNames or {}) do
    if n == lname then return itemID end
  end
  for _, g in pairs(ns.db.guildBank or {}) do
    for itemID, n in pairs(g.names or {}) do
      if n == lname then return itemID end
    end
  end
end

-- This character's recorded personal bank
function ns.CountBank(id)
  local c = I:Char()
  if not c or not c.bankT then return 0, nil end
  return (id and c.bank[id]) or 0, c.bankT
end

-- Other characters on this realm (same faction), bags + bank
function ns.CountAlts(id)
  local realm = ns.db.inventory and ns.db.inventory[Realm()]
  if not realm or not id then return 0, {} end
  local me, faction = Me(), UnitFactionGroup("player")
  local total, details = 0, {}
  for name, c in pairs(realm) do
    if name ~= me and (not c.faction or not faction or c.faction == faction) then
      local bags = c.bags and c.bags[id] or 0
      local bank = c.bank and c.bank[id] or 0
      if bags + bank > 0 then
        total = total + bags + bank
        details[#details + 1] = { name = name, bags = bags, bank = bank, t = math.min(c.bagsT or time(), c.bankT or time()) }
      end
    end
  end
  table.sort(details, function(a, b) return (a.bags + a.bank) > (b.bags + b.bank) end)
  return total, details
end

function ns.InventoryInfo()
  local c = I:Char()
  local realm = ns.db.inventory and ns.db.inventory[Realm()] or {}
  local me, faction, alts = Me(), UnitFactionGroup("player"), 0
  for name, x in pairs(realm) do
    if name ~= me and (not x.faction or x.faction == faction) then alts = alts + 1 end
  end
  return { bankT = c and c.bankT, alts = alts }
end

function ns.ForgetAlts()
  local realm = ns.db.inventory and ns.db.inventory[Realm()]
  if not realm then return end
  local me = Me()
  for name in pairs(realm) do
    if name ~= me then realm[name] = nil end
  end
end

---------------------------------------------------------------------------
-- Mailbox: auction purchases land here, so they must count as stock or a
-- re-check would buy them again.
--   ns.db.mail[realm][char]    = { items = { [itemID] = count }, t = time }
--   ns.db.transit[realm][char] = { { id =, n =, t = }, ... }  bought, not seen in mail yet
---------------------------------------------------------------------------
local ATTACH = ATTACHMENTS_MAX_RECEIVE or 12
local TRANSIT_DAYS = 30

local function CharTable(root)
  ns.db[root] = ns.db[root] or {}
  local realm = ns.db[root][Realm()]
  if not realm then
    realm = {}
    ns.db[root][Realm()] = realm
  end
  return realm
end

function ns.RecordPurchase(a)
  if not ns.db or not a or not a.id then return end
  local realm = CharTable("transit")
  local list = realm[Me()] or {}
  realm[Me()] = list
  list[#list + 1] = { id = a.id, n = a.count or 1, t = time() }
  ns.db.itemNames = ns.db.itemNames or {}
  if a.name then ns.db.itemNames[a.id] = strlower(a.name) end
end

function I:RecordMail()
  local n = GetInboxNumItems and GetInboxNumItems() or 0
  local items = {}
  for i = 1, n do
    for att = 1, ATTACH do
      local name, _, count = GetInboxItem(i, att)
      if name then
        local id = ns.ItemID(GetInboxItemLink and GetInboxItemLink(i, att))
        if id then
          items[id] = (items[id] or 0) + (count or 1)
          ns.db.itemNames[id] = strlower(name)
        end
      end
    end
  end
  local now = time()
  CharTable("mail")[Me()] = { items = items, t = now }
  -- everything bought before this moment is now either in the mailbox or already taken
  local transit = CharTable("transit")[Me()]
  if transit then
    for k = #transit, 1, -1 do
      if transit[k].t <= now then table.remove(transit, k) end
    end
  end
  return true
end

-- Items in this character's mailbox (last recorded) + purchases since then
function ns.CountMail(id)
  if not ns.db or not id then return 0, 0 end
  local now = time()
  local box = CharTable("mail")[Me()]
  local inBox = box and box.items[id] or 0
  local bought = 0
  local transit = CharTable("transit")[Me()]
  if transit then
    for k = #transit, 1, -1 do
      local tr = transit[k]
      if now - tr.t > TRANSIT_DAYS * 86400 then
        table.remove(transit, k)
      elseif tr.id == id then
        bought = bought + tr.n
      end
    end
  end
  return inBox + bought, bought, box and box.t
end

local mailFrame = CreateFrame("Frame")
mailFrame:RegisterEvent("MAIL_SHOW")
mailFrame:RegisterEvent("MAIL_INBOX_UPDATE")
mailFrame:RegisterEvent("MAIL_CLOSED")
mailFrame:SetScript("OnEvent", function(_, event)
  if not ns.db then return end
  if event == "MAIL_SHOW" then
    mailFrame.open = true
  elseif event == "MAIL_CLOSED" then
    mailFrame.open = false
  elseif event == "MAIL_INBOX_UPDATE" and mailFrame.open then
    I:RecordMail()
    if ns.main and ns.main:IsShown() then
      for _, panel in ipairs(ns.panels or {}) do
        if panel.Recount and not panel.queue then panel:Recount() end
      end
    end
  end
end)
