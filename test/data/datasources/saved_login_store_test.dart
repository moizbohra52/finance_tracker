import 'package:finance_tracker/data/datasources/local/saved_login_store.dart';
import 'package:finance_tracker/domain/entities/saved_login.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

SavedLogin _login(String id, DateTime usedAt, {String? name}) => SavedLogin(
  userId: id,
  email: '$id@example.com',
  displayName: name,
  lastUsedAt: usedAt,
);

void main() {
  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    preferences = await SharedPreferences.getInstance();
  });

  test('lists the most recently used account first', () async {
    final SavedLoginStore store = SavedLoginStore(preferences);
    await store.save(_login('a', DateTime(2026)), session: 's-a');
    await store.save(_login('b', DateTime(2026, 3)), session: 's-b');

    expect(store.logins().map((SavedLogin l) => l.userId), <String>['b', 'a']);
    expect(store.sessionFor('a'), 's-a');
  });

  test('survives a restart', () async {
    await SavedLoginStore(
      preferences,
    ).save(_login('a', DateTime(2026), name: 'Asha'), session: 's-a');

    final SavedLoginStore restarted = SavedLoginStore(preferences);
    expect(restarted.logins().single.label, 'Asha');
    expect(restarted.sessionFor('a'), 's-a');
  });

  test('an update without a session keeps the saved one', () async {
    final SavedLoginStore store = SavedLoginStore(preferences);
    await store.save(_login('a', DateTime(2026)), session: 's-a');
    await store.save(_login('a', DateTime(2026, 2), name: 'Asha'));

    expect(store.logins().single.displayName, 'Asha');
    expect(store.sessionFor('a'), 's-a');
  });

  test('removing an account forgets its session', () async {
    final SavedLoginStore store = SavedLoginStore(preferences);
    await store.save(_login('a', DateTime(2026)), session: 's-a');
    await store.save(_login('b', DateTime(2026)), session: 's-b');
    await store.remove('a');

    expect(store.login('a'), isNull);
    expect(store.sessionFor('a'), isNull);
    expect(SavedLoginStore(preferences).logins().single.userId, 'b');
  });

  test('unreadable stored data means no saved accounts, not a crash', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auth.saved_logins': '{not json',
    });
    final SavedLoginStore store = SavedLoginStore(
      await SharedPreferences.getInstance(),
    );
    expect(store.logins(), isEmpty);
  });

  test('the label falls back to the email when there is no name', () {
    expect(_login('ravi', DateTime(2026)).label, 'ravi');
    expect(_login('ravi', DateTime(2026)).initial, 'R');
    expect(_login('ravi', DateTime(2026), name: ' ').label, 'ravi');
  });
}
