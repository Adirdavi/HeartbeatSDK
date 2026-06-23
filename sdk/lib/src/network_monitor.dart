import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Monitors network connectivity state at the OS level.
///
/// Uses the `connectivity_plus` plugin to detect when the smartwatch
/// gains or loses network access. This is critical for the offline-first
/// architecture: when connectivity drops, heartbeats are queued locally;
/// when it resumes, the offline queue is flushed.
class NetworkMonitor {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  /// Current network connectivity state.
  bool _isOnline = true;

  /// Whether the device currently has network connectivity.
  bool get isOnline => _isOnline;

  /// Callback invoked when the device comes back online.
  /// Used by the SDK to trigger offline queue flush.
  void Function()? onConnectivityRestored;

  /// Callback invoked when the device loses connectivity.
  /// Used by the SDK to switch to offline queueing mode.
  void Function()? onConnectivityLost;

  /// Start listening to network state changes.
  ///
  /// This should be called during SDK initialization. The listener
  /// operates at the OS level, detecting WiFi, cellular, and
  /// Bluetooth tethering changes on the smartwatch.
  Future<void> startMonitoring() async {
    // Check initial connectivity state
    final results = await _connectivity.checkConnectivity();
    _updateState(results);

    // Listen for changes
    _subscription = _connectivity.onConnectivityChanged.listen(
      _updateState,
      onError: (error) {
        // Assume offline on error — safer for life-safety systems
        _isOnline = false;
        onConnectivityLost?.call();
      },
    );
  }

  /// Stop listening to network state changes.
  ///
  /// Called during SDK cleanup (session close or app shutdown).
  Future<void> stopMonitoring() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  /// Process connectivity result updates from the OS.
  void _updateState(List<ConnectivityResult> results) {
    final wasOnline = _isOnline;

    // Device is online if any connectivity result is not 'none'
    _isOnline = results.any(
      (result) => result != ConnectivityResult.none,
    );

    // Detect state transitions
    if (!wasOnline && _isOnline) {
      // Just came back online — trigger queue flush
      onConnectivityRestored?.call();
    } else if (wasOnline && !_isOnline) {
      // Just went offline — switch to queueing mode
      onConnectivityLost?.call();
    }
  }

  /// Dispose of resources. Must be called when the SDK is done.
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    onConnectivityRestored = null;
    onConnectivityLost = null;
  }
}
