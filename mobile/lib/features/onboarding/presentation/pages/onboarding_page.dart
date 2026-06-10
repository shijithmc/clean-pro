import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/router/app_router.dart';
import '../../../subscription/application/bloc/subscription_bloc.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<_OnboardingSlide> _slides = const [
    _OnboardingSlide(
      title: 'Reclaim your storage',
      subtitle: 'AI finds every duplicate photo eating your space — in minutes.',
      icon: Icons.photo_library_rounded,
    ),
    _OnboardingSlide(
      title: 'Safe by design',
      subtitle: 'Deleted photos go to Trash first. Recover anything within 30 days.',
      icon: Icons.security_rounded,
    ),
    _OnboardingSlide(
      title: 'Your privacy is sacred',
      subtitle: 'Everything happens on your phone.\nNo uploads. No cloud. No exceptions.',
      icon: Icons.lock_rounded,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _checkOnboardingStatus();
  }

  Future<void> _checkOnboardingStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final completed = prefs.getBool(AppConstants.onboardingCompleteKey) ?? false;
    if (completed && mounted) {
      context.go(AppRoutes.scanHome);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemCount: _slides.length,
                itemBuilder: (_, i) => _OnboardingSlideWidget(slide: _slides[i]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _slides.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: i == _currentPage ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == _currentPage
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outline,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_currentPage == _slides.length - 1) ...[
                    ElevatedButton(
                      onPressed: _onStartTrial,
                      child: const Text('Start Free 7-Day Trial'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => context.push(AppRoutes.paywall),
                      child: Text(
                        'See subscription options',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ),
                  ] else
                    ElevatedButton(
                      onPressed: () => _pageController.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      ),
                      child: const Text('Next'),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'No credit card required',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onStartTrial() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.onboardingCompleteKey, true);

    if (mounted) {
      context.read<SubscriptionBloc>().add(const SubscriptionTrialStartRequested());
      context.go(AppRoutes.permission);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
}

class _OnboardingSlide {
  const _OnboardingSlide({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;
}

class _OnboardingSlideWidget extends StatelessWidget {
  const _OnboardingSlideWidget({required this.slide});

  final _OnboardingSlide slide;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            slide.icon,
            size: 96,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 48),
          Text(
            slide.title,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            slide.subtitle,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                  height: 1.5,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
