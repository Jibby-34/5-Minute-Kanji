import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models/kanji_card.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/app_typography.dart';
import '../core/utils/mnemonic_links.dart';

const _popupWidth = 132.0;
const _popupGap = 6.0;

/// Renders a mnemonic as English, with a small lightbulb beside each phrase
/// that has a component reference.
class MnemonicText extends StatefulWidget {
  const MnemonicText({
    super.key,
    required this.mnemonic,
    required this.components,
    required this.style,
  });

  final String mnemonic;
  final List<KanjiComponent> components;
  final TextStyle style;

  @override
  State<MnemonicText> createState() => _MnemonicTextState();
}

class _MnemonicTextState extends State<MnemonicText> {
  final _layerLink = LayerLink();
  final _linkKeys = <int, GlobalKey>{};
  OverlayEntry? _overlay;
  int? _openIndex;
  late List<MnemonicSegment> _segments;

  @override
  void initState() {
    super.initState();
    _segments = segmentMnemonic(widget.mnemonic, widget.components);
  }

  @override
  void didUpdateWidget(MnemonicText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_sameContent(oldWidget)) return;
    _removeOverlay();
    _openIndex = null;
    _linkKeys.clear();
    _segments = segmentMnemonic(widget.mnemonic, widget.components);
  }

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  bool _sameContent(MnemonicText oldWidget) {
    if (oldWidget.mnemonic != widget.mnemonic) return false;
    if (oldWidget.components.length != widget.components.length) return false;
    for (var index = 0; index < widget.components.length; index++) {
      final previous = oldWidget.components[index];
      final next = widget.components[index];
      if (previous.id != next.id ||
          previous.character != next.character ||
          previous.name != next.name ||
          previous.mnemonicText != next.mnemonicText ||
          previous.occurrence != next.occurrence ||
          previous.image != next.image) {
        return false;
      }
    }
    return true;
  }

  bool get _hasLinks => _segments.any((segment) => segment.isLink);

  GlobalKey _keyFor(int index) => _linkKeys.putIfAbsent(index, GlobalKey.new);

  void _toggle(int index) {
    if (_openIndex == index) {
      _close();
      return;
    }
    _removeOverlay();
    setState(() => _openIndex = index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _openIndex != index) return;
      _showOverlay(index);
    });
  }

  void _close() {
    if (_overlay == null && _openIndex == null) return;
    _removeOverlay();
    if (!mounted) return;
    setState(() => _openIndex = null);
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  void _showOverlay(int index) {
    final overlay = Overlay.maybeOf(context);
    final box =
        _linkKeys[index]?.currentContext?.findRenderObject() as RenderBox?;
    if (overlay == null || box == null || !box.hasSize || !box.attached) {
      return;
    }

    final component = _segments[index].component;
    if (component == null) return;

    final global = box.localToGlobal(Offset.zero);
    final media = MediaQuery.of(context);
    final screen = media.size;
    final minLeft = 12.0 + media.padding.left;
    final maxLeft = screen.width - _popupWidth - 12.0 - media.padding.right;
    final center = global.dx + box.size.width / 2;
    final idealLeft = center - _popupWidth / 2;
    final left = maxLeft < minLeft
        ? minLeft
        : idealLeft.clamp(minLeft, maxLeft);
    final shiftX = left - idealLeft;
    const estimatedHeight = 118.0;
    final spaceBelow =
        screen.height -
        media.padding.bottom -
        (global.dy + box.size.height + _popupGap);
    final showAbove =
        spaceBelow < estimatedHeight &&
        global.dy > estimatedHeight + media.padding.top;

    _removeOverlay();
    _overlay = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) => _handleBarrierTap(details.globalPosition),
              ),
            ),
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              targetAnchor: showAbove
                  ? Alignment.topCenter
                  : Alignment.bottomCenter,
              followerAnchor: showAbove
                  ? Alignment.bottomCenter
                  : Alignment.topCenter,
              offset: Offset(shiftX, showAbove ? -_popupGap : _popupGap),
              child: _ComponentPopup(component: component),
            ),
          ],
        );
      },
    );
    overlay.insert(_overlay!);
  }

  void _handleBarrierTap(Offset globalPosition) {
    final index = _linkAt(globalPosition);
    if (index == null || index == _openIndex) {
      _close();
      return;
    }
    _toggle(index);
  }

  int? _linkAt(Offset globalPosition) {
    for (final entry in _linkKeys.entries) {
      final render = entry.value.currentContext?.findRenderObject();
      if (render is! RenderBox || !render.hasSize || !render.attached) {
        continue;
      }
      final local = render.globalToLocal(globalPosition);
      if (render.size.contains(local)) return entry.key;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Memory aid: ${widget.mnemonic}',
      explicitChildNodes: _hasLinks,
      excludeSemantics: !_hasLinks,
      child: _hasLinks ? _linkedText() : _plainText(),
    );
  }

  Widget _plainText() {
    return Text(widget.mnemonic, style: widget.style);
  }

  Widget _linkedText() {
    final children = <InlineSpan>[];
    for (var index = 0; index < _segments.length; index++) {
      final segment = _segments[index];
      final component = segment.component;
      if (component == null) {
        // The parent node announces the full mnemonic. These fragments stay
        // visible, without a second spoken copy.
        children.add(TextSpan(text: segment.text, semanticsLabel: ''));
        continue;
      }
      final link = _link(index, segment.text, component);
      children.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _openIndex == index
              ? CompositedTransformTarget(link: _layerLink, child: link)
              : link,
        ),
      );
    }

    return Text.rich(TextSpan(style: widget.style, children: children));
  }

  Widget _link(int index, String text, KanjiComponent component) {
    return _MnemonicLink(
      key: _keyFor(index),
      text: text,
      component: component,
      style: widget.style,
      onTap: () => _toggle(index),
    );
  }
}

