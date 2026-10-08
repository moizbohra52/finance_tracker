import 'package:flutter/foundation.dart';

/// The editable preference columns of public.user_settings. Values are raw
/// database strings; mapping them to domain enums happens in SettingsController.
@immutable
class UserSettings {
  const UserSettings({
    required this.dateFormat,
    required this.numberFormat,
    required this.firstDayOfWeek,
    required this.languageCode,
    required this.defaultAccountId,
  });

  factory UserSettings.fromJson(Map<String, dynamic> json) => UserSettings(
    dateFormat: json['date_format'] as String?,
    numberFormat: json['number_format'] as String?,
    firstDayOfWeek: json['first_day_of_week'] as String?,
    languageCode: json['language_code'] as String?,
    defaultAccountId: json['default_account_id'] as String?,
  );

  /// Columns read by [UserSettings.fromJson].
  static const String columns =
      'date_format, number_format, first_day_of_week, language_code, '
      'default_account_id';

  final String? dateFormat;
  final String? numberFormat;
  final String? firstDayOfWeek;
  final String? languageCode;
  final String? defaultAccountId;

  /// The values written on save. Every editable column is sent, so clearing
  /// the default account is an explicit null, not a missing field.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'date_format': dateFormat,
    'number_format': numberFormat,
    'first_day_of_week': firstDayOfWeek,
    'language_code': languageCode,
    'default_account_id': defaultAccountId,
  };
}
