import 'package:intl/intl.dart';

class MoneyFormatter {
  MoneyFormatter._();

  static String format(num amount, {String currency = 'USD'}) {
    final f = NumberFormat.currency(
      locale: 'fr_HT',
      symbol: _symbolFor(currency),
      decimalDigits: 2,
    );
    return f.format(amount);
  }

  static String formatPlain(num amount) {
    final f = NumberFormat('#,##0.00', 'fr_HT');
    // Ranplase NBSP (U+00A0) ak espas nòmal pou kòmpatibilite ak printer ESC/POS
    return f.format(amount).replaceAll(' ', ' ');
  }

  static String _symbolFor(String code) {
    switch (code) {
      case 'HTG':
        return 'HTG ';
      case 'USD':
        return '\$';
      default:
        return '$code ';
    }
  }
}
