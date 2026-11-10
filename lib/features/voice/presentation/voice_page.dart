import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../../core/categories.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../../db/app_database.dart';
import '../../expenses/domain/split_calculator.dart';
import '../../trips/data/trip_repository.dart';
import '../../trips/presentation/trip_detail_cubit.dart';
import '../domain/hinglish_parser.dart';

/// "Speak to add": listens on the phone, parses Hinglish, lets you confirm.
class VoicePage extends StatelessWidget {
  const VoicePage({super.key, required this.tripId, this.fromWidget = false});
  final String tripId;

  /// Opened from the home screen widget: when done, go back to the home
  /// screen instead of into the app.
  final bool fromWidget;

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (c) => TripDetailCubit(c.read<TripRepository>(), tripId),
        child: BlocBuilder<TripDetailCubit, TripDetailState>(
          buildWhen: (a, b) => a.loading != b.loading,
          builder: (context, s) => s.loading
              ? const Scaffold(body: Center(child: CircularProgressIndicator()))
              : _VoiceView(tripId: tripId, members: s.members, fromWidget: fromWidget),
        ),
      );
}

enum _Phase { starting, listening, done, unavailable }

class _VoiceView extends StatefulWidget {
  const _VoiceView({required this.tripId, required this.members, this.fromWidget = false});
  final String tripId;
  final List<Member> members;
  final bool fromWidget;

  @override
  State<_VoiceView> createState() => _VoiceViewState();
}

class _VoiceViewState extends State<_VoiceView> with TickerProviderStateMixin {
  final _speech = SpeechToText();
  late final HinglishParser _parser = HinglishParser([
    for (final m in widget.members) ParserMember(id: m.id, name: m.name, isMe: m.isMe),
  ]);
  late final AnimationController _ring =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  final _typed = TextEditingController();

  _Phase _phase = _Phase.starting;
  String _transcript = '';
  double _level = 0;
  String? _localeId;

