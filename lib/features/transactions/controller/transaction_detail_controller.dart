import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/data/repositories/transaction_repository.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:get/get.dart';

/// Loads one transaction by id for the detail route.
class TransactionDetailController extends GetxController {
  TransactionDetailController(
    this._repository,
    this._notifier,
    this.transactionId,
  );

  final TransactionRepository _repository;
  final DataChangeNotifier _notifier;
  final String transactionId;

  final Rxn<Transaction> transaction = Rxn<Transaction>();
  final RxBool isLoading = true.obs;
  final RxnString error = RxnString();

  @override
  void onInit() {
    super.onInit();
    load();
    // Reload after an edit made from this screen.
    ever<int>(_notifier.version, (_) => load(silent: true));
  }

  Future<void> load({bool silent = false}) async {
    if (!silent) isLoading.value = true;
    error.value = null;
    try {
      final Transaction loaded = await _repository.getTransactionById(
        transactionId,
      );
      // A soft-deleted row is gone as far as the user is concerned.
      transaction.value = loaded.deletedAt == null ? loaded : null;
    } on AppException catch (failure) {
      if (!silent) error.value = failure.message;
    } finally {
      isLoading.value = false;
    }
  }
}
