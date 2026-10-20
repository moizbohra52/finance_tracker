import 'package:finance_tracker/features/contacts/services/device_contacts_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeviceContactData', () {
    test('handles single and multiple phones correctly', () {
      const DeviceContactData singlePhone = DeviceContactData(
        id: '1',
        displayName: 'Amit Sharma',
        phones: <String>['+919876543210'],
        email: 'amit@example.com',
      );

      expect(singlePhone.hasPhone, isTrue);
      expect(singlePhone.hasMultiplePhones, isFalse);
      expect(singlePhone.primaryPhone, '+919876543210');

      const DeviceContactData multiPhone = DeviceContactData(
        id: '2',
        displayName: 'Rahul Verma',
        phones: <String>['+919876543210', '+919123456789', '9988776655'],
        email: 'rahul@example.com',
        address: '123 Market Street, Delhi',
        notes: 'Wholesale Supplier',
      );

      expect(multiPhone.hasPhone, isTrue);
      expect(multiPhone.hasMultiplePhones, isTrue);
      expect(multiPhone.primaryPhone, '+919876543210');
      expect(multiPhone.phones.length, 3);
    });

    test('handles empty phones list correctly', () {
      const DeviceContactData noPhone = DeviceContactData(
        id: '3',
        displayName: 'John Doe',
        phones: <String>[],
      );

      expect(noPhone.hasPhone, isFalse);
      expect(noPhone.hasMultiplePhones, isFalse);
      expect(noPhone.primaryPhone, isNull);
    });
  });
}
