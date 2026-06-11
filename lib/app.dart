import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';

class Plus15App extends StatelessWidget {
  const Plus15App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Plus15 Navigator',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: appRouter,
    );
  }
}
