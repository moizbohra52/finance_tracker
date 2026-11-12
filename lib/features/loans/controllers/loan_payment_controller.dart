import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/utils/submit_state.dart';
import 'package:finance_tracker/data/repositories/account_repository.dart';
import 'package:finance_tracker/data/repositories/loan_repository.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/loan.dart';
import 'package:finance_tracker/domain/services/loan_calculator.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

/// Arguments of the payment form route: the loan, an optional payment to edit,
/// and whether it is an EMI prepayment ([kind] extra) or a closing payment.
class LoanPaymentArgs {
  const LoanPaymentArgs({
    required this.loanId,
    this.kind = LoanPaymentKind.scheduled,
    this.existing,
    this.closing = false,
  });

  final String loanId;
  final LoanPaymentKind kind;
  final LoanPayment? existing;
  final bool closing;

  /// A [LoanPaymentArgs], or a bare loan id (a notification tap passes one).
  static LoanPaymentArgs of(Object? argument) {
    if (argument is LoanPaymentArgs) return argument;
    if (argument is String) return LoanPaymentArgs(loanId: argument);
    throw ArgumentError.value(argument, 'argument', 'Not a loan payment');
  }
}

/// The payment form's draft state. The split, the suggestion and the rules all
/// come from [LoanCalculator]; the view only renders the texts and [error].
class LoanPaymentController extends GetxController {
  LoanPaymentController(
    this._repository,
    this._accountsRepository,
    this._notifier,
  );

  final LoanRepository _repository;
  final AccountRepository _accountsRepository;
  final DataChangeNotifier _notifier;

  static const Uuid _uuid = Uuid();

  final Rxn<LoanDetail> loan = Rxn<LoanDetail>();
  final RxnString loadError = RxnString();
  final RxList<Account> accounts = <Account>[].obs;
  final Rx<DateTime> paidAt = _today().obs;
  final RxnString accountId = RxnString();
  final RxString amountText = ''.obs;
  final RxString principalText = ''.obs;
  final RxString interestText = ''.obs;
  final RxString note = ''.obs;
  final SubmitState save = SubmitState();

  LoanPayment? _existing;
  LoanPaymentKind _kind = LoanPaymentKind.scheduled;
  bool _closing = false;

  /// One id per form, so a retried save upserts one payment.
  String _id = '';

  /// The loan's other live payments: what the rules are checked against.
  List<LoanPayment> _earlier = const <LoanPayment>[];

