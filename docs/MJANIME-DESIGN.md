# MJAnime / MJReader visual family

Reference: https://github.com/MJSasha/mj-reader
Local source inspected: design-system/mjreader/MASTER.md, ReaderOptions.java and library-dark/library-light/settings/fold screenshots. MJReader itself was not modified or launched.

- Dark background #0C0E15, surfaces #191E29, foreground #F0F2EC, secondary #ABB5C5, accent #C7FF68.
- Light paper #FAFAF7, surfaces #EAEDE6, foreground #20251F, secondary #4D584E, accent #345A05.
- Roboto regular/medium matches native Android UI type; license bundled in assets/Roboto_LICENSE.txt.
- Rounded poster cards use the full image, clear titles, metadata and actual history progress.
- Focus is an immediate tonal state and visible outline, without scaling/glow or ripple waves.
- TV adaptation keeps the labeled side navigation and explicit player focus nodes.
- Player keeps transport icons and side settings; only appearance changes.
- Settings use grouped surfaces, inline remote-selectable options and shared themed controls.
- Display name/launcher/device labels are MJAnime. Upgrade package, protocol keys and signing identity stay stable.

Verification uses Flutter widget rendering and fake HTTP, video platform and native channels only. No device/emulator/live-account operations.


## Approved TV direction (1.7.0)

The user selected [this Cinema design board](design/cinema-reference.png). It is a visual reference, not an asset to render as app UI. Use real per-title API images, existing fonts and Material icons. Later explicit corrections take precedence over illustrative details in the board:

- Left rail: icons only, no visible text labels; preserve tooltip/accessibility names.
- Home hero: image to content edges, no rounded enclosing card or border. Heading at top, title/metadata/open action below.
- Darkening is local to the lower-left controls, not a full-height left scrim or a global/bottom-wide dimming of the image. Top and right remain bright.
- Horizontal carousels, no auto-rotation; one visible current focus.
- History follows last opening, not playback position; short OK opens detail.
- Episodes always have a permanent number plus caption.
- Search uses the actual OS input method; do not reproduce the illustrated key layout yourself.
- Existing filters, categories, related seasons, voices, frames and characters remain functional even when omitted from the illustrative board.
