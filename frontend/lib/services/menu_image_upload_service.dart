import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

enum MenuImageSource { camera, gallery }

class MenuImageUploadException implements Exception {
  const MenuImageUploadException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MenuImageUploadService {
  MenuImageUploadService({ImagePicker? picker, FirebaseStorage? storage})
      : _picker = picker,
        _storage = storage;

  final ImagePicker? _picker;
  final FirebaseStorage? _storage;

  static bool isSourceSupported(
    MenuImageSource source, {
    bool? isWeb,
    TargetPlatform? platform,
  }) {
    final web = isWeb ?? kIsWeb;
    final target = platform ?? defaultTargetPlatform;

    if (web && source == MenuImageSource.camera) return false;
    if (target == TargetPlatform.linux ||
        target == TargetPlatform.windows ||
        target == TargetPlatform.fuchsia) {
      return false;
    }
    if (source == MenuImageSource.camera && target == TargetPlatform.macOS) {
      return false;
    }
    return true;
  }

  static String unsupportedMessage(MenuImageSource source) {
    return source == MenuImageSource.camera
        ? 'Camera capture is not supported on this platform.'
        : 'Gallery upload is not supported on this platform.';
  }

  static String storagePath({
    required String fileName,
    String? menuItemId,
    DateTime? now,
  }) {
    final safeId = _slug(menuItemId) ?? 'new-item';
    final extension = _extension(fileName);
    final timestamp = (now ?? DateTime.now()).microsecondsSinceEpoch;
    return 'menu-images/$safeId/$timestamp.$extension';
  }

  static String contentTypeFor(String fileName) {
    switch (_extension(fileName)) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'heic':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }

  static String? _slug(String? value) {
    final sanitized = (value ?? '')
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return sanitized.isEmpty ? null : sanitized;
  }

  static String _extension(String fileName) {
    final clean = fileName.trim().split(RegExp(r'[\\/]')).last;
    final parts = clean.split('.');
    if (parts.length < 2) return 'jpg';
    final extension = parts.last.toLowerCase();
    return RegExp(r'^[a-z0-9]{3,5}$').hasMatch(extension) ? extension : 'jpg';
  }

  Future<String> pickAndUpload(
    MenuImageSource source, {
    String? menuItemId,
  }) async {
    if (!isSourceSupported(source)) {
      throw MenuImageUploadException(unsupportedMessage(source));
    }

    final picker = _picker ?? ImagePicker();
    final XFile? file = await picker.pickImage(
      source: source == MenuImageSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
      maxHeight: 1600,
    );

    if (file == null) return '';

    final path = storagePath(fileName: file.name, menuItemId: menuItemId);
    final storage = _storage ?? FirebaseStorage.instance;
    final ref = storage.ref(path);
    final bytes = await file.readAsBytes();

    await ref.putData(
      bytes,
      SettableMetadata(contentType: contentTypeFor(file.name)),
    );

    return ref.getDownloadURL();
  }
}

String menuImageUploadErrorMessage(Object error) {
  if (error is MenuImageUploadException) return error.message;
  if (error is FirebaseException) {
    final detail = error.message?.trim() ?? '';
    return detail.isEmpty
        ? 'Image upload failed (${error.code}).'
        : 'Image upload failed: $detail';
  }
  return 'Could not upload image. Please try again.';
}
