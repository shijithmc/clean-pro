/// Domain-layer subscription exceptions.
/// Defined here so Application (BLoC) and Infrastructure (RevenueCatService)
/// can both reference them without the Application layer depending on Infrastructure.
library;

/// Thrown when the user cancels an in-progress purchase.
class PurchaseCancelledException implements Exception {
  const PurchaseCancelledException();

  @override
  String toString() => 'PurchaseCancelledException: user cancelled the purchase';
}

/// Thrown when a purchase attempt fails for a non-cancellation reason
/// (payment declined, network error, product not found, etc.).
class PurchaseFailedException implements Exception {
  const PurchaseFailedException(this.message);

  final String message;

  @override
  String toString() => 'PurchaseFailedException: $message';
}
