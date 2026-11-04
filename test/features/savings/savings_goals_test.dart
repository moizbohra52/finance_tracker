import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/constants/app_constants.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/services/sync_engine.dart';
import 'package:finance_tracker/core/theme/app_theme.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:finance_tracker/data/models/savings_goal.dart';
import 'package:finance_tracker/data/models/sync_queue_item.dart';
import 'package:finance_tracker/data/repositories/savings_goal_repository.dart';
import 'package:finance_tracker/domain/entities/savings_contribution.dart';
import 'package:finance_tracker/domain/entities/savings_goal.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/features/savings/controllers/savings_goal_controller.dart';
import 'package:finance_tracker/features/savings/controllers/savings_goal_detail_controller.dart';
import 'package:finance_tracker/features/savings/views/savings_goal_detail_view.dart';
import 'package:finance_tracker/features/savings/views/savings_goal_form_view.dart';
import 'package:finance_tracker/features/savings/views/savings_goal_list_view.dart';
import 'package:finance_tracker/features/savings/widgets/add_money_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/fake_finance.dart';

SavingsGoal goal({
  String id = 'g1',
  String target = '1000',
  String saved = '250',
  String contributed = '0',
  DateTime? targetDate,
}) => SavingsGoal(
  id: id,
  userId: 'u',
  name: 'New phone',
  targetAmount: Decimal.parse(target),
  savedAmount: Decimal.parse(saved),
  contributedAmount: Decimal.parse(contributed),
  targetDate: targetDate,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('progress', () {
    test('remaining and progress use exact decimals', () {
      final SavingsGoal g = goal(target: '0.30', saved: '0.10');
      expect(g.remaining, Decimal.parse('0.2'));
      expect(g.progress, closeTo(0.3333, 0.0001));
      expect(g.isReached, isFalse);
    });

    test('saving more than the target is reached, capped at 100%', () {
      final SavingsGoal g = goal(saved: '1200');
      expect(g.isReached, isTrue);
      expect(g.remaining, Decimal.zero);
      expect(g.progress, 1);
    });

    test('overdue only after the target day, and never once reached', () {
      final DateTime day = DateTime(2026, 10, 23);
      expect(
        goal(targetDate: day).isOverdue(DateTime(2026, 10, 23, 23)),
        isFalse,
      );
      expect(goal(targetDate: day).isOverdue(DateTime(2026, 10, 24)), isTrue);
      expect(
        goal(targetDate: day, saved: '1000').isOverdue(DateTime(2026, 11)),
        isFalse,
      );
      expect(goal().isOverdue(DateTime(2100)), isFalse);
    });

    test('contributions count toward progress, remaining and reached', () {
      final SavingsGoal g = goal(
        saved: '250',
        contributed: '750',
        targetDate: DateTime(2026, 10, 23),
      );
      expect(g.totalSaved, Decimal.parse('1000'));
      expect(g.isReached, isTrue);
      expect(g.remaining, Decimal.zero);
      expect(g.progress, 1);
      expect(g.isOverdue(DateTime(2100)), isFalse);
    });

    test('fromJson reads contributed_amount, null or absent means zero', () {
      Map<String, dynamic> row(Object? contributed, {bool withKey = true}) =>
          <String, dynamic>{
            'id': 'g1',
            'user_id': 'u',
            'name': 'New phone',
            'target_amount': '1000',
            'saved_amount': '250',
            if (withKey) 'contributed_amount': contributed,
            'target_date': null,
            'created_at': '2026-01-01T00:00:00Z',
            'updated_at': '2026-01-01T00:00:00Z',
            'deleted_at': null,
          };
      expect(
        SavingsGoalModel.fromJson(row('750.50')).contributedAmount,
        Decimal.parse('750.5'),
      );
      expect(
        SavingsGoalModel.fromJson(row(750)).contributedAmount,
        Decimal.parse('750'),
      );
      expect(
        SavingsGoalModel.fromJson(row(null)).contributedAmount,
        Decimal.zero,
      );
      expect(
        SavingsGoalModel.fromJson(row(null, withKey: false)).contributedAmount,
        Decimal.zero,
      );
    });
  });

  group('controller', () {
    SavingsGoalController controller(FakeFinance f) => SavingsGoalController(
      f.repositories.savingsGoals,
      DataChangeNotifier(),
    );

    test('adds, edits in place and deletes', () async {
      final FakeFinance f = FakeFinance();
      final SavingsGoalController c = controller(f);
      final String id = SavingsGoalController.newId();

      expect(
        await c.saveGoal(
          id: id,
          name: '  Trip ',
          targetAmount: Decimal.parse('5000'),
          savedAmount: Decimal.zero,
          targetDate: null,
        ),
        isTrue,
      );
      await c.load();
      expect(c.goals.single.name, 'Trip');

      expect(
        await c.saveGoal(
          id: id,
          existing: c.goals.single,
          name: 'Trip',
          targetAmount: Decimal.parse('5000'),
          savedAmount: Decimal.parse('1500'),
          targetDate: DateTime(2027, 3),
        ),
        isTrue,
      );
      await c.load();
      expect(f.savingsGoals, hasLength(1));
      expect(c.goals.single.savedAmount, Decimal.parse('1500'));
      expect(c.goals.single.createdAt, f.savingsGoals.single.createdAt);

      expect(await c.deleteGoal(id), isTrue);
      await c.load();
      expect(c.goals, isEmpty);
    });

    test(
      'adding money is a dated history entry; the starting amount stays',
      () async {
        final FakeFinance f = FakeFinance()
          ..savingsGoals.add(goal(targetDate: DateTime(2027)));
        final SavingsGoalController c = controller(f);
        await c.load();

        // The same sheet id twice (a retried save) adds once.
        for (int i = 0; i < 2; i++) {
          expect(
            await c.addMoney(
              id: 'add-1',
              goal: c.goals.single,
              amount: Decimal.parse('100.50'),
            ),
            isTrue,
          );
        }
        await c.load();
        final SavingsGoal g = c.goals.single;
        expect(g.savedAmount, Decimal.parse('250'));
        expect(g.addedAmount, Decimal.parse('100.50'));
        expect(g.totalSaved, Decimal.parse('350.50'));
        expect(g.targetDate, DateTime(2027));
        final SavingsContribution entry = f.contributions.single;
        expect(entry.transactionId, isNull);
        expect(entry.goalId, 'g1');
        expect(entry.addedAt, isNotNull);
        expect(f.savingsGoals.single.savedAmount, Decimal.parse('250'));
      },
    );

    test('afterAdding previews the goal without changing it', () {
      final SavingsGoal g = goal();
      final SavingsGoal after = g.afterAdding(Decimal.parse('750'));
      expect(after.totalSaved, Decimal.parse('1000'));
      expect(after.isReached, isTrue);
      expect(g.totalSaved, Decimal.parse('250'));
    });

    Future<FakeFinance> openSheet(WidgetTester tester) async {
      await initializeDateFormatting(AppConstants.defaultLocale);
      Get.testMode = true;
      addTearDown(Get.reset);
      final FakeFinance f = FakeFinance()..savingsGoals.add(goal());
      Get.put(controller(f));
      await tester.pumpWidget(
        GetMaterialApp(
          theme: AppTheme.light,
          home: const SavingsGoalListView(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add money'));
      await tester.pumpAndSettle();
      expect(find.byType(AddMoneySheet), findsOneWidget);
      return f;
    }

    testWidgets('Add money opens a sheet that previews and saves an entry', (
      WidgetTester tester,
    ) async {
      final FakeFinance f = await openSheet(tester);

      await tester.enterText(
        find.descendant(
          of: find.byType(AddMoneySheet),
          matching: find.byType(TextFormField),
        ),
        '100',
      );
      await tester.pump();
      expect(find.text('After adding'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AddMoneySheet),
          matching: find.text('₹350.00 of ₹1,000.00'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Add ₹100.00'));
      await tester.pumpAndSettle();

      expect(find.byType(AddMoneySheet), findsNothing);
      expect(f.contributions.single.amount, Decimal.parse('100'));
      expect(f.savingsGoals.single.savedAmount, Decimal.parse('250'));
      expect(find.text('₹350.00 of ₹1,000.00'), findsOneWidget);
    });

    testWidgets('the amount-left chip fills the rest and the preview says '
        'the goal is reached', (WidgetTester tester) async {
      await openSheet(tester);

      await tester.tap(find.widgetWithText(ActionChip, '₹750.00 left'));
      await tester.pump();
      expect(find.text('This reaches your goal'), findsOneWidget);

      await tester.tap(find.text('Add ₹750.00'));
      await tester.pumpAndSettle();
      expect(find.text('Goal reached'), findsOneWidget);
    });

    testWidgets('the goal detail lists the history and removes money added '
        'by hand after confirming', (WidgetTester tester) async {
      await initializeDateFormatting(AppConstants.defaultLocale);
      Get.testMode = true;
      addTearDown(Get.reset);
      final FakeFinance f = FakeFinance()
        ..addAccount('Cash', '0')
        ..savingsGoals.add(goal());
      f.addTransaction(id: 't1', type: TransactionType.income, amount: '5000');
      f.contributions.addAll(<SavingsContribution>[
        SavingsContribution(
          id: 'c1',
          userId: 'u',
          transactionId: 't1',
          goalId: 'g1',
          amount: Decimal.parse('500'),
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
        SavingsContribution(
          id: 'm1',
          userId: 'u',
          transactionId: null,
          goalId: 'g1',
          amount: Decimal.parse('100'),
          addedAt: DateTime(2026, 11, 1, 10),
          createdAt: DateTime(2026, 11, 1, 10),
          updatedAt: DateTime(2026, 11, 1, 10),
        ),
      ]);
      final DataChangeNotifier notifier = DataChangeNotifier();
      Get.put(SavingsGoalController(f.repositories.savingsGoals, notifier));
      Get.put(
        SavingsGoalDetailController(
          f.repositories.savingsGoals,
          notifier,
          'g1',
        ),
        tag: 'g1',
      );
      await tester.pumpWidget(
        GetMaterialApp(
          theme: AppTheme.light,
          home: const SavingsGoalDetailView(goalId: 'g1'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('₹850.00'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);
      expect(find.text('Added money'), findsOneWidget);
      expect(find.text('+₹100.00'), findsOneWidget);
      expect(find.text('+₹500.00'), findsOneWidget);
      expect(find.text('Starting amount'), findsOneWidget);

      await tester.tap(find.text('Added money'));
      await tester.pumpAndSettle();
      expect(find.text('Remove this entry?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();

      expect(find.text('Added money'), findsNothing);
      expect(find.text('₹750.00'), findsOneWidget);
      expect(
        f.contributions
            .firstWhere((SavingsContribution c) => c.id == 'm1')
            .deletedAt,
        isNotNull,
      );
    });

    testWidgets('goal card shows the total and the part from income', (
      WidgetTester tester,
    ) async {
      await initializeDateFormatting(AppConstants.defaultLocale);
      Get.testMode = true;
      addTearDown(Get.reset);
      final FakeFinance f = FakeFinance()
        ..addAccount('Cash', '0')
        ..savingsGoals.add(goal());
      f.addTransaction(id: 't1', type: TransactionType.income, amount: '5000');
      f.contributions.add(
        SavingsContribution(
          id: 'c1',
          userId: 'u',
          transactionId: 't1',
          goalId: 'g1',
          amount: Decimal.parse('500'),
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      );
      Get.put(controller(f));
      await tester.pumpWidget(
        GetMaterialApp(
          theme: AppTheme.light,
          home: const SavingsGoalListView(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('₹750.00 of ₹1,000.00'), findsOneWidget);
      expect(find.text('₹500.00 from income'), findsOneWidget);
    });

    testWidgets('goal card has no income line without contributions', (
      WidgetTester tester,
    ) async {
      await initializeDateFormatting(AppConstants.defaultLocale);
      Get.testMode = true;
      addTearDown(Get.reset);
      final FakeFinance f = FakeFinance()..savingsGoals.add(goal());
      Get.put(controller(f));
      await tester.pumpWidget(
        GetMaterialApp(
          theme: AppTheme.light,
          home: const SavingsGoalListView(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('₹250.00 of ₹1,000.00'), findsOneWidget);
      expect(find.textContaining('from income'), findsNothing);
    });

    testWidgets('goal form says how much was added after the starting amount', (
      WidgetTester tester,
    ) async {
      await initializeDateFormatting(AppConstants.defaultLocale);
      Get.testMode = true;
      addTearDown(Get.reset);
      Get.put(controller(FakeFinance()));
      await tester.pumpWidget(
        GetMaterialApp(theme: AppTheme.light, home: const SizedBox()),
      );
      unawaited(
        Get.to<void>(
          () => const SavingsGoalFormView(),
          arguments: goal(contributed: '500'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('+ ₹500.00 added later (see history)'), findsOneWidget);
      // The field edits only the starting amount.
      expect(find.widgetWithText(TextFormField, '250'), findsOneWidget);
    });

    test('a failed load or save shows the error', () async {
      final FakeFinance f = FakeFinance()..nextError = const NetworkFailure();
      final SavingsGoalController c = controller(f);
      await c.load();
      expect(c.error.value, isNotNull);
      expect(c.isLoading.value, isFalse);

      f.nextError = const NetworkFailure();
      final bool saved = await c.saveGoal(
        id: 'g1',
        name: 'Trip',
        targetAmount: Decimal.parse('100'),
        savedAmount: Decimal.zero,
        targetDate: null,
      );
      expect(saved, isFalse);
      expect(c.save.error.value, isNotNull);
    });
  });

  group('offline repository', () {
    late AppDatabase database;
    late SavingsGoalRepository repo;

    setUp(() async {
      database = await AppDatabase.inMemory();
      repo = SavingsGoalRepository(
        SupabaseClient('https://dummy.supabase.co', 'dummy-anon-key'),
        database: database,
        syncEngine: SyncEngine(database: database),
      );
    });

    tearDown(() => database.close());

    test('round-trips a goal and queues every change', () async {
      await repo.createSavingsGoal(
        goal(saved: '250.50', targetDate: DateTime(2027, 1, 31)),
      );
      SavingsGoal stored = (await repo.getSavingsGoals()).single;
      expect(stored.savedAmount, Decimal.parse('250.50'));
      expect(stored.targetDate, DateTime(2027, 1, 31));

      await repo.updateSavingsGoal(goal(saved: '900'));
      stored = (await repo.getSavingsGoals()).single;
      expect(stored.savedAmount, Decimal.parse('900'));
      expect(stored.targetDate, isNull);

      await repo.deleteSavingsGoal('g1');
      expect(await repo.getSavingsGoals(), isEmpty);

      final List<SyncQueueItem> queue = await database.getPendingQueue();
      expect(queue.map((SyncQueueItem q) => q.entity).toSet(), <String>{
        'savings_goals',
      });
      expect(queue.map((SyncQueueItem q) => q.operation), <SyncOperation>[
        SyncOperation.create,
        SyncOperation.update,
        SyncOperation.delete,
      ]);
      expect(queue.first.payload['target_amount'], '1000');
    });

    test('upgrading a version 2 file adds the savings goals table', () async {
      final Database old = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(version: 2, singleInstance: false),
      );
      await AppDatabase.upgrade(old, 2, AppDatabase.databaseVersion);
      final List<Map<String, Object?>> columns = await old.rawQuery(
        'PRAGMA table_info(savings_goals)',
      );
      expect(
        columns.map((Map<String, Object?> c) => c['name']),
        contains('saved_amount'),
      );
      await old.close();
    });
  });
}
