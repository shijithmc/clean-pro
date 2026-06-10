import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import '../../domain/entities/duplicate_group.dart';
import '../../domain/entities/photo_item.dart';
import '../../domain/entities/scan_session.dart';
import '../../domain/repositories/i_photo_scanner_repository.dart';
import '../../domain/services/i_duplicate_detector.dart';
import '../../../../core/constants/app_constants.dart';

// Events
abstract class ScanEvent extends Equatable {
  const ScanEvent();
  @override
  List<Object?> get props => [];
}

class ScanStartRequested extends ScanEvent {
  const ScanStartRequested();
}

class ScanCancelRequested extends ScanEvent {
  const ScanCancelRequested();
}

class ScanGroupReviewCompleted extends ScanEvent {
  const ScanGroupReviewCompleted({required this.groupId, this.userSelectedKeepId});
  final String groupId;
  final String? userSelectedKeepId;
  @override
  List<Object?> get props => [groupId, userSelectedKeepId];
}

class ScanDeleteConfirmed extends ScanEvent {
  const ScanDeleteConfirmed();
}

// States
abstract class ScanState extends Equatable {
  const ScanState();
  @override
  List<Object?> get props => [];
}

class ScanInitial extends ScanState {
  const ScanInitial();
}

class ScanPermissionDenied extends ScanState {
  const ScanPermissionDenied();
}

class ScanInProgress extends ScanState {
  const ScanInProgress({required this.session});
  final ScanSession session;
  @override
  List<Object?> get props => [session];
}

class ScanCompleted extends ScanState {
  const ScanCompleted({required this.session});
  final ScanSession session;
  @override
  List<Object?> get props => [session];
}

class ScanDeleting extends ScanState {
  const ScanDeleting({required this.totalToDelete});
  final int totalToDelete;
  @override
  List<Object?> get props => [totalToDelete];
}

class ScanDeleteCompleted extends ScanState {
  const ScanDeleteCompleted({
    required this.photosDeleted,
    required this.bytesReclaimed,
  });
  final int photosDeleted;
  final int bytesReclaimed;
  @override
  List<Object?> get props => [photosDeleted, bytesReclaimed];
}

class ScanFailed extends ScanState {
  const ScanFailed({required this.message});
  final String message;
  @override
  List<Object?> get props => [message];
}

@injectable
class ScanBloc extends Bloc<ScanEvent, ScanState> {
  ScanBloc(
    this._scannerRepository,
    this._duplicateDetector,
  ) : super(const ScanInitial()) {
    on<ScanStartRequested>(_onScanStartRequested);
    on<ScanCancelRequested>(_onScanCancelRequested);
    on<ScanGroupReviewCompleted>(_onGroupReviewCompleted);
    on<ScanDeleteConfirmed>(_onDeleteConfirmed);
  }

  final IPhotoScannerRepository _scannerRepository;
  final IDuplicateDetector _duplicateDetector;

  StreamSubscription<PhotoItem>? _scanSubscription;
  ScanSession? _currentSession;
  final List<PhotoItem> _scannedPhotos = [];

  Future<void> _onScanStartRequested(
    ScanStartRequested event,
    Emitter<ScanState> emit,
  ) async {
    final hasAccess = await _scannerRepository.hasPhotoAccess();
    if (!hasAccess) {
      final granted = await _scannerRepository.requestPhotoAccess();
      if (!granted) {
        emit(const ScanPermissionDenied());
        return;
      }
    }

    await _duplicateDetector.initialize();

    final totalPhotos = await _scannerRepository.getPhotoCount();
    _scannedPhotos.clear();

    _currentSession = ScanSession.initial().copyWith(
      status: ScanStatus.scanning,
      startedAt: DateTime.now(),
      totalPhotos: totalPhotos.clamp(0, AppConstants.maxPhotosForScan),
    );

    emit(ScanInProgress(session: _currentSession!));

    int processed = 0;

    await emit.forEach(
      _scannerRepository.streamPhotos(
        batchSize: AppConstants.scanBatchSize,
        maxPhotos: AppConstants.maxPhotosForScan,
      ),
      onData: (photo) {
        // Schedule async hash computation — don't block stream
        _processPhotoAsync(photo);
        processed++;

        _currentSession = _currentSession!.copyWith(
          processedPhotos: processed,
        );

        return ScanInProgress(session: _currentSession!);
      },
      onError: (error, stack) {
        _currentSession = _currentSession!.copyWith(
          status: ScanStatus.failed,
          errorMessage: error.toString(),
        );
        return ScanFailed(message: error.toString());
      },
    );

    // All photos streamed — now group duplicates
    if (state is ScanInProgress) {
      try {
        final groups = await _duplicateDetector.groupDuplicates(
          _scannedPhotos,
          pHashThreshold: AppConstants.pHashSimilarityThreshold,
        );

        _currentSession = _currentSession!.copyWith(
          status: ScanStatus.completed,
          completedAt: DateTime.now(),
          groups: groups,
          processedPhotos: processed,
        );

        await _scannerRepository.saveScanResult(_currentSession!);
        emit(ScanCompleted(session: _currentSession!));
      } catch (e) {
        emit(ScanFailed(message: e.toString()));
      }
    }
  }

  Future<void> _processPhotoAsync(PhotoItem photo) async {
    try {
      final pHash = await _duplicateDetector.computePHash(photo);
      final photoWithHash = photo.copyWith(pHash: pHash);
      _scannedPhotos.add(photoWithHash);
    } catch (_) {
      // Skip photos that fail to hash — don't abort the scan
      _scannedPhotos.add(photo);
    }
  }

  Future<void> _onScanCancelRequested(
    ScanCancelRequested event,
    Emitter<ScanState> emit,
  ) async {
    await _scanSubscription?.cancel();
    _currentSession = _currentSession?.copyWith(status: ScanStatus.cancelled);
    emit(const ScanInitial());
  }

  Future<void> _onGroupReviewCompleted(
    ScanGroupReviewCompleted event,
    Emitter<ScanState> emit,
  ) async {
    if (_currentSession == null) return;

    final updatedGroups = _currentSession!.groups.map((g) {
      if (g.id == event.groupId) {
        return g.copyWith(
          isReviewed: true,
          userSelectedKeepId: event.userSelectedKeepId,
        );
      }
      return g;
    }).toList();

    _currentSession = _currentSession!.copyWith(groups: updatedGroups);
    emit(ScanCompleted(session: _currentSession!));
  }

  Future<void> _onDeleteConfirmed(
    ScanDeleteConfirmed event,
    Emitter<ScanState> emit,
  ) async {
    if (_currentSession == null) return;

    final toDelete = _currentSession!.groups
        .expand((g) => g.photosToDelete)
        .map((p) => p.id)
        .toList();

    if (toDelete.isEmpty) return;

    final totalBytes = _currentSession!.groups
        .fold(0, (sum, g) => sum + g.wasteBytes);

    emit(ScanDeleting(totalToDelete: toDelete.length));

    try {
      final deleted = await _scannerRepository.deletePhotos(toDelete);
      emit(ScanDeleteCompleted(
        photosDeleted: deleted.length,
        bytesReclaimed: totalBytes,
      ));
    } catch (e) {
      emit(ScanFailed(message: 'Delete failed: ${e.toString()}'));
    }
  }

  @override
  Future<void> close() async {
    await _scanSubscription?.cancel();
    await _duplicateDetector.dispose();
    return super.close();
  }
}
