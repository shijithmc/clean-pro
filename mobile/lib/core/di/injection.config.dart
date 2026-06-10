// GENERATED CODE - DO NOT MODIFY BY HAND
// Run `flutter pub run build_runner build` to regenerate this file.

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// ignore_for_file: unnecessary_lambdas

import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../../features/scan/infrastructure/services/phash_calculator.dart';
import '../../features/scan/domain/repositories/i_photo_scanner_repository.dart';
import '../../features/scan/domain/services/i_duplicate_detector.dart';
import '../../features/scan/infrastructure/repositories/photo_scanner_repository.dart';
import '../../features/scan/infrastructure/services/duplicate_detector_service.dart';
import '../../features/subscription/domain/repositories/i_subscription_repository.dart';
import '../../features/subscription/infrastructure/services/revenue_cat_service.dart';

extension GetItInjectableX on GetIt {
  // initializes the registration of main-scope dependencies inside of GetIt
  Future<GetIt> init({
    String? environment,
    EnvironmentFilter? environmentFilter,
  }) async {
    final gh = GetItHelper(this, environment, environmentFilter);

    final prefs = await SharedPreferences.getInstance();

    // Singletons
    final pHashCalculator = PHashCalculator();
    gh.lazySingleton<IDuplicateDetector>(() => DuplicateDetectorService(pHashCalculator));
    gh.lazySingleton<IPhotoScannerRepository>(
      () => PhotoScannerRepository(prefs),
    );
    gh.lazySingleton<ISubscriptionRepository>(() => RevenueCatService(prefs));

    return this;
  }
}
