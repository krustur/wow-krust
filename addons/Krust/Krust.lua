local addonName = ...
local events = CreateFrame("Frame")
local display, questWindow, questScrollFrame, questContent
local boxes = {}
local boxBackgrounds = {}
local restedBackgrounds = {}
local questRows = {}
local questLines = {}
local etaText, remainingText, statusText
local lastLevel, lastXP, lastMaxXP
local rateStart, gains = nil, {}
local elapsed = 0
local pendingLevelUpdate = false
local updatingQuestWindow = false

local BOX_COUNT = 100
local BOX_COLUMNS = 25
local BOX_ROWS = 4
local BOX_SIZE = 8
local BOX_SPACING = 2
local GRID_X = 10
local GRID_Y = -24
local GRID_WIDTH = BOX_COLUMNS * BOX_SIZE + (BOX_COLUMNS - 1) * BOX_SPACING
local GRID_HEIGHT = BOX_ROWS * BOX_SIZE + (BOX_ROWS - 1) * BOX_SPACING
local DISPLAY_WIDTH = GRID_X * 2 + GRID_WIDTH
local DISPLAY_HEIGHT = 140
local RATE_WINDOW = 30 * 60
local MIN_RATE_TIME = 60

local DISPLAY_BG_COLOR = { 0.05, 0.08, 0.15, 0.9 }
local DISPLAY_BORDER_COLOR = { 0.22, 0.5, 0.85, 0.95 }
local EMPTY_BOX_COLOR = { 0.16, 0.19, 0.25, 1 }
local NON_RESTED_BOX_COLOR = { 0.09, 0.11, 0.15, 1 }
local RESTED_EMPTY_BOX_COLOR = { 0.16, 0.28, 0.4, 1 }
local ACTIVE_BOX_COLOR = { 0.55, 0.25, 0.85, 1 }
local RESTED_BOX_COLOR = { 0.48, 0.8, 1.0, 1 }
local RESTED_MARKER_COLOR = { 0.92, 0.98, 1.0, 0.95 }

local QUEST_WINDOW_WIDTH = 430
local QUEST_WINDOW_HEIGHT = 480
local QUEST_WINDOW_MIN_WIDTH = 240
local QUEST_WINDOW_MIN_HEIGHT = 120
local QUEST_WINDOW_MAX_WIDTH = 1600
local QUEST_WINDOW_MAX_HEIGHT = 1200
local QUEST_ROW_HEIGHT = 16
local OBJECTIVE_ROW_HEIGHT = 14
local QUEST_SCROLL_STEP = 24

local QUEST_COLOR_ORDER = { "gray", "green", "yellow", "orange", "red" }
local QUEST_GROUP_LABELS = {
    gray = "Gray Quests",
    green = "Green Quests",
    yellow = "Yellow Quests",
    orange = "Orange Quests",
    red = "Red Quests",
}
local QUEST_TEXT_COLORS = {
    gray = { 0.65, 0.65, 0.65, 1 },
    green = { 0.45, 0.9, 0.45, 1 },
    yellow = { 1.0, 0.88, 0.38, 1 },
    orange = { 1.0, 0.5, 0.25, 1 },
    red = { 0.95, 0.45, 0.45, 1 },
}
local QUEST_GROUP_COLORS = {
    gray = { 0.7, 0.75, 0.8, 1 },
    green = { 0.55, 0.95, 0.65, 1 },
    yellow = { 1.0, 0.95, 0.6, 1 },
    orange = { 1.0, 0.7, 0.45, 1 },
    red = { 1.0, 0.65, 0.65, 1 },
}
local QUEST_ZONE_COLOR = { 0.65, 0.84, 1.0, 1 }
local QUEST_OBJECTIVE_COLOR = { 0.85, 0.9, 1.0, 1 }

local restedMarker

local function setTextureColor(texture, color)
    texture:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
end

local function frameIsShown(frame)
    if not frame then
        return false
    end
    if frame.IsShown then
        return frame:IsShown()
    end
    return frame.shown
