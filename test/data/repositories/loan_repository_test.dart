import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/sync_engine.dart';
import 'package:finance_tracker/core/translations/hindi.dart';
import 'package:finance_tracker/core/translations/hinglish.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:finance_tracker/data/models/sync_queue_item.dart';
import 'package:finance_tracker/data/repositories/loan_repository.dart';
import 'package:finance_tracker/domain/entities/loan.dart';
import 'package:finance_tracker/domain/services/loan_ids.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late LoanRepository repo;

  setUp(() async {
    database = await AppDatabase.inMemory();
    repo = LoanRepository(database, syncEngine: SyncEngine(database: database));
  });

  tearDown(() async {
    await database.close();
  });

  Decimal d(String v) => Decimal.parse(v);
  final DateTime now = DateTime(2027, 1, 5, 12);

  Loan loan({
    String id = 'loan-1',
    LoanDirection direction = LoanDirection.taken,
    String name = 'HDFC Home Loan',
    Decimal? principal,
    bool movedMoney = true,
    DateTime? startDate,
    DateTime? firstDueDate,
    DateTime? closedAt,
    String? note,
  }) => Loan(
    id: id,
    userId: '',
    direction: direction,
    method: LoanMethod.emi,
    name: name,
    accountId: 'acc-1',
    principal: principal ?? d('500000'),
    annualRate: d('9'),
    tenureMonths: 60,
    emiAmount: d('10379.18'),
    startDate: startDate ?? DateTime(2027, 1, 5),
    firstDueDate: firstDueDate ?? DateTime(2027, 2, 5),
    movedMoney: movedMoney,
    closedAt: closedAt,
    note: note,
    createdAt: now,
    updatedAt: now,
  );

  Future<List<SyncQueueItem>> queue() async => database.getPendingQueue();

  Future<List<Map<String, Object?>>> rows(String table, [String? where]) =>
      database.db.query(table, where: where);

  Future<int> liveCount(String table) async =>
      (await rows(table, 'deleted_at IS NULL')).length;

  Future<void> insertPayment(String id, {String loanId = 'loan-1'}) async {
    await database.db.insert('loan_payments', <String, Object?>{
      'id': id,
      'user_id': null,
      'loan_id': loanId,
      'account_id': 'acc-1',
      'kind': 'scheduled',
      'paid_at': DateTime(2027, 2, 5).toUtc().toIso8601String(),
      'amount': '10379.18',
      'principal_part': '6129.18',
      'interest_part': '4250',
      'created_at': now.toUtc().toIso8601String(),
      'updated_at': now.toUtc().toIso8601String(),
    });
  }

  test(
    'saving the spec loan writes the loan, money row and reminder',
    () async {
      await repo.saveLoan(loan());

      final List<Map<String, Object?>> loans = await rows('loans');
      expect(loans.length, 1);
      expect(loans.first['moved_money'], 1);
      expect(loans.first['sync_status'], 'pending');

      final List<Map<String, Object?>> txns = await rows('transactions');
      expect(txns.length, 1);
      final Map<String, Object?> money = txns.first;
      expect(money['id'], LoanIds.loanRow('loan-1'));
      expect(money['type'], 'payment_received');
      expect(money['amount'], '500000');
      expect(money['account_id'], 'acc-1');
      expect(money['category_id'], 'c0000000-0000-4000-8000-000000000110');
      expect(money['loan_id'], 'loan-1');
      expect(money['description'], 'HDFC Home Loan');
      expect(money['contact_id'], isNull);

      final List<Map<String, Object?>> reminders = await rows('reminders');
      expect(reminders.length, 1);
      final Map<String, Object?> reminder = reminders.first;
      expect(reminder['id'], LoanIds.reminder('loan-1'));
      expect(reminder['reminder_type'], 'loan');
      expect(reminder['title'], 'Loan payment due');
      expect(reminder['description'], 'HDFC Home Loan');
      expect(reminder['amount'], '10379.18');
      expect(reminder['loan_id'], 'loan-1');
      expect(reminder['contact_id'], isNull);
      expect(reminder['transaction_id'], isNull);
      expect(reminder['repeat_rule'], isNull);
      expect(reminder['is_completed'], 0);
      expect(reminder['notification_enabled'], 1);
      expect(
        DateTime.parse(reminder['remind_at']! as String).toLocal(),
        DateTime(2027, 2, 5, 9),
      );

      final List<SyncQueueItem> items = await queue();
      expect(items.map((SyncQueueItem i) => i.entity).toList(), <String>[
        'loans',
        'transactions',
        'reminders',
      ]);
      expect(items.first.operation, SyncOperation.create);
      expect(items.first.payload['moved_money'], true);
    },
  );

  test('a retried save adds no live rows', () async {
    await repo.saveLoan(loan());
    final int loansBefore = await liveCount('loans');
    final int txnsBefore = await liveCount('transactions');
    final int remindersBefore = await liveCount('reminders');

    await repo.saveLoan(loan());

    expect(await liveCount('loans'), loansBefore);
    expect(await liveCount('transactions'), txnsBefore);
    expect(await liveCount('reminders'), remindersBefore);
    final List<SyncQueueItem> items = await queue();
    expect(items.length, 6);
    expect(items[3].operation, SyncOperation.update);
  });

  test('switching moved money off tombstones the money row', () async {
    await repo.saveLoan(loan());

    await repo.saveLoan(loan(movedMoney: false));

    final List<Map<String, Object?>> txns = await rows('transactions');
    expect(txns.length, 1);
    expect(txns.first['deleted_at'], isNotNull);
    final List<SyncQueueItem> items = await queue();
    expect(
      items.where(
        (SyncQueueItem i) =>
            i.entity == 'transactions' && i.operation == SyncOperation.delete,
      ),
      hasLength(1),
    );
  });

  test('a loan that moved no money writes no money row', () async {
    await repo.saveLoan(loan(movedMoney: false));

    expect(await rows('transactions'), isEmpty);
    expect(await rows('loans'), hasLength(1));
  });

  test('a given loan writes payment_made in the loan_given category', () async {
    await repo.saveLoan(loan(direction: LoanDirection.given, name: 'To Ravi'));

    final Map<String, Object?> money = (await rows('transactions')).single;
    expect(money['type'], 'payment_made');
    expect(money['category_id'], 'c0000000-0000-4000-8000-000000000221');
    expect((await rows('reminders')).single['title'], 'Collect loan payment');
  });

  test('a missing category key leaves category_id null', () async {
    await database.db.delete(
      'categories',
      where: 'system_key = ?',
      whereArgs: <Object>['loan_taken'],
    );

    await repo.saveLoan(loan());

    expect((await rows('transactions')).single['category_id'], isNull);
  });

  test('an invalid loan throws and writes nothing', () async {
    await expectLater(
      repo.saveLoan(loan(name: ' ')),
      throwsA(
        isA<UnexpectedFailure>().having(
          (UnexpectedFailure e) => e.toString(),
          'text',
          contains('Give the loan a name'),
        ),
      ),
    );

    expect(await queue(), isEmpty);
    expect(await rows('loans'), isEmpty);
  });

  test('a closed loan tombstones its reminder', () async {
    await repo.saveLoan(loan());

    await repo.saveLoan(loan(closedAt: now));

    expect((await rows('reminders')).single['deleted_at'], isNotNull);
  });

  test(
    'terms lock: after a payment only name, contact and note change',
    () async {
      await repo.saveLoan(loan());
      await insertPayment('pay-1');
      final int queueBefore = (await queue()).length;

      await expectLater(
        repo.saveLoan(loan(principal: d('400000'))),
        throwsA(
          isA<UnexpectedFailure>().having(
            (UnexpectedFailure e) => e.toString(),
            'text',
            contains(
              'Only the name, contact and note can change after a payment',
            ),
          ),
        ),
      );
      expect((await rows('loans')).single['principal'], '500000');
      expect((await queue()).length, queueBefore);

      await repo.saveLoan(loan(name: 'HDFC Renamed', note: 'new note'));

      final Map<String, Object?> saved = (await rows('loans')).single;
      expect(saved['name'], 'HDFC Renamed');
      expect(saved['note'], 'new note');
    },
  );

  test('getLoans orders open loans by due date, then closed ones', () async {
    await repo.saveLoan(
      loan(id: 'late', name: 'Late', firstDueDate: DateTime(2027, 5, 5)),
    );
    await repo.saveLoan(
      loan(id: 'soon', name: 'Soon', firstDueDate: DateTime(2027, 2, 5)),
    );
    await repo.saveLoan(
      loan(id: 'old', name: 'Old', closedAt: DateTime(2027, 3, 1)),
    );
    await repo.saveLoan(
      loan(id: 'newer', name: 'Newer', closedAt: DateTime(2027, 4, 1)),
    );

    final List<LoanSummary> loans = await repo.getLoans();

    expect(loans.map((LoanSummary s) => s.loan.id).toList(), <String>[
      'soon',
      'late',
      'newer',
      'old',
    ]);
    expect(loans.first.status.outstanding, d('500000'));
  });

  test('getLoansForContact and getLoan', () async {
    await repo.saveLoan(loan(id: 'a'));
    final Loan withContact = Loan(
      id: 'b',
      userId: '',
      direction: LoanDirection.given,
      method: LoanMethod.monthlyInterest,
      name: 'Ravi',
      contactId: 'c1',
      accountId: 'acc-1',
      principal: d('1000'),
      annualRate: d('24'),
      startDate: DateTime(2027, 1, 5),
      movedMoney: false,
      createdAt: now,
      updatedAt: now,
    );
    await repo.saveLoan(withContact);

    final List<LoanSummary> forContact = await repo.getLoansForContact('c1');
    expect(forContact.map((LoanSummary s) => s.loan.id), <String>['b']);

    await insertPayment('pay-a', loanId: 'a');
    final LoanDetail detail = await repo.getLoan('a');
    expect(detail.loan.name, 'HDFC Home Loan');
    expect(detail.payments.single.id, 'pay-a');
    expect(detail.status.outstanding, d('493870.82'));

    await expectLater(repo.getLoan('missing'), throwsA(isA<DatabaseFailure>()));
  });

  test('outstandingTotals sums each direction over live loans', () async {
    await repo.saveLoan(loan(id: 'a', principal: d('500000')));
    await repo.saveLoan(loan(id: 'b', principal: d('250000.50')));
    await repo.saveLoan(
      loan(id: 'c', direction: LoanDirection.given, principal: d('1000')),
    );
    await repo.saveLoan(
      loan(id: 'd', direction: LoanDirection.given, principal: d('77')),
    );
    await repo.deleteLoan('d');

    final ({Decimal given, Decimal taken}) totals = await repo
        .outstandingTotals();

    expect(totals.taken, d('750000.50'));
    expect(totals.given, d('1000'));
  });

  test(
    'deleteLoan tombstones loan, payments, money row and reminder',
    () async {
      await repo.saveLoan(loan());
      await insertPayment('pay-1');
      await database.db.insert('transactions', <String, Object?>{
        'id': 'pay-txn',
        'account_id': 'acc-1',
        'type': 'payment_made',
        'amount': '4250',
        'transaction_date': now.toUtc().toIso8601String(),
        'loan_id': 'loan-1',
        'created_at': now.toUtc().toIso8601String(),
        'updated_at': now.toUtc().toIso8601String(),
      });
      final int queueBefore = (await queue()).length;

      await repo.deleteLoan('loan-1');

      for (final String table in <String>[
        'loans',
        'loan_payments',
        'transactions',
        'reminders',
      ]) {
        expect(await liveCount(table), 0, reason: table);
      }
      final List<SyncQueueItem> items = (await queue())
          .skip(queueBefore)
          .toList();
      expect(
        items.every((SyncQueueItem i) => i.operation == SyncOperation.delete),
        isTrue,
      );
      expect(items.map((SyncQueueItem i) => i.entity).toSet(), <String>{
        'loans',
        'loan_payments',
        'transactions',
        'reminders',
      });
      expect(
        items.where((SyncQueueItem i) => i.entity == 'transactions'),
        hasLength(2),
      );
    },
  );

  test('with a null database every method throws DatabaseFailure', () async {
    final LoanRepository none = LoanRepository(null);

    await expectLater(none.getLoans(), throwsA(isA<DatabaseFailure>()));
    await expectLater(
      none.getLoansForContact('c'),
      throwsA(isA<DatabaseFailure>()),
    );
    await expectLater(none.getLoan('x'), throwsA(isA<DatabaseFailure>()));
    await expectLater(
      none.outstandingTotals(),
      throwsA(isA<DatabaseFailure>()),
    );
    await expectLater(none.saveLoan(loan()), throwsA(isA<DatabaseFailure>()));
    await expectLater(none.deleteLoan('x'), throwsA(isA<DatabaseFailure>()));
  });

  test('every loan message and reminder title is in both language maps', () {
    // The calculator returns plain keys, which the translation coverage scan
    // of `Failure(...)` literals cannot see.
    const List<String> keys = <String>[
      'Give the loan a name',
      'Choose an account',
      'Amount must be more than zero',
      'Amounts can have at most 2 decimals',
      'Interest rate must be between 0% and 60% a year',
      'Interest rate must be between 0% and 5% a month',
      'Tenure must be 1 to 480 months',
      'Enter the EMI',
      "The EMI does not cover the first month's interest",
      'Choose the first EMI date',
      'The first EMI cannot be before the loan starts',
      'Principal and interest must add up to the amount',
      'A payment cannot be dated before the previous one or the loan start',
      'This loan is already repaid',
      'This is more than the principal still owed',
      'This is more than is owed',
      'Only the name, contact and note can change after a payment',
      'Loan payment due',
      'Collect loan payment',
    ];
    expect(
      keys.where(
        (String k) => !hindi.containsKey(k) || !hinglish.containsKey(k),
      ),
      isEmpty,
    );
  });
}
