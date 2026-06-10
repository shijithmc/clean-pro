import 'dart:io';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/app_constants.dart';
import '../../domain/entities/subscription_status.dart';
import '../../domain/repositories/i_subscription_repository.dart';

@LazySingleton(as: ISubscriptionRepository)
class RevenueCatService implements ISubscriptionRepository {
  RevenueCatService(this._prefs);

  final SharedPreferences _prefs;
  bool _isConfigured = false;

  Future<void> _ensureConfigured() async {
    if (_isConfigured) return;

    await Purchases.setLogLevel(LogLevel.error);

    final PurchasesConfiguration config;
    if (Platform.isIOS) {
      config = PurchasesConfiguration(AppConstants.revenueCatAppleApiKey);
    } else {
      config = PurchasesConfiguration(AppConstants.revenueCatGoogleApiKey);
    }

    await Purchases.configure(config);
    _isConfigured = true;
  }

  @override
  Future<SubscriptionStatus> getEntitlement() async {
    await _ensureConfigured();

    try {
      final customerInfo = await Purchases.getCustomerInfo();
      return _mapToSubscriptionStatus(customerInfo);
    } on PlatformException {
      // Fallback to local trial check if SDK unavailable (offline)
      return _getLocalTrialStatus();
    }
  }

  @override
  Future<SubscriptionStatus> purchase(String productId) async {
    await _ensureConfigured();

    final offerings = await Purchases.getOfferings();
    final current = offerings.current;
    if (current == null) {
      throw PurchaseFailedException('No offerings available');
    }

    final package = current.availablePackages.firstWhere(
      (p) => p.storeProduct.identifier == productId,
      orElse: () => throw PurchaseFailedException('Product $productId not found'),
    );

    try {
      final customerInfo = await Purchases.purchasePackage(package);
      return _mapToSubscriptionStatus(customerInfo);
    } on PurchasesErrorCode catch (e) {
      if (e == PurchasesErrorCode.purchaseCancelledError) {
        throw PurchaseCancelledException();
      }
      throw PurchaseFailedException(e.toString());
    }
  }

  @override
  Future<SubscriptionStatus> restorePurchases() async {
    await _ensureConfigured();
    final customerInfo = await Purchases.restorePurchases();
    return _mapToSubscriptionStatus(customerInfo);
  }

  @override
  Future<List<SubscriptionProduct>> getAvailableProducts() async {
    await _ensureConfigured();

    final offerings = await Purchases.getOfferings();
    final current = offerings.current;
    if (current == null) return [];

    return current.availablePackages.map((package) {
      final product = package.storeProduct;
      return SubscriptionProduct(
        productId: product.identifier,
        title: product.title,
        description: product.description,
        priceString: product.priceString,
        currencyCode: product.currencyCode ?? 'USD',
        priceAmountMicros: (product.price * 1000000).round(),
        isAnnual: product.identifier == AppConstants.annualProductId,
      );
    }).toList();
  }

  @override
  Future<SubscriptionStatus> startTrial() async {
    final now = DateTime.now();
    final trialEnd = now.add(const Duration(days: AppConstants.trialDurationDays));

    await _prefs.setString(AppConstants.trialStartDateKey, now.toIso8601String());

    return SubscriptionStatus(
      status: EntitlementStatus.trial,
      tier: SubscriptionTier.freeTrial,
      trialEndDate: trialEnd,
      currentPeriodEnd: trialEnd,
    );
  }

  @override
  Future<SubscriptionStatus> syncWithBackend() async {
    // Backend sync is a secondary fallback — RevenueCat SDK is primary
    return getEntitlement();
  }

  SubscriptionStatus _mapToSubscriptionStatus(CustomerInfo customerInfo) {
    final entitlement = customerInfo.entitlements.active[AppConstants.revenueCatEntitlementId];

    if (entitlement != null && entitlement.isActive) {
      final expiryDate = entitlement.expirationDate != null
          ? DateTime.parse(entitlement.expirationDate!)
          : null;

      final productId = entitlement.productIdentifier;
      final tier = productId == AppConstants.annualProductId
          ? SubscriptionTier.annual
          : SubscriptionTier.monthly;

      return SubscriptionStatus(
        status: EntitlementStatus.active,
        tier: tier,
        currentPeriodEnd: expiryDate,
      );
    }

    // Check local trial
    return _getLocalTrialStatus();
  }

  SubscriptionStatus _getLocalTrialStatus() {
    final trialStartStr = _prefs.getString(AppConstants.trialStartDateKey);

    if (trialStartStr == null) {
      return SubscriptionStatus.none();
    }

    final trialStart = DateTime.parse(trialStartStr);
    final trialEnd = trialStart.add(const Duration(days: AppConstants.trialDurationDays));
    final now = DateTime.now();

    if (now.isBefore(trialEnd)) {
      return SubscriptionStatus(
        status: EntitlementStatus.trial,
        tier: SubscriptionTier.freeTrial,
        trialEndDate: trialEnd,
        currentPeriodEnd: trialEnd,
      );
    }

    return SubscriptionStatus(
      status: EntitlementStatus.expired,
      tier: SubscriptionTier.none,
      trialEndDate: trialEnd,
    );
  }
}

class PurchaseCancelledException implements Exception {}

class PurchaseFailedException implements Exception {
  PurchaseFailedException(this.message);
  final String message;
  @override
  String toString() => 'PurchaseFailedException: $message';
}
