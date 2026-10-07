import 'package:decimal/decimal.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/features/transactions/controller/transaction_controller.dart';
import 'package:finance_tracker/utils/app_formatters.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class TransactionFormView extends GetView<TransactionController> {
  final bool isEditMode;
  final String? transactionId;

  TransactionFormView({
    super.key,
    this.isEditMode = false,
    this.transactionId,
  });

  @override
  Widget build(BuildContext context) {
    // Initialize data when view is created
    _selectedDateTime = DateTime.now();
    _dateTimeController.text =
        AppFormatters.dateTime(_selectedDateTime);

    // Load dropdown data
    _loadAccounts();
    _loadCategories();

    // If editing, load transaction data
    if (isEditMode && transactionId != null) {
      _loadTransactionForEdit();
    }

    final String title =
        isEditMode ? 'Edit Transaction' : 'Add Transaction';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Get.back<void>(),
        ),
        actions: [
          if (isEditMode)
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

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTransactionTypeDropdown(),
                const SizedBox(height: 16),
                _buildAccountDropdown(),
                const SizedBox(height: 16),
                _buildCategoryDropdown(),
                const SizedBox(height: 16),
                _buildAmountField(),
                const SizedBox(height: 16),
                _buildDateTimeField(),
                const SizedBox(height: 16),
                _buildNotesField(),
                const SizedBox(height: 16),
                _buildDescriptionField(),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _saveTransaction,
                  child: Text(isEditMode ? 'Update' : 'Add'),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  final _formKey = GlobalKey<FormState>();
  final _transactionTypeController = DropdownButtonController<TransactionType>();
  final _accountController = DropdownButtonController<String>();
  final _categoryController = DropdownButtonController<String>();
  final _amountController = TextEditingController();
  final _dateTimeController = TextEditingController();
  final _notesController = TextEditingController();
  final _descriptionController = TextEditingController();

  late TransactionType _selectedTransactionType;
  late String _selectedAccountId;
  late String? _selectedCategoryId;
  late DateTime _selectedDateTime;

  void _loadAccounts() {
    controller.loadAccounts();
  }

  void _loadCategories() {
    controller.loadCategories();
  }

  void _loadTransactionForEdit() {
    controller.getTransactionById(transactionId!).then((transaction) {
      _selectedTransactionType = transaction.type;
      _selectedAccountId = transaction.accountId;
      _selectedCategoryId = transaction.categoryId;
      _selectedDateTime = transaction.transactionDate;
      _amountController.text = transaction.amount.toStringAsFixed(2);
      _notesController.text = transaction.note ?? '';
      _descriptionController.text = transaction.description ?? '';
    });
  }

  Widget _buildTransactionTypeDropdown() {
    return DropdownButtonFormField<TransactionType>(
      initialValue: _selectedTransactionType,
      decoration: const InputDecoration(
        labelText: 'Transaction Type',
        border: OutlineInputBorder(),
      ),
      items: TransactionType.values.map((type) {
        return DropdownMenuItem(
          value: type,
          child: Text(_getTransactionTypeLabel(type)),
        );
      }).toList(),
      onChanged: (value) {
        if (value != null) {
          _selectedTransactionType = value;
        }
      },
      validator: (value) =>
          value == null ? 'Please select a transaction type' : null,
    );
  }

  Widget _buildAccountDropdown() {
    return Obx(() => DropdownButtonFormField<String>(
          initialValue: _selectedAccountId.isNotEmpty ? _selectedAccountId : null,
          decoration: const InputDecoration(
            labelText: 'Account',
            border: OutlineInputBorder(),
          ),
          items: controller.accounts.map((account) {
            return DropdownMenuItem(
              value: account.id,
              child: Text(account.name),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              _selectedAccountId = value;
            }
          },
          validator: (value) =>
              value == null || value.isEmpty
                  ? 'Please select an account'
                  : null,
        ));
  }

  Widget _buildCategoryDropdown() {
    return Obx(() => DropdownButtonFormField<String>(
          initialValue: _selectedCategoryId,
          decoration: const InputDecoration(
            labelText: 'Category (Optional)',
            border: OutlineInputBorder(),
          ),
          items: controller.categories.map((category) {
            return DropdownMenuItem(
              value: category.id,
              child: Text(category.name),
            );
          }).toList(),
          onChanged: (value) {
            _selectedCategoryId = value;
          },
        ));
  }

  Widget _buildAmountField() {
    return TextFormField(
      controller: _amountController,
      decoration: const InputDecoration(
        labelText: 'Amount',
        prefixIcon: Icon(Icons.attach_money),
        border: OutlineInputBorder(),
      ),
      keyboardType:
          const TextInputType.numberWithOptions(decimal: true),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter an amount';
        }
        if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value)) {
          return 'Please enter a valid amount';
        }
        return null;
      },
    );
  }

  Widget _buildDateTimeField() {
    return TextFormField(
      controller: _dateTimeController,
      decoration: const InputDecoration(
        labelText: 'Date & Time',
        prefixIcon: Icon(Icons.calendar_today),
        border: OutlineInputBorder(),
        suffixIcon: Icon(Icons.edit_calendar),
      ),
      readOnly: true,
      onTap: _pickDateTime,
      validator: (value) =>
          value == null || value.isEmpty
              ? 'Please select a date and time'
              : null,
    );
  }

  Widget _buildNotesField() {
    return TextFormField(
      controller: _notesController,
      decoration: const InputDecoration(
        labelText: 'Notes (Optional)',
        prefixIcon: Icon(Icons.notes),
        border: OutlineInputBorder(),
      ),
      maxLines: 3,
    );
  }

  Widget _buildDescriptionField() {
    return TextFormField(
      controller: _descriptionController,
      decoration: const InputDecoration(
        labelText: 'Description',
        prefixIcon: Icon(Icons.description),
        border: OutlineInputBorder(),
      ),
      validator: (value) =>
          value == null || value.isEmpty
              ? 'Please enter a description'
              : null,
    );
  }

  void _pickDateTime() async {
    final DateTime? pickedDate = await showDatePicker(
      context: Get.context!,
      initialDate: _selectedDateTime,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (pickedDate != null) {
      final TimeOfDay? pickedTime = await showTimePicker(
        context: Get.context!,
        initialTime: TimeOfDay.fromDateTime(_selectedDateTime),
      );
      if (pickedTime != null) {
        _selectedDateTime = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );
        _dateTimeController.text =
            AppFormatters.dateTime(_selectedDateTime);
      }
    }
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
    }
  }

  void _saveTransaction() {
    if (_formKey.currentState!.validate()) {
      final transaction = Transaction(
        id: transactionId ?? '',
        userId: '', // In a real app, this would come from auth
        accountId: _selectedAccountId,
        categoryId: _selectedCategoryId,
        contactId: null, // Not implemented in this phase
        type: _selectedTransactionType,
        amount: Decimal.parse(_amountController.text),
        transactionDate: _selectedDateTime,
        note: _notesController.text.isNotEmpty ? _notesController.text : null,
        description: _descriptionController.text.isNotEmpty ? _descriptionController.text : null,
        paymentMethod: null, // Not implemented in this phase
        transferId: null, // Not implemented in this phase
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        deletedAt: null,
      );

      if (isEditMode && transactionId != null) {
        controller.updateTransaction(transaction);
      } else {
        controller.createTransaction(transaction);
      }

      Get.back<void>();
    }
  }

  void _deleteTransaction() {
    Get.defaultDialog<void>(
      title: 'Delete Transaction',
      middleText: 'Are you sure you want to delete this transaction?',
      textConfirm: 'Delete',
      textCancel: 'Cancel',
      confirmTextColor: Colors.white,
      onConfirm: () {
        if (transactionId != null) {
          controller.deleteTransaction(transactionId!);
        }
        Get.back<void>();
        Get.back<void>(); // Go back to transaction list
      },
    );
  }
}

// Helper class for dropdown button state management
class DropdownButtonController<T> {
  T? value;
}