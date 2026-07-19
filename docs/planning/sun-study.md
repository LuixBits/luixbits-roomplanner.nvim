# Sun study

RoomPlan can draw an approximate top-down sunlight patch through exterior
windows without network access. Press `S`, run `:RoomPlanSunStudy`, or choose
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

The study popup keeps a date preset, exact date, fixed UTC-offset reminder,
local time, minute step, and milliseconds per step together. The presets cover
today, both equinoxes, and both solstices without saving another plan field.
`j` and `k` retain normal form navigation, while `h` and `l` are the only keys
that change the sunlight time directly. `Space` starts whole-day playback,
closes the popup, and focuses the unobstructed canvas; `Ctrl-s` does the same
without starting the timer. **View current time on canvas**, **Play whole day
on canvas**, and **View daily exposure** expose all three choices explicitly.
**Edit location and plan north** returns to the persisted site popup.

While viewing the canvas, `h` and `l` step backward and forward in the chosen
day; `j` advances three months and `k` goes back three months at the same local
time. `Space` plays from sunrise, pauses or resumes an active run, and restarts
from sunrise after completion. `S` pauses and reopens the same settings, and
`Esc` closes the study. Playback advances only across the calculated daylight
interval. At sunset it stops and replaces the final instant with the daily
exposure overlay. These contextual controls do not add more setup keys.
Press `3` to keep them visible in the dynamic Details pane, or `?` to see the
same commands under **Current mode**. Details also shows date, sunrise/current/
sunset progress, exact azimuth/elevation, display type, legend, selected-room
or selected-window exposure span, and how to leave the mode.

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

Date, time, playback position, presets, and accumulated exposure are transient.
Cancelling the popup or closing the canvas study stops its timer and removes
the overlay; it does not add history, dirty the plan, or add schema keys.

## Window heights and display

The window edit popup can either store a sill/head pair for that window or use
the two configured defaults above. Choosing defaults does not copy redundant
keys into the plan. Explicit heights must be non-negative integer millimetres,
with the head above the sill.

Sun-facing exterior windows and walls receive a colorscheme-linked warning
highlight. Each window projects a floor patch using the theme's warning/error
spectrum into its owner room; room geometry clips the patch, while furniture,
walls, labels, selection, and diagnostics remain readable above it. Shared
interior windows do not cast an outdoor patch. Details says whether a selected
window uses explicit or assumed heights.

Near sunrise and sunset, instantaneous patches shift toward the theme's
stronger warning/error end; the main header includes a view-aware arrow showing
the incoming light direction. The daily exposure display samples the complete
daylight interval using the popup step size and accumulates direct-sun minutes
for every visible floor cell. Its fixed bands are `≤1h`, `≤2h`, `≤4h`, `≤6h`,
and `>6h`, so dates remain visually comparable instead of stretching every day
to its own maximum.

## Accuracy

The solar position is a deterministic NOAA-style approximation calculated in
pure Lua. RoomPlan does not contact a geocoder, timezone service, weather
provider, or daylight-saving database. Enter the offset that applies to the
chosen date. The study popup and Details deliberately repeat that fixed offset
to make seasonal comparisons with a daylight-saving change explicit.

The overlay is clear-sky 2D exposure, not illuminance, glare, reflection,
thermal gain, or a construction simulation. It does not yet model wall
thickness, glazing, overhangs, furniture height shadows, or terrain.

← [Windows and outlets](windows-and-outlets.md) | [Documentation home](../README.md) | [Furniture](furniture.md) →
