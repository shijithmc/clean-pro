import '../entities/subscription_status.dart';

abstract class ISubscriptionRepository {
  /// Returns current entitlement status from RevenueCat SDK.
  /// Primary source of truth — no network call if cache is fresh.
  Future<SubscriptionStatus> getEntitlement();

  /// Initiates purchase of [productId] via App Store / Google Play IAP.
  /// Throws [PurchaseCancelledException] if user cancels.
  /// Throws [PurchaseFailedException] on payment failure.
  Future<SubscriptionStatus> purchase(String productId);

  /// Restores prior purchases (required by App Store Review Guidelines).
  Future<SubscriptionStatus> restorePurchases();

  /// Fetches available products from RevenueCat.
  Future<List<SubscriptionProduct>> getAvailableProducts();

  /// Starts or validates free trial for current user.
  /// Trial is tracked locally (SharedPreferences) and validated server-side.
  Future<SubscriptionStatus> startTrial();

  /// Syncs entitlement with backend (fallback path if SDK unavailable).
  Future<SubscriptionStatus> syncWithBackend();
}

class SubscriptionProduct {
  const SubscriptionProduct({
    required this.productId,
    required this.title,
    required this.description,
    required this.priceString,
    required this.currencyCode,
    required this.priceAmountMicros,
    required this.isAnnual,
  });

  final String productId;
  final String title;
  final String description;
  final String priceString;
  final String currencyCode;
  final int priceAmountMicros;
  final bool isAnnual;

  double get priceAmount => priceAmountMicros / 1000000;
}
