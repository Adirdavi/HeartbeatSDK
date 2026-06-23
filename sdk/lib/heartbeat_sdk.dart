/// HeartbeatSDK — Standalone smartwatch monitoring infrastructure.
///
/// A Flutter/Dart SDK for managing activity sessions and transmitting
/// real-time availability signals (Heartbeats) to the cloud.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:heartbeat_sdk/heartbeat_sdk.dart';
///
/// final sdk = HeartbeatSDK();
/// await sdk.configure(projectId: 'my-project', deviceId: 'watch_001');
///
/// await sdk.openSession(
///   userId: 'user_42',
///   userAge: 25,
///   activityType: 'swimming',
/// );
///
/// sdk.start(interval: Duration(seconds: 10));
///
/// // When done:
/// await sdk.closeSession();
/// ```
library heartbeat_sdk;

// Public API
export 'src/heartbeat_sdk_core.dart';
export 'src/session_manager.dart';
export 'src/models/heartbeat_payload.dart';
export 'src/models/session_config.dart';
export 'src/models/crash_log.dart';
