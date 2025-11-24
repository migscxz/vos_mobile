import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/app_state.dart';
import '../../data/models.dart';

class ChatView extends ConsumerWidget {
  const ChatView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<ConversationSummary> convos = ref.watch(conversationsProvider);
    final String? selectedId = ref.watch(selectedConversationIdProvider);

    // ✅ Never return null from firstWhere's orElse; compute nullable safely first.
    final ConversationSummary? convo = convos.isEmpty
        ? null
        : (selectedId == null
        ? convos.first
        : convos.firstWhere(
          (c) => c.id == selectedId,
      orElse: () => convos.first,
    ));

    if (convo == null) {
      return const Center(child: Text('No conversations'));
    }

    final messages = List.generate(18, (i) {
      final isMe = (i % 3) == 0;
      return _Msg(
        me: isMe,
        text: isMe ? 'Update on ${convo.name}? ($i)' : 'Copy that, noted ($i)',
        time: '11:${(10 + i).toString().padLeft(2, '0')}',
      );
    });

    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          alignment: Alignment.centerLeft,
          child: Text(
            convo.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const Divider(height: 1),
        // Messages
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: messages.length,
            itemBuilder: (_, i) {
              final m = messages[i];
              return Align(
                alignment: m.me ? Alignment.centerRight : Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: m.me
                          ? Theme.of(context).colorScheme.primary.withOpacity(.12)
                          : Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.text, softWrap: true),
                        const SizedBox(height: 4),
                        Text(m.time, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        // Composer
        SafeArea(
          top: false,
          minimum: EdgeInsets.only(bottom: bottomPadding > 0 ? 0 : 8),
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, 6, 12, 12 + (bottomPadding > 0 ? bottomPadding : 0)),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: 'Message…',
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                      border: OutlineInputBorder(
                        borderSide: BorderSide.none,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(onPressed: () {}, icon: const Icon(Icons.send), tooltip: 'Send'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Msg {
  final bool me;
  final String text;
  final String time;
  _Msg({required this.me, required this.text, required this.time});
}