  static DateTime _today() {
    final DateTime n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static String newId() => _uuid.v4();

  LoanPaymentKind get kind => _kind;

  /// Loads the loan and the accounts and fills the form: the next EMI (or the
  /// interest due), the payoff when closing, or the edited payment itself.
  Future<void> start(LoanPaymentArgs args) async {
    final LoanPayment? existing = args.existing;
    _existing = existing;
    _id = existing?.id ?? newId();
    loadError.value = null;
    try {
      accounts.assignAll(
        (await _accountsRepository.getAccounts()).where(
          (Account a) => a.isActive || a.id == existing?.accountId,
        ),
      );
    } on AppException {
      // The picker stays empty; saving then asks for an account.
    }
    final LoanDetail detail;
    try {
      detail = await _repository.getLoan(args.loanId);
    } on AppException catch (failure) {
      loadError.value = failure.message;
      return;
    }
    loan.value = detail;
    _earlier = detail.payments
        .where((LoanPayment p) => p.id != existing?.id)
        .toList();
    final bool monthly = detail.loan.method == LoanMethod.monthlyInterest;
    _kind = existing?.kind ?? _kindFor(monthly, args);
    _closing = existing == null && args.closing;
    if (existing != null) {
      paidAt.value = _day(existing.paidAt);
      accountId.value = existing.accountId;
      amountText.value = _text(existing.amount);
      principalText.value = _text(existing.principalPart);
      interestText.value = _text(existing.interestPart);
      note.value = existing.note ?? '';
      return;
    }
    final String loanAccount = detail.loan.accountId;
    accountId.value = accounts.any((Account a) => a.id == loanAccount)
        ? loanAccount
        : (accounts.isEmpty ? null : accounts.first.id);
    _suggest();
  }

  /// A monthly-interest loan has no EMI to prepay: its payments are always
  /// scheduled. An EMI loan's closing payment is an extra one.
  static LoanPaymentKind _kindFor(bool monthly, LoanPaymentArgs args) {
    if (monthly) return LoanPaymentKind.scheduled;
    return args.closing ? LoanPaymentKind.extra : args.kind;
  }

  /// The user typed an amount: split it interest first.
  void setAmount(String text) {
    amountText.value = text;
    _closing = false;
    final Decimal? amount = Decimal.tryParse(text.trim());
    if (amount == null) return;
    _split(_suggestion(amount: amount));
  }

  /// The interest becomes what is left of the amount.
  void setPrincipal(String text) {
    principalText.value = text;
    final Decimal? principal = Decimal.tryParse(text.trim());
    final Decimal? amount = Decimal.tryParse(amountText.value.trim());
    if (principal == null || amount == null) return;
    interestText.value = _text(amount - principal);
  }

  /// The principal becomes what is left of the amount.
  void setInterest(String text) {
    interestText.value = text;
    final Decimal? interest = Decimal.tryParse(text.trim());
    final Decimal? amount = Decimal.tryParse(amountText.value.trim());
    if (interest == null || amount == null) return;
    principalText.value = _text(amount - interest);
  }

  /// A monthly-interest loan's interest due depends on the date, so the split
  /// is suggested again; an EMI loan's stays as typed.
  void setDate(DateTime date) {
    paidAt.value = _day(date);
    if (loan.value?.loan.method == LoanMethod.monthlyInterest) _suggest();
  }

  /// The first broken rule, or null while the amount is blank or all is valid.
  String? get error {
    if (loan.value == null || amountText.value.trim().isEmpty) return null;
    return _validate();
  }

  /// Writes the payment; the repository checks it again and refuses edits of
  /// anything but the latest payment, its message landing in [save].error.
  Future<bool> savePayment() => save.run(() async {
    final String? message = accountId.value == null
        ? 'Choose an account'
        : _validate();
    if (message != null) throw UnexpectedFailure(message);
    await _repository.savePayment(_draft());
    _notifier.markChanged();
  });

  String? _validate() {
    final LoanDetail? detail = loan.value;
    if (detail == null) return 'Amount must be more than zero';
    return LoanCalculator.validatePayment(detail.loan, _earlier, _draft());
  }

  LoanPart _suggestion({Decimal? amount}) => LoanCalculator.suggest(
    loan.value!.loan,
    _earlier,
    kind: _kind,
    paidAt: paidAt.value,
    amount: amount,
    closing: _closing,
  );

  /// Fills the whole form from the suggestion; a zero amount stays blank.
  void _suggest() {
    final LoanPart part = _suggestion();
    amountText.value = part.amount > Decimal.zero ? _text(part.amount) : '';
    _split(part);
  }

  void _split(LoanPart part) {
    principalText.value = _text(part.principal);
    interestText.value = _text(part.interest);
  }

  static String _text(Decimal value) => value.toStringAsFixed(2);

  LoanPayment _draft() {
    final DateTime now = DateTime.now();
    final String trimmed = note.value.trim();
    return LoanPayment(
      id: _id,
      userId: _existing?.userId ?? '',
      loanId: loan.value!.loan.id,
      accountId: accountId.value ?? '',
      kind: _kind,
      paidAt: paidAt.value,
      amount: Decimal.tryParse(amountText.value.trim()) ?? Decimal.zero,
      principalPart:
          Decimal.tryParse(principalText.value.trim()) ?? Decimal.zero,
      interestPart: Decimal.tryParse(interestText.value.trim()) ?? Decimal.zero,
      note: trimmed.isEmpty ? null : trimmed,
      createdAt: _existing?.createdAt ?? now,
      updatedAt: now,
    );
  }
}
