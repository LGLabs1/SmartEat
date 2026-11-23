import 'package:flutter/material.dart';

class ResponsiveSearchField extends StatelessWidget {
  const ResponsiveSearchField({
    super.key,
    required this.fieldBuilder,
    this.threshold = 520,
    this.tooltip = 'Search',
    this.iconColor,
  });

  final Widget Function(BuildContext context, {required bool autofocus})
      fieldBuilder;
  final double threshold;
  final String tooltip;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= threshold) {
      return fieldBuilder(context, autofocus: false);
    }

    return IconButton(
      tooltip: tooltip,
      icon: Icon(Icons.search, color: iconColor),
      onPressed: () {
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (sheetContext) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                16 + MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(sheetContext).colorScheme.outline,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 12),
                  fieldBuilder(sheetContext, autofocus: true),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
