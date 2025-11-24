import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class DashboardView extends StatelessWidget {
  const DashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 420; // phones in portrait
        final crossAxisCount = isNarrow ? 1 : 2;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                boxShadow: const [
                  BoxShadow(color: Color(0x336B73FF), blurRadius: 20, offset: Offset(0, 10)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Welcome back', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  SizedBox(height: 4),
                  Text('VOS Mobile', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: GridView.count(
                padding: const EdgeInsets.all(16),
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: isNarrow ? 2.6 : 1.6, // less height on narrow
                children: const [
                  _DashCard(title: 'Reports', subtitle: 'Quick access to KPIs'),
                  _DashCard(title: 'Approvals', subtitle: 'Pending requests'),
                  _DashCard(title: 'Chats', subtitle: 'Team messages'),
                  _DashCard(title: 'Profile', subtitle: 'Your settings'),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DashCard extends StatelessWidget {
  final String title;
  final String subtitle;
  const _DashCard({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 6),
            Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color)),
          ],
        ),
      ),
    );
  }
}
