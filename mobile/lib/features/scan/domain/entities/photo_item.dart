import 'package:equatable/equatable.dart';

/// Represents a single photo asset on the device.
/// All data derived from on-device metadata — never uploaded.
class PhotoItem extends Equatable {
  const PhotoItem({
    required this.id,
    required this.path,
    required this.sizeBytes,
    required this.width,
    required this.height,
    required this.createdAt,
    required this.modifiedAt,
    this.pHash,
    this.embedding,
    this.isFavourite = false,
    this.isInAlbum = false,
    this.albumNames = const [],
    this.mimeType = 'image/jpeg',
  });

  final String id;
  final String path;
  final int sizeBytes;
  final int width;
  final int height;
  final DateTime createdAt;
  final DateTime modifiedAt;

  /// 64-bit perceptual hash for duplicate detection.
  final int? pHash;

  /// MobileNetV3 embedding vector for semantic similarity.
  final List<double>? embedding;

  final bool isFavourite;
  final bool isInAlbum;
  final List<String> albumNames;
  final String mimeType;

  int get megapixels => (width * height / 1000000).round();

  double get aspectRatio => width > 0 ? width / height : 1.0;

  bool get isLivePhoto => mimeType.contains('heic') || mimeType.contains('heif');

  bool get hasWarning => isFavourite || isInAlbum;

  PhotoItem copyWith({
    int? pHash,
    List<double>? embedding,
  }) =>
      PhotoItem(
        id: id,
        path: path,
        sizeBytes: sizeBytes,
        width: width,
        height: height,
        createdAt: createdAt,
        modifiedAt: modifiedAt,
        pHash: pHash ?? this.pHash,
        embedding: embedding ?? this.embedding,
        isFavourite: isFavourite,
        isInAlbum: isInAlbum,
        albumNames: albumNames,
        mimeType: mimeType,
      );

  @override
  List<Object?> get props => [id, pHash, embedding];
}
