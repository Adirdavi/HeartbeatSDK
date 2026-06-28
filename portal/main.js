/**
 * Main Application — HeartbeatSDK Lifeguard Dashboard
 *
 * Orchestrates:
 * - REST API data fetching and SSE real-time updates
 * - Session list rendering with live status updates
 * - Map integration (device + station markers)
 * - Alert management
 * - Stats bar updates
 * - Clock display
 */

import { initMap, updateDeviceMarkers, focusOnDevice, resizeMap } from "./map.js";
import { configureAlerts, updateAlerts } from "./alerts.js";

// ═══════════════════════════════════════════════════════════
//  API Server Configuration
//  Change this to your deployed server URL in production
// ═══════════════════════════════════════════════════════════

const API_URL = import.meta.env.VITE_API_URL || "http://localhost:3000";

// ═══════════════════════════════════════════════════════════
//  State
// ═══════════════════════════════════════════════════════════

/** @type {Array<Object>} All active sessions */
let sessions = [];

/** @type {Array<Object>} All closed sessions for history */
let closedSessions = [];

/** @type {Array<Object>} All alerts */
let alerts = [];

/** @type {EventSource|null} SSE connection */
let eventSource = null;

// ═══════════════════════════════════════════════════════════
//  Initialization
// ═══════════════════════════════════════════════════════════

document.addEventListener("DOMContentLoaded", () => {
  console.log("🏖️ HeartbeatSDK Portal — Initializing...");

  // Start the clock
  updateClock();
  setInterval(updateClock, 1000);

  // Initialize the map
  initMap();

  // Connect to API server via SSE
  try {
    connectToServer();
  } catch (error) {
    console.error("Server connection failed:", error);
    setConnectionStatus(false, error.message);
  }

  // Handle window resize
  window.addEventListener("resize", () => {
    resizeMap();
  });

  // History Modal Event Listeners
  const btnShowHistory = document.getElementById("btn-show-history");
  const btnCloseHistory = document.getElementById("btn-close-history");
  const historyOverlay = document.getElementById("history-overlay");

  if (btnShowHistory && historyOverlay) {
    btnShowHistory.addEventListener("click", () => {
      renderHistoryTable();
      historyOverlay.classList.add("active");
    });
  }

  if (btnCloseHistory && historyOverlay) {
    btnCloseHistory.addEventListener("click", () => {
      historyOverlay.classList.remove("active");
    });
  }
});

// ═══════════════════════════════════════════════════════════
//  SSE Connection — Real-time updates from API server
// ═══════════════════════════════════════════════════════════

function connectToServer() {
  console.log(`🔌 Connecting to API server: ${API_URL}/api/realtime`);

  // Configure alerts module with the API URL
  configureAlerts(API_URL);

  // Also fetch closed sessions (SSE only sends active)
  fetchClosedSessions();

  // Connect to SSE endpoint for real-time updates
  eventSource = new EventSource(`${API_URL}/api/realtime`);

  eventSource.addEventListener("sessions_update", (event) => {
    const allSessions = JSON.parse(event.data);
    console.log(`📡 Received ${allSessions.length} active session(s) from server`);
    setConnectionStatus(true);

    sessions = allSessions.filter((s) => s.current_status !== "closed");
    renderSessions(sessions);
    updateDeviceMarkers(sessions);
    updateStats();
  });

  eventSource.addEventListener("alerts_update", (event) => {
    const allAlerts = JSON.parse(event.data);
    console.log(`🚨 Received ${allAlerts.length} alert(s) from server`);

    alerts = allAlerts.sort(
      (a, b) => (b.triggered_at || 0) - (a.triggered_at || 0)
    );
    updateAlerts(alerts);
    updateStats();
  });

  eventSource.addEventListener("stations_update", (event) => {
    const stations = JSON.parse(event.data);
    console.log(`🏖️ Received ${stations.length} station(s) from server`);
  });

  eventSource.onopen = () => {
    console.log("🔥 SSE connection established");
    setConnectionStatus(true);
  };

  eventSource.onerror = (error) => {
    console.error("SSE connection error:", error);
    setConnectionStatus(false, "Connection lost — retrying...");
  };
}

/**
 * Fetch closed sessions from the REST API for history display.
 */
