import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../repositories/medication_repository.dart';
import '../state/adherence.dart';
import '../widgets/app_navigation.dart';

class AlertsListScreen extends ConsumerWidget {
  const AlertsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(activeMedicationAlertsProvider);
    final alertPhone = ref.watch(alertPhoneProvider);
    final adherence = ref.watch(todayAdherenceProvider);
    final userId = ref.watch(userIdProvider);
    final schedules = ref.watch(scheduleByUserProvider(userId));
    final medications = ref.watch(medicationsByUserProvider(userId));
    final loading =
        adherence.isLoading || schedules.isLoading || medications.isLoading;
    final hasError =
        adherence.hasError || schedules.hasError || medications.hasError;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts'),
        leading: const AppBackButton(),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.phone_in_talk_rounded),
              title: const Text('SMS alert number'),
              subtitle: Text(alertPhone),
              trailing: IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => context.push('/settings'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (loading) const LinearProgressIndicator(),
          if (hasError)
            ListTile(
              title: const Text('Could not load medication alerts'),
              trailing: TextButton(
                onPressed: () {
                  ref.invalidate(todayAdherenceProvider);
                  ref.invalidate(scheduleByUserProvider(userId));
                  ref.invalidate(medicationsByUserProvider(userId));
                },
                child: const Text('Retry'),
              ),
            ),
          if (alerts.isEmpty && !loading && !hasError)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: 40,
                      color: Colors.green,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'All caught up! No active alerts.',
                      textAlign: TextAlign.center,
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
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(icon, color: color),
                title: Text(a.title),
                subtitle: Text('${a.message}\n\nSMS target: $alertPhone'),
                onTap: () => context.go('/dashboard'),
                isThreeLine: true,
                trailing: entry.key < ref.watch(alertsProvider).length
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'Dismiss',
                        onPressed: () => ref
                            .read(alertsProvider.notifier)
                            .dismiss(entry.key),
                      )
                    : null,
              ),
            );
          }),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 1,
        onDestinationSelected: (index) {
          if (index == 0) context.go('/dashboard');
          if (index == 2) context.go('/caregiver');
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(
            icon: Icon(Icons.notifications),
            label: 'Alerts',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_alt_outlined),
            label: 'Care',
          ),
        ],
      ),
    );
  }
}
