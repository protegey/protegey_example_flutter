import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:protegey_sdk/protegey_sdk.dart';
import 'package:protegey_sdk_location/protegey_sdk_location.dart';
import 'package:shared_preferences/shared_preferences.dart';

// In a real app, read these from your own build config — never hardcode a production API key.
const _defaultApiKey = String.fromEnvironment('PROTEGEY_API_KEY');
const _defaultBaseUrl = String.fromEnvironment('PROTEGEY_BASE_URL', defaultValue: 'https://api.protegey.com');

const _prefsApiKeyKey = 'protegey_example_api_key';
const _prefsBaseUrlKey = 'protegey_example_base_url';
const _prefsCustomerIdKey = 'protegey_example_customer_id';

// A fresh id per demo run — real integrations pass the end user's own stable id instead.
final _randomCustomerId = 'customer-${Random().nextInt(999999).toRadixString(36)}';
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
  // Editable and remembered across launches: a re-verification (face match) must use the SAME customer
  // id as that person's earlier KYC — a fresh random id on every launch could never match.
  final _customerIdController = TextEditingController(text: _randomCustomerId);
  String get _customerId => _customerIdController.text.trim().isEmpty ? _randomCustomerId : _customerIdController.text.trim();
  final _amountController = TextEditingController(text: '15000');
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
    final savedCustomerId = prefs.getString(_prefsCustomerIdKey);
    if (savedCustomerId != null && savedCustomerId.isNotEmpty) _customerIdController.text = savedCustomerId;
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
    await prefs.setString(_prefsCustomerIdKey, _customerId);
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
      // Silent, as in production: sends the position only if the location permission is already
      // granted (never prompts), shows nothing, never throws. A transaction reported for this
      // customer within ~15 minutes reuses it.
      unawaited(protegey.location.update(externalCustomerId: _customerId));
    } catch (err) {
      setState(() => _log = 'device.identify() failed: $err');
    }
  }

  // Sandbox demo only: in production a transaction is reported server-to-server, from your own
  // backend (POST /partner-api/transactions) — see the Flutter SDK docs' Transactions section.
  // Shown here to demo the optional GPS position: the user is asked first, and only a "yes"
  // reads the position (and shows the OS permission prompt if it hasn't been answered yet).
  Future<void> _makeTransaction() async {
    final protegey = _protegey;
    if (protegey == null) {
      setState(() => _log = 'Set an API key first.');
      return;
    }
    final amount = num.tryParse(_amountController.text.replaceAll(RegExp(r'[\s,]'), ''));
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter an amount greater than 0.')));
      return;
    }
    final useLocation = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.location_on_outlined),
        title: const Text('Use your location?'),
        content: const Text('Sharing your position with this payment helps us spot fraud, such as someone '
            'using your account from another city. It is only used for this check.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('No, continue without')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Yes, use my location')),
        ],
      ),
    );
    if (useLocation == null || !mounted) return; // dismissed: no transaction

    DeviceLocation? location;
    if (useLocation) {
      // The user just said yes, so a few seconds for a precise GPS fix is acceptable here.
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Row(children: [CircularProgressIndicator(), SizedBox(width: 20), Text('Reading your position…')]),
        ),
      );
      location = await ProtegeyLocation.current(requestPermission: true, timeout: const Duration(seconds: 5));
      if (mounted) Navigator.of(context).pop();
      if (location == null && mounted) {
        final blocked = await Permission.locationWhenInUse.isPermanentlyDenied;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(blocked
              ? 'Location is turned off for this app — the payment is sent without it.'
              : 'No position available (permission refused or location off) — the payment is sent without it.'),
          action: blocked ? const SnackBarAction(label: 'Settings', onPressed: openAppSettings) : null,
        ));
      }
    }

    final reference = 'txn-${DateTime.now().millisecondsSinceEpoch}';
    try {
      final result = await protegey.transactions.report(TransactionInput(
        externalTransactionId: reference,
        externalCustomerId: _customerId,
        direction: TransactionDirection.debit,
        amount: amount,
        currency: 'XOF',
        transactionType: 'transfer',
        channel: TransactionChannel.mobileApp,
        location: location,
      ));
      setState(() => _log = 'transactions.report($reference) -> decision=${result.decision}, riskScore=${result.riskScore}, '
          'alerts=${result.alerts.length}, location=${result.location == null ? 'none' : 'used'}');
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => _TransactionResultSheet(reference: reference, amount: amount, sent: location, result: result),
      );
    } catch (err) {
      setState(() => _log = 'transactions.report() failed: $err');
    }
  }

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

  Future<void> _saveCustomerId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsCustomerIdKey, _customerId);
  }

  /// 3D liveness (selfie only, billed per proven check) — and its re-verification variant, which
  /// matches the face against this customer's KYC. Separate from KYC.
  Future<void> _startLiveness({required bool reverify}) async {
    final protegey = _protegey;
    if (protegey == null) {
      setState(() => _log = 'Set an API key first.');
      return;
    }
    await _saveCustomerId();
    final cameraStatus = await Permission.camera.request();
    if (!cameraStatus.isGranted) {
      setState(() => _log = 'Camera permission denied — the 3D liveness check needs the camera.');
      return;
    }
    if (!mounted) return;
    try {
      final LivenessSession? session;
      if (reverify) {
        session = await protegey.liveness.presentReverification(context, externalUserId: _customerId);
      } else {
        session = await protegey.liveness.presentLiveness(context, externalUserId: _customerId);
      }
      if (session == null) {
        setState(() => _log = 'Liveness sheet closed before a result.');
        return;
      }
      final finished = session;
      final result = finished.livenessProven == null
          ? 'no result yet'
          : finished.livenessProven == false
              ? 'inconclusive scan'
              : reverify
                  ? (finished.matched == true ? 'SAME person as the KYC (match level ${finished.matchLevel})' : 'DIFFERENT person (match level ${finished.matchLevel})')
                  : 'live person';
      setState(() => _log = '${reverify ? 'liveness.presentReverification' : 'liveness.presentLiveness'}(externalUserId: $_customerId)\n'
          '-> status=${finished.status}, result=$result, attempts=${finished.attempts}, billed=${finished.billableChecks} check(s) = ${finished.amount} USD');
    } on ProtegeyApiException catch (err) {
      if (err.errorCode == no3dEnrollmentErrorCode) {
        setState(() => _log = 'No 3D record (KYC) exists for "$_customerId".\nRun "Verify my identity" with this customer ID first, then re-verify.');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No 3D record (KYC) exists for "$_customerId" — verify their identity first.')));
        }
        return;
      }
      setState(() => _log = 'liveness failed: $err');
    } catch (err) {
      setState(() => _log = 'liveness failed: $err');
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
              'app. In production, transactions and cash deposits are reported server-to-server, from '
              'your own backend: their buttons here send those calls to the API set below (the '
              'transaction one shows the optional GPS position).',
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
            const Text('Customer ID (externalUserId)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            TextField(
              controller: _customerIdController,
              onSubmitted: (_) => _saveCustomerId(),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                helperText: 'Kept across launches. Use the same ID for "Verify my identity" and "Re-verify me".',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), labelText: 'Transaction amount', suffixText: 'XOF'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(onPressed: _makeTransaction, icon: const Icon(Icons.send), label: const Text('Make a transaction')),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _identifyDevice, child: const Text('Identify device again')),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _reportBehavioral, child: const Text('Report a behavioral event')),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _startKyc, child: const Text('Verify my identity')),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _lookUpKycSessions, child: const Text('Look up my KYC sessions')),
            const SizedBox(height: 8),
            FilledButton.icon(onPressed: () => _startLiveness(reverify: false), icon: const Icon(Icons.face_retouching_natural), label: const Text('3D liveness check')),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(onPressed: () => _startLiveness(reverify: true), icon: const Icon(Icons.verified_user), label: const Text('Re-verify me (face match vs my KYC)')),
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

