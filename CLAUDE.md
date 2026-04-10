# Splitr — Project Rules

## App Info
- **Bundle ID:** `com.zimalogistics.splitr`
- **Platform:** iOS
- **GitHub repo:** github.com/zimalogistics/splitr
- **Pricing:** Free

## Publishing
- **Privacy policy Gist ID:** —
- **Privacy policy URL:** —
- **Pipeline:** `./publish.sh ios beta` (TestFlight) · `./publish.sh ios metadata` (store listing)
- **Build numbers:** YYYYMMDDHHmm timestamp format (auto-set by publish.sh)

## Build
```bash
xcodegen generate
xcodebuild -project Splitr.xcodeproj -scheme Splitr \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES SWIFT_STRICT_CONCURRENCY=complete
```

## Companion Projects
- **Android:** ../speed-converter-android/
- **Shared Assets:** ../speed-converter-shared/


## Reference Screenshots (for Android companion)
To capture iOS screenshots as design reference for the Android version:
```bash
~/Documents/random-projects/dev-projects/apps/auto-listing-apps/capture-reference.sh speed-converter
```
This auto-captures every 2 seconds while you navigate the app in the simulator, then auto-names via OCR. Screenshots save to `../speed-converter-shared/reference/screens/` with a generated `SCREEN_MAP.md`. Just run the command above, navigate every screen, and press Ctrl+C when done.

## Testing & Quality Gates
All quality gates in `~/.claude/standards/app-quality.md` apply. App-specific commands:
```bash
xcodegen generate && xcodebuild -project Splitr.xcodeproj -scheme Splitr -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build SWIFT_TREAT_WARNINGS_AS_ERRORS=YES SWIFT_STRICT_CONCURRENCY=complete
```
**The user must NEVER find a broken build.** Fix failures silently, re-run, do not hand off.


## In-App Purchase
- **Product ID:** `com.zimalogistics.splitr.tip.small / .medium / .large`
- **Type:** Consumable
- **Price:** $0.99 / $2.99 / $4.99
- **Display Name:** Tip Jar (Small Coffee / Large Coffee / You're a Legend)

## Stack
- **Min deployment:** iOS 17.0
