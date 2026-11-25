-- CrateShuffle: static data for WoW: Forever Waylaid Crates.
-- Fill options come from community crate lists (wowforeverbuilds / outof.games / wowhandbook).
-- Item IDs are the classic IDs (Forever reuses the classic item pool).
-- Every crate is filled with ONE of its options.

local _, ns = ...
ns = ns or {}

local I = {
  -- cloth / bolts
  LinenCloth = 2589, WoolCloth = 2592, SilkCloth = 4306, MageweaveCloth = 4338, Runecloth = 14047,
  BoltLinen = 2996, BoltWool = 2997, BoltSilk = 4305, BoltMageweave = 4339, BoltRunecloth = 14048,
  -- leather / hides
  LightLeather = 2318, MediumLeather = 2319, HeavyLeather = 4234, ThickLeather = 4304, RuggedLeather = 8170,
  CuredLightHide = 4231, CuredMediumHide = 4233, CuredHeavyHide = 4236, CuredThickHide = 8172,
  -- ore / bars
  CopperOre = 2770, TinOre = 2771, IronOre = 2772, SilverOre = 2775, GoldOre = 2776,
  MithrilOre = 3858, TruesilverOre = 7911, ThoriumOre = 10620, DarkIronOre = 11370,
  CopperBar = 2840, TinBar = 3576, BronzeBar = 2841, SilverBar = 2842, IronBar = 3575,
  GoldBar = 3577, SteelBar = 3859, MithrilBar = 3860, TruesilverBar = 6037, ThoriumBar = 12359,
  DarkIronBar = 11371,
  -- engineering parts
  CopperBolts = 4359, CopperTube = 4361, CopperModulator = 4363,
  BronzeTube = 4371, WhirringBronzeGizmo = 4375, BronzeFramework = 4382, GoldPowerCore = 10558,
  IronStrut = 4387, MithrilTube = 10559, UnstableTrigger = 10560, MithrilCasing = 10561,
  ThoriumWidget = 15994, TruesilverTransformer = 18631, ThoriumTube = 16000,
  -- enchanting
  StrangeDust = 10940, GreaterMagicEssence = 10939, SmallGlimmeringShard = 10978, LargeGlimmeringShard = 11084,
  SoulDust = 11083, GreaterAstralEssence = 11082, SmallGlowingShard = 11138, LargeGlowingShard = 11139,
  VisionDust = 11137, GreaterMysticEssence = 11135, SmallRadiantShard = 11177, LargeRadiantShard = 11178,
  DreamDust = 11176, GreaterNetherEssence = 11175, SmallBrilliantShard = 14343, LargeBrilliantShard = 14344,
  -- herbs
  Peacebloom = 2447, Silverleaf = 765, Earthroot = 2449, Mageroyal = 785, Briarthorn = 2450,
  Stranglekelp = 3820, Bruiseweed = 2453, WildSteelbloom = 3355, GraveMoss = 3369, Kingsblood = 3356,
  Liferoot = 3357, Fadeleaf = 3818, Goldthorn = 3821, KhadgarsWhisker = 3358,
  Wintersbite = 3819, Firebloom = 4625, PurpleLotus = 8831, ArthasTears = 8836,
  GoldenSansam = 13464, Sungrass = 8838, Blindweed = 8839, GhostMushroom = 8845, Gromsblood = 8846,
  Dreamfoil = 13463, MountainSilversage = 13465, Plaguebloom = 13466, Icecap = 13467,
}
ns.ItemIDs = I

-- Fallback display names (used until the client has item data cached).
ns.ItemNames = {}
for k, id in pairs(I) do
  ns.ItemNames[id] = (k:gsub("(%l)(%u)", "%1 %2"))
end

-- Tier info. favor = gathered (white) crate favor; crafted (green) crates pay double.
-- Artisan favor is community-expected, not confirmed.
ns.Tiers = {
  Apprentice = { order = 1, minLevel = 10, favor = 5 },
  Journeyman = { order = 2, minLevel = 10, favor = 10 },
  Expert     = { order = 3, minLevel = 20, favor = 15 },
  Artisan    = { order = 4, minLevel = 35, favor = 20, unconfirmed = true },
}

local function o(...) -- one fill option: pairs of (itemID, qty)
  local t, a = {}, { ... }
  for i = 1, #a, 2 do t[#t + 1] = { id = a[i], qty = a[i + 1] } end
  return t