end

local function snapshot()
    lastLevel = UnitLevel("player")
    lastXP = UnitXP("player")
    lastMaxXP = UnitXPMax("player")
end

local function resetRate()
    rateStart = GetTime()
    gains = {}
end

local function addPanelChrome(frame, bgColor, borderColor)
    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(frame)
    background:SetTexture("Interface\\Buttons\\WHITE8X8")
    setTextureColor(background, bgColor)

    local top = frame:CreateTexture(nil, "BORDER")
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    top:SetHeight(1)
    top:SetTexture("Interface\\Buttons\\WHITE8X8")
    setTextureColor(top, borderColor)

    local bottom = frame:CreateTexture(nil, "BORDER")
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(1)
    bottom:SetTexture("Interface\\Buttons\\WHITE8X8")
    setTextureColor(bottom, borderColor)

    local left = frame:CreateTexture(nil, "BORDER")
    left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    left:SetWidth(1)
    left:SetTexture("Interface\\Buttons\\WHITE8X8")
    setTextureColor(left, borderColor)

    local right = frame:CreateTexture(nil, "BORDER")
    right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    right:SetWidth(1)
    right:SetTexture("Interface\\Buttons\\WHITE8X8")
    setTextureColor(right, borderColor)
end

local function updateRestedMarker(xp, maxXP, restedXP)
    if not restedMarker then
        return
    end

    if maxXP <= 0 or not restedXP or restedXP <= 0 then
        restedMarker:Hide()
        return
    end

    local markerXP = math.min(maxXP, xp + restedXP)
    if markerXP <= xp then
        restedMarker:Hide()
        return
    end

    local progress = math.max(0, math.min(BOX_COUNT, markerXP / maxXP * BOX_COUNT))
    local boxIndex = math.max(0, math.ceil(progress) - 1)
    local column = boxIndex % BOX_COLUMNS
    local row = math.floor(boxIndex / BOX_COLUMNS)
    local markerOffset = column * (BOX_SIZE + BOX_SPACING) + (progress - boxIndex) * BOX_SIZE
    restedMarker:ClearAllPoints()
    restedMarker:SetPoint("TOPLEFT", display, "TOPLEFT", GRID_X + markerOffset, GRID_Y - row * (BOX_SIZE + BOX_SPACING) + 1)
    restedMarker:Show()
end

local function updateGrid(xp, maxXP)
    local progress = 0
    if maxXP > 0 then
        progress = math.max(0, math.min(1, xp / maxXP)) * BOX_COUNT
    end
    local restedXP = GetXPExhaustion and GetXPExhaustion() or nil
    local isRested = maxXP > 0 and restedXP and restedXP > 0
    local fillColor = isRested and RESTED_BOX_COLOR or ACTIVE_BOX_COLOR
    local restedEnd = isRested and math.max(0, math.min(BOX_COUNT, (xp + restedXP) / maxXP * BOX_COUNT)) or 0

    for i = 1, BOX_COUNT do
        setTextureColor(boxBackgrounds[i], isRested and NON_RESTED_BOX_COLOR or EMPTY_BOX_COLOR)
        setTextureColor(boxes[i], fillColor)
        local fill = math.max(0, math.min(1, progress - (i - 1)))
        boxes[i]:SetWidth(math.max(0.001, BOX_SIZE * fill))
        if fill > 0 then
            boxes[i]:Show()
        else
            boxes[i]:Hide()
        end
        local restedFill = math.max(0, math.min(1, restedEnd - (i - 1)))
        restedBackgrounds[i]:SetWidth(math.max(0.001, BOX_SIZE * restedFill))
        if restedFill > 0 then
            restedBackgrounds[i]:Show()
        else
            restedBackgrounds[i]:Hide()
        end
    end

    updateRestedMarker(xp, maxXP, restedXP)
end

