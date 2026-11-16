import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:finance_tracker/features/import/services/import_file_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads the biggest sheet of an .xlsx, dates as yyyy-MM-dd', () {
    final Excel book = Excel.createExcel();
    book['Cover'].appendRow(<CellValue>[TextCellValue('Statement')]);
    book['Rows']
      ..appendRow(<CellValue>[TextCellValue('Date'), TextCellValue('Amount')])
      ..appendRow(<CellValue>[
        const DateCellValue(year: 2026, month: 11, day: 3),
        const DoubleCellValue(-450.5),
      ])
      ..appendRow(<CellValue>[
        TextCellValue('04/11/2026'),
        const IntCellValue(90),
      ]);
    final List<int> bytes = book.encode()!;

    expect(
      readImportFile((
        name: 'Statement.XLSX',
        bytes: Uint8List.fromList(bytes),
      )),
      <List<String>>[
        <String>['Date', 'Amount'],
        <String>['2026-11-03', '-450.5'],
        <String>['04/11/2026', '90'],
      ],
    );
  });

  test('reads a CSV with a byte order mark and semicolons', () {
    final Uint8List bytes = Uint8List.fromList(<int>[
      0xEF, 0xBB, 0xBF, //
      ...utf8.encode('Date;Amount\n01/11/2026;"1,200.00"\n'),
    ]);
    expect(readImportFile((name: 'a.csv', bytes: bytes)), <List<String>>[
      <String>['Date', 'Amount'],
      <String>['01/11/2026', '1,200.00'],
    ]);
  });

  test('asks for .xlsx or .csv instead of an old .xls', () {
    expect(
      () => readImportFile((name: 'old.xls', bytes: Uint8List(0))),
      throwsA(isA<ImportFileException>()),
    );
  });
}
