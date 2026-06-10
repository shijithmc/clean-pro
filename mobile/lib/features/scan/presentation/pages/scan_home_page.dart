import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../../core/router/app_router.dart';
import '../../../results/presentation/pages/results_page.dart';
import '../../../subscription/application/bloc/subscription_bloc.dart';
import '../../../subscription/domain/entities/subscription_status.dart';
import '../../application/bloc/scan_bloc.dart';
import '../../domain/entities/scan_session.dart';

class ScanHomePage extends StatelessWidget {
  const ScanHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clean Pro'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {/* TODO settings page v2 */},
          ),
        ],
      ),
      body: BlocBuilder<SubscriptionBloc, SubscriptionState>(
        builder: (context, subState) {
          return BlocConsumer<ScanBloc, ScanState>(
            listener: (context, scanState) {
              if (scanState is ScanPermissionDenied) {
                _showPermissionDeniedDialog(context);
              } else if (scanState is ScanInProgress) {
                context.go(AppRoutes.scanProgress);
              } else if (scanState is ScanDeleteCompleted) {
                context.go(
                  AppRoutes.results,
                  extra: ResultsPageArgs(
                    photosDeleted: scanState.photosDeleted,
                    bytesReclaimed: scanState.bytesReclaimed,
                  ),
                );
              }
            },
            builder: (context, scanState) {
              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 24),
                      if (subState is SubscriptionLoaded) ...[
                        _SubscriptionBanner(status: subState.status),
                        const SizedBox(height: 24),
                      ],
                      _HeroCard(
                        onScanTap: () => _onScanTap(context, subState),
                      ),
                      const SizedBox(height: 24),
                      if (scanState is ScanCompleted)
                        _LastScanSummary(session: scanState.session),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _onScanTap(BuildContext context, SubscriptionState subState) {
    if (subState is SubscriptionLoaded && !subState.status.hasAccess) {
      context.push(AppRoutes.paywall);
      return;
    }
    context.read<ScanBloc>().add(const ScanStartRequested());
  }

  void _showPermissionDeniedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Photo Access Required'),
        content: const Text(
          'Clean Pro needs access to your photo library to find duplicates. '
          'Tap Settings to grant access.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          // FA-026: actually open Settings — previously a no-op TODO.
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await PhotoManager.openSetting();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}

class _SubscriptionBanner extends StatelessWidget {
  const _SubscriptionBanner({required this.status});

  final SubscriptionStatus status;

  @override
  Widget build(BuildContext context) {
    if (status.isTrialActive) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              Icons.timer_outlined,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              '${status.daysRemaining ?? 7} days remaining in your free trial',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    if (!status.hasAccess) {
      return GestureDetector(
        onTap: () => GoRouter.of(context).push(AppRoutes.paywall),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 18,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Free trial ended. Subscribe to clean your library.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.error,
              ),
            ],
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.onScanTap});

  final VoidCallback onScanTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.auto_fix_high_rounded,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              'Find duplicate photos',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'AI scans your entire library in minutes and groups similar photos for easy review.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                    height: 1.5,
                  ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onScanTap,
              icon: const Icon(Icons.search_rounded),
              label: const Text('Scan My Photos'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LastScanSummary extends StatelessWidget {
  const _LastScanSummary({required this.session});

  // FA-023: was `dynamic` — typed to ScanSession for compile-time safety.
  final ScanSession session;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Last scan',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}
