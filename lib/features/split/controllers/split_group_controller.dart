import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/utils/submit_state.dart';
import 'package:finance_tracker/data/repositories/contact_repository.dart';
import 'package:finance_tracker/data/repositories/split_repository.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/split.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

/// The groups list plus create, edit and delete.
class SplitGroupController extends GetxController {
  SplitGroupController(
    this._repository,
    this._contactsRepository,
    this._notifier,
  );

  final SplitRepository _repository;
  final ContactRepository _contactsRepository;
  final DataChangeNotifier _notifier;

  static const Uuid _uuid = Uuid();

  final RxList<SplitGroupSummary> groups = <SplitGroupSummary>[].obs;
  final RxBool isLoading = true.obs;
  final RxnString error = RxnString();

  /// Khata contacts for the member picker.
  final RxList<Contact> contacts = <Contact>[].obs;
  final SubmitState save = SubmitState();
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
      groups.assignAll(await _repository.getGroups());
      contacts.assignAll(await _contactsRepository.getContacts());
    } on AppException catch (failure) {
      if (!silent || groups.isEmpty) error.value = failure.message;
    } finally {
      isLoading.value = false;
    }
  }

  /// The display name of a member's contact: the user, the contact's name,
  /// or "Deleted contact" when the contact is gone.
  String contactName(String? contactId) {
    if (contactId == null) return 'You'.tr;
    for (final Contact contact in contacts) {
      if (contact.id == contactId) return contact.name;
    }
    return 'Deleted contact'.tr;
  }

  /// [groupId] is generated once per form so a retried save upserts one row.
  Future<bool> saveGroup({
    required String groupId,
    required String name,
    required List<String> friendContactIds,
  }) => save.run(() async {
    await _repository.saveGroup(
      groupId: groupId,
      name: name,
      friendContactIds: friendContactIds,
    );
    _notifier.markChanged();
  });

  Future<bool> deleteGroup(String groupId) => deletion.run(() async {
    await _repository.deleteGroup(groupId);
    _notifier.markChanged();
  });

  /// The members of a saved group, for the edit form's prefill.
  Future<List<SplitMember>> membersOf(String groupId) =>
      _repository.getMembers(groupId);

  Future<({int expenses, int khataEntries})> deleteImpact(String groupId) =>
      _repository.getGroupDeleteImpact(groupId);

  static String newId() => _uuid.v4();
}
