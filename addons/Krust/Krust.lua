local addonName = ...
local frame = CreateFrame("Frame")
local lastLevel, lastXP, lastMaxXP
local function output(message)
    print("Krust: " .. message)
end
local function snapshot()
    lastLevel = UnitLevel("player")
    lastXP = UnitXP("player")
    lastMaxXP = UnitXPMax("player")
end
local function status()
    output("XP reports are " .. (KrustDB.enabled and "enabled" or "disabled") .. ". Usage: /krust enable | disable")
end
local function updateXP()
    local level = UnitLevel("player")
    local xp = UnitXP("player")
    local maxXP = UnitXPMax("player")
    if not lastLevel or not lastXP or not lastMaxXP then
        snapshot()
        return
    end
    local gained
    if level == lastLevel then
        gained = xp - lastXP
    elseif level == lastLevel + 1 and lastMaxXP > 0 then
        gained = lastMaxXP - lastXP + xp
    elseif level > lastLevel + 1 and KrustDB.enabled then
        output("XP gain crossed multiple levels and cannot be calculated.")
    end
    lastLevel, lastXP, lastMaxXP = level, xp, maxXP
    if not KrustDB.enabled or not gained or gained <= 0 then
        return
    end
    if maxXP <= 0 then
        output("Gained " .. gained .. " XP. No next level is available.")
        return
    end
    local percent = gained / maxXP * 100
    local remaining = math.ceil(math.max(0, maxXP - xp) / gained)
    output(string.format("Gained %d XP (%.2f%% of this level); %d similar gains until the next level.", gained, percent, remaining))
end
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_XP_UPDATE")
frame:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" and arg == addonName then
        if type(KrustDB) ~= "table" then
            KrustDB = {}
        end
        if type(KrustDB.enabled) ~= "boolean" then
            KrustDB.enabled = true
        end
        status()
    elseif event == "PLAYER_ENTERING_WORLD" then
        snapshot()
    elseif event == "PLAYER_XP_UPDATE" and arg == "player" and KrustDB then
        updateXP()
    end
end)
SLASH_KRUST1 = "/krust"
SlashCmdList.KRUST = function(message)
    local command = message:match("^%s*(.-)%s*$"):lower()
    if command == "enable" or command == "disable" then
        KrustDB.enabled = command == "enable"
        snapshot()
    end
    status()
end
