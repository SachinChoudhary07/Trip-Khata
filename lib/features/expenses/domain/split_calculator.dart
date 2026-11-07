/// Pure split maths. All amounts are in paise (₹1 = 100 paise) so there are
/// no floating point rounding errors.
library;

enum SplitMode { equally, byAmount, byShares }

class SplitCalculator {
  const SplitCalculator._();

  /// Splits [amount] equally between [memberIds].
  ///
  /// Leftover paise (e.g. ₹100 / 3) go to the payer when the payer is part of
  /// the split, otherwise to the first member, so shares always add up to
  /// exactly [amount].
  static Map<String, int> equally(
    int amount,
    List<String> memberIds, {
    String? payerId,
  }) {
    if (memberIds.isEmpty) return const {};
    final n = memberIds.length;
    final base = amount ~/ n;
    final leftover = amount - base * n;
    final result = {for (final id in memberIds) id: base};
    final receiver =
        (payerId != null && result.containsKey(payerId)) ? payerId : memberIds.first;
    result[receiver] = result[receiver]! + leftover;
    return result;
  }

  /// Splits [amount] by weights, e.g. {a: 2, b: 1} for 2 rooms : 1 room.
  static Map<String, int> byShares(
    int amount,
    Map<String, int> weights, {
    String? payerId,
  }) {
    final active = {
      for (final e in weights.entries)
        if (e.value > 0) e.key: e.value,
    };
    if (active.isEmpty) return const {};
    final total = active.values.fold<int>(0, (a, b) => a + b);
    final result = <String, int>{};
    var assigned = 0;
    for (final e in active.entries) {
      final part = amount * e.value ~/ total;
      result[e.key] = part;
      assigned += part;
    }
    final receiver = (payerId != null && result.containsKey(payerId))
        ? payerId
        : active.keys.first;
    result[receiver] = result[receiver]! + (amount - assigned);
    return result;
  }

  /// True when exact per-person amounts add up to [amount].
  static bool isValidByAmount(int amount, Map<String, int> parts) =>
      parts.values.every((v) => v >= 0) &&
      parts.values.fold<int>(0, (a, b) => a + b) == amount;
}
