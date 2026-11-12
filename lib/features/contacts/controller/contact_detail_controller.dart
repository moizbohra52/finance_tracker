import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/services/export_service.dart';
import 'package:finance_tracker/core/services/file_sharing_service.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/utils/parallel.dart';
import 'package:finance_tracker/core/utils/submit_state.dart';
import 'package:finance_tracker/data/repositories/contact_repository.dart';
import 'package:finance_tracker/data/repositories/loan_repository.dart';
import 'package:finance_tracker/data/repositories/profile_repository.dart';
import 'package:finance_tracker/data/repositories/reminder_repository.dart';
import 'package:finance_tracker/data/repositories/split_repository.dart';
import 'package:finance_tracker/data/repositories/transaction_repository.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/services/khata_due_reminders.dart';
import 'package:finance_tracker/features/contacts/controller/contact_form_controller.dart';
import 'package:finance_tracker/features/contacts/services/reminder_sender_service.dart';
import 'package:finance_tracker/features/split/controllers/split_expense_controller.dart';
import 'package:finance_tracker/features/split/views/split_settlement_form_view.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

/// One contact, their ledger entries and current balance.
class ContactDetailController extends GetxController {
  ContactDetailController(
    this._repository,
    this._transactionRepository,
    this._notifier,
    this.contactId, {
    ProfileRepository? profileRepository,
    this._splitRepository,
    ReminderRepository? reminderRepository,
    LoanRepository? loanRepository,
    this.exportService = const ExportService(),
    this.sharingService = const FileSharingService(),
  }) : _profiles = profileRepository,
       _reminders = reminderRepository,
       _loans = loanRepository;

  final ContactRepository _repository;
  final TransactionRepository _transactionRepository;
  final DataChangeNotifier _notifier;
  final String contactId;
  final ProfileRepository? _profiles;

  /// Null where split groups are not available (tests without them).
  final SplitRepository? _splitRepository;

  /// Removes an entry's due-date reminder with it; null in tests.
  final ReminderRepository? _reminders;

  /// Lists the contact's loans; null in tests that do not need them.
  final LoanRepository? _loans;
  final ExportService exportService;
  final FileSharingService sharingService;

  static const int pageSize = 30;

  final Rxn<Contact> contact = Rxn<Contact>();

  /// The loaded pages of the ledger, newest first. The balance, the
  /// statement and a contact delete read the whole ledger themselves.
  final RxList<ContactTransaction> entries = <ContactTransaction>[].obs;
  final Rx<Decimal> balance = Decimal.zero.obs;

  /// The contact's loans. They are not part of [balance].
  final RxList<LoanSummary> loans = <LoanSummary>[].obs;
  final RxBool isLoading = true.obs;
  final RxBool isLoadingMore = false.obs;
  final RxBool hasMore = true.obs;
  final RxnString error = RxnString();
  final SubmitState deletion = SubmitState();
  final SubmitState statement = SubmitState();

  /// The split group behind derived entries, keyed by expense/settlement id.
  final RxMap<String, SplitLink> splitLinks = <String, SplitLink>{}.obs;

  /// The group behind [entry], or null for a plain ledger entry. Always
  /// touches [splitLinks], so Obx tiles stay subscribed even for plain rows.
  SplitLink? linkOf(ContactTransaction entry) {
    splitLinks.length;
    final String? id = entry.splitExpenseId ?? entry.splitSettlementId;
    return id == null ? null : splitLinks[id];
  }

  /// Opens the split expense or settlement form behind a derived entry.
  Future<void> openInGroup(ContactTransaction entry) async {
    final SplitRepository? repository = _splitRepository;
    final String? id = entry.splitExpenseId ?? entry.splitSettlementId;
    if (repository == null || id == null) return;
    final bool isSettlement = entry.splitSettlementId != null;
    final Map<String, SplitLink> links = await repository.getLinks(
      expenseIds: <String>[if (!isSettlement) id],
      settlementIds: <String>[if (isSettlement) id],
    );
    final SplitLink? link = links[id];
    if (link == null) return;
    if (isSettlement) {
      await Get.toNamed<void>(
        AppRoutes.splitSettlementForm,
        arguments: SplitSettlementArgs(
          groupId: link.groupId,
          existing: await repository.getSettlement(id),
        ),
      );
    } else {
      await Get.toNamed<void>(
        AppRoutes.splitExpenseForm,
        arguments: SplitExpenseArgs(
          groupId: link.groupId,
          existing: await repository.getExpense(id),
        ),
      );
    }
  }

  // GetX does not dispose workers, and the notifier outlives this
  // controller, so without this a closed controller keeps reloading.
  late final Worker _changes;

  @override
  void onClose() {
    _changes.dispose();
    super.onClose();
  }

  @override
  void onInit() {
    super.onInit();
    load();
    _changes = ever<int>(_notifier.version, (_) => load(silent: true));
  }

  int _generation = 0;

  Future<void> load({bool silent = false}) async {
    final int generation = ++_generation;
    if (!silent) isLoading.value = true;
    error.value = null;
    // A silent reload refetches every entry already on screen, so the list
    // does not jump back to the first page after an edit.
    final int limit = silent && entries.length > pageSize
        ? entries.length
        : pageSize;
    try {
      final (
        Contact loaded,
        List<ContactTransaction> page,
        Decimal total,
      ) = await wait3(
        _repository.getContactById(contactId),
        _repository.getContactTransactions(contactId, limit: limit),
        _repository.getEntriesTotal(contactId),
      );
      if (generation != _generation) return;
      await _loadLoans();
      if (generation != _generation) return;
      contact.value = loaded.deletedAt == null ? loaded : null;
      entries.assignAll(page);
      hasMore.value = page.length == limit;
      balance.value = loaded.balanceWith(total);
      _loadSplitLinks(page);
    } on AppException catch (failure) {
      if (!silent && generation == _generation) error.value = failure.message;
    } finally {
      if (generation == _generation) isLoading.value = false;
    }
  }

