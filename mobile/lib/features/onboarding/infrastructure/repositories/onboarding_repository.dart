import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/app_constants.dart';
import '../../domain/repositories/i_onboarding_repository.dart';

@LazySingleton(as: IOnboardingRepository)
class OnboardingRepository implements IOnboardingRepository {
  OnboardingRepository(this._prefs);

  final SharedPreferences _prefs;

  @override
  Future<bool> isOnboardingCompleted() async {
    return _prefs.getBool(AppConstants.onboardingCompleteKey) ?? false;
  }

  @override
  Future<void> markOnboardingCompleted() async {
    await _prefs.setBool(AppConstants.onboardingCompleteKey, true);
  }
}
