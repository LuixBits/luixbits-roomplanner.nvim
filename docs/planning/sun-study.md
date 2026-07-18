# Sun study

RoomPlan can draw an approximate top-down sunlight patch through exterior
windows without network access. Press `L`, run `:RoomPlanSunStudy`, or choose
**Sun study** from `?`.

The first use opens one structured setup popup. Enter:

- the exact clockwise angle from plan top to geographic north;
- latitude and longitude in decimal degrees;
- the fixed local UTC offset, such as `+02:00`.

This site information is saved with the plan and is one undoable change. The
ordinary interface continues to call walls top, right, bottom, and left so it
always matches the current view. The compact compass shows `P↑` (plan up) until
a site exists, then changes to a geographic indicator such as `N↗`. Rotating
the view changes those screen labels and the compass, never the saved site.

## Popup controls

The study popup keeps date, local time, minute step, and milliseconds per step
together. `h` and `l` move one step. `Space` starts playback, closes the popup,
and focuses the unobstructed canvas; `Ctrl-s` does the same without starting
the timer. **View current time on canvas** and **Play on canvas** expose both
choices explicitly. **Edit location and plan north** returns to the persisted
site popup.

While viewing the canvas, `h` and `l` step backward and forward, `Space` pauses
or resumes, `L` pauses and reopens the same settings, and `Esc` closes the
study. Playback advances only across the calculated daylight interval and
stops at sunset. These contextual controls do not add more setup keys.

The default step is 60 minutes and each frame remains visible for 700 ms. Both
are editable for the current popup and configurable for later studies:

```lua
require("roomplan").setup({
  sun_study = {
    window_defaults = {
      sill_height_mm = 900,
      head_height_mm = 2100,
    },
    playback = {
      step_minutes = 60,
      frame_duration_ms = 700,
    },
  },
})
```

Date, time, and playback position are transient. Cancelling the popup or
closing the canvas study stops its timer and removes the overlay; it does not
add history or dirty the plan.

## Window heights and display

The window edit popup can either store a sill/head pair for that window or use
the two configured defaults above. Choosing defaults does not copy redundant
keys into the plan. Explicit heights must be non-negative integer millimetres,
with the head above the sill.

Sun-facing exterior windows and walls receive a warm highlight. Each window
projects a yellow-to-orange floor patch into its owner room; room geometry
clips the patch, while furniture, walls, labels, selection, and diagnostics
remain readable above it. Shared interior windows do not cast an outdoor
patch. Details says whether a selected window uses explicit or assumed
heights.

## Accuracy

The solar position is a deterministic NOAA-style approximation calculated in
pure Lua. RoomPlan does not contact a geocoder, timezone service, weather
provider, or daylight-saving database. Enter the offset that applies to the
chosen date.

The overlay is clear-sky 2D exposure, not illuminance, glare, reflection,
thermal gain, or a construction simulation. It does not yet model wall
thickness, glazing, overhangs, furniture height shadows, or terrain.

← [Windows and outlets](windows-and-outlets.md) | [Documentation home](../README.md) | [Furniture](furniture.md) →
