local ADDON, ns = ...
local format, floor = string.format, math.floor

-- Sync between YOUR WoW accounts.
--
-- Linking: invite one character of another account (Sync tab). They accept once.
-- Linked accounts then tell each other about every account they know, so with
-- four accounts you send three invites, in any order, and all of them connect.
-- Only invited/accepted accounts are trusted; strangers are ignored.
--
-- Transport: hidden whispers, or the guild addon channel addressed to one
-- character (some servers don't deliver hidden whispers). Nothing is broadcast.
--
-- Robustness / performance:
--   * 10 Hz loop, nothing sent or applied while in combat
--   * small messages jump ahead of bulk transfers (priority lane)
--   * missing pieces of a transfer are asked for again (no silent loss)
--   * a background check every 5 minutes only sends what differs
--   * received data is applied in slices; every message is pcall-guarded
--
-- Messages (prefix "BargainHouse", version 4):
--   H4~<acc>   hello          I4~<acc>  invite        J4~<acc>  invite accepted
--   Y          keep-alive     X         goodbye
--   G<acc>~<t>~<names>        a linked account (gossip)
--   Z<acc>~<t>                an account was unlinked (gossip)
--   P<name>~<money>~<t>~<class>~<level>~<profs>       a character
--   S<prof>~<count>~<sum> / S*    recipe digests
--   W<char>~<prof>~<t>~<hash>~<n> what a character knows (summary)
--   V<char>~<prof>                send me that list
--   A<realm-faction>~<t> / Q<t>   auction scan
--   D<id>~<i>~<n>~<chunk>         stream piece   N<id>~<i,i,..>  resend these
--   streams: L (hashes I have) R (recipes) E (a character's known recipes) M/C (scan)

local PREFIX, VERSION = "BargainHouse", 4
local CHUNK = 200
local CPS, BURST = 800, 3000
local TICK, MAINTAIN = 0.1, 2
local HELLO_INTERVAL, BLIND_HELLO_INTERVAL = 30, 60
local REFRESH_INTERVAL = 300
local KEEPALIVE, SESSION_TIMEOUT = 60, 150
local WORK_PER_TICK = 150
local NACK_AFTER, NACK_TRIES, OUT_KEEP = 15, 10, 900
local INVITE_VALID = 900

local Y = CreateFrame("Frame")
ns.Sync = Y
Y.sessions, Y.buffers, Y.work, Y.out, Y.invites = {}, {}, {}, {}, {}
Y.budget, Y.streamId, Y.log = BURST, 0, {}

local function InCombat() return InCombatLockdown and InCombatLockdown() end
local function Encode(name, rec) return ns.EncodeRecipe and ns.EncodeRecipe(name, rec) end
local function Decode(text) if ns.DecodeRecipe then return ns.DecodeRecipe(text) end end
local function Clean(s) return (tostring(s or ""):gsub("[~%^`}|,]", " ")) end
local function Proper(name) return name and (name:sub(1, 1):upper() .. name:sub(2):lower()) end

local function Hash(s)
  local h = 5381
  for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
  return format("%08x", h)
end

---------------------------------------------------------------------------
-- Queues (head index: no table shifting during big transfers)
---------------------------------------------------------------------------
local function NewQueue() return { head = 1, n = 0, bytes = 0 } end
Y.control, Y.bulk = NewQueue(), NewQueue()

local function Push(q, item)
  q.n = q.n + 1
  q[q.n] = item
  q.bytes = q.bytes + #item.text
end
local function Peek(q) return q[q.head] end
local function Pop(q)
  local item = q[q.head]
  q[q.head] = nil
  q.head = q.head + 1
  q.bytes = q.bytes - #item.text
  if q.head > q.n then q.head, q.n, q.bytes = 1, 0, 0 end
  return item
end

---------------------------------------------------------------------------
-- Log
---------------------------------------------------------------------------
function Y:Log(text, verbose)
  if verbose and not (ns.db and ns.db.syncVerbose) then return end
  table.insert(self.log, 1, { t = time(), text = text })
  while #self.log > 300 do table.remove(self.log) end
  if ns.SyncTab and ns.SyncTab.OnLog then ns.SyncTab:OnLog() end
end

---------------------------------------------------------------------------
-- Accounts
---------------------------------------------------------------------------
function Y:Me() return self.me or UnitName("player") end

-- A private ID for this WoW account. It must never match another account's, so
-- it mixes character and realm (unique per account) with the clock, a seeded
-- random number and a salt that changes if it ever has to be regenerated.
function Y:NewAccountId()
  local who = (UnitName("player") or "?") .. (GetRealmName() or "?")
  self.idAttempt = (self.idAttempt or 0) + 1
  local salt = self.idAttempt * 7919 + floor((GetTime() * 1000) % 99991)
  math.randomseed(floor(time() % 1000000) + salt + tonumber(Hash(who):sub(1, 6), 16))
  math.random(); math.random()
  return Hash(who .. time() .. GetTime() .. salt .. math.random(1, 1000000))
    .. format("%04x%04x", math.random(0, 65535), (salt + floor(time())) % 65536)
end

function Y:AccountId()
  if not ns.db.accountId then
    ns.db.accountId = self:NewAccountId()
    self:Log("This account's sync ID was created")
  end
  return ns.db.accountId
end

function Y:Accounts()
  ns.db.syncAccounts = ns.db.syncAccounts or {}
  return ns.db.syncAccounts
end

function Y:Removed()
  ns.db.syncRemoved = ns.db.syncRemoved or {}
  return ns.db.syncRemoved
end

function Y:AccountOf(name)
  local lname = strlower(name or "")
  for id, a in pairs(self:Accounts()) do
    if a.names and a.names[lname] then return id end
  end
end

function Y:LearnAccount(id, name, t)
  if not id or id == "" or id == self:AccountId() then return false end
  if self:Removed()[id] then return false end
  local accounts = self:Accounts()
  local a = accounts[id]
  local isNew = not a
  if isNew then
    a = { names = {}, t = t or time() }
    accounts[id] = a
  end
  local added = false
  if name and name ~= "" then
    local l = strlower(name)
    if not a.names[l] then
      a.names[l] = true
      added = true
    end
  end
  a.t = math.max(a.t or 0, t or time())
  if isNew then
    self:Log(format("Linked a new account (%s)", name and Proper(name) or id:sub(1, 6)))
    self.gossipDirty = true
  elseif added then
    self:Log(format("New character on a linked account: %s", Proper(name)), true)
    self.gossipDirty = true
  end
  -- a character of a linked account no longer needs the old manual list
  if name and ns.db.syncPartners and ns.db.syncPartners ~= "" then
    local keep = {}
    for p in ns.db.syncPartners:gmatch("[^,%s]+") do
      if strlower(p) ~= strlower(name) then keep[#keep + 1] = p end
    end
    ns.db.syncPartners = table.concat(keep, ", ")
  end
  return isNew or added
end

-- older versions listed characters by hand: still trusted until accounts link
function Y:Partners()
  local out = {}
  for name in (ns.db and ns.db.syncPartners or ""):gmatch("[^,%s]+") do out[strlower(name)] = Proper(name) end
  return out
end

function Y:IsTrusted(name)
  if not name then return false end
  if self:AccountOf(name) then return true end
  return self:Partners()[strlower(name)] ~= nil
end

function Y:Targets()
  local out = {}
  for _, a in pairs(self:Accounts()) do
    for lname in pairs(a.names or {}) do out[lname] = Proper(lname) end
  end
  for lname, name in pairs(self:Partners()) do out[lname] = name end
  for lname, t in pairs(self.invites) do
    if GetTime() - t < INVITE_VALID then out[lname] = Proper(lname) end
  end
  out[strlower(self:Me() or "")] = nil
  if ns.Chars then
    for lname, name in pairs(out) do
      if ns.Chars:IsLocal(name) then out[lname] = nil end -- same account: nothing to sync
    end
  end
  return out
end

function Y:AccountList()
  local out = {}
  for id, a in pairs(self:Accounts()) do
    local names, connected, lastSeen = {}, nil, nil
    for lname in pairs(a.names or {}) do
      local proper = Proper(lname)
      names[#names + 1] = proper
      local s = self.sessions[lname]
      if s and s.active then connected = proper end
      if s and s.lastSeenTime and (not lastSeen or s.lastSeenTime > lastSeen) then lastSeen = s.lastSeenTime end
    end
    table.sort(names)
    out[#out + 1] = { id = id, names = names, connected = connected, lastSeen = lastSeen, t = a.t }
  end
  table.sort(out, function(x, y) return (x.names[1] or "") < (y.names[1] or "") end)
  return out
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------
function Y:Send(target, text, channel, bulk)
  if not target or target == "" then return end
  local s = self.sessions[strlower(target)]
  channel = channel or (s and s.channel) or "WHISPER"
  if channel == "GUILD" then
    if not (IsInGuild and IsInGuild()) then return end
    text = "@" .. target .. "~" .. text
  end
  Push(bulk and self.bulk or self.control, { target = target, text = text, channel = channel })
end

function Y:SendBoth(target, text)
  self:Send(target, text, "WHISPER")
  self:Send(target, text, "GUILD")
end

function Y:SendStream(target, text, label)
  self.streamId = (self.streamId % 99999) + 1
  local sid = self.streamId
  local n = math.ceil(#text / CHUNK)
  local chunks = {}
  for i = 1, n do
    chunks[i] = text:sub((i - 1) * CHUNK + 1, i * CHUNK)
    self:Send(target, format("D%d~%d~%d~%s", sid, i, n, chunks[i]), nil, true)
  end
  self.out[strlower(target) .. ":" .. sid] = { chunks = chunks, n = n, t = GetTime(), target = target, sid = sid }
  self:Log(format("Sending %s to %s (%.1f KB)", label or "data", target, #text / 1024))
end

function Y:Pump(elapsed)
  self.budget = math.min(BURST, self.budget + CPS * elapsed)
  if InCombat() then return end
  for _, q in ipairs({ self.control, self.bulk }) do
    while Peek(q) and self.budget >= #Peek(q).text + #PREFIX do
      local m = Pop(q)
      self.budget = self.budget - #m.text - #PREFIX
      self.whispered = self.whispered or {}
      self.whispered[strlower(m.target)] = GetTime()
      self:Log(format("-> %s (%s) %s", m.target, m.channel, m.text:sub(1, 40)), true)
      if m.channel == "GUILD" then
        SendAddonMessage(PREFIX, m.text, "GUILD")
      else
        SendAddonMessage(PREFIX, m.text, "WHISPER", m.target)
      end
    end
    if Peek(q) then return end -- control lane not empty: bulk waits
  end
end

---------------------------------------------------------------------------
-- Work queue (apply received data in slices)
---------------------------------------------------------------------------
function Y:DoWork()
  if InCombat() then return end
  local budget = WORK_PER_TICK
  while budget > 0 and self.work[1] do
    local job = self.work[1]
    local ok, used, finished = pcall(job.step, budget)
    if not ok then
      self:Log("Error while applying data: " .. tostring(used), true)
      table.remove(self.work, 1)
    else
      budget = budget - (used or budget)
      if finished then
        table.remove(self.work, 1)
        if job.done then pcall(job.done) end
      end
    end
  end
end

---------------------------------------------------------------------------
-- Presence and upkeep
---------------------------------------------------------------------------
-- The client is told at once when a friend or guildmate logs in or out, and a
-- whisper to an offline character answers immediately. We use those instead of
-- polling, so a character is greeted about a second after it appears.
local function ToPattern(fmt)
  if not fmt then return nil end
  local pat = fmt:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
  pat = pat:gsub("%%%%s", "(.-)")
  return pat
end
local ONLINE_PAT = ToPattern(ERR_FRIEND_ONLINE_SS)
local OFFLINE_PAT = ToPattern(ERR_FRIEND_OFFLINE_S)
local NOTFOUND_PAT = ToPattern(ERR_CHAT_PLAYER_NOT_FOUND_S)

local function NameFrom(msg, pat)
  if not pat then return nil end
  local a, b = msg:match(pat)
  local name = b or a
  if not name or name == "" then return nil end
  name = name:gsub("|H.-|h", ""):gsub("[%[%]|]", ""):gsub("^%s+", ""):gsub("%s+$", "")
  return name ~= "" and name or nil
end

-- someone was seen logging in or out
function Y:Sighted(name, online)
  if not name or not ns.db then return end
  local key = strlower(name)
  if not self:Targets()[key] then return end
  local s = self:Session(name)
  s.presence, s.presenceAt = online, GetTime()
  if online then
    s.helloAt = nil          -- greet immediately
    self.maintainSoon = true
    self:Log(name .. " came online", true)
  else
    if s.active then self:Log(name .. " went offline") end
    s.active, s.channel = false, nil
  end
end

local function KnownOnline(name)
  local lname = strlower(name)
  for i = 1, (GetNumFriends and GetNumFriends() or 0) do
    local fname, _, _, _, connected = GetFriendInfo(i)
    if fname and strlower(fname) == lname then return connected and true or false end
  end
  if IsInGuild and IsInGuild() then
    for i = 1, (GetNumGuildMembers and GetNumGuildMembers(true) or 0) do
      local gname, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
      if gname and strlower(gname) == lname then return online and true or false end
    end
  end
  return nil
end

function Y:Session(name)
  local key = strlower(name)
  local s = self.sessions[key] or {}
  self.sessions[key] = s
  return s
end

function Y:Maintain()
  if not ns.db or not ns.db.syncEnabled or InCombat() then return end
  local now = GetTime()
  if IsInGuild and IsInGuild() and GuildRoster and now - (self.rosterAt or -1e9) > 20 then
    self.rosterAt = now
    GuildRoster()
  end
  if ShowFriends and now - (self.friendsAt or -1e9) > 20 then
    self.friendsAt = now
    ShowFriends()
  end

  for key, name in pairs(self:Targets()) do
    local s = self:Session(name)
    local online = KnownOnline(name)
    -- a login/logout we were told about is fresher than any roster snapshot
    if s.presence ~= nil and now - (s.presenceAt or 0) < 600 then online = s.presence end
    if online == false and s.active then
      s.active, s.channel = false, nil
      self:Log(name .. " went offline")
    end
    if s.active then
      if now - (s.lastRecv or 0) > SESSION_TIMEOUT then
        s.active, s.channel = false, nil
        self:Log(name .. " stopped answering")
      else
        if now - (s.pingAt or 0) > KEEPALIVE then
          s.pingAt = now
          self:Send(name, "Y")
        end
        if now - (s.refreshAt or 0) > REFRESH_INTERVAL then
          s.refreshAt = now
          self:SendDigests(name)
        end
      end
    elseif online ~= false then
      local interval = (online == nil) and BLIND_HELLO_INTERVAL or HELLO_INTERVAL
      if now - (s.helloAt or -1e9) >= interval then
        s.helloAt = now
        if self.invites[key] and not self:IsTrusted(name) then
          self:SendBoth(name, "I" .. VERSION .. "~" .. self:AccountId())
        else
          self:SendBoth(name, "H" .. VERSION .. "~" .. self:AccountId())
        end
      end
    end
  end

  -- ask again for pieces that never arrived
  for bkey, buf in pairs(self.buffers) do
    if now - buf.t > NACK_AFTER then
      if (buf.nacks or 0) >= NACK_TRIES then
        self.buffers[bkey] = nil
        self:Log("A transfer from " .. (buf.sender or "?") .. " didn't arrive; asking for it again")
        -- start over rather than stay out of sync
        local s2 = buf.sender and self.sessions[strlower(buf.sender)]
        if s2 then
          s2.sent, s2.refreshAt = nil, 0
        end
        self.requested = {}
      else
        local missing = {}
        for i = 1, (buf.n or 0) do
          if not buf.parts[i] then
            missing[#missing + 1] = i
            if #missing >= 40 then break end
          end
        end
        buf.nacks, buf.t = (buf.nacks or 0) + 1, now
        self:Send(buf.sender, format("N%d~%s", buf.sid, table.concat(missing, ",")))
        self:Log(format("Asking %s again for %d missing piece%s", buf.sender, #missing, #missing == 1 and "" or "s"), true)
      end
    end
  end
  for k, o in pairs(self.out) do
    if now - o.t > OUT_KEEP then self.out[k] = nil end
  end
  self:CheckKnown()
  if self.gossipDirty then
    self.gossipDirty = false
    self:ForActive(function(name) Y:SendAccounts(name) end)
  end
end

local acc, maint = 0, 0
Y:SetScript("OnUpdate", function(self, elapsed)
  acc = acc + elapsed
  if acc < TICK then return end
  elapsed, acc = acc, 0
  if not ns.db then return end
  self:Pump(elapsed)
  self:DoWork()
  if ns.Chars and ns.Chars.Tick then ns.Chars:Tick() end
  maint = maint + elapsed
  if maint >= MAINTAIN or self.maintainSoon then
    maint = 0
    self.maintainSoon = nil
    self:Maintain()
  end
end)

-- hide "No player named X is currently playing." from our quiet hellos
if ChatFrame_AddMessageEventFilter then
  local pattern = ERR_CHAT_PLAYER_NOT_FOUND_S and ("^" .. ERR_CHAT_PLAYER_NOT_FOUND_S:gsub("%%s", "(.+)"):gsub("'", "'?") .. "$")
  ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
    if not pattern or not Y.whispered or not next(Y.whispered) then return false end
    local who = msg:match(pattern)
    who = who and strlower((who:gsub("'", "")))
    if who and Y.whispered[who] and GetTime() - Y.whispered[who] < 10 then return true end
    return false
  end)
end

---------------------------------------------------------------------------
-- What a character knows (crafters), kept apart from the recipes themselves
---------------------------------------------------------------------------
function Y:KnowSets()
  local sets = {}
  for prof, book in pairs(ns.db.recipes or {}) do
    for name, rec in pairs(book) do
      for who, kind in pairs(rec.k or {}) do
        if kind == "own" then
          local lwho = strlower(who)
          sets[lwho] = sets[lwho] or {}
          local set = sets[lwho][prof] or { hashes = {} }
          sets[lwho][prof] = set
          set.hashes[#set.hashes + 1] = Hash(name)
        end
      end
    end
  end
  for _, profs in pairs(sets) do
    for _, set in pairs(profs) do
      table.sort(set.hashes)
      set.hash = Hash(table.concat(set.hashes, ""))
      set.count = #set.hashes
    end
  end
  return sets
end

-- ask for any crafter list that doesn't match what we have (throttled per list)
function Y:CheckKnown()
  if not self.knownW then return end
  local sets = self:KnowSets()
  self.requested = self.requested or {}
  local now = GetTime()
  for key, w in pairs(self.knownW) do
    local lchar = strlower(w.char)
    local mine = sets[lchar] and sets[lchar][w.prof]
    local myHash, myT = mine and mine.hash or "", self:KnowTime(lchar, w.prof)
    if w.hash ~= myHash and ((w.t or 0) > myT or ((w.t or 0) == myT and w.hash > myHash)) then
      if now - (self.requested[key] or -1e9) > 60 then
        self.requested[key] = now
        self:Send(w.from, format("V%s~%s", Clean(w.char), Clean(w.prof)))
      end
    else
      self.knownW[key] = nil -- in sync
    end
  end
end

function Y:KnowTime(lchar, prof)
  ns.db.knowT = ns.db.knowT or {}
  local c = ns.db.knowT[lchar]
  return (c and c[prof]) or 0
end

function Y:SetKnowTime(lchar, prof, t)
  ns.db.knowT = ns.db.knowT or {}
  ns.db.knowT[lchar] = ns.db.knowT[lchar] or {}
  ns.db.knowT[lchar][prof] = t
end

---------------------------------------------------------------------------
-- Digests
---------------------------------------------------------------------------
function Y:Digest(prof)
  local book = ns.db.recipes and ns.db.recipes[prof]
  local count, sum, hashes = 0, 0, {}
  for name in pairs(book or {}) do
    local h = Hash(name)
    hashes[h] = name
    count = count + 1
    sum = (sum + tonumber(h, 16)) % 4294967296
  end
  return count, format("%08x", sum), hashes
end

function Y:SendAccounts(target)
  local mine = {}
  if ns.Chars then
    for _, c in ipairs(ns.Chars:LocalList()) do mine[#mine + 1] = Clean(c.name) end
  end
  if #mine == 0 then mine[1] = Clean(self:Me() or "") end
  self:Send(target, format("G%s~%d~%s", self:AccountId(), time(), table.concat(mine, ",")))
  for id, a in pairs(self:Accounts()) do
    local names = {}
    for lname in pairs(a.names or {}) do names[#names + 1] = Clean(Proper(lname)) end
    if #names > 0 then
      self:Send(target, format("G%s~%d~%s", id, a.t or time(), table.concat(names, ",")))
    end
  end
  for id, t in pairs(self:Removed()) do
    self:Send(target, format("Z%s~%d", id, t))
  end
end

function Y:SendCharacters(target, force)
  if not ns.Chars then return end
  local s = self:Session(target)
  s.sent = s.sent or {}
  for _, c in ipairs(ns.Chars:Everyone()) do
    local key = "P:" .. strlower(c.name)
    -- compare the contents, not the timestamp (gold often changes within a second)
    local sig = format("%d|%d|%s|%d|%s", c.money or 0, c.t or 0, c.class or "", c.level or 0, c.profText or "")
    if force or s.sent[key] ~= sig then
      s.sent[key] = sig
      self:Send(target, format("P%s~%d~%d~%s~%d~%s", Clean(c.name), c.money or 0, c.t or 0,
        Clean(c.class or ""), c.level or 0, Clean(c.profText or "")))
    end
  end
end

function Y:SendDigests(target, full)
  local s = self:Session(target)
  if full then s.sent = {} end
  s.sent = s.sent or {}
  self:SendAccounts(target)
  self:SendCharacters(target, full)

  for prof in pairs(ns.db.recipes or {}) do
    local count, sum = self:Digest(prof)
    local key = "S:" .. prof
    if full or s.sent[key] ~= sum then
      s.sent[key] = sum
      self:Send(target, format("S%s~%d~%s", Clean(prof), count, sum))
    end
  end
  if full then self:Send(target, "S*") end

  for lchar, profs in pairs(self:KnowSets()) do
    for prof, set in pairs(profs) do
      local key = "W:" .. lchar .. ":" .. prof
      if full or s.sent[key] ~= set.hash then
        s.sent[key] = set.hash
        self:Send(target, format("W%s~%s~%d~%s~%d", Clean(Proper(lchar)), Clean(prof),
          self:KnowTime(lchar, prof), set.hash, set.count))
      end
    end
  end

  if ns.MarketKey and ns.FullScan then
    local latest = ns.FullScan:LatestScan()
    self:Send(target, format("A%s~%d", Clean(ns.MarketKey()), latest and latest.t or 0))
  end
end

---------------------------------------------------------------------------
-- Invitations
---------------------------------------------------------------------------
function Y:Invite(name)
  name = Proper(strtrim(name or ""))
  if not name or name == "" then return false, "Type a character name." end
  if strlower(name) == strlower(self:Me() or "") then return false, "That's the character you're playing." end
  if ns.Chars and ns.Chars:IsLocal(name) then return false, name .. " is on this account already." end
  if self:IsTrusted(name) then return false, name .. " is already linked." end
  self.invites[strlower(name)] = GetTime()
  self:SendBoth(name, "I" .. VERSION .. "~" .. self:AccountId())
  self:Log("Invitation sent to " .. name .. " - accept it on that account.")
  return true
end

StaticPopupDialogs["BARGAINHOUSE_SYNC_INVITE"] = {
  text = "%s invites this account to share professions, recipes, gold and auction scans.\n\nAccept only if %s is YOUR character on another account.",
  button1 = "Accept",
  button2 = "Ignore",
  OnAccept = function(self, data) ns.Sync:AnswerInvite(data or self.data, true) end,
  OnCancel = function(self, data, reason)
    if reason == "clicked" then ns.Sync:AnswerInvite(data or self.data, false) end
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
}

function Y:ShowInvite(name, id)
  self.pendingAsk = self.pendingAsk or {}
  self.pendingAsk[strlower(name)] = id
  local d = StaticPopup_Show("BARGAINHOUSE_SYNC_INVITE", name, name)
  if d then d.data = name end
  self:Log(name .. " invited this account to sync (waiting for your answer)")
end

function Y:AnswerInvite(name, accept)
  local id = self.pendingAsk and self.pendingAsk[strlower(name)]
  if not id then return end
  self.pendingAsk[strlower(name)] = nil
  if not accept then
    self:Log("Ignored the invitation from " .. name)
    return
  end
  self:LearnAccount(id, name)
  self:SendBoth(name, "J" .. VERSION .. "~" .. self:AccountId())
  self:Session(name).helloAt = nil
  self:Log("Accepted " .. name .. ": that account is now linked.")
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
function Y:OnMessage(prefix, msg, dist, sender)
  if prefix ~= PREFIX or not ns.db or not sender then return end
  if dist ~= "WHISPER" and dist ~= "GUILD" then return end
  if strlower(sender) == strlower(self:Me() or "") then return end
  if dist == "GUILD" then
    local target, rest = msg:match("^@([^~]+)~(.*)$")
    if not target or strlower(target) ~= strlower(self:Me() or "") then return end
    local kind = rest:sub(1, 1)
    if not self:IsTrusted(sender) and kind ~= "I" and kind ~= "J" and kind ~= "H" then return end
    msg = rest
  end
  local ok, err = pcall(self.Handle, self, msg, sender, dist)
  if not ok then self:Log("Error handling a message from " .. sender .. ": " .. tostring(err), true) end
end

function Y:Handle(msg, sender, dist)
  if not ns.db.syncEnabled then return end
  self:Log(format("<- %s (%s) %s", sender, dist or "WHISPER", msg:sub(1, 40)), true)
  local kind = msg:sub(1, 1)
  local key = strlower(sender)

  -- linking messages first (they can come from an account we don't know yet)
  if kind == "I" then
    local id = msg:match("^I%d+~(%x+)$")
    if not id then return end
    if self:IsTrusted(sender) or self.invites[key] then
      self:LearnAccount(id, sender)
      self.invites[key] = nil
      self:SendBoth(sender, "J" .. VERSION .. "~" .. self:AccountId())
      return
    end
    if not (self.pendingAsk and self.pendingAsk[key]) then self:ShowInvite(sender, id) end
    return
  elseif kind == "J" then
    local id = msg:match("^J%d+~(%x+)$")
    if not id then return end
    if self.invites[key] or self:IsTrusted(sender) then
      self.invites[key] = nil
      self:LearnAccount(id, sender)
      self:Session(sender).helloAt = nil
      self:SendBoth(sender, "H" .. VERSION .. "~" .. self:AccountId())
      self:Log(sender .. " accepted: that account is now linked.")
    end
    return
  end

  local helloId = msg:match("^H%d+~(%x+)$")
  if helloId == self:AccountId() and not (ns.Chars and ns.Chars:IsLocal(sender)) then
    -- two accounts ended up with the same ID: take a new one (once) and carry on
    if not self.idFixed then
      self.idFixed = true
      ns.db.accountId = self:NewAccountId()
      self:Log("Another account had the same sync ID; a new one was created.")
    end
    helloId = nil
  end
  if helloId then
    if self:IsTrusted(sender) then
      self:LearnAccount(helloId, sender)
    elseif self:Accounts()[helloId] and not self:Removed()[helloId] then
      self:LearnAccount(helloId, sender) -- another character of a linked account
    end
  end
  if not self:IsTrusted(sender) then
    if kind == "H" then self:Log("Ignored a hello from " .. sender .. " (not one of your accounts)", true) end
    return
  end

  local s = self:Session(sender)
  s.lastRecv = GetTime()
  s.lastSeenTime = time()
  if not s.channel or dist == "WHISPER" then s.channel = dist or "WHISPER" end
  if helloId then s.accountId = helloId end

  if kind == "H" then
    local fresh = not s.active or GetTime() - (s.lastHello or 0) > 60
    s.active, s.lastHello = true, GetTime()
    if fresh then
      self:Log(sender .. " connected (" .. strlower(s.channel or "whisper") .. ")")
      if not s.replied or GetTime() - s.replied > 60 then
        s.replied = GetTime()
        self:Send(sender, "H" .. VERSION .. "~" .. self:AccountId(), dist)
      end
      s.refreshAt = GetTime()
      self:SendDigests(sender, true)
    end

  elseif kind == "Y" then
    if not s.active then
      s.active = true
      self:Send(sender, "H" .. VERSION .. "~" .. self:AccountId())
    end

  elseif kind == "X" then
    s.active, s.channel, s.lastHello, s.replied = false, nil, nil, nil
    self:Log(sender .. " logged out")

  elseif kind == "G" then
    local id, t, names = msg:sub(2):match("^(%x+)~(%d+)~(.*)$")
    if not id then return end
    for name in names:gmatch("[^,]+") do
      self:LearnAccount(id, strtrim(name), tonumber(t))
    end

  elseif kind == "Z" then
    local id, t = msg:sub(2):match("^(%x+)~(%d+)$")
    if id and id ~= self:AccountId() then
      self:ForgetAccount(id, tonumber(t), true)
    end

  elseif kind == "P" then
    local name, money, t, class, level, profs = msg:sub(2):match("^(.-)~(%d+)~(%d+)~(.-)~(%d+)~(.*)$")
    if name and name ~= "" and ns.Chars then
      -- character updates are relayed for every account, so they never decide
      -- which account a character belongs to (that comes from G messages)
      ns.Chars:StoreRemote(name, { money = tonumber(money), t = tonumber(t), class = class,
        level = tonumber(level), profText = profs, via = sender })
    end

  elseif kind == "S" then
    local body = msg:sub(2)
    s.theirProfs = s.theirProfs or {}
    if body == "*" then
      for prof, book in pairs(ns.db.recipes or {}) do
        if not s.theirProfs[Clean(prof)] and next(book) then
          local records = {}
          for name, rec in pairs(book) do records[#records + 1] = Encode(name, rec) or "" end
          self:SendStream(sender, "R~" .. Clean(prof) .. "}" .. table.concat(records, "}"), #records .. " " .. prof .. " recipes")
        end
      end
      s.theirProfs = {}
      return
    end
    local prof, count, sum = body:match("^(.-)~(%d+)~(%x+)$")
    if not prof then return end
    s.theirProfs[prof] = true
    local myCount, mySum, hashes = self:Digest(prof)
    if tonumber(count) > 0 and (myCount ~= tonumber(count) or mySum ~= sum) then
      local parts = {}
      for h in pairs(hashes) do parts[#parts + 1] = h end
      local text = "L~" .. Clean(prof)
      if #parts > 0 then text = text .. "}" .. table.concat(parts, "}") end
      self:SendStream(sender, text, "my " .. prof .. " list")
    end

  elseif kind == "W" then
    local char, prof, t, hash = msg:sub(2):match("^(.-)~(.-)~(%d+)~(%x+)~%d+$")
    if not char then return end
    if ns.Chars and ns.Chars:IsLocal(char) then return end -- we know our own characters best
    -- remember what that character is said to know, so we can ask again by
    -- ourselves if the list never arrives (the sender won't repeat it)
    self.knownW = self.knownW or {}
    self.knownW[strlower(char) .. ":" .. prof] = { char = char, prof = prof, hash = hash, t = tonumber(t), from = sender }
    self:CheckKnown()

  elseif kind == "V" then
    local char, prof = msg:sub(2):match("^(.-)~(.*)$")
    if not char or not prof then return end
    local lchar = strlower(char)
    local profs = self:KnowSets()[lchar]
    local set = profs and profs[prof]
    if not set then return end
    self:SendStream(sender, format("E~%s~%s~%d}", Clean(Proper(lchar)), Clean(prof), self:KnowTime(lchar, prof))
      .. table.concat(set.hashes, "}"), format("what %s knows in %s", Proper(lchar), prof))

  elseif kind == "A" then
    local mkey, t = msg:sub(2):match("^(.-)~(%d+)$")
    t = tonumber(t)
    if not t or t == 0 or not ns.FullScan or not ns.MarketKey or mkey ~= Clean(ns.MarketKey()) then return end
    local latest = ns.FullScan:LatestScan()
    if (not latest or t > latest.t + 60) and not ns.FullScan.active and (s.scanRequested or 0) ~= t then
      s.scanRequested = t
      self:Send(sender, "Q" .. t)
    end

  elseif kind == "Q" then
    local t = tonumber(msg:sub(2))
    local latest = ns.FullScan and ns.FullScan:LatestScan()
    if not latest or not t or latest.t ~= t then return end
    local day = floor(latest.t / 86400)
    self:SendStream(sender, format("M~%d}", day) .. table.concat(ns.FullScan:MarketLines(day), "}"), "market prices")
    self:SendStream(sender, format("C~%d~%s}", latest.t, Clean(latest.from or self:Me())) .. table.concat(latest.cand or {}, "}"), "auction deals")

  elseif kind == "N" then
    local sid, list = msg:sub(2):match("^(%d+)~(.*)$")
    local o = sid and self.out[key .. ":" .. sid]
    if not o then return end
    local n = 0
    for i in list:gmatch("%d+") do
      i = tonumber(i)
      if o.chunks[i] then
        self:Send(sender, format("D%s~%d~%d~%s", sid, i, o.n, o.chunks[i]))
        n = n + 1
      end
    end
    o.t = GetTime()
    self:Log(format("Resending %d piece%s to %s", n, n == 1 and "" or "s", sender), true)

  elseif kind == "D" then
    local sid, i, n, payload = msg:match("^D(%d+)~(%d+)~(%d+)~(.*)$")
    if not sid then return end
    i, n = tonumber(i), tonumber(n)
    local bkey = key .. ":" .. sid
    local buf = self.buffers[bkey]
    if not buf then
      buf = { parts = {}, got = 0, sender = sender, sid = tonumber(sid), n = n }
      self.buffers[bkey] = buf
    end
    buf.t, buf.n = GetTime(), n
    if not buf.parts[i] then
      buf.parts[i] = payload
      buf.got = buf.got + 1
    end
    if buf.got >= n then
      self.buffers[bkey] = nil
      self:QueueStream(sender, table.concat(buf.parts, "", 1, n))
    end
  end
end

---------------------------------------------------------------------------
-- Applying streams
---------------------------------------------------------------------------
function Y:QueueStream(sender, text)
  local skind = text:sub(1, 1)
  local header, rest = text:match("^(.-)}(.*)$")
  if not header then header, rest = text, "" end
  local items = {}
  for part in rest:gmatch("[^}]+") do items[#items + 1] = part end
  local i = 0

  if skind == "L" then
    local prof = header:match("^L~(.*)$")
    local book = prof and ns.db.recipes and ns.db.recipes[prof]
    if not book then return end
    local has = {}
    for _, h in ipairs(items) do has[h] = true end
    local records, names = {}, {}
    for name in pairs(book) do names[#names + 1] = name end
    self.work[#self.work + 1] = { step = function(budget)
      local stop = math.min(#names, i + budget)
      for k = i + 1, stop do
        local name = names[k]
        if not has[Hash(name)] then records[#records + 1] = Encode(name, book[name]) or "" end
      end
      local used = stop - i
      i = stop
      return math.max(1, used), i >= #names
    end, done = function()
      if #records > 0 then
        Y:SendStream(sender, "R~" .. Clean(prof) .. "}" .. table.concat(records, "}"), #records .. " " .. prof .. " recipes")
      end
    end }

  elseif skind == "R" then
    local prof = header:match("^R~(.*)$")
    if not prof or prof == "" then return end
    ns.db.recipes = ns.db.recipes or {}
    local book = ns.db.recipes[prof] or {}
    ns.db.recipes[prof] = book
    local added = 0
    self.work[#self.work + 1] = { step = function(budget)
      local stop = math.min(#items, i + budget)
      for k = i + 1, stop do
        local name, rec = Decode(items[k])
        if name and not book[name] then
          book[name] = rec
          added = added + 1
        end
      end
      local used = stop - i
      i = stop
      return math.max(1, used), i >= #items
    end, done = function()
      if added > 0 then
        Y:Log(format("Received %d %s recipes from %s", added, prof, sender))
        if ns.Crafting and ns.Crafting.OnRecipesChanged and ns.Crafting.frame and ns.Crafting.frame:IsVisible() then
          ns.Crafting:OnRecipesChanged()
        end
        -- crafter lists that mentioned recipes we lacked can be applied now
        Y.requested = {}
        Y.incomplete = {}
        Y:CheckKnown()
      end
    end }

  elseif skind == "E" then
    local char, prof, t = header:match("^E~(.-)~(.-)~(%d+)$")
    if not char then return end
    local proper, lchar = Proper(char), strlower(char)
    local book = ns.db.recipes and ns.db.recipes[prof]
    if not book then return end
    if ns.Chars and ns.Chars:IsLocal(proper) then return end
    local set, byHash, names, missing, changed = {}, {}, {}, 0, 0
    for _, h in ipairs(items) do set[h] = true end
    for name in pairs(book) do
      names[#names + 1] = name
      byHash[Hash(name)] = name
    end
    for h in pairs(set) do
      if not byHash[h] then missing = missing + 1 end
    end
    self.work[#self.work + 1] = { step = function(budget)
      local stop = math.min(#names, i + budget)
      for k = i + 1, stop do
        local name = names[k]
        local rec = book[name]
        local knows = set[Hash(name)] and true or false
        rec.k = rec.k or {}
        if knows and rec.k[proper] ~= "own" then
          rec.k[proper] = "own"
          changed = changed + 1
        elseif not knows and rec.k[proper] == "own" then
          rec.k[proper] = nil
          changed = changed + 1
        end
      end
      local used = stop - i
      i = stop
      return math.max(1, used), i >= #names
    end, done = function()
      if missing == 0 then
        Y:SetKnowTime(lchar, prof, tonumber(t))
      else
        -- some of those recipes are unknown here: retry once the recipes arrive
        Y.incomplete = Y.incomplete or {}
        Y.incomplete[lchar .. ":" .. prof] = sender
      end
      if changed > 0 then
        Y:Log(format("%s knows %d %s recipes (from %s)", proper, #items, prof, sender))
        if ns.Crafting and ns.Crafting.OnRecipesChanged and ns.Crafting.frame and ns.Crafting.frame:IsVisible() then
          ns.Crafting:OnRecipesChanged()
        end
      end
    end }

  elseif skind == "M" then
    local day = tonumber(header:match("^M~(%d+)$"))
    if not day or not ns.FullScan then return end
    self.work[#self.work + 1] = { step = function(budget)
      local stop = math.min(#items, i + budget)
      local slice = {}
      for k = i + 1, stop do slice[#slice + 1] = items[k] end
      ns.FullScan:MergeMarket(day, slice)
      local used = stop - i
      i = stop
      return math.max(1, used), i >= #items
    end, done = function()
      Y:Log(format("Market prices updated from %s (%d items)", sender, #items))
    end }

  elseif skind == "C" then
    local t, origin = header:match("^C~(%d+)~(.*)$")
    t = tonumber(t)
    if not t or not ns.FullScan then return end
    self.work[#self.work + 1] = { step = function()
      local latest = ns.FullScan:LatestScan()
      if latest and latest.t >= t then return 1, true end
      local who = (origin and origin ~= "") and origin or sender
      ns.FullScan:StoreRemote(t, who, items)
      Y:Log(format("Auction scan from %s: %d deal candidates", who, #items))
      if ns.DealsTab and ns.DealsTab.list then
        ns.DealsTab:Refresh()
        ns.DealsTab:UpdateStatus()
      end
      return math.max(1, #items), true
    end }
  end
end

---------------------------------------------------------------------------
-- Local changes
---------------------------------------------------------------------------
function Y:ForActive(fn)
  local targets = self:Targets()
  for key, s in pairs(self.sessions) do
    if s.active and targets[key] then fn(targets[key]) end
  end
end

function Y:RecipesChanged()
  if not ns.db or not ns.db.syncEnabled then return end
  self.dirtyToken = {}
  local token = self.dirtyToken
  ns.After(5, function()
    if Y.dirtyToken ~= token then return end
    Y:ForActive(function(name) Y:SendDigests(name) end)
  end)
end

function Y:ScanChanged()
  if not ns.db or not ns.db.syncEnabled or not ns.MarketKey then return end
  local latest = ns.FullScan:LatestScan()
  self:ForActive(function(name) Y:Send(name, format("A%s~%d", Clean(ns.MarketKey()), latest and latest.t or 0)) end)
end

function Y:CharacterChanged()
  if not ns.db or not ns.db.syncEnabled then return end
  local wait = 60 - (GetTime() - (self.charSentAt or -1e9))
  if wait > 0 then
    if not self.charPending then
      self.charPending = true
      ns.After(wait, function()
        Y.charPending = false
        Y:CharacterChanged()
      end)
    end
    return
  end
  self.charSentAt = GetTime()
  self:ForActive(function(name) Y:SendCharacters(name) end)
end

function Y:ForgetAccount(id, t, fromPartner)
  if not id then return end
  local a = self:Accounts()[id]
  self:Removed()[id] = t or time()
  if a then
    for lname in pairs(a.names or {}) do
      self.sessions[lname] = nil
      if ns.Chars then ns.Chars:ForgetRemote(Proper(lname)) end
    end
    self:Accounts()[id] = nil
    self:Log(fromPartner and "An account was unlinked on another account" or "Account unlinked")
  end
  if not fromPartner then
    self:ForActive(function(name) Y:Send(name, format("Z%s~%d", id, t or time())) end)
  end
end

function Y:ConnectNow()
  for _, s in pairs(self.sessions) do
    s.active, s.helloAt, s.channel, s.refreshAt, s.sent = false, nil, nil, nil, nil
  end
  self.requested = {}
  self:Log("Looking for your other accounts...")
  self:Maintain()
end

function Y:IsOnline(name)
  local s = name and self.sessions[strlower(name)]
  return s and s.active
end

function Y:Status()
  local out = {}
  for _, a in ipairs(self:AccountList()) do
    out[#out + 1] = format("%s: %s", table.concat(a.names, ", "),
      a.connected and ("connected as " .. a.connected) or "not connected")
  end
  return out
end

function Y:Stats()
  local accounts, connected = 0, 0
  for _, a in ipairs(self:AccountList()) do
    accounts = accounts + 1
    if a.connected then connected = connected + 1 end
  end
  local queued = self.control.bytes + self.bulk.bytes
  local receiving, total = 0, 0
  for _, buf in pairs(self.buffers) do
    receiving = receiving + buf.got
    total = total + (buf.n or 0)
  end
  return { accounts = accounts, connected = connected, queued = queued, eta = queued / CPS,
           receiving = receiving, receiveTotal = total, work = #self.work }
end

Y:RegisterEvent("CHAT_MSG_ADDON")
Y:RegisterEvent("PLAYER_LOGIN")
Y:RegisterEvent("PLAYER_LOGOUT")
Y:RegisterEvent("CHAT_MSG_SYSTEM")
Y:RegisterEvent("FRIENDLIST_UPDATE")
Y:RegisterEvent("GUILD_ROSTER_UPDATE")
Y:SetScript("OnEvent", function(self, event, ...)
  if event == "CHAT_MSG_ADDON" then
    self:OnMessage(...)
  elseif event == "CHAT_MSG_SYSTEM" then
    local msg = ...
    if type(msg) == "string" and ns.db then
      local name = NameFrom(msg, ONLINE_PAT)
      if name then
        self:Sighted(name, true)
      else
        name = NameFrom(msg, OFFLINE_PAT) or NameFrom(msg, NOTFOUND_PAT)
        if name then self:Sighted(name, false) end
      end
    end
  elseif event == "FRIENDLIST_UPDATE" or event == "GUILD_ROSTER_UPDATE" then
    -- these fire as soon as someone logs in or out
    if ns.db then self.maintainSoon = true end
  elseif event == "PLAYER_LOGIN" then
    self.me = UnitName("player")
    self.helloTimer = 8
  elseif event == "PLAYER_LOGOUT" then
    local targets = ns.db and self:Targets() or {}
    for key, s in pairs(self.sessions) do
      if s.active and targets[key] then
        if s.channel == "GUILD" and IsInGuild and IsInGuild() then
          SendAddonMessage(PREFIX, "@" .. targets[key] .. "~X", "GUILD")
        else
          SendAddonMessage(PREFIX, "X", "WHISPER", targets[key])
        end
      end
    end
  end
end)
