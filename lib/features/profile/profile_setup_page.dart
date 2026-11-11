import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/reminders.dart';
import '../../core/theme/app_theme.dart';
import '../trips/data/trip_repository.dart';

/// Name, avatar colour and UPI ID. Used for every new trip you create.
class ProfileSetupPage extends StatefulWidget {
  const ProfileSetupPage({super.key, this.editing = false});
  final bool editing;

  @override
  State<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends State<ProfileSetupPage> {
  final _name = TextEditingController();
  final _upi = TextEditingController();
  int _color = 0;
  bool _saving = false;

  static final _upiPattern = RegExp(r'^[\w.\-]{2,}@[a-zA-Z]{2,}$');

  @override
  void initState() {
    super.initState();
    context.read<TripRepository>().getProfile().then((p) {
      if (p == null || !mounted) return;
      setState(() {
        _name.text = p.name;
        _upi.text = p.upiId ?? '';
        _color = p.colorIndex;
      });
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _upi.dispose();
    super.dispose();
  }

  String get _initials {
    final parts = _name.text.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p.characters.first.toUpperCase()).join();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final upi = _upi.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add your name')));
      return;
    }
    if (upi.isNotEmpty && !_upiPattern.hasMatch(upi)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('That UPI ID looks wrong, e.g. name@okaxis')));
      return;
    }
    setState(() => _saving = true);
    try {
      final repo = context.read<TripRepository>();
      final first = await repo.getProfile() == null;
      await repo.saveProfile(name: name, upiId: upi.isEmpty ? null : upi, colorIndex: _color);
      if (first) await Reminders.setEnabled(true);
      if (!mounted) return;
      widget.editing ? context.pop() : context.go('/home');
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn’t save your profile. Try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final upiOk = _upiPattern.hasMatch(_upi.text.trim());
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: widget.editing
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop())
            : IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/login')),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              disabledBackgroundColor: AppColors.primary,
              disabledForegroundColor: Colors.white,
            ),
            child: _saving
                ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                    ),
                    SizedBox(width: 10),
                    Text('Saving…'),
                  ])
                : Text(widget.editing ? 'Save' : 'Continue'),
          ),
        ),
      ),
      body: ListView(padding: const EdgeInsets.symmetric(horizontal: 24), children: [
        Text(widget.editing ? 'Edit profile' : 'Set up your profile',
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
        const SizedBox(height: 6),
        const Text('This is how friends see you in a trip.', style: TextStyle(fontSize: 15, color: AppColors.textMuted)),
        const SizedBox(height: 28),
        Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.6, end: 1),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutBack,
            builder: (_, v, child) => Transform.scale(scale: v, child: child),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 104,
              height: 104,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.people[_color], shape: BoxShape.circle),
              child: Text(_initials, style: const TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < AppColors.people.length; i++)
            GestureDetector(
              onTap: () => setState(() => _color = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 5),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.people[i],
                  shape: BoxShape.circle,
                  border: Border.all(color: i == _color ? AppColors.text : Colors.white, width: 3),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 28),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Full name'),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _upi,
          keyboardType: TextInputType.emailAddress,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'UPI ID (optional)',
            hintText: 'name@okaxis',
            helperText: 'Friends pay you here when the trip is settled.',
            suffixIcon: upiOk ? const Icon(Icons.check_circle, color: AppColors.primary) : null,
          ),
        ),
        const SizedBox(height: 24),
      ]),
    );
  }
}
