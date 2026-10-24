import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/utils/submit_state.dart';
import 'package:finance_tracker/data/repositories/savings_goal_repository.dart';
import 'package:finance_tracker/domain/entities/savings_goal.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

/// Savings goal list, plus create, edit and delete.
class SavingsGoalController extends GetxController {
  SavingsGoalController(this._repository, this._notifier);

  final SavingsGoalRepository _repository;
  final DataChangeNotifier _notifier;

  static const Uuid _uuid = Uuid();

  final RxList<SavingsGoal> goals = <SavingsGoal>[].obs;
  final RxBool isLoading = true.obs;
  final RxnString error = RxnString();
  final SubmitState save = SubmitState();
  final SubmitState deletion = SubmitState();

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

  Future<void> load({bool silent = false}) async {
    if (!silent) isLoading.value = true;
    error.value = null;
    try {
      goals.assignAll(await _repository.getSavingsGoals());
    } on AppException catch (failure) {
      if (!silent || goals.isEmpty) error.value = failure.message;
    } finally {
      isLoading.value = false;
    }
  }

  /// [id] is generated once per form so a retried save upserts one row.
  Future<bool> saveGoal({
    required String id,
    SavingsGoal? existing,
    required String name,
    required Decimal targetAmount,
    required Decimal savedAmount,
    required DateTime? targetDate,
  }) => save.run(() async {
    final DateTime now = DateTime.now();
    final SavingsGoal goal = SavingsGoal(
      id: id,
      userId: existing?.userId ?? '',
      name: name.trim(),
      targetAmount: targetAmount,
      savedAmount: savedAmount,
      targetDate: targetDate,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    if (existing == null) {
      await _repository.createSavingsGoal(goal);
    } else {
      await _repository.updateSavingsGoal(goal);
    }
    _notifier.markChanged();
  });

  /// Adds [amount] to what is saved. The update stores the new total, so a
  /// retried save writes the same value instead of adding twice.
  Future<bool> addMoney(SavingsGoal goal, Decimal amount) => saveGoal(
    id: goal.id,
    existing: goal,
    name: goal.name,
    targetAmount: goal.targetAmount,
    savedAmount: goal.savedAmount + amount,
    targetDate: goal.targetDate,
  );

  Future<bool> deleteGoal(String goalId) => deletion.run(() async {
    await _repository.deleteSavingsGoal(goalId);
    _notifier.markChanged();
  });

  static String newId() => _uuid.v4();
}
