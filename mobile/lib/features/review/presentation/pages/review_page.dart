import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../shared/utils/file_size_formatter.dart';
import '../../../scan/application/bloc/scan_bloc.dart';
import '../../../scan/domain/entities/duplicate_group.dart';
import '../../../scan/domain/entities/scan_session.dart';

class ReviewPage extends StatelessWidget {
  const ReviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Duplicates'),
        automaticallyImplyLeading: false,
      ),
      body: BlocConsumer<ScanBloc, ScanState>(
        listener: (context, state) {
          if (state is ScanDeleting || state is ScanDeleteCompleted || state is ScanFailed) {
            // Navigation handled in ScanHomePage listener
          }
        },
        builder: (context, state) {
          if (state is! ScanCompleted) {
            return const Center(child: CircularProgressIndicator());
          }

          final session = state.session;

          if (session.groups.isEmpty) {
            return _EmptyResultsView(
              totalPhotos: session.totalPhotos,
              onDone: () => context.go(AppRoutes.scanHome),
            );
          }

          return Column(
            children: [
              _SummaryBar(session: session),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: session.groups.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _GroupListTile(
                    group: session.groups[i],
                    onTap: () => context.push(
                      AppRoutes.groupDetail.replaceFirst(':groupId', session.groups[i].id),
                    ),
                  ),
                ),
              ),
              _BottomActionBar(session: session),
            ],
          );
        },
      ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.session});
  final ScanSession session;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _Stat(
            label: 'Groups',
            value: session.totalDuplicateGroups.toString(),
          ),
          _Stat(
            label: 'Photos to delete',
            value: session.totalPhotosToDelete.toString(),
          ),
          _Stat(
            label: 'To reclaim',
            value: FileSizeFormatter.formatCompact(session.totalWasteBytes),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        Text(label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                )),
      ],
    );
  }
}

class _GroupListTile extends StatelessWidget {
  const _GroupListTile({required this.group, required this.onTap});
  final DuplicateGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          child: const Icon(Icons.photo_library_outlined),
        ),
        title: Text(
          '${group.photoCount} similar photos',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${group.photosToDelete.length} to delete · ${FileSizeFormatter.formatCompact(group.wasteBytes)}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (group.hasWarning)
              Icon(
                Icons.warning_amber_rounded,
                size: 18,
                color: Theme.of(context).colorScheme.error,
              ),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({required this.session});
  final ScanSession session;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            // FA-021: withOpacity deprecated → withValues
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ElevatedButton(
            onPressed: () => _confirmDelete(context),
            child: Text(
              'Clean ${FileSizeFormatter.formatCompact(session.totalWasteBytes)} Now',
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => context.go(AppRoutes.scanHome),
            child: const Text('Skip for now'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    // FA-024: avoid force-cast — state may change between onPressed and here.
    final state = context.read<ScanBloc>().state;
    if (state is! ScanCompleted) return;
    final session = state.session;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Deletion'),
        content: Text(
          'Delete ${session.totalPhotosToDelete} photos and reclaim '
          '${FileSizeFormatter.format(session.totalWasteBytes)}?\n\n'
          'Photos go to Trash and can be recovered for 30 days.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clean Now'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      context.read<ScanBloc>().add(const ScanDeleteConfirmed());
    }
  }
}

class _EmptyResultsView extends StatelessWidget {
  const _EmptyResultsView({required this.totalPhotos, required this.onDone});
  final int totalPhotos;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline_rounded,
              size: 80,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'Your library is clean!',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Scanned $totalPhotos photos — no duplicates found.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton(onPressed: onDone, child: const Text('Done')),
          ],
        ),
      ),
    );
  }
}
