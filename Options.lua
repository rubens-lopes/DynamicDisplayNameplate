-- The options panel: one checkbox per switch in ns.OPTIONS, each with a
-- sentence or two on what it does. Listed under Options > AddOns.

local _, ns = ...

local panel = CreateFrame("Frame")
panel.name = ns.TITLE
panel:Hide()

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText(ns.TITLE)

local intro = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
intro:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
intro:SetJustifyH("LEFT")
intro:SetText("Changes apply right away. Game settings the addon changes wait until you leave combat. "
    .. "Every switch also has a /ddn- command; type /ddn-help for the list.")

local boxes = {}
local anchor = intro
for _, option in ipairs(ns.OPTIONS) do
    local box = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    box:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", anchor == intro and -2 or -26, -14)
    local label = box.Text or box:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:ClearAllPoints()
    label:SetPoint("LEFT", box, "RIGHT", 2, 0)
    label:SetFontObject("GameFontNormal")
    label:SetText(option.label)
    box:SetScript("OnClick", function(self) ns.Set(option.key, self:GetChecked() and true or false) end)

    local help = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 26, 0)
    help:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    help:SetJustifyH("LEFT")
    help:SetText(option.help .. "\n|cff808080/ddn-" .. option.command .. " [on|off]|r")

    boxes[option.key] = box
    anchor = help
end

panel:SetScript("OnShow", function()
    for key, box in pairs(boxes) do box:SetChecked(ns.Get(key) and true or false) end
end)

if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, ns.TITLE)
    Settings.RegisterAddOnCategory(category)
    ns.OpenOptions = function() Settings.OpenToCategory(category:GetID()) end
elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
    ns.OpenOptions = function()
        -- Called twice: the first call only opens the frame on older clients.
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end
