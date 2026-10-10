# TouchBar HUD 0.4.2

TouchBar HUD mirrors the current macOS Touch Bar at the bottom of the built-in display. It is intended for a Touch Bar whose touch input still works but whose backlight or visible panel does not.

## Behavior

- Click or drag directly on the on-screen mirror to operate Touch Bar controls.
- With a Touch Bar slider open, place the pointer on the slider and use the mouse wheel or two-finger trackpad scroll to adjust it.
- The HUD remains visible while the mouse pointer is over it, so expanded and transient controls stay usable.
- Press `Option-Command-T` to show or hide the mirror.
- By default, the mirror appears when the Touch Bar display reports activity and hides after three seconds.
- Use the menu-bar icon to change the hide delay, keep the mirror visible, disable automatic reveal, reposition it, or view diagnostics.
- The HUD is restricted to the MacBook's built-in display and hides if that display is unavailable.
- Use the menu-bar **Opacity** submenu to choose 35%, 50%, 65%, 80%, 90%, or 100% opacity. The choice is saved.
- The **Hide after** submenu includes 1-second, 2-second, 3-second, 5-second, and 8-second delays.

## Physical alignment

The default size maps the 2170-pixel Touch Bar to the 2880-pixel-wide built-in display of the 15-inch 2018 MacBook Pro. This preserves the physical horizontal scale even when macOS uses a scaled display resolution.

If the left or right edges do not line up perfectly from your normal viewing angle, use **Physical alignment** in the menu-bar menu. Move the HUD in 5-point increments or change its width in 10-point increments. The correction is saved automatically.

## Important limitation

Apple does not publish the Touch Bar display or mouse-forwarding APIs. Automatic reveal is therefore best-effort: touching controls that visibly react should reveal the HUD, but an app-driven Touch Bar layout change can also reveal it. The keyboard shortcut remains the reliable fallback.

## Build

Run `./build.sh`. The built app is written to `build/TouchBar HUD.app` and is ad-hoc signed for local use.

Quit Touché before running TouchBar HUD so the two applications do not compete for the simulator display stream.

Mouse forwarding requires Accessibility permission. On first launch, allow TouchBar HUD in **System Settings > Privacy & Security > Accessibility**, then quit and reopen it. Replacing the locally signed app with a new build may require removing and re-adding it in that list.
