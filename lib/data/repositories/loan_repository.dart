import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/sync_engine.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:finance_tracker/data/models/loan.dart';
import 'package:finance_tracker/data/models/reminder.dart';
import 'package:finance_tracker/data/models/sync_queue_item.dart';
import 'package:finance_tracker/data/models/transaction.dart';
import 'package:finance_tracker/data/repositories/payloads.dart';
import 'package:finance_tracker/domain/entities/loan.dart';
import 'package:finance_tracker/domain/entities/reminder.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/loan_calculator.dart';
import 'package:finance_tracker/domain/services/loan_ids.dart';
import 'package:get/get.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

/// One loan for the list screens, with where it stands.
class LoanSummary {
  const LoanSummary({required this.loan, required this.status});

  final Loan loan;
  final LoanStatus status;
}

/// A loan with its live payments (newest first) for the detail screen.
class LoanDetail {
  const LoanDetail({
    required this.loan,
    required this.payments,
    required this.status,
  });

  final Loan loan;
  final List<LoanPayment> payments;
  final LoanStatus status;
}

/// Local storage for loans (docs/05_FINANCIAL_LOGIC.md). Every write is one
/// SQLite transaction holding the rows and their queue items, parents
/// enqueued first. With a null database every method throws `DatabaseFailure`
/// (production always passes the database).
class LoanRepository {
  LoanRepository(AppDatabase? database, {SyncEngine? syncEngine})
    : _db = database,
      // ignore: prefer_initializing_formals
      _syncEngine = syncEngine;

  final AppDatabase? _db;
  final SyncEngine? _syncEngine;

  AppDatabase get _database {
    final AppDatabase? db = _db;
    if (db == null) throw const DatabaseFailure();
    return db;
  }

  static Future<void> _enqueue(
    DatabaseExecutor txn,
    SyncOperation operation,
    String entity,
    String entityId,
    Map<String, dynamic> payload,
    DateTime now,
  ) => txn.insert(
    'sync_queue',
    SyncQueueItem(
      operation: operation,
      entity: entity,
      entityId: entityId,
      payload: payload,
      createdAt: now,
    ).toRow(),
  );

  /// A full local row: model columns plus timestamps and the pending flag.
  static Map<String, dynamic> _row(
    Map<String, dynamic> json,
    DateTime createdAt,
    DateTime updatedAt,
  ) => <String, dynamic>{
    ...json,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'deleted_at': null,
    'sync_status': 'pending',
  };

  /// Live loans: open ones by next due date (none last), then closed ones,
  /// the latest closed first.
  Future<List<LoanSummary>> getLoans() => _summaries('deleted_at IS NULL', []);

  Future<List<LoanSummary>> getLoansForContact(String contactId) =>
      _summaries('deleted_at IS NULL AND contact_id = ?', <Object>[contactId]);

  Future<LoanDetail> getLoan(String loanId) async {
    final AppDatabase database = _database;
    final Loan? loan = await _loanOrNull(database.db, loanId);
    if (loan == null || !loan.isLive) throw const DatabaseFailure();
    final List<LoanPayment> payments = await _livePayments(database.db, loanId);
    return LoanDetail(
      loan: loan,
      payments: payments,
      status: LoanCalculator.status(loan, payments),
    );
  }

  /// What is still owed in each direction, over live loans.
  Future<({Decimal given, Decimal taken})> outstandingTotals() async {
    Decimal given = Decimal.zero;
    Decimal taken = Decimal.zero;
    for (final LoanSummary s in await getLoans()) {
      if (s.loan.direction == LoanDirection.given) {
        given += s.status.outstanding;
      } else {
        taken += s.status.outstanding;
      }
    }
    return (given: given, taken: taken);
  }

