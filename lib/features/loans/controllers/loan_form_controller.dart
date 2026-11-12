import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/utils/submit_state.dart';
import 'package:finance_tracker/data/repositories/account_repository.dart';
import 'package:finance_tracker/data/repositories/contact_repository.dart';
import 'package:finance_tracker/data/repositories/loan_repository.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/loan.dart';
import 'package:finance_tracker/domain/services/loan_calculator.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

/// Arguments of the loan form route: the loan to edit, or the direction (and
/// optionally the contact) of a new one.
class LoanFormArgs {
  const LoanFormArgs({
    this.existing,
    this.direction = LoanDirection.taken,
    this.contactId,
  });

  final Loan? existing;
  final LoanDirection direction;
  final String? contactId;
}

/// The loan form's draft state. Validation and the EMI come from
/// [LoanCalculator]; the view only renders the getters.
class LoanFormController extends GetxController {
  LoanFormController(
    this._repository,
    this._accountsRepository,
    this._contactsRepository,
    this._notifier,
  ) {
    final DateTime start = startDate.value;
    _previousStart = start;
    firstDueDate.value = LoanCalculator.addMonths(start, 1);
    _workers = <Worker>[
      everAll(<RxInterface<Object?>>[
        principalText,
        rateText,
        tenureText,
        method,
      ], (_) => _followSuggestion()),
      ever<DateTime>(startDate, _followStart),
    ];
  }

  final LoanRepository _repository;
  final AccountRepository _accountsRepository;
  final ContactRepository _contactsRepository;
  final DataChangeNotifier _notifier;

  static const Uuid _uuid = Uuid();

  final Rx<LoanDirection> direction = LoanDirection.taken.obs;
  final Rx<LoanMethod> method = LoanMethod.emi.obs;
  final RxString name = ''.obs;
  final RxnString contactId = RxnString();
  final RxString principalText = ''.obs;

  /// A year for an EMI loan, a month for a monthly-interest loan (saved
  /// times 12).
  final RxString rateText = ''.obs;
  final RxString tenureText = ''.obs;
  final RxString emiText = ''.obs;
  final Rx<DateTime> startDate = _today().obs;
  final Rxn<DateTime> firstDueDate = Rxn<DateTime>();
  final RxnString accountId = RxnString();
  final RxBool movedMoney = true.obs;
  final RxString note = ''.obs;
  final RxList<Account> accounts = <Account>[].obs;
  final RxList<Contact> contacts = <Contact>[].obs;

  /// True once the loan has a live payment: only name, contact and note change.
  final RxBool termsLocked = false.obs;
  final SubmitState save = SubmitState();

  late final List<Worker> _workers;
  late DateTime _previousStart;
  Loan? _existing;

  /// Until the user types in the EMI field it follows [suggestedEmi].
  bool _emiEdited = false;

