import '../entities/photo_item.dart';
import '../entities/scan_session.dart';

/// Contract for photo library access and scan lifecycle.
/// Implementation uses photo_manager package — dependency never
/// referenced in domain layer.
abstract class IPhotoScannerRepository {
  /// Requests full photo library access.
  /// Returns true if granted, false if denied or limited.
  Future<bool> requestPhotoAccess();

  /// Returns true if full photo library access is currently granted.
  Future<bool> hasPhotoAccess();

  /// Total number of images in the library.
  Future<int> getPhotoCount();

  /// Streams photo items in batches of [batchSize] for incremental processing.
  /// Emits [PhotoItem] values without embedding/pHash — callers compute those.
  Stream<PhotoItem> streamPhotos({
    int batchSize = 100,
    int maxPhotos = 50000,
  });

  /// Deletes [assetIds] by moving them to the device's native Trash.
  /// Throws [PhotoDeletionException] if any deletion fails.
  /// Returns list of successfully deleted IDs.
  Future<List<String>> deletePhotos(List<String> assetIds);

  /// Saves completed scan session for display in "Recently Cleaned" log.
  Future<void> saveScanResult(ScanSession session);

  /// Loads the most recent completed scan session (for re-entry UX).
  Future<ScanSession?> loadLastScanSession();
}
