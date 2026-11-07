import 'package:flutter_test/flutter_test.dart';
import 'package:tripkhata/core/utils/money.dart';

void main() {
  test('formatPaise uses Indian grouping and hides zero paise', () {
    expect(formatPaise(150000), '₹1,500');
    expect(formatPaise(18450000), '₹1,84,500');
    expect(formatPaise(3334), '₹33.34');
    expect(formatPaise(-105000), '−₹1,050');
    expect(formatPaise(5000, sign: true), '+₹50');
  });
}
