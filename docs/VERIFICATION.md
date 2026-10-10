# Verification — 0.5.2 beta

Checked on October 10, 2026, on a MacBookPro15,1 running macOS 15.7.9 (24G830), with Apple clang 17 and the Command Line Tools SDK. This is evidence for this machine and build, not a certification of every supported OS or MacBook model.

## 0.5.2 About and logo checks

- Optimized build, strict signature/plist verification, and Clang static analysis passed.
- 138 graphical regression checks and 107 headless checks passed with native IOSurface access.
- An isolated preview using the actual About action and packaged resources displayed the logo, app name, `Version 0.5.2 (12)`, one-line description, and MIT copyright. It did not start the Touch Bar backend or change preferences.
- The menu-bar PDF loaded as a 22 × 18 template image. The full-size logo and 32-pixel icon were visually checked; native `iconutil` generated the bundled icon set.

## 0.5.1 model-sizing checks

- Optimized build, strict signature/plist verification, and Clang static analysis passed.
- 138 graphical regression checks and 107 headless checks passed.
- New checks cover exact model classification, manual priority, unknown-model fallback, logical/Retina equivalence, shorter source geometry, physical scaling across display sizes, input-coordinate independence, saved menu selections in an isolated preferences suite, and preservation/reset of fine corrections.
- The native `hw.model` detector identified this MacBookPro15,1 as the 15-inch MacBook Pro profile. The cached lookup returned the same result, and the baseline width fraction remained 2170/2880 (about 0.753472).
- Physical alignment on 13- and 16-inch devices remains pending. See [MODEL_SIZING.md](MODEL_SIZING.md) for calibration assumptions and the supported identifier table.

The resource measurements below are from 0.5.0. They were not repeated for 0.5.1 or 0.5.2; the frame pipeline is unchanged, the system-info lookup runs once at startup, and the About panel is created on demand.

## 0.5.0 completed checks

- Optimized Intel build with ARC, `-Wall -Wextra -Werror`; bundle plist validation and strict ad-hoc signature verification.
- Clang static analysis with no diagnostics; shell syntax and source/documentation whitespace checks passed.
- Runtime verification refused a duplicate instance while the restored copy was running. Release packaging correctly rejected an ad-hoc signature before attempting notarization.
- 66 graphical regression checks passed; 47 portable checks passed in the explicit CI/headless mode.
- Checks cover finite preference values, screen-bounded geometry, coordinate conversion, denied-input gating, paired cancellation, latest-frame coalescing, stopped-generation rejection, balanced frame use counts, first-frame auto-reveal settings, manual hide while pinned/hovered, one reused hide timer, and bounded sleep/session/display recovery using a fake backend.
- All five required and three optional DFRFoundation symbols were present.
- A 45-second run of the actual app connected to the real Touch Bar, received 63 frames, delivered 38, reported a 1085 × 30 logical source, and registered the shortcut successfully. The HUD was hidden when the final snapshot was taken. The previously running 0.4.2 copy was restored after this check.

### Actual app resource sample

The sample began approximately three seconds after launch and lasted 30.1 seconds. Existing user preferences were used; no physical mouse gestures were sent and Accessibility was not authorized for this ad-hoc build.

| Metric | Observed |
| --- | --- |
| Average CPU, one logical core | 0.044% |
| Physical footprint, sampled min–max | 5.82–5.95 MiB |
| Physical footprint, sample start → end | 5.95 → 5.82 MiB |
| Interrupt wakeups | 0.47/second |
| Package-idle wakeups | 0.13/second |
| Process disk reads/writes in interval | 0 bytes / 0 bytes |

The older, long-running 0.4.2 process was also sampled read-only for 20 seconds: approximately 0.0013% CPU and 13.38–13.42 MiB physical footprint. These runs had different histories and activity, so they are not a controlled speedup comparison. Both idle samples were small.

The short real-stream run supports low startup/idle overhead on this Mac. It does not establish long-term leak freedom, battery impact, active mouse-control cost, or total WindowServer/GPU energy use.

### Synthetic rendering stress

The 45-second fixture produced 2,700 newly allocated 2170 × 60 surfaces at 60 Hz and delivered 1,252 visible layer updates (about 27.8/second). Its 35.1-second sample averaged 4.29% of one CPU core, including the fixture's generator and allocation work. Physical footprint rose from 3.68 to 3.91 MiB and plateaued for the last 11 samples; disk reads/writes were zero. The initial surface's use count returned to baseline after teardown.

This workload renders generated frames and does not verify private input forwarding, battery life, or long-term leak freedom. Its higher wakeup rate (87 interrupt wakeups/second) includes an intentional 60 Hz source timer plus delivery scheduling; the production app does not have that generator timer.

## Remaining checks for broader compatibility and a trusted binary

The free 0.5.2 beta is limited to the tested MacBookPro15,1 configuration. Its archive is ad hoc signed and not notarized, so downloaded copies require Apple's **Open Anyway** approval. The rows below remain open for wider compatibility claims and a future Developer ID release.

| Scenario | What to verify | Status |
| --- | --- | --- |
| macOS 13/14 and other claimed OS versions | Real Touch Bar stream, permissions, hotkey, controls | Not tested here |
| Other Touch Bar MacBook models | Source size, input coordinates, built-in alignment | Not tested here |
| Accessibility grant/revoke | Click, drag, cancellation, open slider, non-momentum scroll, system permission UI | Synthetic gating passed; physical input/UI testing pending |
| Login after installation in Applications | Opt-in registration, disable/unregister, approval-required state, quiet launch | Implementation reviewed; system registration not changed during testing |
| Real sleep/wake and user switching | No background stream while suspended; one reconnect on resume | Fake-backend regression checks passed; real cycles pending |
| Clamshell and external displays | HUD never moves to an external screen; reconnect on reopening | Geometry/lifecycle tests passed; real display cycles pending |
| Full screen, Spaces, menu tracking, Dock changes | Position, visibility, hover hold, explicit hide | Manual matrix pending |
| Long running resource test | 10-minute idle, continuous animation/input, repeated show/hide and reconnects | Short sample completed; extended energy/leak test pending |
| Conflicting mirror and shortcut | Useful failure/diagnostic state; no retry spin | Failure handling reviewed; explicit conflict test pending |
| Unsupported machine / missing framework | Clear diagnostics, no repeated work, usable Quit menu | Failure handling reviewed; unsupported hardware test pending |
| Developer ID build and downloaded archive | Hardened runtime, private backend/input, notarization, stapled ticket, Gatekeeper | Credentials and signed-build testing required |

CI builds and tests synthetic behavior. GitHub runners do not provide a physical Touch Bar, and headless mode deliberately skips window/lifecycle tests. Do not interpret CI success as completion of this manual matrix.
