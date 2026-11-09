import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:prism_ui/prism_ui.dart' as prism;
import 'package:prism_ui/icons/icons.dart' as glyph;

import '../../../core/ui/widgets/header_control_style.dart';
import '../../../theme/app_motion.dart';
import '../../shell/widgets/scrolling_page_header.dart';

const double _searchButtonSize = 44;
const double _searchFieldGap = 12;

/// The right-hand search button grows leftward over the title. The text field
/// keeps its final width while being revealed, avoiding relayout during typing.
class ExpandingHeaderSearch extends StatefulWidget {
  const ExpandingHeaderSearch({
    super.key,
    required this.title,
    required this.controller,
    required this.focusNode,
    required this.expanded,
    required this.onOpen,
    required this.onClose,
    required this.onChanged,
    this.hint = '搜索歌曲、歌手或专辑',
    this.tooltip = '搜索歌曲',
    this.onImage = false,
    this.titleOpacity = 1,
    this.actions = const [],
    this.collapsedContent,
    this.autoFocus = true,
    this.shrinkWrap = false,
    this.closedEndInset = 0,
  });

  final String title;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool expanded;
  final VoidCallback onOpen, onClose;
  final ValueChanged<String> onChanged;
  final String hint, tooltip;
  final bool onImage;
  final double titleOpacity;
  final List<Widget> actions;
  final Widget? collapsedContent;
  final bool autoFocus;
  final bool shrinkWrap;

  /// Space reserved by actions that sit to the right of the search lead while
  /// the bar is closed. Prism UI releases this space as the field grows so the
  /// open search layer can cover the complete toolbar.
  final double closedEndInset;

  @override
  State<ExpandingHeaderSearch> createState() => _ExpandingHeaderSearchState();
}

