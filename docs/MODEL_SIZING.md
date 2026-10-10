# Model-based sizing

Automatic mode reads `hw.model` locally with `sysctlbyname`, once per process. Exact identifiers select a display family. A saved manual override takes priority; unknown identifiers use the original 15-inch profile and clearly report that fallback. The app does not use an external display's dimensions for this calculation.

| Sizing profile | Model identifiers | Native display width | Display density |
| --- | --- | --- | --- |
| 13-inch MacBook Pro | MacBookPro13,2; 14,2; 15,2; 15,4; 16,2; 16,3 | 2560 pixels | 227 pixels/inch |
| 15-inch MacBook Pro | MacBookPro13,3; 14,3; 15,1; 15,3 | 2880 pixels | 220 pixels/inch |
| 16-inch MacBook Pro | MacBookPro16,1; 16,4 | 3072 pixels | 226 pixels/inch |

Each abbreviated identifier above has the `MacBookPro` prefix. Non-Touch-Bar identifiers such as MacBookPro13,1 and MacBookPro14,1 are deliberately excluded. Recognizing a profile does not establish compatibility with an older model's unsupported macOS installation; the application's macOS 13 minimum still applies. Apple silicon compatibility has not been established by this Intel build.

Model identifiers come from [Apple's model identification guide](https://support.apple.com/en-us/108052). Display dimensions and densities come from Apple's specifications for [13-inch](https://support.apple.com/en-us/111925), [15-inch](https://support.apple.com/en-us/111949), and [16-inch](https://support.apple.com/en-us/111932) models.

## Calibration and assumptions

The original calibration treats a 2170 × 60 Touch Bar as having the same physical horizontal pixel scale as the A1990's 2880-pixel-wide, 220-PPI display. It is a project calibration, not an Apple-published physical Touch Bar measurement. The new estimate retains it and adjusts for each display's pixel density.

For the active Touch Bar reported by macOS, the fraction of display width is:

```text
(source width / source height) × 60 / native display width × (display PPI / 220)
```

Using aspect ratio makes 1085 × 30 logical points and 2170 × 60 pixels equivalent. It also adjusts the estimate when the live active Touch Bar is shorter; no separate hardcoded width is assumed for a simulator generation. Invalid or implausible source dimensions fall back to the original aspect ratio.

Multiply that fraction by the built-in screen's current width in AppKit points, then apply the saved width correction. This scales with macOS display settings while holding estimated physical size constant. The geometry code adds the frame padding, centers the strip plus the saved horizontal correction, and clamps it to the built-in screen. Small valid sizes are no longer forced to a 700-point minimum that could override the requested physical scale.

The assumption of a common Touch Bar physical pixel scale still needs validation on other hardware. This feature estimates width; it does not measure the user's viewing position or factory placement of the active strip. Horizontal placement, especially with a separate physical Escape key, may need manual correction. Existing correction values survive profile changes. Reset alignment clears only those corrections, leaving the model selection intact.

## Verification

Tests cover exact identification (including 13-inch MacBookPro16,2), manual overrides, unknown/non-Touch-Bar identifiers, invalid saved selections, logical/Retina equivalence, shorter live sources, scaling across display resolutions, screen bounds, input-coordinate independence, menu checkmarks, isolated preference persistence, and preservation/reset of fine corrections.

The 15-inch baseline is unchanged mathematically. Other model families have been verified with synthetic geometry and Apple specification data; their physical alignment still needs real-hardware checks before claiming exact calibration.
