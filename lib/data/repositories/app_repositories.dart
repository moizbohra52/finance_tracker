import 'package:finance_tracker/core/services/sync_engine.dart';
import 'package:finance_tracker/data/datasources/contact_datasource.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:finance_tracker/data/repositories/account_repository.dart';
import 'package:finance_tracker/data/repositories/budget_repository.dart';
import 'package:finance_tracker/data/repositories/category_repository.dart';
import 'package:finance_tracker/data/repositories/contact_repository.dart';
import 'package:finance_tracker/data/repositories/notification_repository.dart';
import 'package:finance_tracker/data/repositories/recurring_repository.dart';
import 'package:finance_tracker/data/repositories/reminder_repository.dart';
import 'package:finance_tracker/data/repositories/transaction_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The finance repositories, created once at startup and injected so tests
/// can supply in-memory fakes instead of a Supabase client.
class AppRepositories {
  const AppRepositories({
    required this.accounts,
    required this.categories,
    required this.transactions,
    required this.contacts,
    required this.budgets,
    required this.recurring,
    required this.notifications,
    required this.reminders,
  });

  factory AppRepositories.supabase(
    SupabaseClient client, {
    AppDatabase? database,
    SyncEngine? syncEngine,
  }) => AppRepositories(
    accounts: AccountRepository(
      client,
      database: database,
      syncEngine: syncEngine,
    ),
    categories: CategoryRepository(
      client,
      database: database,
      syncEngine: syncEngine,
    ),
    transactions: TransactionRepository(
      client,
      database: database,
      syncEngine: syncEngine,
    ),
    contacts: ContactRepository(
      database != null
          ? ContactLocalDatasourceImpl(database, syncEngine)
          : ContactDatasourceImpl(client),
    ),
    budgets: BudgetRepository(
      client,
      database: database,
      syncEngine: syncEngine,
    ),
    recurring: RecurringRepository(
      client,
      database: database,
      syncEngine: syncEngine,
    ),
    notifications: NotificationRepository(client),
    reminders: ReminderRepository(
      client,
      database: database,
      syncEngine: syncEngine,
    ),
  );

  final AccountRepository accounts;
  final CategoryRepository categories;
  final TransactionRepository transactions;
  final ContactRepository contacts;
  final BudgetRepository budgets;
  final RecurringRepository recurring;
  final NotificationRepository notifications;
  final ReminderRepository reminders;
}
