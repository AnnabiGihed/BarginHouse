local ADDON, ns = ...
_G.BargainHouse = ns

ns.VERSION = "1.0.0"
ns.ACCENT = "|cff33d999"
ns.TIME_LEFT = { "<30m", "<2h", "<12h", "48h" }

local floor, format = math.floor, string.format

ns.DEFAULTS = {
  replaceBlizzard = true,
  tooltipPrices = true,
  searchMode = "CONTAINS",
  maxPages = 25,
  hideBidOnly = false,
  undercut = 1,        -- copper
  undercutPct = 0,     -- percent
  bidPct = 90,         -- starting bid as % of buyout
  duration = 2,        -- 1 = 12h, 2 = 24h, 3 = 48h
  scale = 1,
  history = {},
  favorites = {},
  confirmBuy = true,
  minimap = { angle = 200, hide = false },
  syncEnabled = true,
  remoteScan = {},
  remoteChars = {},
  syncAccounts = {},   -- account IDs of your other accounts and their characters    -- characters on your other accounts (gold, professions)
  syncPartners = "",   -- older versions: manually listed characters (migrated automatically)
  syncAccounts = {},   -- linked accounts (Sync tab)
  syncRemoved = {},
  syncVerbose = false,
  knowT = {},          -- when each character's recipe list was last updated
  allowExtra = true,
  watch = {},          -- Deals tab watchlist
  watchEnabled = true,
  watchInterval = 15,  -- seconds between two watchlist checks
  watchMargin = 20,    -- percent under market value counts as a deal
  scrollVellum = true, -- enchanting: price the vellum and sell as a scroll   -- buy a bigger stack when that is cheaper in total
  vendorBuy = {},       -- merchant prices seen (unlimited stock items)
  manualPrice = {},     -- reagent prices typed by the player
  market = {},         -- daily price summaries per realm-faction (full scans)
  lastScan = {},
  mail = {},           -- recorded mailboxes per realm/character
  transit = {},        -- purchases on their way to the mailbox
  useGuildBank = true,
  useBank = true,
  useAlts = true,
  inventory = {},      -- recorded bags + personal bank per realm/character
  itemNames = {},
  guildBank = {},     -- recorded full-access guild bank tabs, per realm+guild
  recipes = {},        -- recorded from profession windows (account-wide)
  craftQueue = {},
  shoppingText = "",
  shoppingBank = false,
  shoppingIgnoreHave = false,
  prices = {},         -- [itemID] = { l = last lowest, a = rolling avg, n = samples, t = time }
}

