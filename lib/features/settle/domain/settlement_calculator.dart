/// Balances and "fewest payments" settle-up. Amounts in paise.
library;

import 'package:equatable/equatable.dart';

class PaymentEntry {
  const PaymentEntry(this.payerId, this.amount);
  final String payerId;
  final int amount;
}

class ShareEntry {
  const ShareEntry(this.memberId, this.amount);
  final String memberId;
  final int amount;
}

class SettledEntry {
  const SettledEntry(this.fromId, this.toId, this.amount);
  final String fromId;
  final String toId;
  final int amount;
}

class Transfer extends Equatable {
  const Transfer(this.fromId, this.toId, this.amount);
  final String fromId;
  final String toId;
  final int amount;

  @override
  List<Object?> get props => [fromId, toId, amount];

  @override
  String toString() => '$fromId -> $toId: $amount';
}

class SettlementCalculator {
  const SettlementCalculator._();

  /// balance = paid - shares (+ settlements sent - settlements received).
  /// Positive = gets money back, negative = owes. Always sums to zero.
  static Map<String, int> balances({
    required Iterable<String> memberIds,
    required Iterable<PaymentEntry> payments,
    required Iterable<ShareEntry> shares,
    Iterable<SettledEntry> settlements = const [],
  }) {
    final b = {for (final id in memberIds) id: 0};
    for (final p in payments) {
      b[p.payerId] = (b[p.payerId] ?? 0) + p.amount;
    }
    for (final s in shares) {
      b[s.memberId] = (b[s.memberId] ?? 0) - s.amount;
    }
    for (final s in settlements) {
      b[s.fromId] = (b[s.fromId] ?? 0) + s.amount;
      b[s.toId] = (b[s.toId] ?? 0) - s.amount;
    }
    return b;
  }

  /// Greedy: biggest debtor pays biggest creditor until everyone is at zero.
  /// Needs at most n - 1 payments for n people.
  static List<Transfer> simplify(Map<String, int> balances) {
    final debtors = <MapEntry<String, int>>[];
    final creditors = <MapEntry<String, int>>[];
    balances.forEach((id, v) {
      if (v < 0) debtors.add(MapEntry(id, -v));
      if (v > 0) creditors.add(MapEntry(id, v));
    });
    int byAmountDesc(MapEntry<String, int> a, MapEntry<String, int> b) {
      final c = b.value.compareTo(a.value);
      return c != 0 ? c : a.key.compareTo(b.key);
    }

    final result = <Transfer>[];
    while (debtors.isNotEmpty && creditors.isNotEmpty) {
      debtors.sort(byAmountDesc);
      creditors.sort(byAmountDesc);
      final d = debtors.first;
      final c = creditors.first;
      final pay = d.value < c.value ? d.value : c.value;
      result.add(Transfer(d.key, c.key, pay));
      debtors[0] = MapEntry(d.key, d.value - pay);
      creditors[0] = MapEntry(c.key, c.value - pay);
      debtors.removeWhere((e) => e.value == 0);
      creditors.removeWhere((e) => e.value == 0);
    }
    return result;
  }
}
