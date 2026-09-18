local ADDON, ns = ...
local C = ns.C
local format = string.format

local K = {}
ns.Crafting = K

local EMPTY_RECIPES = "No recipes recorded yet.\n\nOpen any profession window once - your own, an alt's, or a [profession link] someone posts in chat - and all its recipes are saved here for every character."

function K:Create(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  self.frame = f
  ns.db.craftQueue = ns.db.craftQueue or {}

  local left = CreateFrame("Frame", nil, f)
  ns.Size(left, 290, 546)
  left:SetPoint("TOPLEFT")

  -- profession + search --------------------------------------------------
  local prof = ns.Dropdown(left, 150, 24, function() K:RefreshRecipes() end)
  prof:SetPoint("TOPLEFT")
  self.prof = prof

  local crafter = ns.Dropdown(left, 134, 24, function() K:RefreshRecipes() end)
  crafter:SetPoint("LEFT", prof, "RIGHT", 6, 0)
  crafter.tooltip = "Show recipes a specific character can craft"
  self.crafter = crafter

  local search = ns.EditBox(left, 196, 24, "Search recipes...")
  search:SetPoint("TOPLEFT", 0, -30)
  search.onChange = function() K:RefreshRecipes() end
  search.acceptsLinks = "replace"
  self.search = search

  local craftable = ns.Check(left, "Can craft", function(_, on)
    ns.db.craftableOnly = on
    K:RefreshRecipes()
  end)
  craftable:SetPoint("LEFT", search, "RIGHT", 8, 0)
  craftable:SetChecked(ns.db.craftableOnly)
  craftable.tooltip = "Only recipes your stock covers at least once (bags, plus bank / alts / guild bank / mailbox as set in the Stock menu). Green number = crafts possible from your bags right now, yellow = with all your stock."
  self.craftableCheck = craftable

  -- recipe list ------------------------------------------------------------
  local rcols = {
    { text = "Recipe", w = 160, key = "name" },
    { text = "Crafter", w = 74, key = "who", font = "BHFontSmall" },
  }
  local recipes = ns.List(left, "BargainHouseRecipeList", 290, 222, 22, rcols, true)
  recipes:SetPoint("TOPLEFT", 0, -60)
  recipes.emptyText = EMPTY_RECIPES
  recipes.update = function(r, e)
    r.icon:SetTexture(e.rec.i)
    local q = e.rec.l and e.rec.l:match("|c(%x%x%x%x%x%x%x%x)")
    local suffix = ""
    if (e.now or 0) > 0 then suffix = "  |cff66dd88x" .. e.now .. "|r"
    elseif (e.total or 0) > 0 then suffix = "  |cffe6cc80x" .. e.total .. "|r" end
    r.cols[1]:SetText((q and ("|c" .. q) or "|cffffffff") .. e.name .. "|r" .. suffix)
    local mine, others = ns.Recipes:Crafters(e.rec)
    if #mine > 0 then
      r.cols[2]:SetText("|cff66dd88" .. mine[1] .. "|r" .. (#mine > 1 and ("|cff888888 +" .. (#mine - 1) .. "|r") or ""))
    elseif e.maybe then
      r.cols[2]:SetText("|cffe6cc80" .. e.maybe[1].name .. "?|r" .. (#e.maybe > 1 and ("|cff888888 +" .. (#e.maybe - 1) .. "|r") or ""))
    elseif #others > 0 then
      r.cols[2]:SetText("|cff888888link|r")
    else
      r.cols[2]:SetText("|cff555555?|r")
    end
  end
  recipes.onClick = function(e, button)
    if IsModifiedClick() and e.rec.l then
      HandleModifiedItemClick(e.rec.l)
      return
    end
    K.selected = e
    recipes.selected = e
    recipes:Refresh()
    K:UpdateAddButton()
    if button == "RightButton" then K:AddToQueue() end
  end
  recipes.onEnter = function(e, r)
    K:RecipeTooltip(r, e.prof, e.name, e.rec, 1)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(ns.ACCENT .. "Click|r select   " .. ns.ACCENT .. "Right-click|r add to queue   then |cffffd100Profit?|r to check it", 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end
  self.recipeList = recipes

  -- add row ----------------------------------------------------------------
  local craftsLabel = ns.Text(left, "BHFontSmall", "Crafts")
  craftsLabel:SetPoint("TOPLEFT", 0, -294)
  local qty = ns.EditBox(left, 50, 24, nil, true)
  qty:SetPoint("TOPLEFT", 40, -288)
  qty:SetMaxLetters(4)
  qty:SetTextSilent(1)
  qty.onChange = function() K:UpdateAddButton() end
  qty.onEnter = function() K:AddToQueue() end
  self.qty = qty

  local add = ns.Button(left, "Add to queue", 124, 24, "accent")
  add:SetPoint("TOPLEFT", 96, -288)
  add:SetScript("OnClick", function() K:AddToQueue() end)
  self.addBtn = add

  local profit = ns.Button(left, "Profit?", 66, 24, "gold")
  profit:SetPoint("LEFT", add, "RIGHT", 4, 0)
  profit.tooltip = "Would crafting the selected recipe make or lose gold if you bought all the materials on the auction house and sold the result?"
  profit:SetScript("OnClick", function()
    if K.selected then ns.ProfitCheck:Open(K.selected, tonumber(K.qty:GetText()) or 1) end
  end)
  self.profitBtn = profit

  -- craft queue ------------------------------------------------------------
  local qcols = {
    { text = "Crafts", w = 40, key = "q", j = "RIGHT" },
    { text = "Craft queue", w = 194, key = "n" },
  }
  local queue = ns.List(left, "BargainHouseCraftQueue", 290, 178, 22, qcols, true)
  queue:SetPoint("TOPLEFT", 0, -320)
  queue.emptyText = "Add recipes to build your craft queue."
  queue.update = function(r, e)
    local rec = ns.Recipes:Get(e.p, e.n)
    r.icon:SetTexture(rec and rec.i)
    r.cols[1]:SetText(ns.ACCENT .. e.q .. "|r")
    local made = rec and rec.m or 1
    r.cols[2]:SetText(e.n .. (made > 1 and format("  |cff888888(makes %d)|r", e.q * made) or ""))
  end
  queue.onClick = function(e, button)
    if K.panel.queue or K.panel.scanning then return end
    if button == "RightButton" or IsShiftKeyDown() then
      e.q = 0
    else
      e.q = e.q - 1
    end
    K:CleanQueue()
  end
  queue.onEnter = function(e, r)
    local rec = ns.Recipes:Get(e.p, e.n)
    if rec then K:RecipeTooltip(r, e.p, e.n, rec, e.q) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(ns.ACCENT .. "Click|r remove one craft   " .. ns.ACCENT .. "Right-click|r remove", 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end
  self.queueList = queue

  local clear = ns.Button(left, "Clear", 90, 30)
  clear:SetPoint("TOPLEFT", 0, -506)
  clear:SetScript("OnClick", function()
    if K.panel.queue or K.panel.scanning then return end
    wipe(ns.db.craftQueue)
    K:CleanQueue()
    K.panel:Clear()
  end)

  local find = ns.Button(left, "Find materials", 194, 30, "accent")
  find:SetPoint("TOPLEFT", 96, -506)
  find:SetScript("OnClick", function()
    if K.panel.scanning then K.panel:StopScan() else K:FindMaterials() end
  end)
  self.findBtn = find

  -- materials panel ----------------------------------------------------------
  self.panel = ns.MaterialsPanel(f, "Craft", {
    emptyText = "Pick what you want to craft on the left and press 'Find materials'.\n\nWhat you already carry is subtracted, the rest is priced at the lowest total cost\nand bought after one confirmation.",
    confirmText = function() return K:QueueSummary() end,
    onScanState = function(on)
      find:SetText(on and "Stop" or (ns.atAH and "Find materials" or "Check materials"))
      find:SetStyle(on and "danger" or "accent")
    end,
  })

  ns.ProfitCheck:Create(f)

  f:SetScript("OnShow", function() K:OnRecipesChanged() end)
  self:OnRecipesChanged()
  return f
end

function K:RecipeTooltip(owner, prof, name, rec, crafts)
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  if rec.l then GameTooltip:SetHyperlink(rec.l) else GameTooltip:SetText(name, 1, 1, 1) end
  GameTooltip:AddLine(" ")
  local mine, others = ns.Recipes:Crafters(rec)
  GameTooltip:AddLine(" ")
  if #mine > 0 then
    GameTooltip:AddLine("|cff66dd88Crafted by:|r " .. table.concat(mine, ", "), 1, 1, 1, true)
  else
    local holders = ns.Chars and ns.Chars:WithProfession(prof) or {}
    if holders[1] then
      local parts = {}
      for _, h in ipairs(holders) do parts[#parts + 1] = format("%s (%d)", h.name, h.rank) end
      GameTooltip:AddLine("|cffe6cc80Probably:|r " .. table.concat(parts, ", "), 1, 1, 1, true)
      GameTooltip:AddLine("They have " .. prof .. " but this recipe isn't confirmed. Open that character's profession window once.", 0.7, 0.7, 0.7, true)
    else
      GameTooltip:AddLine("|cff888888None of your characters is known to craft this.|r", 1, 1, 1, true)
    end
  end
  if #others > 0 then
    GameTooltip:AddLine("|cff888888Seen in profession links from:|r " .. table.concat(others, ", "), 0.8, 0.8, 0.8, true)
  end
  local head = crafts > 1 and format("Reagents for %d crafts", crafts) or "Reagents"
  GameTooltip:AddLine(ns.ACCENT .. head .. "|r  |cff888888" .. prof .. "|r")
  local now, total = K:Craftable(rec)
  GameTooltip:AddLine(format("|cff66dd88Can craft %d from bags|r   |cffe6cc80%d with all stock|r", now, total))
  for _, rg in ipairs(rec.r) do
    local link = rg.id and select(2, GetItemInfo(rg.id))
    local bags, mail, _, bank, alts, guild = ns.StockCount(link, rg.n, rg.id)
    local have = bags + mail + bank + alts + guild
    local need = rg.c * crafts
    local color = have >= need and "|cff66dd88" or "|cffffd100"
    local p = rg.id and ns.db.prices[rg.id]
    GameTooltip:AddDoubleLine(format("%dx %s  %s(have %d)|r", need, rg.n, color, have),
      p and ns.Money(p.l * need) or "", 1, 1, 1, 1, 1, 1)
  end
end

function K:OnRecipesChanged()
  if not self.prof then return end
  local items = { { value = "", text = "All professions" } }
  for _, p in ipairs(ns.Recipes:Professions()) do
    items[#items + 1] = { value = p.name, text = format("%s  |cff888888(%d)|r", p.name, p.count) }
  end
  self.prof:SetItems(items)
  self.prof:SetValue(self.prof.value or "", true)
  local citems = { { value = "", text = "Any crafter" }, { value = "*own", text = "My characters" } }
  for _, who in ipairs(ns.Recipes:AllCrafters()) do citems[#citems + 1] = { value = who, text = who } end
  self.crafter:SetItems(citems)
  local cur = self.crafter.value or ""
  local found = false
  for _, it in ipairs(citems) do if it.value == cur then found = true end end
  self.crafter:SetValue(found and cur or "", true)
  self:RefreshRecipes()
  self:CleanQueue()
end

function K:RefreshRecipes()
  local p = self.prof.value
  local c = self.crafter.value or ""
  local data = ns.Recipes:List(p ~= "" and p or nil, strtrim(self.search:GetText() or ""), (c ~= "" and c ~= "*own") and nil or (c ~= "" and c or nil))
  local cache, profHolders = {}, {}
  local function Holders(prof)
    if not profHolders[prof] then profHolders[prof] = ns.Chars and ns.Chars:WithProfession(prof) or {} end
    return profHolders[prof]
  end
  local filtered = {}
  for _, e in ipairs(data) do
    local mine = ns.Recipes:Crafters(e.rec, true)
    e.maybe = nil
    if #mine == 0 then
      -- nobody confirmed: characters with that profession probably can
      local holders = Holders(e.prof)
      if holders[1] then e.maybe = holders end
    end
    e.who = mine[1] or (e.maybe and e.maybe[1].name) or "~"
    e.now, e.total = self:Craftable(e.rec, cache)
    local okCrafter = true
    if c ~= "" and c ~= "*own" and #mine == 0 and e.maybe then
      okCrafter = false
      for _, h in ipairs(e.maybe) do if h.name == c then okCrafter = true end end
    end
    if okCrafter and (not ns.db.craftableOnly or e.total > 0) then filtered[#filtered + 1] = e end
  end
  data = filtered
  if self.selected then
    local found
    for _, e in ipairs(data) do
      if e.name == self.selected.name and e.prof == self.selected.prof then found = e break end
    end
    self.selected = found
  end
  self.recipeList.selected = self.selected
  self.recipeList:SetData(data)
  self:UpdateAddButton()
end

-- How many crafts your stock allows: from bags now, and with every enabled stock source
function K:Craftable(rec, cache)
  local now, total = math.huge, math.huge
  for _, rg in ipairs(rec.r or {}) do
    local key = rg.id or rg.n
    local c = cache and cache[key]
    if not c then
      local link = rg.id and select(2, GetItemInfo(rg.id))
      local bags, mail, _, bank, alts, guild = ns.StockCount(link, rg.n, rg.id)
      c = { bags, bags + mail + bank + alts + guild }
      if cache then cache[key] = c end
    end
    local need = math.max(1, rg.c or 1)
    now = math.min(now, math.floor(c[1] / need))
    total = math.min(total, math.floor(c[2] / need))
  end
  if now == math.huge then now, total = 0, 0 end
  return now, total
end

function K:UpdateMode()
  if not self.findBtn then return end
  if not self.panel.scanning then
    self.findBtn:SetText(ns.atAH and "Find materials" or "Check materials")
  end
  self:UpdateAddButton()
  if not ns.atAH and ns.ProfitCheck.frame and ns.ProfitCheck.frame:IsShown() then ns.ProfitCheck:Close() end
  self:RefreshRecipes()
end

function K:UpdateAddButton()
  local n = tonumber(self.qty:GetText()) or 0
  ns.Enable(self.addBtn, self.selected ~= nil and n > 0)
  if self.profitBtn then ns.Enable(self.profitBtn, self.selected ~= nil and n > 0 and ns.atAH) end
end

function K:AddToQueue()
  local e = self.selected
  local n = tonumber(self.qty:GetText()) or 0
  if not e or n <= 0 or self.panel.queue or self.panel.scanning then return end
  for _, q in ipairs(ns.db.craftQueue) do
    if q.p == e.prof and q.n == e.name then
      q.q = q.q + n
      self:CleanQueue()
      return
    end
  end
  table.insert(ns.db.craftQueue, { p = e.prof, n = e.name, q = n })
  self:CleanQueue()
end

function K:CleanQueue()
  local q = ns.db.craftQueue
  for i = #q, 1, -1 do
    if q[i].q <= 0 or not ns.Recipes:Get(q[i].p, q[i].n) then table.remove(q, i) end
  end
  self.queueList:SetData(q, true)
  ns.Enable(self.findBtn, #q > 0 or self.panel.scanning)
end

function K:QueueSummary()
  local q = ns.db.craftQueue
  if #q == 1 then return format("%d x %s", q[1].q, q[1].n) end
  return format("%d recipes in your craft queue", #q)
end

-- Adds up the reagents of every queued craft
function K:Materials()
  local list, byKey = {}, {}
  for _, entry in ipairs(ns.db.craftQueue) do
    local rec = ns.Recipes:Get(entry.p, entry.n)
    if rec then
      for _, rg in ipairs(rec.r) do
        local key = rg.id or strlower(rg.n)
        local m = byKey[key]
        if not m then
          local link
          if rg.id then
            local _, l, quality, _, _, _, _, _, _, texture = GetItemInfo(rg.id)
            link = l
            m = { name = rg.n, need = 0, link = link, quality = quality, texture = texture }
          else
            m = { name = rg.n, need = 0 }
          end
          m.users = {}
          byKey[key] = m
          list[#list + 1] = m
        end
        m.need = m.need + rg.c * entry.q
        m.users[#m.users + 1] = entry.n
      end
    end
  end
  for _, m in ipairs(list) do
    m.usedBy = table.concat(m.users, ", ")
    m.users = nil
  end
  return list
end

function K:FindMaterials()
  if #ns.db.craftQueue == 0 then return end
  if ns.ProfitCheck.frame and ns.ProfitCheck.frame:IsShown() then ns.ProfitCheck:Close() end
  self.panel:Check(self:Materials())
end
