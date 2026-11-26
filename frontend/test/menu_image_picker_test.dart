import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/services/menu_form_options.dart';
import 'package:smarteat/services/menu_image_upload_service.dart';
import 'package:smarteat/widgets/menu_image_picker.dart';

class _FakeUploadService extends MenuImageUploadService {
  _FakeUploadService({required this.url, this.error});

  final String url;
  final Object? error;
  int calls = 0;

  @override
  Future<String> pickAndUpload(
    MenuImageSource source, {
    String? menuItemId,
  }) async {
    calls++;
    if (error != null) throw error!;
    return url;
  }
}

void main() {
  group('menu form options', () {
    test('includes Others in the shared category list', () {
      expect(menuCategoryOptions, contains('Others'));
      expect(menuCategoryOptions, contains('Drinks'));
    });
  });

  group('MenuImageUploadService helpers', () {
    test('camera is unavailable on web and gallery stays available', () {
      expect(
        MenuImageUploadService.isSourceSupported(
          MenuImageSource.camera,
          isWeb: true,
          platform: TargetPlatform.iOS,
        ),
        isFalse,
      );
      expect(
        MenuImageUploadService.isSourceSupported(
          MenuImageSource.gallery,
          isWeb: true,
          platform: TargetPlatform.iOS,
        ),
        isTrue,
      );
    });

    test('both sources are unavailable on desktop platforms', () {
      for (final source in MenuImageSource.values) {
        expect(
          MenuImageUploadService.isSourceSupported(
            source,
            isWeb: false,
            platform: TargetPlatform.windows,
          ),
          isFalse,
        );
      }
    });

    test('builds a sanitized storage path', () {
      final path = MenuImageUploadService.storagePath(
        fileName: 'Dish Photo.PNG',
        menuItemId: 'Menu/Item 42',
        now: DateTime(2026, 1, 2, 3, 4, 5, 6, 7),
      );

      expect(path, matches(r'^menu-images/menu_item_42/\d+\.png$'));
    });

    test('normalizes content types', () {
      expect(MenuImageUploadService.contentTypeFor('dish.png'), 'image/png');
      expect(MenuImageUploadService.contentTypeFor('dish.jpg'), 'image/jpeg');
    });

    test('formats upload errors', () {
      expect(
        menuImageUploadErrorMessage(
          const MenuImageUploadException('No camera here'),
        ),
        'No camera here',
      );
      expect(
        menuImageUploadErrorMessage(Object()),
        'Could not upload image. Please try again.',
      );
    });
  });

  group('MenuImagePickerField', () {
    testWidgets('uploads a gallery image into the URL controller',
        (tester) async {
      final controller = TextEditingController();
      final uploaded = <String>[];
      final service = _FakeUploadService(url: 'https://example.com/dish.png');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MenuImagePickerField(
              imageUrlController: controller,
              onImageUploaded: uploaded.add,
              uploadService: service,
              isWeb: false,
              platform: TargetPlatform.iOS,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Upload from gallery/album'));
      await tester.pumpAndSettle();

      expect(service.calls, 1);
      expect(controller.text, 'https://example.com/dish.png');
      expect(uploaded, <String>['https://example.com/dish.png']);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows upload errors without changing the URL', (tester) async {
      final controller = TextEditingController();
      final service = _FakeUploadService(
        url: '',
        error: const MenuImageUploadException('Camera blocked'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MenuImagePickerField(
              imageUrlController: controller,
              onImageUploaded: (_) {},
              uploadService: service,
              isWeb: false,
              platform: TargetPlatform.iOS,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Take image'));
      await tester.pumpAndSettle();

      expect(find.text('Camera blocked'), findsOneWidget);
      expect(controller.text, isEmpty);
    });
  });
}
