-- SPDX-FileCopyrightText: 2026 Sayantan Santra <sayantan.santra689@gmail.com>
-- SPDX-License-Identifier: GPL-3.0
-- https://github.com/SinTan1729/koreader-patches

-- This widget draws a clean top bar in KOReader reader view
-- It shows the author name on left, book title on right,
-- and time in the middle. The time is automatically refreshed.
-- Customization is possible, but I don't intend to provide much support.
-- It's heavily inspired by https://github.com/joshuacant/KOReader.patches
-- Please use his patches instead, if you want more customization.

local UIManager = require("ui/uimanager")
local Blitbuffer = require("ffi/blitbuffer")
local TextWidget = require("ui/widget/textwidget")
local CenterContainer = require("ui/widget/container/centercontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local BD = require("ui/bidi")
local Size = require("ui/size")
local Geom = require("ui/geometry")
local Device = require("device")
local Font = require("ui/font")
local util = require("util")
local datetime = require("datetime")
local Screen = Device.screen
local _ = require("gettext")
local T = require("ffi/util").template
local ReaderView = require("apps/reader/modules/readerview")
local _ReaderView_paintTo_orig = ReaderView.paintTo
local header_settings = G_reader_settings:readSetting("footer")
local screen_width = Screen:getWidth()
local logger = require("logger")

local header_region = nil
local refresh_scheduled = false
local scheduled_view = nil
local function scheduleHeaderRefresh(view)
    if refresh_scheduled then
        return
    end

    refresh_scheduled = true
    scheduled_view = view

    logger.info("Clean Header: Scheduling header refresh.")
    UIManager:scheduleIn(60 - tonumber(os.date("%S")), function()
        logger.info("Clean Header: Firing header refresh.")
        if view
            and view.dialog
            and header_region then
            UIManager:setDirty(view.dialog, function()
                return "ui", header_region
            end)
        end
        refresh_scheduled = false
    end)
end

local function makeClockWidget(font_face, font_size, bold, color)
    local time = datetime.secondsToHour(
        os.time(),
        G_reader_settings:isTrue("twelve_hour_clock")
    ) or ""

    return TextWidget:new {
        text = time,
        face = Font:getFace(font_face, font_size),
        bold = bold,
        fgcolor = color,
        padding = 0,
    }
end

local function paintCenteredClock(bb, x, y, clock_widget, top_padding)
    clock_widget:paintTo(
        bb,
        x + screen_width / 2 - clock_widget:getSize().w / 2,
        y + top_padding
    )
end

local function getMaxClockWidth()
    local header_font_face = "ffont"                                 -- this is the same font the footer uses
    local header_font_size = header_settings.text_font_size or 14    -- Will use your footer setting if available
    local header_font_bold = header_settings.text_font_bold or false -- Will use your footer setting if available
    local widget = TextWidget:new {
        text = "88:88 PM",
        face = Font:getFace(header_font_face, header_font_size),
        bold = header_font_bold,
        padding = 0,
    }

    local width = widget:getSize().w
    widget:free()

    return width
end

ReaderView.paintTo = function(self, bb, x, y)
    _ReaderView_paintTo_orig(self, bb, x, y)
    if self.render_mode ~= nil then return end                       -- Show only for epub-likes and never on pdf-likes

    local header_font_face = "ffont"                                 -- this is the same font the footer uses
    -- header_font_face = "source/SourceSerif4-Regular.ttf" -- this is the serif font from Project: Title
    local header_font_size = header_settings.text_font_size or 14    -- Will use your footer setting if available
    local header_font_bold = header_settings.text_font_bold or false -- Will use your footer setting if available
    local header_font_color = Blitbuffer
        .COLOR_BLACK                                                 -- black is the default, but there's 15 other shades to try
    local header_top_padding = Size.padding
        .small                                                       -- replace small with default or large for more space at the top
    local header_use_book_margins = true                             -- Use same margins as book for header
    local header_margin = Size.padding
        .large                                                       -- Use this instead, if book margins is set to false
    local left_max_width_pct = 42                                    -- this % is how much space the left corner can use before "truncating..."
    local right_max_width_pct = 42                                   -- this % is how much space the right corner can use before "truncating..."

    -- Title and Author(s):
    local center_header_widget = makeClockWidget(
        header_font_face,
        header_font_size,
        header_font_bold,
        header_font_color
    )
    self._clock_width = self._clock_width or getMaxClockWidth()
    paintCenteredClock(
        bb,
        x,
        y,
        center_header_widget,
        header_top_padding
    )

    local book_title = ""
    local book_author = ""
    if self.ui.doc_props then
        book_title = self.ui.doc_props.display_title or ""
        book_author = self.ui.doc_props.authors or ""
        if book_author:find("\n") then -- Show first author if multiple authors
            book_author = T(_("%1 et al."), util.splitToArray(book_author, "\n")[1] .. ",")
        end
    end

    -- ===========================!!!!!!!!!!!!!!!=========================== -
    -- What you put here will show in the header:
    local left_corner_header = string.format("%s", book_author)
    local right_corner_header = string.format("%s", book_title)
    -- Look up "string.format" in Lua if you need help.
    -- ===========================!!!!!!!!!!!!!!!=========================== -

    -- don't change anything below this line
    local margins = 0
    local left_margin = header_margin
    local right_margin = header_margin
    if header_use_book_margins then -- Set width % based on R + L margins
        left_margin = self.document:getPageMargins().left or header_margin
        right_margin = self.document:getPageMargins().right or header_margin
    end
    margins = left_margin + right_margin
    local avail_width = screen_width - margins -- deduct margins from width
    local function getFittedText(text, max_width_pct)
        if text == nil or text == "" then
            return ""
        end
        local text_widget = TextWidget:new {
            text = text:gsub(" ", "\u{00A0}"), -- no-break-space
            max_width = avail_width * max_width_pct * (1 / 100),
            face = Font:getFace(header_font_face, header_font_size),
            bold = header_font_bold,
            padding = 0,
        }
        local fitted_text, add_ellipsis = text_widget:getFittedText()
        text_widget:free()
        if add_ellipsis then
            fitted_text = fitted_text .. "…"
        end
        return BD.auto(fitted_text)
    end
    left_corner_header = getFittedText(left_corner_header, left_max_width_pct)
    right_corner_header = getFittedText(right_corner_header, right_max_width_pct)
    local left_header_text = TextWidget:new {
        text = left_corner_header,
        face = Font:getFace(header_font_face, header_font_size),
        bold = header_font_bold,
        fgcolor = header_font_color,
        padding = 0,
    }
    local right_header_text = TextWidget:new {
        text = right_corner_header,
        face = Font:getFace(header_font_face, header_font_size),
        bold = header_font_bold,
        fgcolor = header_font_color,
        padding = 0,
    }
    local dynamic_space = (avail_width - left_header_text:getSize().w - right_header_text:getSize().w)
    local header = CenterContainer:new {
        dimen = Geom:new { w = screen_width, h = math.max(left_header_text:getSize().h, right_header_text:getSize().h, center_header_widget:getSize().h) + header_top_padding },
        VerticalGroup:new {
            VerticalSpan:new { width = header_top_padding },
            HorizontalGroup:new {
                left_header_text,
                HorizontalSpan:new { width = dynamic_space },
                right_header_text,
            }
        },
    }
    header:paintTo(bb, x, y)
    header_region = header.dimen

    if self ~= scheduled_view then
        logger.info("Clean Header: View has changed.")
        refresh_scheduled = false
    end
    scheduleHeaderRefresh(self)
end
