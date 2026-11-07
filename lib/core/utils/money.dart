import 'package:intl/intl.dart';

final _inr = NumberFormat.decimalPattern('en_IN');

/// 150000 paise -> "₹1,500". Shows paise only when they are not zero.
String formatPaise(int paise, {bool sign = false}) {
  final neg = paise < 0;
  final abs = paise.abs();
  final rupees = abs ~/ 100;
  final p = abs % 100;
  final body = p == 0 ? _inr.format(rupees) : '${_inr.format(rupees)}.${p.toString().padLeft(2, '0')}';
  final prefix = neg ? '−' : (sign && paise > 0 ? '+' : '');
  return '$prefix₹$body';
}

/// "1500" typed on the numpad -> 150000 paise.
int rupeesTextToPaise(String text) => (int.tryParse(text) ?? 0) * 100;
