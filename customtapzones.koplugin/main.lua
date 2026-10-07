-- v1.1: Centralised tap-cell resolution (honours inverse_reading_order and UI
--       mirroring), persisted active state, corrected "copy scheme" menu labels,
--       inlined en/uk tr() localization, minor cleanups.
-- v1.0: Initial version.
local BD           = require("ui/bidi")
local ButtonDialog = require("ui/widget/buttondialog")
local DataStorage  = require("datastorage")
local Device       = require("device")
local GridEditor   = require("grideditor")
local InfoMessage  = require("ui/widget/infomessage")
local ZoneOverlay  = require("zoneoverlay")
local LuaSettings  = require("luasettings")
local UIManager    = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local Screen = Device.screen

if not Device:isTouchDevice() then
    return { disabled = true }
end

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

-- Orientation name for menu labels. `genitive` selects the Ukrainian form
-- used after "з" ("from"), e.g. "з книжкового режиму".
local function modeName(is_portrait, genitive)
    if is_portrait then
        return genitive and tr("portrait", "книжкового") or tr("portrait", "книжковий")
    end
    return genitive and tr("landscape", "альбомного") or tr("landscape", "альбомний")
end

-- Short orientation noun for parenthetical labels, e.g. "(portrait)".
local function modeNoun(is_portrait)
    return is_portrait and tr("portrait", "Портрет") or tr("landscape", "Альбом")
end

local DEFAULT_COLS = 3
local DEFAULT_ROWS = 3

local function buildDefaultMatrix(cols, rows)
    local m = {}
    for r = 1, rows do
        m[r] = {}
        for c = 1, cols do
            m[r][c] = (c == 1) and "backward" or "forward"
        end
    end
    return m
end

local CustomTapZones = WidgetContainer:extend{
    name         = "customtapzones",
    is_doc_only  = true,

    _portrait_cols   = DEFAULT_COLS,
    _portrait_rows   = DEFAULT_ROWS,
    _portrait_matrix = nil,

    _landscape_cols   = DEFAULT_COLS,
    _landscape_rows   = DEFAULT_ROWS,
    _landscape_matrix = nil,

    _active = true,
}

function CustomTapZones:_settingsPath()
    return DataStorage:getSettingsDir() .. "/customtapzones.lua"
end

function CustomTapZones:_loadSettings()
    local settings = LuaSettings:open(self:_settingsPath())

    self._portrait_cols   = settings:readSetting("portrait_cols")   or DEFAULT_COLS
    self._portrait_rows   = settings:readSetting("portrait_rows")   or DEFAULT_ROWS
    self._portrait_matrix = settings:readSetting("portrait_matrix")
        or buildDefaultMatrix(self._portrait_cols, self._portrait_rows)

    self._landscape_cols   = settings:readSetting("landscape_cols")   or DEFAULT_COLS
    self._landscape_rows   = settings:readSetting("landscape_rows")   or DEFAULT_ROWS
    self._landscape_matrix = settings:readSetting("landscape_matrix")
        or buildDefaultMatrix(self._landscape_cols, self._landscape_rows)

    -- Active unless explicitly disabled; keeps the plugin on by default.
    self._active = not settings:isFalse("active")
end

function CustomTapZones:_saveSettings()
    local settings = LuaSettings:open(self:_settingsPath())
    settings:saveSetting("portrait_cols",   self._portrait_cols)
    settings:saveSetting("portrait_rows",   self._portrait_rows)
    settings:saveSetting("portrait_matrix", self._portrait_matrix)

    settings:saveSetting("landscape_cols",   self._landscape_cols)
    settings:saveSetting("landscape_rows",   self._landscape_rows)
    settings:saveSetting("landscape_matrix", self._landscape_matrix)

    settings:saveSetting("active", self._active)
    settings:flush()
end

function CustomTapZones:_isPortrait()
    return Screen:getWidth() < Screen:getHeight()
end

--- Whether tap X is mirrored, matching ReaderView:getTapZones().
-- Mirrored UI and inverse (right-to-left / manga) reading order flip the axis.
function CustomTapZones:_isMirrored()
    local inverse = self.ui and self.ui.view and self.ui.view.inverse_reading_order
    return (inverse and true or false) ~= BD.mirroredUILayout()
