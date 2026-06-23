/**
 * HeartbeatSDK — REST API Server
 *
 * A standalone Express.js server that replaces Firebase Cloud Functions
 * and Firestore with a custom REST API and JSON file persistence.
 *
 * Architecture:
 *   ⌚ Watch → 📱 Phone (SDK) → ☁️ This Server → 🖥️ Portal
 *
 * Features:
 *   - REST API endpoints for heartbeats, sessions, alerts, crash reports
 *   - Server-Sent Events (SSE) for real-time portal updates
 *   - Watchdog timer for detecting stale sessions
 *   - JSON file persistence (db.json)
 *   - IP tracking per heartbeat
 */

const express = require("express");
const cors = require("cors");
const fs = require("fs");
const path = require("path");
const { v4: uuidv4 } = require("uuid");

const app = express();
const PORT = process.env.PORT || 3000;

// ═══════════════════════════════════════════════════════════
//  MIDDLEWARE
// ═══════════════════════════════════════════════════════════

app.use(cors());
app.use(express.json());

// Trust proxy for accurate IP tracking (needed on Render/Heroku)
app.set("trust proxy", true);

// ═══════════════════════════════════════════════════════════
//  DATABASE (JSON File Persistence)
// ═══════════════════════════════════════════════════════════

const DB_PATH = path.join(__dirname, "db.json");

/** In-memory database */
let db = {
  sessions: [],
  alerts: [],
  crashReports: [],
  stations: [],
};

/** Load database from disk on startup */
function loadDB() {
  try {
    if (fs.existsSync(DB_PATH)) {
      const raw = fs.readFileSync(DB_PATH, "utf-8");
      db = JSON.parse(raw);
      console.log(
        `📂 Database loaded: ${db.sessions.length} sessions, ${db.alerts.length} alerts, ${db.stations.length} stations`
      );
    }
  } catch (err) {
    console.error("⚠️  Failed to load db.json, starting fresh:", err.message);
  }
}

/** Save database to disk */
function saveDB() {
  try {
    fs.writeFileSync(DB_PATH, JSON.stringify(db, null, 2), "utf-8");
  } catch (err) {
    console.error("⚠️  Failed to save db.json:", err.message);
  }
}

// Load on startup
loadDB();

// ═══════════════════════════════════════════════════════════
//  CONSTANTS
// ═══════════════════════════════════════════════════════════

/** Seconds of silence before a session is flagged as Warning */
const WARNING_THRESHOLD_SEC = 30;

/** Seconds of silence before a session is escalated to Emergency */
const EMERGENCY_THRESHOLD_SEC = 60;

/** Watchdog check interval (ms) */
const WATCHDOG_INTERVAL_MS = 5000;

// ═══════════════════════════════════════════════════════════
//  SSE (Server-Sent Events) — Real-time updates to portal
// ═══════════════════════════════════════════════════════════

/** @type {Set<import('http').ServerResponse>} Connected SSE clients */
const sseClients = new Set();

/**
 * Broadcast an event to all connected SSE clients.
 * @param {string} eventType - Event name (e.g., 'sessions_update', 'alerts_update')
 * @param {any} data - JSON-serializable data to send
 */
function broadcast(eventType, data) {
  const message = `event: ${eventType}\ndata: ${JSON.stringify(data)}\n\n`;

  for (const client of sseClients) {
    try {
      client.write(message);
    } catch {
      sseClients.delete(client);
    }
  }
}

/** Broadcast current sessions and alerts to all clients */
function broadcastFullState() {
  const activeSessions = db.sessions.filter(
    (s) => s.current_status !== "closed"
  );
  broadcast("sessions_update", activeSessions);
  broadcast("alerts_update", db.alerts);
}

// ═══════════════════════════════════════════════════════════
//  SSE ENDPOINT — GET /api/realtime
// ═══════════════════════════════════════════════════════════

