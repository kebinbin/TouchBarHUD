# Changelog

## 0.5.2 — beta

- Add a concise native About panel with the app logo, version/build, description, and MIT copyright line.
- Add a simple display-and-Touch-Bar logo, packaged macOS app icon, and matching menu-bar template mark.
- Include a native icon-generation script and editable SVG logo.
- Document the free ad hoc signed beta and package it with a checksum and verified compatibility notes.

## 0.5.1 — release candidate

- Detect the laptop model once at startup and automatically select a sizing profile for known Intel Touch Bar MacBook Pros.
- Add a saved Laptop model override for 13-, 15-, and 16-inch models, with a clearly labeled fallback when detection fails.
- Scale the mirror using the model's display pixel density and live Touch Bar aspect ratio, preserving the original A1990 calibration across scaled resolutions.
- Preserve fine alignment corrections when changing profiles and include the model/sizing selection in diagnostics.
- Add regression checks for model identification, scaled geometry, shorter Touch Bars, profile persistence, menu state, and fallback handling.

## 0.5.0 — release candidate

- Split the single source file into native Objective-C app, backend, view, and geometry modules.
- Coalesce frame delivery to at most 30 updates per second; avoid image commits while hidden.
- Reuse one hide timer, throttle activity bookkeeping, and remove broad global system-event monitoring.
- Protect retained IOSurfaces from display-stream reuse and discard stale stream callbacks.
- Pause connections during sleep, inactive sessions, and loss of the built-in display; add explicit Retry.
- Make manual hiding work while pinned or hovered and respect disabled automatic reveal on the first frame.
- Gate mouse gestures on Accessibility permission, release active gestures during teardown, and ignore scroll momentum.
- Validate persisted numeric settings and keep alignment adjustments inside the screen.
- Add opt-in Start at login through ServiceManagement, quiet startup, shortcut diagnostics, and a duplicate-instance guard.
- Add optimized staged builds, regression checks, static analysis, CI, MIT license, and release documentation.

## 0.4.2

Initial source release: Touch Bar mirroring, mouse forwarding, scrolling, automatic visibility, and alignment controls.
