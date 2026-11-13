/// Public download locations for the installable SmartEat apps.
///
/// The installers are published as GitHub Release assets. The
/// `releases/latest/download/...` URLs are stable and always point at the
/// newest release, so links in Settings never change between versions.
class AppDownloads {
  AppDownloads._();

  static const String androidApk =
      'https://github.com/LGLabs1/SmartEat/releases/latest/download/smarteat-android.apk';

  static const String windowsZip =
      'https://github.com/LGLabs1/SmartEat/releases/latest/download/smarteat-windows.zip';
}
