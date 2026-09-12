import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'shared/providers/side_rail_theme_provider.dart';

/// MaterialApp.router 루트 위젯
class PlaydataApp extends ConsumerWidget {
  const PlaydataApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final palette = ref.watch(sideRailDarkPaletteProvider);

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(
        primary: palette.action,
        primaryLight: palette.actionLight,
      ),
      routerConfig: router,
    );
  }
}
