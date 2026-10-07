import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:get/get.dart';

/// Progress and error state for one user-triggered async action (a form
/// submit, a delete). Controllers hold one per action and views observe it.
class SubmitState {
  final RxBool isBusy = false.obs;
  final RxnString error = RxnString();

  /// Runs [action] unless one is already running. Returns true on success;
  /// on failure the user-facing message is in [error].
  Future<bool> run(Future<void> Function() action) async {
    if (isBusy.value) return false;
    error.value = null;
    isBusy.value = true;
    try {
      await action();
      return true;
    } on AppException catch (failure) {
      error.value = failure.message;
      return false;
    } finally {
      isBusy.value = false;
    }
  }
}
