# HeartbeatSDK

**Standalone smartwatch monitoring infrastructure for life-safety applications.**

HeartbeatSDK is a software infrastructure designed for smartwatches that operates independently — no paired smartphone required. It manages activity sessions, transmits real-time availability signals (Heartbeats) to the cloud, and powers a monitoring portal for operators and lifeguards.

---

## SDK Public API

```dart
import 'package:heartbeat_sdk/heartbeat_sdk.dart';

// Initialize the SDK
final sdk = HeartbeatSDK();
await sdk.configure(serverUrl: 'https://heartbeat-api.onrender.com', deviceId: 'watch_001');

// Open a session
await sdk.openSession(
  userId: 'user_42',
  userAge: 25,
  activityType: 'swimming',
);

// Start heartbeat transmission (every 10 seconds)
sdk.start(interval: Duration(seconds: 10));

// Close session when done
await sdk.closeSession();
```

## Key Features

- **Session Management** — Open/close activity sessions with user validation (18+)
- **Autonomous Heartbeat Transmission** — Background timer sends availability signals
- **Offline-First** — Local caching when disconnected, auto-sync on reconnect
- **Crash Analytics** — Captures errors before shutdown, transmits on next boot
- **Haptic Control** — Disables vibration during sessions to prevent distractions

## Use Cases

- 🏊 **Marine Rescue** — Monitoring swimmers and surfers (SaveMe)
- 👴 **Elderly Care** — Continuous monitoring for distress detection
- 🏔️ **Extreme Sports** — Tracking lone workers and athletes
