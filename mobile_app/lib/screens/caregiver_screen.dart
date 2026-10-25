import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/adherence.dart';
import '../state/prescriptions.dart';
import '../widgets/app_navigation.dart';
import '../widgets/caregiver_invite_dialog.dart';

class CaregiverScreen extends ConsumerWidget {
  const CaregiverScreen({super.key});

  Widget _statusBadge(String status) {
    final color = status == 'Connected'
        ? Colors.green
        : status == 'Pending'
        ? Colors.orange
        : Colors.blue;
    return Chip(
      label: Text(
        status,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
      backgroundColor: color.withValues(alpha: 0.12),
      padding: EdgeInsets.zero,
      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caregivers = ref.watch(caregiversProvider);
    final pending = ref.watch(pendingPrescriptionsProvider);
    final awaitingCount = pending
        .where((p) => p.status == VerificationStatus.awaitingVerifier)
        .length;

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Care team'),
      ),
      bottomNavigationBar: const AppNavigationBar(selectedIndex: 2),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Prescription review queue
          if (awaitingCount > 0) ...[
            Card(
              color: Colors.orange.shade50,
              child: ListTile(
                leading: const Icon(
                  Icons.pending_actions_rounded,
                  color: Colors.orange,
                ),
                title: Text(
                  '$awaitingCount prescription${awaitingCount == 1 ? '' : 's'} need${awaitingCount == 1 ? 's' : ''} review',
                ),
                subtitle: const Text('Tap to open the verification queue'),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                onTap: () => context.push('/prescription-queue'),
              ),
            ),
            const SizedBox(height: 12),
          ],
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
                trailing: _statusBadge(c.status),
              ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => showCaregiverInviteDialog(context, ref),
            icon: const Icon(Icons.group_add_rounded),
            label: const Text('Invite care team member'),
          ),
        ],
      ),
    );
  }
}
