import '../../core/categories.dart';

/// Place types reuse expense categories so a check-in's expense gets the
/// right category automatically.
const placeTypes = [
  (ExpenseCategory.stay, 'Hotel'),
  (ExpenseCategory.food, 'Food'),
  (ExpenseCategory.fuel, 'Fuel'),
  (ExpenseCategory.tickets, 'Sightseeing'),
  (ExpenseCategory.shopping, 'Shopping'),
  (ExpenseCategory.other, 'Other'),
];
