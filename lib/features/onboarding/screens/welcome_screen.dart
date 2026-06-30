import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../home/screens/home_screen.dart';
import '../../../core/services/providers.dart';
import '../../../core/services/localization_provider.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/glass_background.dart';


class OnboardingStep {
  final String titleKey;
  final String descriptionKey;
  final IconData icon;
  final Color iconColor;
  final List<Color> gradientColors;

  const OnboardingStep({
    required this.titleKey,
    required this.descriptionKey,
    required this.icon,
    required this.iconColor,
    required this.gradientColors,
  });
}

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> with TickerProviderStateMixin {
  late PageController _pageController;
  late List<AnimationController> _pulseControllers;
  int _currentPage = 0;

  static const List<OnboardingStep> _steps = [
    OnboardingStep(
      titleKey: "scan_leaves",
      descriptionKey: "scan_leaves_desc",
      icon: Icons.camera_alt_rounded,
      iconColor: Colors.white,
      gradientColors: [Color(0xFF2E7D32), Color(0xFF1B5E20)],
    ),
    OnboardingStep(
      titleKey: "detect_disease",
      descriptionKey: "detect_disease_desc",
      icon: Icons.psychology_rounded,
      iconColor: Colors.white,
      gradientColors: [Color(0xFF009688), Color(0xFF004D40)],
    ),
    OnboardingStep(
      titleKey: "treat_protect",
      descriptionKey: "treat_protect_desc",
      icon: Icons.healing_rounded,
      iconColor: Colors.white,
      gradientColors: [Color(0xFF4CAF50), Color(0xFF1B5E20)],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    
    // Breathing pulse animations for each page's icon
    _pulseControllers = List.generate(
      _steps.length,
      (i) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2000),
      )..repeat(reverse: true),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (var controller in _pulseControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _navigateToHome() {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const HomeScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 0.08);
          const end = Offset.zero;
          const curve = Curves.easeInOutCubic;

          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          var offsetAnimation = animation.drive(tween);
          
          var fadeTween = Tween<double>(begin: 0.0, end: 1.0);
          var fadeAnimation = animation.drive(fadeTween);

          return FadeTransition(
            opacity: fadeAnimation,
            child: SlideTransition(
              position: offsetAnimation,
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  void _showLanguageSelectorBottomSheet(BuildContext context, WidgetRef ref) {
    final activeLocale = ref.read(localeProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.0),
                  child: Text(
                    'Select Language / භාෂාව / மொழி / भाषा',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: languageNames.entries.map((entry) {
                      final isSelected = activeLocale == entry.key;
                      return ListTile(
                        leading: Icon(
                          Icons.check_circle_rounded,
                          color: isSelected ? colorScheme.primary : Colors.transparent,
                          size: 22,
                        ),
                        title: Text(
                          entry.value,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            fontSize: 14.5,
                          ),
                        ),
                        onTap: () {
                          ref.read(localeProvider.notifier).setLocale(entry.key);
                          Navigator.pop(context);
                        },
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    
    final locale = ref.watch(localeProvider);

    return Scaffold(
      body: GlassBackground(
        child: SafeArea(
          child: Column(
            children: [
              // Top Bar (Theme selector & Language & Skip button)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Language Switcher Button
                    TextButton.icon(
                      onPressed: () => _showLanguageSelectorBottomSheet(context, ref),
                      icon: Icon(Icons.language_rounded, color: colorScheme.primary, size: 20),
                      label: Text(
                        languageNames[locale] ?? 'English',
                        style: TextStyle(
                          color: isDark ? const Color(0xFFF0F0F0) : const Color(0xFF1C1C1C),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    // Theme Switcher & Skip Row
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                            color: isDark ? const Color(0xFFF0F0F0) : const Color(0xFF1C1C1C),
                          ),
                          onPressed: () {
                            ref.read(themeModeProvider.notifier).toggleTheme();
                          },
                        ),
                        if (_currentPage < _steps.length - 1)
                          TextButton(
                            onPressed: _navigateToHome,
                            child: Text(
                              getTranslation('skip', locale),
                              style: TextStyle(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 14.5,
                              ),
                            ),
                          )
                        else
                          const SizedBox(width: 48), // Padding equivalent
                      ],
                    ),
                  ],
                ),
              ),

              // Horizontal Slides (PageView)
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() {
                      _currentPage = index;
                    });
                  },
                  itemCount: _steps.length,
                  itemBuilder: (context, index) {
                    final step = _steps[index];
                    final pulseAnim = Tween<double>(begin: 1.0, end: 1.1).animate(
                      CurvedAnimation(
                        parent: _pulseControllers[index],
                        curve: Curves.easeInOutSine,
                      ),
                    );

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Animated Glowing Icon Container
                          AnimatedBuilder(
                            animation: _pulseControllers[index],
                            builder: (context, child) {
                              return Transform.scale(
                                scale: pulseAnim.value,
                                child: child,
                              );
                            },
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Glowing background halo
                                Container(
                                  width: 170,
                                  height: 170,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: colorScheme.primary.withValues(alpha: isDark ? 0.15 : 0.1),
                                    boxShadow: [
                                      BoxShadow(
                                        color: colorScheme.primary.withValues(alpha: 0.12),
                                        blurRadius: 36,
                                        spreadRadius: 8,
                                      ),
                                    ],
                                  ),
                                ),
                                // Main Icon Card
                                Container(
                                  width: 130,
                                  height: 130,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: step.gradientColors,
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: colorScheme.primary.withValues(alpha: 0.3),
                                        blurRadius: 20,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: Icon(
                                      step.icon,
                                      size: 56,
                                      color: step.iconColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 36),
                          
                          // Glassmorphic Info Card
                          GlassCard(
                            margin: const EdgeInsets.symmetric(horizontal: 8.0),
                            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Step Title
                                Text(
                                  getTranslation(step.titleKey, locale),
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.5,
                                    fontSize: 22,
                                    color: isDark ? const Color(0xFFF0F0F0) : const Color(0xFF1C1C1C),
                                  ),
                                ),
                                const SizedBox(height: 12),

                                // Step Description
                                Text(
                                  getTranslation(step.descriptionKey, locale),
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: isDark ? const Color(0xBAAAAAAA) : const Color(0xBA666666),
                                    height: 1.5,
                                    fontSize: 13.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // Bottom Indicator & Actions Panel
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    // Dot Page Indicators
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_steps.length, (idx) {
                        final isSelected = _currentPage == idx;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: isSelected ? 20 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            color: isSelected
                                ? colorScheme.primary
                                : colorScheme.primary.withValues(alpha: 0.25),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 32),

                    // Primary Button (Next or Get Started)
                    Container(
                      width: double.infinity,
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.primary.withValues(alpha: 0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: () {
                          if (_currentPage < _steps.length - 1) {
                            _pageController.nextPage(
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeInOutCubic,
                            );
                          } else {
                            _navigateToHome();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                          elevation: 0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _currentPage == _steps.length - 1
                                  ? getTranslation('get_started', locale)
                                  : getTranslation('next', locale),
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              _currentPage == _steps.length - 1
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.arrow_forward_rounded,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
