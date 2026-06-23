import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models/heartbeat_payload.dart';
import 'offline_queue.dart';
import 'network_monitor.dart';

/// Manages the heartbeat transmission timer and HTTP delivery.
///
/// Responsible for:
/// - Running a periodic timer at the configured interval
/// - Building heartbeat payloads with current device telemetry
/// - Sending payloads to the Cloud Function endpoint via HTTP POST
/// - Delegating to [OfflineQueue] when the device is offline
/// - Flushing the offline queue when connectivity is restored
class HeartbeatTransmitter {
  final OfflineQueue _offlineQueue;
  final NetworkMonitor _networkMonitor;

  Timer? _heartbeatTimer;
  String? _cloudFunctionUrl;
  bool _isRunning = false;

  /// Callback that builds the current heartbeat payload.
  /// The SDK core provides this with current device state.
  HeartbeatPayload Function()? onBuildPayload;

  /// Callback invoked after each heartbeat attempt with the result.
  void Function(bool success, bool queued)? onHeartbeatResult;

  /// Total heartbeats transmitted in this session.
  int _transmittedCount = 0;

  /// Total heartbeats queued offline in this session.
  int _queuedCount = 0;

  HeartbeatTransmitter({
    required OfflineQueue offlineQueue,
    required NetworkMonitor networkMonitor,
  })  : _offlineQueue = offlineQueue,
        _networkMonitor = networkMonitor;

  /// Configure the target API server URL.
  void configure(String serverUrl) {
    // Custom Express REST API endpoint
    _cloudFunctionUrl = '$serverUrl/api/heartbeat';
  }

  /// Start the heartbeat transmission timer.
  ///
  /// Sends a heartbeat payload at the specified [interval].
  /// Default interval is 10 seconds (optimized for battery life
  /// while maintaining real-time monitoring resolution).
  void start({Duration interval = const Duration(seconds: 10)}) {
    if (_isRunning) return;
    _isRunning = true;

    // Send first heartbeat immediately
    _tick();

    // Then set up periodic timer
    _heartbeatTimer = Timer.periodic(interval, (_) => _tick());
  }

  /// Stop the heartbeat transmission timer.
  void stop() {
    _isRunning = false;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Execute a single heartbeat tick.
  Future<void> _tick() async {
    if (onBuildPayload == null) return;

    final payload = onBuildPayload!();

    if (_networkMonitor.isOnline) {
      // Online — transmit directly
      final success = await _transmitHeartbeat(payload);
      if (success) {
        _transmittedCount++;
        onHeartbeatResult?.call(true, false);

        // Also try to flush any queued payloads
        if (_offlineQueue.isNotEmpty) {
          await _flushOfflineQueue();
        }
      } else {
        // Transmission failed — queue it
        await _handleOfflineState(payload);
      }
    } else {
      // Offline — queue for later
      await _handleOfflineState(payload);
    }
  }

  /// Transmit a single heartbeat payload via HTTP POST.
  ///
  /// Returns `true` if the server responded with 2xx status.
  Future<bool> _transmitHeartbeat(HeartbeatPayload payload) async {
    if (_cloudFunctionUrl == null) return false;

    try {
      final response = await http.post(
        Uri.parse(_cloudFunctionUrl!),
        headers: {
          'Content-Type': 'application/json',
          'X-SDK-Version': payload.sdkVersion,
        },
        body: jsonEncode({'data': payload.toJson()}),
      ).timeout(const Duration(seconds: 5));

      return response.statusCode >= 200 && response.statusCode < 300;
    } on TimeoutException {
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Handle offline state — save payload to local queue.
  Future<void> _handleOfflineState(HeartbeatPayload payload) async {
    await _offlineQueue.enqueue(payload);
    _queuedCount++;
    onHeartbeatResult?.call(false, true);
  }

  /// Flush the offline queue by transmitting all queued payloads.
  ///
  /// Called when connectivity is restored. Payloads are sent in
  /// chronological order to maintain the time-series data integrity.
  Future<void> _flushOfflineQueue() async {
    final flushedCount = await _offlineQueue.flush(_transmitSingle);
    _transmittedCount += flushedCount;
  }

  /// Transmit a single payload (used as callback for queue flush).
  Future<bool> _transmitSingle(HeartbeatPayload payload) async {
    return _transmitHeartbeat(payload);
  }

  /// Trigger an immediate flush of the offline queue.
  ///
  /// Called by the SDK when network connectivity is restored.
  Future<void> flushQueue() async {
    if (_offlineQueue.isNotEmpty) {
      await _flushOfflineQueue();
    }
  }

  /// Whether the transmitter is currently running.
  bool get isRunning => _isRunning;

  /// Total heartbeats successfully transmitted this session.
  int get transmittedCount => _transmittedCount;

  /// Total heartbeats queued offline this session.
  int get queuedCount => _queuedCount;

  /// Number of payloads currently in the offline queue.
  int get pendingQueueSize => _offlineQueue.queueSize;

  /// Reset counters (called when a new session starts).
  void resetCounters() {
    _transmittedCount = 0;
    _queuedCount = 0;
  }

  /// Dispose of resources.
  void dispose() {
    stop();
    onBuildPayload = null;
    onHeartbeatResult = null;
  }
}