  /// Validates the loan and writes it, its money row and its reminder in one
  /// local transaction, queued in that order. A retry with the same id
  /// upserts. Once a payment is live only the name, contact and note change.
  Future<void> saveLoan(Loan loan) async {
    final AppDatabase database = _database;
    final String? message = LoanCalculator.validateLoan(loan);
    if (message != null) throw UnexpectedFailure(message);
    final DateTime now = DateTime.now();
    final String categoryKey = loan.direction == LoanDirection.taken
        ? 'loan_taken'
        : 'loan_given';
    final String moneyId = LoanIds.loanRow(loan.id);

    await database.db.transaction((DatabaseExecutor txn) async {
      // Read inside the transaction: the closed state belongs to the payments
      // and the stored row, never to the (possibly stale) form copy.
      final Loan? existing = await _loanOrNull(txn, loan.id);
      final List<LoanPayment> payments = await _livePayments(txn, loan.id);
      if (existing != null &&
          payments.isNotEmpty &&
          termsChanged(existing, loan)) {
        throw const UnexpectedFailure(
          'Only the name, contact and note can change after a payment',
        );
      }
      final Loan saved = existing?.closedAt == null
          ? loan.copyWith(clearClosedAt: true, updatedAt: now)
          : loan.copyWith(closedAt: existing!.closedAt, updatedAt: now);
      final bool isNew = existing == null || !existing.isLive;
      final LoanStatus status = LoanCalculator.status(saved, payments);
      // 1. The loan.
      final Map<String, dynamic> loanJson = LoanModel.toJson(saved);
      await txn.insert('loans', <String, dynamic>{
        ..._row(loanJson, existing?.createdAt ?? loan.createdAt, now),
        'moved_money': saved.movedMoney ? 1 : 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await _enqueue(
        txn,
        isNew ? SyncOperation.create : SyncOperation.update,
        'loans',
        loan.id,
        loanJson,
        now,
      );
      // 2. The money row of a loan that moved money.
      if (saved.movedMoney) {
        final bool moneyLive = (await _liveIds(
          txn,
          'transactions',
          'id = ?',
          moneyId,
        )).isNotEmpty;
        final Map<String, dynamic> json = TransactionModel.fromEntity(
          Transaction(
            id: moneyId,
            userId: '',
            accountId: saved.accountId,
            categoryId: await _categoryId(txn, categoryKey),
            contactId: null,
            type: saved.direction == LoanDirection.taken
                ? TransactionType.payment_received
                : TransactionType.payment_made,
            amount: saved.principal,
            transactionDate: saved.startDate,
            description: saved.name,
            loanId: saved.id,
            createdAt: now,
            updatedAt: now,
          ),
        ).toJson();
        await txn.insert(
          'transactions',
          _row(json, now, now),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await _enqueue(
          txn,
          moneyLive ? SyncOperation.update : SyncOperation.create,
          'transactions',
          moneyId,
          json,
          now,
        );
      } else {
        await _tombstoneLive(txn, 'transactions', 'id = ?', moneyId, now);
      }
      // 3. The reminder of the next due date; none for a closed loan.
      await _syncReminder(txn, saved, status, now);
    });
    _syncEngine?.notifyNewQueueItem();
  }

  /// Soft-deletes the loan, its payments, every transaction linked to it and
  /// its reminder, one queue delete per row, in one local transaction.
  Future<void> deleteLoan(String loanId) async {
    final AppDatabase database = _database;
    final DateTime now = DateTime.now();
    await database.db.transaction((DatabaseExecutor txn) async {
      await _tombstoneLive(txn, 'loans', 'id = ?', loanId, now);
      for (final String id in await _liveIds(
        txn,
        'loan_payments',
        'loan_id = ?',
        loanId,
      )) {
        await _tombstoneLive(txn, 'loan_payments', 'id = ?', id, now);
      }
      for (final String id in await _liveIds(
        txn,
        'transactions',
        'loan_id = ?',
        loanId,
      )) {
        await _tombstoneLive(txn, 'transactions', 'id = ?', id, now);
      }
      await _tombstoneLive(
        txn,
        'reminders',
        'id = ?',
        LoanIds.reminder(loanId),
        now,
      );
    });
    _syncEngine?.notifyNewQueueItem();
  }

  /// Writes a payment, its principal and interest rows, the loan's closed
  /// state and the reminder in one local transaction, queued in that order.
  /// Only the loan's latest live payment (by `paid_at`, `created_at`, id) can
  /// be edited, and a new one cannot be dated before it, so the stored splits
  /// of later payments never go stale. A retry with the same id upserts.
  Future<void> savePayment(LoanPayment payment) async {
    final AppDatabase database = _database;
    final DateTime now = DateTime.now();
    await database.db.transaction((DatabaseExecutor txn) async {
      final Loan loan = await _liveLoan(txn, payment.loanId);
      final List<LoanPayment> live = await _livePayments(txn, loan.id);
      final LoanPayment? existing = live
          .where((LoanPayment p) => p.id == payment.id)
          .firstOrNull;
      if (existing != null && live.first.id != existing.id) {
        throw const UnexpectedFailure('Only the latest payment can be changed');
      }
      final List<LoanPayment> others = live
          .where((LoanPayment p) => p.id != payment.id)
          .toList();
      final String? message = LoanCalculator.validatePayment(
        loan,
        others,
        payment,
      );
      if (message != null) throw UnexpectedFailure(message);

      final DateTime createdAt = existing?.createdAt ?? payment.createdAt;
      final LoanPayment saved = payment.copyWith(updatedAt: now);
      final Map<String, dynamic> json = LoanPaymentModel.toJson(saved);
      await txn.insert(
        'loan_payments',
        _row(json, createdAt, now),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _enqueue(
        txn,
        existing == null ? SyncOperation.create : SyncOperation.update,
        'loan_payments',
        saved.id,
        json,
        now,
      );
      final bool taken = loan.direction == LoanDirection.taken;
      await _writePart(
        txn,
        id: LoanIds.paymentPrincipal(saved.id),
        amount: saved.principalPart,
        type: taken
            ? TransactionType.payment_made
            : TransactionType.payment_received,
        categoryKey: taken ? 'loan_repayment_made' : 'loan_repayment_received',
        loan: loan,
        payment: saved,
        createdAt: createdAt,
        now: now,
      );
      await _writePart(
        txn,
        id: LoanIds.paymentInterest(saved.id),
        amount: saved.interestPart,
        type: taken ? TransactionType.expense : TransactionType.income,
        categoryKey: taken ? 'loan_interest_paid' : 'loan_interest_received',
        loan: loan,
        payment: saved,
        createdAt: createdAt,
        now: now,
      );
      final List<LoanPayment> after = <LoanPayment>[...others, saved];
      final Loan updated = await _writeClosed(
        txn,
        loan,
        LoanCalculator.outstanding(loan, after) <= Decimal.zero
            ? saved.paidAt
            : null,
        now,
      );
      await _syncReminder(
        txn,
        updated,
        LoanCalculator.status(updated, after),
        now,
      );
    });
    _syncEngine?.notifyNewQueueItem();
  }

  /// Soft-deletes the loan's latest live payment and its two money rows,
  /// reopens the loan if the payment had closed it and moves the reminder
  /// back to the next due date.
  Future<void> deletePayment(String paymentId) async {
    final AppDatabase database = _database;
    final DateTime now = DateTime.now();
    await database.db.transaction((DatabaseExecutor txn) async {
      final List<Map<String, dynamic>> found = await txn.query(
        'loan_payments',
        columns: <String>['loan_id'],
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: <Object>[paymentId],
        limit: 1,
      );
      if (found.isEmpty) throw const DatabaseFailure();
      final Loan loan = await _liveLoan(txn, found.first['loan_id'] as String);
      final List<LoanPayment> live = await _livePayments(txn, loan.id);
      if (live.first.id != paymentId) {
        throw const UnexpectedFailure('Only the latest payment can be changed');
      }
      await _tombstoneLive(txn, 'loan_payments', 'id = ?', paymentId, now);
      await _tombstoneLive(
        txn,
        'transactions',
        'id = ?',
        LoanIds.paymentPrincipal(paymentId),
        now,
      );
      await _tombstoneLive(
        txn,
        'transactions',
        'id = ?',
        LoanIds.paymentInterest(paymentId),
        now,
      );
      final List<LoanPayment> after = live.skip(1).toList();
      final Loan updated = await _writeClosed(
        txn,
        loan,
        LoanCalculator.outstanding(loan, after) <= Decimal.zero
            ? loan.closedAt
            : null,
        now,
      );
      await _syncReminder(
        txn,
        updated,
        LoanCalculator.status(updated, after),
        now,
      );
    });
    _syncEngine?.notifyNewQueueItem();
  }

  /// True when [next] differs from [old] in anything but name, contact, note
  /// (and the closed state, which the payments own).
  static bool termsChanged(Loan old, Loan next) {
    bool sameDay(DateTime? a, DateTime? b) =>
        (a == null && b == null) ||
        (a != null &&
            b != null &&
            a.year == b.year &&
            a.month == b.month &&
            a.day == b.day);
    return old.direction != next.direction ||
        old.method != next.method ||
        old.accountId != next.accountId ||
        old.principal != next.principal ||
        old.annualRate != next.annualRate ||
        old.tenureMonths != next.tenureMonths ||
        old.emiAmount != next.emiAmount ||
        old.movedMoney != next.movedMoney ||
        !sameDay(old.startDate, next.startDate) ||
        !sameDay(old.firstDueDate, next.firstDueDate);
  }

  /// Open loans by next due date (none last), then closed ones, the latest
  /// closed first; ties by id.
  static List<LoanSummary> ordered(List<LoanSummary> all) {
    final List<LoanSummary> open = all
        .where((LoanSummary s) => !s.loan.isClosed)
        .toList();
    open.sort((LoanSummary a, LoanSummary b) {
      final DateTime? da = a.status.nextDueDate;
      final DateTime? db = b.status.nextDueDate;
      final int byDue = da == null
          ? (db == null ? 0 : 1)
          : (db == null ? -1 : da.compareTo(db));
      return byDue != 0 ? byDue : a.loan.id.compareTo(b.loan.id);
    });
    final List<LoanSummary> closed = all
        .where((LoanSummary s) => s.loan.isClosed)
        .toList();
    closed.sort((LoanSummary a, LoanSummary b) {
      final int byClosed = b.loan.closedAt!.compareTo(a.loan.closedAt!);
      return byClosed != 0 ? byClosed : a.loan.id.compareTo(b.loan.id);
    });
    return <LoanSummary>[...open, ...closed];
  }

  Future<List<LoanSummary>> _summaries(String where, List<Object> args) async {
    final AppDatabase database = _database;
    final List<Map<String, dynamic>> rows = await database.db.query(
      'loans',
      where: where,
      whereArgs: args,
    );
    final List<LoanSummary> all = <LoanSummary>[];
    for (final Map<String, dynamic> row in rows) {
      final Loan loan = LoanModel.fromJson(row);
      final List<LoanPayment> payments = await _livePayments(
        database.db,
        loan.id,
      );
      all.add(
        LoanSummary(loan: loan, status: LoanCalculator.status(loan, payments)),
      );
    }
    return ordered(all);
  }

  Future<Loan?> _loanOrNull(DatabaseExecutor db, String loanId) async {
    final List<Map<String, dynamic>> rows = await db.query(
      'loans',
      where: 'id = ?',
      whereArgs: <Object>[loanId],
      limit: 1,
    );
    return rows.isEmpty ? null : LoanModel.fromJson(rows.first);
  }

  Future<Loan> _liveLoan(DatabaseExecutor txn, String loanId) async {
    final Loan? loan = await _loanOrNull(txn, loanId);
    if (loan == null || !loan.isLive) throw const DatabaseFailure();
    return loan;
  }

  Future<String?> _categoryId(DatabaseExecutor txn, String systemKey) async {
    final List<Map<String, dynamic>> category = await txn.query(
      'categories',
      columns: <String>['id'],
      where: 'system_key = ? AND is_system = 1 AND deleted_at IS NULL',
      whereArgs: <Object>[systemKey],
      limit: 1,
    );
    return category.isEmpty ? null : category.first['id'] as String;
  }

  /// The money row of one part of a payment; a part of 0 has no row, so an
  /// existing one is tombstoned.
  Future<void> _writePart(
    DatabaseExecutor txn, {
    required String id,
    required Decimal amount,
    required TransactionType type,
    required String categoryKey,
    required Loan loan,
    required LoanPayment payment,
    required DateTime createdAt,
    required DateTime now,
  }) async {
    if (amount <= Decimal.zero) {
      await _tombstoneLive(txn, 'transactions', 'id = ?', id, now);
      return;
    }
    final bool live = (await _liveIds(
      txn,
      'transactions',
      'id = ?',
      id,
    )).isNotEmpty;
    final Map<String, dynamic> json = TransactionModel.fromEntity(
      Transaction(
        id: id,
        userId: '',
        accountId: payment.accountId,
        categoryId: await _categoryId(txn, categoryKey),
        contactId: null,
        type: type,
        amount: amount,
        transactionDate: payment.paidAt,
        note: payment.note,
        description: loan.name,
        loanId: loan.id,
        createdAt: createdAt,
        updatedAt: now,
      ),
    ).toJson();
    await txn.insert(
      'transactions',
      _row(json, createdAt, now),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _enqueue(
      txn,
      live ? SyncOperation.update : SyncOperation.create,
      'transactions',
      id,
      json,
      now,
    );
  }

  /// Sets the loan's `closed_at` to [closedAt] and queues the loan only when
  /// it changes; returns the loan as it now stands.
  Future<Loan> _writeClosed(
    DatabaseExecutor txn,
    Loan loan,
    DateTime? closedAt,
    DateTime now,
  ) async {
    final DateTime? old = loan.closedAt;
    final bool unchanged = old == null
        ? closedAt == null
        : closedAt != null && closedAt.isAtSameMomentAs(old);
    if (unchanged) return loan;
    final Loan updated = closedAt == null
        ? loan.copyWith(clearClosedAt: true, updatedAt: now)
        : loan.copyWith(closedAt: closedAt, updatedAt: now);
    await txn.update(
      'loans',
      <String, dynamic>{
        'closed_at': closedAt?.toUtc().toIso8601String(),
        'updated_at': now.toUtc().toIso8601String(),
        'sync_status': 'pending',
      },
      where: 'id = ?',
      whereArgs: <Object>[loan.id],
    );
    await _enqueue(
      txn,
      SyncOperation.update,
      'loans',
      loan.id,
      LoanModel.toJson(updated),
      now,
    );
    return updated;
  }

  /// The reminder of the loan's next due date (revived if it was
  /// tombstoned); tombstoned for a closed loan. A live reminder whose due
  /// date and amount are unchanged keeps its done / snooze state (a rename or
  /// note edit must not wake what the user silenced); one a payment moved
  /// starts afresh.
  Future<void> _syncReminder(
    DatabaseExecutor txn,
    Loan loan,
    LoanStatus status,
    DateTime now,
  ) async {
    final String reminderId = LoanIds.reminder(loan.id);
    final DateTime? due = loan.isClosed ? null : status.nextDueDate;
    if (due == null) {
      await _tombstoneLive(txn, 'reminders', 'id = ?', reminderId, now);
      return;
    }
    final List<Map<String, dynamic>> found = await txn.query(
      'reminders',
      columns: <String>[
        'created_at',
        'deleted_at',
        'remind_at',
        'amount',
        'is_completed',
        'snoozed_until',
      ],
      where: 'id = ?',
      whereArgs: <Object>[reminderId],
      limit: 1,
    );
    final Map<String, dynamic>? old = found.isEmpty ? null : found.first;
    final bool reminderLive = old != null && old['deleted_at'] == null;
    final DateTime createdAt = old == null
        ? now
        : DateTime.parse(old['created_at'] as String);
    final DateTime remindAt = DateTime(due.year, due.month, due.day, 9);
    final Decimal? amount = (status.nextAmount ?? Decimal.zero) > Decimal.zero
        ? status.nextAmount
        : null;
    final bool unchanged =
        reminderLive &&
        DateTime.parse(old['remind_at'] as String).isAtSameMomentAs(remindAt) &&
        (old['amount'] == null
            ? amount == null
            : amount != null &&
                  Decimal.parse(old['amount'].toString()) == amount);
    final bool isCompleted = unchanged && old['is_completed'] == 1;
    final DateTime? snoozedUntil = unchanged && old['snoozed_until'] != null
        ? DateTime.parse(old['snoozed_until'] as String)
        : null;
    final Map<String, dynamic> json = ReminderModel.toJson(
      Reminder(
        id: reminderId,
        userId: '',
        type: ReminderType.loan,
        title: loan.direction == LoanDirection.taken
            ? 'Loan payment due'.tr
            : 'Collect loan payment'.tr,
        description: loan.name,
        amount: amount,
        contactId: null,
        transactionId: null,
        loanId: loan.id,
        remindAt: remindAt,
        repeat: ReminderRepeat.none,
        isCompleted: isCompleted,
        notificationEnabled: true,
        snoozedUntil: snoozedUntil,
        createdAt: createdAt,
        updatedAt: now,
      ),
    );
    await txn.insert('reminders', <String, dynamic>{
      ...json,
      'is_completed': isCompleted ? 1 : 0,
      'notification_enabled': 1,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': now.toUtc().toIso8601String(),
      'deleted_at': null,
      'sync_status': 'pending',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await _enqueue(
      txn,
      reminderLive ? SyncOperation.update : SyncOperation.create,
      'reminders',
      reminderId,
      json,
      now,
    );
  }

  /// The loan's live payments, newest first.
  Future<List<LoanPayment>> _livePayments(
    DatabaseExecutor db,
    String loanId,
  ) async {
    final List<Map<String, dynamic>> rows = await db.query(
      'loan_payments',
      where: 'loan_id = ? AND deleted_at IS NULL',
      whereArgs: <Object>[loanId],
      orderBy: 'paid_at DESC, created_at DESC, id DESC',
    );
    return rows.map(LoanPaymentModel.fromJson).toList();
  }

  /// Soft-deletes every live row of [table] matching [where].
  Future<void> _tombstoneLive(
    DatabaseExecutor txn,
    String table,
    String where,
    String id,
    DateTime now,
  ) async {
    final int updated = await txn.update(
      table,
      <String, dynamic>{
        'deleted_at': now.toUtc().toIso8601String(),
        'updated_at': now.toUtc().toIso8601String(),
        'sync_status': 'pending',
      },
      where: '$where AND deleted_at IS NULL',
      whereArgs: <Object>[id],
    );
    if (updated == 0) return;
    await _enqueue(txn, SyncOperation.delete, table, id, tombstone(), now);
  }

  Future<List<String>> _liveIds(
    DatabaseExecutor txn,
    String table,
    String where,
    Object arg,
  ) async {
    final List<Map<String, dynamic>> rows = await txn.query(
      table,
      columns: <String>['id'],
      where: '$where AND deleted_at IS NULL',
      whereArgs: <Object>[arg],
    );
    return <String>[
      for (final Map<String, dynamic> r in rows) r['id'] as String,
    ];
  }
}
