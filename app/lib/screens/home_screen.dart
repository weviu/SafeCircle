import 'package:flutter/material.dart';

/// Landing shell for roles whose real screens arrive in a later phase.
class PlaceholderHome extends StatelessWidget {
  const PlaceholderHome({super.key, required this.role});

  /// Lowercase role, e.g. `counselor`.
  final String role;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SafeCircle')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Hello, $role',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '${role.toUpperCase()} screens arrive in Phase 4',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
