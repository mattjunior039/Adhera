import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/schedule.dart';
import '../repositories/adhera_inventory_repository.dart';
import '../repositories/dose_verification_repository.dart';
import '../repositories/medication_repository.dart';
import '../repositories/sample_day_provider.dart';
import '../services/api_service.dart';
import '../state/adherence.dart';
import '../state/prescriptions.dart';
import '../widgets/caregiver_invite_dialog.dart';
import '../widgets/time_labels.dart';
import '../widgets/weekly_schedule.dart';

class HomeDashboardScreen extends ConsumerWidget {
  const HomeDashboardScreen({super.key});

  Widget _buildTodaySchedule(
    BuildContext context,
    WidgetRef ref,
    List<Schedule> schedules,
    Map<int, String> medicationNames,
    String todayName,
    Set<int> takenIds,
    Map<int, String> verifiedStatuses,
  ) {
    final todaySchedules =
        schedules
            .where((s) => s.dayOfWeek.toLowerCase() == todayName.toLowerCase())
            .toList()
          ..sort((a, b) => a.timeOfDay.compareTo(b.timeOfDay));

    if (todaySchedules.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Icon(
                Icons.event_available_rounded,
                size: 40,
                color: Colors.green,
              ),
              const SizedBox(height: 8),
              const Text(
                'No medications scheduled for today.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => context.push('/add-medication'),
                icon: const Icon(Icons.add),
                label: const Text('Add a medication'),
              ),
            ],
          ),
        ),
      );
    }

    final doneCount = todaySchedules
        .where((s) => takenIds.contains(s.id))
        .length;
    Widget buildDoseCard(Schedule s) {
      final taken = takenIds.contains(s.id);
      final verified = verifiedStatuses[s.id];
      final medName = medicationNames[s.medicationId] ?? 'Medication';
      final note = (s.notes != null && s.notes!.trim().isNotEmpty)
          ? '  \u2022  ${s.notes}'
          : '';
      return Card(
        key: ValueKey('dose-${s.id}'),
        margin: const EdgeInsets.only(bottom: 10),
        color: taken
            ? Colors.green.shade50
            : verified == 'missed'
            ? Colors.red.shade50
            : null,
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: taken
                ? Colors.green.shade400
                : Theme.of(context).colorScheme.primary,
            child: Icon(
              taken
                  ? Icons.check_rounded
                  : verified == 'missed'
                  ? Icons.warning_rounded
                  : Icons.medication_rounded,
              color: Colors.white,
            ),
          ),
          title: Text(
            medName,
            style: taken
                ? TextStyle(
                    decoration: TextDecoration.lineThrough,
                    color: Colors.grey.shade600,
                  )
                : null,
          ),
          onTap: () => showMedicationInstructions(
            context,
            s,
            ref
                .read(medicationsByUserProvider(ref.read(userIdProvider)))
                .asData
                ?.value
                .where((med) => med.id == s.medicationId)
                .firstOrNull,
          ),
          subtitle: Row(
            children: [
              Expanded(child: Text('${s.timeOfDay}$note')),
              if (verified == 'taken') ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.verified_rounded,
                        size: 11,
                        color: Colors.green.shade700,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        ref.watch(isSampleProfileProvider)
                            ? 'Complete'
                            : 'Verified',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (verified == 'missed') ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.warning_rounded,
                        size: 11,
                        color: Colors.red.shade600,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'Missed',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.red.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          trailing: taken
              ? IconButton(
                  icon: const Icon(Icons.undo_rounded, color: Colors.grey),
                  tooltip: 'Undo',
                  onPressed: () =>
                      _updateDoseStatus(context, ref, s.id, 'unknown'),
                )
              : IconButton(
                  icon: const Icon(
                    Icons.check_circle_outline_rounded,
                    color: Colors.green,
                  ),
                  tooltip: 'Mark taken',
                  onPressed: () =>
                      _updateDoseStatus(context, ref, s.id, 'taken'),
                ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: LinearProgressIndicator(
                value: doneCount / todaySchedules.length,
                borderRadius: BorderRadius.circular(4),
                minHeight: 8,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '$doneCount / ${todaySchedules.length}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...todaySchedules
            .where(
              (s) =>
                  !takenIds.contains(s.id) &&
                  verifiedStatuses[s.id] != 'missed',
            )
            .map(buildDoseCard),
        if (doneCount > 0 ||
            todaySchedules.any((s) => verifiedStatuses[s.id] == 'missed'))
          ExpansionTile(
            key: PageStorageKey(
              'completed-doses-${ref.watch(userIdProvider)}-$todayName',
            ),
            leading: const Icon(
              Icons.check_circle_rounded,
              color: Colors.green,
            ),
            title: Text('Completed ($doneCount)'),
            subtitle:
                todaySchedules.any((s) => verifiedStatuses[s.id] == 'missed')
                ? Text(
                    '${todaySchedules.where((s) => verifiedStatuses[s.id] == 'missed').length} missed',
                  )
                : null,
            children: todaySchedules
                .where(
                  (s) =>
                      takenIds.contains(s.id) ||
                      verifiedStatuses[s.id] == 'missed',
                )
                .map(buildDoseCard)
                .toList(),
          ),
      ],
    );
  }

  Future<void> _updateDoseStatus(
    BuildContext context,
    WidgetRef ref,
    int scheduleId,
    String status,
  ) async {
    if (ref.read(isSampleProfileProvider)) {
      ref.read(sampleDoseStatusesProvider.notifier).update(scheduleId, status);
      return;
    }
    try {
      await ref
          .read(medicationRepositoryProvider)
          .logDose(
            userId: ref.read(userIdProvider),
            scheduleId: scheduleId,
            status: status,
            confidence: 1.0,
          );
      ref.invalidate(todayAdherenceProvider);
    } on Exception catch (error) {
      if (context.mounted) {
        final message = error is ApiException
            ? error.message
            : error.toString();
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  Widget _caregiverBadge(String status) {
    if (status == 'Connected') {
      return const Icon(Icons.check_circle_rounded, color: Colors.green);
    }
    if (status == 'Pending') {
      return const Icon(Icons.schedule_rounded, color: Colors.orange);
    }
    return const Icon(Icons.mail_rounded, color: Colors.blue);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(userIdProvider);
    final medicationsState = ref.watch(medicationsByUserProvider(userId));
    final schedulesState = ref.watch(scheduleByUserProvider(userId));
    final inventoryState = ref.watch(adheraInventoryProvider(userId));
    final eventsState = ref.watch(doseVerificationEventsProvider(userId));
    final adherenceState = ref.watch(todayAdherenceProvider);
    if (medicationsState.isLoading || schedulesState.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (medicationsState.hasError || schedulesState.hasError) {
      return Scaffold(
        appBar: AppBar(title: const Text('Adhera')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 40),
                const SizedBox(height: 12),
                const Text(
                  'Could not load your account data from the backend.',
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    ref.invalidate(medicationsByUserProvider(userId));
                    ref.invalidate(scheduleByUserProvider(userId));
                    ref.invalidate(adheraInventoryProvider(userId));
                    ref.invalidate(doseVerificationEventsProvider(userId));
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final alerts = ref.watch(activeMedicationAlertsProvider);
    final medications = medicationsState.requireValue;
    final schedules = schedulesState.requireValue;
    final inventory =
        inventoryState.asData?.value ?? const <AdheraInventorySlot>[];
    final photoEvents =
        eventsState.asData?.value ?? const <DoseVerificationEvent>[];
    final caregivers = ref.watch(caregiversProvider);
    final pending = ref.watch(pendingPrescriptionsProvider);
    final adherence = adherenceState.asData?.value ?? {};
    final takenIds = adherence.entries
        .where((entry) => entry.value == 'taken')
        .map((entry) => entry.key)
        .toSet();
    final todayName = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ][ref.watch(displayedWeekdayProvider) - 1];
    final medNames = {for (final m in medications) m.id: m.name};
    final compartmentByKey = {
      for (final slot in inventory) '${slot.dayOfWeek}_${slot.period}': slot,
    };
    final awaitingReview = pending
        .where((p) => p.status == VerificationStatus.awaitingVerifier)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Adhera'),
        actions: [
          IconButton(
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Today\u2019s schedule',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          _buildTodaySchedule(
            context,
            ref,
            schedules,
            medNames,
            todayName,
            takenIds,
            adherence,
          ),
          const SizedBox(height: 18),
          if (adherenceState.hasError)
            ListTile(
              title: const Text('Could not load dose completion status'),
              trailing: TextButton(
                onPressed: () => ref.invalidate(todayAdherenceProvider),
                child: const Text('Retry'),
              ),
            ),
          // Quick actions
          Text('Quick actions', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.5,
            children: [
              _ActionCard(
                icon: Icons.add_circle_outline_rounded,
                label: 'Add medication',
                onTap: () => context.push('/add-medication'),
              ),
              _ActionCard(
                icon: Icons.search_rounded,
                label: 'Identify pill',
                onTap: () => context.push('/analyze-pill'),
              ),
              _ActionCard(
                icon: Icons.document_scanner_rounded,
                label: 'Scan label',
                onTap: () => context.push('/scan-prescription'),
              ),
              _ActionCard(
                icon: Icons.calendar_month_rounded,
                label: 'Set schedule',
                onTap: () => context.push('/schedule'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // Medications list
          Text('Medications', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ...medications.map(
            (med) => Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .primaryContainer,
                  child: Icon(
                    Icons.medication_rounded,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                title: Text(med.name),
                subtitle: Text(
                  [
                    if (med.dosage != null) med.dosage!,
                    if (med.instructions != null) med.instructions!,
                  ].join('  \u2022  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.info_outline),
                  tooltip: 'View / edit',
                  onPressed: () => context.push('/medication/${med.id}'),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const SizedBox(height: 18),
          if (schedules.any((s) => s.notes?.startsWith('DEMO ONLY:') == true))
            WeeklySchedule(schedules: schedules, medications: medications)
          else ...[
            Text(
              'Weekly Adhera contents',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (inventoryState.isLoading) const LinearProgressIndicator(),
            if (inventoryState.hasError)
              ListTile(
                title: const Text('Could not load Adhera inventory'),
                trailing: TextButton(
                  onPressed: () =>
                      ref.invalidate(adheraInventoryProvider(userId)),
                  child: const Text('Retry'),
                ),
              ),
            for (final day
                in const [
                  'Sunday',
                  'Monday',
                  'Tuesday',
                  'Wednesday',
                  'Thursday',
                  'Friday',
                  'Saturday',
                ].where(
                  (day) => const ['AM', 'PM'].every(
                    (period) => compartmentByKey.containsKey('${day}_$period'),
                  ),
                )) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Text(day, style: Theme.of(context).textTheme.titleSmall),
              ),
              Row(
                children: [
                  for (final period in const ['AM', 'PM']) ...[
                    if (period == 'PM') const SizedBox(width: 8),
                    Expanded(
                      child: Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          dense: true,
                          leading: Icon(
                            period == 'AM'
                                ? Icons.wb_sunny_outlined
                                : Icons.nightlight_outlined,
                          ),
                          title: Text(
                            '$period · ${compartmentByKey['${day}_$period']!.medicationName}',
                          ),
                          subtitle: Text(
                            '${compartmentByKey['${day}_$period']!.pillCount} pill(s) in compartment',
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
          const SizedBox(height: 18),
          // Recent verifications
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent verifications',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              TextButton(
                onPressed: () => context.push('/history'),
                child: const Text('View all'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (eventsState.isLoading) const LinearProgressIndicator(),
          if (eventsState.hasError)
            ListTile(
              title: const Text('Could not load recent verifications'),
              trailing: TextButton(
                onPressed: () =>
                    ref.invalidate(doseVerificationEventsProvider(userId)),
                child: const Text('Retry'),
              ),
            ),
          ...photoEvents
              .take(3)
              .map(
                (e) => Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.videocam_outlined),
                    ),
                    title: Text(
                      '${e.recognizedMedication ?? 'Video'} · ${e.eventType}',
                    ),
                    subtitle: Text(relativeTime(e.createdAt)),
                    trailing: const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 16,
                    ),
                    onTap: () =>
                        context.push('/dose-verification-result', extra: e),
                  ),
                ),
              ),
          const SizedBox(height: 18),
          // Prescriptions awaiting verifier review
          if (awaitingReview > 0) ...[
            Card(
              color: Colors.orange.shade50,
              child: ListTile(
                leading: const Icon(
                  Icons.pending_actions_rounded,
                  color: Colors.orange,
                ),
                title: Text(
                  '$awaitingReview prescription${awaitingReview == 1 ? '' : 's'} pending review',
                ),
                subtitle: const Text(
                  'A care team member needs to verify these',
                ),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                onTap: () => context.push('/prescription-queue'),
              ),
            ),
            const SizedBox(height: 18),
          ],
          // Active alerts with dismiss
          Text('Active alerts', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (alerts.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Colors.green),
                    const SizedBox(width: 12),
                    Text(
                      'No active alerts',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          ...alerts.asMap().entries.map((entry) {
            final a = entry.value;
            final color = a.severity == 'High'
                ? Colors.red
                : a.severity == 'Medium'
                ? Colors.orange
                : Colors.blue;
            final icon = a.severity == 'High'
                ? Icons.error_rounded
                : a.severity == 'Medium'
                ? Icons.warning_rounded
                : Icons.info_rounded;
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: Icon(icon, color: color),
                title: Text(a.title),
                subtitle: Text(a.message),
                trailing: entry.key < ref.watch(alertsProvider).length
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        tooltip: 'Dismiss',
                        onPressed: () => ref
                            .read(alertsProvider.notifier)
                            .dismiss(entry.key),
                      )
                    : null,
              ),
            );
          }),
          const SizedBox(height: 18),
          // Care team
          Text('Care team', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ...caregivers.map(
            (c) => Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: c.status == 'Connected'
                      ? Colors.green.shade100
                      : Colors.orange.shade100,
                  child: Icon(
                    Icons.person_rounded,
                    color: c.status == 'Connected'
                        ? Colors.green.shade700
                        : Colors.orange.shade700,
                  ),
                ),
                title: Text(c.name),
                subtitle: Text(
                  '${c.relation}${c.phone != null ? "  \u2022  ${c.phone}" : ""}',
                ),
                trailing: _caregiverBadge(c.status),
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => showCaregiverInviteDialog(context, ref),
            icon: const Icon(Icons.group_add_rounded),
            label: const Text('Invite care team member'),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (i) {
          if (i == 1) {
            context.go('/alerts');
          } else if (i == 2) {
            context.go('/caregiver');
          } else {
            context.go('/dashboard');
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            selectedIcon: Icon(Icons.notifications),
            label: 'Alerts',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_alt_outlined),
            selectedIcon: Icon(Icons.people_alt),
            label: 'Care',
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 24),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
