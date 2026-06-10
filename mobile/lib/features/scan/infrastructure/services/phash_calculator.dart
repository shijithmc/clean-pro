import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:injectable/injectable.dart';

/// Computes perceptual hash (pHash) for images.
/// Algorithm: DCT-based pHash — resize to 32x32, convert to greyscale,
/// compute 32x32 DCT, extract top-left 8x8 sub-DCT, compare to median.
/// Produces 64-bit integer hash.
@injectable
class PHashCalculator {
  static const int _dctSize = 32;
  static const int _hashSize = 8;

  /// Computes the perceptual hash of [imageBytes] (JPEG/PNG/HEIC decoded bytes).
  int compute(Uint8List imageBytes) {
    final image = img.decodeImage(imageBytes);
    if (image == null) return 0;

    final resized = img.copyResize(image, width: _dctSize, height: _dctSize);
    final greyscale = img.grayscale(resized);

    final pixels = List<double>.generate(
      _dctSize * _dctSize,
      (i) {
        final x = i % _dctSize;
        final y = i ~/ _dctSize;
        return img.getLuminance(greyscale.getPixel(x, y)).toDouble();
      },
    );

    final dctValues = _computeDCT(pixels);
    final topLeft = _extractTopLeft(dctValues);
    final median = _computeMedian(topLeft);

    int hash = 0;
    for (int i = 0; i < topLeft.length; i++) {
      if (topLeft[i] > median) {
        hash |= (1 << i);
      }
    }
    return hash;
  }

  /// Hamming distance between two 64-bit pHash values.
  /// ≤ 10 = near-duplicate; 0 = identical.
  static int hammingDistance(int hash1, int hash2) {
    int xor = hash1 ^ hash2;
    int count = 0;
    while (xor != 0) {
      count += xor & 1;
      xor >>= 1;
    }
    return count;
  }

  List<double> _computeDCT(List<double> pixels) {
    final n = _dctSize;
    final result = List<double>.filled(n * n, 0.0);

    for (int u = 0; u < n; u++) {
      for (int v = 0; v < n; v++) {
        double sum = 0.0;
        for (int x = 0; x < n; x++) {
          for (int y = 0; y < n; y++) {
            sum += pixels[y * n + x] *
                math.cos(((2 * x + 1) * u * math.pi) / (2 * n)) *
                math.cos(((2 * y + 1) * v * math.pi) / (2 * n));
          }
        }
        final cu = u == 0 ? 1.0 / math.sqrt(2) : 1.0;
        final cv = v == 0 ? 1.0 / math.sqrt(2) : 1.0;
        result[v * n + u] = (2.0 / n) * cu * cv * sum;
      }
    }
    return result;
  }

  List<double> _extractTopLeft(List<double> dct) {
    final result = <double>[];
    for (int y = 0; y < _hashSize; y++) {
      for (int x = 0; x < _hashSize; x++) {
        result.add(dct[y * _dctSize + x]);
      }
    }
    // Skip (0,0) DC component
    return result.skip(1).toList();
  }

  double _computeMedian(List<double> values) {
    final sorted = List<double>.from(values)..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) / 2;
  }
}
