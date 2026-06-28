/**
 * Map Module — Leaflet.js integration for the dashboard.
 *
 * Renders an interactive map centered on the Tel Aviv coastline with:
 * - Device markers (color-coded by status: green/yellow/red)
 * - Auto-updating positions on data changes
 * - Custom popup info windows
 */

/** @type {L.Map} */
let map = null;

/** @type {Map<string, L.Marker>} Device markers indexed by device_id */
const deviceMarkers = new Map();

// Tel Aviv coastline center
const TEL_AVIV_CENTER = [32.0780, 34.7680];
const DEFAULT_ZOOM = 14;

/**
 * Initialize the Leaflet map.
 */
export function initMap() {
  map = L.map("map", {
    center: TEL_AVIV_CENTER,
    zoom: DEFAULT_ZOOM,
    zoomControl: true,
    attributionControl: true,
  });

  // Dark-themed map tiles (CartoDB Dark Matter)
  L.tileLayer(
    "https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png",
    {
      attribution:
        '&copy; <a href="https://www.openstreetmap.org/copyright">OSM</a> &copy; <a href="https://carto.com/">CARTO</a>',
      subdomains: "abcd",
      maxZoom: 19,
    }
  ).addTo(map);

  // Fix Leaflet rendering in hidden/resized containers
  setTimeout(() => map.invalidateSize(), 250);

  return map;
}

/**
 * Create a custom device marker icon based on status.
 */
function createDeviceIcon(status) {
  const colors = {
    normal: "#22c55e",
    warning: "#f59e0b",
    emergency: "#ef4444",
  };

  const color = colors[status] || colors.normal;

  return L.divIcon({
    className: `device-marker device-marker--${status}`,
    html: "⌚",
    iconSize: [32, 32],
    iconAnchor: [16, 16],
    popupAnchor: [0, -20],
  });
}

/**
 * Update device markers on the map.
 *
 * @param {Array<Object>} sessions - Array of device session objects
 */
export function updateDeviceMarkers(sessions) {
  if (!map) return;

  // Track which devices are still active
  const activeDeviceIds = new Set();

  for (const session of sessions) {
    if (!session.gps) continue;

    const { device_id, gps, current_status, user_id, activity_type, battery_level } = session;
    activeDeviceIds.add(device_id);

    const latLng = [gps.lat, gps.lng];

    if (deviceMarkers.has(device_id)) {
      // Update existing marker
      const marker = deviceMarkers.get(device_id);
      marker.setLatLng(latLng);
      marker.setIcon(createDeviceIcon(current_status));
      marker.setPopupContent(createDevicePopup(session));
    } else {
      // Create new marker
      const marker = L.marker(latLng, {
        icon: createDeviceIcon(current_status),
      })
        .bindPopup(createDevicePopup(session))
        .addTo(map);

      deviceMarkers.set(device_id, marker);
    }
  }

  // Remove markers for devices that are no longer active
  for (const [deviceId, marker] of deviceMarkers) {
    if (!activeDeviceIds.has(deviceId)) {
      map.removeLayer(marker);
      deviceMarkers.delete(deviceId);
    }
  }
}

/**
 * Create popup content for a device marker.
 */
function createDevicePopup(session) {
  const statusEmoji = {
    normal: "🟢",
    warning: "🟡",
    emergency: "🔴",
  };

  return `
    <div class="popup-title">${statusEmoji[session.current_status] || "⚪"} ${session.device_id}</div>
    <div class="popup-detail">
      <strong>User:</strong> ${session.user_id || "Unknown"}<br/>
      <strong>Activity:</strong> ${session.activity_type || "Unknown"}<br/>
      <strong>Status:</strong> ${(session.current_status || "unknown").toUpperCase()}<br/>
      <strong>Battery:</strong> ${session.battery_level >= 0 ? session.battery_level + "%" : "N/A"}<br/>
      <strong>GPS:</strong> ${session.gps?.lat?.toFixed(4)}, ${session.gps?.lng?.toFixed(4)}
    </div>
  `;
}

/**
 * Pan the map to focus on a specific device.
 */
export function focusOnDevice(deviceId) {
  const marker = deviceMarkers.get(deviceId);
  if (marker && map) {
    map.setView(marker.getLatLng(), 16, { animate: true });
    marker.openPopup();
  }
}

/**
 * Resize the map (call after container resize).
 */
export function resizeMap() {
  if (map) {
    map.invalidateSize();
  }
}
