import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ai_assistant_provider.dart';
import '../theme.dart';
import 'sage_avatar.dart';

/// Publishes the live screen-space bounds of its child after layout and on
/// size/metrics changes. The GlobalKey is stable across rebuilds so the Sage
/// popup can always point at the avatar that is actually on screen.
class SageAnchorPublisher extends StatefulWidget {
  const SageAnchorPublisher({
    Key? key,
    required this.onAnchorChanged,
    required this.child,
  }) : super(key: key);

  final ValueChanged<Rect?> onAnchorChanged;
  final Widget child;

  @override
  State<SageAnchorPublisher> createState() => _SageAnchorPublisherState();
}

class _SageAnchorPublisherState extends State<SageAnchorPublisher>
    with WidgetsBindingObserver {
  final GlobalKey _anchorKey = GlobalKey(debugLabel: 'sage-header-anchor');
  Rect? _lastRect;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _schedulePublish();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedulePublish();
  }

  @override
  void didUpdateWidget(covariant SageAnchorPublisher oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedulePublish();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _schedulePublish();
  }

  void _schedulePublish() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _publish();
    });
  }

  void _publish() {
    final renderObject = _anchorKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      _clear();
      return;
    }
    final rect = renderObject.localToGlobal(Offset.zero) & renderObject.size;
    if (_lastRect == rect) return;
    _lastRect = rect;
    widget.onAnchorChanged(rect);
  }

  void _clear() {
    final rect = _lastRect;
    if (rect == null) return;
    _lastRect = null;
    widget.onAnchorChanged(null);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: _anchorKey, child: widget.child);
  }
}

class SageHeaderButton extends StatefulWidget {
  const SageHeaderButton({Key? key})
      : super(key: key ?? const Key('sage-header-button'));

  @override
  State<SageHeaderButton> createState() => _SageHeaderButtonState();
}

class _SageHeaderButtonState extends State<SageHeaderButton> {
  Rect? _publishedRect;

  void _onAnchorChanged(Rect? rect) {
    final provider = context.read<AIAssistantProvider>();
    if (rect == null) {
      final previous = _publishedRect;
      if (previous != null) provider.clearSageAnchor(previous);
      _publishedRect = null;
      return;
    }
    _publishedRect = rect;
    provider.updateSageAnchor(rect);
  }

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
                SageAnchorPublisher(
                  onAnchorChanged: _onAnchorChanged,
                  child: Stack(
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
                              border:
                                  Border.all(color: Colors.white, width: 1.5),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (!narrow) ...[
                  const SizedBox(width: 6),
                  const Text(
                    'Sage',
                    style: TextStyle(
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
