# Lessons Learned

| Date | What went wrong | Rule to prevent it |
|------|-----------------|--------------------|
| 2026-03-21 | App icon had alpha channel → App Store rejection | Always export app icons as pure RGB PNG (no alpha). Use Pillow `Image.new("RGB", ...)` or strip alpha before archiving. |
| 2026-03-21 | Contents.json slot sizes didn't match actual file pixel dimensions | Verify each slot: e.g. 20pt @2x = 40px file. Run a dimension check script after icon generation. |
| 2026-03-21 | Unassigned child error in appiconset | Ensure backup/extra icon files are not inside the .appiconset folder — move them out before building. |

## Code Review Catches
| Date | Category | What was caught | Prevention rule |
|------|----------|----------------|-----------------|
| 2026-03-22 | bug | HintSheet swipe-dismiss didn't set `hasSeenHint = true` — hint re-appeared every launch | Always use `.sheet(isPresented:onDismiss:)` when the dismiss action must fire regardless of how the sheet is closed |
| 2026-03-22 | performance | `UIImpactFeedbackGenerator` allocated on every keystroke — cold instance fires unreliably | Store haptic generators as properties, call `prepare()` once in init |
| 2026-03-22 | bug | Chaining two `.sheet` presentations via `asyncAfter` in `onDismiss` is race-prone — second sheet can be dropped | Use a single sheet with internal paged `TabView` instead of sequential sheets |
| 2026-03-22 | accessibility | 12pt caption text in `textDim` (Color(white: 0.28)) on near-black background fails WCAG AA (~2.0:1) | Use `textSecondary` minimum for any readable caption; reserve `textDim` for purely decorative elements |
