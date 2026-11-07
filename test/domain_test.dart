import 'package:flutter_test/flutter_test.dart';
import 'package:tripkhata/core/categories.dart';
import 'package:tripkhata/features/expenses/domain/split_calculator.dart';
import 'package:tripkhata/features/settle/domain/settlement_calculator.dart';
import 'package:tripkhata/features/voice/domain/hinglish_parser.dart';

void main() {
  group('SplitCalculator', () {
    test('keychain: ₹100 between 2 of 3 people', () {
      final s = SplitCalculator.equally(10000, ['rahul', 'aman'], payerId: 'rahul');
      expect(s, {'rahul': 5000, 'aman': 5000});
    });

    test('leftover paise go to the payer', () {
      final s = SplitCalculator.equally(10000, ['a', 'b', 'c'], payerId: 'b');
      expect(s, {'a': 3333, 'b': 3334, 'c': 3333});
      expect(s.values.reduce((x, y) => x + y), 10000);
    });

    test('by shares 2:1', () {
      final s = SplitCalculator.byShares(9000, {'a': 2, 'b': 1});
      expect(s, {'a': 6000, 'b': 3000});
    });
  });

  group('SettlementCalculator', () {
    test('keychain example leaves Priya untouched', () {
      final b = SettlementCalculator.balances(
        memberIds: ['rahul', 'aman', 'priya'],
        payments: const [PaymentEntry('rahul', 10000)],
        shares: const [ShareEntry('rahul', 5000), ShareEntry('aman', 5000)],
      );
      expect(b, {'rahul': 5000, 'aman': -5000, 'priya': 0});
      expect(SettlementCalculator.simplify(b), const [Transfer('aman', 'rahul', 5000)]);
    });

    test('balances always sum to zero and simplify clears them', () {
      final b = {'sachin': -105000, 'rahul': 211000, 'aman': 38000, 'priya': 124000, 'neha': -132500, 'vikas': -135500};
      expect(b.values.reduce((x, y) => x + y), 0);
      final transfers = SettlementCalculator.simplify(b);
      expect(transfers.length, lessThanOrEqualTo(5));
      final after = Map.of(b);
      for (final t in transfers) {
        after[t.fromId] = after[t.fromId]! + t.amount;
        after[t.toId] = after[t.toId]! - t.amount;
      }
      expect(after.values.every((v) => v == 0), isTrue);
    });

    test('a settlement moves balances back towards zero', () {
      final b = SettlementCalculator.balances(
        memberIds: ['a', 'b'],
        payments: const [PaymentEntry('a', 2000)],
        shares: const [ShareEntry('a', 1000), ShareEntry('b', 1000)],
        settlements: const [SettledEntry('b', 'a', 1000)],
      );
      expect(b, {'a': 0, 'b': 0});
    });
  });

  group('HinglishParser', () {
    final parser = HinglishParser(const [
      ParserMember(id: 'me', name: 'Sachin', isMe: true),
      ParserMember(id: 'rahul', name: 'Rahul'),
      ParserMember(id: 'aman', name: 'Aman'),
      ParserMember(id: 'neha', name: 'Neha'),
    ]);

    test('Rahul ne 1500 ka petrol bharwaya, sab mein baant do', () {
      final r = parser.parse('Rahul ne 1500 ka petrol bharwaya, sab mein baant do');
      expect(r.amount, 150000);
      expect(r.payerId, 'rahul');
      expect(r.category, ExpenseCategory.fuel);
      expect(r.splitWith, isNull);
    });

    test('Aman paid 800 for lunch, split with Neha and me', () {
      final r = parser.parse('Aman paid 800 for lunch, split with Neha and me');
      expect(r.amount, 80000);
      expect(r.payerId, 'aman');
      expect(r.category, ExpenseCategory.food);
      expect(r.splitWith, unorderedEquals(['neha', 'me', 'aman']));
    });

    test('maine dedh hazaar hotel ke diye', () {
      final r = parser.parse('maine dedh hazaar hotel ke diye');
      expect(r.amount, 150000);
      expect(r.payerId, 'me');
      expect(r.category, ExpenseCategory.stay);
    });

    test('pandrah sau ka toll, ₹1,200 style numbers', () {
      expect(parser.parse('pandrah sau ka toll').amount, 150000);
      expect(parser.parse('Rahul ne ₹1,200 diye').amount, 120000);
      expect(parser.parse('2k ka khana').amount, 200000);
    });

    test('keychain only for Rahul and Aman', () {
      final r = parser.parse('Rahul ne 100 ke keychain liye, Rahul aur Aman ke beech');
      expect(r.amount, 10000);
      expect(r.category, ExpenseCategory.shopping);
      expect(r.splitWith, unorderedEquals(['rahul', 'aman']));
    });
  });
}
