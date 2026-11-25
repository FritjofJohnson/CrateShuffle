-- CrateShuffle scanner: reads live listings with the modern C_AuctionHouse API (WoW: Forever, interface 16001).
-- One browse query finds every "Waylaid Crate" listing, then one search per crate type and per material
-- reads the full order book (price + quantity), so costs reflect real depth.

local _, ns = ...
local S = {}
ns.Scanner = S

local AH = C_AuctionHouse
local QUERY_TIMEOUT = 4
local MAX_MORE = 8 -- "request more results" pages per item

local frame = CreateFrame("Frame")
local queue, current, running, onDone, onProgress = {}, nil, false, nil, nil
local snapshot, total, doneCount, token = nil, 0, 0, 0

local function sorts()
  return {
    { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false },
    { sortOrder = Enum.AuctionHouseSortOrder.Name, reverseSort = false },
  }
end

local function itemName(id)
  local n = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
  if not n and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
  return n
end

local function ready()
  if AH.IsThrottledMessageSystemReady then return AH.IsThrottledMessageSystemReady() end
  return true
end

local nextQuery -- forward

local function finish(task)
  if current ~= task then return end
  current = nil
  doneCount = doneCount + 1
  if onProgress then onProgress(doneCount, total) end
  C_Timer.After(0.05, nextQuery)
end

local function startTimeout(task)
  token = token + 1
  local my = token
  C_Timer.After(QUERY_TIMEOUT, function()
    if current == task and token == my then
      task.timedOut = true
      if task.onTimeout then task.onTimeout(task) end
      finish(task)
    end
  end)
end

-- Task: browse "Waylaid Crate" -> list of crate itemKeys
local function browseTask()
  local t = { kind = "browse", keys = {}, more = 0 }
  t.send = function()
    AH.SendBrowseQuery({ searchString = "Waylaid Crate", sorts = sorts(), filters = {}, itemClassFilters = {} })
  end
  t.read = function()
    local results = AH.GetBrowseResults() or {}
    for _, r in ipairs(results) do
      if r.itemKey and r.itemKey.itemID then t.keys[r.itemKey.itemID] = r end
    end
    if AH.HasFullBrowseResults and not AH.HasFullBrowseResults() and t.more < MAX_MORE then
      t.more = t.more + 1
      AH.RequestMoreBrowseResults()
      return
    end
    if t.resolving then return end
    t.resolving, t.tries = true, 0
    t.resolve()
  end
  -- Item names can arrive a moment after the browse results; retry a few times.
  t.resolve = function()
    if current ~= t then return end
    t.tries = t.tries + 1
    local pending = 0
    for id, r in pairs(t.keys) do
      if not t.queued then t.queued = {} end
      if not t.queued[id] then
        local name = itemName(id)
        if not name and AH.GetItemKeyInfo then
          local info = AH.GetItemKeyInfo(r.itemKey)
          name = info and info.itemName
        end
        if not name then
          pending = pending + 1
        else
          t.queued[id] = true
          if name:lower():find("waylaid crate", 1, true) then
            local key = ns.CrateKey(name)
            if key == ns.UNREAD_KEY or ns.CrateByKey[key] then
              table.insert(queue, S.SearchTask(id, "crate", key, name))
              total = total + 1
            else
              ns.Debug("Unknown crate name on AH: " .. name)
            end
          end
        end
      end
    end
    if pending > 0 and t.tries < 5 then
      C_Timer.After(0.6, t.resolve)
    else
      if pending > 0 then ns.Print(pending .. " crate listing(s) skipped: item names did not load. Scan again.") end
      finish(t)
    end
  end
  return t
end

