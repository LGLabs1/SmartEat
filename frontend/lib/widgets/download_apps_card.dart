import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_downloads.dart';

/// Install entry points for the SmartEat apps.
///
/// Android installs from a signed APK and Windows from a ZIP archive, both
/// served by Firebase Hosting. iOS installs as a PWA via Safari's "Add to
/// Home Screen" because a native `.ipa` needs App Store/TestFlight signing.
///
/// The rows adapt to where the app is already running so users are not asked
/// to install the build they are holding. [isWebOverride] and
/// [platformOverride] exist for widget tests.
class DownloadAppsCard extends StatelessWidget {
  const DownloadAppsCard({
    super.key,
    this.onDownloadAndroid,
    this.onDownloadWindows,
    this.onInstallIos,
    this.isWebOverride,
    this.platformOverride,
  });

  final VoidCallback? onDownloadAndroid;
  final VoidCallback? onDownloadWindows;
  final VoidCallback? onInstallIos;
  final bool? isWebOverride;
  final TargetPlatform? platformOverride;

  bool get _isWeb => isWebOverride ?? kIsWeb;
  TargetPlatform get _platform => platformOverride ?? defaultTargetPlatform;

  bool get _showAndroid => _isWeb || _platform != TargetPlatform.android;
  bool get _showWindows => _isWeb || _platform != TargetPlatform.windows;
  bool get _showIos => _isWeb || _platform != TargetPlatform.iOS;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Get SmartEat on your other devices',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (_showAndroid)
            ListTile(
              leading: Icon(Icons.android, color: scheme.primary),
              title: const Text('Download Android APK'),
              subtitle: const Text(
                  'Android 7.0+ \u00B7 Allow install from this source'),
              trailing: const Icon(Icons.download_outlined),
              onTap: onDownloadAndroid ??
                  () => _download(context, AppDownloads.androidApk),
            ),
          if (_showAndroid && (_showWindows || _showIos))
            const Divider(height: 1),
          if (_showWindows)
            ListTile(
              leading:
                  Icon(Icons.desktop_windows_outlined, color: scheme.primary),
              title: const Text('Download for Windows'),
              subtitle:
                  const Text('Windows 10/11 \u00B7 ZIP archive with the app'),
              trailing: const Icon(Icons.download_outlined),
              onTap: onDownloadWindows ??
                  () => _download(context, AppDownloads.windowsZip),
            ),
          if (_showWindows && _showIos) const Divider(height: 1),
          if (_showIos)
            ListTile(
              leading: Icon(Icons.phone_iphone, color: scheme.primary),
              title: const Text('Install on iPhone/iPad'),
              subtitle: const Text('Add to Home Screen using Safari'),
              trailing: const Icon(Icons.info_outline),
              onTap: onInstallIos ?? () => _showIosInstructions(context),
            ),
        ],
      ),
    );
  }

  Future<void> _download(BuildContext context, String url) async {
    final launched = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!context.mounted || launched) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not start the download.')),
    );
  }

  void _showIosInstructions(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Install on iPhone/iPad'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('1. Open Smart Eat in Safari.'),
            SizedBox(height: 8),
            Text('2. Tap the Share button.'),
            SizedBox(height: 8),
            Text('3. Choose "Add to Home Screen", then tap Add.'),
            SizedBox(height: 16),
            Text(
              'Smart Eat will then open like an app from your Home Screen.',
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
}
