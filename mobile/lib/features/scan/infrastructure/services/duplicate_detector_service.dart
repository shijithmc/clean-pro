import 'dart:io';
import 'dart:typed_data';
import 'package:injectable/injectable.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../../../core/constants/app_constants.dart';
import '../../domain/entities/duplicate_group.dart';
import '../../domain/entities/photo_item.dart';
import '../../domain/services/i_duplicate_detector.dart';
import 'phash_calculator.dart';
import 'package:image/image.dart' as img;
import 'dart:math' as math;

@LazySingleton(as: IDuplicateDetector)
class DuplicateDetectorService implements IDuplicateDetector {
  DuplicateDetectorService(this._pHashCalculator);

  final PHashCalculator _pHashCalculator;
  Interpreter? _interpreter;
  bool _isInitialized = false;

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;
    _interpreter = await Interpreter.fromAsset(AppConstants.mobileNetModelPath);
    _isInitialized = true;
  }

  @override
  Future<void> dispose() async {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
  }

  @override
  Future<int> computePHash(PhotoItem photo) async {
    final bytes = await File(photo.path).readAsBytes();
    return _pHashCalculator.compute(bytes);
  }

  @override
  Future<List<double>> computeEmbedding(PhotoItem photo) async {
    if (!_isInitialized) await initialize();
    final interpreter = _interpreter;
    if (interpreter == null) throw StateError('TFLite interpreter not initialized');

    final bytes = await File(photo.path).readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) return List.filled(AppConstants.embeddingDimensions, 0.0);

    // Resize to 224x224 for MobileNetV3
    final resized = img.copyResize(image, width: 224, height: 224);

    // Normalise to [-1, 1] as expected by MobileNetV3
    final input = List.generate(
      1,
      (_) => List.generate(
        224,
        (y) => List.generate(
          224,
          (x) {
            final pixel = resized.getPixel(x, y);
            return [
              (pixel.r / 127.5) - 1.0,
              (pixel.g / 127.5) - 1.0,
              (pixel.b / 127.5) - 1.0,
            ];
          },
        ),
      ),
    );

    final output = List.generate(
      1,
      (_) => List.filled(AppConstants.embeddingDimensions, 0.0),
    );

    interpreter.run(input, output);
    return output[0];
  }

  @override
  Future<List<DuplicateGroup>> groupDuplicates(
    List<PhotoItem> photos, {
    int pHashThreshold = 10,
    double embeddingThreshold = 0.95,
  }) async {
    final photosWithHash = photos.where((p) => p.pHash != null).toList();
    final clusters = <List<PhotoItem>>[];
    final assigned = <String>{};

    for (int i = 0; i < photosWithHash.length; i++) {
      final photo = photosWithHash[i];
      if (assigned.contains(photo.id)) continue;

      final cluster = [photo];
      assigned.add(photo.id);

      for (int j = i + 1; j < photosWithHash.length; j++) {
        final candidate = photosWithHash[j];
        if (assigned.contains(candidate.id)) continue;

        final distance = PHashCalculator.hammingDistance(
          photo.pHash!,
          candidate.pHash!,
        );

        if (distance <= pHashThreshold) {
          // Optional second pass for near-duplicates: embedding similarity
          if (distance > 0 && photo.embedding != null && candidate.embedding != null) {
            final similarity = _cosineSimilarity(photo.embedding!, candidate.embedding!);
            if (similarity < embeddingThreshold) continue;
          }
          cluster.add(candidate);
          assigned.add(candidate.id);
        }
      }

      if (cluster.length >= 2) {
        clusters.add(cluster);
      }
    }

    return clusters.asMap().entries.map((entry) {
      final index = entry.key;
      final cluster = entry.value;
      final type = _classifyGroupType(cluster);
      final keepId = selectBestPhoto(cluster);

      return DuplicateGroup(
        id: 'group_$index',
        photos: cluster,
        type: type,
        recommendedKeepId: keepId,
      );
    }).toList();
  }

  @override
  String selectBestPhoto(List<PhotoItem> photos) {
    if (photos.isEmpty) throw ArgumentError('photos must not be empty');
    if (photos.length == 1) return photos.first.id;

    // Priority: most megapixels → most recent → largest file
    final sorted = List<PhotoItem>.from(photos)
      ..sort((a, b) {
        final mpCompare = b.megapixels.compareTo(a.megapixels);
        if (mpCompare != 0) return mpCompare;
        final dateCompare = b.createdAt.compareTo(a.createdAt);
        if (dateCompare != 0) return dateCompare;
        return b.sizeBytes.compareTo(a.sizeBytes);
      });

    return sorted.first.id;
  }

  DuplicateGroupType _classifyGroupType(List<PhotoItem> photos) {
    // Exact duplicates: all pHash values identical
    final hashes = photos.map((p) => p.pHash).toSet();
    if (hashes.length == 1) return DuplicateGroupType.exact;

    // Burst detection: all taken within 3 seconds of each other
    final times = photos.map((p) => p.createdAt).toList()..sort();
    if (times.last.difference(times.first).inSeconds <= 3) {
      return DuplicateGroupType.burst;
    }

    return DuplicateGroupType.nearDuplicate;
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;
    double dot = 0.0, normA = 0.0, normB = 0.0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    final denominator = math.sqrt(normA) * math.sqrt(normB);
    return denominator == 0 ? 0.0 : dot / denominator;
  }
}
