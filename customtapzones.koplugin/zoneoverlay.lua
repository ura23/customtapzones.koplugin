--[[
ZoneOverlayWidget — full-screen overlay that draws the active tap grid.

Shows:
  • Semi-transparent dark lines forming the N×M grid
  • A label in each cell: "▶ Fwd", "◀ Back", or "— —"

Dismissed immediately on any tap anywhere on the screen.
The tap is NOT forwarded further (overlay is modal until dismissed).
--]]

local Blitbuffer    = require("ffi/blitbuffer")
local Device        = require("device")
local Font          = require("ui/font")
local Geom          = require("ui/geometry")
local GestureRange  = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget    = require("ui/widget/textwidget")
local UIManager     = require("ui/uimanager")
local _             = require("gettext")
local Screen        = Device.screen

-- ── Visual constants ─────────────────────────────────────────────────────────

local LINE_WIDTH        = 2          -- grid line thickness in px
local LINE_COLOR        = Blitbuffer.COLOR_BLACK
local CELL_BG_FWD       = Blitbuffer.COLOR_LIGHT_GRAY   -- forward cells
local CELL_BG_BWD       = Blitbuffer.COLOR_GRAY          -- backward cells
local CELL_BG_IGN       = Blitbuffer.COLOR_WHITE         -- ignore cells
local LABEL_COLOR       = Blitbuffer.COLOR_BLACK
local LABEL_FONT        = Font:getFace("x_smallinfofont")

-- ── Widget ────────────────────────────────────────────────────────────────────

local ZoneOverlayWidget = InputContainer:extend{
    -- Required: grid description
    cols   = 3,
    rows   = 3,
    matrix = nil,   -- [row][col] = "forward"|"backward"|"ignore"

    -- Optional
    close_callback = nil,
}

function ZoneOverlayWidget:init()
    self.dimen = Geom:new{ x = 0, y = 0,
        w = Screen:getWidth(), h = Screen:getHeight() }

    -- Capture any tap anywhere to dismiss
    self.ges_events.TapDismiss = {
        GestureRange:new{
            ges   = "tap",
            range = self.dimen,
        }
    }
end

function ZoneOverlayWidget:getSize()
    return self.dimen
end

-- ── Painting ──────────────────────────────────────────────────────────────────

function ZoneOverlayWidget:paintTo(bb, x, y)
    local sw = self.dimen.w
    local sh = self.dimen.h
    local cols = self.cols
    local rows = self.rows

    -- Pixel size of one cell
    local cell_w = sw / cols
    local cell_h = sh / rows

    -- 1. Fill cell backgrounds
    for r = 1, rows do
        for c = 1, cols do
            local action = (self.matrix[r] and self.matrix[r][c]) or "forward"
            local bg = CELL_BG_IGN
            if action == "forward"  then bg = CELL_BG_FWD end
            if action == "backward" then bg = CELL_BG_BWD end

            local cx = x + math.floor((c - 1) * cell_w)
            local cy = y + math.floor((r - 1) * cell_h)
            local cw = math.floor(c * cell_w) - math.floor((c - 1) * cell_w)
            local ch = math.floor(r * cell_h) - math.floor((r - 1) * cell_h)
            bb:paintRect(cx, cy, cw, ch, bg)
        end
    end

    -- 2. Draw grid lines (vertical)
    for c = 1, cols - 1 do
        local lx = x + math.floor(c * cell_w) - math.floor(LINE_WIDTH / 2)
        bb:paintRect(lx, y, LINE_WIDTH, sh, LINE_COLOR)
    end
    -- Horizontal lines
    for r = 1, rows - 1 do
        local ly = y + math.floor(r * cell_h) - math.floor(LINE_WIDTH / 2)
        bb:paintRect(x, ly, sw, LINE_WIDTH, LINE_COLOR)
    end
    -- Outer border
    bb:paintRect(x,              y,               sw, LINE_WIDTH, LINE_COLOR)
    bb:paintRect(x,              y + sh - LINE_WIDTH, sw, LINE_WIDTH, LINE_COLOR)
    bb:paintRect(x,              y,               LINE_WIDTH, sh, LINE_COLOR)
    bb:paintRect(x + sw - LINE_WIDTH, y,           LINE_WIDTH, sh, LINE_COLOR)

    -- 3. Draw action label in each cell
    for r = 1, rows do
        for c = 1, cols do
            local action = (self.matrix[r] and self.matrix[r][c]) or "forward"
            local label
            if action == "forward"  then label = _("▶▶")  end
            if action == "backward" then label = _("◀◀") end
            if action == "ignore"   then label = _("— —")    end

            local tw = TextWidget:new{
                text       = label,
                face       = LABEL_FONT,
                fgcolor    = LABEL_COLOR,
            }
            local tsz = tw:getSize()

            local cx = x + math.floor((c - 1) * cell_w)
            local cy = y + math.floor((r - 1) * cell_h)
            local cw = math.floor(c * cell_w) - math.floor((c - 1) * cell_w)
            local ch = math.floor(r * cell_h) - math.floor((r - 1) * cell_h)

            -- Centre label in cell (clamp so it never goes outside)
            local tx = cx + math.max(0, math.floor((cw - tsz.w) / 2))
            local ty = cy + math.max(0, math.floor((ch - tsz.h) / 2))

            tw:paintTo(bb, tx, ty)
            tw:free()
        end
    end
end

-- ── Dismiss on tap ────────────────────────────────────────────────────────────

function ZoneOverlayWidget:onTapDismiss()
    UIManager:close(self)
    if self.close_callback then
        self.close_callback()
    end
    return true   -- consume the event; do NOT turn the page
end

return ZoneOverlayWidget
