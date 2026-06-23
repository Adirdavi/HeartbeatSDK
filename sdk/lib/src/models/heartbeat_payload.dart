/// Data model representing a single heartbeat transmission payload.
///
/// Contains all telemetry data sent from the smartwatch to the cloud
/// at each heartbeat interval. Designed for efficient serialization
/// and Firestore document mapping.
class HeartbeatPayload {
  /// Unique identifier for the smartwatch device.
  final String deviceId;

  /// Active session identifier (UUID v4).
  final String sessionId;

  /// Identifier of the host application using the SDK (e.g., 'com.example.surfwatch').
  final String appId;

  /// User identifier associated with this session.
  final String userId;

  /// UTC timestamp of when this heartbeat was generated (milliseconds since epoch).
  final int timestamp;

  /// Current battery level as a percentage (0-100).
  final int batteryLevel;

  /// Current heart rate reading from the watch sensor, if available.
  final int? heartRate;

  /// GPS coordinates of the device at the time of heartbeat.
  final GpsCoordinates? gps;

  /// Type of activity being monitored (e.g., 'swimming', 'surfing', 'walking').
  final String activityType;

  /// SDK version string for telemetry and debugging.
  final String sdkVersion;

  HeartbeatPayload({
    required this.deviceId,
    required this.sessionId,
    required this.appId,
    required this.userId,
    required this.timestamp,
    required this.batteryLevel,
    this.heartRate,
    this.gps,
    required this.activityType,
    this.sdkVersion = '1.0.0',
  });

  /// Serialize to a JSON-compatible map for HTTP transmission.
  Map<String, dynamic> toJson() {
    return {
      'device_id': deviceId,
      'session_id': sessionId,
      'app_id': appId,
      'user_id': userId,
      'timestamp': timestamp,
      'battery_level': batteryLevel,
      if (heartRate != null) 'heart_rate': heartRate,
      if (gps != null) 'gps': gps!.toJson(),
      'activity_type': activityType,
      'sdk_version': sdkVersion,
    };
  }

  /// Deserialize from a JSON map (used when loading from offline queue).
  factory HeartbeatPayload.fromJson(Map<String, dynamic> json) {
    return HeartbeatPayload(
      deviceId: json['device_id'] as String,
      sessionId: json['session_id'] as String,
      appId: json['app_id'] as String? ?? 'unknown_app',
      userId: json['user_id'] as String,
      timestamp: json['timestamp'] as int,
      batteryLevel: json['battery_level'] as int,
      heartRate: json['heart_rate'] as int?,
      gps: json['gps'] != null
          ? GpsCoordinates.fromJson(json['gps'] as Map<String, dynamic>)
          : null,
      activityType: json['activity_type'] as String,
      sdkVersion: json['sdk_version'] as String? ?? '1.0.0',
    );
  }

  @override
  String toString() {
    return 'HeartbeatPayload(device=$deviceId, session=$sessionId, '
        'battery=$batteryLevel%, ts=$timestamp)';
  }
}

/// GPS coordinate pair with latitude and longitude.
class GpsCoordinates {
  final double lat;
  final double lng;

  const GpsCoordinates({required this.lat, required this.lng});

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};

  factory GpsCoordinates.fromJson(Map<String, dynamic> json) {
    return GpsCoordinates(
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
    );
  }

  @override
  String toString() => 'GpsCoordinates(lat=$lat, lng=$lng)';
}
