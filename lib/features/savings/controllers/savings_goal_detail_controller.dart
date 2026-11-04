import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/utils/submit_state.dart';
import 'package:finance_tracker/data/repositories/savings_goal_repository.dart';
import 'package:finance_tracker/domain/entities/savings_contribution.dart';
import 'package:get/get.dart';

/// One savings goal's history, paged, newest first. The goal itself comes
/// from SavingsGoalController, which reloads it after every change.
class SavingsGoalDetailController extends GetxController {
  SavingsGoalDetailController(this._repository, this._notifier, this.goalId);

  final SavingsGoalRepository _repository;
  final DataChangeNotifier _notifier;
  final String goalId;

  static const int pageSize = 50;

  final RxList<SavingsHistoryEntry> history = <SavingsHistoryEntry>[].obs;
  final RxBool isLoading = true.obs;
  final RxBool isLoadingMore = false.obs;
  final RxBool hasMore = false.obs;
  final RxnString error = RxnString();
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

  /// Reloads as many entries as are shown (at least one page), so a change
  /// does not collapse a list the user has paged through.
  Future<void> load({bool silent = false}) async {
    if (!silent) isLoading.value = true;
    error.value = null;
    try {
      final int shown = history.length > pageSize ? history.length : pageSize;
      final List<SavingsHistoryEntry> rows = await _repository.getHistory(
        goalId,
        limit: shown,
      );
      history.assignAll(rows);
      hasMore.value = rows.length >= shown;
    } on AppException catch (failure) {
      if (!silent || history.isEmpty) error.value = failure.message;
    } finally {
      isLoading.value = false;
    }
  }

  /// Appends the next page; [hasMore] turns false at the end.
  Future<void> loadMore() async {
    if (isLoadingMore.value || !hasMore.value) return;
    isLoadingMore.value = true;
    try {
      final List<SavingsHistoryEntry> page = await _repository.getHistory(
        goalId,
        offset: history.length,
        limit: pageSize,
      );
      history.addAll(page);
      hasMore.value = page.length >= pageSize;
    } on AppException catch (failure) {
      error.value = failure.message;
    } finally {
      isLoadingMore.value = false;
    }
  }

  /// Removes money added by hand; the goal's total drops with it.
  Future<bool> deleteEntry(String contributionId) => deletion.run(() async {
    await _repository.deleteContribution(contributionId);
    _notifier.markChanged();
  });
}
