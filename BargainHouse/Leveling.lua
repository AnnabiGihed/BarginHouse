local ADDON, ns = ...
local format, floor, ceil = string.format, math.floor, math.ceil

-- Works out the cheapest way to raise a profession.
--
-- Each craft has a chance of giving a skill point that depends on its colour at
-- your current skill: orange always, yellow usually, green sometimes, grey never.
-- So the cost of one point is (materials - what you get back) / chance, and the
-- cheapest plan is found by walking skill by skill and taking the best recipe at
-- each point.
--
-- Thresholds come from ns.ProfessionData. A few are marked estimated (c=0);
-- anything seen in your own profession window corrects them for good.

local P = {}
ns.Leveling = P

-- Chance that one craft gives a skill point.
--
-- While a recipe is orange every craft gives a point. From the yellow threshold
-- it falls away in a straight line and reaches zero at grey:
--
--     chance = (grey - your skill) / (grey - yellow)
--
-- This is the model trade-skill calculators use and it matches what happens in
-- game. An earlier version assumed 75% at yellow and about 25% in green, which
-- asked you to buy roughly twice the materials you actually needed.

-- How many skill points one successful craft gives. Retail rules give 1;
-- Warmane's Icecrown and other boosted realms give 3. Set in the Level up tab,
-- or left on auto, where it is worked out from your own skill-ups.
function P:Gain()
  local set = ns.db.skillGain
  if set and set > 0 then return set end
  local seen = ns.db.skillGainSeen or {}
  local best, bestN = 1, 0
  for step, n in pairs(seen) do
    if n > bestN then best, bestN = step, n end
  end
  return best
end

function P:GainDetected()
  local seen = ns.db.skillGainSeen or {}
  local best, bestN, total = nil, 0, 0
  for step, n in pairs(seen) do
    total = total + n
    if n > bestN then best, bestN = step, n end
  end
  return best, total
end

-- called when a profession's skill went up by some amount
function P:NoteSkillUp(step)
  if not step or step < 1 or step > 25 then return end
  ns.db.skillGainSeen = ns.db.skillGainSeen or {}
  ns.db.skillGainSeen[step] = (ns.db.skillGainSeen[step] or 0) + 1
end

