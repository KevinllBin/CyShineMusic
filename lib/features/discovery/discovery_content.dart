import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/music_api.dart';
import '../../core/models/enums.dart';
import '../../core/models/playlist_summary.dart';
import '../../core/ui/app_refresh_indicator.dart';
import '../../theme/app_motion.dart';
import 'discovery_controller.dart';
import 'widgets/discovery_helpers.dart';
import 'widgets/discovery_placeholders.dart';
import 'widgets/discovery_source_selector.dart';
import 'widgets/leaderboard_spotlight.dart';
import 'widgets/masonry_playlist_grid.dart';

class DiscoveryContent extends ConsumerStatefulWidget {
  const DiscoveryContent({super.key});

  @override
  ConsumerState<DiscoveryContent> createState() => _DiscoveryContentState();
}

class _DiscoveryContentState extends ConsumerState<DiscoveryContent> {
  late final PageController _pageController;

  /// 抑制 onPageChanged → provider → animateToPage 的回环。
  bool _syncingFromPager = false;

  @override
  void initState() {
    super.initState();
    final source = ref.read(selectedDiscoverySourceProvider);
    _pageController = PageController(
      initialPage: math.max(0, kDiscoverySources.indexOf(source)),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _handlePageChanged(int index) {
    _syncingFromPager = true;
    ref.read(selectedDiscoverySourceProvider.notifier).state =
        kDiscoverySources[index];
    _syncingFromPager = false;
  }

  void _animateToSource(MusicSource source) {
    final index = kDiscoverySources.indexOf(source);
    if (index < 0 || !_pageController.hasClients) return;
    final current =
        _pageController.page?.round() ?? _pageController.initialPage;
    if (current == index) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _pageController.jumpToPage(index);
    } else {
      _pageController.animateToPage(
        index,
        duration: AppMotion.medium,
        curve: AppMotion.emphasized,
      );
    }
  }

  Widget _buildSourcePage(BuildContext context, int index) {
    final source = kDiscoverySources[index];
    return Consumer(
      builder: (context, ref, _) {
        final categoryId = ref.watch(selectedDiscoveryCategoryProvider(source));
        // 页面骨架常驻：切换歌单分类只让「精选歌单」区块进入加载态，
        // 上方的官方排行榜不随之卸载重建。
        return _DiscoveryList(
          source: source,
          featured: ref.watch(featuredPlaylistsProvider(source)),
          onRefresh: () async {
            ref.invalidate(featuredPlaylistsProvider(source));
            ref.invalidate(leaderboardBoardsProvider(source));
            await Future.wait([
              ref.read(featuredPlaylistsProvider(source).future),
              ref.read(leaderboardBoardsProvider(source).future),
            ]);
          },
          onRetry: () => ref.invalidate(featuredPlaylistsProvider(source)),
          onLoadMore: (page) => ref
              .read(musicApiProvider)
              .featuredPlaylists(
                source: source,
                page: page,
                limit: discoveryPlaylistPageSize,
                categoryId: categoryId,
              ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 点击音源标签等外部写入 provider 时，让 pager 跟着动画过去。
    ref.listen<MusicSource>(selectedDiscoverySourceProvider, (previous, next) {
      if (_syncingFromPager || previous == next) return;
      _animateToSource(next);
    });
    return Column(
      children: [
        DiscoverySourceSelector(pageController: _pageController),
        const SizedBox(height: 6),
        Expanded(
          child: PageView.builder(
            key: const PageStorageKey('discovery-source-pager'),
            controller: _pageController,
            physics: const BouncingScrollPhysics(),
            onPageChanged: _handlePageChanged,
            itemCount: kDiscoverySources.length,
            itemBuilder: _buildSourcePage,
          ),
        ),
      ],
    );
  }
}

class _DiscoveryList extends StatefulWidget {
  const _DiscoveryList({
    required this.source,
    required this.featured,
    required this.onRefresh,
    required this.onRetry,
    required this.onLoadMore,
  });

  final MusicSource source;

  /// 当前分类的首页数据；loading / error 只影响歌单区块。
  final AsyncValue<List<PlaylistSummary>> featured;
  final Future<void> Function() onRefresh;
  final VoidCallback onRetry;
  final Future<List<PlaylistSummary>> Function(int page) onLoadMore;

  @override
  State<_DiscoveryList> createState() => _DiscoveryListState();
}

class _DiscoveryListState extends State<_DiscoveryList> {
  final ScrollController _scrollController = ScrollController();
  late List<PlaylistSummary> _items;
  var _nextPage = 2;
  var _loadingMore = false;
  var _hasMore = true;
  Object? _loadMoreError;

  /// 只认已到达的数据；分类切换期间 provider 处于 loading，此时不分页。
  List<PlaylistSummary>? get _loadedItems =>
      widget.featured.isLoading ? null : widget.featured.asData?.value;

  @override
  void initState() {
    super.initState();
    _reset(_loadedItems);
    _scrollController.addListener(_maybeLoadMore);
    _scheduleFillViewport();
  }

  @override
  void didUpdateWidget(covariant _DiscoveryList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldItems = oldWidget.featured.isLoading
        ? null
        : oldWidget.featured.asData?.value;
    if (oldWidget.source != widget.source ||
        !identical(oldItems, _loadedItems)) {
      _reset(_loadedItems);
      _scheduleFillViewport();
    }
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_maybeLoadMore)
      ..dispose();
    super.dispose();
  }

  void _reset(List<PlaylistSummary>? items) {
    _items = List<PlaylistSummary>.from(items ?? const <PlaylistSummary>[]);
    _nextPage = 2;
    _loadingMore = false;
    _hasMore = items != null && items.isNotEmpty;
    _loadMoreError = null;
  }

  void _scheduleFillViewport() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadMore());
  }

  void _maybeLoadMore() {
    if (!mounted ||
        !_scrollController.hasClients ||
        _scrollController.position.extentAfter > 600) {
      return;
    }
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() {
      _loadingMore = true;
      _loadMoreError = null;
    });
    try {
      final page = await widget.onLoadMore(_nextPage);
      if (!mounted) return;
      final seen = _items.map((item) => item.key).toSet();
      final additions = [
        for (final item in page)
          if (seen.add(item.key)) item,
      ];
      setState(() {
        _items.addAll(additions);
        _nextPage++;
        _hasMore = page.isNotEmpty && additions.isNotEmpty;
      });
      if (_hasMore) _scheduleFillViewport();
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadMoreError = error);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// 「精选歌单」区块：加载 / 错误 / 空 / 网格。只有这一块随分类切换变化。
  List<Widget> _buildFeaturedSection() {
    final loaded = _loadedItems;
    if (loaded == null) {
      return [
        widget.featured.hasError && !widget.featured.isLoading
            ? DiscoverySectionError(
                message: discoveryFriendlyError(widget.featured.error!),
                onRetry: widget.onRetry,
              )
            : const DiscoverySectionLoading(),
      ];
    }
    if (_items.isEmpty) return const [DiscoverySectionEmpty()];
    return [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: MasonryPlaylistGrid(items: _items),
        ),
      ),
      if (_loadingMore)
        const Padding(
          padding: EdgeInsets.only(top: 18),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (_loadMoreError != null)
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Center(
            child: IconButton.filledTonal(
              tooltip: '重新加载',
              onPressed: _loadMore,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return AppRefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        key: PageStorageKey('discovery-${widget.source.code}-scroll'),
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 156),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: LeaderboardSpotlight(source: widget.source),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
                  child: Text(
                    '精选歌单',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
          ..._buildFeaturedSection(),
        ],
      ),
    );
  }
}
