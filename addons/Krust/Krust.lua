local addonName = ...
local events = CreateFrame("Frame")
local display
local boxes = {}
local etaText, statusText
local lastLevel, lastXP, lastMaxXP
local rateStart, gains = nil, {}
local elapsed = 0
local pendingLevelUpdate = false

local BOX_COUNT = 40
local BOX_COLUMNS = 20
local BOX_SIZE = 8
local BOX_SPACING = 2
local RATE_WINDOW = 30 * 60
local MIN_RATE_TIME = 60

local function snapshot()
    lastLevel = UnitLevel("player")
    lastXP = UnitXP("player")
    lastMaxXP = UnitXPMax("player")
end

local function resetRate()
    rateStart = GetTime()
    gains = {}
end

local function updateGrid(xp, maxXP)
    local progress = 0
    if maxXP > 0 then
        progress = math.max(0, math.min(1, xp / maxXP)) * BOX_COUNT
    end
    for i = 1, BOX_COUNT do
        local fill = math.max(0, math.min(1, progress - (i - 1)))
        boxes[i]:SetWidth(math.max(0.001, BOX_SIZE * fill))
        if fill > 0 then
            boxes[i]:Show()
        else
            boxes[i]:Hide()
        end
    end
end

local function updateETA(xp, maxXP)
    if maxXP <= 0 then
        etaText:SetText("ETA: No next level")
        return
    end
    local now = GetTime()
    local cutoff = now - RATE_WINDOW
    local total = 0
    local recent = {}
    for _, gain in ipairs(gains) do
        if gain.time > cutoff then
            recent[#recent + 1] = gain
            total = total + gain.amount
        end
    end
    gains = recent
    local duration = math.min(RATE_WINDOW, now - rateStart)
    if duration < MIN_RATE_TIME then
        etaText:SetText("ETA: Estimating...")
    elseif total <= 0 then
        etaText:SetText("ETA: Unavailable")
    else
        local seconds = math.max(0, maxXP - xp) * duration / total
        if seconds < 60 then
            etaText:SetText("ETA: ~< 1m")
        else
            local minutes = math.ceil(seconds / 60)
            if minutes >= 60 then
                etaText:SetText(string.format("ETA: ~%dh %02dm", math.floor(minutes / 60), minutes % 60))
            else
                etaText:SetText(string.format("ETA: ~%dm", minutes))
            end
        end
    end
end

local function updateDisplay()
    local xp, maxXP = UnitXP("player"), UnitXPMax("player")
    updateGrid(xp, maxXP)
    updateETA(xp, maxXP)
end

local function validCoordinate(value)
    return type(value) == "number" and value == value and value > -100000 and value < 100000
end

local function createDisplay()
    display = CreateFrame("Frame", "KrustDisplay", UIParent)
    display:SetWidth(BOX_COLUMNS * (BOX_SIZE + BOX_SPACING) + 10)
    display:SetHeight(92)
    display:SetMovable(true)
    display:EnableMouse(true)
    display:RegisterForDrag("LeftButton")
    display:SetClampedToScreen(true)
    if validCoordinate(KrustDB.x) and validCoordinate(KrustDB.y) then
        display:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", KrustDB.x, KrustDB.y)
    else
        display:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    display:SetScript("OnDragStart", function(self) self:StartMoving() end)
    display:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local left, top = self:GetLeft(), self:GetTop()
        local parentLeft, parentBottom = UIParent:GetLeft(), UIParent:GetBottom()
        if left and top and parentLeft and parentBottom then
            KrustDB.x, KrustDB.y = left - parentLeft, top - parentBottom
        end
    end)

    local background = display:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(display)
    background:SetTexture(0, 0, 0, 0.75)
    for i = 1, BOX_COUNT do
        local column = (i - 1) % BOX_COLUMNS
        local row = math.floor((i - 1) / BOX_COLUMNS)
        local empty = display:CreateTexture(nil, "BORDER")
        empty:SetWidth(BOX_SIZE)
        empty:SetHeight(BOX_SIZE)
        empty:SetPoint("TOPLEFT", display, "TOPLEFT", 6 + column * (BOX_SIZE + BOX_SPACING), -6 - row * (BOX_SIZE + BOX_SPACING))
        empty:SetTexture(0.2, 0.2, 0.2, 1)
        local fill = display:CreateTexture(nil, "ARTWORK")
        fill:SetHeight(BOX_SIZE)
        fill:SetPoint("TOPLEFT", empty, "TOPLEFT", 0, 0)
        fill:SetTexture(0.55, 0.25, 0.85, 1)
        boxes[i] = fill
    end
    etaText = display:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    etaText:SetPoint("TOPLEFT", display, "TOPLEFT", 6, -29)
    statusText = display:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("TOPLEFT", display, "TOPLEFT", 6, -43)
    statusText:SetWidth(BOX_COLUMNS * (BOX_SIZE + BOX_SPACING) - 2)
    statusText:SetJustifyH("LEFT")
    statusText:SetText("Waiting for an XP gain.")
    if KrustDB.shown then display:Show() else display:Hide() end
