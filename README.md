Stupid Underdog Pick (iOS)

SwiftUI iOS app for StupidUnderdogPick using the existing Supabase backend.

Setup

- Install XcodeGen and generate the Xcode project:

```bash
brew install xcodegen
cd /Users/mjensen/Desktop/ios-stupid-underdog-pick && xcodegen generate
open "Stupid Underdog Pick.xcodeproj"
```

- Config is in `Config/AppConfig.xcconfig` and is already wired to Debug/Release.

- URL Scheme: `sup` with host `underdog` (callback like `sup://underdog/callback?code=...`).

- Supabase Swift SDK is declared in `project.yml`.

- All Supabase credentials are read from Info.plist via `.xcconfig` substitutions.