local function updateETA(xp, maxXP)
    if maxXP <= 0 then
        etaText:SetText("ETA: No next level")
        remainingText:SetText("Remaining XP: No next level")
        return
    end
    remainingText:SetText(string.format("Remaining XP: %d", math.max(0, maxXP - xp)))
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
            etaText:SetText("ETA: < 1m")
        else
            local minutes = math.ceil(seconds / 60)
            if minutes >= 60 then
                etaText:SetText(string.format("ETA: %dh %02dm", math.floor(minutes / 60), minutes % 60))
            else
                etaText:SetText(string.format("ETA: %dm", minutes))
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

local function getQuestColor(questLevel, questID)
    local playerLevel = (UnitEffectiveLevel and UnitEffectiveLevel("player")) or UnitLevel("player") or 0
    local level = tonumber(questLevel) or playerLevel
    local color
    if questID and C_PlayerInfo and C_PlayerInfo.GetContentDifficultyQuestForPlayer and GetDifficultyColor then
        local difficulty = C_PlayerInfo.GetContentDifficultyQuestForPlayer(questID)
        if difficulty ~= nil then color = GetDifficultyColor(difficulty) end
    end
    if not color and GetQuestDifficultyColor then
        color = GetQuestDifficultyColor(level)
    end
    if color and type(color.r) == "number" and type(color.g) == "number" and type(color.b) == "number" then
        local key
        if math.abs(color.r - color.g) < 0.05 and math.abs(color.g - color.b) < 0.05 then
            key = "gray"
        elseif color.g > color.r then
            key = "green"
        elseif color.g < 0.3 then
            key = "red"
        elseif color.g < 0.75 then
            key = "orange"
        else
            key = "yellow"
        end
        return key, { color.r, color.g, color.b, 1 }
    end

    local greenRange = GetQuestGreenRange and GetQuestGreenRange() or 5
    if level >= playerLevel + 5 then
        return "red", QUEST_TEXT_COLORS.red
    elseif level >= playerLevel + 3 then
        return "orange", QUEST_TEXT_COLORS.orange
    elseif level >= playerLevel - 4 then
        return "yellow", QUEST_TEXT_COLORS.yellow
    elseif level >= playerLevel - greenRange then
        return "green", QUEST_TEXT_COLORS.green
    end
    return "gray", QUEST_TEXT_COLORS.gray
end

local function questFlag(value)
    return value and value ~= 0
end

local function openQuestInQuestLog(questTitle, questLevel, fallbackIndex, questID)
    if questID and QuestMapFrame_OpenToQuestDetails then
        QuestMapFrame_OpenToQuestDetails(questID)
        return
    end
    if not questTitle and not fallbackIndex then
        return
    end

    local questLogShown = QuestLogFrame and QuestLogFrame.IsShown and QuestLogFrame:IsShown()
    if ToggleQuestLog and not questLogShown then
        ToggleQuestLog()
    end
    if ExpandQuestHeader then
        ExpandQuestHeader(0)
    end

    local questIndex = fallbackIndex
    if questTitle and GetNumQuestLogEntries and GetQuestLogTitle then
        for i = 1, GetNumQuestLogEntries() do
            local title, level, _, isHeader = GetQuestLogTitle(i)
            if not questFlag(isHeader) and title == questTitle and level == questLevel then
                questIndex = i
                break
            end
        end
    end

    if not questIndex then
        return
    end
    if SelectQuestLogEntry then
        SelectQuestLogEntry(questIndex)
    elseif QuestLog_SetSelection then
        QuestLog_SetSelection(questIndex)
    end
    if QuestLog_Update then
        QuestLog_Update()
    end
end