class _MnemonicLink extends StatelessWidget {
  const _MnemonicLink({
    super.key,
    required this.text,
    required this.component,
    required this.style,
    required this.onTap,
  });

  final String text;
  final KanjiComponent component;
  final TextStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: 'Show the ${component.name} component',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text, style: style),
              const SizedBox(width: 2),
              Icon(
                Icons.lightbulb_outline,
                size: 12,
                color: theme.colorScheme.primary.withValues(alpha: 0.72),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComponentPopup extends StatelessWidget {
  const _ComponentPopup({required this.component});

  final KanjiComponent component;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      color: isDark ? theme.colorScheme.surface : Colors.white,
      elevation: isDark ? 8 : 3,
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.45 : 0.16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.hairline),
      ),
      child: SizedBox(
        width: _popupWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ComponentGlyph(component: component, size: 44),
              const SizedBox(height: 4),
              Text(
                component.name,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.mutedText,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComponentGlyph extends StatefulWidget {
  const _ComponentGlyph({required this.component, required this.size});

  final KanjiComponent component;
  final double size;

  @override
  State<_ComponentGlyph> createState() => _ComponentGlyphState();
}

class _ComponentGlyphState extends State<_ComponentGlyph> {
  var _hasAsset = false;

  @override
  void initState() {
    super.initState();
    _lookup();
  }

  @override
  void didUpdateWidget(_ComponentGlyph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.component.image != widget.component.image) {
      _hasAsset = false;
      _lookup();
    }
  }

  Future<void> _lookup() async {
    final image = widget.component.image;
    if (image == null || image.isEmpty) return;
    final exists = await _ComponentAssets.contains(image);
    if (!mounted || image != widget.component.image || !exists) return;
    setState(() => _hasAsset = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fallback = Text(
      widget.component.character,
      textAlign: TextAlign.center,
      style: AppTypography.kanji(
        color: theme.colorScheme.onSurface,
        size: widget.size,
      ),
    );
    final image = widget.component.image;
    if (!_hasAsset || image == null || image.isEmpty) return fallback;
    return Semantics(
      label: widget.component.character,
      child: Image.asset(
        image,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
        errorBuilder: (context, error, stackTrace) => fallback,
      ),
    );
  }
}

/// Looks up component illustrations without throwing when a file is absent.
class _ComponentAssets {
  _ComponentAssets._();

  static Future<Set<String>>? _assets;

  static Future<bool> contains(String path) {
    return _load().then((assets) => assets.contains(path));
  }

  static Future<Set<String>> _load() {
    return _assets ??= _read();
  }

  static Future<Set<String>> _read() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      return manifest.listAssets().toSet();
    } catch (_) {
      return const {};
    }
  }
}
