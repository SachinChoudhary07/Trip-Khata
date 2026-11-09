import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/categories.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../expenses/domain/split_calculator.dart';
import '../trips/data/trip_repository.dart';
import '../trips/presentation/trip_detail_cubit.dart';
import 'place_types.dart';
import 'route_page.dart' show osmTiles, osmAttribution;

/// Save where you are right now. GPS works without internet; the map
/// tiles load only when there is a network.
class CheckInPage extends StatelessWidget {
  const CheckInPage({super.key, required this.tripId});
  final String tripId;

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (c) => TripDetailCubit(c.read<TripRepository>(), tripId),
        child: _CheckInView(tripId: tripId),
      );
}

class _CheckInView extends StatefulWidget {
  const _CheckInView({required this.tripId});
  final String tripId;

  @override
  State<_CheckInView> createState() => _CheckInViewState();
}

class _CheckInViewState extends State<_CheckInView> {
  final _name = TextEditingController();
  final _note = TextEditingController();
  final _amount = TextEditingController();
  ExpenseCategory _type = ExpenseCategory.stay;
  bool _withExpense = true;
  LatLng? _pos;
  String _gps = 'Finding your location…';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() => _gps = 'Location is off. Turn it on to pin this place.');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        setState(() => _gps = 'Location permission denied. The stop is saved without a pin.');
        return;
      }
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && mounted) {
        setState(() {
          _pos = LatLng(last.latitude, last.longitude);
          _gps = 'Approximate location';
        });
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
      );
      if (!mounted) return;
      setState(() {
        _pos = LatLng(p.latitude, p.longitude);
        _gps = 'GPS · ${p.latitude.toStringAsFixed(4)}, ${p.longitude.toStringAsFixed(4)} · works offline';
      });
    } catch (_) {
      if (mounted && _pos == null) setState(() => _gps = 'Could not get a GPS fix. The stop is saved without a pin.');
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim().isEmpty
        ? placeTypes.firstWhere((t) => t.$1 == _type).$2
        : _name.text.trim();
    final amount = rupeesTextToPaise(_amount.text.replaceAll(',', '').trim());
    final s = context.read<TripDetailCubit>().state;
    if (_withExpense && amount > 0 && s.me == null) return;
    setState(() => _saving = true);
    final repo = context.read<TripRepository>();
    final placeId = await repo.addPlace(
      tripId: widget.tripId,
      name: name,
      type: _type.name,
      lat: _pos?.latitude,
      lng: _pos?.longitude,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    );
    if (_withExpense && amount > 0) {
      final ids = s.members.map((m) => m.id).toList();
      final shares = SplitCalculator.equally(amount, ids, payerId: s.me!.id);
      await repo.addExpense(
        tripId: widget.tripId,
        title: name,
        amount: amount,
        category: _type.name,
        paidBy: s.me!.id,
        shares: [for (final e in shares.entries) NewShare(e.key, e.value)],
        placeId: placeId,
      );
    }
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => context.pop()),
        title: const Text('Check in'),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Save stop'),
          ),
        ),
      ),
      body: ListView(children: [
        SizedBox(
          height: 180,
          child: Stack(children: [
            if (_pos != null)
              FlutterMap(
                key: ValueKey(_pos),
                options: MapOptions(
                  initialCenter: _pos!,
                  initialZoom: 15,
                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                ),
                children: [
                  osmTiles(),
                  MarkerLayer(markers: [
                    Marker(
                      point: _pos!,
                      width: 44,
                      height: 44,
                      alignment: Alignment.topCenter,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: -30, end: 0),
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.bounceOut,
                        builder: (_, dy, child) => Transform.translate(offset: Offset(0, dy), child: child),
                        child: const Icon(Icons.location_on, size: 44, color: AppColors.primary),
                      ),
                    ),
                  ]),
                  osmAttribution(),
                ],
              )
            else
              Container(
                color: const Color(0xFFE9ECE6),
                alignment: Alignment.center,
                child: const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5)),
              ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [BoxShadow(color: Color(0x1F15181C), blurRadius: 8, offset: Offset(0, 2))],
                ),
                child: Row(children: [
                  const Icon(Icons.my_location, size: 18, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_gps, style: const TextStyle(fontSize: 13))),
                ]),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('What is this place?',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.5,
              children: [
                for (final t in placeTypes)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      color: t.$1 == _type ? AppColors.primarySoft : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: t.$1 == _type ? AppColors.primary : AppColors.border,
                        width: t.$1 == _type ? 1.5 : 1,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => setState(() => _type = t.$1),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(t.$1.icon, color: t.$1.fg),
                        const SizedBox(height: 6),
                        Text(t.$2, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name', hintText: 'Lake view hotel'),
            ),
            const SizedBox(height: 12),
            TextField(controller: _note, decoration: const InputDecoration(labelText: 'Note (optional)')),
            const SizedBox(height: 12),
            Material(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: SwitchListTile(
                title: const Text('Also add an expense', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(_withExpense ? 'Paid by you · split with everyone' : 'Only save the place'),
                value: _withExpense,
                onChanged: (v) => setState(() => _withExpense = v),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              child: _withExpense
                  ? Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: TextField(
                        controller: _amount,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ '),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ]),
        ),
      ]),
    );
  }
}