end

--- Map a tap position to the logical grid cell and return its action.
function CustomTapZones:_resolveCell(pos, cur_w, cur_h)
    local is_port = cur_w < cur_h
    local cols   = is_port and self._portrait_cols   or self._landscape_cols
    local rows   = is_port and self._portrait_rows   or self._landscape_rows
    local matrix = is_port and self._portrait_matrix or self._landscape_matrix

    local c = math.floor((pos.x / cur_w) * cols) + 1
    local r = math.floor((pos.y / cur_h) * rows) + 1
    c = math.max(1, math.min(cols, c))
    r = math.max(1, math.min(rows, r))

    if self:_isMirrored() then
        c = cols - c + 1
    end
    return matrix[r] and matrix[r][c] or "ignore"
end

function CustomTapZones:init()
    self:_loadSettings()
    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end
end

function CustomTapZones:onReaderReady()
    self:_patchSetupTouchZones()
    if self._active then
        self:_applyZones()
    end
end

function CustomTapZones:_patchSetupTouchZones()
    if self.ui.paging and not self.ui.paging._ctz_patched then
        local orig_setup = self.ui.paging.setupTouchZones
        self.ui.paging.setupTouchZones = function(this, ...)
            orig_setup(this, ...)
            if self._active then
                self:_applyZones()
            end
        end
        self.ui.paging._ctz_patched = true
    end

    if self.ui.rolling and not self.ui.rolling._ctz_patched then
        local orig_setup = self.ui.rolling.setupTouchZones
        self.ui.rolling.setupTouchZones = function(this, ...)
            orig_setup(this, ...)
            if self._active then
                self:_applyZones()
            end
        end
        self.ui.rolling._ctz_patched = true
    end
end

function CustomTapZones:_applyZones()
    local zones = {
        {
            id = "tap_forward",
            ges = "tap",
            screen_zone = {
                ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1,
            },
            handler = function(ges)
                if G_reader_settings:nilOrFalse("page_turns_disable_tap") then
                    -- Read the live matrix so rotations are handled dynamically
                    local action = self:_resolveCell(ges.pos, Screen:getWidth(), Screen:getHeight())
                    local dir = (action == "forward") and 1 or (action == "backward") and -1 or nil

                    if dir then
                        if self.ui.paging then
                            self.ui.paging:onGotoViewRel(dir)
                        elseif self.ui.rolling then
                            self.ui.rolling:onGotoViewRel(dir)
                        end
                    end
                    return true
                end
            end,
        },
        {
            id = "tap_backward",
            ges = "tap",
            screen_zone = {
                ratio_x = 0, ratio_y = 0, ratio_w = 0, ratio_h = 0,
            },
            handler = function() return true end,
        }
    }

    self.ui:registerTouchZones(zones)
    self._active = true
end

