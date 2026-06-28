/**
 * Alerts Module — Real-time alert management for the lifeguard dashboard.
 *
 * Handles:
 * - Rendering alert cards in the alerts panel
 * - Critical emergency popup modal with sound
 * - Acknowledge button that calls the REST API server
 * - Alert history tracking
 */

import { focusOnDevice } from "./map.js";

/** @type {Map<string, Object>} Alert data indexed by alert_id */
const alertsMap = new Map();

/** Currently displayed emergency alert ID */
let activeEmergencyId = null;

/** Cloud Function URL for acknowledging alerts */
let acknowledgeUrl = "";

/**
 * Configure the alerts module.
 *
 * @param {string} projectId - Firebase project ID for building function URLs
 */
export function configureAlerts(apiUrl) {
  acknowledgeUrl = `${apiUrl}/api/alert/acknowledge`;

  // Set up emergency overlay event listeners
  const ackBtn = document.getElementById("btn-emergency-ack");
  const dismissBtn = document.getElementById("btn-emergency-dismiss");

  if (ackBtn) {
    ackBtn.addEventListener("click", () => {
      if (activeEmergencyId) {
        acknowledgeAlert(activeEmergencyId);
        hideEmergencyOverlay();
      }
    });
  }

  if (dismissBtn) {
    dismissBtn.addEventListener("click", hideEmergencyOverlay);
  }
}

/**
 * Update the alerts list with new data.
 *
 * @param {Array<Object>} alerts - Array of alert objects from Firestore
 */
export function updateAlerts(alerts) {
  const container = document.getElementById("alerts-list");
  const countBadge = document.getElementById("alerts-count");

  if (!container) return;

  // Sort: pending first, then by triggered_at descending
  const sorted = [...alerts].sort((a, b) => {
    if (a.status === "pending" && b.status !== "pending") return -1;
    if (a.status !== "pending" && b.status === "pending") return 1;
    return (b.triggered_at || 0) - (a.triggered_at || 0);
  });

  // Update count badge (only pending alerts)
  const pendingCount = sorted.filter((a) => a.status === "pending").length;
  if (countBadge) countBadge.textContent = pendingCount;

  // Check for new emergency alerts to show overlay
  for (const alert of sorted) {
    const prevAlert = alertsMap.get(alert.id);
    if (
      alert.severity === "emergency" &&
      alert.status === "pending" &&
      (!prevAlert || prevAlert.status !== "pending")
    ) {
      showEmergencyOverlay(alert);
    }
    alertsMap.set(alert.id, alert);
  }

  // Render alert cards
  if (sorted.length === 0) {
    container.innerHTML = `
      <div class="empty-state">
        <div class="empty-state__icon">✅</div>
        <div class="empty-state__text">All clear<br/>No pending alerts</div>
      </div>
    `;
    return;
  }

  container.innerHTML = sorted.map((alert) => renderAlertCard(alert)).join("");

  // Attach acknowledge button listeners
  container.querySelectorAll("[data-ack-id]").forEach((btn) => {
    btn.addEventListener("click", (e) => {
      e.stopPropagation();
      const alertId = btn.dataset.ackId;
      acknowledgeAlert(alertId);
    });
  });

  // Attach click-to-focus listeners
  container.querySelectorAll("[data-device-focus]").forEach((card) => {
    card.addEventListener("click", () => {
      const deviceId = card.dataset.deviceFocus;
      if (deviceId) focusOnDevice(deviceId);
    });
  });
}

/**
 * Render a single alert card HTML.
 */
function renderAlertCard(alert) {
  const timeAgo = getTimeAgo(alert.triggered_at);
  const isAcked = alert.status === "acknowledged";
  const severityClass = isAcked ? "acknowledged" : alert.severity;

  return `
    <div class="alert-card alert-card--${severityClass} animate-fade-in"
         data-device-focus="${alert.device_id || ""}">
      <div class="alert-card__header">
        <span class="alert-card__severity alert-card__severity--${alert.severity}">
          ${alert.severity === "emergency" ? "🔴" : "🟡"} ${(alert.severity || "").toUpperCase()}
        </span>
        <span class="alert-card__time">${timeAgo}</span>
      </div>
      <div class="alert-card__body">
        Device <span class="alert-card__device">${alert.device_id || "Unknown"}</span>
        — ${alert.time_since_last_heartbeat || "?"}s since last heartbeat
        <div class="alert-card__info">
          <span>👤 ${alert.user_id || "Unknown"}</span>
          <span>🏊 ${alert.activity_type || "Unknown"}</span>
          <span>🔋 ${alert.last_battery_level >= 0 ? alert.last_battery_level + "%" : "N/A"}</span>
        </div>
      </div>
      ${
        !isAcked
          ? `<button class="btn-acknowledge" data-ack-id="${alert.id}" type="button">
               ✓ Acknowledge
             </button>`
          : `<span style="font-size: 0.72rem; color: var(--text-muted);">
               ✓ Acknowledged by ${alert.acknowledged_by || "operator"} 
             </span>`
      }
    </div>
  `;
}