-- Task: full order book for one itemID
function S.SearchTask(itemID, kind, crateKey, name)
  local t = { kind = kind, itemID = itemID, crateKey = crateKey, name = name, more = 0, listings = {} }
  t.itemKey = AH.MakeItemKey(itemID)
  t.send = function()
    AH.SendSearchQuery(t.itemKey, sorts(), true)
  end
  t.readCommodity = function()
    local n = AH.GetNumCommoditySearchResults(itemID) or 0
    wipe(t.listings)
    for i = 1, n do
      local r = AH.GetCommoditySearchResultInfo(itemID, i)
      if r and r.unitPrice and r.quantity then
        local q = r.quantity - (r.numOwnerItems or 0)
        if q > 0 then t.listings[#t.listings + 1] = { unit = r.unitPrice, qty = q } end
      end
    end
    if AH.HasFullCommoditySearchResults and not AH.HasFullCommoditySearchResults(itemID) and t.more < MAX_MORE then
      t.more = t.more + 1
      AH.RequestMoreCommoditySearchResults(itemID)
      return
    end
    t.store(); finish(t)
  end
  t.readItem = function()
    local n = AH.GetNumItemSearchResults(t.itemKey) or 0
    wipe(t.listings)
    for i = 1, n do
      local r = AH.GetItemSearchResultInfo(t.itemKey, i)
      if r and r.buyoutAmount and r.quantity and r.quantity > 0 and not r.containsOwnerItem and not r.containsAccountItem then
        t.listings[#t.listings + 1] = { unit = r.buyoutAmount / r.quantity, qty = r.quantity }
      end
    end
    if AH.HasFullItemSearchResults and not AH.HasFullItemSearchResults(t.itemKey) and t.more < MAX_MORE then
      t.more = t.more + 1
      AH.RequestMoreItemSearchResults(t.itemKey)
      return
    end
    t.store(); finish(t)
  end
  t.store = function()
    if kind == "crate" then
      local prev = snapshot.crates[crateKey]
      if prev then -- two item IDs mapping to the same key (unlikely): merge
        for _, x in ipairs(t.listings) do prev.listings[#prev.listings + 1] = x end
      else
        snapshot.crates[crateKey] = { name = name, itemID = itemID, listings = t.listings }
      end
    else
      snapshot.items[itemID] = { listings = t.listings }
    end
  end
  t.onTimeout = function() t.store() end -- no answer = no listings
  return t
end

function nextQuery()
  if not running then return end
  if current then return end
  local t = table.remove(queue, 1)
  if not t then
    running = false
    local cb = onDone; onDone = nil
    if cb then cb(snapshot) end
    return
  end
  if not ready() then
    table.insert(queue, 1, t)
    C_Timer.After(0.25, nextQuery)
    return
  end
  current = t
  startTimeout(t)
  local ok, err = pcall(t.send)
  if not ok then
    ns.Print("Query failed: " .. tostring(err))
    current = nil
    S.Abort()
  end
end

frame:SetScript("OnEvent", function(_, event, ...)
  if not current then return end
  if event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
    if current.kind == "browse" then current.read() end
  elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
    local id = ...
    if current.itemID and current.itemID == id then current.readCommodity() end
  elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
    local key = ...
    if current.itemID and type(key) == "table" and key.itemID == current.itemID then current.readItem() end
  elseif event == "AUCTION_HOUSE_CLOSED" then
    S.Abort("Auction house closed; scan stopped.")
  end
end)
for _, ev in ipairs({ "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
  "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED", "AUCTION_HOUSE_CLOSED" }) do
  pcall(frame.RegisterEvent, frame, ev)
end

function S.IsRunning() return running end

function S.Abort(msg)
  running, current, onDone = false, nil, nil
  wipe(queue)
  if msg then ns.Print(msg) end
  if ns.UI then ns.UI.SetStatus(msg or "Scan stopped.") end
end

-- Start a full scan. done(snapshot) is called when every query has answered or timed out.
function S.Start(done, progress)
  if running then ns.Print("A scan is already running."); return end
  if not (AH and AH.SendSearchQuery and AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
    ns.Print("Open the auction house first.")
    return
  end
  snapshot = { items = {}, crates = {}, time = time() }
  wipe(queue)
  queue[1] = browseTask()
  for _, id in ipairs(ns.AllMaterialIDs()) do
    queue[#queue + 1] = S.SearchTask(id, "item")
  end
  total, doneCount = #queue, 0
  running, onDone, onProgress = true, done, progress
  nextQuery()
end