  // Fields the user confirms before saving.
  int? _amount;
  String? _payerId;
  ExpenseCategory _category = ExpenseCategory.other;
  late Set<String> _splitWith = widget.members.map((m) => m.id).toSet();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final ok = await _speech.initialize(
      onStatus: (s) {
        if ((s == 'done' || s == 'notListening') && _phase == _Phase.listening && mounted) {
          _finish();
        }
      },
      onError: (e) {
        if (!mounted) return;
        setState(() => _phase = _transcript.isEmpty ? _Phase.unavailable : _Phase.done);
      },
    );
    if (!mounted) return;
    if (!ok) {
      setState(() => _phase = _Phase.unavailable);
      return;
    }
    final profile = await context.read<TripRepository>().getProfile();
    final locales = await _speech.locales();
    final hindi = locales.where((l) => l.localeId.toLowerCase().startsWith('hi')).firstOrNull;
    final enIn = locales.where((l) => l.localeId.toLowerCase().replaceAll('-', '_') == 'en_in').firstOrNull;
    _localeId = (profile?.voiceLang == 'en' ? (enIn ?? hindi) : (hindi ?? enIn))?.localeId;
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _phase = _Phase.listening;
      _transcript = '';
    });
    await _speech.listen(
      onResult: _onResult,
      localeId: _localeId,
      listenFor: const Duration(seconds: 20),
      pauseFor: const Duration(seconds: 3),
      onSoundLevelChange: (l) {
        if (mounted) setState(() => _level = l);
      },
      listenOptions: SpeechListenOptions(partialResults: true, listenMode: ListenMode.dictation),
    );
  }

  void _onResult(SpeechRecognitionResult r) {
    if (!mounted) return;
    setState(() => _transcript = r.recognizedWords);
    if (r.finalResult) _finish();
  }

  void _finish() {
    _speech.stop();
    _apply(_transcript);
  }

  void _apply(String text) {
    final p = _parser.parse(text);
    setState(() {
      _transcript = text;
      _phase = _Phase.done;
      _amount = p.amount ?? _amount;
      _payerId = p.payerId ?? _payerId ?? widget.members.where((m) => m.isMe).firstOrNull?.id;
      _category = p.category ?? _category;
      _splitWith = (p.splitWith ?? widget.members.map((m) => m.id)).toSet();
    });
  }

  @override
  void dispose() {
    _speech.cancel();
    _ring.dispose();
    _typed.dispose();
    super.dispose();
  }

  Member? _member(String? id) => widget.members.where((m) => m.id == id).firstOrNull;

  Future<void> _editAmount() async {
    final c = TextEditingController(text: _amount == null ? '' : (_amount! ~/ 100).toString());
    final v = await showDialog<int>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Amount'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(prefixText: '₹ '),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, rupeesTextToPaise(c.text.trim())), child: const Text('OK')),
        ],
      ),
    );
    if (v != null && v > 0) setState(() => _amount = v);
  }

  Future<void> _pickPayer() async {
    final id = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final m in widget.members)
            ListTile(
              leading: MemberAvatar(name: m.name, colorIndex: m.colorIndex, size: 36),
              title: Text(m.isMe ? '${m.name} (you)' : m.name),
              trailing: m.id == _payerId ? const Icon(Icons.check, color: AppColors.primary) : null,
              onTap: () => Navigator.pop(c, m.id),
            ),
        ]),
      ),
    );
    if (id != null) setState(() => _payerId = id);
  }

  Future<void> _save() async {
    if (_amount == null || _amount == 0) return _toast('Say or tap an amount');
    if (_payerId == null) return _toast('Who paid?');
    if (_splitWith.isEmpty) return _toast('Pick at least one person');
    setState(() => _saving = true);
    final ordered = widget.members.map((m) => m.id).where(_splitWith.contains).toList();
    final shares = SplitCalculator.equally(_amount!, ordered, payerId: _payerId);
    await context.read<TripRepository>().addExpense(
          tripId: widget.tripId,
          title: _category == ExpenseCategory.other ? 'Expense' : _category.label,
          amount: _amount!,
          category: _category.name,
          paidBy: _payerId!,
          shares: [for (final e in shares.entries) NewShare(e.key, e.value)],
          byVoice: true,
        );
    if (!mounted) return;
    if (widget.fromWidget) {
      _toast('Saved to the trip');
      await Future<void>.delayed(const Duration(milliseconds: 700));
      return _close();
    }
    context.pop();
  }

  /// Back to wherever the user came from: the app, or the home screen when
  /// this was opened from the widget.
  void _close() {
    if (widget.fromWidget) {
      SystemNavigator.pop();
    } else {
      context.pop();
    }
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final listening = _phase == _Phase.listening;
    return Scaffold(
      backgroundColor: const Color(0xFF2B3136),
      body: Column(children: [
        Expanded(child: GestureDetector(onTap: _close, behavior: HitTestBehavior.opaque)),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 1, end: 0),
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          builder: (_, v, child) => FractionalTranslation(translation: Offset(0, v), child: child),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.fromLTRB(20, 10, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
            child: SafeArea(
              top: false,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 14),
                Row(children: [
                  const Expanded(
                    child: Text('Speak to add', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  ),
                  Container(
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(15)),
                    child: const Row(children: [
                      Icon(Icons.language, size: 14, color: AppColors.textMuted),
                      SizedBox(width: 6),
                      Text('Hindi + English',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 18),
                if (_phase != _Phase.unavailable) _mic(listening),
                const SizedBox(height: 14),
                if (_phase == _Phase.unavailable) _typeInstead() else _transcriptBox(),
                if (_phase == _Phase.done) ...[
                  const SizedBox(height: 14),
                  _parsed(),
                ],
                if (_phase == _Phase.listening && _transcript.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text('Try: “Aman paid 800 for lunch, split with Neha and me”',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                  ),
                const SizedBox(height: 18),
                Row(children: [
                  OutlinedButton.icon(
                    onPressed: () => context.pushReplacement('/trip/${widget.tripId}/add'),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Type'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _phase == _Phase.done && !_saving ? _save : null,
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Save'),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _mic(bool listening) => Column(children: [
        GestureDetector(
          onTap: listening ? _finish : _start,
          child: SizedBox(
            width: 96,
            height: 96,
            child: AnimatedBuilder(
              animation: _ring,
              builder: (_, __) => Stack(alignment: Alignment.center, children: [
                if (listening)
                  for (final offset in const [0.0, 0.5])
                    Builder(builder: (_) {
                      final t = (_ring.value + offset) % 1;
                      return Transform.scale(
                        scale: 1 + t * 0.8,
                        child: Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.primary.withValues(alpha: 0.35 * (1 - t)),
                          ),
                        ),
                      );
                    }),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: listening ? AppColors.primary : AppColors.textMuted,
                  ),
                  child: Icon(listening ? Icons.mic : Icons.mic_none, size: 38, color: Colors.white),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 22,
          child: AnimatedBuilder(
            animation: _ring,
            builder: (_, __) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < 9; i++)
                Container(
                  width: 3,
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  height: listening
                      ? 6 + 16 * ((math.sin(_ring.value * 2 * math.pi * 3 + i) + 1) / 2) * (0.4 + (_level.clamp(0, 10) / 10) * 0.6)
                      : 6,
                  decoration: BoxDecoration(
                    color: listening ? AppColors.primary : AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          switch (_phase) {
            _Phase.starting => 'Getting the mic ready…',
            _Phase.listening => 'Listening… tap the mic when done',
            _Phase.done => 'Got it. Check the details, or tap the mic to say it again.',
            _Phase.unavailable => '',
          },
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
      ]);

  Widget _transcriptBox() => AnimatedSize(
        duration: const Duration(milliseconds: 200),
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.line),
          ),
          alignment: Alignment.center,
          child: Text(
            _transcript.isEmpty ? '…' : '“$_transcript”',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, height: 1.45),
          ),
        ),
      );

  /// No speech service (emulator, or Google app missing): type the sentence.
  Widget _typeInstead() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Voice isn’t available on this phone. Type the sentence instead and we’ll fill it in.',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
        const SizedBox(height: 10),
        TextField(
          controller: _typed,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Rahul ne 1500 ka petrol bharwaya'),
          onSubmitted: _apply,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: () => _apply(_typed.text), child: const Text('Fill in')),
        ),
        if (_transcript.isNotEmpty) _parsed(),
      ]);

  Widget _parsed() {
    final payer = _member(_payerId);
    final n = _splitWith.length;
    final rows = <Widget>[
      _ParsedRow(
        lead: const Icon(Icons.currency_rupee, size: 18, color: AppColors.primaryDark),
        label: 'Amount',
        value: _amount == null ? 'Tap to add' : formatPaise(_amount!),
        ok: _amount != null,
        onTap: _editAmount,
      ),
      _ParsedRow(
        lead: payer == null
            ? const Icon(Icons.person_outline, size: 18)
            : MemberAvatar(name: payer.name, colorIndex: payer.colorIndex, size: 28),
        label: 'Paid by',
        value: payer == null ? 'Tap to pick' : (payer.isMe ? 'You' : payer.name),
        ok: payer != null,
        onTap: _pickPayer,
      ),
      _ParsedRow(
        lead: CategoryTile(category: _category, size: 28),
        label: 'Category',
        value: _category.label,
        ok: _category != ExpenseCategory.other,
        onTap: () {
          final all = ExpenseCategory.values;
          setState(() => _category = all[(all.indexOf(_category) + 1) % all.length]);
        },
      ),
      _ParsedRow(
        lead: const Icon(Icons.group_outlined, size: 18, color: AppColors.primaryDark),
        label: 'Split',
        value: n == widget.members.length
            ? 'All $n${_amount == null ? '' : ' · ${formatPaise(_amount! ~/ n)} each'}'
            : '$n people${_amount == null || n == 0 ? '' : ' · ${formatPaise(_amount! ~/ n)} each'}',
        ok: n > 0,
        onTap: null,
      ),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < rows.length; i++)
        FadeSlideIn(delay: Duration(milliseconds: 70 * i), child: Padding(padding: const EdgeInsets.only(bottom: 8), child: rows[i])),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final m in widget.members)
          FilterChip(
            label: Text(m.isMe ? 'You' : m.name),
            selected: _splitWith.contains(m.id),
            showCheckmark: false,
            selectedColor: AppColors.primarySoft,
            onSelected: (v) => setState(() => v ? _splitWith.add(m.id) : _splitWith.remove(m.id)),
          ),
      ]),
    ]);
  }
}

class _ParsedRow extends StatelessWidget {
  const _ParsedRow({required this.lead, required this.label, required this.value, required this.ok, this.onTap});
  final Widget lead;
  final String label;
  final String value;
  final bool ok;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: ok ? AppColors.background : AppColors.yellowSoft,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              SizedBox(width: 28, height: 28, child: Center(child: lead)),
              const SizedBox(width: 10),
              Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textMuted))),
              Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Icon(ok ? Icons.check : Icons.error_outline, size: 16, color: ok ? AppColors.primary : const Color(0xFF8A5A00)),
            ]),
          ),
        ),
      );
}
