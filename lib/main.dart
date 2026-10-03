import 'dart:math';

import 'package:flutter/material.dart';
import 'package:protegey_sdk/protegey_sdk.dart';
import 'package:shared_preferences/shared_preferences.dart';

// In a real app, read these from your own build config — never hardcode a production API key.
const _defaultApiKey = String.fromEnvironment('PROTEGEY_API_KEY');
const _defaultBaseUrl = String.fromEnvironment('PROTEGEY_BASE_URL', defaultValue: 'https://api.protegey.com');

const _prefsApiKeyKey = 'protegey_example_api_key';
const _prefsBaseUrlKey = 'protegey_example_base_url';

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
  // Nullable on purpose: the SDK's constructor throws on an empty apiKey, and a fresh install
  // with no --dart-define and no saved preference yet has nothing to construct it with — the
  // whole point of the editable fields below is to let someone fill one in at runtime instead of
  // crashing on launch, so every call site below must tolerate this being null until they do.
  Protegey? _protegey;
  final _apiKeyController = TextEditingController();
  final _baseUrlController = TextEditingController();
  String _log = 'Waiting for device.identify()…';
  String? _visitorId;

  @override
  void initState() {
    super.initState();
    _apiKeyController.text = _defaultApiKey;
    _baseUrlController.text = _defaultBaseUrl;
    if (_defaultApiKey.isNotEmpty) {
      _protegey = Protegey(apiKey: _defaultApiKey, baseUrl: _defaultBaseUrl);
    } else {
      _log = 'Enter an API key below and tap "Apply & reconnect" to get started.';
    }
    _loadSavedCredentials();
  }

  // Lets you point this app at any partner's key/environment at runtime, without rebuilding —
  // handy for testing against staging vs. production, or a different demo partner.
  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final savedKey = prefs.getString(_prefsApiKeyKey);
    final savedUrl = prefs.getString(_prefsBaseUrlKey);
    if (savedKey == null || savedKey.isEmpty) return;
    setState(() {
      _apiKeyController.text = savedKey;
      _baseUrlController.text = savedUrl ?? _defaultBaseUrl;
      _protegey = Protegey(apiKey: _apiKeyController.text, baseUrl: _baseUrlController.text);
    });
    _identifyDevice();
  }

  Future<void> _applyCredentials() async {
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      setState(() => _log = 'API key cannot be empty.');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsApiKeyKey, apiKey);
    await prefs.setString(_prefsBaseUrlKey, _baseUrlController.text);
    setState(() {
      _protegey = Protegey(apiKey: apiKey, baseUrl: _baseUrlController.text);
      _log = 'Switched to baseUrl=${_baseUrlController.text}';
    });
    _identifyDevice();
  }

  Future<void> _identifyDevice() async {
    final protegey = _protegey;
    if (protegey == null) {
      setState(() => _log = 'Set an API key first.');
      return;
    }
    try {
      final result = await protegey.device.identify(externalCustomerId: _customerId);
      setState(() {
        _visitorId = result.visitorId;
        _log = 'device.identify() -> visitorId=${result.visitorId}, action=${result.action}';
      });
    } catch (err) {
      setState(() => _log = 'device.identify() failed: $err');
    }
  }

  Future<void> _reportTransaction() async {
    final protegey = _protegey;
    if (protegey == null) {
      setState(() => _log = 'Set an API key first.');
      return;
    }
    try {
      final result = await protegey.transactions.report(TransactionInput(
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
    final protegey = _protegey;
    if (protegey == null) {
      setState(() => _log = 'Set an API key first.');
      return;
    }
    try {
      final result = await protegey.behavioral.report(ReportBehavioralEventInput(
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
    final protegey = _protegey;
    if (protegey == null) {
      setState(() => _log = 'Set an API key first.');
      return;
    }
    try {
      // One call: starts the session AND shows it in a draggable bottom sheet — the user never
      // leaves this app, and there's no UI code to write for that on our end.
      final status = await protegey.kyc.presentVerification(context, externalUserId: _customerId);
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
        child: ListView(
          children: [
            const Text(
              'Demonstrates every protegey_sdk module: device intelligence, transaction reporting, '
              'behavioral biometrics, and identity verification shown in an in-app webview — the '
              'user never leaves this app.',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              color: const Color(0xFFEEF2FF),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('API key', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  TextField(controller: _apiKeyController, decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), hintText: 'your-api-key')),
                  const SizedBox(height: 8),
                  const Text('Base URL', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  TextField(controller: _baseUrlController, decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), hintText: 'https://api.protegey.com')),
                  const SizedBox(height: 8),
                  ElevatedButton(onPressed: _applyCredentials, child: const Text('Apply & reconnect')),
                ],
              ),
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
