import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../repositories/medication_repository.dart';
import '../state/adherence.dart';
import '../widgets/app_navigation.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _notifications = true;
  late final TextEditingController _alertPhoneController;

  @override
  void initState() {
    super.initState();
    _alertPhoneController = TextEditingController(
      text: ref.read(alertPhoneProvider),
    );
  }

  @override
  void dispose() {
    _alertPhoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (currentUser != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .primaryContainer,
                      child: Text(
                        currentUser.fullName.isNotEmpty
                            ? currentUser.fullName[0].toUpperCase()
                            : '?',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentUser.fullName,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            currentUser.email,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (currentUser.phone != null)
                            Text(
                              currentUser.phone!,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          SwitchListTile(
            value: _notifications,
            title: const Text('Push notifications'),
            subtitle: const Text('Receive dose reminders'),
            onChanged: (v) => setState(() => _notifications = v),
          ),
          const Divider(),
          const SizedBox(height: 8),
          TextField(
            controller: _alertPhoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'SMS alert phone number',
              prefixIcon: Icon(Icons.phone_iphone_rounded),
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => ref.read(alertPhoneProvider.notifier).update(v),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () {
              ref
                  .read(alertPhoneProvider.notifier)
                  .update(_alertPhoneController.text);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Alert phone number saved')),
              );
            },
            icon: const Icon(Icons.check_rounded),
            label: const Text('Save alert number'),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => context.go('/login'),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
          ),
        ],
      ),
    );
  }
}
