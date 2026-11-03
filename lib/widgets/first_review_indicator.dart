import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';

/// Small note for a kanji marked known that has not been rated yet.
///
/// A tap opens the explanation. The icon stays quiet so the character
/// remains the focus.
class FirstReviewIndicator extends StatefulWidget {
  const FirstReviewIndicator({super.key});

  static const title = 'Previously marked as known';

  static const explanation =
      'This kanji was marked as known during your placement test or when you added it to your known kanji. This is your first review of it!';

  @override
  State<FirstReviewIndicator> createState() => _FirstReviewIndicatorState();
}

class _FirstReviewIndicatorState extends State<FirstReviewIndicator> {
  final OverlayPortalController _overlay = OverlayPortalController();

  void _toggle() {
    if (_overlay.isShowing) {
      _overlay.hide();
    } else {
      _overlay.show();
    }
  }

  void _hide() {
    if (_overlay.isShowing) _overlay.hide();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _overlay,
      overlayChildBuilder: _popover,
      child: IconButton(
        onPressed: _toggle,
        tooltip: FirstReviewIndicator.title,
        style: IconButton.styleFrom(
          foregroundColor: theme.mutedText,
          backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.92),
          minimumSize: const Size(32, 32),
          fixedSize: const Size(32, 32),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          side: BorderSide(color: theme.hairline),
        ),
        icon: const Icon(Icons.info_outline, size: 16),
      ),
    );
  }

  Widget _popover(BuildContext context, OverlayChildLayoutInfo info) {
    final theme = Theme.of(context);
    final place = _place(info);
    final dark = theme.brightness == Brightness.dark;

    return SizedBox(
      width: info.overlaySize.width,
      height: info.overlaySize.height,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: _hide,
              behavior: HitTestBehavior.translucent,
            ),
          ),
          Positioned(
            left: place.left,
            top: place.top,
            width: place.width,
            child: Material(
              color: dark ? AppColors.darkSurface : AppColors.paperDeep,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: theme.hairline),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      FirstReviewIndicator.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        letterSpacing: -0.2,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      FirstReviewIndicator.explanation,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.78,
                        ),
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  _PopoverPlace _place(OverlayChildLayoutInfo info) {
    const width = 280.0;
    const margin = 12.0;
    const estimatedHeight = 168.0;
    final translation = info.childPaintTransform.getTranslation();
    final anchor = Offset(translation.x, translation.y);
    final overlay = info.overlaySize;

    var left = anchor.dx + info.childSize.width - width;
    if (left < margin) left = margin;
    final maxLeft = overlay.width - width - margin;
    if (maxLeft > margin && left > maxLeft) left = maxLeft;
    if (left < margin) left = margin;

    var top = anchor.dy + info.childSize.height + 6;
    if (top + estimatedHeight > overlay.height - margin) {
      top = anchor.dy - estimatedHeight - 6;
    }
    if (top < margin) top = margin;

    final fittedWidth = overlay.width - margin * 2;
    return _PopoverPlace(
      left: left,
      top: top,
      width: fittedWidth < width ? fittedWidth : width,
    );
  }
}

class _PopoverPlace {
  const _PopoverPlace({
    required this.left,
    required this.top,
    required this.width,
  });

  final double left;
  final double top;
  final double width;
}
