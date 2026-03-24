# UI/UX Reference

## Navigation Structure
- **Single screen app** — no tabs, no nav stack
- All functionality lives in one scrollable `ContentView`
- Sheets: Tip Jar, First-Launch Hint, Name/Rename Preset

## Screen Inventory

### Main Screen (ContentView)
- Toolbar: app title (left), ☕ tip jar button (right)
- **Speed section** — mph and km/h input cards
- **Pace section** — min/mile and min/km input cards
- **Distance section** — miles and km input cards + distance shortcut buttons (800m, 1.5K, 3K, 5K, 10K, Half, Marathon)
- **Time section** — HH:MM:SS input card
- Save button + Clear All button
- **Saved Presets section** — appears below when entries exist; cards with name, values, share/delete actions; drag-to-reorder

### Sheets
- **HintSheet** — shown once on first launch; 3-bullet how-to; dismissible
- **NamePresetSheet** — text field to name a new preset or rename an existing one
- **TipJarSheet** — three IAP buttons with product prices; loads async

## Design Decisions
- **Dark mode only** — fixed dark palette; not system-adaptive. Intentional brand choice.
- **Inputs and results share one scroll** — keeps the whole calculation visible without screen switching
- **No submit button** — recalculation fires on every keystroke; immediate feedback is the core UX
- **Anchor system (2-group max)** — prevents over-determination; oldest anchor dropped when a third group is touched. This avoids circular recalc.
- **Field state colors** — blue tint = user-entered (anchor), teal tint = calculated, default = empty. Gives visual feedback on which values are derived.
- **iPhone only** — layout is not adapted for iPad; restricted in project settings

## Known Issues
_None logged yet._
