import 'package:equatable/equatable.dart';
import 'photo_item.dart';

enum DuplicateGroupType {
  exact,        // identical file content / identical pHash
  nearDuplicate, // pHash Hamming distance ≤ threshold
  burst,        // burst-mode sequence (similar timestamp + high similarity)
  screenshot,   // screenshot category
}

/// A cluster of photos detected as duplicates or near-duplicates.
class DuplicateGroup extends Equatable {
  const DuplicateGroup({
    required this.id,
    required this.photos,
    required this.type,
    required this.recommendedKeepId,
    this.isReviewed = false,
    this.userSelectedKeepId,
  });

  final String id;
  final List<PhotoItem> photos;
  final DuplicateGroupType type;

  /// AI-recommended photo to keep (highest resolution + most recent).
  final String recommendedKeepId;

  final bool isReviewed;

  /// User override — if null, [recommendedKeepId] is used.
  final String? userSelectedKeepId;

  String get effectiveKeepId => userSelectedKeepId ?? recommendedKeepId;

  List<PhotoItem> get photosToDelete =>
      photos.where((p) => p.id != effectiveKeepId).toList();

  int get wasteBytes =>
      photosToDelete.fold(0, (sum, p) => sum + p.sizeBytes);

  int get photoCount => photos.length;

  bool get hasWarning => photos.any((p) => p.hasWarning);

  DuplicateGroup copyWith({
    bool? isReviewed,
    String? userSelectedKeepId,
  }) =>
      DuplicateGroup(
        id: id,
        photos: photos,
        type: type,
        recommendedKeepId: recommendedKeepId,
        isReviewed: isReviewed ?? this.isReviewed,
        userSelectedKeepId: userSelectedKeepId ?? this.userSelectedKeepId,
      );

  @override
  List<Object?> get props => [id, photos, type, recommendedKeepId, isReviewed, userSelectedKeepId];
}
