# LCFloatingMenu | Dribbble design reference library

> Curated 2026-10-24. Design direction, NOT licensed assets or production-ready iOS source. All linked shots remain the creators' work.
> Scope: iOS 27-inspired Liquid Glass, classic full-screen LiveContainer/SideStore guest switcher. This file is a long-lived source of truth for future UI revisions of LCFloatingMenu, not a request to rebuild the binary.

## Reference shortlist (real Dribbble shots)

| Priority | Shot / designer | URL | What to borrow | What not to copy |
| --- | --- | --- | --- | --- |
| A | Animated Liquid FAB — Farhad Ahmed | https://dribbble.com/shots/27214600-Animated-Liquid-FAB-Floating-Action-Button-UI | Continuous, small-to-large liquid expansion and retracting microinteraction from a single floating affordance | Oversized FAB, radial actions obscuring the Guest, expensive always-running animation |
| A | Liquid Glass UI · Tab Navigation — Rishi Raghu | https://dribbble.com/shots/26298309-Liquid-Glass-UI-Tab-Navigation | Convincing refraction around active controls; restrained edge light and dimensional glass | Huge black bar or thick opaque interior that covers content |
| A | Bottom Bar Navigation \| IOS — Sohaib Saleem | https://dribbble.com/shots/26297913-Bottom-Bar-Navigation-IOS | Compact 4-icon tool tray, selected-button shape/optical hierarchy, compare frosted vs liquid styles | Button labels in compact mode; system-bar-like permanent overlay |
| A | Settings - iOS Liquid Glass — Sithum Lahiru | https://dribbble.com/shots/26353024-Settings-iOS-Liquid-Glass | Material language of independent settings screen, carefully grouped options and soft visual hierarchy | Giant stacked acrylic cards and low-contrast form text |
| A | iOS 26-Inspired Liquid Glass Control Panel UI — Ajirioghene Jesuhovie | https://dribbble.com/shots/26669785-iOS-26-Inspired-Liquid-Glass-Control-Panel-UI | Modular controls, meaningful transparency, localized glass affordances even on bright backgrounds | Making every row a colorful glass button; excessive simultaneous effects |
| B | Liquid Glass Sidebar UI — Mari Chubina | https://dribbble.com/shots/26295742-Liquid-Glass-Sidebar-UI | Collapsed versus expanded states, soft depth and controlled side attachment | A desktop-sized vertical sidebar on a phone |
| B | Liquid Glass IOS Widgets — Yasir Ekinci | https://dribbble.com/shots/26997828-Liquid-Glass-IOS-Widgets-Exploration-of-Liquid-Interfaces | Optical layering, balanced translucent surfaces and gentle typography | Over-blurring contents and strong decorative reflections |
| B | Mobile App Setting Page Design for iOS Daily UI Challenge #007 — Rohan Mishra | https://dribbble.com/shots/5838972-Mobile-App-Setting-Page-Design-for-iOS-Daily-UI-Challenge-007 | Paired light and dark settings layouts with restrained hierarchy | Hardcoded theme colors derived from foreground Guest appearance |

## Project-specific UX principles (requirements to preserve)

1. **Collapsed:** a narrow edge microbead; low intrusion, side snap, optional 3-second slim fade. Large *invisible hit area* (target roughly 44pt) even if visual bead is 9-16pt wide; no Android-style oversized bubble.
2. **Expanded:** title-free and description-free. Header: real installed LC/SideStore icons/favorites. Middle: **only this region scrolls**. Footer: **fixed centered icon-only actions** (home/restart/settings/collapse). Adaptive panel height and configurable scale from 75 to 120 percent; never clip beyond the safe area.
3. **Modes:** normal = real icon + app name; compact = a **single narrow vertical column** of one app icon per row, each with a full-width, enlarged tap target and VoiceOver accessibility label. Don't replace icons with initial-letter tiles.
4. **Settings:** a **separate full-screen page** launched by tapping the gear; back navigation returns to Guest app switcher without relaunching Guest. DIY theme presets, placement, opacity, scale, compact mode, per-App settings, favorites management, logging. Use a **dedicated opaque settings UIWindow** that becomes key while settings are open; within it, a native **grouped UITableView home and UINavigationController** lead to four categories: Appearance, Interaction, App Management and Diagnostics. Restore the Guest's key window on exit. Never allow taps to leak into the Guest.
5. **Theme:** reflect **iOS system** light/dark mode, not the Guest app's forced style. Validate when Guest forces dark/light, when Reduce Transparency/Increase Contrast/Reduce Motion are on, and when the phone transitions light↔dark. Glass must remain legible on white, black, colorful, video and non-glass backgrounds: use an adaptive readability layer where needed.
6. **Motion:** a restrained spring transition (roughly 200-330 ms), single focal animation. Prefer a morph of the bead into the panel; avoid strong elastic overshoot, performance-heavy continuous blur/refraction, and custom rendering inside active games.
7. **Safety:** keep LiveContainer classic single-task switch. Avoid activating unsupported, locked, JIT-dependent or stale-signed guests directly. Do not inject SpringBoard. Preserve locally exportable rotating diagnostics.
8. **Do not equate a successful GitHub Actions compile with a validated iOS UI.** Compare on-device screenshots in both system appearances and across different Guest renderers.

## Suggested review order

P0: real app icons, non-intrusive bead, clean fixed-footer expanded menu, correct system-mode color.
P1: high-contrast full-screen settings and live DIY controls, compact single-column icon shelf, >=44pt actual hit targets at 75% scale, scale gesture correctness.
P2: fine optical refraction, restrained highlight movement, adaptive microanimations.
P3: optional advanced presets or animated interaction variants after device performance testing.

## Design acceptance checklist

- [ ] Bright white Guest, pure black Guest, video/Metal Guest and colorful Guest are visually readable.
- [ ] Switching Guest style does **not** change overlay's system light/dark appearance.
- [ ] Fixed footer stays stationary while scrolling 10+ apps.
- [ ] Compact mode has no unnecessary visible labels but retains accessibility labels.
- [ ] Panel at 75%, 100%, 120% retains tappable controls and fits safe area in landscape and portrait.
- [ ] Settings appears as a separate full-screen key window, divided into native UIKit category pages; there is no Guest touch-through and closing returns without terminating Guest.
- [ ] A single vertical app icon column is used in compact mode; never switch back to 4-column app grid.
- [ ] App icons are genuine LC icon caches/CFBundleIcons or neutral fallbacks.
- [ ] No non-essential explanatory title or menu-management row in expanded switcher.
- [ ] Each Guest can disable problematic tweak injection; logs remain exportable.

## Copyright / reuse

Use shots as inspiration and hyperlink to the original authors. Do not bundle, hotlink, redistribute or trace proprietary Dribbble shot assets, icons, illustrations, or Figma kits into the dylib without permission. Recreate a distinct, original UIKit design.
