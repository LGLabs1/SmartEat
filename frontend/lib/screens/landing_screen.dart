import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_downloads.dart';
import '../config/app_version.dart';
import '../theme.dart';
import '../utils/web_download_stub.dart'
    if (dart.library.js_interop) '../utils/web_download_web.dart';
import '../widgets/app_logo.dart';
import '../widgets/sage_avatar.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryController;
  late final Animation<double> _heroFade;
  late final Animation<Offset> _heroSlide;
  late final Animation<double> _previewFade;
  late final Animation<Offset> _previewSlide;
  late final Animation<double> _downloadsFade;
  late final Animation<Offset> _downloadsSlide;
  late final Animation<double> _featuresFade;
  late final Animation<Offset> _featuresSlide;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );

    _heroFade = _stagedFade(0, 0.56);
    _heroSlide = _stagedSlide(0, 0.56, const Offset(0, 0.05));
    _previewFade = _stagedFade(0.16, 0.72);
    _previewSlide = _stagedSlide(0.16, 0.72, const Offset(0.05, 0));
    _downloadsFade = _stagedFade(0.3, 0.86);
    _downloadsSlide = _stagedSlide(0.3, 0.86, const Offset(0, 0.06));
    _featuresFade = _stagedFade(0.42, 1);
    _featuresSlide = _stagedSlide(0.42, 1, const Offset(0, 0.06));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      if (_entryController.isAnimating) _entryController.stop();
      if (_entryController.value != 1) _entryController.value = 1;
      return;
    }
    if (!_entryController.isAnimating && !_entryController.isCompleted) {
      _entryController.forward();
    }
  }

  Animation<double> _stagedFade(double begin, double end) {
    return CurvedAnimation(
      parent: _entryController,
      curve: Interval(begin, end, curve: Curves.easeOut),
    );
  }

  Animation<Offset> _stagedSlide(double begin, double end, Offset beginOffset) {
    return Tween<Offset>(begin: beginOffset, end: Offset.zero).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: Interval(begin, end, curve: Curves.easeOutCubic),
      ),
    );
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.sageNavy,
      body: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.sageNavy,
                    AppTheme.sagePanel,
                    const Color(0xFF070D18),
                  ],
                  stops: const [0, 0.55, 1],
                ),
              ),
            ),
          ),
          Positioned(
            top: -200,
            right: -160,
            child: FadeTransition(
              opacity: _heroFade,
              child: _SageGlowOrb(
                size: 520,
                color: AppTheme.sageBlue.withValues(alpha: 0.18),
              ),
            ),
          ),
          Positioned(
            bottom: -240,
            left: -180,
            child: FadeTransition(
              opacity: _heroFade,
              child: _SageGlowOrb(
                size: 560,
                color: AppTheme.sageBlueDeep.withValues(alpha: 0.16),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.pagePadding,
                vertical: 28,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppTheme.contentMaxWidth,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 960;
                      final medium = constraints.maxWidth >= 640;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _stage(
                            child: _buildTopBar(),
                            fade: _heroFade,
                            slide: _heroSlide,
                          ),
                          SizedBox(height: wide ? 58 : 40),
                          if (wide)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  flex: 6,
                                  child: _stage(
                                    child: _buildHeroCopy(wide: true),
                                    fade: _heroFade,
                                    slide: _heroSlide,
                                  ),
                                ),
                                const SizedBox(width: 52),
                                Expanded(
                                  flex: 5,
                                  child: _stage(
                                    child: _buildPreviewCard(),
                                    fade: _previewFade,
                                    slide: _previewSlide,
                                  ),
                                ),
                              ],
                            )
                          else ...[
                            _stage(
                              child: _buildHeroCopy(wide: false),
                              fade: _heroFade,
                              slide: _heroSlide,
                            ),
                            SizedBox(height: medium ? 38 : 32),
                            Center(
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 520),
                                child: _stage(
                                  child: _buildPreviewCard(),
                                  fade: _previewFade,
                                  slide: _previewSlide,
                                ),
                              ),
                            ),
                          ],
                          SizedBox(height: wide ? 64 : 52),
                          _stage(
                            child: _buildDownloads(),
                            fade: _downloadsFade,
                            slide: _downloadsSlide,
                          ),
                          SizedBox(height: wide ? 64 : 52),
                          _stage(
                            child: _buildFeatures(),
                            fade: _featuresFade,
                            slide: _featuresSlide,
                          ),
                          const SizedBox(height: 36),
                          _buildFooter(),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stage({
    required Widget child,
    required Animation<double> fade,
    required Animation<Offset> slide,
  }) {
    return FadeTransition(
      opacity: fade,
      child: SlideTransition(position: slide, child: child),
    );
  }

  Widget _buildTopBar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        return Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const AppLogo(height: 32),
            ),
            const Spacer(),
            if (!compact) ...[
              TextButton(
                onPressed: () => Navigator.of(context).pushNamed('/login'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white.withValues(alpha: 0.72),
                ),
                child: const Text('Sign in'),
              ),
              const SizedBox(width: 8),
              _buildGradientButton(
                label: 'Create account',
                onPressed: () => Navigator.of(context).pushNamed('/register'),
                icon: Icons.person_add_alt_rounded,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildHeroCopy({required bool wide}) {
    final alignment =
        wide ? CrossAxisAlignment.start : CrossAxisAlignment.center;
    final textAlign = wide ? TextAlign.start : TextAlign.center;

    return Column(
      crossAxisAlignment: alignment,
      children: [
        SizedBox(
          width: wide ? 76 : 68,
          height: wide ? 76 : 68,
          child: SageAvatar(
            size: wide ? 76 : 68,
          ),
        ),
        const SizedBox(height: 8),
        _SageIntroMessages(wide: wide),
        const SizedBox(height: 8),
        Text(
          'MEET SAGE · YOUR AI COMPANION',
          textAlign: textAlign,
          style: const TextStyle(
            color: AppTheme.sageCyan,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
        SizedBox(height: wide ? 20 : 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: AppTheme.sageBlue.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: AppTheme.sageAccent.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                size: 14,
                color: AppTheme.sageAccent,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  'EATERY OPERATIONS, SIMPLIFIED',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.sagePaleBlue,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: wide ? 24 : 20),
        Text(
          'Run your eatery with\ncalm confidence.',
          textAlign: textAlign,
          style: TextStyle(
            color: Colors.white,
            fontSize: wide ? 52 : 36,
            height: 1.08,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.4,
          ),
        ),
        SizedBox(height: wide ? 20 : 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Text(
            'Orders, POS, inventory, recipes, analytics, finance, payroll, attendance, notifications, and Sage AI — all in one beautifully simple workspace.',
            textAlign: textAlign,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.58),
              fontSize: wide ? 17 : 15,
              height: 1.6,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        SizedBox(height: wide ? 30 : 26),
        _buildCtas(wide: wide),
        SizedBox(height: wide ? 26 : 22),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.verified_rounded,
              size: 16,
              color: AppTheme.sageSuccess,
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                'One workspace for your whole team',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.52),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCtas({required bool wide}) {
    final signIn = _buildGradientButton(
      key: const Key('landing-sign-in'),
      label: 'Sign in',
      icon: Icons.login_rounded,
      onPressed: () => Navigator.of(context).pushNamed('/login'),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
    );
    final register = OutlinedButton.icon(
      key: const Key('landing-create-account'),
      onPressed: () => Navigator.of(context).pushNamed('/register'),
      icon: const Icon(Icons.person_add_alt_rounded, size: 18),
      label: const Text('Create account'),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(
          color: AppTheme.sageAccent.withValues(alpha: 0.45),
          width: 1.4,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );

    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          signIn,
          const SizedBox(height: 12),
          register,
        ],
      );
    }

    return Row(
      children: [
        signIn,
        const SizedBox(width: 12),
        register,
      ],
    );
  }

  Widget _buildGradientButton({
    Key? key,
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    required EdgeInsetsGeometry padding,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppTheme.sageGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppTheme.sageBlue.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        key: key,
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          shadowColor: Colors.transparent,
          padding: padding,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _buildPreviewCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppTheme.sagePanel.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.sageBlue.withValues(alpha: 0.2),
            blurRadius: 42,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.insights_rounded,
                  size: 19,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Today at a glance',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.94),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Illustrative sample data',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.sageSuccess.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.circle,
                      size: 5,
                      color: Color(0xFF7BE0A0),
                    ),
                    const SizedBox(width: 5),
                    const Text(
                      'SAMPLE',
                      style: TextStyle(
                        color: Color(0xFFBFF5D2),
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  icon: Icons.receipt_long_rounded,
                  value: '128',
                  label: 'Orders',
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _MetricTile(
                  icon: Icons.account_balance_wallet_rounded,
                  value: '₱12.4k',
                  label: 'Sales',
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _MetricTile(
                  icon: Icons.inventory_2_outlined,
                  value: '3',
                  label: 'Low stock',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppTheme.sageBlue.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    size: 18,
                    color: AppTheme.sageCyan,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sage insight',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Peak hour starts soon. Prep your busiest stations.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.58),
                          fontSize: 11,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Sample figures only. Not connected to any registered eatery.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloads() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Get SmartEat on every device.',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Installable builds and a home-screen app for iPhone and iPad.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.52),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Current download version ${AppVersion.display}',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.42),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 900
                ? 3
                : constraints.maxWidth >= 620
                    ? 2
                    : 1;
            final gap = 14.0;
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            final options = [
              _DownloadOption(
                key: const Key('landing-download-android'),
                icon: Icons.android_rounded,
                title: 'Download Android APK',
                subtitle: 'Android 7.0+ · Signed APK',
                onTap: () => _launchDownload(context, AppDownloads.androidApk),
              ),
              _DownloadOption(
                key: const Key('landing-download-windows'),
                icon: Icons.desktop_windows_outlined,
                title: 'Download for Windows',
                subtitle: 'Windows 10/11 · ZIP archive',
                onTap: () => _launchDownload(context, AppDownloads.windowsZip),
              ),
              _DownloadOption(
                key: const Key('landing-download-pwa'),
                icon: Icons.phone_iphone_rounded,
                title: 'Install on iPhone/iPad',
                subtitle: 'Add to Home Screen using Safari',
                onTap: () => _showIosInstructions(context),
              ),
            ];

            if (columns == 1) {
              return Column(
                children: [
                  for (final option in options) ...[
                    SizedBox(width: double.infinity, child: option),
                    SizedBox(height: gap),
                  ],
                ],
              );
            }

            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final option in options)
                  SizedBox(width: width, child: option),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _launchDownload(BuildContext context, String url) async {
    if (kIsWeb) {
      if (startWebDownload(url)) return;
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start the download.')),
      );
      return;
    }

    try {
      final launched = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!context.mounted || launched) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start the download.')),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start the download.')),
      );
    }
  }

  void _showIosInstructions(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.sagePanel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Install on iPhone/iPad',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('1. Open Smart Eat in Safari.',
                style: TextStyle(color: Colors.white70)),
            SizedBox(height: 8),
            Text('2. Tap the Share button.',
                style: TextStyle(color: Colors.white70)),
            SizedBox(height: 8),
            Text(
              '3. Choose "Add to Home Screen", then tap Add.',
              style: TextStyle(color: Colors.white70),
            ),
            SizedBox(height: 16),
            Text(
              'Smart Eat will then open like an app from your Home Screen.',
              style: TextStyle(color: Colors.white54),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatures() {
    final features = [
      _Feature(
        key: const Key('landing-feature-orders'),
        icon: Icons.restaurant_menu_rounded,
        color: AppTheme.sageAccent,
        title: 'Orders & menu',
        body:
            'Take dine-in and takeaway orders, update prices, and keep every station aligned in real time.',
      ),
      _Feature(
        key: const Key('landing-feature-pos'),
        icon: Icons.shopping_cart_outlined,
        color: AppTheme.sageCyan,
        title: 'Point of sale',
        body:
            'Build quick orders, apply discounts, and send tickets to the kitchen without leaving the counter.',
      ),
      _Feature(
        key: const Key('landing-feature-inventory'),
        icon: Icons.inventory_2_outlined,
        color: AppTheme.sageSuccess,
        title: 'Inventory control',
        body:
            'Track stock, low items, movements, purchases, and waste before they slow down service.',
      ),
      _Feature(
        key: const Key('landing-feature-recipes'),
        icon: Icons.menu_book_outlined,
        color: const Color(0xFFF59E0B),
        title: 'Recipes & costing',
        body:
            'Store recipes, costing, menu margins, and item performance in one connected place.',
      ),
      _Feature(
        key: const Key('landing-feature-analytics'),
        icon: Icons.analytics_outlined,
        color: AppTheme.sageBlue,
        title: 'Analytics & forecasts',
        body:
            'See sales trends, insights, forecasts, and the patterns behind your busiest hours.',
      ),
      _Feature(
        key: const Key('landing-feature-finance'),
        icon: Icons.account_balance_wallet_outlined,
        color: AppTheme.sageSuccess,
        title: 'Finance & reports',
        body:
            'Manage expenses, payables, reports, and monthly payroll with clear, trustworthy totals.',
      ),
      _Feature(
        key: const Key('landing-feature-staff'),
        icon: Icons.groups_rounded,
        color: const Color(0xFFE040FB),
        title: 'Staff & attendance',
        body:
            'Plan shifts, track attendance, and keep roles, approvals, and schedules organized.',
      ),
      _Feature(
        key: const Key('landing-feature-payroll'),
        icon: Icons.payments_outlined,
        color: const Color(0xFF8B5CF6),
        title: 'Payroll & meals',
        body:
            'Handle staff meals, payroll summaries, and approvals without chasing spreadsheets.',
      ),
      _Feature(
        key: const Key('landing-feature-sage'),
        icon: Icons.auto_awesome_rounded,
        color: AppTheme.sageCyan,
        visual: const SageAvatar(size: 44),
        title: 'Sage AI assistant',
        body:
            'Ask Sage about sales, stock, staff, or what to prepare next, right inside your workspace.',
      ),
      _Feature(
        key: const Key('landing-feature-notifications'),
        icon: Icons.notifications_active_outlined,
        color: const Color(0xFFF97316),
        title: 'Notifications & SMS',
        body:
            'Get in-app, device, and SMS alerts for low stock, bills, orders, and attendance.',
      ),
      _Feature(
        key: const Key('landing-feature-settings'),
        icon: Icons.settings_outlined,
        color: AppTheme.sagePaleBlue,
        title: 'Settings & profiles',
        body:
            'Manage eatery details, notification preferences, and personal profiles with confidence.',
      ),
      _Feature(
        key: const Key('landing-feature-devices'),
        icon: Icons.devices_rounded,
        color: AppTheme.sageBlueDeep,
        title: 'Every device',
        body:
            'Run SmartEat on Android, Windows, or as a home-screen app on iPhone and iPad.',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Everything in one place.',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'A calmer way to run the details that keep your eatery moving.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.52),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 900
                ? 3
                : constraints.maxWidth >= 620
                    ? 2
                    : 1;
            final gap = 14.0;
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;

            if (columns == 1) {
              return Column(
                children: [
                  for (final feature in features) ...[
                    SizedBox(width: double.infinity, child: feature),
                    SizedBox(height: gap),
                  ],
                ],
              );
            }

            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final feature in features)
                  SizedBox(width: width, child: feature),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Row(
      children: [
        Icon(
          Icons.copyright_outlined,
          size: 14,
          color: Colors.white.withValues(alpha: 0.35),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            'SmartEat · Eatery Management System',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _SageGlowOrb extends StatelessWidget {
  const _SageGlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}

class _SageIntroMessages extends StatefulWidget {
  const _SageIntroMessages({required this.wide});

  final bool wide;

  @override
  State<_SageIntroMessages> createState() => _SageIntroMessagesState();
}

class _SageIntroMessagesState extends State<_SageIntroMessages>
    with SingleTickerProviderStateMixin {
  static const List<String> _messages = [
    'Hi, I’m Sage — your eatery sidekick.',
    'Ask me what needs attention today.',
    'I keep stock, sales, and staff in sync.',
  ];

  late final AnimationController _controller;
  int _offset = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  void _syncAnimation() {
    if (MediaQuery.disableAnimationsOf(context)) {
      if (_controller.isAnimating) _controller.stop();
      if (_controller.value != 0) _controller.value = 0;
      return;
    }
    if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _advance() {
    setState(() => _offset++);
  }

  @override
  Widget build(BuildContext context) {
    final animationsDisabled = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final base = (_controller.value * _messages.length)
            .floor()
            .clamp(0, _messages.length - 1);
        final index = (base + _offset) % _messages.length;
        final message = _messages[index];

        return Semantics(
          label: message,
          child: GestureDetector(
            key: const Key('landing-sage-intro'),
            onTap: _advance,
            child: Container(
              constraints: BoxConstraints(maxWidth: widget.wide ? 430 : 320),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.sageBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: AppTheme.sageAccent.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    size: 14,
                    color: AppTheme.sageAccent,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: AnimatedSwitcher(
                      duration: animationsDisabled
                          ? Duration.zero
                          : const Duration(milliseconds: 280),
                      switchInCurve: Curves.easeOut,
                      child: Text(
                        message,
                        key: ValueKey<int>(index),
                        textAlign:
                            widget.wide ? TextAlign.start : TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppTheme.sagePaleBlue,
                          fontSize: widget.wide ? 12 : 11,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.white.withValues(alpha: 0.62)),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadOption extends StatefulWidget {
  const _DownloadOption({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  State<_DownloadOption> createState() => _DownloadOptionState();
}

class _DownloadOptionState extends State<_DownloadOption> {
  bool _hovering = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Semantics(
        button: true,
        child: GestureDetector(
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(
              0,
              _pressed
                  ? 2
                  : _hovering
                      ? -4
                      : 0,
              0,
            ),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTheme.sagePanel.withValues(
                alpha: _hovering ? 0.98 : 0.82,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppTheme.sageAccent.withValues(
                  alpha: _hovering ? 0.5 : 0.16,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.sageBlue.withValues(
                    alpha: _hovering ? 0.2 : 0.08,
                  ),
                  blurRadius: _hovering ? 28 : 16,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppTheme.sageBlue.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child:
                      Icon(widget.icon, size: 21, color: AppTheme.sageAccent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.download_rounded,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.45),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    this.visual,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final Widget? visual;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.sagePanel.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.sageBlue.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: visual ?? Icon(icon, size: 22, color: color),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            body,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.56),
              fontSize: 13,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
