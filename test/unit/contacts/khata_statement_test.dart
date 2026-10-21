import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/services/export_service.dart';
import 'package:finance_tracker/core/services/file_sharing_service.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/features/contacts/controller/contact_detail_controller.dart';
import 'package:finance_tracker/features/contacts/services/reminder_sender_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

import '../../helpers/fake_finance.dart';
import '../../helpers/fakes.dart';

Contact _contact({String type = 'receivable', String opening = '0'}) => Contact(
  id: 'c-1',
  userId: 'u',
  name: 'Ravi Kumar',
  mobile: '9876543210',
  openingBalance: Decimal.parse(opening),
  openingBalanceType: type,
  createdAt: DateTime(2026, 10),
  updatedAt: DateTime(2026, 10),
);

ContactTransaction _entry(
  String id,
  ContactTransactionType type,
  String amount,
  int day,
) => ContactTransaction(
  id: id,
  userId: 'u',
  contactId: 'c-1',
  type: type,
  amount: Decimal.parse(amount),
  transactionDate: DateTime(2026, 10, day),
  note: 'Entry $id',
  createdAt: DateTime(2026, 10, day),
  updatedAt: DateTime(2026, 10, day),
);

final List<ContactTransaction> _ledger = <ContactTransaction>[
  _entry('1', ContactTransactionType.credit, '500', 2),
  _entry('2', ContactTransactionType.paymentReceived, '200', 3),
  _entry('3', ContactTransactionType.debit, '50', 4),
  _entry('4', ContactTransactionType.paymentMade, '20', 5),
];

class _FakeSharing extends FileSharingService {
  String? fileName;
  String? mimeType;
  List<int>? bytes;

  @override
  Future<ShareResult> saveAndShareBytes({
    required String fileName,
    required List<int> bytes,
    String? mimeType,
    String? subject,
  }) async {
    this.fileName = fileName;
    this.mimeType = mimeType;
    this.bytes = bytes;
    return const ShareResult('success', ShareResultStatus.success);
  }
}

void main() {
  group('UPI pay link', () {
    test('fills the payee and amount', () {
      expect(
        ReminderSenderService.buildUpiLink(
          upiId: ' asha@okaxis ',
          payeeName: 'Asha Rao',
          amount: Decimal.parse('1500.5'),
          currencyCode: 'INR',
        ),
        'upi://pay?pa=asha@okaxis&pn=Asha%20Rao&am=1500.50&cu=INR',
      );
    });

    test('is null without a UPI ID, a positive amount, or outside INR', () {
      String? link(String? upiId, String amount, String currency) =>
          ReminderSenderService.buildUpiLink(
            upiId: upiId,
            amount: Decimal.parse(amount),
            currencyCode: currency,
          );

      expect(link(null, '10', 'INR'), isNull);
      expect(link('  ', '10', 'INR'), isNull);
      expect(link('asha@okaxis', '0', 'INR'), isNull);
      expect(link('asha@okaxis', '10', 'USD'), isNull);
    });
  });

  group('reminder message', () {
    test('asks someone who owes the user to pay by UPI', () {
      final String message = ReminderSenderService.buildHinglishMessage(
        contactName: 'Ravi',
        amount: Decimal.parse('250'),
        isReceivable: true,
        upiId: 'asha@okaxis',
      );
      expect(message, contains('asha@okaxis'));
      expect(message, contains('upi://pay?pa=asha@okaxis&am=250.00&cu=INR'));
    });

    test('the Hindi message greets in Hindi and keeps the pay link', () {
      final String message = ReminderSenderService.buildHindiMessage(
        contactName: 'Ravi',
        amount: Decimal.parse('250'),
        isReceivable: true,
        upiId: 'asha@okaxis',
      );
      expect(message, startsWith('नमस्ते Ravi जी,'));
      expect(message, contains('upi://pay?pa=asha@okaxis&am=250.00&cu=INR'));
    });

    test('has no pay link when the user owes, or has no UPI ID', () {
      expect(
        ReminderSenderService.buildEnglishMessage(
          contactName: 'Ravi',
          amount: Decimal.parse('250'),
          isReceivable: false,
          upiId: 'asha@okaxis',
        ),
        isNot(contains('upi://')),
      );
      expect(
        ReminderSenderService.buildEnglishMessage(
          contactName: 'Ravi',
          amount: Decimal.parse('250'),
          isReceivable: true,
        ),
        isNot(contains('upi://')),
      );
    });
  });

  group('ledger', () {
    test('each entry moves the balance by its signed amount', () {
      expect(
        _ledger.map((ContactTransaction e) => e.signedAmount.toString()),
        <String>['500', '-200', '-50', '20'],
      );
      expect(
        _contact(opening: '100').getCurrentBalance(_ledger),
        Decimal.parse('370'),
      );
      expect(
        _contact(type: 'payable', opening: '100').signedOpeningBalance,
        Decimal.parse('-100'),
      );
    });
  });

  group('statement PDF', () {
    test('renders with and without a pay QR, and when empty', () async {
      const ExportService service = ExportService();
      const String link = 'upi://pay?pa=asha@okaxis&am=370.00&cu=INR';
      for (final (List<ContactTransaction> entries, String? payLink)
          in <(List<ContactTransaction>, String?)>[
            (_ledger, null),
            (_ledger, link),
            (<ContactTransaction>[], link),
          ]) {
        final List<int> bytes = await service.generateContactStatementPdf(
          contact: _contact(opening: '100'),
          entries: entries,
          userName: 'Asha Rao',
          upiPayLink: payLink,
          currencyCode: 'INR',
        );
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      }
    });
  });

  group('sharing', () {
    test('shares the ledger as a PDF named after the contact', () async {
      final FakeFinance finance = FakeFinance();
      finance.contacts.add(_contact());
      finance.contactTransactions.addAll(_ledger);
      final _FakeSharing sharing = _FakeSharing();
      final ContactDetailController controller = ContactDetailController(
        finance.repositories.contacts,
        finance.repositories.transactions,
        DataChangeNotifier(),
        'c-1',
        profileRepository: FakeProfileRepository(),
        sharingService: sharing,
      );
      await controller.load();

      expect(await controller.shareStatement(), isTrue);
      expect(sharing.fileName, startsWith('Khata_Ravi_Kumar_'));
      expect(sharing.fileName, endsWith('.pdf'));
      expect(sharing.mimeType, 'application/pdf');
      expect(String.fromCharCodes(sharing.bytes!.take(5)), '%PDF-');
    });
  });
}
