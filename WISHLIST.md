# Splitr — Feature Wishlist

A running list of ideas to revisit. Not prioritised — just captured.

---

## Completed ✓

- **Per-field clear buttons** — tap × on any field to clear just that value
- **Share / copy result** — share sheet summary (e.g. "6.2 miles @ 8:30/mile = 52:42")
- **Saved entries** — save and restore up to 5 recent calculations
- **Distance shortcuts** — quick-tap buttons for 5K, 10K, Half Marathon, Marathon
- **Haptic feedback** — subtle tap when fields auto-populate
- **Named presets** — give a saved entry a custom name (e.g. "Marathon pace")

---

## Preset Improvements

- **Rename presets** — edit the name of a preset after it's been saved
- **Unlimited presets** — remove or raise the 5-entry cap (or paginate)
- **Reorder presets** — drag to reorder the saved list
- **iCloud sync** — presets survive phone upgrades and sync across iPhone/iPad

---

## Usability Improvements

- **Preferred units setting** — remember if the user thinks in miles vs km and emphasise that side of the UI
- **Onboarding hint** — first-time tip explaining you need to enter 2 values to derive the rest ✓
- **Home screen widget** — show last saved preset or most recent calculation
- **Swipe to clear a single field** — swipe gesture alternative to the × button

---

## Broader Audience

- **Swim mode** — add yards as a distance unit, per-100m / per-100yd pace
- **Cycling mode** — watts/power zone display (requires user weight input)
- **Apple Watch app** — view saved presets on wrist during a run

---

## Notes

- Watch app would need a separate Xcode target added to project.yml
- iCloud sync would use CloudKit or NSUbiquitousKeyValueStore (simpler)
- Preferred units could be a simple toggle in a Settings sheet
- Onboarding hint: show once on first launch, dismissible
