import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/utils/submit_state.dart';
import 'package:finance_tracker/data/repositories/account_repository.dart';
import 'package:finance_tracker/data/repositories/contact_repository.dart';
import 'package:finance_tracker/data/repositories/split_repository.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/split.dart';
import 'package:finance_tracker/domain/services/split_balances.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

/// The settle-up form's draft state.
class SplitSettlementController extends GetxController {
  SplitSettlementController(
    this._repository,
    this._accountsRepository,
    this._contactsRepository,
    this._notifier,
  );

  final SplitRepository _repository;
  final AccountRepository _accountsRepository;
  final ContactRepository _contactsRepository;
  final DataChangeNotifier _notifier;

  static const Uuid _uuid = Uuid();

  final RxList<SplitMember> members = <SplitMember>[].obs;
  final RxList<Account> accounts = <Account>[].obs;
  final RxList<Contact> contacts = <Contact>[].obs;
  final RxnString fromId = RxnString();
  final RxnString toId = RxnString();
  final RxString amountText = ''.obs;
  final RxnString accountId = RxnString();
  final SubmitState save = SubmitState();
  final SubmitState deletion = SubmitState();

  String _groupId = '';
  SplitSettlement? _existing;

  /// Loads members and accounts, prefills the outstanding amount between
  /// [fromMemberId] and [toMemberId] (or the edited [existing] settlement).
  Future<void> start({
    required String groupId,
    SplitSettlement? existing,
    String? fromMemberId,
    String? toMemberId,
  }) async {
    _groupId = groupId;
    _existing = existing;
    members.assignAll(await _repository.getMembers(groupId));
    contacts.assignAll(await _contactsRepository.getContacts());
    try {
      accounts.assignAll(await _accountsRepository.getAccounts());
    } on AppException {
      // The picker stays empty; the save then fails with a clear message.
    }
    if (existing != null) {
      fromId.value = existing.fromMemberId;
      toId.value = existing.toMemberId;
      amountText.value = existing.amount.toString();
      accountId.value = existing.accountId;
      return;
    }
    fromId.value = fromMemberId ?? _meId();
    toId.value = toMemberId;
    if (fromId.value != null && toId.value != null) {
      final SplitGroupDetail detail = await _repository.getGroupDetail(groupId);
      final Decimal outstanding = detail.balances.pairs
          .where(
            (PairBalance p) =>
                p.debtorMemberId == fromId.value &&
                p.creditorMemberId == toId.value,
          )
          .map((PairBalance p) => p.amount)
          .fold(Decimal.zero, (Decimal a, Decimal b) => a + b);
      amountText.value = outstanding > Decimal.zero
          ? outstanding.toString()
          : '';
    } else {
      amountText.value = '';
    }
    accountId.value = null;
  }

  bool get userIsParty {
    final SplitMember? from = _member(fromId.value);
    final SplitMember? to = _member(toId.value);
    return from?.isMe == true || to?.isMe == true;
  }

  /// The display name of a member: the user, the contact's name, or
  /// "Deleted contact".
  String memberNameById(String memberId) {
    final SplitMember? member = _member(memberId);
    if (member == null) return 'Deleted contact'.tr;
    if (member.isMe) return 'You'.tr;
    for (final Contact contact in contacts) {
      if (contact.id == member.contactId) return contact.name;
    }
    return 'Deleted contact'.tr;
  }

  String? _meId() {
    for (final SplitMember m in members) {
      if (m.isMe) return m.id;
    }
    return null;
  }

  SplitMember? _member(String? memberId) {
    for (final SplitMember m in members) {
      if (m.id == memberId) return m;
    }
    return null;
  }

  /// True when the two chosen members are both friends (no khata write).
  bool get _friendToFriend {
    final SplitMember? from = _member(fromId.value);
    final SplitMember? to = _member(toId.value);
    return from != null && to != null && !from.isMe && !to.isMe;
  }

  /// [id] is generated once per form so a retried save upserts one row.
  Future<bool> saveSettlement({
    required String id,
    required DateTime date,
    required String? note,
  }) {
    return save.run(() async {
      final Decimal? amount = Decimal.tryParse(amountText.value.trim());
      if (fromId.value == null ||
          toId.value == null ||
          fromId.value == toId.value) {
        throw const UnexpectedFailure('Choose two different people');
      }
      if (amount == null || amount <= Decimal.zero) {
        throw const UnexpectedFailure('Amount must be more than zero');
      }
      final DateTime now = DateTime.now();
      final SplitSettlement settlement = SplitSettlement(
        id: id,
        userId: '',
        groupId: _groupId,
        fromMemberId: fromId.value!,
        toMemberId: toId.value!,
        amount: amount,
        settledAt: date,
        accountId: _friendToFriend ? null : accountId.value,
        note: (note ?? '').trim().isEmpty ? null : note!.trim(),
        createdAt: _existing?.createdAt ?? now,
        updatedAt: now,
      );
      await _repository.saveSettlement(settlement);
      _notifier.markChanged();
    });
  }

  Future<bool> deleteSettlement(String id) => deletion.run(() async {
    await _repository.deleteSettlement(id);
    _notifier.markChanged();
  });

  static String newId() => _uuid.v4();
}
