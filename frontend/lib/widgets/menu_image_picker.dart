import 'package:flutter/material.dart';

import '../services/menu_image_upload_service.dart';

class MenuImagePickerField extends StatefulWidget {
  const MenuImagePickerField({
    Key? key,
    required this.imageUrlController,
    required this.onImageUploaded,
    this.menuItemId,
    this.uploadService,
    this.isWeb,
    this.platform,
  }) : super(key: key);

  final TextEditingController imageUrlController;
  final ValueChanged<String> onImageUploaded;
  final String? menuItemId;
  final MenuImageUploadService? uploadService;
  final bool? isWeb;
  final TargetPlatform? platform;

  @override
  State<MenuImagePickerField> createState() => _MenuImagePickerFieldState();
}

class _MenuImagePickerFieldState extends State<MenuImagePickerField> {
  late final MenuImageUploadService _service;

  bool _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = widget.uploadService ?? MenuImageUploadService();
  }

  Future<void> _handlePick(MenuImageSource source) async {
    if (_uploading) return;

    setState(() {
      _uploading = true;
      _error = null;
    });

    try {
      final url = await _service.pickAndUpload(
        source,
        menuItemId: widget.menuItemId,
      );

      if (!mounted || url.isEmpty) return;

      widget.imageUrlController.text = url;
      widget.onImageUploaded(url);
    } catch (e) {
      if (mounted) {
        setState(() => _error = menuImageUploadErrorMessage(e));
      }
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = widget.imageUrlController.text.trim();
    final cameraSupported = MenuImageUploadService.isSourceSupported(
      MenuImageSource.camera,
      isWeb: widget.isWeb,
      platform: widget.platform,
    );
    final gallerySupported = MenuImageUploadService.isSourceSupported(
      MenuImageSource.gallery,
      isWeb: widget.isWeb,
      platform: widget.platform,
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 68,
                  height: 68,
                  child: url.isEmpty
                      ? Container(
                          color: theme.colorScheme.surface,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.add_photo_alternate_outlined,
                            color: theme.colorScheme.onSurfaceVariant,
                            size: 30,
                          ),
                        )
                      : Image.network(
                          url,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: theme.colorScheme.surface,
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                color: theme.colorScheme.onSurfaceVariant,
                                size: 30,
                              ),
                            );
                          },
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Add a dish photo',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Capture or choose an image to upload automatically.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              Tooltip(
                message: cameraSupported
                    ? 'Take a new photo'
                    : MenuImageUploadService.unsupportedMessage(
                        MenuImageSource.camera),
                child: OutlinedButton.icon(
                  onPressed: _uploading || !cameraSupported
                      ? null
                      : () => _handlePick(MenuImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Take image'),
                ),
              ),
              Tooltip(
                message: gallerySupported
                    ? 'Choose an existing photo'
                    : MenuImageUploadService.unsupportedMessage(
                        MenuImageSource.gallery),
                child: FilledButton.tonalIcon(
                  onPressed: _uploading || !gallerySupported
                      ? null
                      : () => _handlePick(MenuImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Upload from gallery/album'),
                ),
              ),
            ],
          ),
          if (_uploading) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Uploading image...',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline,
                    size: 16, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