function CustomTapZones:addToMainMenu(menu_items)
    local ok_ro, order = pcall(require, "ui/elements/reader_menu_order")
    if ok_ro and order and order.more_tools then
        local found = false
        for _, id in ipairs(order.more_tools) do
            if id == "custom_tap_zones" then found = true; break end
        end
        if not found then table.insert(order.more_tools, "custom_tap_zones") end
    end

    menu_items.custom_tap_zones = {
        text = tr("Custom tap zones", "Власні зони гортання"),
        -- sorting_hint замінено на явне додавання в reader_menu_order
        sub_item_table = {
            {
                text_func = function()
                    local is_port = self:_isPortrait()
                    local c = is_port and self._portrait_cols or self._landscape_cols
                    local r = is_port and self._portrait_rows or self._landscape_rows
                    return string.format(tr("Grid: %d \u{00D7} %d", "Сітка: %d \u{00D7} %d"), c, r)
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    self:_showGridSizeDialog(touchmenu_instance)
                    return true
                end,
            },
            {
                -- Copy the other orientation's scheme into the current one.
                text_func = function()
                    local from = not self:_isPortrait()
                    return string.format(tr("Copy scheme from %s mode", "Скопіювати схему з %s режиму"),
                                         modeName(from, true))
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    if self:_isPortrait() then
                        self._portrait_cols   = self._landscape_cols
                        self._portrait_rows   = self._landscape_rows
                        self._portrait_matrix = self:_copyMatrix(self._landscape_matrix,
                            self._landscape_cols, self._landscape_rows)
                    else
                        self._landscape_cols   = self._portrait_cols
                        self._landscape_rows   = self._portrait_rows
                        self._landscape_matrix = self:_copyMatrix(self._portrait_matrix,
                            self._portrait_cols, self._portrait_rows)
                    end

                    self:_saveSettings()

                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end

                    UIManager:show(InfoMessage:new{
                        text = tr("Settings copied", "Налаштування скопійовано"),
                    })
                    return true
                end,
            },
            {
                -- Copy the current orientation's scheme into the other one.
                text_func = function()
                    local to = not self:_isPortrait()
                    return string.format(tr("Copy scheme to %s mode", "Скопіювати схему в %s режим"),
                                         modeName(to, false))
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    if self:_isPortrait() then
                        self._landscape_cols   = self._portrait_cols
                        self._landscape_rows   = self._portrait_rows
                        self._landscape_matrix = self:_copyMatrix(self._portrait_matrix,
                            self._portrait_cols, self._portrait_rows)
                    else
                        self._portrait_cols   = self._landscape_cols
                        self._portrait_rows   = self._landscape_rows
                        self._portrait_matrix = self:_copyMatrix(self._landscape_matrix,
                            self._landscape_cols, self._landscape_rows)
                    end

                    self:_saveSettings()

                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end

                    UIManager:show(InfoMessage:new{
                        text = tr("Settings copied", "Налаштування скопійовано"),
                    })
                    return true
                end,
            },
            {
                text_func = function()
                    return string.format(tr("Edit tap zones (%s)…", "Редагувати тап-зони (%s)…"),
                                         modeNoun(self:_isPortrait()))
                end,
                callback = function()
                    self:_showGridEditor()
                    return true
                end,
            },
            {
                text_func = function()
                    return string.format(tr("Show grid (%s)", "Показати сітку (%s)"),
                                         modeNoun(self:_isPortrait()))
                end,
                callback = function()
                    self:_showOverlay()
                end,
                separator = true,
            },
            {
                text_func = function()
                    return self._active and tr("Plugin active", "Плагін активний")
                        or tr("Plugin inactive", "Плагін неактивний")
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    if self._active then
                        self._active = false
                        if self.ui.paging then
                            self.ui.paging:setupTouchZones()
                        elseif self.ui.rolling then
                            self.ui.rolling:setupTouchZones()
                        end
                    else
                        self:_applyZones()
                    end
                    self:_saveSettings()

                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                    return true
                end,
            },
        },
    }
end

function CustomTapZones:_copyMatrix(src_matrix, cols, rows)
    local new_m = {}
    for r = 1, rows do
        new_m[r] = {}
        for c = 1, cols do
            new_m[r][c] = src_matrix[r] and src_matrix[r][c] or "forward"
        end
    end
    return new_m
end

function CustomTapZones:_showGridEditor()
    local is_port = self:_isPortrait()
    local cols   = is_port and self._portrait_cols or self._landscape_cols
    local rows   = is_port and self._portrait_rows or self._landscape_rows
    local matrix = is_port and self._portrait_matrix or self._landscape_matrix

    local matrix_copy = {}
    for r = 1, rows do
        matrix_copy[r] = {}
        for c = 1, cols do
            matrix_copy[r][c] = matrix[r] and matrix[r][c] or "forward"
        end
    end

    local editor = GridEditor:new{
        cols   = cols,
        rows   = rows,
        matrix = matrix_copy,
        mirror = self:_isMirrored(),
        callback = function(new_matrix)
            if is_port then
                self._portrait_matrix = new_matrix
            else
                self._landscape_matrix = new_matrix
            end

            self:_saveSettings()
            -- TouchMenu is closed when the editor is opened, so it is not
            -- refreshed here to avoid ghost UI artifacts.
        end,
    }
    UIManager:show(editor)
end

