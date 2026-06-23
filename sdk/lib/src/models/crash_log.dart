/// Data model for crash log entries captured before device shutdown.
///
/// When an unexpected crash occurs, the SDK catches the error moments
/// before the app closes and saves this log to local memory. On next
/// boot, the SDK retrieves and transmits it to the server.
class CrashLog {
  /// Unique identifier for this crash report.
  final String reportId;

  /// Device ID where the crash occurred.
  final String deviceId;

  /// Active session ID at the time of crash, if any.
  final String? sessionId;

  /// The error message captured from the exception.
  final String errorMessage;

  /// Full stack trace string.
  final String stackTrace;

  /// UTC timestamp of when the crash occurred (ms since epoch).
  final int crashTimestamp;

  /// Snapshot of device state at crash time.
  final DeviceState? deviceState;

  /// SDK version at the time of crash.
  final String sdkVersion;

  CrashLog({
    required this.reportId,
    required this.deviceId,
    this.sessionId,
    required this.errorMessage,
    required this.stackTrace,
    required this.crashTimestamp,
    this.deviceState,
    this.sdkVersion = '1.0.0',
  });

  /// Serialize to JSON for local storage and server transmission.
  Map<String, dynamic> toJson() {
    return {
      'report_id': reportId,
      'device_id': deviceId,
      if (sessionId != null) 'session_id': sessionId,
      'error_message': errorMessage,
      'stack_trace': stackTrace,
      'crash_timestamp': crashTimestamp,
      if (deviceState != null) 'device_state': deviceState!.toJson(),
      'sdk_version': sdkVersion,
    };
  }

  /// Deserialize from JSON (used when loading saved crash logs on next boot).
  factory CrashLog.fromJson(Map<String, dynamic> json) {
    return CrashLog(
      reportId: json['report_id'] as String,
      deviceId: json['device_id'] as String,
      sessionId: json['session_id'] as String?,
      errorMessage: json['error_message'] as String,
      stackTrace: json['stack_trace'] as String,
      crashTimestamp: json['crash_timestamp'] as int,
      deviceState: json['device_state'] != null
          ? DeviceState.fromJson(json['device_state'] as Map<String, dynamic>)
          : null,
      sdkVersion: json['sdk_version'] as String? ?? '1.0.0',
    );
  }

  @override
  String toString() {
    return 'CrashLog(id=$reportId, device=$deviceId, error=$errorMessage)';
  }
}

/// Snapshot of the device state captured at crash time for diagnostics.
class DeviceState {
  /// Battery level at crash time (0-100).
  final int? batteryLevel;

  /// Whether the device was online at crash time.
  final bool? isOnline;

  /// Number of heartbeats in the offline queue at crash time.
  final int? queuedHeartbeats;

  /// Uptime in seconds since session was opened.
  final int? sessionUptime;

  const DeviceState({
    this.batteryLevel,
    this.isOnline,
    this.queuedHeartbeats,
    this.sessionUptime,
  });

  Map<String, dynamic> toJson() {
    return {
      if (batteryLevel != null) 'battery_level': batteryLevel,
      if (isOnline != null) 'is_online': isOnline,
      if (queuedHeartbeats != null) 'queued_heartbeats': queuedHeartbeats,
      if (sessionUptime != null) 'session_uptime': sessionUptime,
    };
  }

  factory DeviceState.fromJson(Map<String, dynamic> json) {
    return DeviceState(
      batteryLevel: json['battery_level'] as int?,
      isOnline: json['is_online'] as bool?,
      queuedHeartbeats: json['queued_heartbeats'] as int?,
      sessionUptime: json['session_uptime'] as int?,
    );
  }
}