async function fetchClosedSessions() {
  try {
    const res = await fetch(`${API_URL}/api/sessions`);
    if (res.ok) {
      const allSessions = await res.json();
      closedSessions = allSessions.filter((s) => s.current_status === "closed");
    }
  } catch (err) {
    console.warn("Failed to fetch session history:", err);
  }
}

// ═══════════════════════════════════════════════════════════
//  Session Rendering
// ═══════════════════════════════════════════════════════════

function renderSessions(sessionList) {
  const container = document.getElementById("sessions-list");
  const countBadge = document.getElementById("sessions-count");

  if (!container) return;
  if (countBadge) countBadge.textContent = sessionList.length;

  if (sessionList.length === 0) {
    container.innerHTML = `
      <div class="empty-state">
        <div class="empty-state__icon">📡</div>
        <div class="empty-state__text">No active sessions<br/>Waiting for devices...</div>
      </div>
    `;
    return;
  }

  // Sort: emergency first, then warning, then normal
  const statusOrder = { emergency: 0, warning: 1, normal: 2 };
  const sorted = [...sessionList].sort(
    (a, b) =>
      (statusOrder[a.current_status] ?? 3) -
      (statusOrder[b.current_status] ?? 3)
  );

  container.innerHTML = sorted.map((s) => renderSessionCard(s)).join("");

  // Attach click handlers to focus on map
  container.querySelectorAll("[data-session-device]").forEach((card) => {
    card.addEventListener("click", () => {
      focusOnDevice(card.dataset.sessionDevice);
    });
  });
}

function renderSessionCard(session) {
  const status = session.current_status || "normal";
  const statusLabel = status.charAt(0).toUpperCase() + status.slice(1);
  const statusEmoji = { normal: "🟢", warning: "🟡", emergency: "🔴" };
  const duration = formatDuration(Date.now() - (session.session_start || Date.now()));

  const startTime = session.session_start ? new Date(session.session_start).toLocaleTimeString("en-US", {hour: "2-digit", minute: "2-digit"}) : "Unknown";
  const lastHeartbeat = session.last_heartbeat_timestamp ? new Date(session.last_heartbeat_timestamp).toLocaleTimeString("en-US", {hour: "2-digit", minute: "2-digit", second: "2-digit"}) : "Unknown";

  // Heart rate color coding
  const hr = session.heart_rate ?? -1;
  const hrColor = hr > 150 ? "#ff4444" : hr > 120 ? "#ffaa00" : hr >= 0 ? "#00ff88" : "var(--text-muted)";
  const hrText = hr >= 0 ? `${hr} bpm` : "N/A";

  // SpO2 color coding
  const spo2 = session.spo2 ?? -1;
  const spo2Color = spo2 < 94 ? "#ff4444" : spo2 < 96 ? "#ffaa00" : spo2 >= 0 ? "#00ff88" : "var(--text-muted)";
  const spo2Text = spo2 >= 0 ? `${spo2}%` : "N/A";

  return `
    <div class="session-card session-card--${status}"
         data-session-device="${session.device_id}">
      <div class="session-card__top">
        <span class="session-card__device">${session.device_id}</span>
        <span class="session-card__status session-card__status--${status}">
          ${statusEmoji[status] || "⚪"} ${statusLabel}
        </span>
      </div>
      <div class="session-card__user">
        👤 ${session.user_id || "Unknown"}
      </div>
      <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 8px; margin-top: 10px;">
        <div style="background: rgba(255,255,255,0.05); border-radius: 8px; padding: 8px; text-align: center;">
          <div style="font-size: 0.65rem; color: var(--text-muted); margin-bottom: 2px;">❤️ HEART RATE</div>
          <div style="font-size: 1.1rem; font-weight: 700; color: ${hrColor};">${hrText}</div>
        </div>
        <div style="background: rgba(255,255,255,0.05); border-radius: 8px; padding: 8px; text-align: center;">
          <div style="font-size: 0.65rem; color: var(--text-muted); margin-bottom: 2px;">🫁 SpO2</div>
          <div style="font-size: 1.1rem; font-weight: 700; color: ${spo2Color};">${spo2Text}</div>
        </div>
      </div>
      <div class="session-card__meta" style="flex-wrap: wrap; gap: 8px; margin-top: 8px;">
        <span>🏊 ${session.activity_type || "Unknown"}</span>
        <span>🔋 ${session.battery_level >= 0 ? Math.round(session.battery_level) + "%" : "N/A"}</span>
        <span style="color: var(--text-muted); font-size: 0.85rem;">v${session.sdk_version || "1.0.0"}</span>
      </div>
      <div style="font-size: 0.75rem; color: var(--text-muted); margin-top: 10px; border-top: 1px solid rgba(255,255,255,0.1); padding-top: 8px;">
        <div style="margin-bottom: 2px;">⏱️ <strong>Duration:</strong> ${duration}</div>
        <div style="margin-bottom: 2px;">🟢 <strong>Started:</strong> ${startTime}</div>
        <div>📡 <strong>Last Ping:</strong> ${lastHeartbeat}</div>
      </div>
    </div>
  `;
}

