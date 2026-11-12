import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/data/repositories/loan_repository.dart';
import 'package:finance_tracker/domain/entities/loan.dart';
import 'package:get/get.dart';

/// The loans list: Taken and Given segments over one loaded list.
class LoanListController extends GetxController {
  LoanListController(this._repository, this._notifier);

  final LoanRepository _repository;
  final DataChangeNotifier _notifier;

  final RxList<LoanSummary> loans = <LoanSummary>[].obs;
  final Rx<LoanDirection> direction = LoanDirection.taken.obs;
  final RxBool isLoading = true.obs;
  final RxnString error = RxnString();

  late final Worker _changes;

  /// Open loans of the current direction, in the repository's order.
  List<LoanSummary> get open => _current(closed: false);

  /// Closed loans of the current direction, latest closed first.
  List<LoanSummary> get closed => _current(closed: true);

  /// What is still owed on the open loans of the current direction.
  Decimal get totalOutstanding => open.fold(
    Decimal.zero,
    (Decimal sum, LoanSummary s) => sum + s.status.outstanding,
  );

  List<LoanSummary> _current({required bool closed}) => loans
      .where(
        (LoanSummary s) =>
            s.loan.direction == direction.value && s.loan.isClosed == closed,
      )
      .toList();

  @override
  void onInit() {
    super.onInit();
    load();
    _changes = ever<int>(_notifier.version, (_) => load(silent: true));
  }

  @override
  void onClose() {
    _changes.dispose();
    super.onClose();
  }

  Future<void> load({bool silent = false}) async {
    if (!silent) isLoading.value = true;
    error.value = null;
    try {
      loans.assignAll(await _repository.getLoans());
    } on AppException catch (failure) {
      if (!silent || loans.isEmpty) error.value = failure.message;
    } finally {
      isLoading.value = false;
    }
  }
}
