-- Colors and strengths shared by every part of the interface.
--
-- Keeping them in one place means the whole interface stays consistent,
-- and a change here, like making hover highlights stronger, applies
-- everywhere at once.

local style = {}

-- Main text and icons.
style.TEXT_COLOR = "#F2F2F2"

-- Secondary text, like the subtitle and the clock.
style.MUTED_TEXT_COLOR = "#B4B4B4"

-- The highlight behind a control while the pointer is over it. It has to
-- be fairly strong: in HDR, mpv draws the interface at normal "paper
-- white" brightness while the video can be much brighter, so a faint
-- highlight disappears over bright scenes (Phase 2, step 3).
style.HOVER_COLOR = "#FFFFFF"
style.HOVER_OPACITY = 0.45

-- The unplayed part of the seek bar.
style.TRACK_COLOR = "#FFFFFF"
style.TRACK_OPACITY = 0.3

-- Small labels that float over the video, like the seek bar's preview.
style.TOOLTIP_OPACITY = 0.85

-- The dark fades behind the top bar and bottom controls.
style.BACKGROUND_COLOR = "#000000"
style.BACKGROUND_OPACITY = 0.7

return style
