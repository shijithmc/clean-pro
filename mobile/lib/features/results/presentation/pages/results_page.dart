import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../shared/utils/file_size_formatter.dart';

class ResultsPageArgs {
  const ResultsPageArgs({
    this.photosDeleted = 0,
    this.bytesReclaimed = 0,
  });

  final int photosDeleted;
  final int bytesReclaimed;
}

class ResultsPage extends StatelessWidget {
  const ResultsPage({super.key, required this.args});

  final ResultsPageArgs args;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _SuccessAnimation(),
              const SizedBox(height: 48),
              Text(
                FileSizeFormatter.format(args.bytesReclaimed),
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'reclaimed',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                    ),
              ),
              const SizedBox(height: 32),
              _StatRow(
                icon: Icons.delete_outline_rounded,
                label: 'Photos removed',
                value: args.photosDeleted.toString(),
              ),
              const SizedBox(height: 12),
              _StatRow(
                icon: Icons.restore_rounded,
                label: 'Recoverable for',
                value: '30 days',
              ),
              const Spacer(),
              Text(
                'Photos moved to Trash — recoverable in Photos app for 30 days.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => context.go(AppRoutes.scanHome),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuccessAnimation extends StatefulWidget {
  const _SuccessAnimation();

  @override
  State<_SuccessAnimation> createState() => _SuccessAnimationState();
}

class _SuccessAnimationState extends State<_SuccessAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scale = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
    _controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.primaryContainer,
        ),
        child: Icon(
          Icons.check_rounded,
          size: 56,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 12),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
        const Spacer(),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}