/// What was sent and what Protegey made of it, right after `transactions.report()`.
class _TransactionResultSheet extends StatelessWidget {
  final String reference;
  final num amount;
  final DeviceLocation? sent;
  final ReportTransactionResult result;

  const _TransactionResultSheet({required this.reference, required this.amount, required this.sent, required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sent = this.sent;
    final used = result.location;
    final decisionColor = switch (result.decision) {
      'CLEAR' => Colors.green,
      'BLOCKED' => Colors.red,
      _ => Colors.orange,
    };
    String yesNo(bool? value) => value == null ? '-' : (value ? 'Yes' : 'No');

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Transaction sent', style: theme.textTheme.titleLarge),
                const Spacer(),
                Chip(
                  label: Text(result.decision, style: TextStyle(color: decisionColor, fontWeight: FontWeight.w700)),
                  side: BorderSide(color: decisionColor),
                ),
              ],
            ),
            _InfoRow(label: 'Amount', value: '$amount XOF'),
            _InfoRow(label: 'Risk score', value: '${result.riskScore} / 100'),
            _InfoRow(label: 'Alerts', value: '${result.alerts.length}'),
            _InfoRow(label: 'Reference', value: reference, mono: true),
            const Divider(height: 32),
            Row(
              children: [
                Icon(used == null ? Icons.location_off_outlined : Icons.location_on, color: used == null ? Colors.grey : theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(used == null ? 'Sent without location' : 'Location taken into account', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            if (sent != null) ...[
              Text('Read on this phone', style: theme.textTheme.labelLarge),
              _InfoRow(label: 'Position', value: '${sent.latitude.toStringAsFixed(6)}, ${sent.longitude.toStringAsFixed(6)}', mono: true),
              _InfoRow(label: 'Accuracy', value: sent.accuracyMeters == null ? '-' : '± ${sent.accuracyMeters!.round()} m'),
              if (sent.capturedAt != null) _InfoRow(label: 'Taken at', value: TimeOfDay.fromDateTime(sent.capturedAt!.toLocal()).format(context)),
              const SizedBox(height: 12),
            ],
            if (used != null) ...[
              Text('Used by Protegey (stored rounded to ~100 m)', style: theme.textTheme.labelLarge),
              _InfoRow(label: 'Position', value: '${used.latitude ?? '-'}, ${used.longitude ?? '-'}', mono: true),
              _InfoRow(label: 'Fake GPS', value: yesNo(used.isMocked)),
              _InfoRow(label: 'Distance from IP address', value: used.gpsIpDistanceKm == null ? 'unknown' : '${used.gpsIpDistanceKm} km'),
              _InfoRow(label: 'Travel speed since last position', value: used.impliedTravelSpeedKmh == null ? 'first position' : '${used.impliedTravelSpeedKmh} km/h'),
              _InfoRow(label: 'New area for this customer', value: yesNo(used.isNewGpsArea)),
            ] else
              Text('No position was used for this transaction.', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 24),
            FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
          ],
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
