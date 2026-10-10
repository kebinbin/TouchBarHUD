# Contributing

This is a native Objective-C/AppKit app built with ARC and a shell script. Xcode's Command Line Tools are sufficient; there are no third-party runtime dependencies or package installation steps.

## Source map

| File | Responsibility |
| --- | --- |
| `main.m` | Process entry point, duplicate-instance guard, framework-check command |
| `Sources/TBHAppDelegate.m` | Menu, preferences, HUD visibility, shortcut, login-item and workspace lifecycle |
| `Sources/TBHTouchBarController.m` | Private framework boundary, simulator, display stream, frame ownership and coalescing |
| `Sources/TBHSurfaceView.m` | Layer presentation, coordinate conversion, click/drag/scroll gestures |
| `Sources/TBHDeviceSizing.m` | Cached hardware-model lookup, sizing profiles, and physical-scale estimate |
| `Sources/TBHGeometry.m` | Preference validation and screen-bounded geometry |
| `Tests/Tests.m` | Regression checks using synthetic surfaces and input |

Keep private API signatures in the controller. Keep AppKit operations, controller lifecycle, and frame presentation on the main thread. Prefix project classes and constants with `TBH`; keep implementation-only properties in class extensions. Comments should explain constraints and ownership, rather than restate code.

The stream callback borrows an IOSurface. Each owner that keeps it after the callback retains it **and** increments its use count. The controller keeps only the newest frame. The view holds a separate reference while displaying it, and releases the previous reference after the Core Animation transaction completes. A frame burst schedules at most one pending delivery; its last frame is still delivered. Stream generations reject callbacks from stopped sessions. DFRFoundation stays loaded for the process lifetime because stream teardown can be asynchronous.

The app does not poll input or Accessibility permission and does not retry failed connections in a loop. Workspace events resume suspended connections; explicit Retry handles other failures. Do not add frame-by-frame window positioning or repeated timer construction. Hidden windows do not commit image updates.

The model lookup runs once per process. Sizing profiles are display families, not simulator generations. Keep input coordinates tied to the live Touch Bar size. See [MODEL_SIZING.md](docs/MODEL_SIZING.md) before changing profile data or the original calibration. Tests isolate preference writes in a temporary suite through the app delegate's `preferences` accessor.

## Logo assets

The simple mark represents a display mirroring a Touch Bar. `Resources/Logo.svg` is editable vector artwork; `Logo.png` is its 1024-pixel preview. The app ships `AppIcon.icns` and a monochrome `StatusIcon.pdf` that macOS tints for light/dark menu bars.

To change the geometry or colors consistently, edit `scripts/generate-icons.m`, then run `./scripts/generate-icons.sh`. Generated assets are committed so ordinary builds do not need to regenerate artwork. Rendering uses native Core Graphics and `iconutil`, without extra dependencies.

The README shows a real Touch Bar capture in `docs/TouchBar-screenshot.png`. Its padded frame is generated with `./scripts/frame-touchbar.sh`; keep the original capture unchanged when adjusting the frame.

The README animation in `docs/TouchBar-demo.gif` was captured from the HUD's live Touch Bar stream. It shows Chrome, a real brightness adjustment, and the return to Chrome. Its dark frame uses the same renderer as the still image. Review all frames for private content before replacing it; source frames are intentionally not stored in the repository.

## Checks

```sh
./build.sh
./scripts/test.sh
./scripts/analyze.sh
```

Compilation treats warnings as errors. The tests need a graphical macOS session and IOSurface access; CI validates the portable checks and builds the bundle. CI cannot validate a physical Touch Bar. Follow the manual matrix in [VERIFICATION.md](docs/VERIFICATION.md) before making compatibility claims.

For a bug report, include macOS version, MacBook model, app version, Diagnostics text, whether another Touch Bar mirror is running, and steps to reproduce. Avoid sharing screenshots or frame contents that reveal private app information.
