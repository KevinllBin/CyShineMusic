import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/tooltip.dart';

/// [text], with a tooltip of its whole string once it is cut short.
class TooltipText extends StatefulWidget {
  final Text text;

  const TooltipText({super.key, required this.text});

  @override
  State<TooltipText> createState() => _TooltipTextState();
}

class _TooltipTextState extends State<TooltipText> {
  bool _cut = false;
  bool? _reported;

  // Paint finds the text cut short, so the tooltip joins it a frame later.
  void _handleCut(bool cut) {
    final scheduled = _reported != null;
    _reported = cut;
    if (scheduled) {
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final cut = _reported!;
      _reported = null;
      if (mounted && cut != _cut) {
        setState(() => _cut = cut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = _CutReporter(onCut: _handleCut, child: widget.text);
    if (!_cut) {
      return text;
    }
    return Tooltip(
      triggerMode: TooltipTriggerMode.longPress,
      preferBelow: false,
      message: widget.text.data ?? '',
      child: text,
    );
  }
}

class _CutReporter extends SingleChildRenderObjectWidget {
  const _CutReporter({required this.onCut, required super.child});

  final ValueChanged<bool> onCut;

  @override
  _RenderCutReporter createRenderObject(BuildContext context) =>
      _RenderCutReporter(onCut);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCutReporter renderObject,
  ) {
    renderObject.onCut = onCut;
  }
}

class _RenderCutReporter extends RenderProxyBox {
  _RenderCutReporter(this.onCut);

  ValueChanged<bool> onCut;
  bool _cut = false;

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    RenderObject? node = child;
    while (node is RenderProxyBox) {
      node = node.child;
    }
    final cut = node is RenderParagraph && node.didExceedMaxLines;
    if (cut != _cut) {
      _cut = cut;
      onCut(cut);
    }
  }
}

/// A tooltip only a hovering pointer raises, built on its first hover: touch
/// has no hover, and a long press belongs to the row's context menu.
class HoverTooltip extends StatefulWidget {
  const HoverTooltip({super.key, required this.message, required this.child});

  final String message;
  final Widget child;

  @override
  State<HoverTooltip> createState() => _HoverTooltipState();
}

class _HoverTooltipState extends State<HoverTooltip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    if (_hovered) {
      return Tooltip(message: widget.message, child: widget.child);
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      child: Semantics(tooltip: widget.message, child: widget.child),
    );
  }
}

class TooltipLabel extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int maxLines;

  const TooltipLabel(this.text, {super.key, this.style, this.maxLines = 2});

  @override
  Widget build(BuildContext context) {
    return TooltipText(
      text: Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: DefaultTextStyle.of(context).style.merge(style),
      ),
    );
  }
}

/// What [EmojiText] draws in which font, below it; without one, emoji keep the
/// font of the text around them.
class EmojiFont extends InheritedWidget {
  const EmojiFont({
    super.key,
    required this.family,
    required this.pattern,
    required super.child,
  });

  final String family;
  final Pattern pattern;

  static EmojiFont? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<EmojiFont>();

  @override
  bool updateShouldNotify(EmojiFont oldWidget) =>
      family != oldWidget.family || pattern != oldWidget.pattern;
}

class EmojiText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  const EmojiText(
    this.text, {
    super.key,
    this.maxLines,
    this.overflow,
    this.style,
  });

  static TextSpan _spanOf(String text, TextStyle? style, EmojiFont? emojiFont) {
    if (emojiFont == null) {
      return TextSpan(text: text, style: style);
    }
    final List<TextSpan> spans = [];
    final matches = emojiFont.pattern.allMatches(text);

    int lastMatchEnd = 0;
    for (final match in matches) {
      if (match.start > lastMatchEnd) {
        spans.add(
          TextSpan(
            text: text.substring(lastMatchEnd, match.start),
            style: style,
          ),
        );
      }
      spans.add(
        TextSpan(
          text: match.group(0),
          style: (style ?? const TextStyle()).copyWith(
            fontFamily: emojiFont.family,
          ),
        ),
      );
      lastMatchEnd = match.end;
    }
    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastMatchEnd), style: style));
    }

    return TextSpan(children: spans);
  }

  /// The width [EmojiText] lays [text] out at on one line under [style].
  static double widthOf(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(
        style: MediaQuery.boldTextOf(context)
            ? style.merge(const TextStyle(fontWeight: FontWeight.bold))
            : style,
        children: [_spanOf(text, null, EmojiFont.of(context))],
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      maxLines: 1,
    )..layout();
    try {
      return painter.maxIntrinsicWidth;
    } finally {
      painter.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      _spanOf(text, style, EmojiFont.of(context)),
      style: style,
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
    );
  }
}
