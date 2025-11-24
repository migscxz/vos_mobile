import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'ui/shell/shell.dart';

class VOSApp extends StatelessWidget {
  const VOSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'VOS Mobile',
      themeMode: ThemeMode.system,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const Shell(),
    );
  }
}
