import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/adherence.dart';

void showCaregiverInviteDialog(BuildContext context, WidgetRef ref) {
  final nameCtrl = TextEditingController();
  final relCtrl = TextEditingController(text: 'Family member');
  final phoneCtrl = TextEditingController();
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Invite care team member'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: relCtrl,
            decoration: const InputDecoration(labelText: 'Relationship'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone number'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final name = nameCtrl.text.trim();
            final rel = relCtrl.text.trim();
            final phone = phoneCtrl.text.trim();
            if (name.isEmpty || rel.isEmpty || phone.isEmpty) return;
            ref
                .read(caregiversProvider.notifier)
                .inviteCaregiver(name: name, relation: rel, phone: phone);
            Navigator.of(ctx).pop();
          },
          child: const Text('Send invite'),
        ),
      ],
    ),
  ).whenComplete(() {
    nameCtrl.dispose();
    relCtrl.dispose();
    phoneCtrl.dispose();
  });
}
