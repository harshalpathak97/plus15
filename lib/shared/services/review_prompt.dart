import 'package:in_app_review/in_app_review.dart';
import '../../data/datasources/local_storage.dart';

/// Ask for a Play rating only after real use, and rarely.
bool shouldAskForReview({
  required int arrivals,
  required int asks,
  required DateTime? lastAsk,
  required DateTime now,
}) =>
    arrivals >= 2 &&
    asks < 3 &&
    (lastAsk == null || now.difference(lastAsk) >= const Duration(days: 90));

/// Counts a finished trip and, when [shouldAskForReview] says so, shows the
/// Play rating sheet a moment later. Play limits how often it appears and
/// never says whether it did, so only requests are counted.
Future<void> countArrivalAndMaybeAsk(LocalStorage storage, {DateTime? now}) async {
  final arrivals = storage.getArrivals() + 1;
  await storage.setArrivals(arrivals);
  final at = now ?? DateTime.now();
  final asks = storage.getReviewAsks();
  if (!shouldAskForReview(
      arrivals: arrivals, asks: asks, lastAsk: storage.getReviewAskedAt(), now: at)) {
    return;
  }
  final review = InAppReview.instance;
  if (!await review.isAvailable()) return;
  await Future<void>.delayed(const Duration(milliseconds: 1500));
  await storage.setReviewAsked(asks + 1, at);
  await review.requestReview();
}
