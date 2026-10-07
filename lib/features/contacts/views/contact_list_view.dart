import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/features/contacts/controller/contact_controller.dart';
import 'package:finance_tracker/features/contacts/views/contact_detail_view.dart';
import 'package:finance_tracker/features/contacts/views/contact_form_view.dart';
import 'package:finance_tracker/widgets/contact_list_item.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ContactListView extends GetView<ContactController> {
  const ContactListView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Get.back<void>(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _addContact,
            tooltip: 'Add Contact',
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterOptions,
            tooltip: 'Filter Contacts',
          ),
          IconButton(
            icon: const Icon(Icons.notifications),
            onPressed: _checkReminders,
            tooltip: 'Check Reminders',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48.0),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: TextField(
              onChanged: (value) => controller.searchQuery = value,
              decoration: InputDecoration(
                hintText: 'Search contacts...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
                filled: true,
                fillColor: Colors.grey.shade100,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
              ),
            ),
          ),
        ),
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
                  onPressed: () => controller.loadContacts(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        if (controller.contacts.isEmpty) {
          return const Center(
            child: Text('No contacts found'),
          );
        }

        return ListView.builder(
          itemCount: controller.contacts.length,
          itemBuilder: (context, index) {
            final contact = controller.contacts[index];
            return ContactListItem(
              contact: contact,
              onTap: () => _viewContact(contact.id),
            );
          },
        );
      }),
      floatingActionButton: FloatingActionButton(
        onPressed: _addContact,
        tooltip: 'Add Contact',
        child: const Icon(Icons.add),
      ),
    );
  }

  void _addContact() {
    Get.to<void>(() => ContactFormView());
  }

  void _viewContact(String contactId) {
    Get.to<void>(() => ContactDetailView(contactId: contactId));
  }

  void _showFilterOptions() {
    Get.defaultDialog<String>(
      title: 'Filter Contacts',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.all_inclusive),
            title: const Text('All Contacts'),
            selected: controller.filterType == 'all',
            onTap: () {
              controller.filterType = 'all';
              Get.back<void>();
            },
          ),
          ListTile(
            leading: const Icon(Icons.arrow_downward, color: Colors.green),
            title: const Text('Receivable (They owe you)'),
            selected: controller.filterType == 'receivable',
            onTap: () {
              controller.filterType = 'receivable';
              Get.back<void>();
            },
          ),
          ListTile(
            leading: const Icon(Icons.arrow_upward, color: Colors.red),
            title: const Text('Payable (You owe)'),
            selected: controller.filterType == 'payable',
            onTap: () {
              controller.filterType = 'payable';
              Get.back<void>();
            },
          ),
        ],
      ),
    );
  }

  void _checkReminders() async {
    final count = await controller.getRemindersCount();
    if (count > 0) {
      await Get.dialog<void>(
        AlertDialog(
          title: const Text('Reminders'),
          content: Text('You have $count contacts requiring attention'),
          actions: [
            TextButton(
              child: const Text('OK'),
              onPressed: () => Get.back<void>(),
            ),
          ],
        ),
      );
    } else {
      Get.showSnackbar(
        const GetSnackBar(
          title: 'No Reminders',
          message: 'No contacts require attention at this time',
          backgroundColor: Colors.green,
        ),
      );
    }
  }
}