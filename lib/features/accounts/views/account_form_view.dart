import 'package:decimal/decimal.dart';
import 'package:finance_tracker/features/accounts/controllers/account_controller.dart';
import 'package:finance_tracker/domain/entities/account.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_content.dart';
import 'package:finance_tracker/core/widgets/app_card.dart';
import 'package:finance_tracker/core/widgets/app_text_field.dart';
import 'package:finance_tracker/core/widgets/app_button.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AccountFormView extends StatefulWidget {
  const AccountFormView({Key? key}) : super(key: key);

  @override
  State<AccountFormView> createState() => _AccountFormViewState();
}

class _AccountFormViewState extends State<AccountFormView> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _openingBalanceController = TextEditingController();
  final _openingBalanceDateController = TextEditingController();
  AccountType? _selectedType;
  final AccountController _controller = Get.find();

  @override
  void initState() {
    super.initState();
    if (Get.arguments is Account) {
      final Account account = Get.arguments as Account;
      _nameController.text = account.name;
      _selectedType = account.type;
      _openingBalanceController.text = account.openingBalance.toString();
      if (account.openingBalanceDate != null) {
        _openingBalanceDateController.text =
            account.openingBalanceDate!.toIso8601String().split('T').first;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _openingBalanceController.dispose();
    _openingBalanceDateController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    try {
      final Account account = Account(
        id: (Get.arguments is Account) ? (Get.arguments as Account).id : '',
        userId: '', // TODO: get from auth
        name: _nameController.text.trim(),
        type: _selectedType!,
        openingBalance: Decimal.parse(_openingBalanceController.text),
        openingBalanceDate: _openingBalanceDateController.text.isNotEmpty
            ? DateTime.parse(_openingBalanceDateController.text)
            : null,
        isActive: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      if (Get.arguments is Account) {
        await _controller.updateAccount(account);
      } else {
        await _controller.addAccount(
          name: account.name,
          type: account.type,
          openingBalance: account.openingBalance,
          openingBalanceDate: account.openingBalanceDate,
        );
      }
      Get.back();
    } catch (e) {
      Get.snackbar('Error', e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isEditing = Get.arguments is Account;
    return Scaffold(
      appBar: AppAppBar(
        title: isEditing ? 'Edit Account' : 'Add Account',
      ),
      body: AppContent(
        child: AppCard(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: ListView(
                children: [
                  AppTextField(
                    label: 'Account Name',
                    controller: _nameController,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter an account name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<AccountType>(
                    decoration: const InputDecoration(labelText: 'Account Type'),
                    value: _selectedType,
                    items: AccountType.values.map((type) {
                      return DropdownMenuItem<AccountType>(
                        value: type,
                        child: Text(_getAccountTypeLabel(type)),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedType = value;
                      });
                    },
                    validator: (value) {
                      if (value == null) {
                        return 'Please select an account type';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    label: 'Opening Balance',
                    controller: _openingBalanceController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter an opening balance';
                      }
                      if (Decimal.tryParse(value) == null) {
                        return 'Please enter a valid number';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    label: 'Opening Balance Date (YYYY-MM-DD)',
                    controller: _openingBalanceDateController,
                    keyboardType: TextInputType.datetime,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return null;
                      }
                      try {
                        DateTime.parse(value);
                        return null;
                      } catch (_) {
                        return 'Please enter a valid date';
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  AppButton(
                    label: isEditing ? 'Update Account' : 'Add Account',
                    onPressed: _submit,
                    isExpanded: false,
                  ),
                ],
              ),
            ),
          ),
        ),
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