local function CopyDefaults(src, dst)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      CopyDefaults(v, dst[k])
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
function ns.Print(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
  DEFAULT_CHAT_FRAME:AddMessage(ns.ACCENT .. "BargainHouse|r: " .. table.concat(parts, " "))
end

function ns.Me()
  return UnitName("player")
end

local function Commas(n)
  local s, k = tostring(n), 0
  repeat s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2") until k == 0
  return s
end

ns.GOLD_ICON = "Interface\\MoneyFrame\\UI-GoldIcon"
ns.SILVER_ICON = "Interface\\MoneyFrame\\UI-SilverIcon"
ns.COPPER_ICON = "Interface\\MoneyFrame\\UI-CopperIcon"
local G = "|T" .. ns.GOLD_ICON .. ":0:0:2:0|t"
local S = "|T" .. ns.SILVER_ICON .. ":0:0:2:0|t"
local CP = "|T" .. ns.COPPER_ICON .. ":0:0:2:0|t"

-- Money string with gold / silver / copper coin icons
function ns.Money(copper, showZero)
  copper = floor((copper or 0) + 0.5)
  if copper <= 0 then
    if not showZero then return "|cff555555--|r" end
    copper = 0
  end
  local g, s, c = floor(copper / 10000), floor(copper / 100) % 100, copper % 100
  if g > 0 then
    return format("%s%s %02d%s %02d%s", Commas(g), G, s, S, c, CP)
  elseif s > 0 then
    return format("%d%s %02d%s", s, S, c, CP)
  end
  return format("%d%s", c, CP)
end

-- Compact money for narrow columns (exact value in tooltips)
function ns.MoneyShort(copper)
  copper = floor((copper or 0) + 0.5)
  if copper <= 0 then return "|cff555555--|r" end
  local g, s, c = floor(copper / 10000), floor(copper / 100) % 100, copper % 100
  if g > 0 then return format("%s%s %02d%s", Commas(g), G, s, S) end
  if s > 0 then return format("%d%s %02d%s", s, S, c, CP) end
  return format("%d%s", c, CP)
end

---------------------------------------------------------------------------
-- Cheapest way to buy at least `need` items from a set of auctions.
-- Stacks can't be split, so this is a small min-cost knapsack (exact over
-- the candidate set). Returns { auctions, count, cost, need, short }.
---------------------------------------------------------------------------
function ns.PlanPurchase(auctions, need, me, allowExtra)
  if allowExtra == nil then allowExtra = not (ns.db and ns.db.allowExtra == false) end
  local cand, available, maxCount = {}, 0, 1
  for _, a in ipairs(auctions) do
    if a.buyout > 0 and a.owner ~= me then
      cand[#cand + 1] = a
      available = available + a.count
      if a.count > maxCount then maxCount = a.count end
    end
  end
  table.sort(cand, function(x, y)
    if x.unit ~= y.unit then return x.unit < y.unit end
    return x.count < y.count
  end)

  local plan = { auctions = {}, count = 0, cost = 0, need = need, extra = 0 }
  if #cand == 0 then plan.short = true return plan end

  if available <= need then
    for _, a in ipairs(cand) do
      plan.auctions[#plan.auctions + 1] = a
      plan.count = plan.count + a.count
      plan.cost = plan.cost + a.buyout
    end
    plan.short = available < need
    return plan
  end

  -- keep the cheapest offers only (plenty of slack so the optimum is almost always inside)
  local pool, cum = {}, 0
  for _, a in ipairs(cand) do
    pool[#pool + 1] = a
    cum = cum + a.count
    -- exact amounts can need pricier small stacks: consider everything then
    if (allowExtra and cum >= need * 2 + maxCount and #pool >= 8) or #pool >= 400 then break end
  end

  local INF = math.huge
  local take, target = {}, nil

  if allowExtra then
    -- dp[j] = cheapest cost for at least j items (j capped at need)
    local dp = { [0] = 0 }
    for j = 1, need do dp[j] = INF end
    for i, a in ipairs(pool) do
      local c, cost, row = a.count, a.buyout, {}
      for j = need - 1, 0, -1 do
        local base = dp[j]
        if base < INF then
          local nj = j + c
          if nj > need then nj = need end
          if base + cost < dp[nj] then
            dp[nj] = base + cost
            row[nj] = j
          end
        end
      end
      take[i] = row
    end
    if dp[need] < INF then target = need end
  else
    -- dp[j] = cheapest cost for exactly j items; pick the smallest j >= need
    local cap = need + maxCount - 1
    local dp = { [0] = 0 }
    for j = 1, cap do dp[j] = INF end
    for i, a in ipairs(pool) do
      local c, cost, row = a.count, a.buyout, {}
      for j = cap - c, 0, -1 do
        local base = dp[j]
        if base < INF and base + cost < dp[j + c] then
          dp[j + c] = base + cost
          row[j + c] = j
        end
      end
      take[i] = row
    end
    for j = need, cap do
      if dp[j] < INF then target = j break end
    end
  end

  if not target then plan.short = true return plan end
  local j = target
  for i = #pool, 1, -1 do
    local prev = take[i][j]
    if prev then
      local a = pool[i]
      table.insert(plan.auctions, 1, a)
      plan.count = plan.count + a.count
      plan.cost = plan.cost + a.buyout
      j = prev
      if j == 0 then break end
    end
  end
  plan.extra = math.max(0, plan.count - need)
  return plan
end

function ns.ItemID(link)
  return link and tonumber(link:match("item:(%-?%d+)"))
end

function ns.QualityHex(q)
  local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q or 1]
  if c then return format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) end
  return "|cffffffff"
end

function ns.TimeAgo(sec)
  if sec < 60 then return "just now" end
  if sec < 3600 then return floor(sec / 60) .. "m ago" end
  if sec < 86400 then return floor(sec / 3600) .. "h ago" end
  return floor(sec / 86400) .. "d ago"
end

-- Tiny timer
-- Tiny timer (the frame only runs while something is scheduled)
local timers, timerFrame = {}, CreateFrame("Frame")
timerFrame:Hide()
timerFrame:SetScript("OnUpdate", function(self)
  local now = GetTime()
  for i = #timers, 1, -1 do
    local t = timers[i]
    if t and now >= t.at then
      table.remove(timers, i)
      t.fn()
    end
  end
  if #timers == 0 then self:Hide() end
end)
function ns.After(delay, fn)
  timers[#timers + 1] = { at = GetTime() + delay, fn = fn }
  timerFrame:Show()
end

---------------------------------------------------------------------------
-- Search matching
-- Returns: text to send to the server (substring), and a client-side matcher
---------------------------------------------------------------------------
function ns.BuildMatcher(text, mode)
  local t = strlower(text or "")
  if t == "" then return "", function() return true end end

  if mode == "EXACT" then
    return text, function(n) return strlower(n) == t end
  elseif mode == "STARTS" then
    return text, function(n) return strlower(n):sub(1, #t) == t end
  elseif mode == "ENDS" then
    return text, function(n) n = strlower(n); return #n >= #t and n:sub(-#t) == t end
  elseif mode == "WORDS" then
    local words, longest = {}, ""
    for w in t:gmatch("%S+") do
      words[#words + 1] = w
      if #w > #longest then longest = w end
    end
    return longest, function(n)
      n = strlower(n)
      for _, w in ipairs(words) do
        if not n:find(w, 1, true) then return false end
      end
      return true
    end
  elseif mode == "WILDCARD" then
    local longest = ""
    for seg in t:gmatch("[^%*%?]+") do
      if #seg > #longest then longest = seg end
    end
    local pat = t:gsub("[%^%$%(%)%%%.%[%]%+%-]", "%%%0")
    pat = pat:gsub("%*", ".*")
    pat = pat:gsub("%?", ".")
    pat = "^" .. pat .. "$"
    return longest, function(n) return strlower(n):find(pat) ~= nil end
  end

  -- CONTAINS
  return text, function(n) return strlower(n):find(t, 1, true) ~= nil end
end

-- Find an auction (captured earlier) in the currently loaded "list" page
function ns.FindInList(a)
  local batch = GetNumAuctionItems("list")
  for i = 1, batch do
    local name, _, count, _, _, _, _, _, buyout, _, _, owner = GetAuctionItemInfo("list", i)
    if name == a.name and count == a.count and (buyout or 0) == a.buyout
      and (not a.owner or not owner or owner == a.owner)
      and GetAuctionItemLink("list", i) == a.link then
      return i
    end
  end
end

---------------------------------------------------------------------------
-- Price database
---------------------------------------------------------------------------
function ns.RecordPrice(id, unit)
  if not id or not unit or unit <= 0 then return end
  local prices = ns.db.prices
  local p, now = prices[id], time()
  if not p then
    prices[id] = { l = floor(unit), a = floor(unit), n = 1, t = now }
    return
  end
  local w = math.min(p.n, 9)
  p.a = floor((p.a * w + unit) / (w + 1))
  p.l = floor(unit)
  p.n = p.n + 1
  p.t = now
end

local function AddTooltipPrices(tt)
  if not ns.db or not ns.db.tooltipPrices then return end
  local _, link = tt:GetItem()
  local id = ns.ItemID(link)
  local p = id and ns.db.prices[id]
  if not p then return end
  tt:AddDoubleLine(ns.ACCENT .. "AH lowest|r |cff888888(" .. ns.TimeAgo(time() - p.t) .. ")|r", ns.Money(p.l), 1, 1, 1, 1, 1, 1)
  if p.n > 1 then
    tt:AddDoubleLine(ns.ACCENT .. "AH average|r", ns.Money(p.a), 1, 1, 1, 1, 1, 1)
  end
  tt:Show()
end

function ns.InsertLinkName(name, link)
  local box = ns.focusedBox
  if not (box and box.acceptsLinks and box:IsVisible()) then
    box = ns.Browse and ns.Browse.search
    if not (box and box:IsVisible()) then return end
  end
  if box.acceptsLinks == "insert" then
    box:Insert(name)
  else
    if not (link and link:find("item:", 1, true)) and box == (ns.Browse and ns.Browse.search) then return end
    box:SetText(name)
    box:HighlightText(0, 0)
    if box.SetCursorPosition then box:SetCursorPosition(#name) end
  end
end

---------------------------------------------------------------------------
-- History / favorites
---------------------------------------------------------------------------
function ns.AddHistory(text, mode)
  if not text or text == "" then return end
  local h = ns.db.history
  for i = #h, 1, -1 do
    if h[i].t == text and h[i].m == mode then table.remove(h, i) end
  end
  table.insert(h, 1, { t = text, m = mode })
  while #h > 15 do table.remove(h) end
end

function ns.IsFavorite(text, mode)
  for i, f in ipairs(ns.db.favorites) do
    if f.t == text and f.m == mode then return i end
  end
end

function ns.ToggleFavorite(text, mode)
  local i = ns.IsFavorite(text, mode)
  if i then
    table.remove(ns.db.favorites, i)
  elseif text and text ~= "" then
    table.insert(ns.db.favorites, { t = text, m = mode })
  end
end

---------------------------------------------------------------------------
-- Auction house replacement
---------------------------------------------------------------------------
function ns.ApplyReplace()
  if ns.db.replaceBlizzard then
    UIParent:UnregisterEvent("AUCTION_HOUSE_SHOW")
  else
    UIParent:RegisterEvent("AUCTION_HOUSE_SHOW")
  end
end

function ns.OpenMain()
  if not ns.main then ns.CreateMain() end
  ns.main:Show()
  ns.main:SetMode(true)
end

-- Open anywhere (minimap button): auction features only at an auctioneer
function ns.ToggleMain(tab)
  if not ns.main then ns.CreateMain() end
  if ns.main:IsShown() and (not tab or ns.main.current == tab) then
    ns.main:Hide()
    return
  end
  ns.main:Show()
  ns.main:SetMode(ns.atAH and true or false)
  if tab then ns.main:SelectTab(tab) end
end

function ns.HideMainSilently()
  if ns.main and ns.main:IsShown() then
    ns.suppressClose = true
    ns.main:Hide()
    ns.suppressClose = false
  end
end

function ns.OpenBlizzard()
  if not ns.atAH then return end
  ns.HideMainSilently()
  if not AuctionFrame then LoadAddOn("Blizzard_AuctionUI") end
  if AuctionFrame then
    ShowUIPanel(AuctionFrame)
  end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("AUCTION_HOUSE_SHOW")
ev:RegisterEvent("AUCTION_HOUSE_CLOSED")
ev:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    BargainHouseDB = BargainHouseDB or {}
    CopyDefaults(ns.DEFAULTS, BargainHouseDB)
    ns.db = BargainHouseDB
    ns.ApplyReplace()

    GameTooltip:HookScript("OnTooltipSetItem", AddTooltipPrices)
    ItemRefTooltip:HookScript("OnTooltipSetItem", AddTooltipPrices)

    -- Shift-click an item (bags, chat, tooltips, lists) -> put its name in our
    -- search / list boxes, like the default auction house does
    if ChatEdit_InsertLink then
      hooksecurefunc("ChatEdit_InsertLink", function(text)
        if not text or not ns.main or not ns.main:IsShown() then return end
        if ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() then return end -- chat gets the link
        local name = text:match("|h%[(.-)%]|h")
        if not name or name == "" then return end
        ns.InsertLinkName(name, text)
      end)
    end

    ns.CreateMinimapButton()

    if ContainerFrameItemButton_OnModifiedClick then
      hooksecurefunc("ContainerFrameItemButton_OnModifiedClick", function(btn, button)
        if button == "LeftButton" and IsAltKeyDown() and ns.atAH and ns.main and ns.main:IsShown() then
          ns.Sell:SetItemFromBag(btn:GetParent():GetID(), btn:GetID())
        end
      end)
    end
    self:UnregisterEvent("ADDON_LOADED")

  elseif event == "AUCTION_HOUSE_SHOW" then
    ns.atAH = true
    if ns.db.replaceBlizzard then ns.OpenMain() end

  elseif event == "AUCTION_HOUSE_CLOSED" then
    ns.atAH = false
    ns.Scanner:Stop()
    ns.HideMainSilently()
  end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SLASH_BARGAINHOUSE1 = "/bh"
SLASH_BARGAINHOUSE2 = "/bargainhouse"
SlashCmdList.BARGAINHOUSE = function(msg)
  msg = strlower(strtrim(msg or ""))
  if msg == "toggle" or msg == "blizzard" then
    ns.db.replaceBlizzard = not ns.db.replaceBlizzard
    ns.ApplyReplace()
    ns.Print("Replace default auction house:", ns.db.replaceBlizzard and "|cff33d999ON|r" or "|cffff5555OFF|r")
  elseif msg == "reset" then
    ns.db.pos, ns.db.scale = nil, 1
    if ns.main then
      ns.main:SetScale(1)
      ns.main:ClearAllPoints()
      ns.main:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    end
    ns.Print("Window position and scale reset.")
  elseif msg == "clearprices" then
    wipe(ns.db.prices)
    ns.Print("Price database cleared.")
  elseif msg == "guild" or msg == "guildbank" then
    local info, why = ns.GuildBankInfo()
    if info then
      ns.Print(format("Guild bank (%s): %d items in %d full-access tab%s, recorded %s.", info.guild, info.items, info.tabs, info.tabs == 1 and "" or "s", ns.TimeAgo(time() - info.t)))
    else
      ns.Print("Guild bank: " .. why)
    end
  elseif msg == "autobuy" then
    ns.db.clickMode = false
    ns.Print("Automatic buying re-enabled. If the server blocks it again, page mode switches back on by itself.")
  elseif msg == "show" then
    if ns.atAH then ns.OpenMain() else ns.ToggleMain() end
  elseif msg == "minimap" then
    ns.ToggleMinimapButton()
  else
    ns.Print("v" .. ns.VERSION .. " commands:")
    ns.Print("  /bh show - open the window (anywhere; auction features at an auctioneer)")
    ns.Print("  /bh minimap - show / hide the minimap button")
    ns.Print("  /bh toggle - enable/disable replacing the default auction house")
    ns.Print("  /bh reset - reset window position and scale")
    ns.Print("  /bh clearprices - wipe the recorded price history")
    ns.Print("  /bh guild - show what is recorded from your guild bank")
    ns.Print("  /bh autobuy - switch back to automatic buying after a block")
  end
end
