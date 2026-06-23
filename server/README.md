# HeartbeatSDK REST API Server

A standalone Express.js REST API server for managing real-time smartwatch monitoring sessions, alerts, and crash analytics.

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

## Getting Started

### Prerequisites

- Node.js ≥ 18

### Installation

```bash
cd server
npm install
```

### Running Locally

```bash
# Production mode
npm start

# Development mode (auto-restart on changes)
npm run dev
```

The server starts on `http://localhost:3000` by default.  
Set the `PORT` environment variable to change the port.

---

## API Endpoints

### Health Check

```
GET /api/health
```

**Response:**
```json
{
  "status": "ok",
  "uptime": 123.456,
  "timestamp": 1719100000000,
  "stats": {
    "active_sessions": 3,
    "total_sessions": 15,
    "pending_alerts": 1,
    "total_alerts": 5,
    "crash_reports": 2,
    "stations": 10,
    "sse_clients": 1
  }
}
```

---

### Heartbeat (SDK → Server)

```
POST /api/heartbeat
```

Receives a heartbeat payload from the SmartWatch SDK. Creates or updates a session.

**Request Body:**
```json
{
  "device_id": "watch_001",
  "session_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "user_id": "user_42",
  "timestamp": 1719100000000,
  "battery_level": 85,
  "heart_rate": 72,
  "spo2": 98,
  "gps": {
    "lat": 32.0853,
    "lng": 34.7818
  },
  "activity_type": "swimming",
  "user_age": 25,
  "sdk_version": "1.0.0"
}
```

**Success Response (200):**
```json
{
  "success": true,
  "device_id": "watch_001",
  "session_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "status": "normal",
  "server_timestamp": 1719100000500
}
```

**Error Response (400):**
```json
{
  "error": "Invalid payload. Required fields: device_id, timestamp, session_id"
}
```

#### Close Session

Send `"action": "close_session"` in the heartbeat payload to close an active session:

```json
{
  "device_id": "watch_001",
  "session_id": "a1b2c3d4-...",
  "timestamp": 1719103600000,
  "action": "close_session"
}
```

---

### Crash Report (SDK → Server)

```
POST /api/crash-report
```

Receives crash analytics from the SDK for post-mortem analysis.

**Request Body:**
```json
{
  "report_id": "crash_abc123",
  "device_id": "watch_001",
  "session_id": "a1b2c3d4-...",
  "error_message": "Null check operator used on a null value",
  "stack_trace": "...",
  "crash_timestamp": 1719100000000,
  "sdk_version": "1.0.0",
  "device_state": {
    "battery_level": 15,
    "is_online": false,
    "queued_heartbeats": 3,
    "session_uptime": 1800
  }
}
```

**Success Response (200):**
```json
{
  "success": true,
  "report_id": "crash_abc123"
}
```

---

### Acknowledge Alert (Portal → Server)

```
POST /api/alert/acknowledge
```

Called from the lifeguard portal when an operator acknowledges an alert.

**Request Body:**
```json
{
  "alert_id": "alert_a1b2c3d4",
  "acknowledged_by": "lifeguard_portal"
}
```

**Success Response (200):**
```json
{
  "success": true,
  "alert_id": "alert_a1b2c3d4",
  "status": "acknowledged"
}
```

**Error Response (404):**
```json
{
  "error": "Alert not found"
}
```

---

### Get Sessions

```
GET /api/sessions          # All sessions (active + closed)
GET /api/sessions/active   # Active sessions only
```

**Response:**
```json
[
  {
    "device_id": "watch_001",
    "session_id": "a1b2c3d4-...",
    "user_id": "user_42",
    "last_heartbeat_timestamp": 1719100000000,
    "battery_level": 85,
    "heart_rate": 72,
    "spo2": 98,
    "gps": { "lat": 32.0853, "lng": 34.7818 },
    "activity_type": "swimming",
    "current_status": "normal",
    "session_start": 1719096400000,
    "user_age": 25,
    "client_ip": "192.168.1.100"
  }
]
```

