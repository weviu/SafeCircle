import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../providers.dart';
import 'notifications_repository.dart';
import 'push_controller.dart';

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (ref) => NotificationsRepository(ref.watch(dioProvider)),
);

final pushControllerProvider = ChangeNotifierProvider<PushController>((ref) {
  // The legacy ChangeNotifierProvider disposes its notifier itself on teardown,
  // so no ref.onDispose here (that would double-dispose the controller).
  return PushController(
    repository: ref.watch(notificationsRepositoryProvider),
    dio: ref.watch(dioProvider),
  );
});