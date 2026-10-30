import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:finance_tracker/features/contacts/controller/contact_form_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fake_finance.dart';

void main() {
  late FakeFinance finance;
  late ContactFormController controller;

  setUp(() {
    Get.testMode = true;
    finance = FakeFinance();
    controller = ContactFormController(
      finance.repositories.contacts,
      finance.repositories.transactions,
      finance.repositories.accounts,
      finance.repositories.categories,
      DataChangeNotifier(),
    );
  });

  tearDown(Get.reset);

  Future<Transaction> save(ContactTransactionType type) async {
    final String id = 'entry-${type.name}';
    expect(
      await controller.saveEntry(
        id: id,
        contactId: 'c-amit',
        contactName: 'Amit',
        type: type,
        amount: Decimal.parse('500'),
        date: DateTime(2026, 10, 30),
        dueDate: null,
        note: null,
        accountId: 'acc-cash',
      ),
      isTrue,
    );
    final String txId = ContactFormController.linkedTransactionId(id);
    return finance.transactions.singleWhere((Transaction t) => t.id == txId);
  }

  test('the account row of a khata entry gets its matching category', () async {
    final Transaction lent = await save(ContactTransactionType.credit);
    expect(lent.type, TransactionType.payment_made);
    expect(lent.categoryId, 'system-khata_lent');

    final Transaction borrowed = await save(ContactTransactionType.debit);
    expect(borrowed.type, TransactionType.payment_received);
    expect(borrowed.categoryId, 'system-khata_borrowed');

    expect(
      (await save(ContactTransactionType.paymentReceived)).categoryId,
      'system-khata_repayment_received',
    );
    expect(
      (await save(ContactTransactionType.paymentMade)).categoryId,
      'system-khata_repayment_made',
    );
  });
}
