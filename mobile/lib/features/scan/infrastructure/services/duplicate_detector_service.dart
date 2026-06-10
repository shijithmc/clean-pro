import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;
import 'package:injectable/injectable.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../../../core/constants/app_constants.dart';
import '../../domain/entities/duplicate_group.dart';
import '../../domain/entities/photo_item.dart';
import '../../domain/services/i_duplicate_detector.dart';
import 'phash_calculator.dart';

@LazySingleton(as: IDuplicateDetector)
class DuplicateDetectorService implements IDuplicateDetector {
  DuplicateDetectorService(this._pHashCalculator);

  final PHashCalculator _pHashCalculator;

  // Model bytes are loaded on the UI isolate (rootBundle is not available in
  // background isolates) then passed by value into each compute() call.
  Uint8List? _modelBytes;
  bool _isInitialized = false;

  // FA-005: load model bytes here so compute() isolates can create their own
  // interpreter without needing rootBundle access.
  @override
  Future<void> initialize() async {
    if (_isInitialized) return;
    final byteData = await rootBundle.load(AppConstants.mobileNetModelPath);
    _modelBytes = byteData.buffer.asUint8List();
    _isInitialized = true;
  }

  @override
  Future<void> dispose() async {
    _modelBytes = null;
    _isInitialized = false;
  }

  // FA-003: offload File I/O + DCT computation to a background isolate via
  // PHashCalculator.computeInIsolate().
  @override
  Future<int> computePHash(PhotoItem photo) async {
    final bytes = await File(photo.path).readAsBytes();
    return _pHashCalculator.computeInIsolate(bytes);
  }

  // FA-005: offload File I/O + image decode + TFLite inference to a background
  // isolate. The main isolate only loads model bytes once and passes them by
  // value; each compute() invocation creates its own interpreter, runs inference,
  // then closes the interpreter — no shared state crosses the isolate boundary.
  @override
  Future<List<double>> computeEmbedding(PhotoItem photo) async {
    if (!_isInitialized) await initialize();
    final modelBytes = _modelBytes;
    if (modelBytes == null) {
      throw StateError('DuplicateDetectorService.initialize() was not awaited');
    }
    return compute(
      _runEmbeddingIsolate,
      _EmbeddingArgs(photo.path, modelBytes, AppConstants.embeddingDimensions),
    );
  }

  // FA-018: offload the O(n²) Hamming-distance clustering to a background
  // isolate so the UI thread is not blocked after stream exhaustion.
  // PhotoItem / DuplicateGroup are pure data classes — no Flutter types —
  // so they cross the isolate boundary safely via Dart message passing.
  @override
  Future<List<DuplicateGroup>> groupDuplicates(
    List<PhotoItem> photos, {
    int pHashThreshold = 10,
    double embeddingThreshold = 0.95,
  }) {
    return compute(
      _groupDuplicatesIsolate,
      _GroupDuplicatesArgs(photos, pHashThreshold, embeddingThreshold),
    );
  }

  @override
  String selectBestPhoto(List<PhotoItem> photos) {
    if (photos.isEmpty) throw ArgumentError('photos must not be empty');
    if (photos.length == 1) return photos.first.id;

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
}

// ---------------------------------------------------------------------------
// Isolate argument / helper types
// ---------------------------------------------------------------------------

class _EmbeddingArgs {
  const _EmbeddingArgs(this.photoPath, this.modelBytes, this.embeddingDimensions);
  final String photoPath;
  final Uint8List modelBytes;
  final int embeddingDimensions;
}

class _GroupDuplicatesArgs {
  const _GroupDuplicatesArgs(this.photos, this.pHashThreshold, this.embeddingThreshold);
  final List<PhotoItem> photos;
  final int pHashThreshold;
  final double embeddingThreshold;
}

// ---------------------------------------------------------------------------
// Top-level isolate entry points (must be top-level for compute())
// ---------------------------------------------------------------------------

/// Runs MobileNetV3 embedding inference in a background isolate.
/// Creates and destroys its own [Interpreter] — no shared state.
Future<List<double>> _runEmbeddingIsolate(_EmbeddingArgs args) async {
  final interpreter = Interpreter.fromBuffer(args.modelBytes);

  try {
    final bytes = await File(args.photoPath).readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) return List.filled(args.embeddingDimensions, 0.0);

    final resized = img.copyResize(image, width: 224, height: 224);

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
      (_) => List.filled(args.embeddingDimensions, 0.0),
    );

    interpreter.run(input, output);
    return output[0];
  } finally {
    interpreter.close();
  }
}

/// O(n²) duplicate clustering — runs in a background isolate.
List<DuplicateGroup> _groupDuplicatesIsolate(_GroupDuplicatesArgs args) {
  final photos = args.photos;
  final pHashThreshold = args.pHashThreshold;
  final embeddingThreshold = args.embeddingThreshold;

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
    final keepId = _selectBestPhoto(cluster);

    return DuplicateGroup(
      id: 'group_$index',
      photos: cluster,
      type: type,
      recommendedKeepId: keepId,
    );
  }).toList();
}

DuplicateGroupType _classifyGroupType(List<PhotoItem> photos) {
  final hashes = photos.map((p) => p.pHash).toSet();
  if (hashes.length == 1) return DuplicateGroupType.exact;

  final times = photos.map((p) => p.createdAt).toList()..sort();
  if (times.last.difference(times.first).inSeconds <= 3) {
    return DuplicateGroupType.burst;
  }

  return DuplicateGroupType.nearDuplicate;
}

String _selectBestPhoto(List<PhotoItem> photos) {
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

double _cosineSimilarity(List<double> a, List<double> b) {
  if (a.length != b.length) return 0.0;
  double dot = 0.0, normA = 0.0, normB = 0.0;
  for (int i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  // FA-044: one sqrt(a*b) instead of sqrt(a)*sqrt(b)
  final denominator = math.sqrt(normA * normB);
  return denominator == 0 ? 0.0 : dot / denominator;
}
