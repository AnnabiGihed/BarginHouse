local ADDON, ns = ...
local C = ns.C
local format, floor = string.format, math.floor

local T = {}
ns.LevelingTab = T

local function SkillOf(prof)
  for i = 1, GetNumSkillLines() do
    local name, isHeader, _, rank = GetSkillLineInfo(i)
    if not isHeader and name then
      local n = (name == "Smelting") and "Mining" or name
      if n == prof then return rank end
    end
  end
end

function T:Create(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  self.frame = f

  local title = ns.Text(f, "BHFontLarge", "Level up a profession")
  title:SetPoint("TOPLEFT", 4, -6)
  local hint = ns.Text(f, "BHFontSmall", "Pick a profession and the skill to reach. The cheapest route is worked out from what materials cost right now.")
  hint:SetPoint("TOPLEFT", 4, -26)
  hint:SetWidth(292)
  hint:SetJustifyH("LEFT")
  hint:SetHeight(28)

  local prof = ns.Dropdown(f, 140, 26, function() T:OnProfession() end)
  prof:SetPoint("TOPLEFT", 0, -60)
  local items = {}
  for _, p in ipairs(ns.Leveling:Professions()) do items[#items + 1] = { value = p, text = p } end
  prof:SetItems(items)
  self.prof = prof

  local fromL = ns.Text(f, "BHFontSmall", "From")
  fromL:SetPoint("LEFT", prof, "RIGHT", 8, 0)
  local from = ns.Text(f, "BHFontNormal", "1", "CENTER")
  from:SetPoint("LEFT", fromL, "RIGHT", 6, 0)
  ns.Size(from, 40, 26)
  self.from = from
  function from:GetText() return self.__value or "1" end
  function from:SetTextSilent(v) self.__value = tostring(v or 1); self:SetText(self.__value) end

  local toL = ns.Text(f, "BHFontSmall", "to")
  toL:SetPoint("LEFT", from, "RIGHT", 6, 0)
  local to = ns.EditBox(f, 44, 26, "")
  to:SetPoint("LEFT", toL, "RIGHT", 6, 0)
  to:SetNumeric(true)
  to.onEnter = function() T:BuildPlan() end
  self.to = to

  local plan = ns.Button(f, "Work out the plan", 140, 26, "accent")
  plan:SetPoint("TOPLEFT", 0, -122)
  plan:SetScript("OnClick", function() T:BuildPlan(true) end)
  self.planBtn = plan

  local known = ns.Check(f, "Only recipes I know", function() T:BuildPlan() end)
  known:SetPoint("TOPLEFT", 0, -150)
  self.known = known

  local gainL = ns.Text(f, "BHFontSmall", "Points per skill-up")
  gainL:SetPoint("TOPLEFT", 0, -94)
  local gain = ns.Dropdown(f, 96, 22, function(v)
    ns.db.skillGain = v
    T:BuildPlan()
  end)
  gain:SetPoint("LEFT", gainL, "RIGHT", 6, 0)
  gain.tooltip = "How much skill one successful craft gives. Retail rules give 1; Warmane's Icecrown gives 3. On auto this is taken from your own skill-ups."
  self.gain = gain

  local sell = ns.Check(f, "I will sell what I craft", function() T:BuildPlan() end)
  sell:SetPoint("TOPLEFT", 0, -174)
  sell:SetChecked(true)
  sell.tooltip = "Counts what each craft is worth on the auction house against its cost. Untick if you plan to vendor or keep them."
  self.sell = sell

  local cols = {
    { text = "Skill", w = 42, font = "BHFontSmall" },
    { text = "Make", w = 96, font = "BHFontSmall" },
    { text = "Crafts", w = 28, j = "RIGHT", font = "BHFontSmall" },
    { text = "Cost", w = 50, j = "RIGHT", font = "BHFontSmall" },
  }
  local list = ns.List(f, "BargainHouseLevelPlan", 292, 184, 22, cols, true)
  list:SetPoint("TOPLEFT", 0, -202)
  list.emptyText = "Pick a profession and a target skill, then press 'Work out the plan'."
  list.update = function(r, step)
    local rec = step.rec
    r.icon:SetTexture(GetItemIcon and rec.i > 0 and GetItemIcon(rec.i) or "Interface\\Icons\\INV_Misc_QuestionMark")
    r.cols[1]:SetText(format("%d-%d", step.from, step.to))
    local _, _, _, _, confirmed = ns.Leveling:Bands(rec)
    r.cols[2]:SetText((confirmed and "|cffdddddd" or "|cffe6cc80") .. rec.n .. "|r")
    r.cols[3]:SetText(step.crafts)
    r.cols[4]:SetText(ns.MoneyShort(step.cost))
    r.cols[4]:SetText(step.cost > 0 and ns.MoneyShort(step.cost) or "|cff555555--|r")
  end
  list.onEnter = function(step, row) T:StepTooltip(step, row) end
  list.onClick = function(step, button)
    if button == "RightButton" and step.rec.i and step.rec.i > 0 and ns.Browse then
      ns.main:SelectTab(1)
      ns.Browse:SearchFor(step.rec.n)
      return
    end
    T.selected = step
    list.selected = step
    list:Refresh()
    ns.Enable(T.rejectBtn, true)
    T:UpdateStepButtons()
  end
  self.list = list

  local summary = ns.Text(f, "BHFontLarge", "")
  summary:SetPoint("TOPLEFT", 0, -446)
  ns.Size(summary, 292, 20)
  self.summary = summary

  local sub = ns.Text(f, "BHFontSmall", "")
  sub:SetPoint("TOPLEFT", 0, -468)
  ns.Size(sub, 292, 14)
  sub:SetJustifyH("LEFT")
  self.subSummary = sub

  local note = ns.Text(f, "BHFontSmall", "")
  note:SetPoint("TOPLEFT", 0, -484)
  ns.Size(note, 292, 28)
  note:SetJustifyH("LEFT")
  note:SetJustifyV("TOP")
  self.note = note

  local findRecipe = ns.Button(f, "Find recipe on AH", 140, 22)
  findRecipe:SetPoint("TOPLEFT", 0, -392)
  findRecipe.tooltip = "Search the auction house for the recipe this step needs"
  findRecipe:SetScript("OnClick", function() T:FindRecipe() end)
  self.findRecipeBtn = findRecipe

  local reject = ns.Button(f, "Reject step", 96, 22, "danger")
  reject:SetPoint("LEFT", findRecipe, "RIGHT", 6, 0)
  reject.tooltip = "Leave this recipe out of the plan (you can't get it, or don't want it) and work out another way"
  reject:SetScript("OnClick", function()
    local step = T.selected
    if not step then return end
    T.banned = T.banned or {}
    T.banned[step.rec.s] = step.rec.n
    T.selected = nil
    T:BuildPlan(true)
  end)
  self.rejectBtn = reject

  local clear = ns.Button(f, "Clear rejections", 120, 22)
  clear:SetPoint("TOPLEFT", 0, -418)
  clear:SetScript("OnClick", function()
    T.banned = {}
    T:BuildPlan(true)
  end)
  self.clearBtn = clear

  local find = ns.Button(f, "Find materials", 130, 26, "accent")
  find:SetPoint("BOTTOMLEFT", 0, 4)
  find:SetScript("OnClick", function()
    if T.panel.scanning then T.panel:StopAll("Stopped.") return end
    if not T.info or not T.info.materials then return end
    T.panel:Check(ns.Leveling:MaterialList(T.info))
  end)
  self.findBtn = find

  self.panel = ns.MaterialsPanel(f, "Level", {
    emptyText = "Work out a plan, then press 'Find materials'.\n\nWhat you already have is subtracted; the rest is priced\nat the lowest total cost and bought after one confirmation.",
    confirmText = function() return T:QueueSummary() end,
    onScanState = function(on)
      find:SetText(on and "Stop" or (ns.atAH and "Find materials" or "Check materials"))
      find:SetStyle(on and "danger" or "accent")
    end,
    onFinished = function(aborted)
      -- the check just read real prices off the auction house, so the plan can
      -- be worked out again with them
      if aborted then return end
      T:RePlanWithLivePrices()
    end,
  })

  f:SetScript("OnShow", function() T:OnShow() end)
  return f
end

function T:RefreshGain()
  local detected, samples = ns.Leveling:GainDetected()
  local items = { { value = 0, text = detected and format("Auto (%d seen)", detected) or "Auto" } }
  for _, v in ipairs({ 1, 2, 3, 5, 10 }) do
    items[#items + 1] = { value = v, text = v .. (v == 1 and " point" or " points") }
  end
  self.gain:SetItems(items)
  self.gain:SetValue(ns.db.skillGain or 0, true)
  self.gainSamples = samples
end

function T:OnShow()
  self:RefreshGain()
  if not self.prof.value then
    -- start with a profession this character actually has
    for _, p in ipairs(ns.Leveling:Professions()) do
      if SkillOf(p) then self.prof:SetValue(p, true) break end
    end
    if not self.prof.value then self.prof:SetValue(ns.Leveling:Professions()[1], true) end
    self:OnProfession()
  end
end

function T:OnProfession()
  local prof = self.prof.value
  local rank = prof and SkillOf(prof)
  self.from:SetTextSilent(rank or 1)
  self.to:SetTextSilent(tostring(ns.Leveling:MaxSkill(prof)))
  self.banned = {}
  self.list:SetData({}, true)
  self.summary:SetText("")
  self.subSummary:SetText("")
  self.note:SetText("")
  self.info = nil
end

function T:BuildPlan(fromButton)
  local ok, err = pcall(self.DoBuildPlan, self, fromButton)
  if not ok then
    self.summary:SetText("|cffff5555Something went wrong working out the plan.|r")
    ns.Print("|cffff5555Level up:|r " .. tostring(err))
  end
end

function T:DoBuildPlan(fromButton)
  local prof = self.prof.value
  if not prof then
    self.summary:SetText("|cffffaa33Pick a profession first.|r")
    return
  end
  local from = tonumber(self.from:GetText()) or 1
  local to = tonumber(self.to:GetText()) or 0
  local steps, err, info = ns.Leveling:Plan(prof, from, to, {
    knownOnly = self.known:GetChecked() and true or false,
    sellResults = self.sell:GetChecked() and true or false,
    banned = self.banned,
  })
  if err then
    self.summary:SetText("|cffff5555" .. err .. "|r")
    self.subSummary:SetText("")
    self.list:SetData({}, true)
    return
  end
  self.steps, self.info = steps, info
  self.list:SetData(steps, true)
  if fromButton and self.planBtn then
    self.planBtn:SetText("Plan updated")
    self.planToken = (self.planToken or 0) + 1
    local token = self.planToken
    ns.After(1.5, function()
      if T.planToken == token and T.planBtn then T.planBtn:SetText("Work out the plan") end
    end)
  end

  if info.stuckAt then
    local rejected = 0
    for _ in pairs(self.banned or {}) do rejected = rejected + 1 end
    self.summary:SetText(format("|cffffaa33Stuck at skill %d.|r", info.stuckAt))
    self.subSummary:SetText(rejected > 0
      and "|cffe6cc80No alternative left - clear some rejections.|r"
      or "|cff888888Nothing you can buy the materials for. Scan the auction house.|r")
  else
    local crafts = 0
    for _, st in ipairs(steps) do crafts = crafts + st.crafts end
    self.summary:SetText(format("%s%d to %d: %s|r", ns.ACCENT, info.from, info.to,
      ns.Money(info.total or 0, true)))
    self.subSummary:SetText(format("|cff888888in materials, %d crafts, %d point%s per skill-up|r",
      crafts, info.gain, info.gain == 1 and "" or "s"))
  end

  local notes = {}
  if (ns.db.skillGain or 0) == 0 and (self.gainSamples or 0) == 0 then
    notes[#notes + 1] = "|cffe6cc80Assuming 1 skill point per craft: set 3 if you play on Icecrown, or leave it on auto and it will learn from your first skill-ups.|r"
  end
  if info.estimates then
    notes[#notes + 1] = "|cffe6cc80Yellow rows: estimated threshold, corrected once you open that profession window.|r"
  end
  local unknown = 0
  for _ in pairs(info.unknown or {}) do unknown = unknown + 1 end
  if unknown > 0 then
    notes[#notes + 1] = format("%d material%s unpriced: run a full scan in Deals.", unknown, unknown == 1 and "" or "s")
  end
  local buy = 0
  for _, s in ipairs(steps) do if s.recipeCost then buy = buy + 1 end end
  if buy > 0 then notes[#notes + 1] = format("%d recipe%s to buy or find.", buy, buy == 1 and "" or "s") end
  local rejected = 0
  for _ in pairs(self.banned or {}) do rejected = rejected + 1 end
  if rejected > 0 then
    table.insert(notes, 1, format("|cff888888%d recipe%s rejected.|r", rejected, rejected == 1 and "" or "s"))
  end
  ns.Enable(self.clearBtn, rejected > 0)
  ns.Enable(self.rejectBtn, self.selected ~= nil)
  self:UpdateStepButtons()
  while #notes > 2 do table.remove(notes) end   -- the box holds two lines of advice
  self.note:SetText(table.concat(notes, " "))
end

-- look up the selected step's recipe on the auction house
function T:FindRecipe()
  local step = self.selected
  if not step then
    self.note:SetText("|cffffaa33Pick a step first.|r")
    return
  end
  local prof, rec = self.prof.value, step.rec
  if ns.Leveling:Knows(prof, rec) then
    self.note:SetText(format("|cff888888You already know %s.|r", rec.n))
    return
  end
  local name, exact = ns.Leveling:RecipeItemName(prof, rec)
  if not name then
    self.note:SetText(format("|cff888888%s is taught by a trainer, not sold as a recipe.|r", rec.n))
    return
  end
  ns.Browse:SearchFor(name, exact and "EXACT" or "CONTAINS")
end

function T:StepTooltip(step, row)
  local rec = step.rec
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:SetText(rec.n, 1, 1, 1)
  local o, y, g, x, confirmed = ns.Leveling:Bands(rec)
  GameTooltip:AddDoubleLine("Orange / yellow / green / grey", format("%d / %d / %d / %d", o, y, g, x), 0.8, 0.8, 0.8, 1, 1, 1)
  if not confirmed then
    GameTooltip:AddLine("The skill thresholds are estimated for this recipe; open that profession window once to pin them down.", 0.9, 0.8, 0.5, true)
  end
  GameTooltip:AddDoubleLine("Skill gained", format("%d to %d", step.from, step.to), 0.8, 0.8, 0.8, 1, 1, 1)
  GameTooltip:AddDoubleLine("Crafts needed", step.crafts, 0.8, 0.8, 0.8, 1, 1, 1)
  GameTooltip:AddDoubleLine("Cost", ns.Money(step.cost), 0.8, 0.8, 0.8, 1, 1, 1)
  GameTooltip:AddDoubleLine("Each skill point", ns.Money(floor(step.cost / math.max(1, step.to - step.from))), 0.8, 0.8, 0.8, 1, 1, 1)
  GameTooltip:AddDoubleLine("Recipe from", step.rec.src or "unknown", 0.8, 0.8, 0.8, 1, 1, 1)
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Materials for one craft:", 1, 1, 1)
  for _, r in ipairs(rec.r) do
    local name = GetItemInfo(r[1]) or ("item " .. r[1])
    local price = ns.Leveling:ItemCost(r[1])
    GameTooltip:AddDoubleLine(format("   %dx %s", r[2], name), price and ns.Money(price) or "|cff888888no price|r", 0.9, 0.9, 0.9, 1, 1, 1)
  end
  if rec.ri and rec.ri > 0 then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("You need the recipe itself: " .. (rec.src or "unknown"), 0.8, 0.8, 0.8, true)
  end
  GameTooltip:Show()
end

-- after the materials check, redo the plan on the prices it just read
function T:RePlanWithLivePrices()
  local before = self.info and self.info.total
  self:DoBuildPlan(false)
  local after = self.info and self.info.total
  if not before or not after then return end
  if after < before then
    self.note:SetText(format("|cff66dd88Re-planned on live prices: %s instead of %s. Press 'Find materials' again to buy the new list.|r",
      ns.Money(after), ns.Money(before)))
  elseif after > before then
    self.note:SetText(format("|cffe6cc80Live prices are dearer than the estimate: %s instead of %s.|r",
      ns.Money(after), ns.Money(before)))
  else
    self.note:SetText("|cff888888Prices confirmed against the auction house.|r")
  end
end

-- "Find recipe on AH" only makes sense for a recipe you must buy
function T:UpdateStepButtons()
  if not self.findRecipeBtn then return end
  local step, prof = self.selected, self.prof.value
  local usable = false
  if step and prof and not ns.Leveling:Knows(prof, step.rec) then
    usable = ns.Leveling:RecipeItemName(prof, step.rec) ~= nil
  end
  ns.Enable(self.findRecipeBtn, usable)
end

function T:QueueSummary()
  local info = self.info
  if not info then return "these materials" end
  return format("everything for %s %d to %d", self.prof.value or "", info.from or 0, info.to or 0)
end
