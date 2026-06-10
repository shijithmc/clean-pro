import 'package:equatable/equatable.dart';

enum SubscriptionTier { none, freeTrial, monthly, annual }

enum EntitlementStatus {
  none,       // New user — no trial started
  trial,      // Within free trial window
  active,     // Paid subscription active
  expired,    // Trial ended, no subscription
  cancelled,  // Subscription cancelled — access until period end
  gracePeriod, // Payment failed — brief grace window
}

class SubscriptionStatus extends Equatable {
  const SubscriptionStatus({
    required this.status,
    required this.tier,
    this.currentPeriodEnd,
    this.trialEndDate,
    this.isInGracePeriod = false,
  });

  factory SubscriptionStatus.none() => const SubscriptionStatus(
        status: EntitlementStatus.none,
        tier: SubscriptionTier.none,
      );

  final EntitlementStatus status;
  final SubscriptionTier tier;
  final DateTime? currentPeriodEnd;
  final DateTime? trialEndDate;
  final bool isInGracePeriod;

  bool get hasAccess =>
      status == EntitlementStatus.trial ||
      status == EntitlementStatus.active ||
      status == EntitlementStatus.cancelled ||
      status == EntitlementStatus.gracePeriod;

  bool get isTrialActive => status == EntitlementStatus.trial;

  bool get isPaidActive => status == EntitlementStatus.active;

  int? get daysRemaining {
    final end = currentPeriodEnd ?? trialEndDate;
    if (end == null) return null;
    final remaining = end.difference(DateTime.now()).inDays;
    return remaining.clamp(0, 9999);
  }

  bool get isAboutToExpire {
    final days = daysRemaining;
    return days != null && days <= 3;
  }

  @override
  List<Object?> get props => [status, tier, currentPeriodEnd, trialEndDate, isInGracePeriod];
}
