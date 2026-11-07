import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../core/categories.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/common.dart';
import '../../db/app_database.dart';
import '../trips/data/trip_repository.dart';
import '../trips/presentation/trip_detail_cubit.dart';

/// OpenStreetMap tiles. Free for light use under the OSM tile policy:
/// a real app id as user agent, attribution shown, no bulk downloads.
TileLayer osmTiles() => TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.tripkhata.tripkhata',
      maxZoom: 19,
    );

Widget osmAttribution() => const RichAttributionWidget(
      showFlutterMapAttribution: false,
      attributions: [TextSourceAttribution('OpenStreetMap contributors')],
    );

class RoutePage extends StatelessWidget {
  const RoutePage({super.key, required this.tripId});
  final String tripId;

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (c) => TripDetailCubit(c.read<TripRepository>(), tripId),
        child: _RouteView(tripId: tripId),
      );
}

class _RouteView extends StatefulWidget {
  const _RouteView({required this.tripId});
  final String tripId;

  @override
  State<_RouteView> createState() => _RouteViewState();
}

class _RouteViewState extends State<_RouteView> {
  ExpenseCategory? _filter;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<TripRepository>();
    return StreamBuilder<List<Place>>(
      stream: repo.watchPlaces(widget.tripId),
      builder: (context, snap) => BlocBuilder<TripDetailCubit, TripDetailState>(builder: (context, s) {
        final places = snap.data ?? const <Place>[];
        final spentAt = <String, int>{};
        for (final e in s.expenses) {
          if (e.placeId != null) spentAt[e.placeId!] = (spentAt[e.placeId!] ?? 0) + e.amount;
        }
        final pinned = places.where((p) => p.lat != null && p.lng != null).toList();
        final points = [for (final p in pinned) LatLng(p.lat!, p.lng!)];
        var km = 0.0;
        const dist = Distance();
        for (var i = 1; i < points.length; i++) {
          km += dist.as(LengthUnit.Meter, points[i - 1], points[i]) / 1000;
        }
        final onRoad = spentAt.values.fold<int>(0, (a, v) => a + v);
        final shown = _filter == null ? places : places.where((p) => p.type == _filter!.name).toList();

        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => context.push('/trip/${widget.tripId}/checkin'),
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            icon: const Icon(Icons.location_on_outlined),
            label: const Text('Check in here', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          body: Column(children: [
            SizedBox(
              height: 330,
              child: Stack(children: [
                Positioned.fill(child: _map(points, pinned)),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(children: [
                      Material(
                        color: Colors.white,
                        shape: const CircleBorder(),
                        elevation: 2,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => context.pop(),
                          child: const SizedBox(width: 44, height: 44, child: Icon(Icons.arrow_back)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(children: [
                            _FilterChip(label: 'All stops', on: _filter == null, onTap: () => setState(() => _filter = null)),
                            for (final c in const [ExpenseCategory.fuel, ExpenseCategory.food, ExpenseCategory.stay])
                              _FilterChip(label: c.label, on: _filter == c, onTap: () => setState(() => _filter = c)),
                          ]),
                        ),
                      ),
                    ]),
                  ),
                ),
              ]),
            ),
            Expanded(
              child: Transform.translate(
                offset: const Offset(0, -20),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    boxShadow: [BoxShadow(color: Color(0x1415181C), blurRadius: 10, offset: Offset(0, -2))],
                  ),
                  child: Column(children: [
                    const SizedBox(height: 10),
                    Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                      child: Row(children: [
                        _Stat(label: 'Distance', value: points.length < 2 ? '—' : '~${km.round()} km'),
                        _Stat(label: 'Stops', value: '${places.length}'),
                        _Stat(label: 'Spent at stops', value: formatPaise(onRoad)),
                      ]),
                    ),
                    Expanded(
                      child: places.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(32),
                                child: Text('No stops yet. Tap “Check in here” at a hotel, dhaba or petrol pump.',
                                    textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
                              ),
                            )
                          : _Timeline(places: shown, spentAt: spentAt),
                    ),
                  ]),
                ),
              ),
            ),
          ]),
        );
      }),
    );
  }

  Widget _map(List<LatLng> points, List<Place> pinned) {
    if (points.isEmpty) {
      return Container(
        color: const Color(0xFFE9ECE6),
        alignment: Alignment.center,
        child: const Icon(Icons.map_outlined, size: 48, color: AppColors.border),
      );
    }
    return FlutterMap(
      key: ValueKey(points.length),
      options: MapOptions(
        initialCenter: points.first,
        initialZoom: 12,
        initialCameraFit: points.length > 1
            ? CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.fromLTRB(40, 90, 40, 50))
            : null,
        backgroundColor: const Color(0xFFE9ECE6),
      ),
      children: [
        osmTiles(),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 1400),
          curve: Curves.easeOutCubic,
          builder: (_, t, __) {
            final n = (points.length * t).ceil().clamp(1, points.length).toInt();
            return PolylineLayer(polylines: [
              Polyline(points: points, color: Colors.white, strokeWidth: 9),
              Polyline(points: points.sublist(0, n), color: AppColors.primary, strokeWidth: 5),
            ]);
          },
        ),
        MarkerLayer(markers: [
          for (final (i, p) in pinned.indexed)
            Marker(
              point: LatLng(p.lat!, p.lng!),
              width: 34,
              height: 34,
              child: FadeSlideIn(
                delay: Duration(milliseconds: 500 + 120 * i),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: const [BoxShadow(color: Color(0x3315181C), blurRadius: 6, offset: Offset(0, 2))],
                  ),
                  child: Icon(ExpenseCategory.fromName(p.type).icon, size: 18, color: ExpenseCategory.fromName(p.type).fg),
                ),
              ),
            ),
        ]),
        osmAttribution(),
      ],
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.places, required this.spentAt});
  final List<Place> places;
  final Map<String, int> spentAt;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    DateTime? lastDay;
    var i = 0;
    for (final p in places) {
      final day = DateTime(p.visitedAt.year, p.visitedAt.month, p.visitedAt.day);
      if (day != lastDay) {
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(46, 10, 0, 6),
          child: Text(DateFormat('EEE, d MMM').format(day),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
        ));
        lastDay = day;
      }
      final cat = ExpenseCategory.fromName(p.type);
      final spent = spentAt[p.id];
      rows.add(FadeSlideIn(
        delay: Duration(milliseconds: 300 + 60 * (i < 10 ? i : 10)),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Column(children: [
              CategoryTile(category: cat, size: 32),
              Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 2), color: AppColors.line)),
            ]),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 14),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      Text(
                        [DateFormat('h:mm a').format(p.visitedAt), if (p.note != null) p.note!].join(' · '),
                        style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                      ),
                    ]),
                  ),
                  if (spent != null)
                    Text(formatPaise(spent), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ]),
        ),
      ));
      i++;
    }
    return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 100), children: rows);
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        ]),
      );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Material(
          color: on ? AppColors.text : Colors.white,
          borderRadius: BorderRadius.circular(17),
          elevation: 1,
          child: InkWell(
            borderRadius: BorderRadius.circular(17),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(label,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: on ? Colors.white : AppColors.text)),
            ),
          ),
        ),
      );
}
