/// Turns a spoken Hinglish sentence into expense fields, without any AI API.
///
/// "Rahul ne 1500 ka petrol bharwaya, sab mein baant do"
///   -> amount 150000 paise, payer Rahul, category fuel, split with everyone.
library;

import '../../../core/categories.dart';

class ParserMember {
  const ParserMember({required this.id, required this.name, this.isMe = false});
  final String id;
  final String name;
  final bool isMe;
}

class ParsedExpense {
  const ParsedExpense({
    this.amount,
    this.payerId,
    this.category,
    this.splitWith,
    required this.transcript,
  });

  /// Paise.
  final int? amount;
  final String? payerId;
  final ExpenseCategory? category;

  /// null = everyone on the trip.
  final List<String>? splitWith;
  final String transcript;
}

class HinglishParser {
  HinglishParser(this.members);
  final List<ParserMember> members;

  static const _units = <String, double>{
    'ek': 1, 'do': 2, 'teen': 3, 'char': 4, 'chaar': 4, 'paanch': 5, 'panch': 5,
    'chhe': 6, 'che': 6, 'saat': 7, 'aath': 8, 'nau': 9, 'das': 10,
    'gyarah': 11, 'barah': 12, 'terah': 13, 'chaudah': 14, 'pandrah': 15,
    'solah': 16, 'satrah': 17, 'atharah': 18, 'unnis': 19, 'bees': 20,
    'pachees': 25, 'tees': 30, 'chalis': 40, 'pachas': 50, 'saath': 60,
    'sattar': 70, 'assi': 80, 'nabbe': 90,
    'dedh': 1.5, 'dhai': 2.5, 'sawa': 1.25, 'adha': 0.5,
    'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6,
    'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10, 'fifteen': 15,
    'twenty': 20, 'fifty': 50,
  };
  static const _hundred = {'sau', 'so', 'hundred'};
  static const _thousand = {'hazaar', 'hazar', 'hajar', 'thousand', 'k'};
  static const _lakh = {'lakh', 'lac'};

  static const _payerMarkers = {'ne', 'paid', 'diya', 'diye', 'di', 'pay', 'kiya'};
  static const _meWords = {'maine', 'mene', 'mainne', 'i'};
  static const _meInSplit = {'mere', 'mera', 'meri', 'me', 'mujhe', 'mai', 'main', 'myself'};
  static const _everyone = {'sab', 'sabme', 'sabmein', 'sabka', 'sabke', 'everyone', 'all', 'sabhi'};

  ParsedExpense parse(String input) {
    final tokens = _tokenize(input);
    return ParsedExpense(
      transcript: input,
      amount: _amount(tokens),
      payerId: _payer(tokens),
      category: _category(tokens),
      splitWith: _split(tokens),
    );
  }

  List<String> _tokenize(String s) {
    var t = s.toLowerCase();
    t = t.replaceAllMapped(RegExp(r'(\d),(\d)'), (m) => '${m[1]}${m[2]}');
    t = t.replaceAll('₹', ' ');
    t = t.replaceAllMapped(RegExp(r'(\d)(k)\b'), (m) => '${m[1]} k');
    t = t.replaceAll(RegExp(r'[^a-z0-9ऀ-ॿ.\s]'), ' ');
    return t
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && w != 'rs' && w != 'rupay' && w != 'rupaye' && w != 'rupees')
        .toList();
  }

  /// Largest number spoken in the sentence, in paise.
  int? _amount(List<String> tokens) {
    final candidates = <double>[];
    double total = 0;
    double? chunk;
    var active = false;

    void flush() {
      if (active) candidates.add(total + (chunk ?? 0));
      total = 0;
      chunk = null;
      active = false;
    }

    for (final w in tokens) {
      final digit = double.tryParse(w);
      if (digit != null) {
        if (chunk != null) flush();
        chunk = (chunk ?? 0) + digit;
        active = true;
      } else if (_units.containsKey(w)) {
        chunk = (chunk ?? 0) + _units[w]!;
        active = true;
      } else if (_hundred.contains(w) && active) {
        chunk = (chunk ?? 1) * 100;
      } else if (_thousand.contains(w) && active) {
        total += (chunk ?? 1) * 1000;
        chunk = null;
      } else if (_lakh.contains(w) && active) {
        total += (chunk ?? 1) * 100000;
        chunk = null;
      } else {
        flush();
      }
    }
    flush();
    if (candidates.isEmpty) return null;
    candidates.sort();
    final rupees = candidates.last;
    if (rupees <= 0) return null;
    return (rupees * 100).round();
  }

  ParserMember? _memberFor(String w) {
    for (final m in members) {
      final first = m.name.toLowerCase().split(' ').first;
      if (w == first || w == m.name.toLowerCase()) return m;
    }
    return null;
  }

  ParserMember? get _me {
    for (final m in members) {
      if (m.isMe) return m;
    }
    return null;
  }

  String? _payer(List<String> tokens) {
    for (var i = 0; i < tokens.length; i++) {
      final w = tokens[i];
      if (_meWords.contains(w) && _me != null) {
        if (w != 'i' || (i + 1 < tokens.length && _payerMarkers.contains(tokens[i + 1]))) {
          return _me!.id;
        }
      }
      final m = _memberFor(w);
      if (m != null && i + 1 < tokens.length && _payerMarkers.contains(tokens[i + 1])) {
        return m.id;
      }
    }
    for (final w in tokens) {
      final m = _memberFor(w);
      if (m != null) return m.id;
    }
    return null;
  }

  ExpenseCategory? _category(List<String> tokens) {
    for (final w in tokens) {
      for (final c in ExpenseCategory.values) {
        if (c.keywords.contains(w)) return c;
      }
    }
    return null;
  }

  List<String>? _split(List<String> tokens) {
    if (tokens.any(_everyone.contains)) return null;
    final payer = _payer(tokens);
    final ids = <String>[];
    var payerSeen = false;
    for (var i = 0; i < tokens.length; i++) {
      final m = _memberFor(tokens[i]);
      if (m == null) continue;
      // Skip the first mention of the payer ("Rahul ne ..."), keep later ones.
      if (m.id == payer && !payerSeen) {
        payerSeen = true;
        continue;
      }
      if (!ids.contains(m.id)) ids.add(m.id);
    }
    final me = _me;
    final mentionsMe = tokens.any(_meInSplit.contains);
    if (me != null && mentionsMe && !ids.contains(me.id) && ids.isNotEmpty) {
      ids.add(me.id);
    } else if (me != null && mentionsMe && ids.isEmpty && payer != me.id) {
      ids.add(me.id);
    }
    if (ids.isEmpty) return null;
    if (payer != null && !ids.contains(payer) && _sharesWithPayer(tokens)) ids.add(payer);
    return ids;
  }

  bool _sharesWithPayer(List<String> tokens) =>
      tokens.contains('beech') ||
      tokens.contains('between') ||
      tokens.contains('aur') ||
      tokens.contains('with') ||
      tokens.contains('saath');
}
