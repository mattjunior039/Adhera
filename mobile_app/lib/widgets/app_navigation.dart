import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Back',
    icon: const Icon(Icons.arrow_back),
    onPressed: () {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/dashboard');
      }
    },
  );
}

class AppNavigationBar extends StatelessWidget {
  const AppNavigationBar({super.key, required this.selectedIndex});

  final int selectedIndex;

  @override
  Widget build(BuildContext context) => NavigationBar(
    selectedIndex: selectedIndex,
    onDestinationSelected: (index) {
      if (index != selectedIndex) {
        context.go(const ['/dashboard', '/alerts', '/caregiver'][index]);
      }
    },
    destinations: const [
      NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
      NavigationDestination(
        icon: Icon(Icons.notifications_outlined),
        label: 'Alerts',
      ),
      NavigationDestination(
        icon: Icon(Icons.people_alt_outlined),
        label: 'Care',
      ),
    ],
  );
}
