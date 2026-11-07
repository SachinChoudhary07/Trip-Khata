import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../db/app_database.dart';
import '../../settle/domain/settlement_calculator.dart';
import '../data/trip_repository.dart';

class TripDetailState extends Equatable {
  const TripDetailState({
    this.loading = true,
    this.trip,
    this.members = const [],
    this.expenses = const [],
    this.sharesByExpense = const {},
    this.settlements = const [],
    this.balances = const {},
    this.transfers = const [],
  });

  final bool loading;
  final Trip? trip;
  final List<Member> members;
  final List<Expense> expenses;
  final Map<String, List<ExpenseShare>> sharesByExpense;
  final List<Settlement> settlements;

  /// memberId -> paise (positive = gets back).
  final Map<String, int> balances;

  /// Fewest payments to clear everything, minus what is already settled.
  final List<Transfer> transfers;

  Member? get me => members.where((m) => m.isMe).firstOrNull;
  int get total => expenses.fold(0, (a, e) => a + e.amount);
  int get perPerson => members.isEmpty ? 0 : total ~/ members.length;
  int get myBalance => me == null ? 0 : (balances[me!.id] ?? 0);
  Member? member(String id) => members.where((m) => m.id == id).firstOrNull;

  bool isMine(Expense e) =>
      me != null && (sharesByExpense[e.id]?.any((s) => s.memberId == me!.id) ?? false);

  int myShare(Expense e) =>
      sharesByExpense[e.id]?.where((s) => s.memberId == me?.id).fold<int>(0, (a, s) => a + s.share) ?? 0;

  @override
  List<Object?> get props => [loading, trip, members, expenses, sharesByExpense, settlements, balances, transfers];
}

class TripDetailCubit extends Cubit<TripDetailState> {
  TripDetailCubit(this._repo, this.tripId) : super(const TripDetailState()) {
    _subs = [
      _repo.watchTrip(tripId).listen((v) => _trip = v),
      _repo.watchMembers(tripId).listen((v) => _members = v),
      _repo.watchExpenses(tripId).listen((v) => _expenses = v),
      _repo.watchShares(tripId).listen((v) => _shares = v),
      _repo.watchSettlements(tripId).listen((v) => _settlements = v),
    ];
  }

  final TripRepository _repo;
  final String tripId;
  late final List<StreamSubscription<Object?>> _subs;

  Trip? _t;
  List<Member>? _m;
  List<Expense>? _e;
  List<ExpenseShare>? _s;
  List<Settlement>? _st;
  bool _tripLoaded = false;

  set _trip(Trip? v) {
    _t = v;
    _tripLoaded = true;
    _emit();
  }

  set _members(List<Member> v) {
    _m = v;
    _emit();
  }

  set _expenses(List<Expense> v) {
    _e = v;
    _emit();
  }

  set _shares(List<ExpenseShare> v) {
    _s = v;
    _emit();
  }

  set _settlements(List<Settlement> v) {
    _st = v;
    _emit();
  }

  void _emit() {
    if (!_tripLoaded || _m == null || _e == null || _s == null || _st == null || isClosed) return;
    final byExpense = <String, List<ExpenseShare>>{};
    for (final s in _s!) {
      (byExpense[s.expenseId] ??= []).add(s);
    }
    final balances = SettlementCalculator.balances(
      memberIds: _m!.map((m) => m.id),
      payments: _e!.map((e) => PaymentEntry(e.paidBy, e.amount)),
      shares: _s!.map((s) => ShareEntry(s.memberId, s.share)),
      settlements: _st!.map((s) => SettledEntry(s.fromMember, s.toMember, s.amount)),
    );
    emit(TripDetailState(
      loading: false,
      trip: _t,
      members: _m!,
      expenses: _e!,
      sharesByExpense: byExpense,
      settlements: _st!,
      balances: balances,
      transfers: SettlementCalculator.simplify(balances),
    ));
  }

  Future<void> markPaid(Transfer t) => _repo.addSettlement(
        tripId: tripId,
        fromMember: t.fromId,
        toMember: t.toId,
        amount: t.amount,
      );

  @override
  Future<void> close() async {
    for (final s in _subs) {
      await s.cancel();
    }
    return super.close();
  }
}
