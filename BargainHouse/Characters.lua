local ADDON, ns = ...
local format = string.format

-- Your characters:
--   this account:   ns.db.inventory[realm][name] gains money, class, level, profs, t
--   other accounts: ns.db.remoteChars[realm][name] = { money, t, class, level, profText, via }
-- Professions come from the skills list, so no profession window is needed.

local PROFESSIONS = {
  Alchemy = true, Blacksmithing = true, Enchanting = true, Engineering = true, Herbalism = true,
  Inscription = true, Jewelcrafting = true, Leatherworking = true, Mining = true, Skinning = true,
  Tailoring = true, Cooking = true, ["First Aid"] = true, Fishing = true,
}

local CH = CreateFrame("Frame")
ns.Chars = CH
CH:Hide()

local function Realm() return GetRealmName() or "?" end
local function InCombat() return InCombatLockdown and InCombatLockdown() end

local function ProfText(profs)
  local parts = {}
  for name, p in pairs(profs or {}) do parts[#parts + 1] = format("%s:%d:%d", name, p[1] or 0, p[2] or 0) end
  table.sort(parts)
  return table.concat(parts, ",")
end

function ns.ParseProfText(text)
  local out = {}
  for name, rank, max in (text or ""):gmatch("([^:,]+):(%d+):(%d+)") do
    out[#out + 1] = { name = name, rank = tonumber(rank), max = tonumber(max) }
  end
  table.sort(out, function(a, b) return a.rank > b.rank end)
  return out
end

---------------------------------------------------------------------------
-- Recording the character you're playing
---------------------------------------------------------------------------
function CH:Record()
  if not ns.db or not ns.Inventory then return end
  if InCombat() then self.pending = true return end
  local c = ns.Inventory:Char()
  if not c then return end
  -- right after login the server may not have sent your gold yet (GetMoney() = 0):
  -- never let such an early 0 replace a known amount
  local money = GetMoney() or 0
  if money > 0 or not c.money or GetTime() - (self.loginAt or 0) > 60 then
    c.money = money
  end
  local _, classFile = UnitClass("player")
  c.class = classFile
  c.level = UnitLevel("player")
  c.faction = UnitFactionGroup("player")
  c.t = time()

  local profs, found = {}, false
  for i = 1, (GetNumSkillLines and GetNumSkillLines() or 0) do
    local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
    if name and not isHeader and PROFESSIONS[name] then
      profs[name] = { rank or 0, maxRank or 0 }
      found = true
    end
  end
  if found then c.profs = profs end

  if ns.Sync then ns.Sync:CharacterChanged() end
  if ns.CharactersTab and ns.CharactersTab.frame and ns.CharactersTab.frame:IsVisible() then ns.CharactersTab:Refresh() end
end

-- Called from the sync module's 10 Hz loop: re-read gold a few times after
-- login (the server can send it late), then every 5 minutes. No extra frame.
function CH:Tick()
  if not self.loginAt then return end
  local since = GetTime() - self.loginAt
  if self.rereads and self.rereads[1] and since >= self.rereads[1] then
    table.remove(self.rereads, 1)
    self:Schedule(0.1)
  elseif since - (self.lastPeriodic or 0) >= 300 then
    self.lastPeriodic = since
    self:Schedule(0.1)
  end
end

-- debounce: money and skills fire in bursts (looting, crafting)
function CH:Schedule(delay)
  self.delay = math.max(self.delay or 0, delay or 3)
  self:Show()
end

CH:SetScript("OnUpdate", function(self, elapsed)
  self.delay = self.delay - elapsed
  if self.delay > 0 then return end
  self:Hide()
  self:Record()
end)

CH:RegisterEvent("PLAYER_ENTERING_WORLD")
CH:RegisterEvent("PLAYER_MONEY")
CH:RegisterEvent("SKILL_LINES_CHANGED")
CH:RegisterEvent("PLAYER_LEVEL_UP")
CH:RegisterEvent("PLAYER_REGEN_ENABLED")
CH:RegisterEvent("PLAYER_LOGOUT")
CH:SetScript("OnEvent", function(self, event)
  if not ns.db then return end
  if event == "PLAYER_LOGOUT" then
    local c = ns.Inventory and ns.Inventory:Char()
    if c then
      local money = GetMoney() or 0
      if money > 0 or not c.money then c.money = money end -- gold can read 0 while logging out
      c.t = time()
    end
  elseif event == "PLAYER_REGEN_ENABLED" then
    if self.pending then
      self.pending = false
      self:Schedule(2)
    end
  elseif event == "PLAYER_ENTERING_WORLD" then
    if not self.loginAt then
      self.loginAt = GetTime()
      self.rereads = { 20, 60 } -- seconds after login; then every 5 minutes (see Tick)
    end
    self:Schedule(3)
  else
    self:Schedule(3)
  end
end)

---------------------------------------------------------------------------
-- Lists
---------------------------------------------------------------------------
function CH:LocalList()
  local out = {}
  local realm = ns.db.inventory and ns.db.inventory[Realm()]
  for name, c in pairs(realm or {}) do
    if c.t or c.money then
      local money, t = c.money, c.t
      if name == UnitName("player") then
        -- the character you're playing: live gold
        local live = GetMoney() or 0
        if live > 0 or not money then money = live end
        t = time()
      end
      out[#out + 1] = { name = name, money = money, t = t, class = c.class, level = c.level, profText = ProfText(c.profs) }
    end
  end
  return out
end

function CH:IsLocal(name)
  local realm = ns.db.inventory and ns.db.inventory[Realm()]
  return realm and realm[name] and (realm[name].t or realm[name].money) and true or false
end

function CH:StoreRemote(name, data)
  if not name or name == "" or self:IsLocal(name) then return end
  -- gold is never lost: a 0 (character offline / not sent yet) keeps the old amount
  ns.db.remoteChars = ns.db.remoteChars or {}
  local realm = ns.db.remoteChars[Realm()] or {}
  ns.db.remoteChars[Realm()] = realm
  local old = realm[name]
  if old and (old.t or 0) > (data.t or 0) then return end
  if old and (not data.money or data.money == 0) and (old.money or 0) > 0 then data.money = old.money end
  if old and (not data.profText or data.profText == "") then data.profText = old.profText end
  realm[name] = data
  if ns.CharactersTab and ns.CharactersTab.frame and ns.CharactersTab.frame:IsVisible() then ns.CharactersTab:Refresh() end
end

function CH:ForgetRemote(via)
  local realm = ns.db.remoteChars and ns.db.remoteChars[Realm()]
  if not realm then return end
  for name, c in pairs(realm) do
    if strlower(name) == strlower(via) or (c.via and strlower(c.via) == strlower(via)) then realm[name] = nil end
  end
end

function CH:IsKnown(name)
  if self:IsLocal(name) then return true end
  local realm = ns.db.remoteChars and ns.db.remoteChars[Realm()]
  return realm and realm[name] ~= nil
end

-- Every character: this account, other accounts, and listed ones not heard from yet
function CH:All()
  local rows, seen = {}, {}
  local me = UnitName("player")
  for _, c in ipairs(self:LocalList()) do
    c.account = "local"
    c.playing = (c.name == me)
    rows[#rows + 1] = c
    seen[strlower(c.name)] = true
  end
  local realm = ns.db.remoteChars and ns.db.remoteChars[Realm()]
  for name, c in pairs(realm or {}) do
    if not seen[strlower(name)] then
      rows[#rows + 1] = { name = name, money = c.money, t = c.t, class = c.class, level = c.level, profText = c.profText, account = "remote", via = c.via }
      seen[strlower(name)] = true
    end
  end
  for key, name in pairs(ns.Sync and ns.Sync:Partners() or {}) do
    if not seen[key] then
      rows[#rows + 1] = { name = name, account = "remote", waiting = true }
    end
  end
  for _, r in ipairs(rows) do
    r.listed = ns.Sync and ns.Sync:IsTrusted(r.name) or false
    r.online = r.playing or (ns.Sync and ns.Sync:IsOnline(r.name)) or false
  end
  return rows
end

-- every character we know: this account and the linked ones (for relaying)
function CH:Everyone()
  local out = self:LocalList()
  local realm = ns.db.remoteChars and ns.db.remoteChars[Realm()]
  for name, c in pairs(realm or {}) do
    out[#out + 1] = { name = name, money = c.money, t = c.t, class = c.class, level = c.level, profText = c.profText }
  end
  return out
end

-- characters that have a profession (from the skills list), for "who can craft"
function CH:WithProfession(prof)
  local out = {}
  for _, r in ipairs(self:All()) do
    for _, p in ipairs(ns.ParseProfText(r.profText)) do
      if p.name == prof then out[#out + 1] = { name = r.name, rank = p.rank } end
    end
  end
  table.sort(out, function(a, b) return a.rank > b.rank end)
  return out
end

function CH:TotalGold()
  local total, n = 0, 0
  for _, r in ipairs(self:All()) do
    if r.money then
      total = total + (r.playing and GetMoney() or r.money)
      n = n + 1
    end
  end
  return total, n
end
