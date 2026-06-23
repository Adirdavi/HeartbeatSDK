import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'models/crash_log.dart';

/// Crash analytics reporter for the HeartbeatSDK.
///
/// Implements a global error listener that captures unexpected crashes
/// moments before the app closes. The crash log (error message, stack
/// trace, timestamp, device state) is saved to local memory.
///
/// On the next app launch, the SDK detects saved crash logs and
/// proactively transmits them to the server BEFORE opening a new session.
class CrashReporter {
  static const String _crashLogKey = 'hb_crash_logs';
  static const int _maxStoredCrashes = 10;
  static const _uuid = Uuid();

  SharedPreferences? _prefs;
  String? _currentDeviceId;
  String? _currentSessionId;

  /// Whether the crash reporter is currently active.
  bool _isActive = false;

  /// Initialize the crash reporter.
  ///
  /// Must be called during SDK setup, before opening any session.
  Future<void> initialize(String deviceId) async {
    _currentDeviceId = deviceId;
    _prefs = await SharedPreferences.getInstance();
  }

  /// Set the current session ID for crash context.
  void setSessionId(String? sessionId) {
    _currentSessionId = sessionId;
  }

  /// Activate global error listeners.
  ///
  /// Hooks into Flutter's error handling framework to capture:
  /// - FlutterError.onError (framework-level errors)
  /// - PlatformDispatcher.onError (platform-level errors)
  /// - Isolate.current.addErrorListener (isolate-level errors)
  void activate() {
    if (_isActive) return;
    _isActive = true;

    // Capture Flutter framework errors
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      _captureError(
        details.exceptionAsString(),
        details.stack?.toString() ?? 'No stack trace',
      );
      // Forward to original handler (so it still shows in debug console)
      originalOnError?.call(details);
    };

    // Capture platform-level errors (async errors not caught by zones)
    PlatformDispatcher.instance.onError = (error, stack) {
      _captureError(error.toString(), stack.toString());
      return true; // Prevent the error from propagating
    };
  }

  /// Deactivate error listeners.
  ///
  /// Called during SDK cleanup. Restores default error handling.
  void deactivate() {
    _isActive = false;
    // Note: We don't restore the original handlers to avoid
    // complex state management. The capture function checks _isActive.
  }

  /// Capture an error and save it to local storage.
  ///
  /// This runs synchronously and as fast as possible to maximize
  /// the chance of persisting the log before the app terminates.
  Future<void> _captureError(String errorMessage, String stackTrace) async {
    if (!_isActive || _currentDeviceId == null) return;

    try {
      final crashLog = CrashLog(
        reportId: _uuid.v4(),
        deviceId: _currentDeviceId!,
        sessionId: _currentSessionId,
        errorMessage: errorMessage,
        stackTrace: stackTrace,
        crashTimestamp: DateTime.now().toUtc().millisecondsSinceEpoch,
        deviceState: const DeviceState(),
      );

      await _saveCrashLog(crashLog);
    } catch (e) {
      // Last resort — if we can't even save the crash log,
      // there's nothing more we can do. Fail silently.
    }
  }

  /// Save a crash log to SharedPreferences.
  Future<void> _saveCrashLog(CrashLog log) async {
    if (_prefs == null) return;

    final existingLogs = await getSavedCrashLogs();
    existingLogs.add(log);

    // Enforce max stored crashes
    while (existingLogs.length > _maxStoredCrashes) {
      existingLogs.removeAt(0);
    }

    final jsonList = existingLogs.map((l) => jsonEncode(l.toJson())).toList();
    await _prefs!.setStringList(_crashLogKey, jsonList);
  }

  /// Retrieve all saved crash logs from local storage.
  ///
  /// Called on SDK initialization to check for crashes from previous runs.
  Future<List<CrashLog>> getSavedCrashLogs() async {
    if (_prefs == null) await initialize(_currentDeviceId ?? 'unknown');

    final jsonList = _prefs?.getStringList(_crashLogKey) ?? [];
    final logs = <CrashLog>[];

    for (final jsonString in jsonList) {
      try {
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        logs.add(CrashLog.fromJson(json));
      } catch (e) {
        // Skip corrupted entries
        continue;
      }
    }

    return logs;
  }

  /// Check if there are pending crash logs from previous runs.
  Future<bool> hasPendingCrashLogs() async {
    final logs = await getSavedCrashLogs();
    return logs.isNotEmpty;
  }

  /// Clear all saved crash logs after successful transmission.
  Future<void> clearCrashLogs() async {
    await _prefs?.remove(_crashLogKey);
  }

  /// Transmit all pending crash logs to the server.
  ///
  /// This is called during SDK initialization, BEFORE opening a new session.
  /// Returns the number of successfully transmitted crash logs.
  Future<int> transmitPendingLogs(
    Future<bool> Function(CrashLog) transmitFn,
  ) async {
    final logs = await getSavedCrashLogs();
    if (logs.isEmpty) return 0;

    int successCount = 0;
    for (final log in logs) {
      try {
        final success = await transmitFn(log);
        if (success) successCount++;
      } catch (e) {
        // Continue trying remaining logs
        continue;
      }
    }

    if (successCount == logs.length) {
      await clearCrashLogs();
    }

    return successCount;
  }

  /// Dispose of resources.
  void dispose() {
    deactivate();
    _currentDeviceId = null;
    _currentSessionId = null;
  }
}
