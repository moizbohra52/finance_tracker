import 'package:finance_tracker/core/utils/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('email', () {
    expect(Validators.email(''), 'Enter your email');
    expect(Validators.email('asha@'), 'Enter a valid email address');
    expect(Validators.email('asha@example'), 'Enter a valid email address');
    expect(Validators.email(' asha@example.com '), isNull);
  });

  test('new password policy matches the server settings', () {
    expect(Validators.newPassword(''), 'Enter a password');
    expect(Validators.newPassword('abc123'), 'Use at least 8 characters');
    expect(Validators.newPassword('abcdefgh'), 'Use both letters and numbers');
    expect(Validators.newPassword('12345678'), 'Use both letters and numbers');
    expect(Validators.newPassword('secret123'), isNull);
  });

  test('confirm password compares with the current value', () {
    String password = 'secret123';
    final String? Function(String?) confirm = Validators.confirmPassword(
      () => password,
    );
    expect(confirm(''), 'Confirm your password');
    expect(confirm('secret123'), isNull);
    password = 'changed123';
    expect(confirm('secret123'), 'Passwords do not match');
  });

  test('required field and optional mobile', () {
    expect(Validators.requiredField('  ', 'name'), 'Enter your name');
    expect(Validators.requiredField('Asha', 'name'), isNull);
    expect(Validators.optionalMobile(''), isNull);
    expect(Validators.optionalMobile('+91 98765 43210'), isNull);
    expect(Validators.optionalMobile('12ab'), 'Enter a valid mobile number');
  });
}
