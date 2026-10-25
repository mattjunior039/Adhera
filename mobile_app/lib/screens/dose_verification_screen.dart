import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../repositories/dose_verification_repository.dart';
import '../repositories/medication_repository.dart';
import '../repositories/pillbox_inventory_repository.dart';
import '../services/api_service.dart';
import '../widgets/app_navigation.dart';

class DoseVerificationVideoScreen extends ConsumerStatefulWidget {
  const DoseVerificationVideoScreen({super.key});

  @override
  ConsumerState<DoseVerificationVideoScreen> createState() =>
      _DoseVerificationVideoScreenState();
}

class _DoseVerificationVideoScreenState
    extends ConsumerState<DoseVerificationVideoScreen> {
  File? _selectedVideo;
  bool _isBusy = false;
  String? _error;
  PillboxInventorySlot? _selectedCompartment;
  final _phaseTimes = List.generate(4, (_) => TextEditingController());

  @override
  void dispose() {
    for (final controller in _phaseTimes) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _initializeInventory(int userId) async {
    try {
      await ref
          .read(pillboxInventoryRepositoryProvider)
          .initializeTestInventory(userId);
      ref.invalidate(pillboxInventoryProvider(userId));
    } on Exception catch (e) {
      if (mounted) {
        setState(
          () => _error = e is ApiException
              ? e.message
              : 'Could not initialize test inventory',
        );
      }
    }
  }

  Future<void> _pick(bool fromCamera) async {
    try {
      final repo = ref.read(doseVerificationRepositoryProvider);
      final picked = fromCamera
          ? await repo.recordVerificationVideo()
          : await repo.pickVerificationVideoFromGallery();
      if (picked == null) return;
      setState(() {
        _selectedVideo = File(picked.path);
        for (final controller in _phaseTimes) {
          controller.clear();
        }
        _error = null;
      });
    } catch (_) {
      setState(() => _error = 'Could not access camera or gallery');
    }
  }

  Future<void> _analyze() async {
    if (_selectedVideo == null) {
      setState(() => _error = 'Record or select a video first');
      return;
    }
    if (_selectedCompartment == null) {
      setState(() => _error = 'Select the compartment shown in the video');
      return;
    }
    List<double>? phaseWindows;
    if (_phaseTimes.any((controller) => controller.text.trim().isNotEmpty)) {
      final values = _phaseTimes
          .map((controller) => double.tryParse(controller.text.trim()))
          .toList();
      if (values.any((value) => value == null || !value.isFinite)) {
        setState(() => _error = 'Enter all four timestamps in seconds');
        return;
      }
      phaseWindows = values.whereType<double>().toList();
      if (!(0 <= phaseWindows[0] &&
          phaseWindows[0] < phaseWindows[1] &&
          phaseWindows[1] < phaseWindows[2] &&
          phaseWindows[2] < phaseWindows[3] &&
          phaseWindows[3] <= 120)) {
        setState(
          () =>
              _error = 'Use separate before/after intervals within 120 seconds',
        );
        return;
      }
    }
    setState(() {
      _isBusy = true;
      _error = null;
    });

    final int userId =
        ref.read(currentUserProvider)?.id ?? ref.read(userIdProvider);
    final repo = ref.read(doseVerificationRepositoryProvider);

    try {
      final result = await repo.analyzeVideo(
        userId: userId,
        videoFile: _selectedVideo!,
        compartmentId: _selectedCompartment!.id,
        phaseWindows: phaseWindows,
      );
      ref.invalidate(pillboxInventoryProvider(userId));
      ref.invalidate(doseVerificationEventsProvider(userId));
      if (!mounted) return;
      context.push('/dose-verification-result', extra: result);
    } on Exception catch (e) {
      if (!mounted) return;
      final message = e is ApiException ? e.message : 'Verification failed: $e';
      setState(() => _error = message);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final int userId =
        ref.watch(currentUserProvider)?.id ?? ref.watch(userIdProvider);
    final inventory = ref.watch(pillboxInventoryProvider(userId));

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Verify dose with video'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Blue PM prototype only: keep all seven open compartments visible, Sunday on the left. '
                      'Hold still before and after removing a pill. Results require review; inventory is unchanged. '
                      'Maximum 120 seconds / 50 MiB.',
                      style: TextStyle(fontSize: 12, color: Colors.blue),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            inventory.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => Text('Could not load box inventory: $error'),
              data: (slots) => slots.length != 14
                  ? OutlinedButton.icon(
                      onPressed: _isBusy
                          ? null
                          : () => _initializeInventory(userId),
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: Text(
                        slots.isEmpty
                            ? 'Initialize 14-slot test box'
                            : 'Complete 14-slot test box',
                      ),
                    )
                  : DropdownButtonFormField<int>(
                      isExpanded: true,
                      initialValue: _selectedCompartment?.id,
                      decoration: const InputDecoration(
                        labelText: 'Compartment shown in this video',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: slots
                          .where((slot) => slot.period == 'PM')
                          .map(
                            (slot) => DropdownMenuItem<int>(
                              value: slot.id,
                              child: Text(
                                '${slot.dayOfWeek} ${slot.period} · ${slot.pillCount} × ${slot.medicationName}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (id) => setState(
                        () => _selectedCompartment = id == null
                            ? null
                            : slots.firstWhere((slot) => slot.id == id),
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            ExpansionTile(
              title: const Text('Before/after times (optional)'),
              subtitle: const Text('Recommended: choose clear, open views'),
              children: [
                const Text(
                  'Seconds: before start/end, then after start/end. Leave all blank for automatic timing.',
                ),
                Row(
                  children: [
                    for (var index = 0; index < _phaseTimes.length; index++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: TextField(
                            controller: _phaseTimes[index],
                            enabled: !_isBusy,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: const [
                                'Before start',
                                'Before end',
                                'After start',
                                'After end',
                              ][index],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            SizedBox(
              height: 160,
              child: _selectedVideo != null
                  ? Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.videocam_rounded,
                            size: 56,
                            color: Colors.white70,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _selectedVideo!.uri.pathSegments.last,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.videocam_outlined,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No video selected',
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (Platform.isIOS || Platform.isAndroid) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isBusy ? null : () => _pick(true),
                      icon: const Icon(Icons.videocam_outlined),
                      label: const Text('Record'),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isBusy ? null : () => _pick(false),
                    icon: const Icon(Icons.video_library_outlined),
                    label: Text(Platform.isMacOS ? 'Choose video' : 'Gallery'),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed:
                    _isBusy ||
                        _selectedVideo == null ||
                        _selectedCompartment == null
                    ? null
                    : _analyze,
                icon: _isBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.analytics_outlined),
                label: Text(_isBusy ? 'Analyzing...' : 'Analyze video'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DoseVerificationResultScreen extends ConsumerStatefulWidget {
  const DoseVerificationResultScreen({super.key, required this.result});
  final DoseVerificationEvent result;

  @override
  ConsumerState<DoseVerificationResultScreen> createState() =>
      _DoseVerificationResultScreenState();
}

class _DoseVerificationResultScreenState
    extends ConsumerState<DoseVerificationResultScreen> {
  static const _labels = {
    'CANDIDATE_SINGLE_REMOVAL': (
      'Possible pill removal',
      Icons.help_outline_rounded,
      Colors.orange,
    ),
    'CANDIDATE_TRANSFER': (
      'Possible pill transfer, not removal',
      Icons.swap_horiz_rounded,
      Colors.orange,
    ),
    'NO_COUNT_CHANGE': (
      'No target count change; not verified',
      Icons.help_outline_rounded,
      Colors.grey,
    ),
    'REMOVED_AS_EXPECTED': (
      'Dose removed',
      Icons.check_circle_rounded,
      Colors.green,
    ),
    'PARTIAL_REMOVAL': (
      'Partial dose removed',
      Icons.warning_amber_rounded,
      Colors.orange,
    ),
    'NO_REMOVAL_DETECTED': (
      'No removal detected',
      Icons.error_outline_rounded,
      Colors.red,
    ),
    'EXTRA_PILL_PRESENT': (
      'Unexpected: pill count increased',
      Icons.priority_high_rounded,
      Colors.red,
    ),
    'MEDICATION_MISMATCH': (
      'Medicine does not match this compartment',
      Icons.warning_amber_rounded,
      Colors.orange,
    ),
    'WRONG_SLOT': (
      'Wrong compartment?',
      Icons.wrong_location_rounded,
      Colors.red,
    ),
    'INCONCLUSIVE': (
      'Could not verify',
      Icons.help_outline_rounded,
      Colors.grey,
    ),
  };

  bool _fixing = false;

  Future<void> _fixOrientation(String columnOrder) async {
    setState(() => _fixing = true);
    try {
      final int userId =
          ref.read(currentUserProvider)?.id ?? ref.read(userIdProvider);
      await ref
          .read(doseVerificationRepositoryProvider)
          .setOrientationProfile(userId: userId, columnOrder: columnOrder);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved. This applies to your next verification.'),
        ),
      );
    } on Exception catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save orientation setting.')),
      );
    } finally {
      if (mounted) setState(() => _fixing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final (label, icon, color) =
        _labels[result.eventType] ??
        ('Unknown result', Icons.help_outline_rounded, Colors.grey);

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Verification result'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(icon, size: 56, color: color.shade700),
                    const SizedBox(height: 12),
                    Text(
                      label,
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Before: ${result.preCount ?? "unknown"} pill(s)  \u2022  After: ${result.postCount ?? "unknown"} pill(s)',
                    ),
                    if (result.recognizedMedication != null) ...[
                      const SizedBox(height: 6),
                      Text('Identified: ${result.recognizedMedication}'),
                    ],
                    if (result.destinationLabel != null)
                      Text('Transfer destination: ${result.destinationLabel}'),
                    if (result.reason != null)
                      Text(result.reason!, textAlign: TextAlign.center),
                    if (result.inventoryUpdated) ...[
                      const SizedBox(height: 6),
                      const Text('Box inventory updated'),
                    ] else if (result.requiresReview ||
                        result.recognizedMedication != null) ...[
                      const SizedBox(height: 6),
                      const Text(
                        'Inventory unchanged; confirm medicine and compartment',
                      ),
                    ],
                    if (result.assumedLabel != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        result.prototype == 'official_blue_pm'
                            ? 'Detected slot: ${result.assumedLabel} (fixed blue PM layout)'
                            : result.orientationCalibrated
                            ? 'Detected slot: ${result.assumedLabel}'
                            : 'Compartment guess: ${result.assumedLabel} (grid position only, not yet calibrated)',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    if (result.expectedLabel != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Expected slot: ${result.expectedLabel}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (result.wrongSlot && result.prototype == 'official_blue_pm')
              const Text(
                'Detected slot differs from your selection. Review the video; the blue PM layout is Sunday to Saturday, left to right.',
                style: TextStyle(color: Colors.red),
              )
            else if (result.wrongSlot)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.wrong_location_rounded, color: Colors.red),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'This looks like the wrong compartment for the selected schedule. If this is actually '
                            'correct, your day order may be flipped — fix it below.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _fixing
                                ? null
                                : () => _fixOrientation('forward'),
                            child: const Text('Sunday is on the left'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _fixing
                                ? null
                                : () => _fixOrientation('reversed'),
                            child: const Text('Sunday is on the right'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              )
            else if (!result.periodConfident)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.help_outline_rounded, color: Colors.grey),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Could not confidently tell AM from PM in this clip, so slot/schedule matching was skipped.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            if (result.requiresReview)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.flag_rounded, color: Colors.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        result.prototype == 'official_blue_pm'
                            ? 'Experimental target-only comparison. Iron may be uncertain. Manual review required; this does not prove ingestion.'
                            : 'Low confidence (${(result.confidence * 100).toStringAsFixed(0)}%) — flagged for manual review.',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              )
            else
              Text(
                'Confidence: ${(result.confidence * 100).toStringAsFixed(0)}%  \u2022  '
                '${result.framesAccepted}/${result.framesSampled} frames usable',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => context.go('/dashboard'),
              icon: const Icon(Icons.home_rounded),
              label: const Text('Return to dashboard'),
            ),
          ],
        ),
      ),
    );
  }
}