function CustomTapZones:_showOverlay()
    local is_port = self:_isPortrait()
    local cols   = is_port and self._portrait_cols   or self._landscape_cols
    local rows   = is_port and self._portrait_rows   or self._landscape_rows
    local matrix = is_port and self._portrait_matrix or self._landscape_matrix

    UIManager:show(ZoneOverlay:new{
        cols   = cols,
        rows   = rows,
        matrix = matrix,
        mirror = self:_isMirrored(),
    })
end

function CustomTapZones:_resizeMatrix(old_matrix, new_cols, new_rows)
    local new_m = {}
    for r = 1, new_rows do
        new_m[r] = {}
        for c = 1, new_cols do
            if old_matrix and old_matrix[r] and old_matrix[r][c] then
                new_m[r][c] = old_matrix[r][c]
            else
                new_m[r][c] = (c == 1) and "backward" or "forward"
            end
        end
    end
    return new_m
end

function CustomTapZones:_showGridSizeDialog(touchmenu_instance)
    local is_port = self:_isPortrait()
    local dialog

    local function updateDialog()
        local c = is_port and self._portrait_cols or self._landscape_cols
        local r = is_port and self._portrait_rows or self._landscape_rows

        if dialog then
            UIManager:close(dialog)
        end

        dialog = ButtonDialog:new{
            buttons = {
                {
                    {
                        text = string.format(tr("Columns: %d", "Стовпців: %d"), c),
                        align = "left",
                        callback = function() end,
                    },
                    {
                        text = "\u{2795}",
                        enabled = c < 8,
                        callback = function()
                            if is_port then
                                self._portrait_cols = math.min(8, self._portrait_cols + 1)
                                self._portrait_matrix = self:_resizeMatrix(self._portrait_matrix,
                                    self._portrait_cols, self._portrait_rows)
                            else
                                self._landscape_cols = math.min(8, self._landscape_cols + 1)
                                self._landscape_matrix = self:_resizeMatrix(self._landscape_matrix,
                                    self._landscape_cols, self._landscape_rows)
                            end
                            self:_saveSettings()
                            updateDialog()
                        end,
                    },
                    {
                        text = "\u{2796}",
                        enabled = c > 2,
                        callback = function()
                            if is_port then
                                self._portrait_cols = math.max(2, self._portrait_cols - 1)
                                self._portrait_matrix = self:_resizeMatrix(self._portrait_matrix,
                                    self._portrait_cols, self._portrait_rows)
                            else
                                self._landscape_cols = math.max(2, self._landscape_cols - 1)
                                self._landscape_matrix = self:_resizeMatrix(self._landscape_matrix,
                                    self._landscape_cols, self._landscape_rows)
                            end
                            self:_saveSettings()
                            updateDialog()
                        end,
                    },
                },
                {
                    {
                        text = string.format(tr("Rows: %d", "Рядків: %d"), r),
                        align = "left",
                        callback = function() end,
                    },
                    {
                        text = "\u{2795}",
                        enabled = r < 8,
                        callback = function()
                            if is_port then
                                self._portrait_rows = math.min(8, self._portrait_rows + 1)
                                self._portrait_matrix = self:_resizeMatrix(self._portrait_matrix,
                                    self._portrait_cols, self._portrait_rows)
                            else
                                self._landscape_rows = math.min(8, self._landscape_rows + 1)
                                self._landscape_matrix = self:_resizeMatrix(self._landscape_matrix,
                                    self._landscape_cols, self._landscape_rows)
                            end
                            self:_saveSettings()
                            updateDialog()
                        end,
                    },
                    {
                        text = "\u{2796}",
                        enabled = r > 2,
                        callback = function()
                            if is_port then
                                self._portrait_rows = math.max(2, self._portrait_rows - 1)
                                self._portrait_matrix = self:_resizeMatrix(self._portrait_matrix,
                                    self._portrait_cols, self._portrait_rows)
                            else
                                self._landscape_rows = math.max(2, self._landscape_rows - 1)
                                self._landscape_matrix = self:_resizeMatrix(self._landscape_matrix,
                                    self._landscape_cols, self._landscape_rows)
                            end
                            self:_saveSettings()
                            updateDialog()
                        end,
                    },
                },
            }
        }
        UIManager:show(dialog)

        if touchmenu_instance then
            touchmenu_instance:updateItems()
        end
    end

    updateDialog()
end

return CustomTapZones
