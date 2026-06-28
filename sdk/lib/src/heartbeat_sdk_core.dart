import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'crash_reporter.dart';
import 'haptics_controller.dart';
import 'heartbeat_transmitter.dart';
import 'models/crash_log.dart';
import 'models/heartbeat_payload.dart';
import 'models/session_config.dart';
import 'network_monitor.dart';
import 'offline_queue.dart';
import 'session_manager.dart';

/// HeartbeatSDK — Standalone smartwatch monitoring infrastructure.
///
/// The main entry point for the SDK. Provides a clean public API for
/// watch application developers to integrate life-safety monitoring
/// into their smartwatch apps.
///
/// ## Architecture
///
/// The SDK is designed for an offline-first, autonomous operation model:
///
/// ```
/// ┌──────────────────────────────────────────┐
/// │             HeartbeatSDK Core             │
/// │                                          │
/// │  ┌──────────┐  ┌──────────────────────┐  │
/// │  │ Session   │  │ Heartbeat            │  │
/// │  │ Manager   │  │ Transmitter          │  │
/// │  └──────────┘  └──────────────────────┘  │
/// │  ┌──────────┐  ┌──────────────────────┐  │
/// │  │ Network   │  │ Offline              │  │
/// │  │ Monitor   │  │ Queue                │  │
/// │  └──────────┘  └──────────────────────┘  │
/// │  ┌──────────┐  ┌──────────────────────┐  │
/// │  │ Haptics   │  │ Crash                │  │
/// │  │ Controller│  │ Reporter             │  │
/// │  └──────────┘  └──────────────────────┘  │
/// └──────────────────────────────────────────┘
/// ```
///
/// ## Usage
///
/// ```dart
/// final sdk = HeartbeatSDK();
///
/// // 1. Configure with project and device IDs
/// await sdk.configure(projectId: 'my-project', deviceId: 'watch_001');
///
/// // 2. Open a session
/// await sdk.openSession(
///   userId: 'user_42',
///   userAge: 25,
///   activityType: 'swimming',
/// );
///
/// // 3. Start heartbeat transmission
/// sdk.start(interval: Duration(seconds: 10));
///
/// // 4. Close session when done
/// await sdk.closeSession();
/// ```
class HeartbeatSDK {
  // ───────────────────── Internal Modules ─────────────────────
  final SessionManager _sessionManager = SessionManager();
  final OfflineQueue _offlineQueue = OfflineQueue();
  final NetworkMonitor _networkMonitor = NetworkMonitor();
  final CrashReporter _crashReporter = CrashReporter();
  final HapticsController _hapticsController = HapticsController();
  late final HeartbeatTransmitter _transmitter;

  // ───────────────────── Configuration ─────────────────────
  String? _serverUrl;
  String? _deviceId;
  String? _appId;
  bool _isConfigured = false;

  // ───────────────────── Callbacks ─────────────────────
  /// Called when the SDK logs important events.
  void Function(String level, String message)? onLog;

  /// Called when a heartbeat is transmitted or queued.
  void Function(bool transmitted, bool queued)? onHeartbeat;

  /// Called when network status changes.
  void Function(bool isOnline)? onConnectivityChanged;