---

### Get Alerts

```
GET /api/alerts
```

**Response:**
```json
[
  {
    "id": "alert_a1b2c3d4",
    "device_id": "watch_003",
    "session_id": "...",
    "severity": "emergency",
    "triggered_at": 1719100060000,
    "status": "pending",
    "last_known_gps": { "lat": 32.0710, "lng": 34.7635 },
    "last_battery_level": 15,
    "time_since_last_heartbeat": 75,
    "activity_type": "swimming",
    "user_id": "user_noa"
  }
]
```

---

### Get Lifeguard Stations

```
GET /api/stations
```

**Response:**
```json
[
  {
    "station_id": "station_gordon",
    "name": "Gordon Beach Station",
    "beach_name": "Gordon Beach",
    "location": { "lat": 32.0831, "lng": 34.7678 },
    "is_active": true,
    "capacity": 3,
    "contact_phone": "+972-3-555-0101"
  }
]
```

---

### Real-time Updates (SSE)

```
GET /api/realtime
```

Server-Sent Events stream for real-time portal updates.

**Event Types:**

| Event | Data | Trigger |
|-------|------|---------|
| `sessions_update` | Array of active sessions | On heartbeat, status change |
| `alerts_update` | Array of all alerts | On new alert, acknowledge |
| `stations_update` | Array of stations | On initial connection |

**Example (JavaScript):**
```js
const eventSource = new EventSource("http://localhost:3000/api/realtime");

eventSource.addEventListener("sessions_update", (event) => {
  const sessions = JSON.parse(event.data);
  console.log("Active sessions:", sessions);
});

eventSource.addEventListener("alerts_update", (event) => {
  const alerts = JSON.parse(event.data);
  console.log("Alerts:", alerts);
});
```

---

## Watchdog Timer

The server runs a background watchdog every **5 seconds** that checks all active sessions:

| Condition | New Status | Action |
|-----------|-----------|--------|
| No heartbeat for > 30 seconds | `warning` | Create warning alert |
| No heartbeat for > 60 seconds | `emergency` | Create emergency alert |
| Heartbeat received | `normal` | — |

---

## Testing with curl

```bash
# 1. Health check
curl http://localhost:3000/api/health

# 2. Send a heartbeat
curl -X POST http://localhost:3000/api/heartbeat \
  -H "Content-Type: application/json" \
  -d '{
    "device_id": "watch_001",
    "session_id": "test-session-001",
    "user_id": "user_42",
    "timestamp": '"$(date +%s000)"',
    "battery_level": 85,
    "heart_rate": 72,
    "gps": {"lat": 32.0853, "lng": 34.7818},
    "activity_type": "swimming",
    "user_age": 25
  }'

# 3. Get active sessions
curl http://localhost:3000/api/sessions/active

# 4. Listen to real-time events
curl -N http://localhost:3000/api/realtime

# 5. Close a session
curl -X POST http://localhost:3000/api/heartbeat \
  -H "Content-Type: application/json" \
  -d '{
    "device_id": "watch_001",
    "session_id": "test-session-001",
    "timestamp": '"$(date +%s000)"',
    "action": "close_session"
  }'
```

---

## Deployment (Render.com)

1. Push to GitHub
2. Create a new **Web Service** on [render.com](https://render.com)
3. Settings:
   - **Root Directory**: `server`
   - **Build Command**: `npm install`
   - **Start Command**: `node server.js`
   - **Environment**: Node.js
4. The server will receive a URL like `https://heartbeat-api.onrender.com`

---

## Error Codes

| Status | Meaning |
|--------|---------|
| `200` | Success |
| `400` | Bad Request — missing required fields |
| `404` | Not Found — resource does not exist |
| `405` | Method Not Allowed |
| `500` | Internal Server Error |
