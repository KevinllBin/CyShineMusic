import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter/widgets.dart';
import 'package:prism_ui/text_field.dart';
import 'package:prism_ui/text_loupe.dart';
import 'package:prism_ui/text_selection_controls.dart';
import 'package:prism_ui/text_selection_menu.dart';

/// Lets the [Text]s under it be selected together.
class SelectionArea extends StatelessWidget {
  const SelectionArea({
    super.key,
    this.focusNode,
    this.contextMenuBuilder = TextSelectionMenu.selectableRegion,
    this.onSelectionChanged,
    required this.child,
  });

  final FocusNode? focusNode;
  final SelectableRegionContextMenuBuilder? contextMenuBuilder;
  final ValueChanged<SelectedContent?>? onSelectionChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SelectableRegion(
      selectionControls: textSelectionControlsFor(defaultTargetPlatform),
      focusNode: focusNode,
      contextMenuBuilder: contextMenuBuilder,
      magnifierConfiguration: textLoupeConfiguration,
      onSelectionChanged: onSelectionChanged,
      child: child,
    );
  }
}

/// Text on its own that can be selected, without a [SelectionArea] around it.
class SelectableText extends StatefulWidget {
  const SelectableText(
    String this.data, {
    super.key,
    this.style,
    this.textAlign = TextAlign.start,
    this.maxLines,
    this.minLines,
    this.contextMenuBuilder = TextSelectionMenu.editableText,
  }) : textSpan = null;

  const SelectableText.rich(
    TextSpan this.textSpan, {
    super.key,
    this.style,
    this.textAlign = TextAlign.start,
    this.maxLines,
    this.minLines,
    this.contextMenuBuilder = TextSelectionMenu.editableText,
  }) : data = null;

  final String? data;
  final TextSpan? textSpan;
  final TextStyle? style;
  final TextAlign textAlign;
  final int? maxLines;
  final int? minLines;
  final EditableTextContextMenuBuilder? contextMenuBuilder;

  @override
  State<SelectableText> createState() => _SelectableTextState();
}

class _SelectableTextState extends State<SelectableText> {
  late final _controller = _SpanController(_span);
  final _focusNode = FocusNode(skipTraversal: true);

  TextSpan get _span => widget.textSpan ?? TextSpan(text: widget.data ?? '');

  @override
  void didUpdateWidget(SelectableText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.data != oldWidget.data ||
        widget.textSpan != oldWidget.textSpan) {
      _controller.span = _span;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SelectableField(
      controller: _controller,
      focusNode: _focusNode,
      decoration: null,
      readOnly: true,
      showCursor: false,
      autocorrect: false,
      maxLines: widget.maxLines,
      minLines: widget.minLines,
      textAlign: widget.textAlign,
      style: DefaultTextStyle.of(context).style.merge(widget.style),
      scrollPhysics: const NeverScrollableScrollPhysics(),
      mouseCursor: SystemMouseCursors.text,
      contextMenuBuilder: widget.contextMenuBuilder,
    );
  }
}

// Its own type, so that finding the TextFields means the ones that take input.
class _SelectableField extends TextField {
  const _SelectableField({
    super.controller,
    super.focusNode,
    super.decoration,
    super.readOnly,
    super.showCursor,
    super.autocorrect,
    super.maxLines,
    super.minLines,
    super.textAlign,
    super.style,
    super.scrollPhysics,
    super.mouseCursor,
    super.contextMenuBuilder,
  });
}

class _SpanController extends TextEditingController {
  _SpanController(this._span) : super(text: _span.toPlainText());

  TextSpan _span;

  set span(TextSpan value) {
    _span = value;
    final text = value.toPlainText();
    this.value = TextEditingValue(
      text: text,
      selection: text == this.text
          ? selection
          : const TextSelection.collapsed(offset: -1),
    );
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) => TextSpan(style: style, children: [_span]);
}
