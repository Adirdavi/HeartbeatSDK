import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models/heartbeat_payload.dart';

/// Manages a persistent offline queue for heartbeat payloads.
///
/// When the device loses network connectivity, heartbeats are enqueued
/// to SharedPreferences. Once connectivity is restored, the queue is
/// flushed in chronological order, ensuring no data loss.
///
/// Storage Format:
/// - Queue index stored at key `hb_queue_index` as a JSON list of keys
/// - Each payload stored at key `hb_queue_{timestamp}_{index}`
class OfflineQueue {
  static const String _queueIndexKey = 'hb_queue_index';
  static const int _maxQueueSize = 500;

  SharedPreferences? _prefs;
  final List<String> _queueKeys = [];

  /// Initialize the queue by loading the index from SharedPreferences.
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    final savedKeys = _prefs?.getStringList(_queueIndexKey);
    if (savedKeys != null) {
      _queueKeys.addAll(savedKeys);
    }
  }

  /// Enqueue a heartbeat payload for later transmission.
  ///
  /// Payloads are serialized to JSON and stored in SharedPreferences.
  /// If the queue exceeds [_maxQueueSize], the oldest entries are dropped
  /// to prevent unbounded storage growth on the watch.
  Future<void> enqueue(HeartbeatPayload payload) async {
    if (_prefs == null) await initialize();

    final key = 'hb_queue_${payload.timestamp}_${_queueKeys.length}';
    final jsonString = jsonEncode(payload.toJson());

    await _prefs!.setString(key, jsonString);
    _queueKeys.add(key);

    // Enforce max queue size — drop oldest entries
    while (_queueKeys.length > _maxQueueSize) {
      final oldestKey = _queueKeys.removeAt(0);
      await _prefs!.remove(oldestKey);
    }

    await _saveIndex();
  }

  /// Retrieve all queued payloads in chronological order.
  ///
  /// Returns a list of [HeartbeatPayload] objects. Does not remove them
  /// from the queue — call [removeProcessed] after successful transmission.
  Future<List<HeartbeatPayload>> getAll() async {
    if (_prefs == null) await initialize();

    final payloads = <HeartbeatPayload>[];
    for (final key in _queueKeys) {
      final jsonString = _prefs!.getString(key);
      if (jsonString != null) {
        try {
          final json = jsonDecode(jsonString) as Map<String, dynamic>;
          payloads.add(HeartbeatPayload.fromJson(json));
        } catch (e) {
          // Corrupted entry — skip and clean up on next flush
          continue;
        }
      }
    }
    return payloads;
  }

  /// Remove a batch of processed entries by their keys.
  ///
  /// Called after successful transmission to clear flushed payloads.
  Future<void> removeProcessed(int count) async {
    if (_prefs == null) return;

    final keysToRemove = _queueKeys.take(count).toList();
    for (final key in keysToRemove) {
      await _prefs!.remove(key);
      _queueKeys.remove(key);
    }
    await _saveIndex();
  }

  /// Flush the entire queue — attempt to transmit all queued payloads.
  ///
  /// Takes a [transmitFn] callback that handles actual HTTP transmission.
  /// Returns the number of successfully transmitted payloads.
  Future<int> flush(
    Future<bool> Function(HeartbeatPayload) transmitFn,
  ) async {
    final payloads = await getAll();
    int successCount = 0;

    for (final payload in payloads) {
      try {
        final success = await transmitFn(payload);
        if (success) {
          successCount++;
        } else {
          // Stop flushing on first failure (network likely down again)
          break;
        }
      } catch (e) {
        break;
      }
    }

    if (successCount > 0) {
      await removeProcessed(successCount);
    }

    return successCount;
  }

  /// Get the current number of queued payloads.
  int get queueSize => _queueKeys.length;

  /// Check if the queue has any pending payloads.
  bool get isNotEmpty => _queueKeys.isNotEmpty;

  /// Clear the entire queue (used during session reset or testing).
  Future<void> clear() async {
    if (_prefs == null) return;

    for (final key in _queueKeys) {
      await _prefs!.remove(key);
    }
    _queueKeys.clear();
    await _saveIndex();
  }

  /// Persist the queue index to SharedPreferences.
  Future<void> _saveIndex() async {
    await _prefs?.setStringList(_queueIndexKey, _queueKeys);
  }
}
