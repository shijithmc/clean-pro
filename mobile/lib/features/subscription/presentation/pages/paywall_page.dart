import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/router/app_router.dart';
import '../../../../shared/utils/file_size_formatter.dart';
import '../../application/bloc/subscription_bloc.dart';
import '../../domain/entities/subscription_status.dart';
import '../../domain/repositories/i_subscription_repository.dart';

class PaywallPage extends StatelessWidget {
  const PaywallPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Go Pro'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: BlocConsumer<SubscriptionBloc, SubscriptionState>(
        listener: (context, state) {
          if (state is SubscriptionLoaded && state.status.isPaidActive) {
            context.go(AppRoutes.scanHome);
          } else if (state is SubscriptionError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            );
          }
        },
        builder: (context, state) {
          final products = state is SubscriptionLoaded ? state.products : <SubscriptionProduct>[];
          final isLoading = state is SubscriptionLoading || state is SubscriptionPurchasing;

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  const Icon(
                    Icons.auto_fix_high_rounded,
                    size: 64,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Clean Pro',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Find and remove duplicate photos.\nReclaim your storage today.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                          height: 1.5,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  const _FeatureList(),
                  const Spacer(),
                  if (products.isNotEmpty) ...[
                    _ProductCards(products: products, isLoading: isLoading),
                  ] else ...[
                    _DefaultPricingCards(isLoading: isLoading),
                  ],
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: isLoading
                        ? null
                        : () => context.read<SubscriptionBloc>().add(const SubscriptionRestoreRequested()),
                    child: const Text('Restore Purchases'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Cancel anytime. Subscriptions managed by App Store / Google Play.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FeatureList extends StatelessWidget {
  const _FeatureList();

  @override
  Widget build(BuildContext context) {
    const features = [
      'Unlimited duplicate detection',
      'AI keep recommendations',
      'Background scanning',
      'Safe delete to Trash',
      'Works offline — no uploads ever',
    ];

    return Column(
      children: features
          .map(
            (f) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Text(f, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _ProductCards extends StatelessWidget {
  const _ProductCards({required this.products, required this.isLoading});

  final List<SubscriptionProduct> products;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final annual = products.where((p) => p.isAnnual).firstOrNull;
    final monthly = products.where((p) => !p.isAnnual).firstOrNull;

    return Column(
      children: [
        if (annual != null)
          _PricingButton(
            title: 'Annual',
            price: annual.priceString,
            subtitle: 'Save 50% — best value',
            isPrimary: true,
            isLoading: isLoading,
            onTap: () => context.read<SubscriptionBloc>().add(
                  SubscriptionPurchaseRequested(productId: annual.productId),
                ),
          ),
        const SizedBox(height: 12),
        if (monthly != null)
          _PricingButton(
            title: 'Monthly',
            price: monthly.priceString,
            subtitle: 'Billed monthly',
            isPrimary: false,
            isLoading: isLoading,
            onTap: () => context.read<SubscriptionBloc>().add(
                  SubscriptionPurchaseRequested(productId: monthly.productId),
                ),
          ),
      ],
    );
  }
}

class _DefaultPricingCards extends StatelessWidget {
  const _DefaultPricingCards({required this.isLoading});

  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _PricingButton(
          title: 'Annual',
          price: '\$17.99/year',
          subtitle: 'Save 50% — best value',
          isPrimary: true,
          isLoading: isLoading,
          onTap: () => context.read<SubscriptionBloc>().add(
                const SubscriptionPurchaseRequested(productId: AppConstants.annualProductId),
              ),
        ),
        const SizedBox(height: 12),
        _PricingButton(
          title: 'Monthly',
          price: '\$2.99/month',
          subtitle: 'Billed monthly',
          isPrimary: false,
          isLoading: isLoading,
          onTap: () => context.read<SubscriptionBloc>().add(
                const SubscriptionPurchaseRequested(productId: AppConstants.monthlyProductId),
              ),
        ),
      ],
    );
  }
}

class _PricingButton extends StatelessWidget {
  const _PricingButton({
    required this.title,
    required this.price,
    required this.subtitle,
    required this.isPrimary,
    required this.isLoading,
    required this.onTap,
  });

  final String title;
  final String price;
  final String subtitle;
  final bool isPrimary;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: isPrimary
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline,
            width: isPrimary ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(16),
          color: isPrimary
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surface,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ],
              ),
            ),
            if (isLoading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Text(
                price,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isPrimary
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
              ),
          ],
        ),
      ),
    );
  }
}
