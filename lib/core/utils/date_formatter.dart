import 'package:intl/intl.dart';

class DateFormatter {
  DateFormatter._();

  static String full(DateTime dt) =>
      DateFormat('dd MMM yyyy, HH:mm', 'fr_HT').format(dt);

  static String short(DateTime dt) =>
      DateFormat('dd/MM/yy HH:mm', 'fr_HT').format(dt);

  static String dayOnly(DateTime dt) =>
      DateFormat('dd MMM yyyy', 'fr_HT').format(dt);

  static String receiptStamp(DateTime dt) =>
      DateFormat('dd/MM/yyyy HH:mm:ss').format(dt);
}
