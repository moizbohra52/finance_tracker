import 'dart:io';

import 'package:finance_tracker/core/translations/hindi.dart';
import 'package:finance_tracker/core/translations/hinglish.dart';
import 'package:flutter_test/flutter_test.dart';

/// Screens whose text is translated. Later parts add their files here.
const List<String> translatedFiles = <String>[
  'lib/core/widgets/app_bottom_navigation.dart',
  'lib/core/widgets/app_app_bar.dart',
  'lib/core/widgets/app_dialog.dart',
  'lib/features/notifications/widgets/notification_bell.dart',
  'lib/features/dashboard/views/app_shell_view.dart',
  'lib/features/dashboard/views/dashboard_view.dart',
  'lib/features/settings/views/settings_view.dart',
  'lib/features/settings/widgets/settings_widgets.dart',
  'lib/features/notifications/widgets/notification_settings_section.dart',
  'lib/features/app_lock/widgets/app_lock_tile.dart',
  'lib/features/auth/widgets/account_switcher_sheet.dart',
  'lib/features/auth/widgets/confirm_sign_out.dart',
];

/// A string literal (either quote) followed by `.tr` or `.trParams`.
final RegExp _key = RegExp(
  r"""(?:'((?:[^'\\\n]|\\.)*)'|"((?:[^"\\\n]|\\.)*)")\s*\.\s*tr(?:Params)?\b""",
);

/// A literal with `$` interpolation followed by `.tr`.
final RegExp _interpolated = RegExp(
  r"""(?:'[^'\n]*\$[^'\n]*'|"[^"\n]*\$[^"\n]*")\s*\.\s*tr\b""",
);

/// User-visible text passed as a plain literal (no `.tr` after it), directly
/// or as a branch of `? :` / `??`.
final RegExp _plain = RegExp(
  r"""(?:\bText\(\s*|\b(?:title|subtitle|label|tooltip|message|hintText|labelText|helperText|semanticLabel|actionLabel|confirmLabel|cancelLabel):\s*|AppSnackbar\.show\(\s*|\?\s*|\s:\s*)(?:'[^'\n]*[A-Za-z][^'\n]*'|"[^"\n]*[A-Za-z][^"\n]*")\s*[,):;]""",
);

String _unescape(String key) =>
    key.replaceAll(r"\'", "'").replaceAll(r'\"', '"').replaceAll(r'\$', r'$');

Map<String, String> _sources() => <String, String>{
  for (final String path in translatedFiles)
    path: File(path).readAsStringSync(),
};

void main() {
  test('every key used in part 1 screens is in both maps', () {
    final List<String> missing = <String>[
      for (final MapEntry<String, String> file in _sources().entries)
        for (final Match m in _key.allMatches(file.value))
          if (!hindi.containsKey(_unescape(m.group(1) ?? m.group(2)!)) ||
              !hinglish.containsKey(_unescape(m.group(1) ?? m.group(2)!)))
            '${file.key}: ${m.group(1) ?? m.group(2)}',
    ];
    expect(missing, isEmpty);
  });

  test('no interpolated string is translated with .tr', () {
    final List<String> found = <String>[
      for (final MapEntry<String, String> file in _sources().entries)
        for (final Match m in _interpolated.allMatches(file.value))
          '${file.key}: ${m.group(0)}',
    ];
    expect(found, isEmpty);
  });

  test('part 1 screens have no untranslated text literal', () {
    // Text made only of values ('$message$note') has nothing to translate.
    final RegExp values = RegExp(r'\$\{[^}]*\}|\$\w+');
    final List<String> found = <String>[
      for (final MapEntry<String, String> file in _sources().entries)
        for (final Match m in _plain.allMatches(file.value))
          if (RegExp('[A-Za-z]').hasMatch(
            m
                .group(0)!
                .replaceFirst(RegExp(r'^[^\x27"]*'), '')
                .replaceAll(values, ''),
          ))
            '${file.key}: ${m.group(0)}',
    ];
    expect(found, isEmpty);
  });
}
