import 'package:web/web.dart' as web;

bool startWebDownload(String url) {
  try {
    web.window.location.assign(url);
    return true;
  } catch (_) {
    return false;
  }
}
