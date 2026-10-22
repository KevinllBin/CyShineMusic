import 'dart:convert';

import '../internal/format.dart';
import '../internal/sdk_http.dart';

int catalogInt(Object? value) => int.tryParse('$value') ?? 0;
String catalogText(Object? value) =>
    decodeName(value).replaceAll(RegExp(r'<[^>]*>'), '').trim();
Map catalogMap(Object? value) => value is Map ? value : const {};
List<Map> catalogMaps(Object? value) =>
    value is List ? value.whereType<Map>().toList() : const [];

String? catalogImage(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  if (text.startsWith('//')) return 'https:$text';
  return text.startsWith('http://')
      ? text.replaceFirst('http://', 'https://')
      : text;
}

Future<Map> catalogJson(
  String url, {
  SdkJsonLoader? loader,
  Map<String, String>? headers,
}) async {
  var body = await (loader ?? SdkHttp.getJson)(url, headers: headers);
  if (body is String) {
    try {
      body = jsonDecode(body);
    } catch (_) {
      throw const FormatException('平台返回了无法识别的数据，请稍后重试');
    }
  }
  if (body is! Map) throw const FormatException('平台返回了无法识别的数据，请稍后重试');
  return body;
}

String catalogDate(Object? value) {
  final millis = catalogInt(value);
  if (millis <= 0) return '';
  final date = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
