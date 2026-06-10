import '../entities/photo_item.dart';
import '../entities/duplicate_group.dart';

/// Contract for on-device duplicate detection.
/// Implementation uses pHash + TFLite MobileNetV3 — all processing on-device.
abstract class IDuplicateDetector {
  /// Computes 64-bit perceptual hash for [photo].
  /// Fast — runs synchronously on decoded image data.
  Future<int> computePHash(PhotoItem photo);

  /// Computes 128-dimensional MobileNetV3 embedding for [photo].
  /// Used for semantic near-duplicate detection beyond pHash.
  Future<List<double>> computeEmbedding(PhotoItem photo);

  /// Groups [photos] into duplicate clusters using Hamming distance on pHash.
  /// Groups with ≥ 2 photos and Hamming distance ≤ [threshold] are duplicates.
  /// For near-duplicates that pass pHash threshold, runs embedding cosine
  /// similarity as a second pass.
  Future<List<DuplicateGroup>> groupDuplicates(
    List<PhotoItem> photos, {
    int pHashThreshold = 10,
    double embeddingThreshold = 0.95,
  });

  /// Selects the best photo to keep from a group.
  /// Priority: highest resolution → most recent → largest file size.
  String selectBestPhoto(List<PhotoItem> photos);

  /// Initializes the TFLite model from assets.
  /// Must be called before [computeEmbedding].
  Future<void> initialize();

  /// Releases TFLite interpreter resources.
  Future<void> dispose();
}
