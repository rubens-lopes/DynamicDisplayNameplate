-- The options panel: one checkbox per switch in ns.OPTIONS, each with a
-- sentence or two on what it does. Listed under Options > AddOns. The list
-- scrolls when it doesn't fit.

local _, ns = ...

local panel = CreateFrame("Frame")
panel.name = ns.TITLE
panel:Hide()

-- Everything goes on content, inside a scroll frame. If the client lacks the
-- template, content is the panel itself and just doesn't scroll.
local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
local content = panel
if ok and scroll then
    scroll:SetPoint("TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -28, 4)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
else
    scroll = nil
end

local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText(ns.TITLE)

local intro = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
intro:SetPoint("RIGHT", content, "RIGHT", -16, 0)
intro:SetJustifyH("LEFT")
intro:SetText("Changes apply right away. Game settings the addon changes wait until you leave combat. "
    .. "Every switch also has a /ddn- command; type /ddn-help for the list.")

local boxes = {}
local helps = {}
local anchor = intro
for _, option in ipairs(ns.OPTIONS) do
    local box = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    box:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", anchor == intro and -2 or -26, -14)
    local label = box.Text or box:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:ClearAllPoints()
    label:SetPoint("LEFT", box, "RIGHT", 2, 0)
    label:SetFontObject("GameFontNormal")
    label:SetText(option.label)
    box:SetScript("OnClick", function(self) ns.Set(option.key, self:GetChecked() and true or false) end)

    local help = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 26, 0)
    help:SetPoint("RIGHT", content, "RIGHT", -16, 0)
    help:SetJustifyH("LEFT")
    help:SetText(option.help .. "\n|cff808080/ddn-" .. option.command .. " [on|off]|r")

    boxes[option.key] = box
    helps[#helps + 1] = { box = box, help = help }
    anchor = help
end

-- The scroll child needs a size: the scroll frame's width, and the height of
-- everything on it, which depends on how the text wraps at that width. Run
-- again on show, once the wrapped text has been laid out.
local function Resize()
    if not scroll then return end
    local width = scroll:GetWidth()
    if not width or width <= 0 then return end
    content:SetWidth(width)
    local height = 16 + title:GetStringHeight() + 8 + intro:GetStringHeight() + 16
    for _, row in ipairs(helps) do
        height = height + 14 + row.box:GetHeight() + row.help:GetStringHeight()
    end
    content:SetHeight(height)
end
if scroll then scroll:SetScript("OnSizeChanged", Resize) end

panel:SetScript("OnShow", function()
    for key, box in pairs(boxes) do box:SetChecked(ns.Get(key) and true or false) end
    Resize()
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
