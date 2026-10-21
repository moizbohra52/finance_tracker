import 'package:finance_tracker/domain/entities/recurring_transaction.dart';
import 'package:get/get.dart';

/// Presentation helpers for [RecurringFrequency], in the app language.
extension RecurringFrequencyLabel on RecurringFrequency {
  /// Plural unit, for "every 2 weeks".
  String get units => switch (this) {
    RecurringFrequency.daily => 'days'.tr,
    RecurringFrequency.weekly => 'weeks'.tr,
    RecurringFrequency.monthly => 'months'.tr,
    RecurringFrequency.yearly => 'years'.tr,
  };
}

/// Presentation helpers for [RecurringTransaction], in the app language.
extension RecurringScheduleLabel on RecurringTransaction {
  /// "Daily", "Weekly", or "Every 2 weeks".
  String get scheduleLabel => intervalCount == 1
      ? frequency.label.tr
      : 'Every @count @units'.trParams(<String, String>{
          'count': '$intervalCount',
          'units': frequency.units,
        });
}
