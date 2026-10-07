import 'package:finance_tracker/features/transactions/controller/transaction_controller.dart';
import 'package:finance_tracker/widgets/transaction_list_item.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class TransactionListView extends GetView<TransactionController> {
  final String? accountId;
  final String? categoryId;
  final String? contactId;
  final DateTime? startDate;
  final DateTime? endDate;

  const TransactionListView({
    super.key,
    this.accountId,
    this.categoryId,
    this.contactId,
    this.startDate,
    this.endDate,
  });

  @override
  Widget build(BuildContext context) {
    // Initialize data when view is created
    controller.loadTransactions(
      accountId: accountId,
      categoryId: categoryId,
      contactId: contactId,
      startDate: startDate,
      endDate: endDate,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _addTransaction,
            tooltip: 'Add Transaction',
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _filterTransactions,
            tooltip: 'Filter Transactions',
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _searchTransactions,
            tooltip: 'Search Transactions',
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
                  onPressed: () => controller.loadTransactions(
                    accountId: accountId,
                    categoryId: categoryId,
                    contactId: contactId,
                    startDate: startDate,
                    endDate: endDate,
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        if (controller.transactions.isEmpty) {
          return const Center(
            child: Text('No transactions found'),
          );
        }

        return ListView.builder(
          itemCount: controller.transactions.length,
          itemBuilder: (context, index) {
            final transaction = controller.transactions[index];
            return TransactionListItem(transaction: transaction);
          },
        );
      }),
    );
  }

  void _addTransaction() {
    // Navigate to add transaction form
    Get.toNamed('/transactions/add');
  }

  void _filterTransactions() {
    // Show filter dialog
    Get.toNamed('/transactions/filter');
  }

  void _searchTransactions() {
    // Show search dialog
    Get.toNamed('/transactions/search');
  }
}