end

local function updateXP()
    local level, xp, maxXP = UnitLevel("player"), UnitXP("player"), UnitXPMax("player")
    if not lastLevel or not lastXP or not lastMaxXP then
        snapshot()
        updateDisplay()
        return
    end
    local gained
    if level == lastLevel then
        gained = xp - lastXP
    elseif level == lastLevel + 1 and lastMaxXP > 0 then
        gained = lastMaxXP - lastXP + xp
    elseif level > lastLevel + 1 then
        statusText:SetText("XP gain crossed multiple levels and cannot be calculated.")
        resetRate()
    else
        resetRate()
    end
    lastLevel, lastXP, lastMaxXP = level, xp, maxXP
    if gained and gained < 0 then
        resetRate()
    elseif gained and gained > 0 then
        gains[#gains + 1] = { time = GetTime(), amount = gained }
        if maxXP <= 0 then
            statusText:SetText(string.format("Gained %d XP. No next level is available.", gained))
        else
            local remaining = math.ceil(math.max(0, maxXP - xp) / gained)
            statusText:SetText(string.format("Gained %d XP. %d more of these to go ...", gained, remaining))
        end
    end
    updateGrid(xp, maxXP)
    updateETA(xp, maxXP)
end

events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_XP_UPDATE")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" and arg == addonName then
        if type(KrustDB) ~= "table" then KrustDB = {} end
        if type(KrustDB.shown) ~= "boolean" then
            KrustDB.shown = type(KrustDB.enabled) ~= "boolean" or KrustDB.enabled
        end
        KrustDB.enabled = nil
        resetRate()
        createDisplay()
        updateDisplay()
    elseif event == "PLAYER_ENTERING_WORLD" and display then
        snapshot()
        resetRate()
        updateDisplay()
    elseif event == "PLAYER_XP_UPDATE" and arg == "player" and display then
        updateXP()
    elseif event == "PLAYER_LEVEL_UP" and display then
        pendingLevelUpdate = true
    end
end)
events:SetScript("OnUpdate", function(_, delta)
    if not display then return end
    if pendingLevelUpdate then
        pendingLevelUpdate = false
        updateXP()
    end
    elapsed = elapsed + delta
    if elapsed >= 1 then
        elapsed = 0
        updateETA(UnitXP("player"), UnitXPMax("player"))
    end
end)

SLASH_KRUST1 = "/krust"
SlashCmdList.KRUST = function(message)
    local command = message:match("^%s*(.-)%s*$"):lower()
    if command == "show" then
        KrustDB.shown = true
        display:Show()
        updateDisplay()
    elseif command == "hide" then
        KrustDB.shown = false
        display:Hide()
    else
        print("Krust: Display is " .. (KrustDB.shown and "shown" or "hidden") .. ". Usage: /krust show | hide")
    end
end
