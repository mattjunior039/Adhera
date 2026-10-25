import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/dose_verification_repository.dart';
import '../repositories/medication_repository.dart';
import '../widgets/app_navigation.dart';
import '../widgets/time_labels.dart';

class VerificationHistoryScreen extends ConsumerWidget {
  const VerificationHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(userIdProvider);
    final asyncEvents = ref.watch(doseVerificationEventsProvider(userId));

    Widget buildList(List<DoseVerificationEvent> events) => ListView(
      children: events
          .map(
            (e) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.green.shade100,
                  child: const Icon(
                    Icons.verified_rounded,
                    color: Colors.green,
                  ),
                ),
                title: Text(
                  '${e.recognizedMedication ?? 'Unclassified'} · ${e.eventType}',
                ),
                subtitle: Text(
                  '${relativeTime(e.createdAt)} · ${e.preCount ?? '?'} → ${e.postCount ?? '?'} pills',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
              ),
            ),
          )
          .toList(),
    );

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Verification history'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: asyncEvents.when(
          data: (events) => events.isEmpty
              ? const Center(child: Text('No video verification history yet.'))
              : buildList(events),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Could not load history: $e')),
        ),
      ),
    );
  }
}
