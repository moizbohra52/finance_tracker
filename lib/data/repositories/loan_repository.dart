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
    final Loan? existing = await _loanOrNull(database.db, loan.id);
    final List<LoanPayment> payments = await _livePayments(
      database.db,
      loan.id,
    );
    if (existing != null &&
        payments.isNotEmpty &&
        termsChanged(existing, loan)) {
      throw const UnexpectedFailure(
        'Only the name, contact and note can change after a payment',
      );
    }
    final DateTime now = DateTime.now();
    final Loan saved = loan.copyWith(updatedAt: now);
    final bool isNew = existing == null || !existing.isLive;
    final String categoryKey = loan.direction == LoanDirection.taken
        ? 'loan_taken'
        : 'loan_given';
    final LoanStatus status = LoanCalculator.status(saved, payments);
    final DateTime? due = loan.isClosed ? null : status.nextDueDate;
    final String moneyId = LoanIds.loanRow(loan.id);
    final String reminderId = LoanIds.reminder(loan.id);

    await database.db.transaction((DatabaseExecutor txn) async {
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
        final List<Map<String, dynamic>> category = await txn.query(
          'categories',
          columns: <String>['id'],
          where: 'system_key = ? AND is_system = 1 AND deleted_at IS NULL',
          whereArgs: <Object>[categoryKey],
          limit: 1,
        );
        final Map<String, dynamic> json = TransactionModel.fromEntity(
          Transaction(
            id: moneyId,
            userId: '',
            accountId: saved.accountId,
            categoryId: category.isEmpty
                ? null
                : category.first['id'] as String,
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
      if (due == null) {
        await _tombstoneLive(txn, 'reminders', 'id = ?', reminderId, now);
      } else {
        final bool reminderLive = (await _liveIds(
          txn,
          'reminders',
          'id = ?',
          reminderId,
        )).isNotEmpty;
        final List<Map<String, dynamic>> old = await txn.query(
          'reminders',
          columns: <String>['created_at'],
          where: 'id = ?',
          whereArgs: <Object>[reminderId],
          limit: 1,
        );
        final DateTime createdAt = old.isEmpty
            ? now
            : DateTime.parse(old.first['created_at'] as String);
        final Map<String, dynamic> json = ReminderModel.toJson(
          Reminder(
            id: reminderId,
            userId: '',
            type: ReminderType.loan,
            title: saved.direction == LoanDirection.taken
                ? 'Loan payment due'.tr
                : 'Collect loan payment'.tr,
            description: saved.name,
            amount: status.nextAmount,
            contactId: null,
            transactionId: null,
            loanId: saved.id,
            remindAt: DateTime(due.year, due.month, due.day, 9),
            repeat: ReminderRepeat.none,
            isCompleted: false,
            notificationEnabled: true,
            snoozedUntil: null,
            createdAt: createdAt,
            updatedAt: now,
          ),
        );
        await txn.insert('reminders', <String, dynamic>{
          ...json,
          'is_completed': 0,
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
