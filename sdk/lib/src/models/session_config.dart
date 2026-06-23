/// Configuration parameters for opening a new monitoring session.
///
/// Passed to [HeartbeatSDK.openSession] to initialize a session
/// with user-specific data and activity context.
class SessionConfig {
  /// Unique user identifier for this session.
  final String userId;

  /// Age of the user. Must be >= 18 for session to be valid.
  /// The SDK is calibrated for monitoring users aged 18 and older.
  final int userAge;

  /// Type of activity being monitored.
  /// Examples: 'swimming', 'surfing', 'walking', 'diving', 'running'.
  final String activityType;

  /// Optional metadata key-value pairs for additional context.
  final Map<String, dynamic>? metadata;

  SessionConfig({
    required this.userId,
    required this.userAge,
    required this.activityType,
    this.metadata,
  });

  /// Validates the session configuration.
  /// Returns `null` if valid, or an error message string if invalid.
  String? validate() {
    if (userId.trim().isEmpty) {
      return 'User ID cannot be empty';
    }
    if (userAge < 18) {
      return 'User must be 18 or older. Got age: $userAge';
    }
    if (activityType.trim().isEmpty) {
      return 'Activity type cannot be empty';
    }
    return null; // Valid
  }

  /// Serialize to JSON for storage or transmission.
  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'user_age': userAge,
      'activity_type': activityType,
      if (metadata != null) 'metadata': metadata,
    };
  }

  /// Deserialize from JSON.
  factory SessionConfig.fromJson(Map<String, dynamic> json) {
    return SessionConfig(
      userId: json['user_id'] as String,
      userAge: json['user_age'] as int,
      activityType: json['activity_type'] as String,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  @override
  String toString() {
    return 'SessionConfig(userId=$userId, age=$userAge, activity=$activityType)';
  }
}
