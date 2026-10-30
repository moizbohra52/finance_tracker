import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/utils/submit_state.dart';
import 'package:finance_tracker/data/repositories/account_repository.dart';
import 'package:finance_tracker/data/repositories/category_repository.dart';
import 'package:finance_tracker/data/repositories/contact_repository.dart';
import 'package:finance_tracker/data/repositories/split_repository.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/category.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/split.dart';
import 'package:finance_tracker/domain/services/split_calculator.dart';
import 'package:finance_tracker/domain/services/split_ids.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

/// The split expense form's draft state. All maths lives in the getters; the
/// view only renders them (CLAUDE.md: no accounting math in widgets).
class SplitExpenseController extends GetxController {
  SplitExpenseController(
    this._repository,
    this._accountsRepository,
    this._categoriesRepository,
    this._contactsRepository,
    this._notifier,
  );

  final SplitRepository _repository;
  final AccountRepository _accountsRepository;
  final CategoryRepository _categoriesRepository;
  final ContactRepository _contactsRepository;
  final DataChangeNotifier _notifier;

  static const Uuid _uuid = Uuid();

  final RxList<SplitMember> members = <SplitMember>[].obs;
  final RxList<Account> accounts = <Account>[].obs;
  final RxList<Category> categories = <Category>[].obs;
  final RxList<Contact> contacts = <Contact>[].obs;
  final Rx<SplitMode> mode = SplitMode.equal.obs;

  /// The typed paid amount per member id; a blank string counts as 0.
  final RxMap<String, String> paidText = <String, String>{}.obs;

  /// The typed tick/amount/percent/share per member id, by mode.
  final RxMap<String, String> inputText = <String, String>{}.obs;

  /// The members sharing equally (equal mode).
  final RxSet<String> ticked = <String>{}.obs;

  final RxString totalText = ''.obs;
  final RxnString categoryId = RxnString();
  final RxnString accountId = RxnString();

  /// False shows the single-payer selector ([payerId]).
  final RxBool multiplePayers = false.obs;
  final RxString payerId = ''.obs;

  final SubmitState save = SubmitState();
  final SubmitState deletion = SubmitState();

  /// The group and expense being edited (null on create).
  String _groupId = '';
  SplitExpenseDetail? _existing;

  /// Loads the group's members, the accounts, categories and contacts, and
  /// prefills from [existing] when editing.
  Future<void> start({
    required String groupId,
    SplitExpenseDetail? existing,
  }) async {
    _groupId = groupId;
    _existing = existing;
    members.assignAll(await _repository.getMembers(groupId));
    contacts.assignAll(await _contactsRepository.getContacts());
    try {
      final String? current = existing?.expense.accountId;
      accounts.assignAll(
        (await _accountsRepository.getAccounts()).where(
          (Account a) => a.isActive || a.id == current,
        ),
      );
      categories.assignAll(await _categoriesRepository.getCategories());
    } on AppException {
      // The pickers simply stay empty; validate() then asks for one.
    }
    mode.value = existing?.expense.splitMode ?? SplitMode.equal;
    totalText.value = existing == null
        ? ''
        : _trimZeros(existing.expense.totalAmount);
    categoryId.value = existing?.expense.categoryId;
    accountId.value = existing?.expense.accountId;
    multiplePayers.value = false;
    String meMemberId = '';
    for (final SplitMember m in members) {
      if (m.isMe) meMemberId = m.id;
    }
    payerId.value = meMemberId;
    paidText.assignAll(<String, String>{
      for (final SplitMember m in members) m.id: '',
    });
    inputText.assignAll(<String, String>{
      for (final SplitMember m in members) m.id: '',
    });
    ticked.assignAll(<String>{
      for (final SplitMember m in members)
        if ((existing == null
            ? m.isMe
            : _shareOf(existing, m.id) > Decimal.zero))
          m.id,
    });
    if (existing != null) {
      for (final SplitPart p in existing.parts) {
        if (p.paidAmount > Decimal.zero) {
          paidText[p.memberId] = _trimZeros(p.paidAmount);
          if (p.memberId != payerId.value) multiplePayers.value = true;
        }
        if (p.shareInput != null) {
          inputText[p.memberId] = _trimZeros(p.shareInput!);
        }
      }
    }
  }

  Decimal _shareOf(SplitExpenseDetail existing, String memberId) {
    for (final SplitPart p in existing.parts) {
      if (p.memberId == memberId) return p.shareAmount;
    }
    return Decimal.zero;
  }

  static String _trimZeros(Decimal v) => v.toString();

  Decimal? get total {
    final String text = totalText.value.trim();
    if (text.isEmpty) return null;
    return Decimal.tryParse(text);
  }

  Map<String, Decimal> get paid => <String, Decimal>{
    for (final SplitMember m in members)
      m.id: multiplePayers.value
          ? (Decimal.tryParse(paidText[m.id] ?? '') ?? Decimal.zero)
          : (m.id == payerId.value ? (total ?? Decimal.zero) : Decimal.zero),
  };

  Map<String, Decimal> get inputs => <String, Decimal>{
    for (final SplitMember m in members)
      m.id: mode.value == SplitMode.equal
          ? (ticked.contains(m.id) ? Decimal.one : Decimal.zero)
          : (Decimal.tryParse(inputText[m.id] ?? '') ?? Decimal.zero),
  };

