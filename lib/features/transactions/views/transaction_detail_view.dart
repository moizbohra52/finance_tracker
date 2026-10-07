import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/features/transactions/controller/transaction_controller.dart';
import 'package:finance_tracker/features/transactions/views/transaction_form_view.dart';
import 'package:finance_tracker/widgets/transaction_list_item.dart';
import 'package:finance_tracker/utils/app_formatters.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class TransactionDetailView extends GetView<TransactionController> {
  final String transactionId;

  const TransactionDetailView({
    super.key,
    required this.transactionId,
  });

  @override
  Widget build(BuildContext context) {
    // Load transaction details when view is created
    _loadTransactionDetails();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction Details'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Get.back(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _editTransaction,
            tooltip: 'Edit Transaction',
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _deleteTransaction,
            tooltip: 'Delete Transaction',
          ),
        ],
      ),
      body: Obx(() {
        if (controller.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (controller.errorMessage.isNotEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Error: ${controller.errorMessage}',
                    style: const TextStyle(color: Colors.red)),
                ElevatedButton(
                  onPressed: () => _loadTransactionDetails(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        final transaction = controller.selectedTransaction;
        if (transaction == null) {
          return const Center(
            child: Text('Transaction not found'),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TransactionListItem(transaction: transaction),
              const Divider(height: 32),
              const Text(
                'Details',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              _buildDetailRow('Type', _getTransactionTypeLabel(transaction.type)),
              _buildDetailRow(
                  'Amount', AppFormatters.currency(transaction.amount)),
              _buildDetailRow(
                  'Date', AppFormatters.dateTime(transaction.transactionDate)),
              if (transaction.note != null && transaction.note!.isNotEmpty)
                _buildDetailRow('Notes', transaction.note!),
              if (transaction.description != null &&
                  transaction.description!.isNotEmpty)
                _buildDetailRow('Description', transaction.description!),
              if (transaction.paymentMethod != null &&
                  transaction.paymentMethod!.isNotEmpty)
                _buildDetailRow('Payment Method', transaction.paymentMethod!),
              if (transaction.transferId != null &&
                  transaction.transferId!.isNotEmpty)
                _buildDetailRow('Transfer ID', transaction.transferId!),
            ],
          ),
        );
      }),
    );
  }

  Future<void> _loadTransactionDetails() async {
    controller.isLoading = true;
    controller.errorMessage = '';
    try {
      final transaction =
          await controller.getTransactionById(transactionId);
      controller.selectedTransaction = transaction;
    } catch (e) {
      controller.errorMessage = e.toString();
    } finally {
      controller.isLoading = false;
    }
  }

  void _editTransaction() {
    Get.to(() => TransactionFormView(
          isEditMode: true,
          transactionId: transactionId,
        ));
  }

  void _deleteTransaction() {
    // TODO: Implement delete confirmation dialog
  }

  String _getTransactionTypeLabel(TransactionType type) {
    switch (type) {
      case TransactionType.income:
        return 'Income';
      case TransactionType.expense:
        return 'Expense';
      case TransactionType.transfer_in:
        return 'Transfer In';
      case TransactionType.transfer_out:
        return 'Transfer Out';
      case TransactionType.adjustment_in:
        return 'Adjustment In';
      case TransactionType.adjustment_out:
        return 'Adjustment Out';
      case TransactionType.opening_balance:
        return 'Opening Balance';
      case TransactionType.payment_received:
        return 'Payment Received';
      case TransactionType.payment_made:
        return 'Payment Made';
      default:
        return 'Unknown';
    }
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }
}