import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ai_assistant_provider.dart';
import '../theme.dart';
import 'sage_avatar.dart';

class SageHeaderButton extends StatelessWidget {
  const SageHeaderButton({Key? key})
      : super(key: key ?? const Key('sage-header-button'));

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AIAssistantProvider>();
    if (provider.staffDashboardActive) {
      return const SizedBox.shrink();
    }

    final narrow = MediaQuery.sizeOf(context).width < 600;
    final avatarSize = narrow ? 30.0 : 34.0;

    return Semantics(
      button: true,
      label: 'Ask Sage',
      child: Tooltip(
        message: 'Ask Sage',
        child: GestureDetector(
          onTap: provider.togglePanel,
          onLongPress: () {
            final content = provider.popupContent ??
                (provider.activeInsights.isNotEmpty
                    ? provider.activeInsights.first.message
                    : 'No alerts');
            provider.displayPopup(content);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    SageAvatar(size: avatarSize),
                    if (provider.hasNewImportantInsight)
                      Positioned(
                        right: -1,
                        top: -1,
                        child: Container(
                          key: const Key('sage-header-badge'),
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                        ),
                      ),
                  ],
                ),
                if (!narrow) ...[
                  const SizedBox(width: 6),
                  Text(
                    'Sage',
                    style: const TextStyle(
                      color: AppTheme.sageCyan,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
