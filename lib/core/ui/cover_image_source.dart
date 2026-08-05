class CoverImageSource {
  const CoverImageSource._();

  static String? normalizeUrl(String? raw, {int? size}) {
    if (raw == null) return null;
    var url = raw.trim();
    if (url.isEmpty) return url;

    final candidate = url.startsWith('//') ? 'http:$url' : url;
    final host = Uri.tryParse(candidate)?.host.toLowerCase() ?? '';
    final keepHttp = host == 'kwcdn.kuwo.cn' || host.endsWith('.kwcdn.kuwo.cn');
    if (url.startsWith('//')) {
      url = '${keepHttp ? 'http' : 'https'}:$url';
    } else if (url.startsWith('http://') && !keepHttp) {
      url = url.replaceFirst('http://', 'https://');
    }
    if (size != null &&
        url.contains('music.126.net') &&
        !url.contains('param=')) {
      final sep = url.contains('?') ? '&' : '?';
      url = '$url${sep}param=${size}y$size';
    }
    return url;
  }

  static Map<String, String>? headersFor(String? url) {
    if (url == null || !url.contains('music.126.net')) return null;
    return const {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Referer': 'https://music.163.com/',
    };
  }
}
