import 'package:flutter_test/flutter_test.dart';
import 'package:heartbeat_sdk/heartbeat_sdk.dart';

void main() {
  group('SessionConfig', () {
    test('validates user age >= 18', () {
      final config = SessionConfig(
        userId: 'user_1',
        userAge: 17,
        activityType: 'swimming',
      );

      expect(config.validate(), isNotNull);
      expect(config.validate(), contains('18 or older'));
    });

    test('accepts valid age >= 18', () {
      final config = SessionConfig(
        userId: 'user_1',
        userAge: 18,
        activityType: 'swimming',
      );

      expect(config.validate(), isNull);
    });

    test('rejects empty user ID', () {
      final config = SessionConfig(
        userId: '',
        userAge: 25,
        activityType: 'swimming',
      );

      expect(config.validate(), isNotNull);
      expect(config.validate(), contains('User ID'));
    });

    test('rejects empty activity type', () {
      final config = SessionConfig(
        userId: 'user_1',
        userAge: 25,
        activityType: '',
      );

      expect(config.validate(), isNotNull);
      expect(config.validate(), contains('Activity type'));
    });

    test('serializes to JSON correctly', () {
      final config = SessionConfig(
        userId: 'user_42',
        userAge: 28,
        activityType: 'surfing',
      );

      final json = config.toJson();
      expect(json['user_id'], equals('user_42'));
      expect(json['user_age'], equals(28));
      expect(json['activity_type'], equals('surfing'));
    });

    test('deserializes from JSON correctly', () {
      final json = {
        'user_id': 'user_42',
        'user_age': 28,
        'activity_type': 'surfing',
      };

      final config = SessionConfig.fromJson(json);
      expect(config.userId, equals('user_42'));
      expect(config.userAge, equals(28));
      expect(config.activityType, equals('surfing'));
    });
  });

  group('HeartbeatPayload', () {
    test('serializes to JSON with all fields', () {
      final payload = HeartbeatPayload(
        deviceId: 'watch_001',
        sessionId: 'sess_abc',
        userId: 'user_1',
        timestamp: 1718745600000,
        batteryLevel: 85,
        heartRate: 72,
        gps: const GpsCoordinates(lat: 32.0853, lng: 34.7818),
        activityType: 'swimming',
      );

      final json = payload.toJson();
      expect(json['device_id'], equals('watch_001'));
      expect(json['session_id'], equals('sess_abc'));
      expect(json['battery_level'], equals(85));
      expect(json['heart_rate'], equals(72));
      expect(json['gps']['lat'], equals(32.0853));
      expect(json['sdk_version'], equals('1.0.0'));
    });

    test('omits null optional fields in JSON', () {
      final payload = HeartbeatPayload(
        deviceId: 'watch_001',
        sessionId: 'sess_abc',
        userId: 'user_1',
        timestamp: 1718745600000,
        batteryLevel: 85,
        activityType: 'swimming',
      );

      final json = payload.toJson();
      expect(json.containsKey('heart_rate'), isFalse);
      expect(json.containsKey('gps'), isFalse);
    });

    test('round-trips through JSON serialization', () {
      final original = HeartbeatPayload(
        deviceId: 'watch_002',
        sessionId: 'sess_xyz',
        userId: 'user_2',
        timestamp: 1718745600000,
        batteryLevel: 42,
        gps: const GpsCoordinates(lat: 32.1, lng: 34.8),
        activityType: 'diving',
      );

      final json = original.toJson();
      final restored = HeartbeatPayload.fromJson(json);

      expect(restored.deviceId, equals(original.deviceId));
      expect(restored.sessionId, equals(original.sessionId));
      expect(restored.batteryLevel, equals(original.batteryLevel));
      expect(restored.gps?.lat, equals(original.gps?.lat));
    });
  });

  group('CrashLog', () {
    test('serializes to JSON correctly', () {
      final log = CrashLog(
        reportId: 'crash_001',
        deviceId: 'watch_001',
        sessionId: 'sess_abc',
        errorMessage: 'Null pointer exception',
        stackTrace: 'at main.dart:42',
        crashTimestamp: 1718745600000,
        deviceState: const DeviceState(
          batteryLevel: 10,
          isOnline: false,
          queuedHeartbeats: 5,
        ),
      );

      final json = log.toJson();
      expect(json['report_id'], equals('crash_001'));
      expect(json['error_message'], equals('Null pointer exception'));
      expect(json['device_state']['battery_level'], equals(10));
      expect(json['device_state']['is_online'], isFalse);
    });

    test('deserializes from JSON correctly', () {
      final json = {
        'report_id': 'crash_002',
        'device_id': 'watch_003',
        'error_message': 'Out of memory',
        'stack_trace': 'at memory.dart:99',
        'crash_timestamp': 1718745600000,
      };

      final log = CrashLog.fromJson(json);
      expect(log.reportId, equals('crash_002'));
      expect(log.deviceId, equals('watch_003'));
      expect(log.sessionId, isNull);
    });
  });

  group('SessionManager', () {
    late SessionManager manager;

    setUp(() {
      manager = SessionManager();
    });

    test('starts in idle state', () {
      expect(manager.state, equals(SessionState.idle));
      expect(manager.isActive, isFalse);
      expect(manager.sessionId, isNull);
    });

    test('opens a valid session', () {
      final config = SessionConfig(
        userId: 'user_1',
        userAge: 25,
        activityType: 'swimming',
      );

      final sessionId = manager.openSession(config);

      expect(sessionId, isNotEmpty);
      expect(manager.state, equals(SessionState.active));
      expect(manager.isActive, isTrue);
      expect(manager.sessionId, equals(sessionId));
    });

    test('rejects session with age < 18', () {
      final config = SessionConfig(
        userId: 'user_1',
        userAge: 16,
        activityType: 'swimming',
      );

      expect(
        () => manager.openSession(config),
        throwsA(isA<SessionException>()),
      );
      expect(manager.state, equals(SessionState.idle));
    });

    test('prevents opening duplicate session', () {
      final config = SessionConfig(
        userId: 'user_1',
        userAge: 25,
        activityType: 'swimming',
      );

      manager.openSession(config);

      expect(
        () => manager.openSession(config),
        throwsA(isA<SessionException>()),
      );
    });

    test('closes session and returns summary', () {
      final config = SessionConfig(
        userId: 'user_1',
        userAge: 25,
        activityType: 'swimming',
      );

      final sessionId = manager.openSession(config);
      final summary = manager.closeSession();

      expect(summary['session_id'], equals(sessionId));
      expect(summary['user_id'], equals('user_1'));
      expect(summary['activity_type'], equals('swimming'));
      expect(summary['duration_ms'], isA<int>());
      expect(manager.state, equals(SessionState.idle));
    });

    test('throws when closing without active session', () {
      expect(
        () => manager.closeSession(),
        throwsA(isA<SessionException>()),
      );
    });

    test('reset returns to idle state', () {
      final config = SessionConfig(
        userId: 'user_1',
        userAge: 25,
        activityType: 'swimming',
      );

      manager.openSession(config);
      manager.reset();

      expect(manager.state, equals(SessionState.idle));
      expect(manager.sessionId, isNull);
    });
  });
}
