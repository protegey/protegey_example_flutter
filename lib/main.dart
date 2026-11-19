import 'dart:math';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
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
      setState(() => _log = 'device.identify() -> visitorId=${result.visitorId}, action=${result.action?.name}, riskScore=${result.riskScore}');
    } catch (err) {
      setState(() => _log = 'device.identify() failed: $err');
    }
  }

  // No "report a transaction" call here on purpose: that call belongs server-to-server, from
  // your own backend (POST /partner-api/transactions), not from this app — see the Flutter SDK
  // docs' Transactions section. device.identify() above is this app's whole job; as long as your
  // backend sends the same externalCustomerId on the transaction it reports moments later,
  // Protegey links the two automatically — nothing to relay yourself.

  // Sandbox demo only: like transactions, a cash deposit is reported server-to-server in
  // production (your teller/agent system holds the authoritative data). Shown here so you can see
  // the request/response shape against a sandbox key.
  Future<void> _recordCashDeposit() async {
    final protegey = _protegey;
    if (protegey == null) {
      setState(() => _log = 'Set an API key first.');
      return;
    }
    // Your own reference — reusing it is rejected with a 409, which makes retries safe.
    final reference = 'dep-${DateTime.now().millisecondsSinceEpoch}';
    try {
      final recorded = await protegey.cashDeposits.record(CashDepositInput(
        externalTransactionId: reference,
        externalCustomerId: _customerId,
        amount: 2500000,
        currency: 'XOF',
        channel: TransactionChannel.branch,
        branchId: 'DKR-PLATEAU',
        depositorName: 'Awa Diallo',
      ));
      // Look it up again by our own reference — the amount comes back as a decimal string.
      final deposit = await protegey.cashDeposits.get(reference);
      setState(() => _log = 'cashDeposits.record() -> decision=${recorded.decision}, riskScore=${recorded.riskScore}, '
          'alerts=${recorded.alerts.length}\ncashDeposits.get($reference) -> amount=${deposit.amount} ${deposit.currency}, '
          'channel=${deposit.channel}, decision=${deposit.decision}');
    } on ProtegeyApiException catch (err) {
      setState(() => _log = err.status == 409 ? 'Duplicate externalTransactionId (409): $err' : 'cashDeposits failed: $err');
    } catch (err) {
      setState(() => _log = 'cashDeposits failed: $err');
    }
  }

  // Finds this customer's KYC sessions by our own id (exact match) and opens the latest one.
  Future<void> _lookUpKycSessions() async {
    final protegey = _protegey;
    if (protegey == null) {
      setState(() => _log = 'Set an API key first.');
      return;
    }
    try {
      final page = await protegey.kyc.listSessions(externalUserId: _customerId, limit: 20);
      if (page.data.isEmpty) {
        setState(() => _log = 'kyc.listSessions(externalUserId: $_customerId) -> no session yet. Tap "Verify my identity" first.');
        return;
      }
      final latest = page.data.first;
      setState(() => _log = 'kyc.listSessions() -> ${page.total} session(s); latest: status=${latest.status}, '
          'recommendation=${latest.recommendation?.name ?? '-'}');
      // Re-fetch the full session: scores, and fresh 1-hour photo links.
      final status = await protegey.kyc.getSession(latest.sessionId);
      if (mounted) {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => KycResultPage(status: status)));
      }
    } catch (err) {
      setState(() => _log = 'kyc.listSessions() failed: $err');
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
      // "LEARNING" for the first few sessions of any given customer — expected, not an error.
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

    // Ask up front, before the webview ever loads — relying only on the webview's own
    // permission-request bridge to the OS is less predictable across Android OEMs/versions than
    // just getting the OS permission granted first and letting the webview inherit it.
    final cameraStatus = await Permission.camera.request();
    if (!cameraStatus.isGranted) {
      setState(() => _log = 'Camera permission denied — identity verification needs camera access to scan your document and face.');
      return;
    }

    if (!mounted) return;
    try {
      // One call: starts the session AND shows it in a draggable bottom sheet — the user never
      // leaves this app, and there's no UI code to write for that on our end.
      final status = await protegey.kyc.presentVerification(context, externalUserId: _customerId);
      if (status == null) {
        setState(() => _log = 'KYC sheet closed before a status arrived.');
        return;
      }
      setState(() => _log = 'KYC status -> ${status.status} (outcome: ${status.outcome.name}, recommendation: ${status.recommendation?.name ?? '-'})');
      // presentVerification() only returns once its OWN bottom sheet has already closed (auto-
      // close on a terminal status, or the user tapping Close) — so by the time we get here
      // there's nothing left to dismiss. This push is a normal full-screen navigation to a
      // dedicated results page, not a popup on top of anything.
      if (mounted) {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => KycResultPage(status: status)));
      }
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
              'Demonstrates this app\'s actual job: device intelligence, behavioral biometrics, '
              'and identity verification shown in an in-app webview — the user never leaves this '
              'app. Transaction reporting isn\'t shown here: it belongs server-to-server, from '
              'your own backend. The cash deposit button is a sandbox demo of that same kind of call.',
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
            ElevatedButton(onPressed: _reportBehavioral, child: const Text('Report a behavioral event')),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _startKyc, child: const Text('Verify my identity')),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _lookUpKycSessions, child: const Text('Look up my KYC sessions')),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _recordCashDeposit, child: const Text('Record a cash deposit (sandbox demo)')),
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

