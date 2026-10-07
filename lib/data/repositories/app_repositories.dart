import 'package:finance_tracker/data/datasources/contact_datasource.dart';
import 'package:finance_tracker/data/repositories/account_repository.dart';
import 'package:finance_tracker/data/repositories/category_repository.dart';
import 'package:finance_tracker/data/repositories/contact_repository.dart';
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
  });

  factory AppRepositories.supabase(SupabaseClient client) => AppRepositories(
    accounts: AccountRepository(client),
    categories: CategoryRepository(client),
    transactions: TransactionRepository(client),
    contacts: ContactRepository(ContactDatasourceImpl(client)),
  );

  final AccountRepository accounts;
  final CategoryRepository categories;
  final TransactionRepository transactions;
  final ContactRepository contacts;
}