  /// The share of every member, from the current mode and inputs.
  Map<String, Decimal> get shares {
    final Decimal? t = total;
    if (t == null) return const <String, Decimal>{};
    return SplitCalculator.sharesFor(mode.value, t, inputs);
  }

  /// The first broken rule, or null while the form is incomplete or valid.
  String? get error {
    final Decimal? t = total;
    if (t == null) return null;
    final Map<String, Decimal> sharesNow = shares;
    if (sharesNow.isEmpty) return null;
    return SplitCalculator.validateInputs(mode.value, t, inputs) ??
        SplitCalculator.validate(
          total: t,
          paid: paid,
          shares: sharesNow,
          meId: _meId,
          categoryId: categoryId.value,
          accountId: accountId.value,
        );
  }

  String get _meId {
    for (final SplitMember m in members) {
      if (m.isMe) return m.id;
    }
    return '';
  }

  String memberName(SplitMember m) => memberNameById(m.id);

  /// The display name of a member: the user, the contact's name, or
  /// "Deleted contact".
  String memberNameById(String memberId) {
    for (final SplitMember m in members) {
      if (m.id != memberId) continue;
      if (m.isMe) return 'You'.tr;
      for (final Contact contact in contacts) {
        if (contact.id == m.contactId) return contact.name;
      }
      return 'Deleted contact'.tr;
    }
    return 'Deleted contact'.tr;
  }

  /// In exact/percent/shares modes: how much of the total is still unassigned.
  Decimal get paidLeft {
    final Decimal? t = total;
    if (t == null) return Decimal.zero;
    final Decimal assigned = paid.values.fold(
      Decimal.zero,
      (Decimal a, Decimal b) => a + b,
    );
    return t - assigned;
  }

  Decimal get sharesLeft {
    final Decimal? t = total;
    if (t == null) return Decimal.zero;
    if (mode.value == SplitMode.equal) return Decimal.zero;
    if (mode.value == SplitMode.exact) {
      final Decimal assigned = shares.values.fold(
        Decimal.zero,
        (Decimal a, Decimal b) => a + b,
      );
      return t - assigned;
    }
    if (mode.value == SplitMode.percent) {
      final Decimal assigned = inputs.values.fold(
        Decimal.zero,
        (Decimal a, Decimal b) => a + b,
      );
      return Decimal.fromInt(100) - assigned;
    }
    return Decimal.zero;
  }

  /// The live preview: the user's share and what they get (positive) or owe.
  ({Decimal yourShare, Decimal youGet})? get preview {
    final Decimal? t = total;
    if (t == null) return null;
    final Map<String, Decimal> sharesNow = shares;
    if (sharesNow.isEmpty) return null;
    final SplitUserRows rows = SplitCalculator.userRows(
      total: t,
      meId: _meId,
      paid: paid,
      shares: sharesNow,
    );
    final Decimal signed = rows.balanceIsPaidForOthers
        ? rows.balanceAmount
        : -rows.balanceAmount;
    return (yourShare: rows.expenseShare, youGet: signed);
  }

  /// [id] is generated once per form so a retried save upserts one row.
  /// Invalid input is refused here and nothing is stored.
  Future<bool> saveExpense({
    required String id,
    required String title,
    required DateTime date,
    required String? note,
  }) {
    final Decimal? t = total;
    final Map<String, Decimal> sharesNow = shares;
    return save.run(() async {
      if (t == null || t <= Decimal.zero) {
        throw const UnexpectedFailure('Amount must be more than zero');
      }
      final String? problem = error;
      if (problem != null) throw UnexpectedFailure(problem);
      final DateTime now = DateTime.now();
      final SplitExpense expense = SplitExpense(
        id: id,
        userId: '',
        groupId: _groupId,
        title: title.trim(),
        totalAmount: t,
        expenseDate: date,
        splitMode: mode.value,
        categoryId: categoryId.value,
        accountId: accountId.value,
        note: (note ?? '').trim().isEmpty ? null : note!.trim(),
        createdAt: _existing?.expense.createdAt ?? now,
        updatedAt: now,
      );
      final List<SplitPart> parts = <SplitPart>[
        for (final MapEntry<String, Decimal> e in sharesNow.entries)
          if (paid[e.key]! > Decimal.zero ||
              e.value > Decimal.zero ||
              (inputs[e.key] ?? Decimal.zero) > Decimal.zero)
            SplitPart(
              id: SplitIds.part(id, e.key),
              userId: '',
              splitExpenseId: id,
              memberId: e.key,
              paidAmount: paid[e.key]!,
              shareAmount: e.value,
              shareInput: mode.value == SplitMode.equal ? null : inputs[e.key],
              createdAt: now,
              updatedAt: now,
            ),
      ];
      await _repository.saveExpense(expense: expense, parts: parts);
      _notifier.markChanged();
    });
  }

  Future<bool> deleteExpense(String id) => deletion.run(() async {
    await _repository.deleteExpense(id);
    _notifier.markChanged();
  });

  static String newId() => _uuid.v4();
}

/// Arguments of `/split-expense-form`.
class SplitExpenseArgs {
  const SplitExpenseArgs({required this.groupId, this.existing});

  final String groupId;

  /// Set when editing an existing expense.
  final SplitExpenseDetail? existing;
}
