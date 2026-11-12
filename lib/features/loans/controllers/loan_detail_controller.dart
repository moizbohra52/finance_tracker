import 'package:decimal/decimal.dart';
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

  /// Whether the schedule shows every instalment, not just the next few.
  final RxBool scheduleExpanded = false.obs;

  late final Worker _changes;

  /// The remaining EMIs, computed and never stored; empty without a loan.
  List<LoanInstalment> get schedule {
    final LoanDetail? d = detail.value;
    return d == null
        ? const <LoanInstalment>[]
        : LoanCalculator.schedule(d.loan, d.payments);
  }

  /// The share of the principal already repaid, 0 to 1 (for a progress bar:
  /// the only place a loan amount becomes a double).
  double get progress {
    final LoanDetail? d = detail.value;
    if (d == null || d.loan.principal <= Decimal.zero) return 0;
    return (d.status.principalRepaid / d.loan.principal).toDouble().clamp(
      0.0,
      1.0,
    );
  }

  /// [progress] as a whole percent, floored so an open loan at 99.6% does not
  /// read 100%.
  int get progressPercent {
    final LoanDetail? d = detail.value;
    if (d == null || d.loan.principal <= Decimal.zero) return 0;
    final Decimal repaid = d.status.principalRepaid;
    if (repaid >= d.loan.principal) return 100;
    return ((repaid * Decimal.fromInt(100)) / d.loan.principal).floor().toInt();
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