local function collectActiveQuests()
    local quests = {}
    local modern = C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo
    local getCount = modern and C_QuestLog.GetNumQuestLogEntries or GetNumQuestLogEntries
    if not getCount or (not modern and not GetQuestLogTitle) then
        return quests
    end

    local function getInfo(index)
        if modern then
            return C_QuestLog.GetInfo(index)
        end
        local title, level, _, isHeader, isCollapsed = GetQuestLogTitle(index)
        return { title = title, level = level, isHeader = isHeader, isCollapsed = isCollapsed }
    end

    local expand, collapse
    if modern and C_QuestLog.ExpandQuestHeader and C_QuestLog.CollapseQuestHeader then
        expand, collapse = C_QuestLog.ExpandQuestHeader, C_QuestLog.CollapseQuestHeader
    else
        expand, collapse = ExpandQuestHeader, CollapseQuestHeader
    end
    local expandedHeaders = {}
    local currentZone = "Unknown Zone"
    local i = 1
    while i <= (getCount() or 0) do
        local info = getInfo(i)
        if info and questFlag(info.isHeader) then
            currentZone = (info.title and info.title ~= "") and info.title or "Unknown Zone"
            if questFlag(info.isCollapsed) and expand and collapse then
                expand(i)
                expandedHeaders[#expandedHeaders + 1] = i
            end
        elseif info and info.title then
            local objectives = {}
            local function addObjective(text)
                if type(text) ~= "string" or not text:find("%S") then return end
                for _, existing in ipairs(objectives) do
                    if existing == text then return end
                end
                objectives[#objectives + 1] = text
            end
            if modern and GetQuestLogQuestText then
                local _, objectiveText = GetQuestLogQuestText(i)
                addObjective(objectiveText)
            end
            if modern and C_QuestLog.GetQuestObjectives and info.questID then
                for _, objective in ipairs(C_QuestLog.GetQuestObjectives(info.questID) or {}) do
                    addObjective(objective.text)
                end
            elseif not modern then
                local objectiveCount = GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(i) or 0
                for objectiveIndex = 1, objectiveCount do
                    local objectiveText = GetQuestLogLeaderBoard and GetQuestLogLeaderBoard(objectiveIndex, i)
                    addObjective(objectiveText)
                end
            end
            if modern and info.questID and C_QuestLog.GetNextWaypointText then
                addObjective(C_QuestLog.GetNextWaypointText(info.questID))
            end
            local colorKey, color = getQuestColor(info.level, info.questID)
            quests[#quests + 1] = {
                index = i,
                id = info.questID,
                zone = currentZone,
                level = info.level or 0,
                title = info.title,
                objectives = objectives,
                colorKey = colorKey,
                color = color,
            }
        end
        i = i + 1
    end

    for j = #expandedHeaders, 1, -1 do
        collapse(expandedHeaders[j])
    end

    return quests
end

local function buildQuestLines()
    local grouped = {
        gray = {},
        green = {},
        yellow = {},
        orange = {},
        red = {},
    }
    local lines = {}
    local quests = collectActiveQuests()

    for _, quest in ipairs(quests) do
        local colorKey = grouped[quest.colorKey] and quest.colorKey or "yellow"
        local zone = (quest.zone and quest.zone ~= "") and quest.zone or "Unknown Zone"
        if not grouped[colorKey][zone] then
            grouped[colorKey][zone] = {}
        end
        grouped[colorKey][zone][#grouped[colorKey][zone] + 1] = quest
    end

    for _, colorKey in ipairs(QUEST_COLOR_ORDER) do
        local zones = grouped[colorKey]
        local zoneNames = {}
        for zoneName in pairs(zones) do
            zoneNames[#zoneNames + 1] = zoneName
        end
        table.sort(zoneNames, function(a, b)
            return string.lower(a) < string.lower(b)
        end)

        if #zoneNames > 0 then
            lines[#lines + 1] = {
                type = "group",
                text = QUEST_GROUP_LABELS[colorKey],
                color = QUEST_GROUP_COLORS[colorKey],
                height = QUEST_ROW_HEIGHT + 2,
            }
            for _, zoneName in ipairs(zoneNames) do
                lines[#lines + 1] = {
                    type = "zone",
                    text = zoneName,
                    color = QUEST_ZONE_COLOR,
                    height = QUEST_ROW_HEIGHT,
                }

                local zoneQuests = zones[zoneName]
                table.sort(zoneQuests, function(a, b)
                    if a.level == b.level then
                        return string.lower(a.title) < string.lower(b.title)
                    end
                    return a.level < b.level
                end)

                for _, quest in ipairs(zoneQuests) do
                    lines[#lines + 1] = {
                        type = "quest",
                        text = string.format("[%d] %s", quest.level, quest.title),
                        color = quest.color,
                        height = QUEST_ROW_HEIGHT,
                        questIndex = quest.index,
                        questID = quest.id,
                        questLevel = quest.level,
                        questTitle = quest.title,
                    }

                    if #quest.objectives == 0 then
                        lines[#lines + 1] = {
                            type = "objective",
                            text = "- No objective progress details.",
                            color = QUEST_OBJECTIVE_COLOR,
                            height = OBJECTIVE_ROW_HEIGHT,
                            questIndex = quest.index,
                            questID = quest.id,
                            questLevel = quest.level,
                            questTitle = quest.title,
                        }
                    else
                        for _, objective in ipairs(quest.objectives) do
                            lines[#lines + 1] = {
                                type = "objective",
                                text = "- " .. objective,
                                color = QUEST_OBJECTIVE_COLOR,
                                height = OBJECTIVE_ROW_HEIGHT,
                                questIndex = quest.index,
                                questID = quest.id,
                                questLevel = quest.level,
                                questTitle = quest.title,
                            }
                        end
                    end
                end
            end
        end
    end

    if #lines == 0 then
        lines[#lines + 1] = {
            type = "empty",
            text = "No active quests.",
            color = QUEST_OBJECTIVE_COLOR,
            height = QUEST_ROW_HEIGHT,
        }
    end

    return lines
end

local function scrollQuestWindow(delta)
    if not questScrollFrame or not questScrollFrame.GetVerticalScroll then
        return
    end
    local maxScroll = questScrollFrame:GetVerticalScrollRange() or 0
    local nextScroll = (questScrollFrame:GetVerticalScroll() or 0) - delta * QUEST_SCROLL_STEP
    if nextScroll < 0 then
        nextScroll = 0
    elseif nextScroll > maxScroll then
        nextScroll = maxScroll
    end
    questScrollFrame:SetVerticalScroll(nextScroll)
end

local function clampQuestScroll()
    if questScrollFrame and questScrollFrame.GetVerticalScrollRange then
        local maxScroll = questScrollFrame:GetVerticalScrollRange() or 0
        if (questScrollFrame:GetVerticalScroll() or 0) > maxScroll then
            questScrollFrame:SetVerticalScroll(maxScroll)
        end
    end
end

local function ensureQuestRow(index)
    if questRows[index] then
        return questRows[index]
    end

    local row = CreateFrame("Button", nil, questContent)
    row:SetHeight(QUEST_ROW_HEIGHT)
    row:SetPoint("LEFT", questContent, "LEFT", 0, 0)
    row:SetPoint("RIGHT", questContent, "RIGHT", 0, 0)
    row.highlight = row:CreateTexture(nil, "BACKGROUND")
    row.highlight:SetAllPoints(row)
    row.highlight:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.highlight:SetVertexColor(0.3, 0.55, 0.9, 0.18)
    row.highlight:Hide()

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.text:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -1)
    row.text:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -1)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(true)

    row:SetScript("OnEnter", function(self)
        if self.questIndex then
            self.highlight:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        self.highlight:Hide()
    end)
    row:SetScript("OnClick", function(self)
        if self.questIndex then
            openQuestInQuestLog(self.questTitle, self.questLevel, self.questIndex, self.questID)
        end
    end)

    questRows[index] = row
    return row
end

local function layoutQuestLines()
    local yOffset = -4
    for i, line in ipairs(questLines) do
        local row = ensureQuestRow(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", questContent, "TOPLEFT", 0, yOffset)
        row:SetPoint("TOPRIGHT", questContent, "TOPRIGHT", 0, yOffset)
        row.text:ClearAllPoints()
        local textInset = 4
        if line.type == "zone" then
            textInset = 12
        elseif line.type == "quest" then
            textInset = 20
        elseif line.type == "objective" then
            textInset = 32
        end
        row.text:SetPoint("TOPLEFT", row, "TOPLEFT", textInset, -1)
        row.text:SetWidth(math.max(1, questContent:GetWidth() - textInset - 4))
        row.text:SetText(line.text)
        row.text:SetTextColor(line.color[1], line.color[2], line.color[3], line.color[4] or 1)
        local height = math.max(line.height, (row.text:GetStringHeight() or 0) + 2)
        row:SetHeight(height)
        row.questIndex = line.questIndex
        row.questID = line.questID
        row.questTitle = line.questTitle
        row.questLevel = line.questLevel
        row.highlight:Hide()
        row:Show()
        yOffset = yOffset - height
    end

    for i = #questLines + 1, #questRows do
        questRows[i]:Hide()
        questRows[i].questIndex = nil
        questRows[i].questID = nil
        questRows[i].questTitle = nil
        questRows[i].questLevel = nil
    end

    questContent:SetHeight(math.max(1, -yOffset + 6))
    clampQuestScroll()
end

local function updateQuestWindow()
    if not questWindow or not questContent or updatingQuestWindow then
        return
    end
    updatingQuestWindow = true
    questLines = buildQuestLines()
    layoutQuestLines()
    updatingQuestWindow = false
end

local function toggleQuestWindow()
    if not questWindow then
        return
    end
    if frameIsShown(questWindow) then
        questWindow:Hide()
        return
    end
    questWindow:Show()
    updateQuestWindow()
end

local function createQuestWindow()
    questWindow = CreateFrame("Frame", "KrustQuestListWindow", UIParent)
    table.insert(UISpecialFrames, "KrustQuestListWindow")
    local width = validCoordinate(KrustDB.questWidth) and KrustDB.questWidth or QUEST_WINDOW_WIDTH
    local height = validCoordinate(KrustDB.questHeight) and KrustDB.questHeight or QUEST_WINDOW_HEIGHT
    width = math.max(QUEST_WINDOW_MIN_WIDTH, math.min(QUEST_WINDOW_MAX_WIDTH, width))
    height = math.max(QUEST_WINDOW_MIN_HEIGHT, math.min(QUEST_WINDOW_MAX_HEIGHT, height))
    questWindow:SetWidth(width)
    questWindow:SetHeight(height)
    questWindow:SetMovable(true)
    questWindow:SetResizable(true)
    questWindow:SetResizeBounds(QUEST_WINDOW_MIN_WIDTH, QUEST_WINDOW_MIN_HEIGHT, QUEST_WINDOW_MAX_WIDTH, QUEST_WINDOW_MAX_HEIGHT)
    questWindow:EnableMouse(true)
    questWindow:RegisterForDrag("LeftButton")
    questWindow:SetClampedToScreen(true)
    if validCoordinate(KrustDB.questX) and validCoordinate(KrustDB.questY) then
        questWindow:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", KrustDB.questX, KrustDB.questY)
    else
        questWindow:SetPoint("TOPLEFT", display, "TOPRIGHT", 12, 0)
    end
    questWindow:SetScript("OnDragStart", function(self) self:StartMoving() end)
    questWindow:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local left, top = self:GetLeft(), self:GetTop()
        local parentLeft, parentBottom = UIParent:GetLeft(), UIParent:GetBottom()
        if left and top and parentLeft and parentBottom then
            KrustDB.questX, KrustDB.questY = left - parentLeft, top - parentBottom
        end
    end)
    addPanelChrome(questWindow, { 0.03, 0.06, 0.12, 0.93 }, DISPLAY_BORDER_COLOR)

    local title = questWindow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", questWindow, "TOPLEFT", 10, -8)
    title:SetText("Krust Quest List")

    local hint = questWindow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPRIGHT", questWindow, "TOPRIGHT", -82, -10)
    hint:SetText("Mouse wheel scroll")
    hint:SetTextColor(0.75, 0.82, 0.95)
    if width < 320 then hint:Hide() end

    local closeButton = CreateFrame("Button", nil, questWindow, "UIPanelButtonTemplate")
    closeButton:SetWidth(64)
    closeButton:SetHeight(18)
    closeButton:SetPoint("TOPRIGHT", questWindow, "TOPRIGHT", -8, -6)
    closeButton:SetText("Close")
    closeButton:SetScript("OnClick", function() questWindow:Hide() end)

    questScrollFrame = CreateFrame("ScrollFrame", nil, questWindow)
    questScrollFrame:SetPoint("TOPLEFT", questWindow, "TOPLEFT", 10, -30)
    questScrollFrame:SetPoint("BOTTOMRIGHT", questWindow, "BOTTOMRIGHT", -10, 18)
    questScrollFrame:EnableMouseWheel(true)
    questScrollFrame:SetScript("OnMouseWheel", function(_, delta)
        scrollQuestWindow(delta)
    end)
    questScrollFrame:SetScript("OnSizeChanged", function()
        clampQuestScroll()
    end)

    questContent = CreateFrame("Frame", nil, questScrollFrame)
    questContent:SetWidth(width - 34)
    questContent:SetHeight(1)
    questScrollFrame:SetScrollChild(questContent)
    questWindow:SetScript("OnSizeChanged", function(_, newWidth)
        questContent:SetWidth(math.max(1, newWidth - 34))
        if #questLines > 0 then layoutQuestLines() end
        if newWidth < 320 then hint:Hide() else hint:Show() end
    end)

    local resizeButton = CreateFrame("Button", nil, questWindow)
    resizeButton:SetWidth(16)
    resizeButton:SetHeight(16)
    resizeButton:SetPoint("BOTTOMRIGHT", questWindow, "BOTTOMRIGHT", -2, 2)
    resizeButton:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeButton:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeButton:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeButton:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then questWindow:StartSizing("BOTTOMRIGHT") end
    end)
    resizeButton:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            questWindow:StopMovingOrSizing()
            KrustDB.questWidth, KrustDB.questHeight = questWindow:GetWidth(), questWindow:GetHeight()
        end
    end)
    resizeButton:SetScript("OnHide", function()
        questWindow:StopMovingOrSizing()
        KrustDB.questWidth, KrustDB.questHeight = questWindow:GetWidth(), questWindow:GetHeight()
    end)
    questWindow:Hide()
