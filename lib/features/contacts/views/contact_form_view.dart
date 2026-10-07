import 'package:decimal/decimal.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/features/contacts/controller/contact_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ContactFormView extends GetView<ContactController> {
  final bool isEditMode;
  final String? contactId;
  late String _openingBalanceType;

  ContactFormView({
    super.key,
    this.isEditMode = false,
    this.contactId,
  });

  @override
  Widget build(BuildContext context) {
    // Initialize data when view is created
    _openingBalanceType = 'receivable';

    // Load dropdown data
    _loadContactForEdit();

    final String title =
        isEditMode ? 'Edit Contact' : 'Add Contact';
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
              onPressed: _deleteContact,
              tooltip: 'Delete Contact',
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
                _buildNameField(),
                const SizedBox(height: 16),
                _buildMobileField(),
                const SizedBox(height: 16),
                _buildEmailField(),
                const SizedBox(height: 16),
                _buildAddressField(),
                const SizedBox(height: 16),
                _buildOpeningBalanceField(),
                const SizedBox(height: 16),
                _buildOpeningBalanceTypeField(),
                const SizedBox(height: 16),
                _buildNotesField(),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _saveContact,
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
  final _nameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _openingBalanceController = TextEditingController();
  final _notesController = TextEditingController();

  void _loadContactForEdit() {
    if (isEditMode && contactId != null) {
      controller.getContactById(contactId!).then((contact) {
        _nameController.text = contact.name;
        _mobileController.text = contact.mobile ?? '';
        _emailController.text = contact.email ?? '';
        _addressController.text = contact.address ?? '';
        _openingBalanceController.text =
            contact.openingBalance.toStringAsFixed(2);
        _notesController.text = contact.notes ?? '';
      });
    }
  }

  Widget _buildNameField() {
    return TextFormField(
      controller: _nameController,
      decoration: const InputDecoration(
        labelText: 'Name',
        border: OutlineInputBorder(),
      ),
      validator: (value) =>
          value == null || value.isEmpty ? 'Please enter a name' : null,
    );
  }

  Widget _buildMobileField() {
    return TextFormField(
      controller: _mobileController,
      decoration: const InputDecoration(
        labelText: 'Mobile (Optional)',
        border: OutlineInputBorder(),
      ),
    );
  }

  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailController,
      decoration: const InputDecoration(
        labelText: 'Email (Optional)',
        border: OutlineInputBorder(),
      ),
    );
  }

  Widget _buildAddressField() {
    return TextFormField(
      controller: _addressController,
      decoration: const InputDecoration(
        labelText: 'Address (Optional)',
        border: OutlineInputBorder(),
      ),
    );
  }

  Widget _buildOpeningBalanceField() {
    return TextFormField(
      controller: _openingBalanceController,
      decoration: const InputDecoration(
        labelText: 'Opening Balance',
        border: OutlineInputBorder(),
      ),
      keyboardType:
          const TextInputType.numberWithOptions(decimal: true),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter an opening balance';
        }
        if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value)) {
          return 'Please enter a valid amount';
        }
        return null;
      },
    );
  }

  Widget _buildOpeningBalanceTypeField() {
    return Obx(() => DropdownButtonFormField<String>(
          initialValue: _openingBalanceType.isNotEmpty
              ? _openingBalanceType
              : null,
          decoration: const InputDecoration(
            labelText: 'Opening Balance Type',
            border: OutlineInputBorder(),
          ),
          items: const [
            'receivable',
            'payable'
          ].map((type) {
            return DropdownMenuItem(
              value: type,
              child: Text(type[0].toUpperCase() + type.substring(1)),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              _openingBalanceType = value;
            }
          },
          validator: (value) =>
              value == null || value.isEmpty
                  ? 'Please select an opening balance type'
                  : null,
        ));
  }

  Widget _buildNotesField() {
    return TextFormField(
      controller: _notesController,
      decoration: const InputDecoration(
        labelText: 'Notes (Optional)',
        border: OutlineInputBorder(),
      ),
      maxLines: 3,
    );
  }

  void _saveContact() {
    if (_formKey.currentState!.validate()) {
      final contact = Contact(
        id: contactId ?? '',
        userId: '', // In a real app, this would come from auth
        name: _nameController.text,
        mobile: _mobileController.text.isNotEmpty
            ? _mobileController.text
            : null,
        email: _emailController.text.isNotEmpty
            ? _emailController.text
            : null,
        address: _addressController.text.isNotEmpty
            ? _addressController.text
            : null,
        notes: _notesController.text.isNotEmpty
            ? _notesController.text
            : null,
        openingBalance:
            Decimal.parse(_openingBalanceController.text),
        openingBalanceType: _openingBalanceType,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        deletedAt: null,
      );

      if (isEditMode && contactId != null) {
        controller.updateContact(contact);
      } else {
        controller.createContact(contact);
      }

      Get.back<void>();
    }
  }

  void _deleteContact() {
    Get.defaultDialog<void>(
      title: 'Delete Contact',
      middleText: 'Are you sure you want to delete this contact?',
      textConfirm: 'Delete',
      textCancel: 'Cancel',
      confirmTextColor: Colors.white,
      onConfirm: () {
        if (contactId != null) {
          controller.deleteContact(contactId!);
        }
        Get.back<void>();
        Get.back<void>(); // Go back to contact list
      },
    );
  }
}

// Helper class for dropdown button state management
class DropdownButtonController<T> {
  T? value;
}