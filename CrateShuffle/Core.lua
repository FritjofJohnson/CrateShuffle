-- CrateShuffle core: settings, reputation/favor reading, price history, report, slash commands.

local ADDON, ns = ...
local E = ns.Engine
local Money = E.Money

ns.DEFAULTS = {
  target = "next",          -- "next", "honored", "revered", "exalted", or a number of turn-ins
  fallbackTurnins = 120,    -- used when your reputation can't be read (120 = Friendly -> Honored)
  repPerTurnin = 50,        -- raise if you have the Diplomat Legacy perk
  perkRanks = 0,            -- Performance Bonus Legacy perk ranks (5% chance of double favor per rank)
  useFavorOnHand = true,
  receiptSilver = 100,      -- copper paid back when turning in a receipted crate (1s)
  filledSilver = { Apprentice = 0, Journeyman = 500, Expert = 0, Artisan = 0 }, -- copper per filled crate
  holdPct = 0.15,           -- HOLD when prices are this much above their 30-day median
  capPerRep = nil,          -- optional hard cap, copper per rep
  debug = false,
}

local function copyDefaults(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      copyDefaults(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end

function ns.Print(...)
  local msg = table.concat({ tostringall(...) }, " ")
  print("|cff33ff99CrateShuffle|r: " .. msg)
end
function ns.Debug(...)
  if CrateShuffleDB and CrateShuffleDB.settings.debug then ns.Print("|cff888888" .. table.concat({ tostringall(...) }, " ") .. "|r") end
end

function ns.GetItemName(id)
  return (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or ns.ItemNames[id] or ("item " .. id)
end

local function today() return math.floor(time() / 86400) end

local function realmDB()
  local key = (GetRealmName() or "?") .. "-" .. (UnitFactionGroup("player") or "?")
  local r = CrateShuffleDB.realms[key]
  if not r then r = { items = {}, crates = {}, route = {} }; CrateShuffleDB.realms[key] = r end
  return r
end

---------------------------------------------------------------------------
-- Reputation & favor
---------------------------------------------------------------------------
function ns.ReadReputation()
  if not (C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex) then return nil end
  local function scan()
    for i = 1, C_Reputation.GetNumFactions() do
      local d = C_Reputation.GetFactionDataByIndex(i)
      if d and d.name and ns.FactionNames[d.name] then return d end
    end
  end
  local ok, d = pcall(scan)
  if (not ok or not d) and C_Reputation.ExpandAllFactionHeaders then
    pcall(C_Reputation.ExpandAllFactionHeaders)
    ok, d = pcall(scan)
  end
  if ok and d and d.reaction then
    return {
      name = d.name, reaction = d.reaction,
      intoStanding = (d.currentStanding or 0) - (d.currentReactionThreshold or 0),
      toNext = (d.nextReactionThreshold or 0) - (d.currentStanding or 0),
    }
  end
end

function ns.ReadFavor()
  if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyListSize) then return nil end
  local ok, q = pcall(function()
    for i = 1, C_CurrencyInfo.GetCurrencyListSize() do
      local info = C_CurrencyInfo.GetCurrencyListInfo(i)
      if info and info.name == ns.FAVOR_CURRENCY_NAME then return info.quantity end
    end
  end)
  return ok and q or nil
end

local TARGET_REACTION = { honored = 6, revered = 7, exalted = 8 }

-- Returns number of turn-ins, description
function ns.TurnInsNeeded(s, rep)
  local R = s.repPerTurnin
  if type(s.target) == "number" then return s.target, s.target .. " turn-ins (manual)" end
  if not rep then
    return s.fallbackTurnins, s.fallbackTurnins .. " turn-ins (reputation not readable; set with /crate target)"
  end
  if rep.reaction >= 8 then return 0, "Already Exalted" end
  local goal = TARGET_REACTION[s.target] or (rep.reaction + 1)
  if goal <= rep.reaction then goal = rep.reaction + 1 end
  local need = rep.toNext
  for r = rep.reaction + 1, goal - 1 do need = need + (ns.StandingSize[r] or 0) end
  return math.ceil(need / R), ("%d rep to %s"):format(need, ns.StandingName[goal] or "?")
end

---------------------------------------------------------------------------
-- History
---------------------------------------------------------------------------
local function recordHistory(snapshot, plan)
  local r, d = realmDB(), today()
  for id, data in pairs(snapshot.items) do
    local v = E.CheapAvg(data.listings, 100)
    if v then r.items[id] = r.items[id] or {}; r.items[id][d] = v end
  end
  for key, data in pairs(snapshot.crates) do
    local v = E.CheapAvg(data.listings, 10)
    if v then r.crates[key] = r.crates[key] or {}; r.crates[key][d] = v end
  end
  if plan.bestPerRep then r.route[d] = plan.bestPerRep end
  -- prune anything older than 45 days
  local cutoff = d - 45
  local function prune(t) for k in pairs(t) do if k < cutoff then t[k] = nil end end end
  prune(r.route)
  for _, t in pairs(r.items) do prune(t) end
  for _, t in pairs(r.crates) do prune(t) end
end

local function volatilityNote(series, current)
  local st = E.SeriesStats(series, today(), 30)
  if st.n < 3 or not st.median then return nil end
  local notes = {}
  if st.cv > 0.30 then notes[#notes + 1] = ("|cffff8000volatile|r (±%d%%)"):format(math.floor(st.cv * 100 + 0.5)) end
  if current and st.median > 0 then
    local diff = current / st.median - 1
    if diff > 0.20 then
      notes[#notes + 1] = ("|cffff4040%d%% above 30d median|r"):format(math.floor(diff * 100 + 0.5))
    elseif diff < -0.20 then
      notes[#notes + 1] = ("|cff40ff40%d%% below 30d median|r"):format(math.floor(-diff * 100 + 0.5))
    end
  end
  if #notes == 0 then return nil end
  return table.concat(notes, ", ")
end

---------------------------------------------------------------------------
-- Analysis + report
---------------------------------------------------------------------------
function ns.BuildOptions()
  local s = CrateShuffleDB.settings
  local rep = ns.ReadReputation()
  local favor = ns.ReadFavor()
  local turnins, targetText = ns.TurnInsNeeded(s, rep)
  return {
    level = UnitLevel("player"),
    turnins = turnins, targetText = targetText, rep = rep, favorRead = favor,
    favorOnHand = s.useFavorOnHand and (favor or 0) or 0,
    repPerTurnin = s.repPerTurnin, receiptFavor = ns.RECEIPT_FAVOR,
    filledSilver = s.filledSilver, receiptSilver = s.receiptSilver,
    perkChance = 0.05 * (s.perkRanks or 0),
    holdPct = s.holdPct, capPerRep = s.capPerRep,
    history = { route = realmDB().route, today = today() },
  }
end

local ACTION_COLOR = { BUY = "|cff40ff40", ["BUY SOME"] = "|cffffd000", HOLD = "|cffff4040" }

function ns.Analyze(snapshot)
  local opts = ns.BuildOptions()
  local plan = E.Plan(snapshot, opts)
  local verdict = E.Verdict(plan, opts)
  recordHistory(snapshot, plan)
  CrateShuffleDB.lastReport = ns.Report(snapshot, opts, plan, verdict)
  ns.lastSnapshot = snapshot
  return plan, verdict
end

function ns.Report(snapshot, opts, plan, v)
  local L = {}
  local function add(...) L[#L + 1] = table.concat({ ... }) end
  local R = opts.repPerTurnin

  add(ACTION_COLOR[v.action] or "", "== ", v.action, " ==|r")
  for _, r in ipairs(v.reasons) do add("  ", r) end
  add("")

  if opts.rep then
    add(("Standing: %s (%d into standing). Goal: %s."):format(ns.StandingName[opts.rep.reaction] or "?", opts.rep.intoStanding, opts.targetText))
    if opts.rep.reaction < 5 then add("|cffff4040You need Friendly to buy Forged Delivery Receipts.|r") end
  else
    add("Goal: ", opts.targetText)
  end
  add(("Merchant's Favor on hand: %s%s"):format(opts.favorRead and tostring(opts.favorRead) or "unknown",
    opts.favorOnHand > 0 and " (counted)" or ""))
  add("")

  if plan.bestPerRep then
    add("|cffffd100Price / rep right now|r")
    add(("  %s per rep  =  %s per turn-in (%d rep)"):format(Money(plan.bestPerRep), Money(plan.bestTurnin), R))
    add(("  %.0f rep per gold"):format(10000 / plan.bestPerRep))
    if v.medianPerRep then add(("  30-day median: %s per rep"):format(Money(v.medianPerRep))) end
    add("")
  end

  if plan.turnins > 0 then
    add(("|cffffd100Plan for %d turn-ins (%d rep)|r"):format(plan.turnins, plan.rep))
    add(("  Total %s, average %s per rep"):format(Money(plan.totalCost), Money(plan.avgPerRep)))
    if v.goodTurnins and v.goodTurnins < plan.turnins then
      add(("  |cffffd000Buy now: the first %d turn-ins.|r Beyond that the next listings get pricey."):format(v.goodTurnins))
    end
    add(("  Buy %d Forged Delivery Receipts (%d favor) at the camp."):format(plan.turnins, plan.turnins * ns.RECEIPT_FAVOR))
    add("  Fill for favor:")
    for _, u in ipairs(plan.fillsUsed) do
      add(("    %dx %s with %s"):format(u.count, u.fill.crate.name, E.FillLabel(u.fill)))
    end
    add("  Keep empty for receipts:")
    for _, u in ipairs(plan.emptiesUsed) do
      add(("    %dx %s%s"):format(u.count, u.name, u.key == ns.UNREAD_KEY and " (right-click to read it first)" or ""))
    end
    add("")
    add("|cffffd100Shopping list|r (pay at most the max unit price)")
    local r = realmDB()
    for _, s in ipairs(plan.shopping) do
      local name, series, cur
      if s.kind == "item" then
        name, series = ns.GetItemName(s.id), r.items[s.id]
        cur = E.CheapAvg(snapshot.items[s.id].listings, 100)
      else
        name, series = s.name, r.crates[s.key]
        cur = E.CheapAvg(snapshot.crates[s.key].listings, 10)
      end
      local note = volatilityNote(series, cur)
      add(("  %d x %s  — %s total, max %s each%s"):format(s.qty, name, Money(s.spent), Money(s.maxUnit),
        note and ("  [" .. note .. "]") or ""))
    end
    add("")
  end

  add("|cffffd100Cheapest favor routes|r (per favor, and how many fills are available within 10%)")
  for i, x in ipairs(E.RankRoutes(snapshot, opts, 6)) do
    add(("  %d. %s with %s: %s/favor, ~%d fills"):format(i, x.fill.crate.name, E.FillLabel(x.fill), Money(x.perFavor), x.depth))
  end
  add("|cffffd100Cheapest empty crates|r (net of the receipt silver)")
  for i, x in ipairs(E.RankEmpties(snapshot, opts, 4)) do
    add(("  %d. %s: %s (%d listed)"):format(i, x.name, Money(x.unit), x.available))
  end

  local nCrates = 0
  for _ in pairs(snapshot.crates) do nCrates = nCrates + 1 end
  add("")
  add(("|cff888888Scanned %d crate types and %d materials at %s. Silver paid on filled turn-ins is set per tier; check /crate settings.|r")
    :format(nCrates, #ns.AllMaterialIDs(), date("%H:%M", snapshot.time)))
  return table.concat(L, "\n")
end

---------------------------------------------------------------------------
-- Scan entry point
---------------------------------------------------------------------------
function ns.Scan()
  if ns.UI then ns.UI.Show(); ns.UI.SetStatus("Scanning...") end
  ns.Scanner.Start(function(snapshot)
    local plan, v = ns.Analyze(snapshot)
    if ns.UI then ns.UI.SetText(CrateShuffleDB.lastReport); ns.UI.SetStatus("Done: " .. v.action) end
    if plan.bestPerRep then
      ns.Print(("%s%s|r — %s per rep, %d turn-ins planned for %s."):format(ACTION_COLOR[v.action] or "", v.action,
        Money(plan.bestPerRep), plan.turnins, Money(plan.totalCost)))
    else
      ns.Print(ACTION_COLOR.HOLD .. "HOLD|r — " .. (v.reasons[1] or "nothing available"))
    end
  end, function(done, total)
    if ns.UI then ns.UI.SetStatus(("Scanning... %d / %d"):format(done, total)) end
  end)
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local HELP = {
  "/crate - show or hide the window",
  "/crate scan - scan the auction house (AH must be open)",
  "/crate target next|honored|revered|exalted|<turn-ins>",
  "/crate silver <apprentice|journeyman|expert|artisan|receipt> <silver> - silver paid back per turn-in",
  "/crate perk <0-3> - Performance Bonus ranks (5% double-favor chance each)",
  "/crate rep <n> - rep per receipted crate (default 50)",
  "/crate hold <percent> - hold when price is this far above the 30-day median (default 15)",
  "/crate cap <silver per 50 rep|off> - never buy above this",
  "/crate favor on|off - count Merchant's Favor you already have",
  "/crate settings, /crate resethistory, /crate debug",
}

local function tierName(s)
  s = s and s:lower() or ""
  for name in pairs(ns.Tiers) do if name:lower() == s then return name end end
end

SLASH_CRATESHUFFLE1, SLASH_CRATESHUFFLE2 = "/crate", "/crateshuffle"
SlashCmdList.CRATESHUFFLE = function(msg)
  local s = CrateShuffleDB.settings
  local cmd, a, b = (msg or ""):lower():match("^%s*(%S*)%s*(%S*)%s*(%S*)")
  if cmd == "" then
    ns.UI.Toggle()
  elseif cmd == "scan" then
    ns.Scan()
  elseif cmd == "target" then
    local n = tonumber(a)
    if n then s.target = math.floor(n)
    elseif a == "next" or TARGET_REACTION[a] then s.target = a
    else ns.Print("Usage: /crate target next|honored|revered|exalted|<turn-ins>"); return end
    ns.Print("Target: " .. tostring(s.target))
  elseif cmd == "silver" then
    local v = tonumber(b)
    if not v then ns.Print("Usage: /crate silver <tier|receipt> <silver>"); return end
    if a == "receipt" then s.receiptSilver = math.floor(v * 100)
    elseif tierName(a) then s.filledSilver[tierName(a)] = math.floor(v * 100)
    else ns.Print("Unknown tier: " .. a); return end
    ns.Print("Saved.")
  elseif cmd == "perk" then
    s.perkRanks = math.max(0, math.min(3, tonumber(a) or 0)); ns.Print("Performance Bonus ranks: " .. s.perkRanks)
  elseif cmd == "rep" then
    s.repPerTurnin = tonumber(a) or 50; ns.Print("Rep per receipted crate: " .. s.repPerTurnin)
  elseif cmd == "hold" then
    s.holdPct = (tonumber(a) or 15) / 100; ns.Print(("Hold threshold: %d%%"):format(s.holdPct * 100))
  elseif cmd == "cap" then
    if a == "off" or a == "" then s.capPerRep = nil; ns.Print("Cap off.")
    else
      local v = tonumber(a)
      if not v then ns.Print("Usage: /crate cap <silver per 50 rep|off>"); return end
      s.capPerRep = v * 100 / 50
      ns.Print(("Cap: %s per turn-in (%s per rep)"):format(Money(v * 100), Money(s.capPerRep)))
    end
  elseif cmd == "favor" then
    s.useFavorOnHand = (a ~= "off"); ns.Print("Count favor on hand: " .. tostring(s.useFavorOnHand))
  elseif cmd == "settings" then
    ns.Print(("target=%s rep/turn-in=%d perk=%d hold=%d%% cap=%s favorOnHand=%s receipt silver=%s")
      :format(tostring(s.target), s.repPerTurnin, s.perkRanks, s.holdPct * 100,
        s.capPerRep and Money(s.capPerRep * 50) .. "/turn-in" or "off", tostring(s.useFavorOnHand), Money(s.receiptSilver)))
    for _, t in ipairs({ "Apprentice", "Journeyman", "Expert", "Artisan" }) do
      ns.Print(("  silver per filled %s crate: %s"):format(t, Money(s.filledSilver[t] or 0)))
    end
  elseif cmd == "resethistory" then
    CrateShuffleDB.realms = {}; ns.Print("Price history cleared.")
  elseif cmd == "debug" then
    s.debug = not s.debug; ns.Print("Debug: " .. tostring(s.debug))
  else
    for _, l in ipairs(HELP) do ns.Print(l) end
  end
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------
local init = CreateFrame("Frame")
init:RegisterEvent("ADDON_LOADED")
init:RegisterEvent("AUCTION_HOUSE_SHOW")
init:SetScript("OnEvent", function(_, event, arg)
  if event == "ADDON_LOADED" and arg == ADDON then
    CrateShuffleDB = CrateShuffleDB or {}
    CrateShuffleDB.settings = CrateShuffleDB.settings or {}
    CrateShuffleDB.realms = CrateShuffleDB.realms or {}
    copyDefaults(CrateShuffleDB.settings, ns.DEFAULTS)
  elseif event == "AUCTION_HOUSE_SHOW" then
    if ns.UI then ns.UI.AttachToAH() end
  end
end)
