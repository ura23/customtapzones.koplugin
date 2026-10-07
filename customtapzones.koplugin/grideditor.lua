-- v1.1: Honour mirrored/inverse reading order when laying out the grid, derive
--       the system-zone warning from real DTAP zones, free the old widget tree
--       on rebuild, inlined en/uk tr() localization.
-- v1.0: Initial version.
local Blitbuffer   = require("ffi/blitbuffer")
local Button       = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device       = require("device")
local Font         = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom         = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InputContainer  = require("ui/widget/container/inputcontainer")
local MovableContainer = require("ui/widget/container/movablecontainer")
local Size         = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TitleBar     = require("ui/widget/titlebar")
local UIManager    = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan  = require("ui/widget/verticalspan")
local ButtonTable  = require("ui/widget/buttontable")
local Screen       = Device.screen

-- ── Localization (en/uk) ────────────────────────────────────────────
-- Language comes from G_reader_settings:readSetting("language"); anything
-- that is not "uk*" falls back to English.
local function is_uk_language()
    local lang = G_reader_settings and G_reader_settings:readSetting("language")
    return type(lang) == "string" and lang:sub(1, 2) == "uk"
end

local function tr(en, uk)
    if is_uk_language() then return uk or en end
    return en
end

-- Vertical bands that belong to the system (top menu, bottom minibar) and
-- therefore cannot receive custom tap actions: taps there are intercepted by
-- higher-priority reader zones.
local DTAP_ZONE_MENU    = G_defaults and G_defaults:readSetting("DTAP_ZONE_MENU")
    or { y = 0, h = 1 / 8 }
local DTAP_ZONE_MINIBAR = G_defaults and G_defaults:readSetting("DTAP_ZONE_MINIBAR")
    or { y = 12 / 13, h = 1 / 13 }
local MENU_TOP_RATIO    = DTAP_ZONE_MENU.y + DTAP_ZONE_MENU.h
local MENU_BOTTOM_RATIO = DTAP_ZONE_MINIBAR.y

local ACTION_CYCLE = { "forward", "backward", "ignore" }