// ═══════════════════════════════════════════════════════════
//  History Rendering
// ═══════════════════════════════════════════════════════════

function renderHistoryTable() {
  const tbody = document.getElementById("history-table-body");
  if (!tbody) return;

  // Re-fetch closed sessions when opening the modal
  fetchClosedSessions();

  if (closedSessions.length === 0) {
    tbody.innerHTML = `<tr><td colspan="6" style="text-align: center; padding: 32px;">No connection history available.</td></tr>`;
    return;
  }

  const sorted = [...closedSessions].sort((a, b) => (b.session_start || 0) - (a.session_start || 0));

  tbody.innerHTML = sorted.map((s) => {
    const startStr = s.session_start ? new Date(s.session_start).toLocaleString(undefined, {month: "short", day: "numeric", hour: "2-digit", minute: "2-digit", second: "2-digit"}) : "Unknown";
    const endStr = s.session_closed_at ? new Date(s.session_closed_at).toLocaleString(undefined, {month: "short", day: "numeric", hour: "2-digit", minute: "2-digit", second: "2-digit"}) : "Unknown";

    return `
      <tr>
        <td class="hl-cyan">${s.user_id || "Unknown"}</td>
        <td>${s.device_id || "Unknown"}</td>
        <td>${s.activity_type || "Unknown"}</td>
        <td>${startStr}</td>
        <td>${endStr}</td>
        <td style="font-family: var(--font-mono); font-size: 0.75rem; color: var(--text-muted);">${s.session_id}</td>
      </tr>
    `;
  }).join("");
}

// ═══════════════════════════════════════════════════════════
//  Stats Bar
// ═══════════════════════════════════════════════════════════

function updateStats() {
  // Active sessions
  const sessionsValue = document.getElementById("stat-sessions-value");
  if (sessionsValue) sessionsValue.textContent = sessions.length;

  // Emergency count
  const emergencyCount = sessions.filter(
    (s) => s.current_status === "emergency"
  ).length;
  const emergenciesValue = document.getElementById("stat-emergencies-value");
  if (emergenciesValue) emergenciesValue.textContent = emergencyCount;

  // Warning count
  const warningCount = sessions.filter(
    (s) => s.current_status === "warning"
  ).length;
  const warningsValue = document.getElementById("stat-warnings-value");
  if (warningsValue) warningsValue.textContent = warningCount;

  // Average battery
  const batteryLevels = sessions
    .filter((s) => s.battery_level >= 0)
    .map((s) => s.battery_level);
  const avgBattery =
    batteryLevels.length > 0
      ? Math.round(
          batteryLevels.reduce((a, b) => a + b, 0) / batteryLevels.length
        )
      : "--";
  const batteryValue = document.getElementById("stat-battery-value");
  if (batteryValue) batteryValue.textContent = `${avgBattery}%`;
}

// ═══════════════════════════════════════════════════════════
//  Utilities
// ═══════════════════════════════════════════════════════════

function updateClock() {
  const el = document.getElementById("header-time");
  if (el) {
    el.textContent = new Date().toLocaleTimeString("en-IL", {
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      hour12: false,
    });
  }
}

function setConnectionStatus(isConnected, errorMsg) {
  const indicator = document.getElementById("connection-dot");
  const text = document.getElementById("connection-text");

  if (indicator && text) {
    if (isConnected) {
      indicator.className = "connection-dot";
      text.textContent = "Live — Server Connected";
    } else {
      indicator.className = "connection-dot offline";
      text.textContent = errorMsg ? `Error: ${errorMsg}` : "Disconnected / Error";
    }
  }
}

function formatDuration(ms) {
  const totalSeconds = Math.floor(ms / 1000);
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);

  if (hours > 0) return `${hours}h ${minutes}m`;
  return `${minutes}m`;
}
