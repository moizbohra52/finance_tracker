import 'package:decimal/decimal.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/features/contacts/controller/contact_controller.dart';
import 'package:finance_tracker/features/contacts/views/contact_form_view.dart';
import 'package:finance_tracker/widgets/contact_list_item.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ContactDetailView extends GetView<ContactController> {
  final String contactId;

  const ContactDetailView({
    super.key,
    required this.contactId,
  });

  @override
  Widget build(BuildContext context) {
    // Load contact details when view is created
    _loadContactDetails();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contact Details'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Get.back<void>(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _editContact,
            tooltip: 'Edit Contact',
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _deleteContact,
            tooltip: 'Delete Contact',
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
                  onPressed: () => _loadContactDetails(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        final contact = controller.selectedContact;
        if (contact == null) {
          return const Center(
            child: Text('Contact not found'),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ContactListItem(contact: contact),
              const Divider(height: 32),
              const Text(
                'Details',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              _buildDetailRow('Name', contact.name),
              if (contact.mobile != null && contact.mobile!.isNotEmpty)
                _buildDetailRow('Mobile', contact.mobile!),
              if (contact.email != null && contact.email!.isNotEmpty)
                _buildDetailRow('Email', contact.email!),
              if (contact.address != null && contact.address!.isNotEmpty)
                _buildDetailRow('Address', contact.address!),
              _buildDetailRow(
                  'Opening Balance',
                  '${contact.openingBalanceType == 'receivable' ? '+' : '-'}\$${contact.openingBalance.toStringAsFixed(2)}'),
              _buildDetailRow(
                  'Opening Balance Type',
                  contact.openingBalanceType == 'receivable'
                      ? 'Receivable'
                      : 'Payable'),
              if (contact.notes != null && contact.notes!.isNotEmpty)
                _buildDetailRow('Notes', contact.notes!),
              const SizedBox(height: 24),
              const Text(
                'Transaction History',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              _buildTransactionHistory(),
            ],
          ),
        );
      }),
    );
  }

  Future<void> _loadContactDetails() async {
    controller.isLoading = true;
    controller.errorMessage = '';
    try {
      final contact =
          await controller.getContactById(contactId);
      controller.selectedContact = contact;

      // Also load transaction history
      await _loadContactTransactions();
    } catch (e) {
      controller.errorMessage = e.toString();
    } finally {
      controller.isLoading = false;
    }
  }

  Future<void> _loadContactTransactions() async {
    final contact = controller.selectedContact;
    if (contact == null) return;

    controller.isLoading = true;
    controller.errorMessage = '';
    try {
      final transactions = await controller.getContactTransactions(
          contact.id);
      // Store transactions in controller for display
      controller.contactTransactions = transactions;
    } catch (e) {
      controller.errorMessage = e.toString();
    } finally {
      controller.isLoading = false;
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

  Widget _buildTransactionHistory() {
    return Obx(() {
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
                onPressed: () => _loadContactDetails(),
                child: const Text('Retry'),
              ),
            ],
          ),
        );
      }

      final transactions = controller.contactTransactions;
      if (transactions.isEmpty) {
        return const Center(
          child: Text('No transactions found'),
        );
      }

      return ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: transactions.length,
        itemBuilder: (context, index) {
          final transaction = transactions[index];
          return _buildTransactionItem(transaction);
        },
      );
    });
  }

  Widget _buildTransactionItem(ContactTransaction transaction) {
    // Determine transaction type and color
    String typeText;
    Color typeColor;
    String amountText;
    Color amountColor;

    switch (transaction.type) {
      case ContactTransactionType.credit:
        typeText = 'Credit';
        typeColor = Colors.green;
        amountText = '+ \$${transaction.amount.toStringAsFixed(2)}';
        amountColor = Colors.green;
        break;
      case ContactTransactionType.debit:
        typeText = 'Debit';
        typeColor = Colors.red;
        amountText = '- \$${transaction.amount.toStringAsFixed(2)}';
        amountColor = Colors.red;
        break;
      case ContactTransactionType.paymentReceived:
        typeText = 'Payment Received';
        typeColor = Colors.blue;
        amountText = '- \$${transaction.amount.toStringAsFixed(2)}';
        amountColor = Colors.blue;
        break;
      case ContactTransactionType.paymentMade:
        typeText = 'Payment Made';
        typeColor = Colors.purple;
        amountText = '+ \$${transaction.amount.toStringAsFixed(2)}';
        amountColor = Colors.purple;
        break;
      case ContactTransactionType.adjustment:
        typeText = 'Adjustment';
        typeColor = Colors.orange;
        amountText = '${transaction.amount >= Decimal.zero ? '+' : '-'}\$${transaction.amount.abs().toStringAsFixed(2)}';
        amountColor = Colors.orange;
        break;
    }

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: typeColor.withValues(alpha: 0.2),
          child: Text(
            typeText[0],
            style: TextStyle(
              color: typeColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          typeText,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Date: ',
            ),
            Text(
              '${transaction.transactionDate.toLocal()}'.split(' ')[0],
            ),
            if (transaction.note != null && transaction.note!.isNotEmpty)
              Text('Note: ${transaction.note}'),
          ],
        ),
        trailing: Text(
          amountText,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: amountColor,
          ),
        ),
      ),
    );
  }

  void _editContact() {
    Get.to<void>(() => ContactFormView(
          isEditMode: true,
          contactId: contactId,
        ));
  }

  void _deleteContact() {
    Get.defaultDialog<void>(
      title: 'Delete Contact',
      middleText: 'Are you sure you want to delete this contact?',
      textConfirm: 'Delete',
      textCancel: 'Cancel',
      confirmTextColor: Colors.white,
      onConfirm: () {
        controller.deleteContact(contactId);
        Get.back<void>();
        Get.back<void>(); // Go back to contact list
      },
    );
  }
}