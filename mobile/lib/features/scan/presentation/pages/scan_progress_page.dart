import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../application/bloc/scan_bloc.dart';

class ScanProgressPage extends StatelessWidget {
  const ScanProgressPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Scanning'),
          automaticallyImplyLeading: false,
          actions: [
            TextButton(
              onPressed: () {
                context.read<ScanBloc>().add(const ScanCancelRequested());
                context.go(AppRoutes.scanHome);
              },
              child: const Text('Cancel'),
            ),
          ],
        ),
        body: BlocConsumer<ScanBloc, ScanState>(
          listener: (context, state) {
            if (state is ScanCompleted) {
              context.go(AppRoutes.review);
            } else if (state is ScanFailed) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Scan failed: ${state.message}'),
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
              );
              context.go(AppRoutes.scanHome);
            } else if (state is ScanInitial) {
              context.go(AppRoutes.scanHome);
            }
          },
          builder: (context, state) {
            if (state is ScanInProgress) {
              final session = state.session;
              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const _PulsingIcon(),
                      const SizedBox(height: 48),
                      Text(
                        'Analysing your library',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'All processing happens on your device',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                      ),
                      const SizedBox(height: 48),
                      LinearProgressIndicator(
                        value: session.progress > 0 ? session.progress : null,
                        borderRadius: BorderRadius.circular(8),
                        minHeight: 8,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        session.totalPhotos > 0
                            ? '${session.processedPhotos} of ${session.totalPhotos} photos'
                            : 'Loading photos...',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return const Center(child: CircularProgressIndicator());
          },
        ),
      ),
    );
  }
}

class _PulsingIcon extends StatefulWidget {
  const _PulsingIcon();

  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _animation,
      child: Icon(
        Icons.auto_awesome_rounded,
        size: 80,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
