local ADDON, ns = ...
local format = string.format

-- `/bh check` looks at what the addon actually built in this client.
--
-- The test suite runs against a stand-in for the game, so it cannot see a tab
-- hidden behind a button, a list drawn outside its panel, or a call to a
-- function that doesn't exist. This does, in one reload.

local C = {}
ns.SelfCheck = C

local function ok(list, text) list[#list + 1] = { true, text } end
local function bad(list, text) list[#list + 1] = { false, text } end

local function Width(frame)
  return frame and frame.GetWidth and frame:GetWidth() or 0
end

function C:Run()
  local r = {}

  -- the window and its tabs
  local main = ns.main
  if not main then
    bad(r, "the window has not been built yet - open it once, then run this again")
    return r
  end
  ok(r, format("window built, %d tabs, %d pages", #main.tabs, #main.pages))
  if #main.tabs ~= #main.pages then
    bad(r, format("%d tabs but %d pages", #main.tabs, #main.pages))
  end

  for i, tab in ipairs(main.tabs) do
    local page = main.pages[i]
    local label = tab.label and tab.label:GetText() or ("tab " .. i)
    if not page then
      bad(r, format("%s has no page behind it", label))
    end
    -- every tab must sit inside the window
    local right = tab:GetRight()
    local edge = main:GetRight()
    if right and edge and right > edge - 4 then
      bad(r, format("%s is drawn outside the window", label))
    end
  end

  -- each page's widgets must fit the area they share with the materials panel
  local checks = {
    { "Crafting", ns.Crafting and ns.Crafting.recipeList, 292 },
    { "Level up", ns.LevelingTab and ns.LevelingTab.list, 292 },
    { "Shopping", ns.Shopping and ns.Shopping.list, 292 },
  }
  for _, c in ipairs(checks) do
    local name, frame, limit = c[1], c[2], c[3]
    if frame then
      local w = Width(frame)
      if w > limit + 2 then
        bad(r, format("%s: its list is %d wide and would cover the materials panel", name, w))
      end
    end
  end

  -- lists must not share a frame name, or they share a scroll bar
  local seen, dupes = {}, 0
  for _, name in ipairs({ "BargainHouseResults", "BargainHouseOffers", "BargainHouseRecipeList",
                          "BargainHouseLevelPlan", "BargainHouseLevelList", "BargainHouseDealList",
                          "BargainHouseWatchList", "BargainHouseSellList", "BargainHouseOwnerList",
                          "BargainHouseCharList", "BargainHouseSyncAccounts", "BargainHouseSyncLog",
                          "BargainHouseProfitList", "BargainHouseShopList", "BargainHouseCraftList" }) do
    local frame = _G[name]
    if frame then
      if seen[frame] then
        dupes = dupes + 1
        bad(r, format("%s shares its frame with %s", name, seen[frame]))
      end
      seen[frame] = name
    end
  end
  if dupes == 0 then ok(r, "every list has its own frame and scroll bar") end

  -- calls between modules that the tests cannot see
  local calls = {
    { "Browse:SearchFor", ns.Browse and ns.Browse.SearchFor },
    { "Leveling:Plan", ns.Leveling and ns.Leveling.Plan },
    { "Leveling:RecipeItemName", ns.Leveling and ns.Leveling.RecipeItemName },
    { "Watch:CheckAllNow", ns.Watch and ns.Watch.CheckAllNow },
    { "Ledger:AfterScan", ns.Ledger and ns.Ledger.AfterScan },
    { "Sync:RequestScans", ns.Sync and ns.Sync.RequestScans },
    { "FullScan:Deals", ns.FullScan and ns.FullScan.Deals },
    { "MaterialsPanel", ns.MaterialsPanel },
    { "SelectBlizzardSellTab", ns.SelectBlizzardSellTab },
  }
  local missing = 0
  for _, c in ipairs(calls) do
    if type(c[2]) ~= "function" then
      missing = missing + 1
      bad(r, c[1] .. " is missing")
    end
  end
  if missing == 0 then ok(r, format("all %d cross-module calls are present", #calls)) end

  -- the data the Level up tab needs
  if ns.ProfessionData then
    local profs, recipes = 0, 0
    for prof in pairs(ns.ProfessionData) do
      profs = profs + 1
      local list = ns.Leveling:Recipes(prof)
      recipes = recipes + (list and #list or 0)
    end
    ok(r, format("%d professions, %d recipes readable", profs, recipes))
  else
    bad(r, "profession data did not load")
  end

  -- the game's own bag clicks must never have been taken over
  if ContainerFrameItemButton_OnClick and ns.BagClickOriginal
     and ContainerFrameItemButton_OnClick ~= ns.BagClickOriginal then
    bad(r, "the game's bag click handler has been replaced (this causes blocked-action errors)")
  end

  return r
end

function C:Print()
  local rows = self:Run()
  local bad_ = 0
  ns.Print("|cff33d999BargainHouse check|r")
  for _, row in ipairs(rows) do
    if row[1] then
      ns.Print("  |cff66dd88ok|r  " .. row[2])
    else
      bad_ = bad_ + 1
      ns.Print("  |cffff5555!!|r  " .. row[2])
    end
  end
  if bad_ == 0 then
    ns.Print("  everything is where it should be")
  else
    ns.Print(format("  |cffff5555%d problem%s found|r - tell the author what it says", bad_, bad_ == 1 and "" or "s"))
  end
end