/// A real, full-screen page — not a popup — shown after `presentVerification()` resolves (its
/// own sheet is already closed by then). Demonstrates reading the session info the SDK actually
/// returns: the typed `outcome` enum for what happened, plus whatever `decision` (Protegey liveness /
/// face match scores) the backend computed, when there is one.
///
/// 'success' means the Protegey face match confidence was >= your account's auto-approve threshold (80%
/// by default); 'manual' means it passed the hard checks (liveness, clean document scan)
/// but fell below that threshold, so a human on your compliance team needs to review it — your
/// own dashboard shows it under "In Review"; 'failed' means a hard check itself failed.
class KycResultPage extends StatelessWidget {
  final KycSessionStatus status;

  const KycResultPage({super.key, required this.status});

  ({IconData icon, Color color, String title, String message}) get _presentation {
    switch (status.outcome) {
      case KycOutcome.success:
        return (
          icon: Icons.check_circle,
          color: Colors.green,
          title: 'Identity verified',
          message: 'Your identity has been confirmed automatically. You can continue.',
        );
      case KycOutcome.manual:
        return (
          icon: Icons.hourglass_top,
          color: Colors.orange,
          title: 'Pending review',
          message: "We received your documents. A reviewer will confirm your identity shortly — we'll let you know once it's done.",
        );
      case KycOutcome.failed:
        return (
          icon: Icons.cancel,
          color: Colors.red,
          title: 'Verification failed',
          message: "We couldn't verify your identity. Please try again with better lighting and a valid, undamaged document.",
        );
      case KycOutcome.unknown:
        return (
          icon: Icons.help_outline,
          color: Colors.grey,
          title: 'Result not available yet',
          message: "We couldn't determine the result yet. This can happen if the session is still being processed.",
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final presentation = _presentation;
    final decision = status.decision;
    final livenessScore = status.livenessScore;
    final matchScore = status.faceMatchScore;
    final confidenceScore = decision?['confidenceScore'];
    final fullName = status.fullName;
    final recommendation = status.recommendation;
    final images = status.images;
    // Pre-signed links, valid 1 hour and re-issued on every getSession() — never store them.
    final photos = <(String, KycImage?)>[
      ('Document', images?.documentFront),
      ('Selfie', images?.selfie),
      ('ID photo', images?.documentFaceCrop),
    ].where((p) => p.$2 != null).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Verification result')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(presentation.icon, color: presentation.color, size: 64),
              const SizedBox(height: 16),
              Text(presentation.title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(presentation.message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Session details', style: Theme.of(context).textTheme.titleMedium),
                      const Divider(height: 24),
                      _InfoRow(label: 'Status', value: status.status),
                      _InfoRow(label: 'Outcome', value: status.outcome.name),
                      // Protegey's verdict; status above is the final decision (can differ after a manual review).
                      if (recommendation != null) _InfoRow(label: 'Recommendation', value: recommendation.name.toUpperCase()),
                      if (fullName is String) _InfoRow(label: 'Full name', value: fullName),
                      if (livenessScore != null) _InfoRow(label: 'Liveness score', value: '${livenessScore.round()}%'),
                      if (matchScore != null) _InfoRow(label: 'Match score', value: '${matchScore.round()}%'),
                      if (confidenceScore is num) _InfoRow(label: 'Confidence', value: '${(confidenceScore * 100).round()}%'),
                      _InfoRow(label: 'Session ID', value: status.sessionId, mono: true),
                      if (status.externalUserId != null) _InfoRow(label: 'External user ID', value: status.externalUserId!, mono: true),
                    ],
                  ),
                ),
              ),
              if (photos.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Photos', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                SizedBox(
                  height: 140,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final (label, image) in photos)
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: SizedBox(
                            width: 100,
                            child: Column(
                              children: [
                                Expanded(
                                  child: Image.network(
                                    image!.url,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => const Icon(Icons.broken_image),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(label, style: Theme.of(context).textTheme.bodySmall),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              ElevatedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;

  const _InfoRow({required this.label, required this.value, this.mono = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade600)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(fontFamily: mono ? 'monospace' : null, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
