import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

/// A file the import cannot read, with the reason to show.
class ImportFileException implements Exception {
  const ImportFileException(this.message);

  /// English text, also its translation key.
  final String message;
}

/// Reads a .csv or .xlsx file into rows of text. Top-level and given plain
/// values, so it can run in a background isolate (`compute`).
List<List<String>> readImportFile(({String name, Uint8List bytes}) file) {
  final String name = file.name.toLowerCase();
  if (name.endsWith('.csv') || name.endsWith('.txt')) {
    String text = utf8.decode(file.bytes, allowMalformed: true);
    // Excel's "CSV UTF-8" starts with a byte order mark.
    if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
      text = text.substring(1);
    }
    // Csv() finds the delimiter itself: comma, semicolon or tab.
    return Csv()
        .decode(text)
        .map(
          (List<dynamic> row) => row.map((Object? c) => '${c ?? ''}').toList(),
        )
        .toList();
  }
  if (name.endsWith('.xlsx')) {
    final Excel excel = Excel.decodeBytes(file.bytes);
    // The sheet with the most rows: statements put a cover sheet first.
    Sheet? sheet;
    for (final Sheet s in excel.tables.values) {
      if (sheet == null || s.maxRows > sheet.maxRows) sheet = s;
    }
    return <List<String>>[
      for (final List<Data?> row in sheet?.rows ?? const <List<Data?>>[])
        <String>[for (final Data? cell in row) _text(cell?.value)],
    ];
  }
  // shortcut: old .xls (Excel 97) is a binary format the excel package does
  // not read; add a reader if users keep sending .xls files.
  throw const ImportFileException(
    'Open this file in Excel or Google Sheets and save it as .xlsx or .csv, then import that.',
  );
}

String _text(CellValue? value) => switch (value) {
  null => '',
  DateCellValue() => DateFormat('yyyy-MM-dd').format(value.asDateTimeLocal()),
  DateTimeCellValue() => DateFormat(
    'yyyy-MM-dd HH:mm:ss',
  ).format(value.asDateTimeLocal()),
  TextCellValue() => value.value.toString(),
  _ => value.toString(),
};
