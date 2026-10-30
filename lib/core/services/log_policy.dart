/// Keep the default journal readable while preserving bounded diagnostic data.
String compactLogMessage(String message, {int maxLength = 1200}) {
  var text = message.replaceAll(RegExp(r'[\r\n\t]+'), ' ');
  text = text.replaceAllMapped(RegExp(r'https?://[^\s"<>]+'), (match) {
    final uri = Uri.tryParse(match[0]!);
    if (uri == null) return '[url]';
    return '${uri.scheme}://${uri.host}${uri.path}${uri.hasQuery ? '?[redacted]' : ''}';
  });
  text = text.replaceAllMapped(
    RegExp(
      r'(authorization|api[_-]?key|access[_-]?token|password)([":=\s]+)[^,;\s}]+',
      caseSensitive: false,
    ),
    (match) => '${match[1]}${match[2]}[redacted]',
  );
  return text.length <= maxLength
      ? text
      : '${text.substring(0, maxLength)}…[truncated]';
}

/// Collapse repeat messages, and bound noisy script logging per ten seconds.
class LogPolicy {
  final _recent = <String, ({String message, DateTime at, int skipped})>{};
  final _budgets = <String, ({DateTime at, int count, int skipped})>{};

  List<String> accept(String scope, String message, DateTime now) {
    final output = <String>[];
    final previous = _recent[scope];
    if (previous != null &&
        previous.message == message &&
        now.difference(previous.at) < const Duration(seconds: 10)) {
      _recent[scope] = (
        message: message,
        at: previous.at,
        skipped: previous.skipped + 1,
      );
      return output;
    }
    if (previous != null && previous.skipped > 0) {
      output.add('repeated=${previous.skipped} previous=${previous.message}');
    }
    _recent[scope] = (message: message, at: now, skipped: 0);
    if (_recent.length > 128) _recent.remove(_recent.keys.first);
    if (scope == 'music-source' &&
        !RegExp(
          r'error|fail|exception|错误|失败',
          caseSensitive: false,
        ).hasMatch(message)) {
      var budget = _budgets[scope];
      if (budget == null ||
          now.difference(budget.at) >= const Duration(seconds: 10)) {
        if (budget != null && budget.skipped > 0) {
          output.add('script_lines_omitted=${budget.skipped}');
        }
        budget = (at: now, count: 0, skipped: 0);
      }
      if (budget.count >= 5) {
        _budgets[scope] = (
          at: budget.at,
          count: budget.count,
          skipped: budget.skipped + 1,
        );
        return output;
      }
      _budgets[scope] = (
        at: budget.at,
        count: budget.count + 1,
        skipped: budget.skipped,
      );
    }
    output.add(message);
    return output;
  }

  Map<String, String> drain() {
    final output = <String, String>{};
    for (final entry in _recent.entries.toList()) {
      final value = entry.value;
      if (value.skipped > 0) {
        output[entry.key] =
            'repeated=${value.skipped} previous=${value.message}';
        _recent[entry.key] = (message: value.message, at: value.at, skipped: 0);
      }
    }
    for (final entry in _budgets.entries.toList()) {
      final value = entry.value;
      if (value.skipped > 0) {
        output[entry.key] =
            '${output[entry.key] ?? ''} script_lines_omitted=${value.skipped}'
                .trim();
        _budgets[entry.key] = (at: value.at, count: value.count, skipped: 0);
      }
    }
    return output;
  }

  void clear() {
    _recent.clear();
    _budgets.clear();
  }
}
