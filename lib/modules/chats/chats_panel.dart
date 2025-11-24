import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/app_state.dart';
import '../../data/models.dart';

class ChatsPanel extends ConsumerWidget {
  const ChatsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final convos = ref.watch(conversationsProvider);

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: convos.length,
      itemBuilder: (_, i) {
        final c = convos[i];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: ListTile(
            leading: CircleAvatar(child: Text(c.name.isNotEmpty ? c.name[0] : '?')),
            title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(c.lastMessage, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: c.unread > 0
                ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(10)),
              child: Text('${c.unread}', style: const TextStyle(color: Colors.white, fontSize: 10)),
            )
                : null,
            onTap: () {
              ref.read(selectedConversationIdProvider.notifier).state = c.id;
              if (Navigator.of(context).canPop()) Navigator.of(context).pop();
              ref.read(moduleProvider.notifier).state = Module.chats;
            },
          ),
        );
      },
    );
  }
}
