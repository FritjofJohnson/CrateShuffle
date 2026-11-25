-- CrateShuffle window: a Scan button, a status line and the scrollable report.

local _, ns = ...
local UI = {}
ns.UI = UI

local f, text, status, content

local function build()
  if f then return end
  local ok
  ok, f = pcall(CreateFrame, "Frame", "CrateShuffleFrame", UIParent, "BasicFrameTemplateWithInset")
  if not ok or not f then
    f = CreateFrame("Frame", "CrateShuffleFrame", UIParent, "BackdropTemplate")
    f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32, insets = { left = 8, right = 8, top = 8, bottom = 8 } })
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
  end
  f:SetSize(620, 520)
  f:SetPoint("CENTER")
  f:SetFrameStrata("HIGH")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetClampedToScreen(true)
  tinsert(UISpecialFrames, "CrateShuffleFrame")

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  title:SetPoint("TOP", 0, -6)
  title:SetText("CrateShuffle — Waylaid Crate rep planner")

  local scan = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  scan:SetSize(110, 24)
  scan:SetPoint("TOPLEFT", 14, -32)
  scan:SetText("Scan AH")
  scan:SetScript("OnClick", function() ns.Scan() end)

  status = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  status:SetPoint("LEFT", scan, "RIGHT", 10, 0)
  status:SetPoint("RIGHT", f, "RIGHT", -16, 0)
  status:SetJustifyH("LEFT")
  status:SetText("Open the auction house, then press Scan.")

  local sf = CreateFrame("ScrollFrame", "CrateShuffleScroll", f, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 14, -64)
  sf:SetPoint("BOTTOMRIGHT", -32, 14)
  content = CreateFrame("Frame", nil, sf)
  content:SetSize(560, 10)
  sf:SetScrollChild(content)

  text = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  text:SetPoint("TOPLEFT")
  text:SetWidth(560)
  text:SetJustifyH("LEFT")
  text:SetJustifyV("TOP")
  text:SetSpacing(2)
  f:Hide()

  if CrateShuffleDB and CrateShuffleDB.lastReport then
    UI.SetText("|cff888888(last scan)|r\n" .. CrateShuffleDB.lastReport)
  end
end

function UI.SetText(s)
  build()
  text:SetText(s or "")
  content:SetHeight(math.max(10, text:GetStringHeight() + 10))
end

function UI.SetStatus(s) build(); status:SetText(s or "") end
function UI.Show() build(); f:Show() end
function UI.Toggle() build(); if f:IsShown() then f:Hide() else f:Show() end end

-- A button on the Blizzard auction house window.
function UI.AttachToAH()
  if UI.ahButton or not AuctionHouseFrame then return end
  local b = CreateFrame("Button", nil, AuctionHouseFrame, "UIPanelButtonTemplate")
  b:SetSize(120, 22)
  b:SetPoint("TOPRIGHT", AuctionHouseFrame, "TOPRIGHT", -30, -1)
  b:SetText("Crate Shuffle")
  b:SetFrameLevel(AuctionHouseFrame:GetFrameLevel() + 10)
  b:SetScript("OnClick", function() UI.Show() end)
  UI.ahButton = b
end
