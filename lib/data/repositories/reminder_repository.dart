import 'package:finance_tracker/core/errors/supabase_error_mapper.dart';
import 'package:finance_tracker/data/models/reminder.dart';
import 'package:finance_tracker/data/repositories/payloads.dart';
import 'package:finance_tracker/domain/entities/reminder.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReminderRepository {
  ReminderRepository(this._supabaseClient);

  final SupabaseClient _supabaseClient;

  /// Every live reminder, soonest first. The list is small and the device
  /// needs all of it to schedule notifications, so it is not paged.
  Future<List<Reminder>> getAll() => guardSupabase(() async {
    final List<Map<String, dynamic>> data = await _supabaseClient
        .from('reminders')
        .select()
        .isFilter('deleted_at', null)
        .order('remind_at');
    return data.map(ReminderModel.fromJson).toList();
  });

  /// Upserts on the client-generated id, so a retried create never duplicates.
  Future<void> create(Reminder reminder) => guardSupabase(() async {
    await _supabaseClient
        .from('reminders')
        .upsert(insertPayload(_supabaseClient, ReminderModel.toJson(reminder)));
  });

  /// Edit, complete, snooze and enable/disable all go through here.
  Future<void> update(Reminder reminder) => guardSupabase(() async {
    await _supabaseClient
        .from('reminders')
        .update(updatePayload(ReminderModel.toJson(reminder)))
        .eq('id', reminder.id);
  });

  Future<void> delete(String id) => guardSupabase(() async {
    await _supabaseClient.from('reminders').update(tombstone()).eq('id', id);
  });
}
