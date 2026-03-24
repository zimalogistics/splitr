# Dependencies

## System Frameworks
- **SwiftUI** — Primary UI framework
- **WidgetKit** — Home screen widget extension (requires widget target)
- **StoreKit 2** — In-app purchases (consumable tip jar)

## Apple Services
- **NSUbiquitousKeyValueStore** — iCloud key-value sync for saved presets (requires iCloud entitlement: `com.apple.developer.ubiquity-kvstore-identifier`)
- **UserDefaults + App Group** — Shared storage between main app and widget extension (`group.com.zimalogistics.splitr`)

## Build Tools
- **xcodegen** — Generates Xcode project from `project.yml` (local dev tool, not a runtime dependency)

## External Packages
_None — no third-party dependencies._
