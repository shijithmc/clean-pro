import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/constants/app_constants.dart';
import 'core/di/injection.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/scan/application/bloc/scan_bloc.dart';
import 'features/subscription/application/bloc/subscription_bloc.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // FA-004: Fail fast in debug/profile builds if required --dart-define values
  // are absent. assert() is compiled out in release — runtime misconfig in
  // release is surfaced by Sentry (once the DSN is provided and init'd below).
  AppConstants.assertConfigured();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await configureDependencies();

  runApp(const CleanProApp());
}

class CleanProApp extends StatelessWidget {
  const CleanProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        // FA-001: ScanBloc was used by ScanHomePage but never registered here —
        // pages were constructing it via getIt() inline, bypassing the BLoC tree
        // and leaking instances across navigations.
        BlocProvider(create: (_) => getIt<ScanBloc>()),
        BlocProvider(create: (_) => getIt<SubscriptionBloc>()..add(const SubscriptionCheckRequested())),
      ],
      child: MaterialApp.router(
        title: 'Clean Pro',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
        routerConfig: AppRouter.router,
        locale: const Locale('en'),
      ),
    );
  }
}
