import 'package:decimal/decimal.dart';
import 'package:intl/intl.dart';

class AppFormatters {
  static String currency(Decimal amount) {
    return '\$${amount.toStringAsFixed(2)}';
  }

  static String dateTime(DateTime dateTime) {
    return DateFormat.yMMMd().add_jm().format(dateTime);
  }

  static String date(DateTime date) {
    return DateFormat.yMMMd().format(date);
  }
}