app.get("/api/realtime", (req, res) => {
  // Set SSE headers
  res.writeHead(200, {
    "Content-Type": "text/event-stream",
    "Cache-Control": "no-cache",
    Connection: "keep-alive",
    "Access-Control-Allow-Origin": "*",
  });

  // Send initial state
  const activeSessions = db.sessions.filter(
    (s) => s.current_status !== "closed"
  );
  res.write(
    `event: sessions_update\ndata: ${JSON.stringify(activeSessions)}\n\n`
  );
  res.write(`event: alerts_update\ndata: ${JSON.stringify(db.alerts)}\n\n`);
  res.write(
    `event: stations_update\ndata: ${JSON.stringify(db.stations)}\n\n`
  );

  // Keep alive
  const keepAlive = setInterval(() => {
    res.write(": keepalive\n\n");
  }, 15000);

  // Register client
  sseClients.add(res);
  console.log(`📡 SSE client connected (total: ${sseClients.size})`);

  // Cleanup on disconnect
  req.on("close", () => {
    clearInterval(keepAlive);
    sseClients.delete(res);
    console.log(`📡 SSE client disconnected (total: ${sseClients.size})`);
  });
});

// ═══════════════════════════════════════════════════════════
//  POST /api/heartbeat — Receive heartbeat from SDK
// ═══════════════════════════════════════════════════════════

