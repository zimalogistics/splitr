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
