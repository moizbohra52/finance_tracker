import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/utils/submit_state.dart';
import 'package:finance_tracker/data/repositories/loan_repository.dart';
import 'package:finance_tracker/domain/entities/loan.dart';
import 'package:finance_tracker/domain/services/loan_calculator.dart';
import 'package:get/get.dart';

/// One loan's detail screen: the loan, its live payments and what is left.
class LoanDetailController extends GetxController {
  LoanDetailController(this._repository, this._notifier, this.loanId);

  final LoanRepository _repository;
  final DataChangeNotifier _notifier;
  final String loanId;

  final Rxn<LoanDetail> detail = Rxn<LoanDetail>();
  final RxBool isLoading = true.obs;
  final RxnString error = RxnString();
  final SubmitState deletion = SubmitState();

  late final Worker _changes;

  /// The remaining EMIs, computed and never stored; empty without a loan.
  List<LoanInstalment> get schedule {
    final LoanDetail? d = detail.value;
    return d == null
        ? const <LoanInstalment>[]
        : LoanCalculator.schedule(d.loan, d.payments);
  }

  /// Only the latest live payment can be edited or deleted (the repository
  /// refuses the rest); payments are newest first.
  bool canChange(LoanPayment p) {
    final List<LoanPayment> payments = detail.value?.payments ?? const [];
    return payments.isNotEmpty && payments.first.id == p.id;
  }

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
      detail.value = await _repository.getLoan(loanId);
    } on AppException catch (failure) {
      if (!silent || detail.value == null) error.value = failure.message;
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> deleteLoan() => deletion.run(() async {
    await _repository.deleteLoan(loanId);
    _notifier.markChanged();
  });

  Future<bool> deletePayment(String paymentId) => deletion.run(() async {
    await _repository.deletePayment(paymentId);
    _notifier.markChanged();
  });
}
