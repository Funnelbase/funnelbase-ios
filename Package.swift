// swift-tools-version: 5.9
import PackageDescription

// The Funnelbase iOS SDK, as a Swift package. Two products, because a notification service
// extension is a separate process with a separate binary: the app links `Funnelbase`, the extension
// links `FunnelbaseNotificationService`, and both share the core through `FunnelbaseCore`.
//
// No Firebase dependency, and no dependencies at all. Whoever holds the push token hands it over
// (`Analytics.push.setToken`), exactly as on Android, so an app on Firebase, on APNs directly, or
// on a gateway of its own all work. See docs/sdk-ios.md.
//
// macOS is listed only so `swift test` runs the core on a Mac without a simulator. The SDK is an
// iOS SDK; the platform layer compiles away elsewhere.
let package = Package(
    name: "Funnelbase",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "Funnelbase", targets: ["Funnelbase"]),
        .library(name: "FunnelbaseNotificationService", targets: ["FunnelbaseNotificationService"]),
    ],
    targets: [
        .target(name: "FunnelbaseCore"),
        .target(name: "Funnelbase", dependencies: ["FunnelbaseCore"]),
        .target(name: "FunnelbaseNotificationService", dependencies: ["FunnelbaseCore"]),
        // One test target: everything worth testing is in the core, and the two platform layers
        // are thin wrappers over it that need a simulator to exercise at all.
        .testTarget(name: "FunnelbaseCoreTests", dependencies: ["FunnelbaseCore"]),
    ]
)
