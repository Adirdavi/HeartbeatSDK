# HeartbeatSDK

**Standalone smartwatch monitoring infrastructure for life-safety applications.**

HeartbeatSDK is a software infrastructure designed for smartwatches that operates independently — no paired smartphone required. It manages activity sessions, transmits real-time availability signals (Heartbeats) to the cloud, and powers a monitoring portal for operators and lifeguards.

---

## Architecture

```
  ⌚ Smartwatch                    📱 Phone                     ☁️ Cloud Server                🖥️ Portal
 ┌───────────┐              ┌──────────────────┐          ┌──────────────────┐          ┌─────────────────┐
 │  Sensors  │   Bluetooth  │  HeartbeatSDK    │  HTTP    │  Express.js      │   SSE    │  Lifeguard      │
 │  HR, GPS  │─────────────▶│  (Flutter/Dart)  │─────────▶│  REST API        │─────────▶│  Dashboard      │
 │  Battery  │              │  open/close      │  POST    │  JSON Persistence│  Stream  │  (Vite + JS)    │
 └───────────┘              │  session         │◀─────────│                  │◀─────────│                 │
                            └──────────────────┘ Response └──────────────────┘  fetch   └─────────────────┘
```

## Monorepo Structure

| Directory | Technology | Purpose |
|-----------|------------|---------|
| `/sdk` | Flutter / Dart | Native smartwatch SDK (Wear OS + watchOS) |
| `/server` | Node.js + Express | Custom REST API server with SSE real-time streaming |
| `/portal` | Vite + Vanilla JS | Real-time lifeguard monitoring dashboard |

## SDK Public API

```dart
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
- **Real-Time Portal** — Live session monitoring, map view, alert management
- **Custom Backend** — Fully controlled REST API with JSON persistence and SSE

## Getting Started

### Prerequisites

- Flutter SDK (≥ 3.0)
- Node.js (≥ 18)

### Development

```bash
# Start the Express API server (port 3000)
npm run dev:server

# Start the Portal development server (port 5173)
npm run dev:portal

# Or start both simultaneously
npm run dev:all
```

### Deployment

The API server is configured for deployment on Render.com using the provided `render.yaml`. The portal can be built and served statically.

## Use Cases

- 🏊 **Marine Rescue** — Monitoring swimmers and surfers (SaveMe)
- 👴 **Elderly Care** — Continuous monitoring for distress detection
- 🏔️ **Extreme Sports** — Tracking lone workers and athletes

## License

MIT
