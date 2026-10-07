import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/utils/app_formatters.dart';
import 'package:flutter/material.dart';

class TransactionListItem extends StatelessWidget {
  final Transaction transaction;

  const TransactionListItem({
    Key? key,
    required this.transaction,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _buildTransactionIcon(),
      title: Text(transaction.description ?? 'No description'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppFormatters.currency(transaction.amount)),
          Text(
            '${AppFormatters.dateTime(transaction.transactionDate)} • ${_getTransactionTypeLabel()}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
      trailing: PopupMenuButton<String>(
        onSelected: _handleMenuSelection,
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'edit',
            child: ListTile(
              leading: Icon(Icons.edit),
              title: Text('Edit'),
            ),
          ),
          const PopupMenuItem(
            value: 'delete',
            child: ListTile(
              leading: Icon(Icons.delete),
              title: Text('Delete'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionIcon() {
    IconData icon;
    Color color;

    switch (transaction.type) {
      case TransactionType.income:
        icon = Icons.arrow_upward;
        color = Colors.green;
        break;
      case TransactionType.expense:
        icon = Icons.arrow_downward;
        color = Colors.red;
        break;
      case TransactionType.transfer_in:
      case TransactionType.transfer_out:
        icon = Icons.swap_horiz;
        color = Colors.blue;
        break;
      case TransactionType.adjustment_in:
      case TransactionType.adjustment_out:
        icon = Icons.create;
        color = Colors.orange;
        break;
      case TransactionType.opening_balance:
        icon = Icons.account_balance;
        color = Colors.purple;
        break;
      case TransactionType.payment_received:
        icon = Icons.receipt_long;
        color = Colors.green;
        break;
      case TransactionType.payment_made:
        icon = Icons.receipt_long;
        color = Colors.red;
        break;
      default:
        icon = Icons.account_balance_wallet;
        color = Colors.grey;
    }

    return CircleAvatar(
      backgroundColor: color.withOpacity(0.2),
      child: Icon(icon, color: color),
    );
  }

  String _getTransactionTypeLabel() {
    switch (transaction.type) {
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

  void _handleMenuSelection(String value) {
    switch (value) {
      case 'edit':
        // TODO: Navigate to edit transaction screen
        break;
      case 'delete':
        // TODO: Show delete confirmation dialog
        break;
    }
  }
}