import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../notifications/notifications_models.dart';
import '../notifications/notifications_providers.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<AppNotification>? _items;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _items = null;
      _error = null;
    });
    try {
      final result = await ref
          .read(notificationsRepositoryProvider)
          .list(limit: 50);
      if (!mounted) return;
      setState(() => _items = result.items);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Bildirimler yüklenemedi.');
    }
  }

  /// Pull-to-refresh: keeps the current rows on screen while re-fetching, so
  /// the RefreshIndicator's own spinner is the only loading feedback.
  Future<void> _refresh() async {
    try {
      final result = await ref
          .read(notificationsRepositoryProvider)
          .list(limit: 50);
      if (!mounted) return;
      await ref.read(pushControllerProvider).refreshUnread();
      if (!mounted) return;
      setState(() {
        _items = result.items;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Bildirimler yenilenemedi.')));
    }
  }

  Future<void> _markRead(AppNotification notification) async {
    if (notification.isRead || _busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(notificationsRepositoryProvider).markRead(notification.id);
      await ref.read(pushControllerProvider).refreshUnread();
      if (!mounted) return;
      setState(() {
        _items = [
          for (final item in _items ?? const <AppNotification>[])
            if (item.id == notification.id)
              AppNotification(
                id: item.id,
                type: item.type,
                title: item.title,
                body: item.body,
                data: item.data,
                readAt: DateTime.now(),
                createdAt: item.createdAt,
              )
            else
              item,
        ];
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Okundu işaretlenemedi.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markAllRead() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(notificationsRepositoryProvider).markAllRead();
      await ref.read(pushControllerProvider).refreshUnread();
      if (!mounted) return;
      setState(() => _items = [
        for (final item in _items ?? const <AppNotification>[])
          AppNotification(
            id: item.id,
            type: item.type,
            title: item.title,
            body: item.body,
            data: item.data,
            readAt: DateTime.now(),
            createdAt: item.createdAt,
          ),
      ]);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Bildirimler okundu sayılamadı.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bildirimler'),
        actions: [
          if ((_items ?? const []).any((item) => !item.isRead))
            TextButton(
              key: const Key('mark-all-read'),
              onPressed: _busy ? null : _markAllRead,
              child: const Text('Tümünü okundu'),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 8),
            FilledButton(onPressed: _load, child: const Text('Tekrar dene')),
          ],
        ),
      );
    }
    final items = _items;
    if (items == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(onRefresh: _refresh, child: _scrollable(items));
  }

  /// AlwaysScrollableScrollPhysics so the empty state stays pullable too.
  Widget _scrollable(List<AppNotification> items) {
    if (items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 160),
          Center(child: Text('Bildirim yok')),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) => _notificationTile(items[index]),
    );
  }

  Widget _notificationTile(AppNotification notification) {
    final theme = Theme.of(context);
    final isUnread = !notification.isRead;
    final when = notification.createdAt.toLocal();
    return ListTile(
      key: ValueKey('notification-${notification.id}'),
      leading: Icon(
        isUnread ? Icons.circle : Icons.circle_outlined,
        color: isUnread ? theme.colorScheme.primary : theme.disabledColor,
      ),
      title: Text(
        notification.title,
        style: isUnread ? theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold) : null,
      ),
      subtitle: Text(notification.body),
      isThreeLine: true,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${when.day.toString().padLeft(2, '0')}.${when.month.toString().padLeft(2, '0')}',
            style: theme.textTheme.bodySmall,
          ),
          if (isUnread)
            Text('Yeni', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary)),
        ],
      ),
      onTap: isUnread ? () => _markRead(notification) : null,
    );
  }
}