local function nextAction(current)
    for i, v in ipairs(ACTION_CYCLE) do
        if v == current then
            return ACTION_CYCLE[(i % #ACTION_CYCLE) + 1]
        end
    end
    return "forward"
end

local function actionLabel(action)
    if action == "forward"  then return "▶▶" end
    if action == "backward" then return "◀◀" end
    return "— —"
end

local function rowOverlapsMenuZone(row_index, total_rows)
    local cell_h = 1.0 / total_rows
    local row_top    = (row_index - 1) * cell_h
    local row_bottom = row_index * cell_h
    if row_bottom <= MENU_TOP_RATIO then return true end
    if row_top >= MENU_BOTTOM_RATIO then return true end
    return false
end

local GridEditorWidget = InputContainer:extend{
    cols     = 3,
    rows     = 3,
    matrix   = nil,
    mirror   = false,   -- mirror column order (RTL / inverse reading order)
    callback        = nil,
}

function GridEditorWidget:init()
    self.edit_matrix = {}
    for r = 1, self.rows do
        self.edit_matrix[r] = {}
        for c = 1, self.cols do
            self.edit_matrix[r][c] = (self.matrix and self.matrix[r] and self.matrix[r][c])
                or "forward"
        end
    end

    self.screen_w = Screen:getWidth()
    self.screen_h = Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.screen_w, h = self.screen_h }

    local dialog_w = math.floor(math.min(self.screen_w, self.screen_h) * 0.92)
    self.dialog_w  = dialog_w

    self:_buildUI()
end

function GridEditorWidget:getSize()
    return self.dimen
end

--- Logical column for a display slot, accounting for mirroring.
function GridEditorWidget:_logicalCol(display_col)
    if self.mirror then
        return self.cols - display_col + 1
    end
    return display_col
end

function GridEditorWidget:_buildUI()
    local dialog_w = self.dialog_w

    -- Exact inner width without FrameContainer borders and padding
    local inner_w = dialog_w - (Size.padding.default * 2) - (Size.border.window * 2)

    local title_bar = TitleBar:new{
        title       = tr("Tap to assign", "Натиснути для призначення"),
        width       = inner_w,
        with_bottom_line = true,
        close_callback = function() self:_onClose() end,
    }

    local sep       = Size.line.medium
    -- Distribute the button width strictly inside inner_w
    local cell_w    = math.floor((inner_w - sep * (self.cols - 1)) / self.cols)

    local grid_group = VerticalGroup:new{ width = inner_w }

    for r = 1, self.rows do
        local row_group = HorizontalGroup:new{}
        local overlaps  = rowOverlapsMenuZone(r, self.rows)

        for display_c = 1, self.cols do
            local c      = self:_logicalCol(display_c)
            local action = self.edit_matrix[r][c]
            local label  = actionLabel(action)
            if overlaps then
                label = label .. " ⚠"
            end

            local btn = Button:new{
                text     = label,
                width    = cell_w,
                radius   = Size.radius.button,
                enabled  = true,
                callback = function()
                    self.edit_matrix[r][c] = nextAction(self.edit_matrix[r][c])
                    self:_rebuild()
                end,
            }
            table.insert(row_group, btn)
            if display_c < self.cols then
                table.insert(row_group, HorizontalSpan:new{ width = sep })
            end
        end

        table.insert(grid_group, row_group)
        if r < self.rows then
            table.insert(grid_group, VerticalSpan:new{ height = sep })
        end
    end

    local legend_widgets = VerticalGroup:new{}
    local has_overlap = false
    for r = 1, self.rows do
        if rowOverlapsMenuZone(r, self.rows) then
            has_overlap = true
            break
        end
    end
    if has_overlap then
        local warn = TextBoxWidget:new{
            text  = tr("⚠ Overlaps the system zone.", "⚠ Накладання на системну зону."),
            face  = Font:getFace("smallinfofont"),
            width = inner_w,
        }
        table.insert(legend_widgets, VerticalSpan:new{ height = Size.padding.small })
        table.insert(legend_widgets, CenterContainer:new{
            dimen = Geom:new{ w = inner_w, h = warn:getSize().h },
            warn,
        })
    end

    local button_table = ButtonTable:new{
        width   = inner_w,
        buttons = {
            {
                { text = tr("Cancel", "Скасувати"), callback = function() self:_onClose() end },
                { text = tr("Apply", "Застосувати"), callback = function() self:_onOK()    end },
            },
        },
        zero_sep = true,
    }

    local vgroup = VerticalGroup:new{ width = inner_w }
    table.insert(vgroup, title_bar)
    table.insert(vgroup, VerticalSpan:new{ height = Size.padding.small })
    table.insert(vgroup, VerticalSpan:new{ height = Size.padding.default })
    table.insert(vgroup, CenterContainer:new{
        dimen = Geom:new{ w = inner_w, h = grid_group:getSize().h },
        grid_group,
    })
    if has_overlap then
        for _, w in ipairs(legend_widgets) do
            table.insert(vgroup, w)
        end
    end
    table.insert(vgroup, VerticalSpan:new{ height = Size.padding.default })
    table.insert(vgroup, CenterContainer:new{
        dimen = Geom:new{ w = inner_w, h = button_table:getSize().h },
        button_table,
    })
    table.insert(vgroup, VerticalSpan:new{ height = Size.padding.small })

    local frame = FrameContainer:new{
        radius          = Size.radius.window,
        padding         = Size.padding.default,
        background      = Blitbuffer.COLOR_WHITE,
        bordersize      = Size.border.window,
        width           = dialog_w,
        vgroup,
    }

    local movable = MovableContainer:new{ frame }

    self[1] = CenterContainer:new{
        dimen = Geom:new{ w = self.screen_w, h = self.screen_h },
        movable,
    }
end

function GridEditorWidget:_rebuild()
    if self[1] then
        self[1]:free()
        self[1] = nil
    end
    self:_buildUI()
    UIManager:setDirty(self, "ui")
end

function GridEditorWidget:_onOK()
    if self.callback then
        local result = {}
        for r = 1, self.rows do
            result[r] = {}
            for c = 1, self.cols do
                result[r][c] = self.edit_matrix[r][c]
            end
        end
        self.callback(result)
    end
    UIManager:close(self)
    UIManager:setDirty(nil, "ui")
end

function GridEditorWidget:_onClose()
    UIManager:close(self)
    UIManager:setDirty(nil, "ui")
end

return GridEditorWidget