function P:Professions()
  local out = {}
  for prof in pairs(ns.ProfessionData or {}) do out[#out + 1] = prof end
  table.sort(out)
  return out
end

-- where a profession stops (Fishing has no crafts, so it never appears)
local maxSkill = {}
function P:MaxSkill(prof)
  if maxSkill[prof] then return maxSkill[prof] end
  local top = 1
  for _, rec in ipairs(self:Recipes(prof) or {}) do
    if rec.x and rec.x > top then top = rec.x end
  end
  local capped = math.min(450, math.max(75, math.ceil(top / 25) * 25))
  maxSkill[prof] = capped
  return capped
end

-- The data is held as text; the profession being planned is unpacked on demand
-- and released when you switch, so memory stays small. Unpacking costs 1-3 ms.
local unpacked, order = {}, {}

local function ParseProfession(text)
  local list = {}
  for line in text:gmatch("[^\n]+") do
    local s, n, i, m, o, y, g, x, ri, c, src, reagents =
      line:match("^(%d+)\t(.-)\t(%d+)\t(%d+)\t(%d+)\t(%d+)\t(%d+)\t(%d+)\t(%d+)\t(%d)\t(.-)\t(.*)$")
    if s then
      local r = {}
      for id, count in reagents:gmatch("(%d+):(%d+)") do
        r[#r + 1] = { tonumber(id), tonumber(count) }
      end
      list[#list + 1] = { s = tonumber(s), n = n, i = tonumber(i), m = tonumber(m),
                          o = tonumber(o), y = tonumber(y), g = tonumber(g), x = tonumber(x),
                          ri = tonumber(ri), c = tonumber(c), src = src, r = r }
    end
  end
  return list
end

function P:Recipes(prof)
  if not prof then return nil end
  local have = unpacked[prof]
  if have then return have end
  local raw = (ns.ProfessionData or {})[prof]
  if not raw then return nil end
  if type(raw) == "table" then return raw end           -- already unpacked data
  local list = ParseProfession(raw)
  unpacked[prof] = list
  order[#order + 1] = prof
  while #order > 1 do                                    -- only the one in use is kept
    local drop = table.remove(order, 1)
    if drop ~= prof then unpacked[drop] = nil end
  end
  return list
end

function P:ForgetUnpacked()
  unpacked, order = {}, {}
end

---------------------------------------------------------------------------
-- Learned corrections: what the game itself told us
---------------------------------------------------------------------------
function P:Learned()
  ns.db.skillBands = ns.db.skillBands or {}
  return ns.db.skillBands
end

-- Called while a profession window is open: the colour of a recipe at a known
-- skill pins down where its bands are.
function P:Observe(prof, spellOrName, difficulty, skill)
  if not prof or not difficulty or not skill then return end
  local rec = self:Find(prof, spellOrName)
  if not rec then return end
  local band = self:Learned()
  local key = tostring(rec.s)
  local b = band[key] or {}
  band[key] = b
  -- optimal = orange, medium = yellow, easy = green, trivial = grey
  if difficulty == "optimal" then
    b.oMax = math.min(b.oMax or 1e9, skill)      -- still orange here
    b.yMin = math.max(b.yMin or 0, skill + 1)
  elseif difficulty == "medium" then
    b.yMax = math.max(b.yMax or 0, skill)
    b.oMin = math.max(b.oMin or 0, 0)
    b.yellowAt = math.min(b.yellowAt or 1e9, skill)
  elseif difficulty == "easy" then
    b.greenAt = math.min(b.greenAt or 1e9, skill)
  elseif difficulty == "trivial" then
    b.greyAt = math.min(b.greyAt or 1e9, skill)
  end
  self.dirty = true
end

-- does the character playing know this recipe? (recorded from profession windows)
function P:Knows(prof, rec)
  local book = ns.db.recipes and ns.db.recipes[prof]
  local entry = book and book[rec.n]
  if not entry then return false end
  local me = UnitName("player")
  for who, kind in pairs(entry.k or {}) do
    if kind == "own" and who == me then return true end
  end
  return false
end

function P:Find(prof, spellOrName)
  for _, rec in ipairs(self:Recipes(prof) or {}) do
    if rec.s == spellOrName or rec.n == spellOrName then return rec end
  end
end

-- thresholds for a recipe, with anything learned in game taking precedence
function P:Bands(rec)
  local o, y, g, x, confirmed = rec.o, rec.y, rec.g, rec.x, rec.c == 1
  local b = self:Learned()[tostring(rec.s)]
  if b then
    if b.yellowAt then y = math.min(y, b.yellowAt); confirmed = true end
    if b.greenAt then g = math.min(g, b.greenAt) end
    if b.greyAt then x = math.min(x, b.greyAt) end
    if b.yMin and o >= b.yMin then o = b.yMin - 1 end
    if b.oMax and o > b.oMax then o = b.oMax; confirmed = true end
  end
  if y < o then y = o end
  if g < y then g = y end
  if x < g then x = g end
  return o, y, g, x, confirmed
end

-- relaxed: an estimated threshold is not allowed to block the plan
-- the same curve, from bands that were worked out once
function P:ChanceFromBands(e, skill, relaxed)
  local o, y, x = e.o, e.y, e.x
  if relaxed and not e.confirmed and skill < o then
    o = 1
    y = math.max(1, math.min(y, e.g))
  end
  if skill < o or skill >= x then return 0 end
  if skill < y then return 1 end
  local span = x - y
  if span <= 0 then return 1 end
  local c = (x - skill) / span
  return c > 0 and c or 0
end

function P:ChanceAt(rec, skill, relaxed)
  local o, y, g, x, confirmed = self:Bands(rec)
  if relaxed and not confirmed and skill < o then
    o = 1
    y = math.max(1, math.min(y, g))
  end
  if skill < o then return 0 end        -- you can't make it yet
  if skill >= x then return 0 end       -- grey: never gives a point
  if skill < y then return 1 end        -- orange: always gives a point
  local span = x - y
  if span <= 0 then return 1 end
  return math.max(0, math.min(1, (x - skill) / span))
end

---------------------------------------------------------------------------
-- What a craft costs
---------------------------------------------------------------------------
-- price for one item: your own stock is free, then vendor, then the auction house
function P:ItemCost(id, name)
  if not id or id == 0 then return nil end
  local cache = self.priceCache
  if cache then
    local hit = cache[id]
    if hit ~= nil then
      if hit == false then return nil end
      return hit, cache.how and cache.how[id]
    end
    local price, how = self:RawItemCost(id, name)
    cache[id] = price or false
    cache.how = cache.how or {}
    cache.how[id] = how
    return price, how
  end
  return self:RawItemCost(id, name)
end

function P:RawItemCost(id, name)
  if not id or id == 0 then return nil end
  if ns.IsVendorItem and ns.IsVendorItem(id, name) then
    local v = ns.VendorPrice and ns.VendorPrice(id)
    if v then return v, "vendor" end
  end
  local manual = ns.db.manualPrice and ns.db.manualPrice[id]
  if manual then return manual, "yours" end
  local market = ns.MarketValue and ns.MarketValue(id)
  if market then return market, "market" end
  local price = ns.db.prices and ns.db.prices[id]
  if price and price.low then return price.low, "seen" end
  local v = ns.VendorPrice and ns.VendorPrice(id)
  if v then return v, "vendor" end
  return nil
end

-- what one craft costs in materials, and what the result is worth
function P:CraftCost(rec)
  local cost, unknown = 0, nil
  for _, r in ipairs(rec.r) do
    local id, count = r[1], r[2]
    local price = self:ItemCost(id)
    if not price then
      unknown = unknown or id
    else
      cost = cost + price * count
    end
  end
  local back = 0
  if rec.i and rec.i > 0 then
    local value = ns.MarketValue and ns.MarketValue(rec.i)
    if value then
      back = value * 0.95 * (rec.m or 1)          -- sold on the auction house
    else
      local _, _, _, _, _, _, _, _, _, _, vendor = GetItemInfo(rec.i)
      if vendor and vendor > 0 then back = vendor * (rec.m or 1) end
    end
  end
  return cost, back, unknown
end

---------------------------------------------------------------------------
-- The item you buy to learn a recipe
---------------------------------------------------------------------------
-- Each profession names its recipes differently on the auction house.
local PREFIX = {
  Alchemy = "Recipe: ", Cooking = "Recipe: ", ["First Aid"] = "Manual: ",
  Blacksmithing = "Plans: ", Leatherworking = "Pattern: ", Tailoring = "Pattern: ",
  Engineering = "Schematic: ", Enchanting = "Formula: ", Jewelcrafting = "Design: ",
  Inscription = "Technique: ", Mining = "Plans: ",
}

-- The name to search for, and whether it is the exact item name.
-- The real item name is used when the client knows the item; otherwise the
-- profession's prefix is added, and failing that the plain name is searched for.
function P:RecipeItemName(prof, rec)
  if not rec.ri or rec.ri == 0 then return nil end
  local name = GetItemInfo(rec.ri) or (ns.db.itemNames and ns.db.itemNames[rec.ri])
  if name and name ~= "" then return name, true end
  local prefix = PREFIX[prof]
  if prefix then return prefix .. rec.n, false end
  return rec.n, false
end

---------------------------------------------------------------------------
-- Can you actually get this recipe, and these materials?
---------------------------------------------------------------------------
local function VendorSource(src)
  return src and (src:find("Vendor") or src:find("vendor")) and true or false
end

-- true, how  /  false, why not
-- sources that cannot simply be bought or trained
local OUT_OF_REACH = { "Drop", "drop", "Quest", "quest", "discovery", "Reputation",
                       "Faction", "PvP", "Arena", "Achievement", "Event", "Fishing" }

function P:RecipeAvailable(prof, rec)
  if self:Knows(prof, rec) then return true, "you know it" end
  if rec.src == "trainer" then return true, "trainer" end
  if VendorSource(rec.src) then return true, rec.src end

  -- a recipe that comes as an item can be bought if it is on the auction house
  if rec.ri and rec.ri > 0 then
    if self:ItemCost(rec.ri) then return true, "recipe on the auction house" end
    return false, "recipe not on sale"
  end

  -- otherwise only rule it out when we know it can't be bought or trained
  for _, word in ipairs(OUT_OF_REACH) do
    if rec.src and rec.src:find(word, 1, true) then
      return false, "comes from " .. rec.src
    end
  end
  return true, rec.src and rec.src ~= "unknown" and rec.src or "trainer"
end

-- a material counts as obtainable if you own some, a vendor sells it, or it has
-- a price from the auction house
-- have we scanned this realm at all? without a scan an item having no price
-- means "we haven't looked", not "you can't buy it"
function P:HaveScanData()
  if not ns.MarketKey then return false end
  local book = ns.db.market and ns.db.market[ns.MarketKey()]
  if book and next(book) then return true end
  local scan = ns.FullScan and ns.FullScan:LatestScan()
  return scan ~= nil
end

function P:MaterialAvailable(id)
  if not id or id == 0 then return false end
  if ns.StockCount then
    local have = select(1, ns.StockCount(nil, nil, id))
    if have and have > 0 then return true end
  end
  if ns.IsVendorItem and ns.IsVendorItem(id) then return true end
  if self:ItemCost(id) then return true end
  return not self:HaveScanData()       -- unknown rather than unobtainable
end

function P:Usable(prof, rec, opts)
  if opts.banned and opts.banned[rec.s] then return false, "you rejected it" end
  if opts.knownOnly and not self:Knows(prof, rec) then return false, "you don't know it" end
  local ok, why = self:RecipeAvailable(prof, rec)
  if not ok then return false, why end
  for _, r in ipairs(rec.r) do
    if not self:MaterialAvailable(r[1]) then
      local name = GetItemInfo(r[1])
      return false, (name or "a material") .. " can't be bought"
    end
  end
  return true
end

---------------------------------------------------------------------------
-- The plan
---------------------------------------------------------------------------
-- from -> to, cheapest first: at every skill point take the recipe with the
-- lowest cost per expected point
function P:Plan(prof, from, to, opts)
  opts = opts or {}
  local recipes = self:Recipes(prof)
  if not recipes then return nil, "No data for " .. tostring(prof) end
  from, to = math.max(1, floor(from or 1)), floor(to or 0)
  if to <= from then return nil, "The target is not above your current skill." end

  local gain = math.max(1, opts.gain or self:Gain())
  local steps, unknownPrices, usedEstimates = {}, {}, false
  local skill, guard = from, 0
  local current

  -- Prices and reagents don't change while we walk the skill levels, so work
  -- each recipe out once. Doing it per skill point made a full plan take a
  -- second or more in game.
  self.priceCache = {}
  local pool = {}
  for _, rec in ipairs(recipes) do
    if self:Usable(prof, rec, opts) then
      local o, y, g, x, confirmed = self:Bands(rec)
      local cost, back, unknown = self:CraftCost(rec)
      if unknown then unknownPrices[unknown] = true end
      pool[#pool + 1] = { rec = rec, o = o, y = y, g = g, x = x, confirmed = confirmed,
                          net = math.max(0, cost - (opts.sellResults == false and 0 or back)),
                          unknown = unknown and true or false }
    end
  end

  local relaxedUsed = false
  while skill < to and guard < 2000 do
    guard = guard + 1
    local relaxed = false
    local best, bestCost, bestChance, bestPartial
    local fallback, fallbackCost, fallbackChance
    for i = 1, #pool do
      local e = pool[i]
      if skill >= e.o and skill < e.x then          -- cheap numeric test first
        local chance = self:ChanceFromBands(e, skill, relaxed)
        if chance > 0 then
          local per = e.net / (chance * gain)
          if e.unknown then
            if not fallbackCost or per < fallbackCost then
              fallback, fallbackCost, fallbackChance = e.rec, per, chance
            end
          elseif not bestCost or per < bestCost then
            best, bestCost, bestChance = e.rec, per, chance
          end
        end
      end
    end
    if not best and fallback then
      best, bestCost, bestChance, bestPartial = fallback, fallbackCost, fallbackChance, true
    end
    if not best and not relaxed then
      -- nothing is usable here: an estimated threshold may be too high, so try
      -- again allowing those recipes from skill 1
      relaxed, relaxedUsed = true, true
      for i = 1, #pool do
        local e = pool[i]
        local chance = self:ChanceFromBands(e, skill, true)
        if chance > 0 then
          local per = e.net / (chance * gain)
          if not bestCost or per < bestCost then
            best, bestCost, bestChance, bestPartial = e.rec, per, chance, e.unknown or nil
          end
        end
      end
    end
    if not best then
      if current then steps[#steps + 1] = current end
      self.priceCache = nil
      return steps, nil, { stuckAt = skill, unknown = unknownPrices, estimates = usedEstimates }
    end
    local _, _, _, _, confirmed = self:Bands(best)
    if not confirmed then usedEstimates = true end

    local step = math.min(gain, to - skill)          -- the last skill-up may overshoot
    local share = step / gain                        -- so only part of a craft is needed
    if current and current.rec == best then
      current.to = skill + step
      current.crafts = current.crafts + share / bestChance
      current.cost = current.cost + bestCost * step
    else
      if current then steps[#steps + 1] = current end
      current = { rec = best, from = skill, to = skill + step, crafts = share / bestChance,
                  cost = bestCost * step, chance = bestChance, partial = bestPartial }
    end
    skill = skill + step
  end
  if current then steps[#steps + 1] = current end

  -- What to buy. Anything an earlier step produces is used by later steps
  -- instead of being bought again: smelting bars for a blacksmithing step used
  -- to put both the ore and the bars on the list.
  local materials, made, total = {}, {}, 0
  for _, step in ipairs(steps) do
    step.crafts = ceil(step.crafts)
    for _, r in ipairs(step.rec.r) do
      local id, need = r[1], r[2] * step.crafts
      local fromPlan = math.min(need, made[id] or 0)
      if fromPlan > 0 then
        made[id] = made[id] - fromPlan
        need = need - fromPlan
        step.usedOwn = (step.usedOwn or 0) + fromPlan
      end
      if need > 0 then materials[id] = (materials[id] or 0) + need end
    end
    if step.rec.i and step.rec.i > 0 then
      made[step.rec.i] = (made[step.rec.i] or 0) + (step.rec.m or 1) * step.crafts
    end
  end

  -- the real cost is what that list costs, plus any recipe you must buy
  for id, count in pairs(materials) do
    local price = self:ItemCost(id)
    if price then total = total + price * count end
  end
  for _, step in ipairs(steps) do
    local spent = 0
    for _, r in ipairs(step.rec.r) do
      local price = self:ItemCost(r[1])
      if price then spent = spent + price * r[2] * step.crafts end
    end
    step.cost = floor(spent)
    if step.rec.ri and step.rec.ri > 0 and not self:Knows(prof, step.rec) then
      local price = self:ItemCost(step.rec.ri)
      step.recipeCost = price
      if price then total = total + price end
    end
  end
  self.priceCache = nil
  return steps, nil, { total = total, materials = materials, unknown = unknownPrices,
                       estimates = usedEstimates, relaxed = relaxedUsed, gain = gain,
                       from = from, to = to }
end

-- the shopping list a plan needs, as the materials panel wants it
function P:MaterialList(info)
  local list = {}
  for id, count in pairs(info.materials or {}) do
    local name = GetItemInfo(id) or (ns.db.itemNames and ns.db.itemNames[id])
    list[#list + 1] = { id = id, name = name, need = ceil(count) }
  end
  table.sort(list, function(a, b) return (a.name or "") < (b.name or "") end)
  return list
end

---------------------------------------------------------------------------
-- Watching your own profession window to confirm the estimated thresholds
---------------------------------------------------------------------------
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("TRADE_SKILL_UPDATE")
watcher:RegisterEvent("TRADE_SKILL_SHOW")
watcher:RegisterEvent("SKILL_LINES_CHANGED")
local lastRank = {}
watcher:SetScript("OnEvent", function(_, event)
  if event == "SKILL_LINES_CHANGED" then
    for i = 1, (GetNumSkillLines and GetNumSkillLines() or 0) do
      local name, isHeader, _, rank = GetSkillLineInfo(i)
      if not isHeader and name and rank then
        local prev = lastRank[name]
        if prev and rank > prev then P:NoteSkillUp(rank - prev) end
        lastRank[name] = rank
      end
    end
    return
  end
  if IsTradeSkillLinked and IsTradeSkillLinked() then return end
  local prof, rank = GetTradeSkillLine()
  if not prof or prof == "UNKNOWN" or not rank or rank == 0 then return end
  if prof == "Smelting" then prof = "Mining" end
  for i = 1, (GetNumTradeSkills() or 0) do
    local name, difficulty, _, _, _ = GetTradeSkillInfo(i)
    if name and difficulty and difficulty ~= "header" then
      P:Observe(prof, name, difficulty, rank)
    end
  end
end)
