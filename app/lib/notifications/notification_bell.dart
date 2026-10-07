import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../notifications/notifications_providers.dart';

/// App-bar bell with an unread badge; opens the notifications inbox.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasUnread = ref.watch(
      pushControllerProvider.select((controller) => controller.hasUnread),
    );
    return IconButton(
      key: const Key('notifications-bell'),
      tooltip: 'Bildirimler',
      onPressed: () => context.push('/notifications'),
      icon: Badge(
        isLabelVisible: hasUnread,
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}