import 'package:finance_tracker/domain/entities/reminder.dart';
import 'package:flutter/material.dart';

/// Icon for each reminder type.
IconData reminderIcon(ReminderType type) => switch (type) {
  ReminderType.payment => Icons.payments_outlined,
  ReminderType.receivable => Icons.call_received_rounded,
  ReminderType.payable => Icons.call_made_rounded,
  ReminderType.khata => Icons.menu_book_outlined,
  ReminderType.recurring => Icons.event_repeat_outlined,
  ReminderType.custom => Icons.notifications_active_outlined,
};

/// Colour of a status label: overdue stands out, the rest stay quiet.
Color reminderStatusColor(ColorScheme colors, ReminderStatus status) =>
    switch (status) {
      ReminderStatus.overdue => colors.error,
      ReminderStatus.upcoming => colors.primary,
      ReminderStatus.snoozed => colors.tertiary,
      ReminderStatus.completed => colors.onSurfaceVariant,
    };