/**
 * Show the emergency overlay modal for a critical alert.
 */
function showEmergencyOverlay(alert) {
  const overlay = document.getElementById("emergency-overlay");
  const details = document.getElementById("emergency-details");

  if (!overlay || !details) return;

  activeEmergencyId = alert.id;

  details.innerHTML = `
    <strong>Device:</strong> ${alert.device_id || "Unknown"}<br/>
    <strong>User:</strong> ${alert.user_id || "Unknown"}<br/>
    <strong>Activity:</strong> ${alert.activity_type || "Unknown"}<br/>
    <strong>Last Heartbeat:</strong> ${alert.time_since_last_heartbeat || "?"}s ago<br/>
    <strong>Battery:</strong> ${alert.last_battery_level >= 0 ? alert.last_battery_level + "%" : "N/A"}<br/>
    ${alert.last_known_gps ? `<strong>Location:</strong> ${alert.last_known_gps.lat?.toFixed(4)}, ${alert.last_known_gps.lng?.toFixed(4)}` : ""}
  `;

  overlay.classList.add("active");

  // Play alert sound (Web Audio API)
  playAlertSound();
}

/**
 * Hide the emergency overlay modal.
 */
function hideEmergencyOverlay() {
  const overlay = document.getElementById("emergency-overlay");
  if (overlay) overlay.classList.remove("active");
  activeEmergencyId = null;
}

/**
 * Acknowledge an alert by calling the Cloud Function.
 */
async function acknowledgeAlert(alertId) {
  try {
    // Update local state immediately for instant UI feedback (especially in demo mode)
    const alert = alertsMap.get(alertId);
    if (alert) {
      alert.status = "acknowledged";
      alert.acknowledged_by = "lifeguard_portal";
      
      // Update the DOM for this specific alert card
      const btn = document.querySelector(`[data-ack-id="${alertId}"]`);
      if (btn) {
        const card = btn.closest('.alert-card');
        if (card) {
          card.classList.remove('alert-card--emergency', 'alert-card--warning');
          card.classList.add('alert-card--acknowledged');
          btn.outerHTML = `<span style="font-size: 0.72rem; color: var(--text-muted);">✓ Acknowledged by lifeguard_portal</span>`;
        }
      }
    }

    const response = await fetch(acknowledgeUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        alert_id: alertId,
        acknowledged_by: "lifeguard_portal",
      }),
    });

    if (response.ok) {
      console.log(`Alert ${alertId} acknowledged successfully`);
    } else {
      console.error(`Failed to acknowledge alert ${alertId}:`, response.status);
    }
  } catch (error) {
    console.error("Error acknowledging alert:", error);
  }
}

/**
 * Play an alert sound using the Web Audio API.
 */
function playAlertSound() {
  try {
    const ctx = new (window.AudioContext || window.webkitAudioContext)();

    // Create a repeating alarm tone
    for (let i = 0; i < 3; i++) {
      const oscillator = ctx.createOscillator();
      const gainNode = ctx.createGain();

      oscillator.connect(gainNode);
      gainNode.connect(ctx.destination);

      oscillator.type = "sine";
      oscillator.frequency.value = 880; // A5 note

      gainNode.gain.setValueAtTime(0.3, ctx.currentTime + i * 0.4);
      gainNode.gain.exponentialRampToValueAtTime(
        0.01,
        ctx.currentTime + i * 0.4 + 0.3
      );

      oscillator.start(ctx.currentTime + i * 0.4);
      oscillator.stop(ctx.currentTime + i * 0.4 + 0.3);
    }
  } catch (e) {
    // Audio might be blocked by browser autoplay policy
    console.warn("Could not play alert sound:", e);
  }
}

/**
 * Format a timestamp into a human-readable "time ago" string.
 */
function getTimeAgo(timestamp) {
  if (!timestamp) return "Unknown";

  const seconds = Math.floor((Date.now() - timestamp) / 1000);

  if (seconds < 10) return "Just now";
  if (seconds < 60) return `${seconds}s ago`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`;
  return `${Math.floor(seconds / 86400)}d ago`;
}

/**
 * Get the count of pending (unacknowledged) alerts.
 */
export function getPendingAlertCount() {
  let count = 0;
  for (const alert of alertsMap.values()) {
    if (alert.status === "pending") count++;
  }
  return count;
}
