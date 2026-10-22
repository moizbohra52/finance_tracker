import 'dart:io';

import 'package:finance_tracker/core/translations/hindi.dart';
import 'package:finance_tracker/core/translations/hinglish.dart';
import 'package:finance_tracker/domain/entities/recurring_transaction.dart';
import 'package:finance_tracker/domain/entities/reminder.dart';
import 'package:finance_tracker/domain/entities/user_preferences.dart';
import 'package:finance_tracker/domain/services/reminder_calculator.dart';
import 'package:finance_tracker/domain/services/report_period.dart';
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
  // Part 3: accounts, categories, reports, budgets, recurring, reminders
  'lib/core/utils/recurring_labels.dart',
  'lib/core/widgets/category_breakdown.dart',
  'lib/core/widgets/charts.dart',
  'lib/core/widgets/date_filter_bar.dart',
  'lib/core/widgets/offline_widgets.dart',
  'lib/widgets/account_list_item.dart',
  'lib/features/accounts/views/account_detail_view.dart',
  'lib/features/accounts/views/account_form_view.dart',
  'lib/features/accounts/views/account_list_view.dart',
  'lib/features/budgets/views/budget_form_view.dart',
  'lib/features/budgets/views/budget_list_view.dart',
  'lib/features/categories/controller/category_controller.dart',
  'lib/features/categories/views/category_form_view.dart',
  'lib/features/categories/views/category_list_view.dart',
  'lib/features/recurring/views/recurring_form_view.dart',
  'lib/features/recurring/views/recurring_list_view.dart',
  'lib/features/reminders/controllers/reminder_controller.dart',
  'lib/features/reminders/views/reminder_detail_view.dart',
  'lib/features/reminders/views/reminder_form_view.dart',
  'lib/features/reminders/views/reminder_list_view.dart',
  'lib/features/reminders/widgets/reminder_visuals.dart',
  'lib/features/reports/views/reports_view.dart',
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
  r"""(?:\bText\(\s*|\b(?:title|subtitle|label|tooltip|message|hintText|labelText|helperText|semanticLabel|actionLabel|confirmLabel|cancelLabel|emptyMessage):\s*|AppSnackbar\.show\(\s*|\?\s*|\s:\s*|\breturn\s+|=>\s*)(?:'[^'\n]*[A-Za-z][^'\n]*'|"[^"\n]*[A-Za-z][^"\n]*")\s*[,):;]""",
);

/// Text assigned (`error = 'x'`), passed positionally (`Section('x', …)`),
/// or written as a list or record element. A map key (`'x':`) is not text.
final RegExp _positional = RegExp(
  r"""(?:(?<![=!<>])=\s*|(?<!RegExp)(?<!DateFormat)\(\s*|,\s*)(?:'[^'\n]*[A-Za-z][^'\n]*'|"[^"\n]*[A-Za-z][^"\n]*")\s*[,);]""",
);

/// Literals that are not translated on purpose.
const Set<String> _notText = <String>{
  "'Cr'", // Indian short units, written the same in Hindi and Hinglish
  "'L'",
  "'actionLabel and onAction must be provided together'", // an assert
};

String _unescape(String key) =>
    key.replaceAll(r"\'", "'").replaceAll(r'\"', '"').replaceAll(r'\$', r'$');

Map<String, String> _sources() => <String, String>{
  for (final String path in translatedFiles)
    path: File(path).readAsStringSync(),
};

void main() {
  test('validators get a translated field name', () {
    // The message is translated, so an English field name would mix the two.
    final RegExp call = RegExp(
      r"Validators\.(?:requiredField|name)\([^,()]+,\s*'[^']*'\s*\)",
    );
    final List<String> found = <String>[
      for (final FileSystemEntity f in Directory(
        'lib',
      ).listSync(recursive: true))
        if (f is File && f.path.endsWith('.dart'))
          for (final Match m in call.allMatches(f.readAsStringSync()))
            '${f.path}: ${m.group(0)}',
    ];
    expect(found, isEmpty);
  });

  test('every enum label shown on a screen is in both maps', () {
    // Shown with `label.tr`, so the key is a value the scan above cannot see.
    final List<String> labels = <String>[
      for (final RecurringFrequency f in RecurringFrequency.values) f.label,
      for (final ReminderType t in ReminderType.values) t.label,
      for (final ReminderRepeat r in ReminderRepeat.values) r.label,
      for (final ReminderStatus s in ReminderStatus.values) s.label,
      for (final SnoozeOption o in SnoozeOption.values) o.label,
      for (final DatePreset p in DatePreset.values) p.label,
      for (final WeekStart w in WeekStart.values) w.label,
      for (final CurrencyOption c in Currencies.supported) c.name,
    ];
    expect(
      labels.where(
        (String l) => !hindi.containsKey(l) || !hinglish.containsKey(l),
      ),
      isEmpty,
    );
  });

  test('every key used in translated screens is in both maps', () {
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

  test('translated screens have no untranslated text literal', () {
    // Text made only of values ('$message$note') has nothing to translate,
    // and a snake_case literal ('other_income') is a key, not text. Where
    // text is assigned or passed positionally, a lowercase literal with no
    // space ('receivable', 'contact-transaction:$id') is a stored value too.
    final RegExp values = RegExp(r'\$\{[^}]*\}|\$\w+');
    final RegExp snakeCase = RegExp(r'''^['"][a-z0-9]+(?:_[a-z0-9]+)+['"]''');
    final RegExp word = RegExp(r'''^['"][a-z][^\s'"]*['"]''');
    final RegExp comment = RegExp(r'(^|\s)//.*$', multiLine: true);
    bool isText(String match, RegExp key) {
      final String literal = match.replaceFirst(RegExp(r'^[^\x27"]*'), '');
      return !key.hasMatch(literal) &&
          !_notText.any(literal.startsWith) &&
          RegExp('[A-Za-z]').hasMatch(literal.replaceAll(values, ''));
    }

    final List<String> found = <String>[
      for (final MapEntry<String, String> file in _sources().entries)
        for (final (RegExp pattern, RegExp key) in <(RegExp, RegExp)>[
          (_plain, snakeCase),
          (_positional, word),
        ])
          for (final Match m in pattern.allMatches(
            file.value.replaceAll(comment, ''),
          ))
            if (isText(m.group(0)!, key)) '${file.key}: ${m.group(0)}',
    ];
    expect(found, isEmpty);
  });
}
