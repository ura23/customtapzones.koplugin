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
local _            = require("gettext")
local Screen       = Device.screen

local MENU_TOP_RATIO    = 1/8
local MENU_BOTTOM_RATIO = 1/8

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
    if action == "forward"  then return _("▶▶") end
    if action == "backward" then return _("◀◀") end
    return _("— —")
end

local function rowOverlapsMenuZone(row_index, total_rows)
    local cell_h = 1.0 / total_rows
    local row_top    = (row_index - 1) * cell_h
    local row_bottom = row_index * cell_h
    if row_bottom <= MENU_TOP_RATIO then return true end
    if row_top >= (1.0 - MENU_BOTTOM_RATIO) then return true end
    return false
end

local GridEditorWidget = InputContainer:extend{
    cols     = 3,
    rows     = 3,
    matrix   = nil,
    callback        = nil,
    close_callback  = nil,
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

function GridEditorWidget:_buildUI()
    local dialog_w = self.dialog_w
    
    -- Розраховуємо точну внутрішню ширину без урахування рамок і відступів FrameContainer
    local inner_w = dialog_w - (Size.padding.default * 2) - (Size.border.window * 2)

    local title_bar = TitleBar:new{
        title       = _("Tap to assign"),
        width       = inner_w,
        with_bottom_line = true,
        close_callback = function() self:_onClose() end,
    }

    local hint_font = Font:getFace("smallinfofont")
    -- local hint = TextBoxWidget:new{
        -- text  = _("Tap a cell to cycle: Forward → Back → Ignore"),
        -- face  = hint_font,
        -- width = inner_w,
    -- }
    -- local hint_container = CenterContainer:new{
        -- dimen = Geom:new{ w = inner_w, h = hint:getSize().h },
        -- hint,
    -- }

    local sep       = Size.line.medium
    -- Розподіляємо ширину кнопок суворо в межах inner_w
    local cell_w    = math.floor((inner_w - sep * (self.cols - 1)) / self.cols)

    local grid_group = VerticalGroup:new{ width = inner_w }

    for r = 1, self.rows do
        local row_group = HorizontalGroup:new{}
        local overlaps  = rowOverlapsMenuZone(r, self.rows)

        for c = 1, self.cols do
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
            if c < self.cols then
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
            text  = _("⚠ Overlaps with system zone."),
            face  = hint_font,
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
                { text = _("Cancel"), callback = function() self:_onClose() end },
                { text = _("Apply"),  callback = function() self:_onOK()    end },
            },
        },
        zero_sep = true,
    }

    local vgroup = VerticalGroup:new{ width = inner_w }
    table.insert(vgroup, title_bar)
    table.insert(vgroup, VerticalSpan:new{ height = Size.padding.small })
    -- table.insert(vgroup, hint_container)
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
    self[1] = nil
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
    if self.close_callback then self.close_callback() end
    UIManager:setDirty(nil, "ui")
end

function GridEditorWidget:_onClose()
    UIManager:close(self)
    if self.close_callback then self.close_callback() end
    UIManager:setDirty(nil, "ui")
end

return GridEditorWidget
