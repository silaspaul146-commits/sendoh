import 'package:flutter/material.dart';
import 'api.dart';
import 'design.dart';
import 'invitations.dart';
import 'main.dart' show CollectionDetail;
import 'push_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen(
      {super.key, required this.api, required this.userId});
  final SendohApi api;
  final String userId;
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<dynamic> rows = [];
  String? cursor, error;
  bool busy = false,
      changingPush = false,
      pushAvailable = false,
      optedIn = false;

  @override
  void initState() {
    super.initState();
    load();
    PushService.updates.addListener(onUpdate);
  }

  @override
  void dispose() {
    PushService.updates.removeListener(onUpdate);
    super.dispose();
  }

  void onUpdate() {
    PushService.pendingOpen = false;
    if (!busy) {
      load();
    }
  }

  Future<void> load({bool more = false}) async {
    if (busy) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data = await widget.api.request(
          '/me/notifications${more && cursor != null ? '?before=${Uri.encodeQueryComponent(cursor!)}' : ''}');
      final opt = await PushService.optedIn(widget.userId);
      if (mounted) {
        setState(() {
          rows = more
              ? [...rows, ...data['items']]
              : List<dynamic>.from(data['items']);
          cursor = data['next_cursor'] as String?;
          pushAvailable = data['push_available'] == true;
          optedIn = opt;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = '$e');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> togglePush() async {
    setState(() => changingPush = true);
    try {
      String message;
      if (optedIn) {
        await PushService.disable(widget.api, widget.userId);
        message =
            'Push alerts disabled on this device. Your inbox is still available.';
      } else {
        message = await PushService.enable(widget.api, widget.userId);
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not update push alerts: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => changingPush = false);
      }
    }
  }

  Future<void> open(Map<String, dynamic> item) async {
    try {
      await widget.api
          .request('/me/notifications/${item['id']}/read', body: {});
      if (!mounted) {
        return;
      }
      if (['ACCEPTED', 'DECLINED'].contains(item['kind'])) {
        final data =
            await widget.api.request('/collections/${item['collection_id']}');
        if (!mounted) {
          return;
        }
        await Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => CollectionDetail(
                api: widget.api, data: Map<String, dynamic>.from(data))));
      } else {
        await Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => InvitationsScreen(api: widget.api)));
      }
      if (mounted) {
        await load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Notifications'), actions: [
          IconButton(
              tooltip: 'Refresh notifications',
              onPressed: busy ? null : () => load(),
              icon: const Icon(Icons.refresh)),
        ]),
        body: RefreshIndicator(
            onRefresh: () => load(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(22),
              children: [
                const Text('Stay in the loop.',
                    style:
                        TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                const Text(
                    'Your invitations and collection updates, all in one place.',
                    style:
                        TextStyle(color: SendohColors.secondary, height: 1.6)),
                const SizedBox(height: 20),
                SurfaceCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      const Text('Push alerts',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text(
                          pushAvailable && PushService.enabled
                              ? 'Get an alert when there is an update. Names and amounts stay inside the app.'
                              : 'Push is not configured yet. Your updates will still appear here.',
                          style: const TextStyle(fontSize: 13, height: 1.6)),
                      if (pushAvailable &&
                          PushService.enabled &&
                          widget.userId.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        OutlinedButton(
                            onPressed: changingPush ? null : togglePush,
                            child: Text(changingPush
                                ? 'Updating…'
                                : optedIn
                                    ? 'Disable push alerts'
                                    : 'Enable push alerts')),
                      ],
                    ])),
                const SizedBox(height: 24),
                if (busy) const LinearProgressIndicator(),
                if (error != null) ...[
                  Text(error!, style: const TextStyle(color: SendohColors.red)),
                  TextButton(
                      onPressed: busy ? null : () => load(),
                      child: const Text('Try again')),
                ],
                if (!busy && error == null && rows.isEmpty)
                  const EmptyState(
                      title: 'You’re all caught up',
                      message:
                          'New invitations and responses will appear here.',
                      icon: Icons.notifications_none),
                ...rows.map((raw) {
                  final item = Map<String, dynamic>.from(raw);
                  final unread = item['read_at'] == null;
                  return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SurfaceCard(
                          color: unread
                              ? SendohColors.tealSoft
                              : SendohColors.surface,
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                                unread
                                    ? Icons.mark_email_unread_outlined
                                    : Icons.drafts_outlined,
                                color: SendohColors.teal),
                            title: Text(item['title'] as String,
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: unread
                                        ? FontWeight.w600
                                        : FontWeight.w400)),
                            subtitle: Text(
                                '${item['collection_name']}\n${displayDate(DateTime.fromMillisecondsSinceEpoch((item['created_at'] as int) * 1000, isUtc: true).toIso8601String())}${item['kind'] == 'INVITED' && item['invitation_available'] == false ? '\nInvitation is no longer pending' : ''}'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => open(item),
                          )));
                }),
                if (cursor != null)
                  OutlinedButton(
                      onPressed: busy ? null : () => load(more: true),
                      child: const Text('Load older updates')),
              ],
            )),
      );
}
