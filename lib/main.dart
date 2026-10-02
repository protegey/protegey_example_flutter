import 'dart:math';

import 'package:flutter/material.dart';
import 'package:protegey_sdk/protegey_sdk.dart';

// In a real app, read these from your own build config — never hardcode a production API key.
const _apiKey = String.fromEnvironment('PROTEGEY_API_KEY');
const _baseUrl = String.fromEnvironment('PROTEGEY_BASE_URL', defaultValue: 'https://api.protegey.com');

// A fresh id per demo run — real integrations pass the end user's own stable id instead.
final _customerId = 'customer-${Random().nextInt(999999).toRadixString(36)}';
final _sessionId = 'flutter-example-session-${DateTime.now().millisecondsSinceEpoch}';

void main() {
  runApp(const ProtegeyExampleApp());
}

class ProtegeyExampleApp extends StatelessWidget {
  const ProtegeyExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Protegey — Flutter example',
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _protegey = Protegey(apiKey: _apiKey, baseUrl: _baseUrl);
  String _log = 'Waiting for device.identify()…';
  String? _visitorId;

  @override
  void initState() {
    super.initState();
    // Typically called once on login/session start — done automatically here so the rest of the
    // demo already has a visitorId to fold in; the button below lets you trigger it again on demand.
    _identifyDevice();
  }

  Future<void> _identifyDevice() async {
    try {
      final result = await _protegey.device.identify(externalCustomerId: _customerId);
      setState(() {
        _visitorId = result.visitorId;
        _log = 'device.identify() -> visitorId=${result.visitorId}, action=${result.action}';
      });
    } catch (err) {
      setState(() => _log = 'device.identify() failed: $err');
    }
  }

  Future<void> _reportTransaction() async {
    try {
      final result = await _protegey.transactions.report(TransactionInput(
        externalTransactionId: 'flutter-example-${DateTime.now().millisecondsSinceEpoch}',
        externalCustomerId: _customerId,
        direction: TransactionDirection.debit,
        amount: 5000,
        currency: 'XAF',
        transactionType: 'test',
        visitorId: _visitorId,
      ));
      setState(() => _log = 'transactions.report() -> decision=${result.decision}, riskScore=${result.riskScore}');
    } catch (err) {
      setState(() => _log = 'transactions.report() failed: $err');
    }
  }

  Future<void> _reportBehavioral() async {
    try {
      final result = await _protegey.behavioral.report(ReportBehavioralEventInput(
        externalCustomerId: _customerId,
        sessionId: _sessionId,
        keystroke: const KeystrokeMetrics(avgInterKeyLatencyMs: 145, typingSpeedCharsPerSec: 4.2, errorRate: 0.02),
        touch: const TouchMetrics(avgSwipeVelocity: 22, scrollBehaviorScore: 0.8),
        navigation: const NavigationMetrics(screenSequence: ['login', 'dashboard', 'transfer', 'confirm']),
      ));
      // "learning" for the first few sessions of any given customer — expected, not an error.
      setState(() => _log = 'behavioral.report() -> status=${result.status}, stepUpRecommended=${result.stepUpRecommended}');
    } catch (err) {
      setState(() => _log = 'behavioral.report() failed: $err');
    }
  }

  Future<void> _startKyc() async {
    try {
      // One call: starts the session AND shows it in a draggable bottom sheet — the user never
      // leaves this app, and there's no UI code to write for that on our end.
      final status = await _protegey.kyc.presentVerification(context, externalUserId: _customerId);
      setState(() => _log = 'KYC status -> ${status?.status ?? '(closed before a status arrived)'}');
    } catch (err) {
      setState(() => _log = 'kyc.startSession() failed: $err');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Protegey — Flutter example')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Demonstrates every protegey_sdk module: device intelligence, transaction reporting, '
              'behavioral biometrics, and identity verification shown in an in-app webview — the '
              'user never leaves this app.',
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _identifyDevice, child: const Text('Identify device again')),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _reportTransaction, child: const Text('Report a test transaction')),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _reportBehavioral, child: const Text('Report a behavioral event')),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _startKyc, child: const Text('Verify my identity')),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              color: const Color(0xFFF4F4F4),
              child: Text(_log, style: const TextStyle(fontFamily: 'monospace')),
            ),
          ],
        ),
      ),
    );
  }
}
