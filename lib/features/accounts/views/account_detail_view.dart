import 'package:decimal/decimal.dart';
import 'package:finance_tracker/features/accounts/controllers/account_controller.dart';
import 'package:finance_tracker/features/accounts/views/account_form_view.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/app_card.dart';
import 'package:finance_tracker/core/widgets/app_button.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AccountDetailView extends GetView<AccountController> {
  const AccountDetailView({super.key, this.account});

  final Account? account;

  @override
  Widget build(BuildContext context) {
    if (account == null) {
      return const Scaffold(
        body: Center(
          child: Text('Account not found'),
        ),
      );
    }
    return Scaffold(
      appBar: AppAppBar(title: account!.name),
      body: AppContent(
        child: AppCard(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: FutureBuilder<Decimal>(
              future: controller.getAccountBalance(account!),
              builder: (context, snapshot) {
                final String openingBalanceText =
                    '\$${account!.openingBalance.toStringAsFixed(2)}';
                final String currentBalanceText = snapshot.hasData
                    ? '\$${snapshot.data!.toStringAsFixed(2)}'
                    : 'Calculating...';
                return ListView(
                  children: [
                    _buildDetailRow('Type', _getAccountTypeLabel(account!.type)),
                    const Divider(),
                    _buildDetailRow('Opening Balance', openingBalanceText),
                    _buildDetailRow('Opening Balance Date',
                        account!.openingBalanceDate != null
                            ? account!.openingBalanceDate.toString().split(' ').first
                            : 'Not set'),
                    const Divider(),
                    _buildDetailRow('Current Balance', currentBalanceText),
                    const Divider(),
                    _buildDetailRow('Created At', account!.createdAt.toString()),
                    _buildDetailRow('Updated At', account!.updatedAt.toString()),
                    if (account!.deletedAt != null)
                      _buildDetailRow('Deleted At',
                          account!.deletedAt!.toString()),
                    const SizedBox(height: 24),
                    AppButton(
                      label: 'Edit Account',
                      onPressed: () => Get.to(() => AccountFormView(),
                          arguments: account)?.then((_) => controller.loadAccounts()),
                      isExpanded: false,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  String _getAccountTypeLabel(AccountType type) {
    switch (type) {
      case AccountType.cash:
        return 'Cash';
      case AccountType.bank:
        return 'Bank';
      case AccountType.upi:
        return 'UPI';
      case AccountType.card:
        return 'Card';
      case AccountType.other:
        return 'Other';
      default:
        return 'Unknown';
    }
  }
}