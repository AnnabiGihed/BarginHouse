local ADDON, ns = ...
local format = string.format

-- Records recipes from any profession window the player opens: their own,
-- an alt's, or someone else's profession link from chat. Data comes straight
-- from the client, so reagent counts are always exact.
-- ns.db.recipes[profession][recipeName] = { i = icon, l = itemLink, h = header, m = made, r = { {n=, c=, id=}, ... } }

---------------------------------------------------------------------------
-- Recipe encoding for sync (definitions only; who knows them is sent apart)
---------------------------------------------------------------------------
local function Clean(v) return (tostring(v or ""):gsub("[~%^`}|]", " ")) end

function ns.EncodeRecipe(name, rec)
  local reagents = {}
  for _, rg in ipairs(rec.r or {}) do
    reagents[#reagents + 1] = table.concat({ rg.id or "", rg.c or 1, Clean(rg.n) }, "`")
  end
  local icon = tostring(rec.i or ""):gsub("^[Ii]nterface\\[Ii]cons\\", "")
  local link = ""
  if rec.l then
    local color, kind, id, iname = rec.l:match("|c(%x+)|H(%a+):(%d+).-|h%[(.-)%]|h")
    if kind then link = table.concat({ color, kind, id, Clean(iname) }, "`") end
  end
  return table.concat({ Clean(name), Clean(icon), link, Clean(rec.h), rec.m or 1, table.concat(reagents, "^") }, "~")
end

function ns.DecodeRecipe(s)
  local name, icon, link, header, made, reagents = s:match("^(.-)~(.-)~(.-)~(.-)~(%d+)~(.*)$")
  if not name or name == "" then return nil end
  local r = reagents:match("^(.-)~")           -- older versions appended crafters here
  if r then reagents = r end
  local itemLink
  local color, kind, id, iname = link:match("^(%x+)`(%a+)`(%d+)`(.*)$")
  if kind then
    itemLink = string.format("|c%s|H%s:%s%s|h[%s]|h|r", color, kind, id, kind == "item" and ":0:0:0:0:0:0:0" or "", iname)
  end
  local rec = { i = icon ~= "" and ("Interface\\Icons\\" .. icon) or nil, l = itemLink,
                h = header ~= "" and header or nil, m = tonumber(made) or 1, r = {}, k = {} }
  for part in reagents:gmatch("[^%^]+") do
    local rid, count, rname = part:match("^(%d*)`(%d+)`(.+)$")
    if rname then rec.r[#rec.r + 1] = { id = tonumber(rid), c = tonumber(count), n = rname } end
  end
  if #rec.r == 0 then return nil end
  return name, rec
end

local R = CreateFrame("Frame")
ns.Recipes = R
R:Hide()
R:RegisterEvent("TRADE_SKILL_SHOW")
R:RegisterEvent("TRADE_SKILL_UPDATE")

R:SetScript("OnEvent", function(self, event)
  if event == "TRADE_SKILL_SHOW" then self.expandOnce = true end
  self.delay = 0.4
  self.retries = 0
  self:Show()
end)

R:SetScript("OnUpdate", function(self, elapsed)
  self.delay = self.delay - elapsed
  if self.delay > 0 then return end
  self:Hide()
  self:Capture()
end)

function R:Capture()
  if not ns.db then return end
  local prof = GetTradeSkillLine()
  if not prof or prof == "" or prof == "UNKNOWN" then return end
  if prof == "Smelting" then prof = "Mining" end -- the mining window is called Smelting
  local n = GetNumTradeSkills() or 0
  if n == 0 then return end

  -- make sure collapsed categories are included (once per window open)
  if self.expandOnce then
    self.expandOnce = false
    for i = 1, n do
      local _, kind, _, expanded = GetTradeSkillInfo(i)
      if kind == "header" and not expanded then
        ExpandTradeSkillSubClass(0) -- expands everything, fires TRADE_SKILL_UPDATE
        return
      end
    end
  end

  ns.db.recipes = ns.db.recipes or {}
  local book = ns.db.recipes[prof] or {}
  ns.db.recipes[prof] = book

  -- who knows these recipes: this character, or the owner of a profession link
  local linked, linkOwner = false, nil
  if IsTradeSkillLinked then linked, linkOwner = IsTradeSkillLinked() end
  local who = linked and linkOwner or UnitName("player")
  local knowKind = linked and "link" or "own"

  local header, added, incomplete, changed = nil, 0, false, false
  for i = 1, n do
    local name, kind = GetTradeSkillInfo(i)
    if kind == "header" then
      header = name
    elseif name then
      local reagents, ok = {}, true
      for r = 1, (GetTradeSkillNumReagents(i) or 0) do
        local rname, _, rcount = GetTradeSkillReagentInfo(i, r)
        if not rname or not rcount then
          ok = false
          break
        end
        reagents[#reagents + 1] = { n = rname, c = rcount, id = ns.ItemID(GetTradeSkillReagentItemLink(i, r)) }
      end
      if ok and #reagents > 0 then
        local old = book[name]
        if not old then added = added + 1; changed = true end
        local knowers = old and old.k or {}
        if who and knowers[who] ~= "own" and knowers[who] ~= knowKind then
          knowers[who] = knowKind
          changed = true
        end
        book[name] = {
          i = GetTradeSkillIcon(i),
          l = GetTradeSkillItemLink(i),
          h = header,
          m = GetTradeSkillNumMade(i) or 1,
          r = reagents,
          k = knowers,
        }
      elseif not ok then
        incomplete = true
      end
    end
  end

  -- reagent names not cached yet: try again shortly
  if incomplete and self.retries < 5 then
    self.retries = self.retries + 1
    self.delay = 1.5
    self:Show()
  end

  if added > 0 then
    if ns.Sync then ns.Sync:RecipesChanged() end
    local linked, who = false, nil
    if IsTradeSkillLinked then linked, who = IsTradeSkillLinked() end
    ns.Print(format("Saved %d new %s recipes%s.", added, prof, (linked and who) and (" from " .. who) or ""))
  end
  -- mass crafting fires this a lot: only refresh when something changed and it's visible
  if changed and ns.Crafting and ns.Crafting.OnRecipesChanged and ns.Crafting.frame and ns.Crafting.frame:IsVisible() then
    ns.Crafting:OnRecipesChanged()
  end
  -- this character's list for this profession is now up to date (used by sync)
  if not linked and who and ns.Sync and ns.Sync.SetKnowTime then
    ns.Sync:SetKnowTime(strlower(who), prof, time())
  end
  if changed and added == 0 and ns.Sync and ns.Sync.RecipesChanged then ns.Sync:RecipesChanged() end
end

-- Flattened, filtered recipe list for the UI
-- Enchanting sells as scrolls: the auction house item is "Scroll of <recipe>",
-- written on a vellum that the profession window never lists as a reagent.
function ns.ScrollName(prof, recipeName)
  if prof ~= "Enchanting" or not recipeName then return nil end
  if recipeName:find("^Scroll of ") then return recipeName end
  if not recipeName:find("^Enchant") then return nil end -- rods, oils and such are items already
  return "Scroll of " .. recipeName
end

function ns.VellumFor(recipeName)
  if recipeName and (recipeName:find("Weapon") or recipeName:find("Staff")) then return "Weapon Vellum III" end
  return "Armor Vellum III"
end

-- crafter: nil = anyone, "*own" = any of my characters, or a character name
function R:List(profFilter, search, crafter)
  local out = {}
  local s = search and strlower(search) or ""
  for prof, book in pairs(ns.db.recipes or {}) do
    if not profFilter or profFilter == prof then
      for name, rec in pairs(book) do
        local okCrafter = true
        if crafter == "*own" then
          okCrafter = #self:Crafters(rec, true) > 0
        elseif crafter then
          okCrafter = rec.k and rec.k[crafter] ~= nil
        end
        if okCrafter and (s == "" or strlower(name):find(s, 1, true)) then
          out[#out + 1] = { prof = prof, name = name, rec = rec }
        end
      end
    end
  end
  table.sort(out, function(a, b)
    if a.name == b.name then return a.prof < b.prof end
    return a.name < b.name
  end)
  return out
end

-- Is this one of my characters? (recorded on this account, or a sync partner)
function R:IsMine(name)
  if not name then return false end
  if strlower(name) == strlower(UnitName("player") or "") then return true end
  local realm = ns.db.inventory and ns.db.inventory[GetRealmName() or "?"]
  if realm and realm[name] then return true end
  local remote = ns.db.remoteChars and ns.db.remoteChars[GetRealmName() or "?"]
  if remote and remote[name] then return true end
  for p in (ns.db.syncPartners or ""):gmatch("[^,%s]+") do
    if strlower(p) == strlower(name) then return true end
  end
  return false
end

-- Sorted crafter names of a recipe; mineOnly = only my characters
function R:Crafters(rec, mineOnly)
  local mine, others = {}, {}
  for who, kind in pairs(rec and rec.k or {}) do
    if kind == "own" or self:IsMine(who) then mine[#mine + 1] = who
    elseif not mineOnly then others[#others + 1] = who end
  end
  table.sort(mine)
  table.sort(others)
  if mineOnly then return mine end
  return mine, others
end

-- Every character that knows at least one recorded recipe
function R:AllCrafters()
  local set = {}
  for _, book in pairs(ns.db.recipes or {}) do
    for _, rec in pairs(book) do
      for who, kind in pairs(rec.k or {}) do
        if kind == "own" or self:IsMine(who) then set[who] = true end
      end
    end
  end
  local out = {}
  for who in pairs(set) do out[#out + 1] = who end
  table.sort(out)
  return out
end

function R:Get(prof, name)
  local book = ns.db.recipes and ns.db.recipes[prof]
  return book and book[name]
end

function R:Professions()
  local out = {}
  for prof, book in pairs(ns.db.recipes or {}) do
    local c = 0
    for _ in pairs(book) do c = c + 1 end
    out[#out + 1] = { name = prof, count = c }
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end
