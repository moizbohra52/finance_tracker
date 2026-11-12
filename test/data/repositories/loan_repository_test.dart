import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/sync_engine.dart';
import 'package:finance_tracker/core/translations/hindi.dart';
import 'package:finance_tracker/core/translations/hinglish.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:finance_tracker/data/models/sync_queue_item.dart';
import 'package:finance_tracker/data/models/transaction.dart';
import 'package:finance_tracker/data/repositories/loan_repository.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/loan.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/finance_summary_calculator.dart';
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

  group('payments', () {
    Loan ravi() => Loan(
      id: 'ravi',
      userId: '',
      direction: LoanDirection.given,
      method: LoanMethod.monthlyInterest,
      name: 'Ravi',
      accountId: 'acc-1',
      principal: d('10000'),
      annualRate: d('24'),
      startDate: DateTime(2027, 1, 1),
      movedMoney: false,
      createdAt: now,
      updatedAt: now,
    );

    LoanPayment pay(
      String id,
      DateTime paidAt,
      String principal,
      String interest, {
      String loanId = 'loan-1',
      LoanPaymentKind kind = LoanPaymentKind.scheduled,
      String? note,
    }) => LoanPayment(
      id: id,
      userId: '',
      loanId: loanId,
      accountId: 'acc-1',
      kind: kind,
      paidAt: paidAt,
      amount: d(principal) + d(interest),
      principalPart: d(principal),
      interestPart: d(interest),
      note: note,
      createdAt: now,
      updatedAt: now,
    );

    LoanPayment first() => pay('p1', DateTime(2027, 2, 5), '6629.18', '3750');

    Future<List<Map<String, Object?>>> liveRows(
      String table, [
      String? where,
    ]) => database.db.query(
      table,
      where: 'deleted_at IS NULL${where == null ? '' : ' AND $where'}',
      orderBy: 'id',
    );

    Future<List<Transaction>> allTransactions() async =>
        (await rows('transactions'))
            .map(TransactionModel.fromJson)
            .map((TransactionModel m) => m.toEntity())
            .toList();

    Future<Decimal> hdfcBalance() async {
      final Account account = Account(
        id: 'acc-1',
        userId: '',
        name: 'HDFC',
        type: AccountType.bank,
        openingBalance: Decimal.zero,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );
      return FinanceSummaryCalculator.accountBalances(<Account>[
        account,
      ], await allTransactions())['acc-1']!;
    }

    test('the first EMI writes its rows and moves the reminder', () async {
      await repo.saveLoan(loan());
      final Decimal before = await hdfcBalance();
      final int queueBefore = (await queue()).length;

      await repo.savePayment(first());

      final Map<String, Object?> principal = (await liveRows(
        'transactions',
        'id = \'${LoanIds.paymentPrincipal('p1')}\'',
      )).single;
      expect(principal['type'], 'payment_made');
      expect(principal['amount'], '6629.18');
      expect(principal['category_id'], 'c0000000-0000-4000-8000-000000000222');
      expect(principal['loan_id'], 'loan-1');
      expect(principal['description'], 'HDFC Home Loan');
      expect(principal['account_id'], 'acc-1');
      expect(principal['contact_id'], isNull);
      final Map<String, Object?> interest = (await liveRows(
        'transactions',
        'id = \'${LoanIds.paymentInterest('p1')}\'',
      )).single;
      expect(interest['type'], 'expense');
      expect(interest['amount'], '3750');
      expect(interest['category_id'], 'c0000000-0000-4000-8000-000000000223');

      expect(before - await hdfcBalance(), d('10379.18'));
      final PeriodSummary period = FinanceSummaryCalculator.period(
        await allTransactions(),
        DateTime(2027, 2),
        DateTime(2027, 3),
      );
      expect(period.expense, d('3750'));
      expect(period.income, Decimal.zero);

      final LoanDetail detail = await repo.getLoan('loan-1');
      expect(detail.status.outstanding, d('493370.82'));
      final Map<String, Object?> reminder = (await liveRows(
        'reminders',
      )).single;
      expect(reminder['amount'], '10379.18');
      expect(
        DateTime.parse(reminder['remind_at']! as String).toLocal(),
        DateTime(2027, 3, 5, 9),
      );

      final List<SyncQueueItem> items = (await queue())
          .skip(queueBefore)
          .toList();
      expect(items.map((SyncQueueItem i) => i.entity).toList(), <String>[
        'loan_payments',
        'transactions',
        'transactions',
        'reminders',
      ]);
      expect(items.first.operation, SyncOperation.create);
      expect(items.last.operation, SyncOperation.update);
      // The loan row is queued only when it closes or reopens.
      expect(items.where((SyncQueueItem i) => i.entity == 'loans'), isEmpty);
    });

    test('a given loan writes payment_received and income rows', () async {
      await repo.saveLoan(ravi());

      await repo.savePayment(
        pay('r1', DateTime(2027, 3, 15), '2600', '400', loanId: 'ravi'),
      );

      final Map<String, Object?> principal = (await liveRows(
        'transactions',
        'id = \'${LoanIds.paymentPrincipal('r1')}\'',
      )).single;
      expect(principal['type'], 'payment_received');
      expect(principal['amount'], '2600');
      expect(principal['category_id'], 'c0000000-0000-4000-8000-000000000111');
      final Map<String, Object?> interest = (await liveRows(
        'transactions',
        'id = \'${LoanIds.paymentInterest('r1')}\'',
      )).single;
      expect(interest['type'], 'income');
      expect(interest['amount'], '400');
      expect(interest['category_id'], 'c0000000-0000-4000-8000-000000000112');
    });

    test('a part of 0 writes no row; the note and name are carried', () async {
      await repo.saveLoan(ravi());

      await repo.savePayment(
        pay(
          'r1',
          DateTime(2027, 1, 10),
          '500',
          '0',
          loanId: 'ravi',
          note: 'cash',
        ),
      );

      final Map<String, Object?> only = (await liveRows('transactions')).single;
      expect(only['id'], LoanIds.paymentPrincipal('r1'));
      expect(only['note'], 'cash');
      expect(only['description'], 'Ravi');
    });

    test('a retried savePayment adds no live rows', () async {
      await repo.saveLoan(loan());
      await repo.savePayment(first());
      final int txns = await liveCount('transactions');
      final int reminders = await liveCount('reminders');

      await repo.savePayment(first());

      expect(await liveCount('loan_payments'), 1);
      expect(await liveCount('transactions'), txns);
      expect(await liveCount('reminders'), reminders);
      expect(
        (await queue()).where(
          (SyncQueueItem i) =>
              i.entity == 'loan_payments' &&
              i.operation == SyncOperation.update,
        ),
        hasLength(1),
      );
    });

    test('a back-dated payment is refused and writes nothing', () async {
      await repo.saveLoan(ravi());
      await repo.savePayment(
        pay('r1', DateTime(2027, 3, 15), '2600', '400', loanId: 'ravi'),
      );
      final int queueBefore = (await queue()).length;

      await expectLater(
        repo.savePayment(
          pay('r2', DateTime(2027, 3, 14), '500', '0', loanId: 'ravi'),
        ),
        throwsA(
          isA<UnexpectedFailure>().having(
            (UnexpectedFailure e) => e.toString(),
            'text',
            contains('A payment cannot be dated before the previous one'),
          ),
        ),
      );

      expect(await liveCount('loan_payments'), 1);
      expect(await liveCount('transactions'), 2);
      expect((await queue()).length, queueBefore);
    });

    test('only the latest payment can be edited or deleted', () async {
      await repo.saveLoan(ravi());
      await repo.savePayment(
        pay('r1', DateTime(2027, 2, 10), '2000', '200', loanId: 'ravi'),
      );
      await repo.savePayment(
        pay('r2', DateTime(2027, 3, 15), '2600', '400', loanId: 'ravi'),
      );
      final int queueBefore = (await queue()).length;
      final Matcher refused = throwsA(
        isA<UnexpectedFailure>().having(
          (UnexpectedFailure e) => e.toString(),
          'text',
          contains('Only the latest payment can be changed'),
        ),
      );

      await expectLater(
        repo.savePayment(
          pay('r1', DateTime(2027, 2, 10), '1000', '200', loanId: 'ravi'),
        ),
        refused,
      );
      await expectLater(repo.deletePayment('r1'), refused);
      expect((await queue()).length, queueBefore);

      final List<Map<String, Object?>> before = await liveRows(
        'transactions',
        'loan_id = \'ravi\'',
      );
      expect(before, hasLength(4));
      await repo.savePayment(
        pay('r2', DateTime(2027, 3, 15), '2600', '200', loanId: 'ravi'),
      );
      final List<Map<String, Object?>> after = await liveRows(
        'transactions',
        'loan_id = \'ravi\'',
      );
      expect(
        after.map((Map<String, Object?> r) => r['id']),
        before.map((Map<String, Object?> r) => r['id']),
      );
      expect(
        after.singleWhere(
          (Map<String, Object?> r) => r['id'] == LoanIds.paymentInterest('r2'),
        )['amount'],
        '200',
      );

      await repo.savePayment(
        pay('r2', DateTime(2027, 3, 15), '2600', '0', loanId: 'ravi'),
      );
      expect(
        await liveRows(
          'transactions',
          'id = \'${LoanIds.paymentInterest('r2')}\'',
        ),
        isEmpty,
      );
      expect(await liveCount('loan_payments'), 2);
    });

    test('deleting the latest payment tombstones it and its rows', () async {
      await repo.saveLoan(loan());
      await repo.savePayment(first());
      final int queueBefore = (await queue()).length;

      await repo.deletePayment('p1');

      expect(await liveCount('loan_payments'), 0);
      expect(
        await liveRows('transactions', 'loan_id = \'loan-1\''),
        hasLength(1),
      );
      final List<SyncQueueItem> items = (await queue())
          .skip(queueBefore)
          .toList();
      expect(
        items
            .where((SyncQueueItem i) => i.operation == SyncOperation.delete)
            .map((SyncQueueItem i) => i.entity)
            .toList(),
        <String>['loan_payments', 'transactions', 'transactions'],
      );
      final Map<String, Object?> reminder = (await liveRows(
        'reminders',
      )).single;
      expect(reminder['amount'], '10379.18');
      expect(
        DateTime.parse(reminder['remind_at']! as String).toLocal(),
        DateTime(2027, 2, 5, 9),
      );
      await expectLater(
        repo.deletePayment('p1'),
        throwsA(isA<DatabaseFailure>()),
      );
    });

    test(
      'closing a loan sets closed_at; deleting the payment reopens',
      () async {
        await repo.saveLoan(ravi());

        await repo.savePayment(
          pay('r1', DateTime(2027, 3, 15), '10000', '400', loanId: 'ravi'),
        );

        final Map<String, Object?> closed = (await rows('loans')).single;
        expect(
          DateTime.parse(closed['closed_at']! as String).toLocal(),
          DateTime(2027, 3, 15),
        );
        expect(closed['sync_status'], 'pending');
        expect((await rows('reminders')).single['deleted_at'], isNotNull);
        expect((await repo.getLoans()).single.loan.isClosed, isTrue);
        final List<SyncQueueItem> closedItems = await queue();
        expect(
          closedItems.where((SyncQueueItem i) => i.entity == 'loans'),
          hasLength(2),
        );
        expect(closedItems.last.entity, 'reminders');
        expect(closedItems.last.operation, SyncOperation.delete);

        await repo.deletePayment('r1');

        final Map<String, Object?> reopened = (await rows('loans')).single;
        expect(reopened['closed_at'], isNull);
        final Map<String, Object?> reminder = (await liveRows(
          'reminders',
        )).single;
        expect(reminder['is_completed'], 0);
        expect(reminder['snoozed_until'], isNull);
        expect(Decimal.parse(reminder['amount']! as String), d('200'));
        expect(
          DateTime.parse(reminder['remind_at']! as String).toLocal(),
          DateTime(2027, 2, 1, 9),
        );
        expect((await repo.getLoans()).single.loan.isClosed, isFalse);
      },
    );

    test('an invalid payment is refused', () async {
      await repo.saveLoan(ravi());
      final int queueBefore = (await queue()).length;

      await expectLater(
        repo.savePayment(
          pay('r1', DateTime(2027, 3, 15), '10001', '0', loanId: 'ravi'),
        ),
        throwsA(isA<UnexpectedFailure>()),
      );
      await expectLater(
        repo.savePayment(
          pay('x', DateTime(2027, 3, 15), '1', '0', loanId: 'no'),
        ),
        throwsA(isA<DatabaseFailure>()),
      );

      expect((await queue()).length, queueBefore);
    });

    test('a failure inside the transaction leaves nothing behind', () async {
      await repo.saveLoan(loan());
      final int queueBefore = (await queue()).length;
      await database.db.execute('DROP TABLE loan_payments');

      await expectLater(repo.savePayment(first()), throwsA(isA<Exception>()));

      expect(await liveCount('transactions'), 1);
      expect((await queue()).length, queueBefore);
    });

    test('a failure after the payment rows rolls them back', () async {
      await repo.saveLoan(loan());
      final int queueBefore = (await queue()).length;
      await database.db.execute('DROP TABLE reminders');

      await expectLater(repo.savePayment(first()), throwsA(isA<Exception>()));

      expect(await liveCount('loan_payments'), 0);
      expect(await liveCount('transactions'), 1);
      expect((await queue()).length, queueBefore);
    });

    test('copyWith can clear closedAt', () {
      final Loan closed = loan(closedAt: now);

      expect(closed.copyWith().closedAt, now);
      expect(closed.copyWith(clearClosedAt: true).closedAt, isNull);
    });
  });

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
    await expectLater(none.deletePayment('x'), throwsA(isA<DatabaseFailure>()));
    await expectLater(
      none.savePayment(
        LoanPayment(
          id: 'p',
          userId: '',
          loanId: 'x',
          accountId: 'a',
          kind: LoanPaymentKind.scheduled,
          paidAt: now,
          amount: d('1'),
          principalPart: d('1'),
          interestPart: Decimal.zero,
          createdAt: now,
          updatedAt: now,
        ),
      ),
      throwsA(isA<DatabaseFailure>()),
    );
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
      'Only the latest payment can be changed',
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