end

-- name = suffix after "Waylaid Crate: "
ns.Crates = {
  -- Apprentice
  { name = "Apprentice Fabrics",     tier = "Apprentice", crafted = true,  fills = { o(I.BoltLinen, 20), o(I.CuredLightHide, 2) } },
  { name = "Apprentice Ingots",      tier = "Apprentice", crafted = true,  fills = { o(I.CopperBar, 20), o(I.TinBar, 20), o(I.BronzeBar, 10) } },
  { name = "Apprentice Parts",       tier = "Apprentice", crafted = true,  fills = { o(I.CopperBolts, 16), o(I.CopperTube, 16), o(I.CopperModulator, 4) } },
  { name = "Apprentice Curiosities", tier = "Apprentice", crafted = false, fills = { o(I.StrangeDust, 20), o(I.GreaterMagicEssence, 4), o(I.SmallGlimmeringShard, 6), o(I.LargeGlimmeringShard, 2) } },
  { name = "Apprentice Herbs",       tier = "Apprentice", crafted = false, fills = { o(I.Peacebloom, 20), o(I.Silverleaf, 20), o(I.Earthroot, 10), o(I.Mageroyal, 10), o(I.Briarthorn, 10) } },
  { name = "Apprentice Ore",         tier = "Apprentice", crafted = false, fills = { o(I.CopperOre, 20), o(I.TinOre, 20) } },
  { name = "Apprentice Textiles",    tier = "Apprentice", crafted = false, fills = { o(I.LinenCloth, 40), o(I.LightLeather, 20) } },
  -- Journeyman
  { name = "Journeyman Fabrics",     tier = "Journeyman", crafted = true,  fills = { o(I.BoltWool, 6), o(I.BoltSilk, 10), o(I.CuredMediumHide, 2) } },
  { name = "Journeyman Ingots",      tier = "Journeyman", crafted = true,  fills = { o(I.SilverBar, 10), o(I.IronBar, 20) } },
  { name = "Journeyman Parts",       tier = "Journeyman", crafted = true,  fills = { o(I.BronzeTube, 8), o(I.WhirringBronzeGizmo, 7), o(I.BronzeFramework, 4), o(I.GoldPowerCore, 45) } },
  { name = "Journeyman Curiosities", tier = "Journeyman", crafted = false, fills = { o(I.SoulDust, 20), o(I.GreaterAstralEssence, 4), o(I.SmallGlowingShard, 6), o(I.LargeGlowingShard, 2) } },
  { name = "Journeyman Herbs",       tier = "Journeyman", crafted = false, fills = { o(I.Stranglekelp, 10), o(I.Bruiseweed, 10), o(I.WildSteelbloom, 10), o(I.GraveMoss, 10), o(I.Kingsblood, 10) } },
  { name = "Journeyman Ore",         tier = "Journeyman", crafted = false, fills = { o(I.SilverOre, 10), o(I.IronOre, 20) } },
  { name = "Journeyman Textiles",    tier = "Journeyman", crafted = false, fills = { o(I.WoolCloth, 20), o(I.SilkCloth, 40), o(I.MediumLeather, 20) } },
  -- Expert
  { name = "Expert Fabrics",         tier = "Expert", crafted = true,  fills = { o(I.BoltMageweave, 8), o(I.CuredHeavyHide, 2) } },
  { name = "Expert Ingots",          tier = "Expert", crafted = true,  fills = { o(I.MithrilBar, 20), o(I.SteelBar, 15), o(I.GoldBar, 10) } },
  { name = "Expert Parts",           tier = "Expert", crafted = true,  fills = { o(I.IronStrut, 8), o(I.MithrilTube, 5), o(I.UnstableTrigger, 12), o(I.MithrilCasing, 5) } },
  { name = "Expert Curiosities",     tier = "Expert", crafted = false, fills = { o(I.VisionDust, 20), o(I.GreaterMysticEssence, 4), o(I.SmallRadiantShard, 6), o(I.LargeRadiantShard, 2) } },
  { name = "Earthly Expert Herbs",   tier = "Expert", crafted = false, fills = { o(I.Liferoot, 20), o(I.Fadeleaf, 10), o(I.Goldthorn, 10), o(I.KhadgarsWhisker, 10) } },
  { name = "Flowering Expert Herbs", tier = "Expert", crafted = false, fills = { o(I.Wintersbite, 10), o(I.Firebloom, 10), o(I.PurpleLotus, 20), o(I.ArthasTears, 10) } },
  { name = "Expert Ore",             tier = "Expert", crafted = false, fills = { o(I.GoldOre, 10), o(I.MithrilOre, 20) } },
  { name = "Expert Textiles",        tier = "Expert", crafted = false, fills = { o(I.MageweaveCloth, 40), o(I.HeavyLeather, 20) } },
  -- Artisan
  { name = "Artisan Fabrics",        tier = "Artisan", crafted = true,  fills = { o(I.BoltRunecloth, 8), o(I.CuredThickHide, 2) } },
  { name = "Artisan Ingots",         tier = "Artisan", crafted = true,  fills = { o(I.DarkIronBar, 2), o(I.TruesilverBar, 10), o(I.ThoriumBar, 20) } },
  { name = "Artisan Parts",          tier = "Artisan", crafted = true,  fills = { o(I.ThoriumWidget, 5), o(I.TruesilverTransformer, 5), o(I.ThoriumTube, 2) } },
  { name = "Artisan Curiosities",    tier = "Artisan", crafted = false, fills = { o(I.DreamDust, 20), o(I.GreaterNetherEssence, 4), o(I.SmallBrilliantShard, 6), o(I.LargeBrilliantShard, 2) } },
  { name = "Earthly Artisan Herbs",  tier = "Artisan", crafted = false, fills = { o(I.GoldenSansam, 10), o(I.Sungrass, 20), o(I.Blindweed, 10), o(I.GhostMushroom, 10), o(I.Gromsblood, 10) } },
  { name = "Flowering Artisan Herbs",tier = "Artisan", crafted = false, fills = { o(I.Dreamfoil, 20), o(I.MountainSilversage, 20), o(I.Plaguebloom, 20), o(I.Icecap, 20) } },
  { name = "Artisan Ore",            tier = "Artisan", crafted = false, fills = { o(I.TruesilverOre, 10), o(I.ThoriumOre, 20), o(I.DarkIronOre, 20) } },
  { name = "Artisan Textiles",       tier = "Artisan", crafted = false, fills = { o(I.Runecloth, 40), o(I.ThickLeather, 20), o(I.RuggedLeather, 20) } },
}

