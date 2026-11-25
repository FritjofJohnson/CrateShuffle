-- CrateShuffle engine: pure Lua (no WoW API), so it can be tested outside the game.
--
-- Model (per Forged Delivery Receipt turn-in):
--   1 receipt  = 15 Merchant's Favor, bought at the camp
--   1 empty Waylaid Crate (any type, incl. an unread one) + receipt -> R rep (50 by default)
--   Favor comes from filling crates: cost = crate + materials - silver paid on turn-in
--
-- Costs walk the real AH order book, so buying 180 crates prices the 180 cheapest,
-- not 180 x the single cheapest listing.

local _, ns = ...
ns = ns or {}
local E = {}
ns.Engine = E

local INF = math.huge
local floor, min, max = math.floor, math.min, math.max

---------------------------------------------------------------------------
-- Money formatting
---------------------------------------------------------------------------
function E.Money(c, plain)
  if c == nil or c ~= c then return "?" end
  if c == INF then return "n/a" end
  local neg = c < 0
  c = floor(math.abs(c) + 0.5)
  local g, s, cp = floor(c / 10000), floor(c / 100) % 100, c % 100
  local parts = {}
  local G, S, C = "g", "s", "c"
  if not plain then G, S, C = "|cffffd700g|r", "|cffc7c7cfs|r", "|cffeda55fc|r" end
  if g > 0 then parts[#parts + 1] = g .. G end
  if s > 0 or (g > 0 and cp > 0) then parts[#parts + 1] = s .. S end
  if cp > 0 or #parts == 0 then parts[#parts + 1] = cp .. C end
  return (neg and "-" or "") .. table.concat(parts, " ")
end

---------------------------------------------------------------------------
-- Order books
---------------------------------------------------------------------------
-- listings: array of { unit = copper per unit, qty = n }
function E.NewBook(listings)
  local l = {}
  for _, x in ipairs(listings or {}) do
    if x.unit and x.unit > 0 and x.qty and x.qty > 0 then l[#l + 1] = { unit = x.unit, qty = x.qty } end
  end
  table.sort(l, function(a, b) return a.unit < b.unit end)
  local total = 0
  for _, x in ipairs(l) do total = total + x.qty end
  return { l = l, i = 1, used = 0, total = total, bought = 0, spent = 0, maxUnit = 0 }
end

-- Cost of `qty` more units without consuming. Returns cost, highestUnit (nil if not enough supply).
function E.Peek(book, qty)
  if not book then return nil end
  local i, used, cost, hi, need = book.i, book.used, 0, 0, qty
  while need > 0 do
    local L = book.l[i]
    if not L then return nil end
    local take = min(L.qty - used, need)
    cost, hi, need, used = cost + take * L.unit, L.unit, need - take, used + take
    if used >= L.qty then i, used = i + 1, 0 end
  end
  return cost, hi
end

function E.Take(book, qty)
  local need, cost = qty, 0
  while need > 0 do
    local L = book.l[book.i]
    local take = min(L.qty - book.used, need)
    cost, need = cost + take * L.unit, need - take
    book.used = book.used + take
    book.maxUnit = max(book.maxUnit, L.unit)
    if book.used >= L.qty then book.i, book.used = book.i + 1, 0 end
  end
  book.bought, book.spent = book.bought + qty, book.spent + cost
  return cost
end

-- Average unit price of the cheapest n units (or all of them). Used as a sniping-resistant "market" price.
function E.CheapAvg(listings, n)
  local b = E.NewBook(listings)
  if b.total == 0 then return nil end
  local q = min(n, b.total)
  local c = E.Peek(b, q)
  return c / q
end

---------------------------------------------------------------------------
-- Stats
---------------------------------------------------------------------------
function E.Median(t)
  if #t == 0 then return nil end
  local s = {}
  for i, v in ipairs(t) do s[i] = v end
  table.sort(s)
  local n = #s
  if n % 2 == 1 then return s[(n + 1) / 2] end
  return (s[n / 2] + s[n / 2 + 1]) / 2
end

-- series: { [day] = value }. Returns { n, median, mean, cv, min, max } over the last `days` days.
function E.SeriesStats(series, today, days)
  local vals = {}
  for d, v in pairs(series or {}) do
    if type(d) == "number" and d > today - days and d <= today and type(v) == "number" then vals[#vals + 1] = v end
  end
  local n = #vals
  if n == 0 then return { n = 0 } end
  local sum, lo, hi = 0, INF, 0
  for _, v in ipairs(vals) do sum, lo, hi = sum + v, min(lo, v), max(hi, v) end
  local mean = sum / n
  local var = 0
  for _, v in ipairs(vals) do var = var + (v - mean) ^ 2 end
  local sd = n > 1 and math.sqrt(var / (n - 1)) or 0
  return { n = n, median = E.Median(vals), mean = mean, cv = mean > 0 and sd / mean or 0, min = lo, max = hi }
end

---------------------------------------------------------------------------
-- Planner
---------------------------------------------------------------------------
-- snapshot = {
--   items  = { [itemID] = { listings } },
--   crates = { [crateKey] = { listings, name = "full AH name" } },
-- }
-- opts = {
--   level, turnins, favorOnHand, repPerTurnin, receiptFavor,
--   filledSilver = { Apprentice=c, Journeyman=c, ... }, receiptSilver = c,
--   perkChance = 0..1 (Performance Bonus: chance of +100% favor), holdPct, capPerRep (copper or nil)
--   history = { route = {[day]=copperPerRep}, today = dayNumber }
-- }
local function buildBooks(snapshot)
  local items, crates = {}, {}
  for id, d in pairs(snapshot.items or {}) do items[id] = E.NewBook(d.listings) end
  for key, d in pairs(snapshot.crates or {}) do crates[key] = E.NewBook(d.listings) end
  return items, crates
end

local function fillOptions(opts)
  local list = {}
  for _, c in ipairs(ns.Crates) do
    local tier = ns.Tiers[c.tier]
    if (opts.level or 60) >= tier.minLevel then
      for oi, opt in ipairs(c.fills) do
        list[#list + 1] = {
          crate = c, optIndex = oi, comps = opt,
          favor = c.favor * (1 + (opts.perkChance or 0)),
          silver = (opts.filledSilver or {})[c.tier] or 0,
        }
      end
    end
  end
  return list
end

-- Marginal cost of one more fill of option `f`, given current consumption. Returns net cost, perFavor.
local function peekFill(f, items, crates)
  local cost = E.Peek(crates[f.crate.key], 1)
  if not cost then return nil end
  for _, comp in ipairs(f.comps) do
    local c = E.Peek(items[comp.id], comp.qty)
    if not c then return nil end
    cost = cost + c
  end
  local net = cost - f.silver
  return net, net / f.favor
end

local function bestFill(fills, items, crates)
  local best, bestNet, bestPF
  for _, f in ipairs(fills) do
    local net, pf = peekFill(f, items, crates)
    if pf and (not bestPF or pf < bestPF) then best, bestNet, bestPF = f, net, pf end
  end
  return best, bestNet, bestPF
end

local function bestEmpty(crates, receiptSilver)
  local bestKey, bestCost
  for key, book in pairs(crates) do
    local c = E.Peek(book, 1)
    if c and (not bestCost or c < bestCost) then bestKey, bestCost = key, c end
  end
  if not bestKey then return nil end
  return bestKey, bestCost, bestCost - (receiptSilver or 0)
end

local function fillLabel(f)
  local parts = {}
  for _, comp in ipairs(f.comps) do
    parts[#parts + 1] = comp.qty .. "x " .. (ns.GetItemName and ns.GetItemName(comp.id) or ns.ItemNames[comp.id] or comp.id)
  end
  return table.concat(parts, " + ")
end
E.FillLabel = fillLabel

-- Ranked list of favor routes at the top of the book (no consumption).
function E.RankRoutes(snapshot, opts, limit)
  local items, crates = buildBooks(snapshot)
  local out = {}
  for _, f in ipairs(fillOptions(opts)) do
    local net, pf = peekFill(f, items, crates)
    if pf then
      -- How many fills are available within 10% of this price?
      local n, guard = 0, pf * 1.10
      local ti, tc = buildBooks(snapshot)
      while n < 500 do
        local _, p = peekFill(f, ti, tc)
        if not p or p > guard then break end
        E.Take(tc[f.crate.key], 1)
        for _, comp in ipairs(f.comps) do E.Take(ti[comp.id], comp.qty) end
        n = n + 1
      end
      out[#out + 1] = { fill = f, net = net, perFavor = pf, depth = n }
    end
  end
  table.sort(out, function(a, b) return a.perFavor < b.perFavor end)
  if limit then for i = #out, limit + 1, -1 do out[i] = nil end end
  return out
end

function E.RankEmpties(snapshot, opts, limit)
  local out = {}
  for key, d in pairs(snapshot.crates or {}) do
    local b = E.NewBook(d.listings)
    local c = E.Peek(b, 1)
    if c then
      out[#out + 1] = { key = key, name = d.name or key, unit = c, net = c - (opts.receiptSilver or 0), available = b.total }
    end
  end
  table.sort(out, function(a, b) return a.unit < b.unit end)
  if limit then for i = #out, limit + 1, -1 do out[i] = nil end end
  return out
end

-- Full plan for `opts.turnins` receipt turn-ins.
function E.Plan(snapshot, opts)
  local items, crates = buildBooks(snapshot)
  local fills = fillOptions(opts)
  local R = opts.repPerTurnin or 50
  local RF = opts.receiptFavor or ns.RECEIPT_FAVOR or 15
  local plan = {
    turnins = 0, wanted = opts.turnins or 0, totalCost = 0,
    perTurnin = {}, fillsUsed = {}, emptiesUsed = {}, favorBought = 0,
  }

  -- Price of the very next turn-in, at the top of the book, ignoring favor already on hand.
  local f0, _, pf0 = bestFill(fills, items, crates)
  local ek0, _, en0 = bestEmpty(crates, opts.receiptSilver)
  if f0 and ek0 then
    plan.bestTurnin = en0 + RF * pf0
    plan.bestPerRep = plan.bestTurnin / R
    plan.bestFill, plan.bestFillPerFavor, plan.bestEmptyKey, plan.bestEmptyNet = f0, pf0, ek0, en0
  end
  if not plan.bestTurnin then
    plan.missing = (not f0) and "favor" or "empty"
    return plan
  end

  local bank = opts.favorOnHand or 0
  local fillCount, emptyCount = {}, {}
  for t = 1, plan.wanted do
    local turnCost, lastPF = 0, nil
    -- favor first, so a crate type is not used as an empty if it is the best fill
    local stalled = false
    while bank < RF do
      local f, net, pf = bestFill(fills, items, crates)
      if not f then stalled = true; break end
      E.Take(crates[f.crate.key], 1)
      for _, comp in ipairs(f.comps) do E.Take(items[comp.id], comp.qty) end
      bank = bank + f.favor
      plan.favorBought = plan.favorBought + f.favor
      turnCost = turnCost + net
      lastPF = pf
      fillCount[f] = (fillCount[f] or 0) + 1
    end
    if stalled then plan.stopReason = "Ran out of affordable favor listings"; break end
    local key, gross, net = bestEmpty(crates, opts.receiptSilver)
    if not key then plan.stopReason = "Ran out of empty crate listings"; break end
    E.Take(crates[key], 1)
    emptyCount[key] = (emptyCount[key] or 0) + 1
    bank = bank - RF
    turnCost = turnCost + net
    plan.turnins = t
    plan.totalCost = plan.totalCost + turnCost
    -- marginal price of this turn-in, smoothed: empty + 15 x current favor price
    if not lastPF then
      local _, _, pf = bestFill(fills, items, crates)
      lastPF = pf or plan.bestFillPerFavor
    end
    plan.perTurnin[t] = net + RF * lastPF
  end

  for f, n in pairs(fillCount) do
    plan.fillsUsed[#plan.fillsUsed + 1] = { fill = f, count = n }
  end
  table.sort(plan.fillsUsed, function(a, b) return a.count > b.count end)
  for k, n in pairs(emptyCount) do
    plan.emptiesUsed[#plan.emptiesUsed + 1] = { key = k, name = (snapshot.crates[k] or {}).name or k, count = n }
  end
  table.sort(plan.emptiesUsed, function(a, b) return a.count > b.count end)

  -- Shopping list straight from the consumed books.
  plan.shopping = {}
  for id, b in pairs(items) do
    if b.bought > 0 then
      plan.shopping[#plan.shopping + 1] = { kind = "item", id = id, qty = b.bought, spent = b.spent, maxUnit = b.maxUnit }
    end
  end
  for key, b in pairs(crates) do
    if b.bought > 0 then
      plan.shopping[#plan.shopping + 1] = { kind = "crate", key = key, name = (snapshot.crates[key] or {}).name or key, qty = b.bought, spent = b.spent, maxUnit = b.maxUnit }
    end
  end
  table.sort(plan.shopping, function(a, b) return a.spent > b.spent end)

  plan.rep = plan.turnins * R
  plan.avgPerRep = plan.rep > 0 and plan.totalCost / plan.rep or nil
  return plan
end

---------------------------------------------------------------------------
-- Verdict: BUY / BUY SOME / HOLD
---------------------------------------------------------------------------
function E.Verdict(plan, opts)
  local R = opts.repPerTurnin or 50
  local v = { reasons = {} }
  if not plan.bestTurnin then
    v.action = "HOLD"
    v.reasons[#v.reasons + 1] = plan.missing == "empty"
      and "No empty Waylaid Crates are listed right now."
      or "No crate + material combination is fully available on the AH right now."
    return v
  end

  local holdPct = opts.holdPct or 0.15
  local st = E.SeriesStats(opts.history and opts.history.route or {}, opts.history and opts.history.today or 0, 30)
  v.stats = st
  local ref = plan.bestPerRep
  if st.n >= 3 and st.median then
    v.medianPerRep = st.median
    v.vsMedian = plan.bestPerRep / st.median - 1
    ref = min(plan.bestPerRep, st.median)
  end

  if opts.capPerRep and plan.bestPerRep > opts.capPerRep then
    v.action = "HOLD"
    v.reasons[#v.reasons + 1] = ("Cheapest route costs %s per rep, above your cap of %s.")
      :format(E.Money(plan.bestPerRep), E.Money(opts.capPerRep))
    return v
  end
  if v.vsMedian and v.vsMedian > holdPct then
    v.action = "HOLD"
    v.reasons[#v.reasons + 1] = ("Prices are %d%% above their 30-day median (%s per rep vs %s). Wait for a dip.")
      :format(floor(v.vsMedian * 100 + 0.5), E.Money(plan.bestPerRep), E.Money(st.median))
    return v
  end

  -- How many turn-ins can be bought before the marginal price climbs past ref * (1 + holdPct)?
  local limit, good = ref * R * (1 + holdPct), 0
  for t = 1, plan.turnins do
    if plan.perTurnin[t] <= limit then good = t else break end
  end
  if opts.capPerRep then
    local capT = opts.capPerRep * R
    local g2 = 0
    for t = 1, plan.turnins do if plan.perTurnin[t] <= capT then g2 = t else break end end
    good = min(good, g2)
  end
  v.goodTurnins = good

  if good >= plan.wanted and plan.turnins >= plan.wanted then
    v.action = "BUY"
  elseif good > 0 then
    v.action = "BUY SOME"
    v.reasons[#v.reasons + 1] = ("Only about %d of %d turn-ins are available near the best price; buy those and hold the rest until listings refill.")
      :format(good, plan.wanted)
  else
    v.action = "HOLD"
    v.reasons[#v.reasons + 1] = "Listings are too thin to buy at a good price."
  end
  if plan.stopReason then v.reasons[#v.reasons + 1] = plan.stopReason .. "." end
  if v.vsMedian and v.vsMedian < -0.10 then
    v.reasons[#v.reasons + 1] = ("Good timing: %d%% below the 30-day median."):format(floor(-v.vsMedian * 100 + 0.5))
  elseif st.n < 3 then
    v.reasons[#v.reasons + 1] = ("Only %d day(s) of price history so far; the 30-day check switches on at 3 days. Scan daily.")
      :format(st.n)
  end
  return v
end

return E
