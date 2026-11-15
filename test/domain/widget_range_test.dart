import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/domain/widget_range.dart';

void main() {
  test('range estimate scales each battery at 45 km per full charge', () {
    expect(estimatedWidgetRangeKm(100, null), 45);
    expect(estimatedWidgetRangeKm(50, 50), 45);
    expect(estimatedWidgetRangeKm(100, 100), 90);
  });

  test('missing and invalid battery readings are not fabricated as range', () {
    expect(estimatedWidgetRangeKm(null, null), isNull);
    expect(estimatedWidgetRangeKm(-1, null), isNull);
    expect(estimatedWidgetRangeKm(-1, 50), 23);
  });

  test('battery percentages are clamped to their valid range', () {
    expect(estimatedWidgetRangeKm(150, null), 45);
    expect(estimatedWidgetRangeKm(0, 0), 0);
  });
}
