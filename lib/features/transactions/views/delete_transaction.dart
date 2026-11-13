import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:finance_tracker/core/utils/category_icons.dart';
import 'package:finance_tracker/core/utils/submit_state.dart';
import 'package:finance_tracker/core/widgets/app_pickers.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/domain/services/transfer_legs.dart';
import 'package:finance_tracker/features/transactions/controller/transaction_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Asks, then deletes [transaction], or both legs when it belongs to a
/// transfer, and says it is done. Shared by the detail screen's Delete
/// button and a swipe on a list row. [transfer] is the transfer when the
/// caller already has it; for a leg without it, it is looked up, so a swipe
/// never leaves half a transfer behind. Returns whether it was deleted; a
/// failed delete leaves its message in [TransactionController.deletion].
Future<bool> confirmDeleteTransaction(
  BuildContext context,
  Transaction transaction, {
  TransferLegs? transfer,
}) async {
  final TransactionController list = Get.find<TransactionController>();
  TransferLegs? legs = transfer;
  if (legs == null && TransferLegs.isLeg(transaction)) {
    try {
      legs = await list.fetchTransfer(transaction.transferId!);
    } on AppException catch (failure) {
      AppSnackbar.show(failure.message);
      return false;
    }
  }
  if (!context.mounted) return false;
  final String amount = AppFormatters.money(transaction.amount);
  final bool confirmed = await confirmDestructive(
    context,
    title: legs == null ? 'Delete transaction?'.tr : 'Delete transfer?'.tr,
    message: legs == null
        ? 'This @type of @amount will be removed from your balance.'.trParams(
            <String, String>{
              'type': transaction.type.label.toLowerCase(),
              'amount': amount,
            },
          )
        : 'This transfer of @amount from @from to @to will be removed from both accounts.'
              .trParams(<String, String>{
                'amount': amount,
                'from': list.accountName(legs.fromAccountId),
                'to': list.accountName(legs.toAccountId),
              }),
  );
  if (!confirmed) return false;
  final bool deleted = legs == null
      ? await list.deleteTransaction(transaction.id)
      : await list.deleteTransfer(legs.transferId);
  if (deleted) {
    AppSnackbar.show(
      legs == null ? 'Transaction deleted'.tr : 'Transfer deleted'.tr,
    );
  }
  return deleted;
}

/// A swipe on a list row: [confirmDeleteTransaction], with a failure shown
/// as a snackbar, since a list has no place for the message.
Future<bool> swipeDeleteTransaction(
  BuildContext context,
  Transaction transaction,
) async {
  final SubmitState deletion = Get.find<TransactionController>().deletion;
  // An earlier failure's message must not show when this one is cancelled.
  deletion.error.value = null;
  final bool deleted = await confirmDeleteTransaction(context, transaction);
  final String? error = deletion.error.value;
  if (!deleted && error != null) AppSnackbar.show(error);
  return deleted;
}
