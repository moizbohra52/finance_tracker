import 'package:finance_tracker/core/translations/hindi.dart';
import 'package:finance_tracker/core/translations/hinglish.dart';
import 'package:flutter_test/flutter_test.dart';

final RegExp _param = RegExp(r'@\w+');

Set<String> _params(String text) =>
    _param.allMatches(text).map((Match m) => m.group(0)!).toSet();

void main() {
  test('both maps have the same keys and no empty text', () {
    expect(hindi.keys.toSet(), hinglish.keys.toSet());
    expect(hindi.values.where((String v) => v.trim().isEmpty), isEmpty);
    expect(hinglish.values.where((String v) => v.trim().isEmpty), isEmpty);
  });

  test('every @param of a key is kept in its translations', () {
    final List<String> broken = <String>[
      for (final String key in hindi.keys)
        if (!_params(hindi[key]!).containsAll(_params(key)) ||
            !_params(hinglish[key] ?? '').containsAll(_params(key)))
          key,
    ];
    expect(broken, isEmpty);
  });
}