app.post("/api/heartbeat", (req, res) => {
  try {
    // Support both direct payload and Firebase-style { data: payload }
    const payload = req.body.data || req.body;

    // Validate required fields
    if (
      !payload ||
      !payload.device_id ||
      !payload.timestamp ||
      !payload.session_id
    ) {
      return res.status(400).json({
        error:
          "Invalid payload. Required fields: device_id, timestamp, session_id",
      });
    }

    const {
      device_id,
      session_id,
      user_id,
      timestamp,
      battery_level,
      gps,
      activity_type,
      sdk_version,
      heart_rate,
      spo2,
      action,
      user_age,
    } = payload;

    // Capture client IP
    const client_ip =
      req.ip || req.headers["x-forwarded-for"] || req.socket.remoteAddress;

    // ── Handle session close action ──
    if (action === "close_session") {
      const sessionIdx = db.sessions.findIndex(
        (s) => s.session_id === session_id
      );
      if (sessionIdx !== -1) {
        db.sessions[sessionIdx].current_status = "closed";
        db.sessions[sessionIdx].session_closed_at = timestamp;
        db.sessions[sessionIdx].updated_at = Date.now();
      }

      saveDB();
      broadcastFullState();

      console.log(
        `🔒 Session ${session_id} closed for device ${device_id}`
      );
      return res.status(200).json({
        success: true,
        device_id,
        session_id,
        status: "closed",
      });
    }

    // ── Build session document ──
    const sessionDoc = {
      device_id,
      session_id,
      user_id: user_id || null,
      last_heartbeat_timestamp: timestamp,
      battery_level: battery_level ?? -1,
      heart_rate: heart_rate ?? -1,
      spo2: spo2 ?? -1,
      gps: gps || null,
      activity_type: activity_type || "unknown",
      current_status: "normal",
      sdk_version: sdk_version || "unknown",
      client_ip: client_ip || null,
      updated_at: Date.now(),
    };

    // ── Find existing session ──
    const existingIdx = db.sessions.findIndex(
      (s) => s.session_id === session_id
    );

    if (existingIdx !== -1) {
      // Update existing session — preserve session_start and user_age
      const existing = db.sessions[existingIdx];
      db.sessions[existingIdx] = {
        ...existing,
        ...sessionDoc,
        session_start: existing.session_start,
        user_age: existing.user_age,
        created_at: existing.created_at,
      };
    } else {
      // New session — auto-close any stale sessions for this device
      db.sessions.forEach((s, idx) => {
        if (s.device_id === device_id && s.current_status !== "closed") {
          db.sessions[idx].current_status = "closed";
          db.sessions[idx].session_closed_at = timestamp;
          db.sessions[idx].closure_reason = "superseded_by_new_session";
          db.sessions[idx].updated_at = Date.now();
          console.log(
            `🔄 Auto-closed stale session ${s.session_id} for device ${device_id}`
          );
        }
      });

      // Create new session
      sessionDoc.session_start = timestamp;
      sessionDoc.user_age = user_age || null;
      sessionDoc.created_at = Date.now();
      db.sessions.push(sessionDoc);
    }

    saveDB();
    broadcastFullState();

    console.log(
      `💓 Heartbeat: ${device_id} | session=${session_id} | battery=${sessionDoc.battery_level}% | hr=${sessionDoc.heart_rate} | ip=${client_ip}`
    );

    return res.status(200).json({
      success: true,
      device_id,
      session_id,
      status: "normal",
      server_timestamp: Date.now(),
    });
  } catch (error) {
    console.error("❌ Error processing heartbeat:", error);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ═══════════════════════════════════════════════════════════
//  POST /api/alert/acknowledge — Acknowledge an alert
// ═══════════════════════════════════════════════════════════

app.post("/api/alert/acknowledge", (req, res) => {
  try {
    // Support both direct payload and Firebase-style { data: payload }
    const body = req.body.data || req.body;
    const { alert_id, acknowledged_by } = body;

    if (!alert_id) {
      return res.status(400).json({ error: "alert_id is required" });
    }

    const alertIdx = db.alerts.findIndex((a) => a.id === alert_id);
    if (alertIdx === -1) {
      return res.status(404).json({ error: "Alert not found" });
    }

    // Update alert
    db.alerts[alertIdx].status = "acknowledged";
    db.alerts[alertIdx].acknowledged_by = acknowledged_by || "unknown";
    db.alerts[alertIdx].acknowledged_at = Date.now();
    db.alerts[alertIdx].updated_at = Date.now();

    saveDB();
    broadcastFullState();

    console.log(
      `✅ Alert ${alert_id} acknowledged by ${acknowledged_by || "unknown"}`
    );

    return res.status(200).json({
      success: true,
      alert_id,
      status: "acknowledged",
    });
  } catch (error) {
    console.error("❌ Error acknowledging alert:", error);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ═══════════════════════════════════════════════════════════
//  POST /api/crash-report — Receive crash report from SDK
// ═══════════════════════════════════════════════════════════

app.post("/api/crash-report", (req, res) => {
  try {
    // Support both direct payload and Firebase-style { data: payload }
    const crashLog = req.body.data || req.body;

    if (!crashLog || !crashLog.report_id || !crashLog.device_id) {
      return res.status(400).json({
        error: "Invalid crash log. Required: report_id, device_id",
      });
    }

    // Store crash report
    crashLog.received_at = Date.now();
    db.crashReports.push(crashLog);

    saveDB();

    console.log(
      `💥 Crash report: ${crashLog.report_id} from device ${crashLog.device_id}`
    );

    return res.status(200).json({
      success: true,
      report_id: crashLog.report_id,
    });
  } catch (error) {
    console.error("❌ Error storing crash report:", error);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ═══════════════════════════════════════════════════════════
//  GET ENDPOINTS — Data retrieval
// ═══════════════════════════════════════════════════════════

/** GET /api/sessions — All sessions */
app.get("/api/sessions", (req, res) => {
  res.json(db.sessions);
});

/** GET /api/sessions/active — Only active (non-closed) sessions */
app.get("/api/sessions/active", (req, res) => {
  const active = db.sessions.filter((s) => s.current_status !== "closed");
  res.json(active);
});

/** GET /api/alerts — All alerts */
app.get("/api/alerts", (req, res) => {
  res.json(db.alerts);
});

/** GET /api/stations — All lifeguard stations */
app.get("/api/stations", (req, res) => {
  res.json(db.stations);
});

/** GET /api/crash-reports — All crash reports */
app.get("/api/crash-reports", (req, res) => {
  res.json(db.crashReports);
});

/** GET /api/health — Server health check */
app.get("/api/health", (req, res) => {
  const activeSessions = db.sessions.filter(
    (s) => s.current_status !== "closed"
  );
  const pendingAlerts = db.alerts.filter((a) => a.status === "pending");

  res.json({
    status: "ok",
    uptime: process.uptime(),
    timestamp: Date.now(),
    stats: {
      active_sessions: activeSessions.length,
      total_sessions: db.sessions.length,
      pending_alerts: pendingAlerts.length,
      total_alerts: db.alerts.length,
      crash_reports: db.crashReports.length,
      stations: db.stations.length,
      sse_clients: sseClients.size,
    },
  });
});

// ═══════════════════════════════════════════════════════════
//  WATCHDOG — Detect stale sessions and create alerts
//  Runs every 5 seconds to check for missed heartbeats.
// ═══════════════════════════════════════════════════════════

function watchdog() {
  const now = Date.now();
  let changed = false;
  const newAlerts = [];

  for (const session of db.sessions) {
    if (session.current_status === "closed") continue;

    const lastBeat = session.last_heartbeat_timestamp;
    if (!lastBeat) continue;

    const timeSinceLastBeat = (now - lastBeat) / 1000; // seconds
    const previousStatus = session.current_status;
    let newStatus = "normal";

    if (timeSinceLastBeat > EMERGENCY_THRESHOLD_SEC) {
      newStatus = "emergency";
    } else if (timeSinceLastBeat > WARNING_THRESHOLD_SEC) {
      newStatus = "warning";
    }

    // Only act if status changed
    if (newStatus !== previousStatus) {
      session.current_status = newStatus;
      session.status_changed_at = now;
      session.time_since_last_heartbeat = Math.round(timeSinceLastBeat);
      changed = true;

      console.log(
        `🔍 Watchdog: ${session.device_id} ${previousStatus} → ${newStatus} (${Math.round(timeSinceLastBeat)}s)`
      );

      // Create alert on escalation to emergency
      if (newStatus === "emergency" && previousStatus !== "emergency") {
        const alert = {
          id: `alert_${uuidv4().slice(0, 8)}`,
          device_id: session.device_id,
          session_id: session.session_id,
          severity: "emergency",
          triggered_at: now,
          status: "pending",
          last_known_gps: session.gps || null,
          last_battery_level: session.battery_level,
          time_since_last_heartbeat: Math.round(timeSinceLastBeat),
          activity_type: session.activity_type,
          user_id: session.user_id,
          created_at: now,
        };
        db.alerts.push(alert);
        newAlerts.push(alert);
      }

      // Create alert on warning (lower priority)
      if (newStatus === "warning" && previousStatus === "normal") {
        const alert = {
          id: `alert_${uuidv4().slice(0, 8)}`,
          device_id: session.device_id,
          session_id: session.session_id,
          severity: "warning",
          triggered_at: now,
          status: "pending",
          last_known_gps: session.gps || null,
          last_battery_level: session.battery_level,
          time_since_last_heartbeat: Math.round(timeSinceLastBeat),
          activity_type: session.activity_type,
          user_id: session.user_id,
          created_at: now,
        };
        db.alerts.push(alert);
        newAlerts.push(alert);
      }
    }
  }

  if (changed) {
    saveDB();
    broadcastFullState();
  }

  if (newAlerts.length > 0) {
    console.log(`🚨 Watchdog created ${newAlerts.length} alert(s)`);
  }
}

// Start watchdog timer
setInterval(watchdog, WATCHDOG_INTERVAL_MS);

// ═══════════════════════════════════════════════════════════
//  START SERVER
// ═══════════════════════════════════════════════════════════

app.listen(PORT, () => {
  console.log(`
╔══════════════════════════════════════════════════╗
║         HeartbeatSDK REST API Server             ║
╠══════════════════════════════════════════════════╣
║  🌐  URL:     http://localhost:${PORT}              ║
║  📡  SSE:     http://localhost:${PORT}/api/realtime  ║
║  💓  Health:  http://localhost:${PORT}/api/health    ║
╠══════════════════════════════════════════════════╣
║  Endpoints:                                      ║
║  POST /api/heartbeat       — SDK heartbeat       ║
║  POST /api/crash-report    — SDK crash report    ║
║  POST /api/alert/acknowledge — Ack alert         ║
║  GET  /api/sessions        — All sessions        ║
║  GET  /api/sessions/active — Active sessions     ║
║  GET  /api/alerts          — All alerts           ║
║  GET  /api/stations        — Lifeguard stations  ║
║  GET  /api/realtime        — SSE stream          ║
║  GET  /api/health          — Health check        ║
╠══════════════════════════════════════════════════╣
║  🔍  Watchdog: every ${WATCHDOG_INTERVAL_MS / 1000}s                        ║
║  ⚠️   Warning:  ${WARNING_THRESHOLD_SEC}s | 🚨 Emergency: ${EMERGENCY_THRESHOLD_SEC}s          ║
╚══════════════════════════════════════════════════╝
  `);
});
