import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:clean_pro/features/scan/infrastructure/services/phash_calculator.dart';

void main() {
  group('PHashCalculator', () {
    late PHashCalculator calculator;

    setUp(() {
      calculator = PHashCalculator();
    });

    group('hammingDistance', () {
      test('identical hashes return distance 0', () {
        const hash = 0xDEADBEEF12345678;
        expect(PHashCalculator.hammingDistance(hash, hash), equals(0));
      });

      test('hashes differing by 1 bit return distance 1', () {
        const hash1 = 0x0000000000000001;
        const hash2 = 0x0000000000000000;
        expect(PHashCalculator.hammingDistance(hash1, hash2), equals(1));
      });

      test('completely different hashes return max distance 64', () {
        const hash1 = 0x0000000000000000;
        const hash2 = 0xFFFFFFFFFFFFFFFF;
        expect(PHashCalculator.hammingDistance(hash1, hash2), equals(64));
      });

      test('near-duplicate threshold: distance <= 10 classified as near-duplicate', () {
        // Hashes with Hamming distance of exactly 10
        const hash1 = 0x0000000000000000;
        // Flip 10 bits
        const hash2 = 0x00000000000003FF;
        expect(PHashCalculator.hammingDistance(hash1, hash2), lessThanOrEqualTo(10));
      });

      test('non-duplicate threshold: distance > 10 classified as non-duplicate', () {
        const hash1 = 0x0000000000000000;
        const hash2 = 0x0000000000007FFF; // 15 bits flipped
        expect(PHashCalculator.hammingDistance(hash1, hash2), greaterThan(10));
      });
    });
  });
}
