import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../db/app_database.dart';
import '../../settle/domain/settlement_calculator.dart';
import '../data/trip_repository.dart';

class TripSummary extends Equatable {
  const TripSummary({required this.trip, required this.members, required this.total, required this.myBalance});
  final Trip trip;
  final List<Member> members;
  final int total;
  final int myBalance;

  bool get isOngoing {
    final now = DateTime.now();
    final s = trip.startDate, e = trip.endDate;
    if (s == null || e == null) return false;
    return !now.isBefore(s) && !now.isAfter(e.add(const Duration(days: 1)));
  }

  @override
  List<Object?> get props => [trip, members, total, myBalance];
}

class TripsState extends Equatable {
  const TripsState({this.loading = true, this.trips = const [], this.activeId});
  final bool loading;
  final List<TripSummary> trips;
  final String? activeId;

  /// The one active trip (quick add, voice and the home widget go here).
  TripSummary? get active => activeId == null ? null : trips.where((t) => t.trip.id == activeId).firstOrNull;

  List<TripSummary> get past => trips.where((t) => t.trip.id != active?.trip.id).toList();

  @override
  List<Object?> get props => [loading, trips, activeId];
}

/// Home screen data: every trip with its total and your balance.
class TripsCubit extends Cubit<TripsState> {
  TripsCubit(this._repo) : super(const TripsState()) {
    _subs = [
      _repo.watchTrips().listen((v) => _update(trips: v)),
      _repo.watchAllMembers().listen((v) => _update(members: v)),
      _repo.watchAllExpenses().listen((v) => _update(expenses: v)),
      _repo.watchAllShares().listen((v) => _update(shares: v)),
      _repo.watchAllSettlements().listen((v) => _update(settlements: v)),
      _repo.watchProfile().listen((p) {
        _activeId = p?.activeTripId;
        _profileSeen = true;
        _update();
      }),
    ];
  }

  final TripRepository _repo;
  late final List<StreamSubscription<Object?>> _subs;
  List<Trip>? _t;
  List<Member>? _m;
  List<Expense>? _e;
  List<ExpenseShare>? _s;
  List<Settlement>? _st;
  String? _activeId;
  bool _profileSeen = false;

  void _update({
    List<Trip>? trips,
    List<Member>? members,
    List<Expense>? expenses,
    List<ExpenseShare>? shares,
    List<Settlement>? settlements,
  }) {
    _t = trips ?? _t;
    _m = members ?? _m;
    _e = expenses ?? _e;
    _s = shares ?? _s;
    _st = settlements ?? _st;
    if (_t == null || _m == null || _e == null || _s == null || _st == null || !_profileSeen || isClosed) return;
    final list = [
      for (final trip in _t!) _summary(trip),
    ];
    emit(TripsState(loading: false, trips: list, activeId: _activeId));
  }

  TripSummary _summary(Trip trip) {
    final members = _m!.where((m) => m.tripId == trip.id).toList();
    final expenses = _e!.where((e) => e.tripId == trip.id).toList();
    final shares = _s!.where((s) => s.tripId == trip.id);
    final settled = _st!.where((s) => s.tripId == trip.id);
    final me = members.where((m) => m.isMe).firstOrNull;
    final b = SettlementCalculator.balances(
      memberIds: members.map((m) => m.id),
      payments: expenses.map((e) => PaymentEntry(e.paidBy, e.amount)),
      shares: shares.map((s) => ShareEntry(s.memberId, s.share)),
      settlements: settled.map((s) => SettledEntry(s.fromMember, s.toMember, s.amount)),
    );
    return TripSummary(
      trip: trip,
      members: members,
      total: expenses.fold(0, (a, e) => a + e.amount),
      myBalance: me == null ? 0 : (b[me.id] ?? 0),
    );
  }

  Future<String> createSample() => _repo.createSampleTrip();

  Future<void> setActive(String? tripId) => _repo.setActiveTrip(tripId);

  @override
  Future<void> close() async {
    for (final s in _subs) {
      await s.cancel();
    }
    return super.close();
  }
}
