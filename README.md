# HeartbeatSDK for iOS & watchOS

The official Swift Package SDK for connecting Apple Watch and iOS devices to the Heartbeat Portal.

## Installation

You can add HeartbeatSDK to an Xcode project by adding it as a package dependency.

1. Open your project in Xcode.
2. Go to **File > Add Package Dependencies...**
3. Enter the URL of this GitHub repository in the search bar.
4. Click **Add Package**.

## Usage

Import the SDK in your SwiftUI view or AppDelegate:

```swift
import HeartbeatSDKSwift

// 1. Configure the SDK with your Firebase project ID
HeartbeatSDK.shared.configure(
    projectId: "adir-2c6b3",
    deviceId: "apple_watch_ultra"
)

// 2. Open a session when the user starts the activity
HeartbeatSDK.shared.openSession(
    userId: "Adir_Davidov", 
    activityType: "swimming"
)

// 3. Close the session when done
HeartbeatSDK.shared.closeSession()
```

## Features
- **Offline Queue**: If the Apple Watch loses cellular/Wi-Fi connection while swimming, the SDK caches heartbeats using `UserDefaults` and flushes them automatically when connection is restored.
- **Battery Optimization**: Native `WatchKit` integration to read actual battery levels.
- **Direct to Firebase**: Connects securely and directly to your Firebase Cloud Functions.
