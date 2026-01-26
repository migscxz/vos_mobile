import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vos_mobile/modules/approvals/approvals_panel.dart';
import 'package:vos_mobile/modules/reports/reports_panel.dart';

import '../../../data/models.dart';
import '../../../state/app_state.dart';
import 'content_area.dart';

class Shell extends ConsumerWidget {
  const Shell({super.key});

  int _indexFor(Module m) {
    switch (m) {
      case Module.reports:
        return 0;
      case Module.chats:
        return 0;
      case Module.approvals:
        return 1;
      case Module.profile:
        return 2;
      case Module.dashboard:
        return 0; // default to Reports
    }
  }

  Module _moduleFor(int i) {
    switch (i) {
      case 0:
        return Module.reports;
      case 1:
        return Module.approvals;
      case 2:
        return Module.profile;
      default:
        return Module.reports;
    }
  }

  String _titleFor(Module m) {
    switch (m) {
      case Module.reports:
        return 'Reports';
      case Module.chats:
        return 'Messages';
      case Module.approvals:
        return 'Approvals';
      case Module.profile:
        return 'You';
      case Module.dashboard:
        return 'VOS';
    }
  }

  Widget _panelFor(Module m) {
    switch (m) {
      case Module.reports:
        return const ReportsPanel();
      case Module.approvals:
        return const ApprovalsPanel();
      case Module.chats:
      case Module.profile:
      case Module.dashboard:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final module = ref.watch(moduleProvider);
    final idx = _indexFor(module);
    final width = MediaQuery.of(context).size.width;
    final bool wide = width >= 700; // tablet/landscape breakpoint

    // increased side width when wide
    final double sideW = width < 900 ? 260 : 360;

    final drawer = Drawer(
      width: sideW,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only()),
      child: SafeArea(child: _panelFor(module)),
    );

    return Scaffold(
      // Left drawer for “channels/submodules”
      drawer: drawer,

      // On wide screens keep the drawer content fixed on the left
      body: SafeArea(
        child: Row(
          children: [
            if (wide)
              SizedBox(
                width: sideW,
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: _panelFor(module),
                ),
              ),
            // main content + app bar
            Expanded(
              child: Column(
                children: [
                  // AppBar replacement: compact, discord-like
                  _TopBar(
                    title: _titleFor(module),
                    showMenu: !wide, // only show menu button when drawer is hidden
                  ),
                  const Divider(height: 1),
                  const Expanded(child: ContentArea()),
                ],
              ),
            ),
          ],
        ),
      ),

      // Bottom navigation = main modules (Discord style)
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (i) => ref.read(moduleProvider.notifier).state = _moduleFor(i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.bar_chart_rounded), label: 'Reports'),
          NavigationDestination(icon: Icon(Icons.verified_outlined), label: 'Approvals'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'You'),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  final bool showMenu;
  const _TopBar({required this.title, required this.showMenu});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          if (showMenu)
            IconButton(
              icon: const Icon(Icons.menu_rounded),
              onPressed: () => Scaffold.of(context).openDrawer(),
              tooltip: 'Open panel',
            ),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          // (optional) quick actions per tab could go here
        ],
      ),
    );
  }
}