class _ExpandingHeaderSearchState extends State<ExpandingHeaderSearch>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: AppMotion.medium,
    reverseDuration: AppMotion.short,
    value: widget.expanded ? 1 : 0,
  )..addStatusListener(_onStatus);
  late final CurvedAnimation _progress = CurvedAnimation(
    parent: _motion,
    curve: AppMotion.emphasized,
    reverseCurve: AppMotion.emphasized,
  );

  @override
  void initState() {
    super.initState();
    if (widget.expanded) _requestFocus();
  }

  void _requestFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          widget.expanded &&
          widget.autoFocus &&
          TickerMode.valuesOf(context).enabled &&
          ModalRoute.of(context)?.isCurrent != false) {
        widget.focusNode.requestFocus();
      }
    });
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _requestFocus();
  }

  @override
  void didUpdateWidget(covariant ExpandingHeaderSearch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expanded == widget.expanded) return;
    if (!widget.expanded) widget.focusNode.unfocus();
    if (MediaQuery.disableAnimationsOf(context)) {
      _motion.value = widget.expanded ? 1 : 0;
    } else if (widget.expanded) {
      _motion.forward();
    } else {
      _motion.reverse();
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: AnimatedBuilder(
        animation: _progress,
        builder: (context, _) {
          final progress = _progress.value;
          final showingField = widget.expanded || !_motion.isDismissed;
          return Stack(
            alignment: Alignment.centerRight,
            clipBehavior: Clip.none,
            children: [
              IgnorePointer(
                ignoring: showingField,
                child: ExcludeSemantics(
                  excluding: showingField,
                  child: Opacity(
                    opacity: 1 - progress,
                    child: Row(
                      mainAxisSize: widget.shrinkWrap
                          ? MainAxisSize.min
                          : MainAxisSize.max,
                      children: [
                        Flexible(
                          fit: widget.shrinkWrap
                              ? FlexFit.loose
                              : FlexFit.tight,
                          child:
                              widget.collapsedContent ??
                              Opacity(
                                opacity: widget.titleOpacity,
                                child: Text(
                                  widget.title,
                                  maxLines: 1,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                        ),
                        if (widget.actions.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          FloatingHeaderSurface(
                            onImage: widget.onImage,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: widget.actions,
                            ),
                          ),
                        ],
                        SizedBox(width: widget.shrinkWrap ? 50 : 52),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final endInset = widget.closedEndInset * (1 - progress);
                    final availableWidth = math.max(44, width - endInset);
                    final groupWidth = lerpDouble(
                      _searchButtonSize,
                      availableWidth,
                      progress,
                    )!;
                    final finalFieldWidth = math.max(
                      0.0,
                      availableWidth - _searchButtonSize - _searchFieldGap,
                    );
                    final fieldWidth = math.max(
                      0.0,
                      groupWidth - _searchButtonSize - _searchFieldGap,
                    );
                    return Padding(
                      // The closed lead sits immediately before the overflow
                      // action. This inset is released as the field takes over
                      // the complete toolbar.
                      padding: EdgeInsetsDirectional.only(end: endInset),
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: SizedBox(
                          width: groupWidth,
                          height: _searchButtonSize,
                          child: _SearchSurface(
                            expanded: showingField,
                            child: TextFieldTapRegion(
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  if (showingField && fieldWidth > 0)
                                    Positioned(
                                      left: 0,
                                      top: 0,
                                      width: fieldWidth,
                                      height: _searchButtonSize,
                                      child: _SearchPane(
                                        child: ClipRect(
                                          child: IgnorePointer(
                                            ignoring: !widget.expanded,
                                            child: Opacity(
                                              opacity:
                                                  ((progress - 0.05) / 0.95)
                                                      .clamp(0, 1),
                                              child: OverflowBox(
                                                alignment: AlignmentDirectional
                                                    .centerStart,
                                                minWidth: finalFieldWidth,
                                                maxWidth: finalFieldWidth,
                                                child: prism.SearchField(
                                                  key: const ValueKey(
                                                    'header-search-field',
                                                  ),
                                                  controller: widget.controller,
                                                  focusNode: widget.focusNode,
                                                  hintText: widget.hint,
                                                  height: _searchButtonSize,
                                                  onChanged: widget.onChanged,
                                                  onSubmitted: () => widget
                                                      .focusNode
                                                      .unfocus(),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  Positioned(
                                    right: 0,
                                    top: 0,
                                    bottom: 0,
                                    width: _searchButtonSize,
                                    child: prism.TonalButtonTheme(
                                      size: prism.TonalButtonSize.bar,
                                      glass: prism.LiquidGlassScope.of(context),
                                      child: prism.ElasticPress(
                                        child: prism.IconButton(
                                          tooltip: widget.expanded
                                              ? '取消'
                                              : widget.tooltip,
                                          onPressed: widget.expanded
                                              ? widget.onClose
                                              : widget.onOpen,
                                          style:
                                              prism.ButtonStyle.from(
                                                fixedSize: const Size.square(
                                                  _searchButtonSize,
                                                ),
                                                minimumSize: const Size.square(
                                                  _searchButtonSize,
                                                ),
                                                padding: EdgeInsets.zero,
                                                tapTargetSize: prism
                                                    .TapTargetSize
                                                    .shrinkWrap,
                                                pressLook: prism.PressLook.none,
                                              ).merge(
                                                headerControlButtonStyle(
                                                  context,
                                                ),
                                              ),
                                          icon: AnimatedSwitcher(
                                            duration:
                                                MediaQuery.disableAnimationsOf(
                                                  context,
                                                )
                                                ? Duration.zero
                                                : AppMotion.short,
                                            child: glyph.GlyphIcon(
                                              widget.expanded
                                                  ? glyph.Glyphs.close
                                                  : glyph.Glyphs.search,
                                              key: ValueKey(widget.expanded),
                                              size: prism
                                                  .TonalButtonSize
                                                  .bar
                                                  .icon,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A closed search uses the same themed button as the other header actions.
/// With glass enabled, the expanding field and cancel share a GooSurface.
/// Otherwise each control draws its own fill and outline for contrast.
class _SearchSurface extends StatelessWidget {
  const _SearchSurface({required this.expanded, required this.child});

  final bool expanded;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!expanded || !prism.LiquidGlassScope.of(context)) return child;
    final scheme = prism.Theme.of(context).colorScheme;
    return prism.GooSurface(
      glass: prism.LiquidGlassStyle.regular(scheme),
      color: prism.SurfaceScope.of(context).next.colorOf(scheme),
      child: child,
    );
  }
}

class _SearchPane extends StatelessWidget {
  const _SearchPane({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => prism.ElasticPress(
    child: prism.LiquidGlassScope.of(context)
        ? prism.GooPane(child: child)
        : DecoratedBox(
            decoration: ShapeDecoration(
              color: headerControlFill(context),
              shape: StadiumBorder(side: headerControlBorder(context)),
            ),
            child: child,
          ),
  );
}
