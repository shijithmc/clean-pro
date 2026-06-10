import 'package:injectable/injectable.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../../domain/entities/photo_item.dart';
import '../../domain/entities/scan_session.dart';
import '../../domain/repositories/i_photo_scanner_repository.dart';
import '../../../../core/constants/app_constants.dart';

@LazySingleton(as: IPhotoScannerRepository)
class PhotoScannerRepository implements IPhotoScannerRepository {
  PhotoScannerRepository(this._prefs);

  final SharedPreferences _prefs;

  static const String _lastScanKey = 'last_scan_session';

  @override
  Future<bool> requestPhotoAccess() async {
    final result = await PhotoManager.requestPermissionExtend();
    return result.isAuth;
  }

  @override
  Future<bool> hasPhotoAccess() async {
    final result = await PhotoManager.requestPermissionExtend();
    return result.isAuth;
  }

  @override
  Future<int> getPhotoCount() async {
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      filterOption: FilterOptionGroup(
        imageOption: const FilterOption(needTitle: false),
      ),
    );

    if (albums.isEmpty) return 0;
    return albums.first.assetCountAsync;
  }

  @override
  Stream<PhotoItem> streamPhotos({
    int batchSize = 100,
    int maxPhotos = 50000,
  }) async* {
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
    );

    if (albums.isEmpty) return;

    final allAlbum = albums.first;
    final totalCount = await allAlbum.assetCountAsync;
    final limit = totalCount.clamp(0, maxPhotos);

    int offset = 0;
    while (offset < limit) {
      final batch = await allAlbum.getAssetListRange(
        start: offset,
        end: (offset + batchSize).clamp(0, limit),
      );

      for (final asset in batch) {
        final file = await asset.file;
        if (file == null) continue;

        // In photo_manager v3, album membership is not directly on AssetEntity.
        // We yield without album metadata here; album info is a secondary concern.
        yield PhotoItem(
          id: asset.id,
          path: file.path,
          sizeBytes: await file.length(),
          width: asset.width,
          height: asset.height,
          createdAt: asset.createDateTime,
          modifiedAt: asset.modifiedDateTime,
          isFavourite: asset.isFavorite,
          isInAlbum: false,
          albumNames: const [],
          mimeType: asset.mimeType ?? 'image/jpeg',
        );
      }

      offset += batchSize;
    }
  }

  @override
  Future<List<String>> deletePhotos(List<String> assetIds) async {
    if (assetIds.isEmpty) return [];

    final result = await PhotoManager.editor.deleteWithIds(assetIds);

    // Return IDs that were successfully moved to Trash
    return result;
  }

  @override
  Future<void> saveScanResult(ScanSession session) async {
    final json = {
      'id': session.id,
      'completedAt': session.completedAt?.toIso8601String(),
      'totalPhotos': session.totalPhotos,
      'totalDuplicateGroups': session.totalDuplicateGroups,
      'totalPhotosToDelete': session.totalPhotosToDelete,
      'totalWasteBytes': session.totalWasteBytes,
    };
    await _prefs.setString(_lastScanKey, jsonEncode(json));
  }

  @override
  Future<ScanSession?> loadLastScanSession() async {
    final stored = _prefs.getString(_lastScanKey);
    if (stored == null) return null;

    try {
      final json = jsonDecode(stored) as Map<String, dynamic>;
      return ScanSession(
        id: json['id'] as String,
        status: ScanStatus.completed,
        completedAt: json['completedAt'] != null
            ? DateTime.parse(json['completedAt'] as String)
            : null,
        totalPhotos: json['totalPhotos'] as int,
      );
    } catch (_) {
      return null;
    }
  }
}