  /// The loans are a side section: a failure keeps the ones shown and does
  /// not hide the ledger.
  Future<void> _loadLoans() async {
    final LoanRepository? repository = _loans;
    if (repository == null) return;
    try {
      loans.assignAll(await repository.getLoansForContact(contactId));
    } on AppException {
      // Keep what is shown; the next reload retries.
    }
  }

  Future<void> loadMore() async {
    if (isLoading.value || isLoadingMore.value || !hasMore.value) return;
    final int generation = _generation;
    isLoadingMore.value = true;
    try {
      final List<ContactTransaction> page = await _repository
          .getContactTransactions(
            contactId,
            limit: pageSize,
            offset: entries.length,
          );
      if (generation != _generation) return;
      entries.addAll(page);
      hasMore.value = page.length == pageSize;
      _loadSplitLinks(page);
    } on AppException {
      // The entries already shown stay; scrolling again retries.
    } finally {
      isLoadingMore.value = false;
    }
  }

  void _loadSplitLinks(List<ContactTransaction> list) {
    final SplitRepository? repository = _splitRepository;
    if (repository == null) return;
    final List<String> expenseIds = <String>[
      for (final ContactTransaction e in list)
        if (e.splitExpenseId != null) e.splitExpenseId!,
    ];
    final List<String> settlementIds = <String>[
      for (final ContactTransaction e in list)
        if (e.splitSettlementId != null) e.splitSettlementId!,
    ];
    if (expenseIds.isEmpty && settlementIds.isEmpty) return;
    repository
        .getLinks(expenseIds: expenseIds, settlementIds: settlementIds)
        .then((Map<String, SplitLink> links) {
          splitLinks.addAll(links);
        })
        .catchError((Object _) {});
  }

  /// Builds this contact's statement PDF and opens the share sheet. When
  /// they owe the user and a UPI ID is set, the PDF carries a pay QR.
  Future<bool> shareStatement() => statement.run(() async {
    final Contact? current = contact.value;
    if (current == null) return;
    String? userName;
    try {
      userName = (await _profiles?.fetchProfile())?.fullName;
    } on Object {
      // The name is optional: the statement then says "From: You".
    }
    try {
      final List<int> bytes = await exportService.generateContactStatementPdf(
        contact: current,
        // The whole ledger, not just the pages on screen.
        entries: await _repository.getContactTransactions(contactId),
        userName: userName,
        upiPayLink: ReminderSenderService.buildUpiLink(
          upiId: AppFormatters.preferences.upiId,
          amount: balance.value,
          payeeName: userName,
        ),
        currencyCode: AppFormatters.preferences.currencyCode,
      );
      final String safeName = current.name
          .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '_')
          .replaceAll(RegExp(r'^_+|_+$'), '');
      final String date = DateFormat('yyyy-MM-dd').format(DateTime.now());
      await sharingService.saveAndShareBytes(
        fileName: 'Khata_${safeName}_$date.pdf',
        bytes: bytes,
        mimeType: 'application/pdf',
        subject: 'Khata statement - @name'.trParams(<String, String>{
          'name': current.name,
        }),
      );
    } on AppException {
      rethrow;
    } on Object {
      // PDF or file errors are not AppExceptions; show the generic message.
      throw const UnexpectedFailure();
    }
  });

  Future<bool> deleteContact() => deletion.run(() async {
    // A live group member keeps the group's balances exact; the contact can
    // only go once they are out of every group.
    final SplitRepository? repository = _splitRepository;
    if (repository != null) {
      final String? groupName = await repository.groupNameBlockingContactDelete(
        contactId,
      );
      if (groupName != null) {
        throw UnexpectedFailure(
          '@name is in the group @group. Remove them from the group first.'
              .trParams(<String, String>{
                'name': contact.value?.name ?? '',
                'group': groupName,
              }),
        );
      }
    }
    // Every entry, not just the pages on screen.
    for (final ContactTransaction e in await _repository.getContactTransactions(
      contactId,
    )) {
      // As deleteEntry does: the entry goes too, or it lingers in exports
      // and backups under a contact that no longer exists.
      await _repository.deleteContactTransaction(e.id);
      if (e.dueDate != null) {
        await _reminders?.delete(KhataDueReminders.id(e.id));
      }
      try {
        final String txId = ContactFormController.linkedTransactionId(e.id);
        await _transactionRepository.deleteTransaction(txId);
      } catch (_) {}
    }
    await _repository.deleteContact(contactId);
    _notifier.markChanged();
  });

  /// Saves the photo's object name (null removes it); the reload that the
  /// change notice starts shows it.
  Future<void> setPhoto(String? avatarPath) async {
    await _repository.setPhoto(contactId, avatarPath);
    _notifier.markChanged();
  }

  Future<bool> deleteEntry(String entryId) => deletion.run(() async {
    final ContactTransaction? entry = entries.firstWhereOrNull(
      (ContactTransaction e) => e.id == entryId,
    );
    if (entry != null && entry.isSplitDerived) {
      throw const UnexpectedFailure(
        'Open it in the group to change or delete it',
      );
    }
    await _repository.deleteContactTransaction(entryId);
    if (entry?.dueDate != null) {
      await _reminders?.delete(KhataDueReminders.id(entryId));
    }
    try {
      final String txId = ContactFormController.linkedTransactionId(entryId);
      await _transactionRepository.deleteTransaction(txId);
    } catch (_) {}
    _notifier.markChanged();
  });
}
