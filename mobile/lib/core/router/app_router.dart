import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../features/onboarding/presentation/pages/onboarding_page.dart';
import '../../features/onboarding/presentation/pages/permission_page.dart';
import '../../features/scan/presentation/pages/scan_home_page.dart';
import '../../features/scan/presentation/pages/scan_progress_page.dart';
import '../../features/review/presentation/pages/review_page.dart';
import '../../features/review/presentation/pages/group_detail_page.dart';
import '../../features/subscription/presentation/pages/paywall_page.dart';
import '../../features/results/presentation/pages/results_page.dart';
import '../di/injection.dart';

abstract class AppRoutes {
  static const String onboarding = '/onboarding';
  static const String permission = '/permission';
  static const String scanHome = '/';
  static const String scanProgress = '/scan/progress';
  static const String review = '/review';
  static const String groupDetail = '/review/group/:groupId';
  static const String paywall = '/paywall';
  static const String results = '/results';
}

class AppRouter {
  AppRouter._();

  static final GoRouter router = GoRouter(
    initialLocation: AppRoutes.onboarding,
    routes: [
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingPage(),
      ),
      GoRoute(
        path: AppRoutes.permission,
        builder: (context, state) => const PermissionPage(),
      ),
      GoRoute(
        path: AppRoutes.scanHome,
        builder: (context, state) => const ScanHomePage(),
      ),
      GoRoute(
        path: AppRoutes.scanProgress,
        builder: (context, state) => const ScanProgressPage(),
      ),
      GoRoute(
        path: AppRoutes.review,
        builder: (context, state) => const ReviewPage(),
      ),
      GoRoute(
        path: AppRoutes.groupDetail,
        builder: (context, state) => GroupDetailPage(
          groupId: state.pathParameters['groupId']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.paywall,
        builder: (context, state) => const PaywallPage(),
      ),
      GoRoute(
        path: AppRoutes.results,
        builder: (context, state) {
          final extra = state.extra as ResultsPageArgs?;
          return ResultsPage(args: extra ?? const ResultsPageArgs());
        },
      ),
    ],
  );
}
