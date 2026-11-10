import 'package:flutter_test/flutter_test.dart';
import 'package:tripkhata/features/trips/budget_alerts.dart';

void main() {
  test('budget levels: 80% and 100%, none without a budget', () {
    expect(BudgetAlerts.levelFor(79999, 100000), 0);
    expect(BudgetAlerts.levelFor(80000, 100000), 80);
    expect(BudgetAlerts.levelFor(99999, 100000), 80);
    expect(BudgetAlerts.levelFor(100000, 100000), 100);
    expect(BudgetAlerts.levelFor(250000, 100000), 100);
    expect(BudgetAlerts.levelFor(500000, null), 0);
    expect(BudgetAlerts.levelFor(500000, 0), 0);
  });
}