-- The unread "Waylaid Crate" (right-click to read its label) is still an empty crate,
-- so it is a valid target for a Forged Delivery Receipt.
ns.UNREAD_KEY = "unread"

-- Order-insensitive key from a crate name, so "Earthly Expert Herbs" and
-- "Expert Herbs (Earthly)" both match.
function ns.CrateKey(name)
  if not name then return nil end
  local s = name:lower():gsub("^%s*waylaid crate%s*:?%s*", "")
  local words = {}
  for w in s:gmatch("%a+") do words[#words + 1] = w end
  if #words == 0 then return ns.UNREAD_KEY end
  table.sort(words)
  return table.concat(words, " ")
end

ns.CrateByKey = {}
for _, c in ipairs(ns.Crates) do
  c.key = ns.CrateKey(c.name)
  c.favor = ns.Tiers[c.tier].favor * (c.crafted and 2 or 1)
  ns.CrateByKey[c.key] = c
end

-- All material item IDs that need prices.
function ns.AllMaterialIDs()
  local seen, list = {}, {}
  for _, c in ipairs(ns.Crates) do
    for _, opt in ipairs(c.fills) do
      for _, comp in ipairs(opt) do
        if not seen[comp.id] then seen[comp.id] = true; list[#list + 1] = comp.id end
      end
    end
  end
  table.sort(list)
  return list
end

-- Rep sizes of each standing (after Friendly). Friendly->Honored, Honored->Revered, Revered->Exalted.
ns.StandingSize = { [5] = 6000, [6] = 12000, [7] = 21000 }
ns.StandingName = { [4] = "Neutral", [5] = "Friendly", [6] = "Honored", [7] = "Revered", [8] = "Exalted" }
ns.FactionNames = { ["Azeroth Commerce Authority"] = true, ["Durotar Supply and Logistics"] = true }
ns.FAVOR_CURRENCY_NAME = "Merchant's Favor"
ns.RECEIPT_FAVOR = 15

return ns
