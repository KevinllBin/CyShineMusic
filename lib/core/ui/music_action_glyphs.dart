import 'package:prism_ui/icons/icons.dart';

/// Music glyphs on Prism's 24dp grid. Actions use rounded 1.8dp strokes;
/// navigation keeps fixed-width contours even under filled button themes.
abstract final class MusicActionGlyphs {
  /// 歌曲库导航：两层短线、圆角唱片套和上挑的单音符。
  /// 用填充路径绘制 1.6dp 细轮廓，避免导航的 fill=1 把线条加粗。
  static const musicLibrary = Glyph([
    GlyphPath(
      'M8.2 1.7H15.8A0.8 0.8 0 0 1 15.8 3.3H8.2A0.8 0.8 0 0 1 8.2 1.7Z'
      'M6.2 4.7H17.8A0.8 0.8 0 0 1 17.8 6.3H6.2A0.8 0.8 0 0 1 6.2 4.7Z',
      solid: true,
    ),
    GlyphPath(
      'M7 7.7H17C19.1 7.7 20.8 9.4 20.8 11.5V18.5'
      'C20.8 20.6 19.1 22.3 17 22.3H7C4.9 22.3 3.2 20.6 3.2 18.5V11.5'
      'C3.2 9.4 4.9 7.7 7 7.7Z'
      'M7 9.3C5.78 9.3 4.8 10.28 4.8 11.5V18.5'
      'C4.8 19.72 5.78 20.7 7 20.7H17C18.22 20.7 19.2 19.72 19.2 18.5V11.5'
      'C19.2 10.28 18.22 9.3 17 9.3H7Z',
      solid: true,
    ),
    GlyphPath(
      'M12.2 17V12.5C12.2 12.14 12.44 11.82 12.78 11.73L15.58 10.93'
      'C16.01 10.81 16.45 11.06 16.57 11.48C16.69 11.91 16.44 12.35 16.02 12.47'
      'L13.8 13.1V17C13.8 17.44 13.44 17.8 13 17.8C12.56 17.8 12.2 17.44 12.2 17Z',
      solid: true,
    ),
    GlyphPath(
      'M13.8 16.9C13.8 18.15 12.45 19.1 10.95 19.1'
      'C9.75 19.1 8.95 18.5 8.95 17.55'
      'C8.95 16.35 10.2 15.45 11.65 15.45C12.9 15.45 13.8 16 13.8 16.9Z',
      solid: true,
    ),
  ]);

  /// 添加到歌单.
  static const playlistAdd = Glyph([
    GlyphPath(
      'M3.5 5H14 M3.5 10.5H12 M3.5 16H9 M17.5 12.5V20.5 M13.5 16.5H21.5',
      role: GlyphRole.line,
    ),
  ]);

  /// 下一首播放.
  static const playNext = Glyph([
    GlyphPath(
      'M3.5 5H19.5 M3.5 10.5H10 M3.5 16H10 M14 10.5L20 15L14 19.5Z M21.5 10.5V19.5',
      role: GlyphRole.line,
    ),
  ]);

  /// 移出歌单.
  static const playlistRemove = Glyph([
    GlyphPath(
      'M3.5 5H19.5 M3.5 10.5H12 M3.5 16H9 M13.5 16.5H21.5',
      role: GlyphRole.line,
    ),
  ]);

  /// 删除.
  static const trash = Glyph([
    GlyphPath(
      'M9 6V3.5H15V6 M4.5 6.5H19.5 M6.5 6.5L7.4 18.8C7.5 19.8 8.1 20.5 9.2 20.5H14.8C15.9 20.5 16.5 19.8 16.6 18.8L17.5 6.5 M10 10.5V16.5 M14 10.5V16.5',
      role: GlyphRole.line,
    ),
  ]);

  /// 下载.
  static const download = Glyph([
    GlyphPath(
      'M12 3.5V14.5 M7.5 10L12 14.5L16.5 10 M4.5 15.5V18.5C4.5 19.6 5.4 20.5 6.5 20.5H17.5C18.6 20.5 19.5 19.6 19.5 18.5V15.5',
      role: GlyphRole.line,
    ),
  ]);

  /// 已下载.
  static const downloaded = Glyph([
    GlyphPath(
      'M7.5 8.5L10.5 11.5L16.5 5 M4.5 15.5V18.5C4.5 19.6 5.4 20.5 6.5 20.5H17.5C18.6 20.5 19.5 19.6 19.5 18.5V15.5',
      role: GlyphRole.line,
    ),
  ]);

  /// 播放音质.
  static const quality = Glyph([
    GlyphPath(
      'M5 7V17 M9.5 4V20 M14 8.5V15.5 M18.5 5.5V18.5',
      role: GlyphRole.line,
    ),
  ]);

  /// 迷你歌词.
  static const lyrics = Glyph([
    GlyphPath(
      'M6 4H18C19.1 4 20 4.9 20 6V18C20 19.1 19.1 20 18 20H6C4.9 20 4 19.1 4 18V6C4 4.9 4.9 4 6 4Z M8 8H16 M8 12H16 M8 16H12',
      role: GlyphRole.line,
    ),
  ]);
}
