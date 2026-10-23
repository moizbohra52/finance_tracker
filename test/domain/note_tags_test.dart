import 'package:finance_tracker/domain/services/note_tags.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('finds #words in any script, once each, in order', () {
    expect(
      NoteTags.of('Dinner #Office with team #goa #office, #शादी'),
      <String>['#Office', '#goa', '#शादी'],
    );
  });

  test('numbers, bare # and underscores do not make tags', () {
    expect(NoteTags.of('Invoice #2 # paid'), isEmpty);
    expect(NoteTags.of('#goa_trip'), <String>['#goa']);
    expect(NoteTags.of(null), isEmpty);
  });

  test('add appends a tag once', () {
    expect(NoteTags.add('', '#goa'), '#goa');
    expect(NoteTags.add('Dinner  ', '#goa'), 'Dinner #goa');
    expect(NoteTags.add('Dinner #Goa', '#goa'), 'Dinner #Goa');
  });
}
