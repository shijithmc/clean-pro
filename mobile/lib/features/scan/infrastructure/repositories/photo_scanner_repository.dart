import 'package:injectable/injectable.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../../../../core/utils/app_logger.dart';
import '../../domain/entities/photo_item.dart';
import '../../domain/entities/scan_session.dart';
import '../../domain/repositories/i_photo_scanner_repository.dart';

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

  // FA-015: use getPermissionState (non-prompting) — requestPermissionExtend
  // was showing a system permission dialog on every status check.
  // photo_manager v3 API: positional RequestType was replaced with named
  // `requestOption: PermissionRequestOption(...)`.
  @override
  Future<bool> hasPhotoAccess() async {
    final state = await PhotoManager.getPermissionState(
      requestOption: const PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: RequestType.image,
          mediaLocation: false,
        ),
      ),
    );
    return state.isAuth;
  }

  // FA-014: use the "All Photos" album, not albums.first.
  // getAssetPathList() order is undefined; on many iOS configurations
  // albums.first is a limited or named album, not the full library.
  @override
  Future<int> getPhotoCount() async {
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      filterOption: FilterOptionGroup(
        imageOption: const FilterOption(needTitle: false),
      ),
    );

    if (albums.isEmpty) return 0;

    final allAlbum = albums.firstWhere(
      (a) => a.isAll,
      orElse: () => albums.first,
    );
    return allAlbum.assetCountAsync;
  }

  // FA-013: same fix in streamPhotos — scan the "All Photos" album.
  @override
  Stream<PhotoItem> streamPhotos({
    int batchSize = 100,
    int maxPhotos = 50000,
  }) async* {
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
    );

    if (albums.isEmpty) return;

    final allAlbum = albums.firstWhere(
      (a) => a.isAll,
      orElse: () => albums.first,
    );
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
    } catch (e, s) {
      // FA-033: log instead of silently swallowing
      appLog.w('Failed to load last scan session', error: e, stackTrace: s);
      return null;
    }
  }
}
