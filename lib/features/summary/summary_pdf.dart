import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/categories.dart';
import '../trips/presentation/trip_detail_cubit.dart';

/// Trip summary as a PDF. Uses "Rs" instead of the rupee sign because the
/// built-in PDF fonts have no ₹ glyph and we don't download fonts.
Future<Uint8List> buildSummaryPdf(TripDetailState s) async {
  final trip = s.trip!;
  final inr = NumberFormat.decimalPattern('en_IN');
  String rs(int paise) {
    final neg = paise < 0;
    final a = paise.abs();
    final body = a % 100 == 0 ? inr.format(a ~/ 100) : '${inr.format(a ~/ 100)}.${(a % 100).toString().padLeft(2, '0')}';
    return '${neg ? '-' : ''}Rs $body';
  }

  String name(String id) {
    final m = s.member(id);
    return m == null ? '?' : (m.isMe ? '${m.name} (you)' : m.name);
  }

  final byCat = <ExpenseCategory, int>{};
  for (final e in s.expenses) {
    final c = ExpenseCategory.fromName(e.category);
    byCat[c] = (byCat[c] ?? 0) + e.amount;
  }
  final cats = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  final teal = PdfColor.fromHex('#0E5E6F');
  final muted = PdfColor.fromHex('#5B636D');
  final line = PdfColor.fromHex('#E4E7EB');
  final df = DateFormat('d MMM yyyy');
  final dates = trip.startDate == null
      ? ''
      : trip.endDate == null
          ? df.format(trip.startDate!)
          : '${df.format(trip.startDate!)} - ${df.format(trip.endDate!)}';

  pw.Widget heading(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 18, bottom: 6),
        child: pw.Text(t, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: teal)),
      );

  final doc = pw.Document(title: '${trip.name} summary', author: 'TripKhata');
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(36),
    footer: (c) => pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text('TripKhata · page ${c.pageNumber} of ${c.pagesCount}', style: pw.TextStyle(fontSize: 9, color: muted)),
    ),
    build: (c) => [
      pw.Text(trip.name, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
      pw.Text('$dates · ${s.members.length} people', style: pw.TextStyle(color: muted)),
      pw.SizedBox(height: 14),
      pw.Row(children: [
        for (final (k, v) in [
          ('Total spent', rs(s.total)),
          ('Per person', rs(s.perPerson)),
          ('Expenses', '${s.expenses.length}'),
        ])
          pw.Expanded(
            child: pw.Container(
              margin: const pw.EdgeInsets.only(right: 8),
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: line), borderRadius: pw.BorderRadius.circular(6)),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(k, style: pw.TextStyle(fontSize: 9, color: muted)),
                pw.Text(v, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
              ]),
            ),
          ),
      ]),
      heading('Where the money went'),
      pw.TableHelper.fromTextArray(
        headers: ['Category', 'Amount', 'Share'],
        data: [
          for (final e in cats) [e.key.label, rs(e.value), '${(e.value * 100 / (s.total == 0 ? 1 : s.total)).round()}%'],
        ],
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
        cellStyle: const pw.TextStyle(fontSize: 10),
        cellAlignments: {1: pw.Alignment.centerRight, 2: pw.Alignment.centerRight},
        border: pw.TableBorder(horizontalInside: pw.BorderSide(color: line, width: 0.5)),
      ),
      heading('Balances'),
      pw.TableHelper.fromTextArray(
        headers: ['Person', 'Balance'],
        data: [
          for (final m in s.members)
            [m.isMe ? '${m.name} (you)' : m.name, (s.balances[m.id] ?? 0) == 0 ? 'Settled' : rs(s.balances[m.id]!)],
        ],
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
        cellStyle: const pw.TextStyle(fontSize: 10),
        cellAlignments: {1: pw.Alignment.centerRight},
        border: pw.TableBorder(horizontalInside: pw.BorderSide(color: line, width: 0.5)),
      ),
      if (s.transfers.isNotEmpty) ...[
        heading('To settle'),
        for (final t in s.transfers)
          pw.Bullet(text: '${name(t.fromId)} pays ${name(t.toId)} ${rs(t.amount)}', style: const pw.TextStyle(fontSize: 10)),
      ],
      heading('All expenses'),
      pw.TableHelper.fromTextArray(
        headers: ['Date', 'What', 'Paid by', 'Split', 'Amount'],
        data: [
          for (final e in s.expenses.reversed)
            [
              DateFormat('d MMM').format(e.spentAt),
              e.title,
              name(e.paidBy),
              '${s.sharesByExpense[e.id]?.length ?? 0} people',
              rs(e.amount),
            ],
        ],
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
        cellStyle: const pw.TextStyle(fontSize: 9),
        cellAlignments: {4: pw.Alignment.centerRight},
        border: pw.TableBorder(horizontalInside: pw.BorderSide(color: line, width: 0.5)),
      ),
    ],
  ));
  return doc.save();
}
