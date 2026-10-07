-- Missing health on friendly plates, in place of Blizzard's health number
-- (what used to be the Deficit Plates addon). Health values are secret on
-- this client: they go straight into widget calls and are never compared or
-- used in math. Only widget methods are called on Blizzard's objects.

local _, ns = ...
local Deficit = {}
ns.Deficit = Deficit

local BLIZZARD_TEXTS = { "LeftText", "RightText", "TextString" }

-- Our text, in the spot and font of Blizzard's health number.
function Deficit.CreateText(bar)
    local text = bar:CreateFontString(nil, "OVERLAY")
    local source = bar.RightText or bar.TextString
    local font, size, flags
    if source then font, size, flags = source:GetFont() end
    text:SetFont(font or STANDARD_TEXT_FONT, size or 10, flags or "OUTLINE")
    text:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
    text:SetJustifyH("RIGHT")
    return text
end

-- show: Blizzard's health number hidden, ours shows missing health (-0 at
-- full). Otherwise Blizzard's number back and ours hidden. Alpha, not Hide(),
-- because Blizzard calls Show() on its texts.
function Deficit.Update(bar, text, unit, show)
    for _, key in ipairs(BLIZZARD_TEXTS) do
        if bar[key] then bar[key]:SetAlpha(show and 0 or 1) end
    end
    if not text then return end
    if not show then
        text:SetAlpha(0)
        return
    end
    text:SetText("-" .. AbbreviateNumbers(UnitHealthMissing(unit)))
    text:SetAlpha(1)
end

-- "shown", "hidden" or "?" for a widget, for /ddn-status. Guarded, because
-- this client can hide values from addons.
function Deficit.Visible(region)
    local ok, shown = pcall(function() return region:IsShown() and region:GetAlpha() > 0 end)
    if not ok then return "?" end
    return shown and "shown" or "hidden"
end
