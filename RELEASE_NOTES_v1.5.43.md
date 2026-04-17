# Gharka Bars v1.5.43

## Fixes

- Wrapped core `Bars` lifecycle and update calls with guarded error logging so one runtime failure is less likely to take down the addon.
- Improved target handling for tracked frames, including safer click-target resolution on target, watch target, and target-of-target bars.
- Refined visible-frame placement and refresh behavior to reduce stale position state and improve stability during active raid updates.

## New Features

- Increased hot position and hot data refresh frequency for snappier on-screen bar updates.
- Added a shared root container and smarter position-source rebuild flow for more reliable frame anchoring.
- Added cached distance and bloodlust refresh scheduling so visible and hidden bars can update more intelligently.
- Style and color sliders on the settings pages now apply live while dragging for faster tweaking.
