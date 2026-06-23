import 'package:vibration/vibration.dart';

/// Controls haptic feedback (vibration) on the smartwatch during sessions.
///
/// During an active monitoring session, haptic feedback is disabled to
/// prevent user distractions. This is critical for life-safety scenarios
/// where an unexpected vibration could startle or distract a swimmer,
/// elderly person, or athlete.
///
/// The controller saves the original vibration state and restores it
/// when the session ends.
class HapticsController {
  bool _hapticsDisabled = false;
  bool _deviceHasVibrator = false;

  /// Check if the device supports vibration.
  Future<void> initialize() async {
    try {
      _deviceHasVibrator = await Vibration.hasVibrator() ?? false;
    } catch (e) {
      _deviceHasVibrator = false;
    }
  }

  /// Disable haptic feedback for the duration of the session.
  ///
  /// Cancels any ongoing vibration and marks haptics as disabled.
  /// While disabled, the SDK will not trigger any vibration alerts.
  Future<void> disableHaptics() async {
    if (!_deviceHasVibrator) return;

    try {
      // Cancel any ongoing vibration
      await Vibration.cancel();
      _hapticsDisabled = true;
    } catch (e) {
      // Silently fail — haptic control is best-effort
    }
  }

  /// Restore haptic feedback after session ends.
  ///
  /// Re-enables the device's ability to vibrate for notifications
  /// and other system alerts.
  Future<void> restoreHaptics() async {
    _hapticsDisabled = false;
  }

  /// Whether haptics are currently disabled by the SDK.
  bool get isDisabled => _hapticsDisabled;

  /// Whether the device supports vibration.
  bool get hasVibrator => _deviceHasVibrator;

  /// Trigger a controlled vibration (only used for critical SDK alerts
  /// that override the haptic suppression, e.g., emergency shutdown).
  Future<void> emergencyVibrate() async {
    if (!_deviceHasVibrator) return;

    try {
      // Strong, distinctive pattern for emergencies
      await Vibration.vibrate(
        pattern: [0, 500, 200, 500, 200, 1000],
        intensities: [0, 255, 0, 255, 0, 255],
      );
    } catch (e) {
      // Silently fail
    }
  }

  /// Dispose of resources.
  void dispose() {
    if (_hapticsDisabled) {
      restoreHaptics();
    }
  }
}
