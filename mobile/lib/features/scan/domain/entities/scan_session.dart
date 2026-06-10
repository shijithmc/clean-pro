import 'package:equatable/equatable.dart';
import 'duplicate_group.dart';

enum ScanStatus { idle, scanning, completed, failed, cancelled }

class ScanSession extends Equatable {
  const ScanSession({
    required this.id,
    required this.status,
    this.startedAt,
    this.completedAt,
    this.totalPhotos = 0,
    this.processedPhotos = 0,
    this.groups = const [],
    this.errorMessage,
  });

  factory ScanSession.initial() => ScanSession(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        status: ScanStatus.idle,
      );

  final String id;
  final ScanStatus status;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final int totalPhotos;
  final int processedPhotos;
  final List<DuplicateGroup> groups;
  final String? errorMessage;

  double get progress =>
      totalPhotos > 0 ? processedPhotos / totalPhotos : 0.0;

  int get totalDuplicateGroups => groups.length;

  int get totalPhotosToDelete =>
      groups.fold(0, (sum, g) => sum + g.photosToDelete.length);

  int get totalWasteBytes =>
      groups.fold(0, (sum, g) => sum + g.wasteBytes);

  Duration? get duration =>
      startedAt != null && completedAt != null
          ? completedAt!.difference(startedAt!)
          : null;

  bool get isScanning => status == ScanStatus.scanning;
  bool get isCompleted => status == ScanStatus.completed;

  ScanSession copyWith({
    ScanStatus? status,
    DateTime? startedAt,
    DateTime? completedAt,
    int? totalPhotos,
    int? processedPhotos,
    List<DuplicateGroup>? groups,
    String? errorMessage,
  }) =>
      ScanSession(
        id: id,
        status: status ?? this.status,
        startedAt: startedAt ?? this.startedAt,
        completedAt: completedAt ?? this.completedAt,
        totalPhotos: totalPhotos ?? this.totalPhotos,
        processedPhotos: processedPhotos ?? this.processedPhotos,
        groups: groups ?? this.groups,
        errorMessage: errorMessage ?? this.errorMessage,
      );

  @override
  List<Object?> get props => [id, status, totalPhotos, processedPhotos, groups.length, errorMessage];
}