end

local function createDisplay()
    display = CreateFrame("Frame", "KrustDisplay", UIParent)
    display:SetWidth(DISPLAY_WIDTH)
    display:SetHeight(DISPLAY_HEIGHT)
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

    addPanelChrome(display, DISPLAY_BG_COLOR, DISPLAY_BORDER_COLOR)

    local title = display:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", display, "TOPLEFT", GRID_X, -8)
    title:SetText("Krust XP")

    for i = 1, BOX_COUNT do
        local column = (i - 1) % BOX_COLUMNS
        local row = math.floor((i - 1) / BOX_COLUMNS)
        local empty = display:CreateTexture(nil, "BORDER")
        empty:SetWidth(BOX_SIZE)
        empty:SetHeight(BOX_SIZE)
        empty:SetPoint("TOPLEFT", display, "TOPLEFT", GRID_X + column * (BOX_SIZE + BOX_SPACING), GRID_Y - row * (BOX_SIZE + BOX_SPACING))
        empty:SetTexture("Interface\\Buttons\\WHITE8X8")
        setTextureColor(empty, EMPTY_BOX_COLOR)
        boxBackgrounds[i] = empty

        local fill = display:CreateTexture(nil, "ARTWORK")
        fill:SetHeight(BOX_SIZE)
        fill:SetPoint("TOPLEFT", empty, "TOPLEFT", 0, 0)
        fill:SetTexture("Interface\\Buttons\\WHITE8X8")
        setTextureColor(fill, ACTIVE_BOX_COLOR)
        boxes[i] = fill
    end

    restedMarker = display:CreateTexture(nil, "OVERLAY")
    restedMarker:SetWidth(2)
    restedMarker:SetHeight(BOX_SIZE + 2)
    restedMarker:SetTexture("Interface\\Buttons\\WHITE8X8")
    setTextureColor(restedMarker, RESTED_MARKER_COLOR)
    restedMarker:Hide()

    for i = 1, BOX_COUNT do
        local rested = display:CreateTexture(nil, "BORDER")
        rested:SetHeight(BOX_SIZE)
        rested:SetPoint("TOPLEFT", boxBackgrounds[i], "TOPLEFT", 0, 0)
        rested:SetTexture("Interface\\Buttons\\WHITE8X8")
        setTextureColor(rested, RESTED_EMPTY_BOX_COLOR)
        restedBackgrounds[i] = rested
    end

    etaText = display:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    etaText:SetPoint("TOPLEFT", display, "TOPLEFT", GRID_X, GRID_Y - GRID_HEIGHT - 8)
    etaText:SetTextColor(0.85, 0.95, 1.0)

    remainingText = display:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    remainingText:SetPoint("TOPLEFT", display, "TOPLEFT", GRID_X, GRID_Y - GRID_HEIGHT - 22)
    remainingText:SetTextColor(0.85, 0.9, 1.0)

    statusText = display:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("TOPLEFT", display, "TOPLEFT", GRID_X, GRID_Y - GRID_HEIGHT - 36)
    statusText:SetWidth(DISPLAY_WIDTH - GRID_X * 2)
    statusText:SetJustifyH("LEFT")
    statusText:SetTextColor(0.85, 0.9, 1.0)
    statusText:SetText("Waiting for an XP gain.")

    local questListButton = CreateFrame("Button", nil, display, "UIPanelButtonTemplate")
    questListButton:SetWidth(130)
    questListButton:SetHeight(20)
    questListButton:SetPoint("BOTTOMRIGHT", display, "BOTTOMRIGHT", -GRID_X, 8)
    questListButton:SetText("Krust Quest List")
    questListButton:SetScript("OnClick", toggleQuestWindow)

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
events:RegisterEvent("UPDATE_EXHAUSTION")
events:RegisterEvent("QUEST_LOG_UPDATE")
events:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" and arg == addonName then
        if type(KrustDB) ~= "table" then KrustDB = {} end
        if type(KrustDB.shown) ~= "boolean" then
            KrustDB.shown = type(KrustDB.enabled) ~= "boolean" or KrustDB.enabled
        end
        KrustDB.enabled = nil
        resetRate()
        createDisplay()
        createQuestWindow()
        updateDisplay()
    elseif event == "PLAYER_ENTERING_WORLD" and display then
        snapshot()
        resetRate()
        updateDisplay()
    elseif event == "PLAYER_XP_UPDATE" and arg == "player" and display then
        updateXP()
    elseif event == "PLAYER_LEVEL_UP" and display then
        pendingLevelUpdate = true
    elseif event == "UPDATE_EXHAUSTION" and display then
        updateGrid(UnitXP("player"), UnitXPMax("player"))
    elseif event == "QUEST_LOG_UPDATE" and frameIsShown(questWindow) then
        updateQuestWindow()
    end
end)
events:SetScript("OnUpdate", function(_, delta)
    if not display then return end
    if pendingLevelUpdate then
        pendingLevelUpdate = false
        updateXP()
        if frameIsShown(questWindow) then updateQuestWindow() end
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
    elseif command == "quests" then
        toggleQuestWindow()
    elseif command == "hide" then
        KrustDB.shown = false
        display:Hide()
    else
        print("Krust: Display is " .. (KrustDB.shown and "shown" or "hidden") .. ". Usage: /krust show | hide | quests")
    end
end
