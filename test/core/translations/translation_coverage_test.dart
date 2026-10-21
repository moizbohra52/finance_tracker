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
  // Part 2: transactions and khata
  'lib/core/utils/category_icons.dart',
  'lib/core/utils/validators.dart',
  'lib/core/widgets/app_bottom_sheet_dropdown.dart',
  'lib/core/widgets/app_pickers.dart',
  'lib/core/widgets/app_text_field.dart',
  'lib/core/widgets/finance_widgets.dart',
  'lib/core/widgets/state_views.dart',
  'lib/widgets/category_picker.dart',
  'lib/widgets/contact_list_item.dart',
  'lib/widgets/transaction_list_item.dart',
  'lib/features/contacts/controller/contact_detail_controller.dart',
  'lib/features/contacts/controller/contact_form_controller.dart',
  'lib/features/contacts/services/device_contacts_service.dart',
  'lib/features/contacts/views/contact_detail_view.dart',
  'lib/features/contacts/views/contact_entry_view.dart',
  'lib/features/contacts/views/contact_form_view.dart',
  'lib/features/contacts/views/contact_list_view.dart',
  'lib/features/contacts/views/contact_picker_sheet.dart',
  'lib/features/contacts/views/device_contact_picker_sheet.dart',
  'lib/features/contacts/views/send_reminder_sheet.dart',
  'lib/features/transactions/controller/calendar_controller.dart',
  'lib/features/transactions/controller/transaction_controller.dart',
  'lib/features/transactions/views/calendar_view.dart',
  'lib/features/transactions/views/transaction_detail_view.dart',
  'lib/features/transactions/views/transaction_filter_sheet.dart',
  'lib/features/transactions/views/transaction_form_view.dart',
  'lib/features/transactions/views/transaction_list_view.dart',
  'lib/features/transactions/views/transfer_form_view.dart',
  'lib/features/transactions/widgets/receipt_field.dart',
  'lib/features/transactions/widgets/receipt_preview.dart',
];

/// A string literal (either quote) followed by `.tr` or `.trParams`.
final RegExp _key = RegExp(
  r"""(?:'((?:[^'\\\n]|\\.)*)'|"((?:[^"\\\n]|\\.)*)")\s*\.\s*tr(?:Params)?\b""",
);

/// A literal with `$` interpolation followed by `.tr` or `.trParams`.
final RegExp _interpolated = RegExp(
  r"""(?:'[^'\n]*\$[^'\n]*'|"[^"\n]*\$[^"\n]*")\s*\.\s*tr(?:Params)?\b""",
);

/// User-visible text passed as a plain literal (no `.tr` after it), directly,
/// as a branch of `? :` / `??`, returned, or as a switch arm.
final RegExp _plain = RegExp(
  r"""(?:\bText\(\s*|\b(?:title|subtitle|label|tooltip|message|hintText|labelText|helperText|semanticLabel|actionLabel|confirmLabel|cancelLabel):\s*|AppSnackbar\.show\(\s*|\?\s*|\s:\s*|\breturn\s+|=>\s*)(?:'[^'\n]*[A-Za-z][^'\n]*'|"[^"\n]*[A-Za-z][^"\n]*")\s*[,):;]""",
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
