import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/data/repositories/split_repository.dart';
import 'package:finance_tracker/data/repositories/transaction_repository.dart';
import 'package:finance_tracker/domain/entities/savings_contribution.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/transfer_legs.dart';
import 'package:finance_tracker/features/split/controllers/split_expense_controller.dart';
import 'package:finance_tracker/features/split/views/split_settlement_form_view.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:get/get.dart';

/// Loads one transaction by id for the detail route, and for a transfer leg
/// both legs, so the screen can show where the money went.
class TransactionDetailController extends GetxController {
  TransactionDetailController(
    this._repository,
    this._notifier,
    this.transactionId, {
    this._splitRepository,
  });

  final TransactionRepository _repository;
  final DataChangeNotifier _notifier;
  final String transactionId;

  /// Null where split groups are not available (tests without them).
  final SplitRepository? _splitRepository;

  final Rxn<Transaction> transaction = Rxn<Transaction>();

  /// Both legs when [transaction] is part of a transfer.
  final Rxn<TransferLegs> transfer = Rxn<TransferLegs>();

  /// The goals an income was put into; empty for anything else.
  final RxList<SavingsContribution> savings = <SavingsContribution>[].obs;
  final RxBool isLoading = true.obs;
  final RxnString error = RxnString();

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
    // Reload after an edit made from this screen.
    _changes = ever<int>(_notifier.version, (_) => load(silent: true));
  }

  /// The group name behind a derived row, for the chip; null for a plain one.
  String? get splitGroupLabel => _link?.groupName;

  SplitLink? _link;

  /// Opens the split expense or settlement form of a derived row.
  Future<void> openInGroup() async {
    final SplitLink? link = _link;
    final SplitRepository? repository = _splitRepository;
    if (link == null || repository == null) return;
    if (link.isSettlement) {
      await Get.toNamed<void>(
        AppRoutes.splitSettlementForm,
        arguments: SplitSettlementArgs(
          groupId: link.groupId,
          existing: await repository.getSettlement(link.id),
        ),
      );
    } else {
      await Get.toNamed<void>(
        AppRoutes.splitExpenseForm,
        arguments: SplitExpenseArgs(
          groupId: link.groupId,
          existing: await repository.getExpense(link.id),
        ),
      );
    }
  }

  Future<void> _loadLink(Transaction t) async {
    final SplitRepository? repository = _splitRepository;
    _link = null;
    final String? id = t.splitExpenseId ?? t.splitSettlementId;
    if (repository == null || id == null) return;
    final Map<String, SplitLink> links = await repository.getLinks(
      expenseIds: <String>[if (t.splitExpenseId != null) t.splitExpenseId!],
      settlementIds: <String>[
        if (t.splitSettlementId != null) t.splitSettlementId!,
      ],
    );
    _link = links[id];
  }

  Future<void> load({bool silent = false}) async {
    if (!silent) isLoading.value = true;
    error.value = null;
    try {
      final Transaction loaded = await _repository.getTransactionById(
        transactionId,
      );
      // A soft-deleted row is gone as far as the user is concerned.
      final Transaction? live = loaded.deletedAt == null ? loaded : null;
      transfer.value = live != null && TransferLegs.isLeg(live)
          ? await _repository.getTransfer(live.transferId!)
          : null;
      if (live != null && live.type == TransactionType.income) {
        savings.assignAll(await _repository.getContributions(live.id));
      } else {
        savings.clear();
      }
      if (live != null) {
        try {
          await _loadLink(live);
        } on AppException {
          _link = null;
        }
      }
      transaction.value = live;
    } on AppException catch (failure) {
      if (!silent) error.value = failure.message;
    } finally {
      isLoading.value = false;
    }
  }
}