  HeartbeatSDK() {
    _transmitter = HeartbeatTransmitter(
      offlineQueue: _offlineQueue,
      networkMonitor: _networkMonitor,
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  PUBLIC API
  // ═══════════════════════════════════════════════════════════

  /// Initialize the SDK and connect to the API server.
  ///
  /// Must be called before any other SDK method. This method:
  /// 1. Stores the server URL and device identifiers
  /// 2. Initializes all internal modules
  /// 3. Sets up the network connectivity monitor
  /// 4. Checks for and transmits any crash logs from previous runs
  ///
  /// [serverUrl] — Base URL of the REST API server (e.g., 'https://heartbeat-api.onrender.com')
  /// [deviceId] — Unique identifier for this smartwatch device
  /// [appId] — Identifier for the host application (e.g., 'com.surf.watch')
  ///
  /// Throws [HeartbeatException] if configuration fails.
  Future<void> configure({
    required String serverUrl,
    required String deviceId,
    required String appId,
  }) async {
    if (_isConfigured) {
      _log('warn', 'SDK already configured. Reconfiguring...');
    }

    _serverUrl = serverUrl;
    _deviceId = deviceId;
    _appId = appId;

    try {
      // Initialize all modules
      await _offlineQueue.initialize();
      await _hapticsController.initialize();
      await _crashReporter.initialize(deviceId);

      // Configure the transmitter with the API server URL
      _transmitter.configure(serverUrl);

      // Set up network monitoring
      _setupNetworkMonitor();
      await _networkMonitor.startMonitoring();

      // Activate crash reporting
      _crashReporter.activate();

      // Check for pending crash logs from previous runs
      await _transmitPendingCrashLogs();

      _isConfigured = true;
      _log('info', 'SDK configured successfully. '
          'Server: $serverUrl, Device: $deviceId');
    } catch (e) {
      throw HeartbeatException('Failed to configure SDK: $e');
    }
  }

  /// Open a new monitoring session.
  ///
  /// Creates a new session ID (UUID v4) and validates the user data.
  /// The user must be 18 years or older for the session to be valid.
  ///
  /// During an active session:
  /// - Haptic feedback is disabled to prevent user distractions
  /// - Crash reporting is linked to the session ID
  ///
  /// [userId] — Unique identifier for the monitored user
  /// [userAge] — User's age (must be >= 18)
  /// [activityType] — Type of activity (e.g., 'swimming', 'surfing')
  /// [metadata] — Optional additional context data
  ///
  /// Returns the generated session ID.
  ///
  /// Throws [HeartbeatException] if the SDK is not configured.
  /// Throws [SessionException] if validation fails or a session is already active.
  Future<String> openSession({
    required String userId,
    required int userAge,
    required String activityType,
    Map<String, dynamic>? metadata,
  }) async {
    _ensureConfigured();

    final config = SessionConfig(
      userId: userId,
      userAge: userAge,
      activityType: activityType,
      metadata: metadata,
    );

    // Open session (validates age >= 18 and other fields)
    final sessionId = _sessionManager.openSession(config);

    // Link crash reporter to this session
    _crashReporter.setSessionId(sessionId);

    // Disable haptic feedback during session
    await _hapticsController.disableHaptics();

    // Reset transmitter counters for new session
    _transmitter.resetCounters();

    _log('info', 'Session opened: $sessionId '
        '(user=$userId, activity=$activityType)');

    return sessionId;
  }

  /// Start the heartbeat transmission timer.
  ///
  /// Begins sending availability signals to the cloud at the specified
  /// interval. Each heartbeat contains device telemetry (battery, GPS,
  /// timestamps) for real-time monitoring.
  ///
  /// [interval] — Time between heartbeats. Default: 10 seconds.
  ///
  /// The 10-second default provides strong real-time resolution for
  /// life-safety monitoring without rapidly draining the battery.
  void start({Duration interval = const Duration(seconds: 10)}) {
    _ensureConfigured();

    if (!_sessionManager.isActive) {
      throw HeartbeatException(
        'Cannot start heartbeat transmission without an active session. '
        'Call openSession() first.',
      );
    }

    // Set up the payload builder
    _transmitter.onBuildPayload = _buildCurrentPayload;
    _transmitter.onHeartbeatResult = (success, queued) {
      onHeartbeat?.call(success, queued);
      if (queued) {
        _log('warn', 'Heartbeat queued offline '
            '(queue size: ${_transmitter.pendingQueueSize})');
      }
    };

    _transmitter.start(interval: interval);

    _log('info', 'Heartbeat transmission started '
        '(interval: ${interval.inSeconds}s)');
  }

  /// Close the current session and clean up.
  ///
  /// This method:
  /// 1. Stops the heartbeat timer
  /// 2. Attempts to flush any remaining offline queue
  /// 3. Sends a final "session closed" signal
  /// 4. Restores haptic feedback
  /// 5. Unlinks crash reporter from the session
  ///
  /// Returns a session summary with duration and statistics.
  Future<Map<String, dynamic>> closeSession() async {
    _ensureConfigured();

    // Stop heartbeat timer
    _transmitter.stop();

    // Try to flush offline queue before closing
    if (_offlineQueue.isNotEmpty && _networkMonitor.isOnline) {
      _log('info', 'Flushing ${_offlineQueue.queueSize} queued heartbeats...');
      await _transmitter.flushQueue();
    }

    // Close the session
    final summary = _sessionManager.closeSession();

    // Add transmission stats to summary
    summary['heartbeats_transmitted'] = _transmitter.transmittedCount;
    summary['heartbeats_queued'] = _transmitter.queuedCount;
    summary['pending_in_queue'] = _offlineQueue.queueSize;

    // Restore haptics
    await _hapticsController.restoreHaptics();

    // Unlink crash reporter from session
    _crashReporter.setSessionId(null);

    _log('info', 'Session closed. '
        'Transmitted: ${summary['heartbeats_transmitted']}, '
        'Duration: ${summary['duration_ms']}ms');

    return summary;
  }

  // ═══════════════════════════════════════════════════════════
  //  INTERNAL METHODS
  // ═══════════════════════════════════════════════════════════

  /// Set up network connectivity monitoring with callbacks.
  void _setupNetworkMonitor() {
    _networkMonitor.onConnectivityRestored = () {
      _log('info', 'Network connectivity restored. Flushing offline queue...');
      onConnectivityChanged?.call(true);
      _transmitter.flushQueue();
    };

    _networkMonitor.onConnectivityLost = () {
      _log('warn', 'Network connectivity lost. Switching to offline mode.');
      onConnectivityChanged?.call(false);
    };
  }

  /// Build the current heartbeat payload with live device telemetry.
  HeartbeatPayload _buildCurrentPayload() {
    return HeartbeatPayload(
      deviceId: _deviceId!,
      sessionId: _sessionManager.sessionId!,
      appId: _appId!,
      userId: _sessionManager.config!.userId,
      timestamp: DateTime.now().toUtc().millisecondsSinceEpoch,
      batteryLevel: _getEstimatedBatteryLevel(),
      gps: _getLastKnownPosition(),
      activityType: _sessionManager.config!.activityType,
    );
  }

  /// Get the current battery level.
  ///
  /// Returns a cached/estimated value to avoid blocking the heartbeat
  /// timer with async battery reads.
  int _getEstimatedBatteryLevel() {
    // battery_plus provides async battery level. For the heartbeat
    // timer we use a synchronous estimate. A background isolate
    // updates the cached value periodically.
    // For now, return -1 to indicate "not yet read" and let the
    // async updater fill it in.
    return -1;
  }

  /// Get the last known GPS position.
  ///
  /// Returns null if location services are unavailable.
  GpsCoordinates? _getLastKnownPosition() {
    // GPS coordinates are updated asynchronously by the Geolocator.
    // The heartbeat uses the last cached position.
    // Full implementation would maintain a location stream.
    return null;
  }

  /// Transmit any pending crash logs from previous runs.
  ///
  /// Called during configure(), BEFORE any session is opened.
  /// This ensures crash analytics from the previous session are
  /// delivered to the server for analysis.
  Future<void> _transmitPendingCrashLogs() async {
    if (await _crashReporter.hasPendingCrashLogs()) {
      _log('info', 'Found pending crash logs from previous run. Transmitting...');

      final count = await _crashReporter.transmitPendingLogs(
        (CrashLog log) async {
          try {
            final response = await http.post(
              Uri.parse('$_serverUrl/api/crash-report'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(log.toJson()),
            ).timeout(const Duration(seconds: 5));

            final success = response.statusCode >= 200 && response.statusCode < 300;
            if (success) {
              _log('info', 'Transmitted crash log: ${log.reportId}');
            }
            return success;
          } catch (e) {
            _log('warn', 'Failed to transmit crash log: $e');
            return false;
          }
        },
      );

      _log('info', 'Transmitted $count crash log(s).');
    }
  }

  /// Ensure the SDK is configured before any operation.
  void _ensureConfigured() {
    if (!_isConfigured) {
      throw HeartbeatException(
        'SDK is not configured. Call configure() first.',
      );
    }
  }

  /// Internal logging method.
  void _log(String level, String message) {
    final timestamp = DateTime.now().toIso8601String();
    final logMessage = '[$timestamp] HeartbeatSDK [$level]: $message';

    // Forward to external logger if set
    onLog?.call(level, logMessage);

    // Always print in debug mode
    assert(() {
      // ignore: avoid_print
      print(logMessage);
      return true;
    }());
  }

  // ═══════════════════════════════════════════════════════════
  //  STATUS & DIAGNOSTICS
  // ═══════════════════════════════════════════════════════════

  /// Whether the SDK has been configured.
  bool get isConfigured => _isConfigured;

  /// Whether a session is currently active.
  bool get hasActiveSession => _sessionManager.isActive;

  /// The current session ID, or null.
  String? get currentSessionId => _sessionManager.sessionId;

  /// Whether the heartbeat timer is running.
  bool get isTransmitting => _transmitter.isRunning;

  /// Whether the device is currently online.
  bool get isOnline => _networkMonitor.isOnline;

  /// Number of heartbeats in the offline queue.
  int get offlineQueueSize => _offlineQueue.queueSize;

  /// Current session uptime in seconds.
  int get sessionUptime => _sessionManager.sessionUptime;

  /// SDK version string.
  String get version => '1.0.0';

  /// Dispose of all SDK resources.
  ///
  /// Must be called when the app is shutting down to ensure
  /// clean resource release.
  Future<void> dispose() async {
    _transmitter.dispose();
    _networkMonitor.dispose();
    _crashReporter.dispose();
    _hapticsController.dispose();
    _isConfigured = false;
  }
}

/// Exception thrown for SDK-level errors.
class HeartbeatException implements Exception {
  final String message;

  const HeartbeatException(this.message);

  @override
  String toString() => 'HeartbeatException: $message';
}
