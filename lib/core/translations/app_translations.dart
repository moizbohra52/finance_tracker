import 'package:finance_tracker/core/translations/hindi.dart';
import 'package:finance_tracker/core/translations/hinglish.dart';
import 'package:get/get.dart';

/// The app's text in Hindi and Hinglish. English needs no map: the English
/// text is the key (`'Settings'.tr`), and a key with no entry shows as is.
/// Keys are matched by locale, see AppLanguage.locale.
class AppTranslations extends Translations {
  @override
  Map<String, Map<String, String>> get keys => <String, Map<String, String>>{
    'hi_IN': hindi,
    'hi_Latn': hinglish,
  };
}
