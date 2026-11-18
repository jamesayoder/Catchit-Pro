import 'package:flutter/material.dart';
import 'cloud.dart';

/// Server-backed notification inbox. No push notification permission is requested.
class NotificationCenter extends StatefulWidget {
  const NotificationCenter({super.key});
  @override
  State<NotificationCenter> createState() => _NotificationCenterState();
}

class _NotificationCenterState extends State<NotificationCenter> {
  final CloudApi api = CloudApi();
  List<Map<String, dynamic>> items = [];
  bool loading = true;
  bool busy = false;
  String? error;

  @override
  void initState() { super.initState(); reload(); }

  Future<void> reload() async {
    if (!mounted) return;
    setState(() { loading = true; error = null; });
    try {
      final result = await api.list('notifications');
      if (mounted) setState(() => items = result);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> markRead(String id) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await api.request('POST', 'notifications/$id/read');
      await reload();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> markAllRead() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await api.request('POST', 'notifications/read-all');
      await reload();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally { if (mounted) setState(() => busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final unread = items.where((e) => e['readUtc'] == null).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications'), actions: [
        if (unread > 0) TextButton(onPressed: busy ? null : markAllRead, child: const Text('Mark all read')),
        IconButton(tooltip: 'Refresh', onPressed: loading ? null : reload, icon: const Icon(Icons.refresh)),
      ]),
      body: loading ? const Center(child: CircularProgressIndicator())
        : error != null ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(error!, textAlign: TextAlign.center),
            FilledButton(onPressed: reload, child: const Text('Retry')),
          ]))
        : items.isEmpty ? const Center(child: Text('No notifications yet'))
        : RefreshIndicator(onRefresh: reload, child: ListView.builder(
            itemCount: items.length, itemBuilder: (context, index) {
              final item = items[index];
              final unreadItem = item['readUtc'] == null;
              final timestamp = DateTime.tryParse('${item['createdUtc']}')?.toLocal();
              final when = timestamp == null ? '' : '${timestamp.month}/${timestamp.day}/${timestamp.year}';
              return Card(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                child: ListTile(
                  leading: Icon(unreadItem ? Icons.notifications_active : Icons.notifications_none,
                    color: unreadItem ? Theme.of(context).colorScheme.primary : Colors.grey),
                  title: Text('${item['title'] ?? 'Notification'}', style: TextStyle(fontWeight: unreadItem ? FontWeight.bold : FontWeight.normal)),
                  subtitle: Text('${item['body'] ?? ''}\n$when'),
                  isThreeLine: true,
                  trailing: unreadItem ? TextButton(onPressed: busy ? null : () => markRead('${item['id']}'), child: const Text('Read')) : null,
                ),
              );
            },
          )),
    );
  }
}
