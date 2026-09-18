local ADDON, ns = ...

-- Items sold by NPC vendors (e.g. Imbued Vial).
--   ns.db.vendorBuy[itemID] = { ["Realm - Character"] = unit price, ... }
-- Prices are stored per character because reputation discounts (up to 20%)
-- change what a vendor charges.

-- Common trade goods that NPC vendors sell. Used to recognise vendor items
-- before their price has been recorded, so an inflated auction house price
-- is never mistaken for their real cost.
local KNOWN_VENDOR_ITEMS = {
  -- alchemy / inscription
  "empty vial", "leaded vial", "crystal vial", "imbued vial",
  "light parchment", "common parchment", "heavy parchment", "resilient parchment",
  -- tailoring / leatherworking
  "coarse thread", "fine thread", "silken thread", "heavy silken thread", "rune thread", "eternium thread",
  "bleach", "gray dye", "green dye", "red dye", "blue dye", "yellow dye", "black dye",
  "salt",
  -- blacksmithing / engineering / enchanting
  "weak flux", "strong flux", "copper rod",
  -- vellums are left out on purpose: scribes make them and they are normally
  -- bought on the auction house, so auction prices are the right ones to use
  -- cooking
  "refreshing spring water", "simple flour", "mild spices", "hot spices", "northern spices",
  -- tools
  "mining pick", "skinning knife", "blacksmith hammer", "arclight spanner", "gyromatic micro-adjustor",
}
local KNOWN = {}
for _, n in ipairs(KNOWN_VENDOR_ITEMS) do KNOWN[n] = true end

local function CharKey()
  return (GetRealmName() or "?") .. " - " .. (UnitName("player") or "?")
end

-- Unit price a vendor charges this character; for items only seen by other
-- characters, the highest of their prices (never underestimates the cost).
function ns.VendorPrice(id)
  local rec = id and ns.db and ns.db.vendorBuy and ns.db.vendorBuy[id]
  if not rec then return nil end
  if type(rec) == "number" then return rec end -- data from an older version
  local mine = rec[CharKey()]
  if mine then return mine end
  local high
  for _, v in pairs(rec) do
    if not high or v > high then high = v end
  end
  return high
end

-- True for items known to be sold by vendors (recorded, or on the list above)
function ns.IsVendorItem(id, name)
  if id and ns.VendorPrice(id) then return true end
  return name and KNOWN[strlower(name)] or false
end

---------------------------------------------------------------------------
-- Record prices whenever a merchant window is open
---------------------------------------------------------------------------
local merchant = CreateFrame("Frame")
merchant:RegisterEvent("MERCHANT_SHOW")
merchant:RegisterEvent("MERCHANT_UPDATE")
merchant:SetScript("OnEvent", function()
  if not ns.db then return end
  ns.db.vendorBuy = ns.db.vendorBuy or {}
  local key = CharKey()
  for i = 1, (GetMerchantNumItems() or 0) do
    local name, _, price, quantity, numAvailable, _, extendedCost = GetMerchantItemInfo(i)
    local link = GetMerchantItemLink(i)
    local id = ns.ItemID(link)
    -- gold price only (no honor/tokens), unlimited stock (limited items can't be counted on)
    if id and name and price and price > 0 and not extendedCost and (numAvailable == nil or numAvailable < 0) then
      local unit = price / math.max(1, quantity or 1) -- price is for the whole bundle
      local rec = ns.db.vendorBuy[id]
      if type(rec) ~= "table" then
        rec = {}
        ns.db.vendorBuy[id] = rec
      end
      rec[key] = unit -- latest price for this character (reputation discount included)
      ns.db.itemNames = ns.db.itemNames or {}
      ns.db.itemNames[id] = strlower(name)
    end
  end
end)

---------------------------------------------------------------------------
-- Split a needed amount between cheaper-than-vendor auctions and the vendor
-- Returns plan (auction part or nil), vendorQty, vendorUnit, unknown
--   unknown = vendor item whose price hasn't been recorded yet
---------------------------------------------------------------------------
function ns.PlanWithVendor(auctions, need, id, name, me)
  local vendorUnit = ns.VendorPrice(id)
  if vendorUnit then
    local cheaper = {}
    for _, a in ipairs(auctions or {}) do
      if a.unit and a.unit < vendorUnit then cheaper[#cheaper + 1] = a end
    end
    local plan = #cheaper > 0 and ns.PlanPurchase(cheaper, need, me) or nil
    local fromAH = plan and plan.count or 0
    if plan and fromAH == 0 then plan = nil end
    -- never pay more at the auction house than buying the same amount at the vendor
    if plan and plan.cost > vendorUnit * math.min(need, plan.count) then plan, fromAH = nil, 0 end
    return plan, math.max(0, need - fromAH), vendorUnit, false
  end
  if ns.IsVendorItem(id, name) then
    return nil, need, nil, true
  end
  return ns.PlanPurchase(auctions or {}, need, me), 0, nil, false
end
