import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../../theme/app_motion.dart';
import '../../shell/widgets/scrolling_page_header.dart';

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
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
      child: AnimatedBuilder(
        animation: _progress,
        builder: (context, _) {
          final progress = _progress.value;
          final showingField = widget.expanded || !_motion.isDismissed;
          return Stack(
            alignment: Alignment.centerRight,
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
                    return Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                        width: lerpDouble(44, width, progress),
                        height: 44,
                        child: FloatingHeaderSurface(
                          onImage: widget.onImage,
                          child: ColoredBox(
                            color: scheme.surfaceContainerHigh.withValues(
                              alpha: progress,
                            ),
                            child: Stack(
                              children: [
                                if (showingField)
                                  Positioned(
                                    top: 0,
                                    bottom: 0,
                                    left: 0,
                                    right: 44,
                                    child: ClipRect(
                                      child: OverflowBox(
                                        alignment: Alignment.centerLeft,
                                        minWidth: (width - 44).clamp(
                                          0,
                                          double.infinity,
                                        ),
                                        maxWidth: (width - 44).clamp(
                                          0,
                                          double.infinity,
                                        ),
                                        child: IgnorePointer(
                                          ignoring: !widget.expanded,
                                          child: Opacity(
                                            opacity: ((progress - 0.2) / 0.8)
                                                .clamp(0, 1),
                                            child: TextField(
                                              key: const ValueKey(
                                                'header-search-field',
                                              ),
                                              controller: widget.controller,
                                              focusNode: widget.focusNode,
                                              onChanged: widget.onChanged,
                                              textInputAction:
                                                  TextInputAction.search,
                                              onSubmitted: (_) =>
                                                  widget.focusNode.unfocus(),
                                              style: TextStyle(
                                                color: scheme.onSurface,
                                                fontSize: 14,
                                                height: 1.2,
                                              ),
                                              decoration: InputDecoration(
                                                hintText: widget.hint,
                                                isDense: true,
                                                filled: false,
                                                hintStyle: TextStyle(
                                                  color:
                                                      scheme.onSurfaceVariant,
                                                  fontSize: 13,
                                                ),
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 14,
                                                      vertical: 13,
                                                    ),
                                                border: InputBorder.none,
                                                enabledBorder: InputBorder.none,
                                                focusedBorder: InputBorder.none,
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
                                  width: 44,
                                  child: IconButton(
                                    tooltip: widget.expanded
                                        ? '退出搜索'
                                        : widget.tooltip,
                                    onPressed: widget.expanded
                                        ? widget.onClose
                                        : widget.onOpen,
                                    color: Color.lerp(
                                      widget.onImage
                                          ? Colors.white
                                          : scheme.onSurfaceVariant,
                                      scheme.onSurfaceVariant,
                                      progress,
                                    ),
                                    icon: AnimatedSwitcher(
                                      duration:
                                          MediaQuery.disableAnimationsOf(
                                            context,
                                          )
                                          ? Duration.zero
                                          : AppMotion.short,
                                      child: Icon(
                                        widget.expanded
                                            ? Icons.close_rounded
                                            : Icons.search_rounded,
                                        key: ValueKey(widget.expanded),
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
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
