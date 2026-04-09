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

## Testing & Quality Gates
Before handing ANY build to the user for Xcode testing, ALL of the following must pass:

1. **Build:** `xcodegen generate && xcodebuild` must complete with zero errors AND zero warnings
2. **Tests:** If test target exists, run it. If not, build is the minimum gate.
3. **Codex CLI review:** Run after every build — never skip, never ask
   ```bash
   codex exec --sandbox read-only --skip-git-repo-check --full-auto --config model_reasoning_effort="high" "Review for bugs and logic errors" 2>/dev/null
   ```
4. **Codex PR review:** Create PR, push, wait ~3 minutes for Codex review before merging
5. **Manual verification:** Run in Simulator, verify the feature works end-to-end

**The user must NEVER find a build error, warning, crash, or broken feature when they open Xcode.**
If any gate fails, fix it silently and re-run. Do not hand off a broken build.

## Stack
- **Min deployment:** iOS 17.0
