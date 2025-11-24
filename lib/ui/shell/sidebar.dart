import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models.dart';
import '../../../state/app_state.dart';

class Sidebar extends ConsumerWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final module = ref.watch(moduleProvider);

    Widget item(IconData icon, Module m, {int badge = 0}) {
      final selected = module == m;
      final iconBtn = IconButton(
        onPressed: () => ref.read(moduleProvider.notifier).state = m,
        icon: Icon(icon, color: Colors.white, size: 22),
        tooltip: m.name,
      );

      return Stack(
        children: [
          // active indicator bar
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            left: 0,
            top: 10,
            bottom: 10,
            width: selected ? 4 : 0,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            decoration: BoxDecoration(
              color: selected ? Colors.white.withOpacity(.18) : Colors.white.withOpacity(.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Stack(
              children: [
                iconBtn,
                if (badge > 0)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('$badge', style: const TextStyle(fontSize: 10, color: Colors.white)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    }

    return Container(
      width: 76,
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 6))],
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          const CircleAvatar(radius: 20, backgroundColor: Colors.white, child: Icon(Icons.check_circle_outline, color: Color(0xFF6B73FF))),
          const SizedBox(height: 16),
          Expanded(
            child: Column(
              children: [
                item(Icons.home_outlined, Module.dashboard),
                item(Icons.bar_chart_rounded, Module.reports),
                item(Icons.chat_bubble_outline, Module.chats, badge: ref.watch(chatsBadgeCountProvider)),
                item(Icons.verified_outlined, Module.approvals, badge: ref.watch(approvalsBadgeCountProvider)),
              ],
            ),
          ),
          item(Icons.person_outline, Module.profile),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
