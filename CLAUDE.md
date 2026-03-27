# Splitr — Project Notes

## Companion Project
Android: ../speed-converter-android/

## Build
- Uses xcodegen: run `./generate.sh` or `xcodegen generate` after adding source files
- Deployment target: iOS 17.0, iPhone only
- **Bundle ID:** com.zimalogistics.splitr
- Widget bundle: com.zimalogistics.splitr.widget
- App Group: group.com.zimalogistics.splitr

## Key Files
- `Splitr/ContentView.swift` — all calculator logic + main UI (~1,200 lines)
- `Splitr/TipJarView.swift` — StoreKit2 tip jar
- `SplitrWidget/SplitrWidget.swift` — WidgetKit extension
- `project.yml` — xcodegen config
