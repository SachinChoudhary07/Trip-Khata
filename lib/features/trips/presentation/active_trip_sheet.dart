import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import 'trips_cubit.dart';

/// "Which trip are you on?" Picks the one active trip and returns its id.
Future<String?> pickActiveTrip(BuildContext context) async {
  final cubit = context.read<TripsCubit>();
  final trips = cubit.state.trips;
  if (trips.isEmpty) return null;
  final id = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * 0.7),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text('Which trip are you on?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('One trip is active at a time. Quick add, voice and the home screen widget add to it.',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.35)),
          ),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final t in trips)
                ListTile(
                  leading: const Icon(Icons.luggage_outlined),
                  title: Text(t.trip.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${t.members.length} people · ${formatPaise(t.total)} spent'),
                  trailing: t.trip.id == cubit.state.activeId
                      ? const Icon(Icons.check_circle, color: AppColors.primary)
                      : null,
                  onTap: () => Navigator.pop(c, t.trip.id),
                ),
            ]),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    ),
  );
  if (id != null) await cubit.setActive(id);
  return id;
}
