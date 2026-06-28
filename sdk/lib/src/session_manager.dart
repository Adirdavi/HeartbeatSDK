import 'package:uuid/uuid.dart';

import 'models/session_config.dart';

/// Manages the lifecycle of monitoring sessions.
///
/// Responsible for:
/// - Creating new session IDs (UUID v4)
/// - Validating session parameters (age >= 18, required fields)
/// - Tracking session state (idle, active, closing)
/// - Recording session start/end timestamps
class SessionManager {
  static const _uuid = Uuid();

  /// Current session state.
  SessionState _state = SessionState.idle;

  /// Current session ID (null when no session is active).
  String? _sessionId;

  /// Configuration for the current session.
  SessionConfig? _config;

  /// Timestamp when the current session was opened (ms since epoch).
  int? _sessionStartTime;

  /// Current session state.
  SessionState get state => _state;

  /// Current session ID, or null if no session is active.
  String? get sessionId => _sessionId;

  /// Current session configuration, or null if no session is active.
  SessionConfig? get config => _config;

  /// Session start timestamp, or null if no session is active.
  int? get sessionStartTime => _sessionStartTime;

  /// Whether a session is currently active.
  bool get isActive => _state == SessionState.active;

  /// Open a new monitoring session.
  ///
  /// Validates the [config] parameters (user must be >= 18 years old),
  /// generates a new UUID v4 session ID, and transitions to active state.
  ///
  /// Throws [SessionException] if:
  /// - A session is already active
  /// - The configuration is invalid (age < 18, empty fields)
  ///
  /// Returns the generated session ID.
  String openSession(SessionConfig config) {
    // Prevent opening a session while one is already active
    if (_state == SessionState.active) {
      throw SessionException(
        'Cannot open a new session while one is active. '
        'Close the current session first. Current session: $_sessionId',
      );
    }

    // Validate configuration
    final validationError = config.validate();
    if (validationError != null) {
      throw SessionException(validationError);
    }

    // Generate session ID and activate
    _sessionId = _uuid.v4();
    _config = config;
    _sessionStartTime = DateTime.now().toUtc().millisecondsSinceEpoch;
    _state = SessionState.active;

    return _sessionId!;
  }

  /// Close the current session.
  ///
  /// Records the session end time and transitions to idle state.
  /// Returns session summary data for final transmission.
  ///
  /// Throws [SessionException] if no session is active.
  Map<String, dynamic> closeSession() {
    if (_state != SessionState.active) {
      throw SessionException(
        'No active session to close. Current state: $_state',
      );
    }

    _state = SessionState.closing;

    final endTime = DateTime.now().toUtc().millisecondsSinceEpoch;
    final summary = {
      'session_id': _sessionId,
      'user_id': _config?.userId,
      'activity_type': _config?.activityType,
      'session_start': _sessionStartTime,
      'session_end': endTime,
      'duration_ms': endTime - (_sessionStartTime ?? endTime),
    };

    // Reset state
    _sessionId = null;
    _config = null;
    _sessionStartTime = null;
    _state = SessionState.idle;

    return summary;
  }

  /// Get the session uptime in seconds.
  ///
  /// Returns 0 if no session is active.
  int get sessionUptime {
    if (_sessionStartTime == null) return 0;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    return ((now - _sessionStartTime!) / 1000).round();
  }

  /// Reset the session manager to idle state (used for error recovery).
  void reset() {
    _state = SessionState.idle;
    _sessionId = null;
    _config = null;
    _sessionStartTime = null;
  }
}

/// Possible states of a monitoring session.
enum SessionState {
  /// No active session.
  idle,

  /// Session is active and heartbeats are being transmitted.
  active,

  /// Session is in the process of closing (final flush in progress).
  closing,
}

/// Exception thrown for session lifecycle errors.
class SessionException implements Exception {
  final String message;

  const SessionException(this.message);

  @override
  String toString() => 'SessionException: $message';
}
