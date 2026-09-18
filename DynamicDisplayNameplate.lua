-- Enemy nameplates only while in combat. PLAYER_REGEN_DISABLED fires just
-- before combat lockdown starts and PLAYER_REGEN_ENABLED just after it ends,
-- so both writes happen while the client still accepts them.

local CVAR = "nameplateShowEnemies"
local TITLE = "Dynamic Display Nameplate"

local warned = false

local function SetEnemyPlates(show)
    if InCombatLockdown() then return end
    local set = (C_CVar and C_CVar.SetCVar) or SetCVar
    local ok, result = pcall(set, CVAR, show and "1" or "0")
    if ok and result ~= false then return end
    if warned then return end
    warned = true
    print(("|cffff8800%s:|r couldn't change enemy nameplates (%s)"):format(TITLE, tostring(result)))
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(_, event)
    SetEnemyPlates(event == "PLAYER_REGEN_DISABLED")
end)
