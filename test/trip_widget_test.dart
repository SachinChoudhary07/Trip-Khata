import 'package:flutter_test/flutter_test.dart';
import 'package:tripkhata/features/widget/trip_widget.dart';

void main() {
  test('widget tap URIs map to actions', () {
    expect(TripWidget.actionOf(Uri.parse('tripkhata://widget/voice')), 'voice');
    expect(TripWidget.actionOf(Uri.parse('tripkhata://widget/type')), 'type');
    expect(TripWidget.actionOf(Uri.parse('tripkhata://widget')), 'open');
    expect(TripWidget.actionOf(Uri.parse('https://example.com/voice')), isNull);
    expect(TripWidget.actionOf(null), isNull);
  });
}
