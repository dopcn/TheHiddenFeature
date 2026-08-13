# Repository Guidelines

## Project Structure & Module Organization

`TheHiddenFeature/` contains the SwiftUI application. The app entry point and root view are at the top level. Feature code is grouped by responsibility: `Desktop/` owns the simulated Home Screen and transfer state, `Pairing/` contains device-role and discovery UI, `Connectivity/` wraps Multipeer Connectivity, and `Models/` defines shared layouts and protocol messages. Images live under `Resources/`; app catalog assets live in `Assets.xcassets`. Keep demo media in `docs/` and update `THIRD_PARTY_ASSETS.md` when adding externally sourced artwork. `PROJECT_PLAN.md` documents the transfer protocol and product constraints.

## Build, Test, and Development Commands

- `open TheHiddenFeature.xcodeproj` opens the project for normal development and physical-device runs.
- `xcodebuild -list -project TheHiddenFeature.xcodeproj` verifies targets and schemes.
- `xcodebuild -project TheHiddenFeature.xcodeproj -scheme TheHiddenFeature -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` performs a signing-free compile check.

The full interaction requires two physical devices running iOS/iPadOS 17 or later. Assign your own development team, install the app on both devices, and test left/right roles together.

## Coding Style & Naming Conventions

Use four-space indentation and standard Swift naming: `UpperCamelCase` for types, `lowerCamelCase` for methods and properties, and descriptive enum cases. Keep SwiftUI views focused, place state transitions in `DesktopSessionModel`, and isolate transport details behind `PeerTransport`. Preserve `@MainActor`, `Sendable`, and `Codable` boundaries when changing concurrent or networked code. No formatter or linter is configured; use Xcode formatting and match nearby code.

## Testing Guidelines

There is currently no XCTest target or coverage threshold. Every change must at least pass the simulator build above. Manually exercise pairing, local dragging, cross-device takeover, timeout rollback, and disconnect recovery when relevant. If adding tests, create an XCTest target, mirror feature folders, name files `FeatureTests.swift`, and use behavior-oriented methods such as `testCommitRemovesSourceItem()`.

## Commit & Pull Request Guidelines

History uses short, imperative summaries such as `drag fix` and `Add English README and demo video`. Keep subjects concise and scope each commit to one change. Pull requests should explain behavior and protocol impact, list validation performed, link related issues, and include screenshots or a short recording for UI changes. Note the device models and assigned left/right roles for physical-device results.

## Security & Assets

Do not commit credentials, provisioning profiles, or private signing material. Review `Info.plist` when changing Bonjour services or local-network permissions. Verify redistribution rights and record provenance before adding third-party icons, wallpapers, or media.
