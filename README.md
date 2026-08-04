# The Hidden Feature

The Hidden Feature is an experimental two-device iOS experience that makes an app icon appear to move directly from an iPhone to an iPad.

The app recreates an iOS-style Home Screen inside the application, connects nearby devices with Multipeer Connectivity, and coordinates the handoff as a drag crosses the shared screen edge.

> [!NOTE]
> This project does not access or modify the real iOS or iPadOS Home Screen. All icons, layouts, gestures, and transfers are simulated inside the app.

## Demo

https://github.com/user-attachments/assets/4037bbb5-e496-4062-916b-c4159122fcbd

[![Watch The Hidden Feature demo](docs/demo-cover.jpg)](docs/demo.mp4)

Click the preview to play the 32-second demonstration.

## Features

- Nearby pairing between an iPhone and an iPad
- Left-device and right-device roles with a shared screen edge
- iOS-style Home Screen layouts tailored for iPhone and iPad
- Long-press edit mode with icon jiggle animations
- Local icon dragging and layout reordering
- Cross-device icon preview, takeover, placement, and rollback
- Reliable transfer state synchronization over Multipeer Connectivity

## Requirements

- Xcode 26.2 or later
- iOS 17.0 or later
- iPadOS 17.0 or later
- Two physical devices on the same local network or within peer-to-peer wireless range
- An Apple Development signing team

## Running the Demo

1. Open `TheHiddenFeature.xcodeproj` in Xcode.
2. Select your development team for the app target.
3. Build and run the app on both devices.
4. Choose the left-device role on the iPhone and the right-device role on the iPad.
5. Complete nearby pairing and place the devices side by side.
6. Enter edit mode on both devices.
7. Drag the Reality Composer icon from the right edge of the iPhone.
8. Continue the gesture from the left edge of the iPad, then drop the icon into place.

## How It Works

The two displays do not share one continuous system touch sequence. When the drag leaves the source screen, the source device sends the icon and transfer state to the target. The target presents an edge preview and attaches it to a new touch when the user's finger enters the second screen. A request/commit/acknowledgement protocol ensures that only one device owns the icon after the transfer completes.

See [PROJECT_PLAN.md](PROJECT_PLAN.md) for the product design, protocol, and implementation details.

## Technology

- SwiftUI
- Multipeer Connectivity
- Swift Observation and structured concurrency
- No third-party runtime dependencies

## Disclaimer

This project is an independent experimental demonstration. It is not affiliated with or endorsed by Apple Inc. Apple product names and visual assets belong to their respective owners.
