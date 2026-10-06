import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'shared/providers/providers.dart';

class Plus15App extends ConsumerStatefulWidget {
  const Plus15App({super.key});

  @override
  ConsumerState<Plus15App> createState() => _Plus15AppState();
}

class _Plus15AppState extends ConsumerState<Plus15App> {
  // Back from Settings with location just turned on: pick it up.
  late final _lifecycle = AppLifecycleListener(onResume: () {
    if (ref.read(locationStreamProvider).valueOrNull == null) {
      ref.invalidate(locationStreamProvider);
    }
  });

  @override
  void initState() {
    super.initState();
    _lifecycle;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Plus 15',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(themeModeProvider),
      routerConfig: appRouter,
      // Status-bar icons follow the app theme on screens without an app bar.
      builder: (context, child) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
          ),
          child: child!,
        );
      },
    );
  }
}
