import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/utils/submit_state.dart';
import 'package:finance_tracker/data/repositories/contact_repository.dart';
import 'package:finance_tracker/data/repositories/split_repository.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/split.dart';
import 'package:finance_tracker/domain/services/split_balances.dart';
import 'package:get/get.dart';

/// One group's detail: header totals, balances and a paged activity feed.
class SplitGroupDetailController extends GetxController {
  SplitGroupDetailController(
    this._repository,
    this._contactsRepository,
    this._notifier,
    this.groupId,
  );

  final SplitRepository _repository;
  final ContactRepository _contactsRepository;
  final DataChangeNotifier _notifier;
  final String groupId;

  static const int _pageSize = 50;

  final Rxn<SplitGroupDetail> detail = Rxn<SplitGroupDetail>();
  final RxList<SplitActivityItem> activity = <SplitActivityItem>[].obs;
  final RxBool isLoading = true.obs;
  final RxBool isLoadingMore = false.obs;
  final RxBool hasMore = false.obs;
  final RxnString error = RxnString();
  final RxList<Contact> contacts = <Contact>[].obs;
  final SubmitState deletion = SubmitState();

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

  Future<void> load({bool silent = false}) async {
    if (!silent) isLoading.value = true;
    error.value = null;
    try {
      detail.value = await _repository.getGroupDetail(groupId);
      activity.assignAll(await _repository.getActivity(groupId));
      hasMore.value = activity.length >= _pageSize;
      contacts.assignAll(await _contactsRepository.getContacts());
    } on AppException catch (failure) {
      if (!silent || detail.value == null) error.value = failure.message;
    } finally {
      isLoading.value = false;
    }
  }

  /// Appends the next page of activity; [hasMore] turns false at the end.
  Future<void> loadMore() async {
    if (isLoadingMore.value || !hasMore.value) return;
    isLoadingMore.value = true;
    try {
      final List<SplitActivityItem> page = await _repository.getActivity(
        groupId,
        offset: activity.length,
      );
      activity.addAll(page);
      hasMore.value = page.length >= _pageSize;
    } on AppException catch (failure) {
      error.value = failure.message;
    } finally {
      isLoadingMore.value = false;
    }
  }

  String memberName(SplitMember m) => memberNameById(m.id);

  String memberNameById(String memberId) {
    SplitMember? member;
    for (final SplitMember m
        in detail.value?.members ?? const <SplitMember>[]) {
      if (m.id == memberId) member = m;
    }
    if (member == null) return 'Deleted contact'.tr;
    if (member.isMe) return 'You'.tr;
    for (final Contact contact in contacts) {
      if (contact.id == member.contactId) return contact.name;
    }
    return 'Deleted contact'.tr;
  }

  /// How much [fromMemberId] owes [toMemberId]; 0 when they do not.
  Decimal outstanding(String fromMemberId, String toMemberId) {
    for (final PairBalance pair
        in detail.value?.balances.pairs ?? const <PairBalance>[]) {
      if (pair.debtorMemberId == fromMemberId &&
          pair.creditorMemberId == toMemberId) {
        return pair.amount;
      }
    }
    return Decimal.zero;
  }

  Future<bool> deleteGroup() => deletion.run(() async {
    await _repository.deleteGroup(groupId);
    _notifier.markChanged();
  });
}
