import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/utils/file_size_formatter.dart';
import '../../../scan/application/bloc/scan_bloc.dart';
import '../../../scan/domain/entities/duplicate_group.dart';
import '../../../scan/domain/entities/photo_item.dart';

class GroupDetailPage extends StatefulWidget {
  const GroupDetailPage({super.key, required this.groupId});

  final String groupId;

  @override
  State<GroupDetailPage> createState() => _GroupDetailPageState();
}

class _GroupDetailPageState extends State<GroupDetailPage> {
  String? _selectedKeepId;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ScanBloc, ScanState>(
      builder: (context, state) {
        if (state is! ScanCompleted) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final group = state.session.groups.firstWhere(
          (g) => g.id == widget.groupId,
          orElse: () => state.session.groups.first,
        );

        final effectiveKeepId = _selectedKeepId ?? group.recommendedKeepId;

        return Scaffold(
          appBar: AppBar(
            title: Text('${group.photoCount} Similar Photos'),
          ),
          body: Column(
            children: [
              if (group.hasWarning)
                _WarningBanner(group: group),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.75,
                  ),
                  itemCount: group.photos.length,
                  itemBuilder: (_, i) {
                    final photo = group.photos[i];
                    final isKeep = photo.id == effectiveKeepId;
                    final isAiRecommended = photo.id == group.recommendedKeepId;

                    return GestureDetector(
                      onTap: () => setState(() => _selectedKeepId = photo.id),
                      child: _PhotoCard(
                        photo: photo,
                        isKeep: isKeep,
                        isAiRecommended: isAiRecommended,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          bottomNavigationBar: _BottomBar(
            group: group,
            effectiveKeepId: effectiveKeepId,
            userChanged: _selectedKeepId != null && _selectedKeepId != group.recommendedKeepId,
            onConfirm: () {
              context.read<ScanBloc>().add(
                    ScanGroupReviewCompleted(
                      groupId: group.id,
                      userSelectedKeepId: _selectedKeepId,
                    ),
                  );
              context.pop();
            },
          ),
        );
      },
    );
  }
}

class _PhotoCard extends StatelessWidget {
  const _PhotoCard({
    required this.photo,
    required this.isKeep,
    required this.isAiRecommended,
  });

  final PhotoItem photo;
  final bool isKeep;
  final bool isAiRecommended;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isKeep ? Theme.of(context).colorScheme.primary : Colors.transparent,
          width: 3,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(File(photo.path), fit: BoxFit.cover),
            if (isKeep)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isAiRecommended) ...[
                        const Icon(Icons.auto_awesome, size: 12, color: Colors.white),
                        const SizedBox(width: 4),
                      ],
                      const Text(
                        'KEEP',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black.withOpacity(0.6), Colors.transparent],
                  ),
                ),
                child: Text(
                  '${photo.megapixels}MP · ${FileSizeFormatter.formatCompact(photo.sizeBytes)}',
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ),
            if (photo.hasWarning)
              Positioned(
                top: 8,
                left: 8,
                child: Icon(
                  Icons.warning_amber_rounded,
                  size: 20,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.group});
  final DuplicateGroup group;

  @override
  Widget build(BuildContext context) {
    final warningPhotos = group.photos.where((p) => p.hasWarning).toList();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${warningPhotos.length} photo${warningPhotos.length > 1 ? "s are" : " is"} favourited or in an album. Review carefully.',
              style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.group,
    required this.effectiveKeepId,
    required this.userChanged,
    required this.onConfirm,
  });

  final DuplicateGroup group;
  final String effectiveKeepId;
  final bool userChanged;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (userChanged)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'You overrode the AI recommendation',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.outline,
                  fontSize: 12,
                ),
              ),
            ),
          ElevatedButton(
            onPressed: onConfirm,
            child: Text(
              'Keep selected · Delete ${group.photosToDelete.length} photos',
            ),
          ),
        ],
      ),
    );
  }
}