  static DateTime _today() {
    final DateTime n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void onClose() {
    for (final Worker w in _workers) {
      w.dispose();
    }
    super.onClose();
  }

  /// Loads the pickers and fills the draft from [LoanFormArgs.existing].
  Future<void> start(LoanFormArgs args) async {
    final Loan? existing = args.existing;
    _existing = existing;
    try {
      accounts.assignAll(await _accountsRepository.getAccounts());
      contacts.assignAll(await _contactsRepository.getContacts());
    } on AppException {
      // The pickers stay empty; the error getter then asks for an account.
    }
    if (existing == null) {
      direction.value = args.direction;
      contactId.value = args.contactId;
      accountId.value = accounts.isEmpty ? null : accounts.first.id;
      return;
    }
    try {
      termsLocked.value = (await _repository.getLoan(
        existing.id,
      )).payments.isNotEmpty;
    } on AppException {
      // The repository refuses term changes after a payment anyway.
    }
    _emiEdited = true;
    direction.value = existing.direction;
    method.value = existing.method;
    name.value = existing.name;
    contactId.value = existing.contactId;
    principalText.value = existing.principal.toString();
    rateText.value = existing.method == LoanMethod.monthlyInterest
        ? (existing.annualRate / Decimal.fromInt(12))
              .toDecimal(scaleOnInfinitePrecision: 4)
              .toString()
        : existing.annualRate.toString();
    tenureText.value = existing.tenureMonths?.toString() ?? '';
    emiText.value = existing.emiAmount?.toString() ?? '';
    startDate.value = existing.startDate;
    firstDueDate.value = existing.firstDueDate;
    accountId.value = existing.accountId;
    movedMoney.value = existing.movedMoney;
    note.value = existing.note ?? '';
  }

  /// The EMI from principal, rate and tenure; null until all three are valid.
  Decimal? get suggestedEmi {
    if (method.value != LoanMethod.emi) return null;
    final Decimal? principal = Decimal.tryParse(principalText.value.trim());
    final Decimal? rate = Decimal.tryParse(rateText.value.trim());
    final int? months = int.tryParse(tenureText.value.trim());
    if (principal == null || rate == null || months == null) return null;
    if (principal <= Decimal.zero ||
        rate < Decimal.zero ||
        rate > Decimal.fromInt(60) ||
        months < 1 ||
        months > 480) {
      return null;
    }
    return LoanCalculator.emi(
      principal: principal,
      annualRate: rate,
      months: months,
    );
  }

  /// The user typed in the EMI field: it stops following [suggestedEmi].
  void editEmi(String text) {
    _emiEdited = true;
    emiText.value = text;
  }

  /// The first broken rule, or null while the form is incomplete or valid.
  String? get error {
    if (principalText.value.trim().isEmpty || rateText.value.trim().isEmpty) {
      return null;
    }
    return LoanCalculator.validateLoan(_draft(''));
  }

  /// [id] is generated once per form ([newId]) so a retry upserts one row. The
  /// repository validates the draft and refuses term changes after a payment;
  /// its message lands in [save].error.
  Future<bool> saveLoan(String id) => save.run(() async {
    await _repository.saveLoan(_draft(id));
    _notifier.markChanged();
  });

  static String newId() => _uuid.v4();

  void _followSuggestion() {
    if (_emiEdited) return;
    emiText.value = suggestedEmi?.toString() ?? '';
  }

  /// The first due date moves with the start date unless the user picked one.
  void _followStart(DateTime start) {
    final DateTime? due = firstDueDate.value;
    if (due == null || due == LoanCalculator.addMonths(_previousStart, 1)) {
      firstDueDate.value = LoanCalculator.addMonths(start, 1);
    }
    _previousStart = start;
  }

  /// The loan as typed. An edit keeps what the form does not show (user,
  /// creation and closed dates).
  Loan _draft(String id) {
    final bool isEmi = method.value == LoanMethod.emi;
    final Decimal? rate = Decimal.tryParse(rateText.value.trim());
    final DateTime start = startDate.value;
    final String trimmedNote = note.value.trim();
    final DateTime now = DateTime.now();
    return Loan(
      id: id,
      userId: _existing?.userId ?? '',
      direction: direction.value,
      method: method.value,
      name: name.value.trim(),
      contactId: contactId.value,
      accountId: accountId.value ?? '',
      principal: Decimal.tryParse(principalText.value.trim()) ?? Decimal.zero,
      // Unparsable text becomes an out-of-range rate so validateLoan says so.
      annualRate: rate == null
          ? Decimal.fromInt(-1)
          : (isEmi ? rate : rate * Decimal.fromInt(12)),
      tenureMonths: isEmi ? int.tryParse(tenureText.value.trim()) : null,
      emiAmount: isEmi ? Decimal.tryParse(emiText.value.trim()) : null,
      startDate: DateTime(start.year, start.month, start.day),
      firstDueDate: isEmi ? firstDueDate.value : null,
      movedMoney: movedMoney.value,
      closedAt: _existing?.closedAt,
      note: trimmedNote.isEmpty ? null : trimmedNote,
      createdAt: _existing?.createdAt ?? now,
      updatedAt: now,
    );
  }
}
