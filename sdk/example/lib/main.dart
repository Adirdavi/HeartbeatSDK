import 'package:flutter/material.dart';
import 'package:heartbeat_sdk/heartbeat_sdk.dart';

void main() {
  runApp(const HeartbeatTestApp());
}

class HeartbeatTestApp extends StatelessWidget {
  const HeartbeatTestApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Heartbeat SDK Test',
      theme: ThemeData(primarySwatch: Colors.red),
      home: const HeartbeatTestHome(),
    );
  }
}

class HeartbeatTestHome extends StatefulWidget {
  const HeartbeatTestHome({Key? key}) : super(key: key);

  @override
  State<HeartbeatTestHome> createState() => _HeartbeatTestHomeState();
}

class _HeartbeatTestHomeState extends State<HeartbeatTestHome> {
  final HeartbeatSDK _sdk = HeartbeatSDK();
  String _status = 'Not configured';
  bool _isTransmitting = false;
  int _localSentCount = 0;

  Future<void> _initializeAndStart() async {
    setState(() => _status = 'Configuring SDK...');
    try {
      // 1. Configure the SDK
      await _sdk.configure(
        projectId: 'adir-2c6b3',
        deviceId: 'test_watch_001',
        appId: 'com.example.surfwatch',
      );

      // 2. Open a session
      await _sdk.openSession(
        userId: 'test_user_42',
        userAge: 25,
        activityType: 'swimming',
      );

      // 3. Start sending heartbeats every 5 seconds for testing
      _sdk.start(interval: const Duration(seconds: 5));

      setState(() {
        _status = 'Transmitting heartbeats...';
        _isTransmitting = true;
      });

      // Listen to heartbeat events
      _sdk.onHeartbeat = (success, queued) {
        if (mounted) {
          setState(() {
            if (success) {
              _localSentCount++;
              _status = 'Heartbeat Sent! (Total: $_localSentCount)';
            } else if (queued) {
              _status = 'Heartbeat Queued Offline! (Queue: ${_sdk.offlineQueueSize})';
            }
          });
        }
      };

    } catch (e) {
      setState(() => _status = 'Error: $e');
    }
  }

  Future<void> _stop() async {
    final summary = await _sdk.closeSession();
    setState(() {
      _status = 'Stopped. Total sent: ${summary['heartbeats_transmitted'] ?? _localSentCount}';
      _isTransmitting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Heartbeat SDK Test')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isTransmitting ? Icons.favorite : Icons.favorite_border,
              color: Colors.red,
              size: 100,
            ),
            const SizedBox(height: 20),
            Text(_status, style: const TextStyle(fontSize: 18), textAlign: TextAlign.center),
            const SizedBox(height: 40),
            if (!_isTransmitting)
              ElevatedButton(
                onPressed: _initializeAndStart,
                child: const Text('Start Session'),
              )
            else
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                onPressed: _stop,
                child: const Text('Stop Session'),
              ),
          ],
        ),
      ),
    );
  }
}
