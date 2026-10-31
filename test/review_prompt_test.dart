import 'package:flutter_test/flutter_test.dart';
import 'package:plus15_navigator/shared/services/review_prompt.dart';

void main() {
  final now = DateTime(2026, 11, 1);
  bool ask({int arrivals = 2, int asks = 0, DateTime? last}) =>
      shouldAskForReview(arrivals: arrivals, asks: asks, lastAsk: last, now: now);

  test('not until the second finished trip', () {
    expect(ask(arrivals: 1), isFalse);
    expect(ask(arrivals: 2), isTrue);
  });

  test('at most once every 90 days', () {
    expect(ask(asks: 1, last: now.subtract(const Duration(days: 89))), isFalse);
    expect(ask(asks: 1, last: now.subtract(const Duration(days: 90))), isTrue);
  });

  test('never more than three times', () {
    expect(ask(asks: 2, last: DateTime(2025)), isTrue);
    expect(ask(asks: 3, last: DateTime(2025)), isFalse);
  });
}
