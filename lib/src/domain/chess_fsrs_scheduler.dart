// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:chess_srs/src/domain/review_result.dart';
import 'package:chess_srs/src/domain/review_state.dart';
import 'package:chess_srs/src/domain/scheduler.dart';

/// Rating outcome for binary FSRS recall in chess (Decision D015).
///
/// In chess, thinking time reflects candidate move verification and calculation,
/// not weak memory. Therefore, ratings collapse strictly to binary Pass/Fail:
/// - [again]: incorrect move, hint used, or corrected false-start attempt.
/// - [good]: first committed move was correct (regardless of calculation time).
enum FsrsRating { again, good }

int _g(FsrsRating r) => r == FsrsRating.again ? 1 : 3;

/// Parameters for the domain-adapted ChessFSRS binary DSR model.
class ChessFsrsParams {
  const ChessFsrsParams({
    this.w0 = 0.35,
    this.w2 = 2.20,
    this.w4 = 4.93,
    this.w5 = 0.94,
    this.w6 = 1.05,
    this.w7 = 0.01,
    this.w8 = 1.49,
    this.w9 = 0.14,
    this.w10 = 0.94,
    this.w11 = 2.18,
    this.w12 = 0.09,
    this.w13 = 0.34,
    this.w14 = 1.26,
    this.sameDayThresholdDays = 1 / 24, // 1 hour
    this.sameDayGainFactor = 1.02,
    this.sameDayLapseFactor = 0.85,
    this.minStabilityDays = 0.02, // ~30 minutes floor
    this.maxStabilityDays = 365 * 5, // 5 years cap
  });

  const ChessFsrsParams.chessDefaults() : this();

  // Initial stability per rating (days)
  final double w0; // S0(Again)
  final double w2; // S0(Good)

  // Difficulty formulas
  final double w4; // D0 base
  final double w5; // D0 slope
  final double w6; // D responsiveness
  final double w7; // D mean reversion

  // Stability success formula
  final double w8;
  final double w9;
  final double w10;

  // Stability lapse formula
  final double w11;
  final double w12;
  final double w13;
  final double w14;

  // Guard parameters for rapid re-reviews
  final double sameDayThresholdDays;
  final double sameDayGainFactor;
  final double sameDayLapseFactor;

  final double minStabilityDays;
  final double maxStabilityDays;
}

const double kFsrsDecay = -0.5;
final double kFsrsFactor = math.pow(0.9, 1 / kFsrsDecay).toDouble() - 1; // 19 / 81 ≈ 0.2345679

/// Calculates retrievability probability R(t, S) given elapsed time and stability in days.
double fsrsRetrievability(double elapsedDays, double stabilityDays) {
  if (stabilityDays.isNaN || stabilityDays <= 0) return 0.0;
  final t = elapsedDays.isNaN || elapsedDays < 0 ? 0.0 : elapsedDays;
  final val = math.pow(1 + kFsrsFactor * t / stabilityDays, kFsrsDecay).toDouble();
  return (val.isFinite && !val.isNaN) ? val.clamp(0.0, 1.0) : 0.0;
}

/// Solves for the optimal review interval in days to hit [targetRetention].
double fsrsIntervalForTarget(double stabilityDays, double targetRetention) {
  if (stabilityDays.isNaN || stabilityDays <= 0) return 0.0;
  final r = (targetRetention.isNaN ? 0.88 : targetRetention).clamp(0.70, 0.99);
  final raw = stabilityDays / kFsrsFactor * (math.pow(r, 1 / kFsrsDecay) - 1);
  return (raw.isFinite && !raw.isNaN && raw > 0) ? raw : 0.0;
}

/// Calculates initial difficulty D0 for a newly introduced move.
double fsrsInitialDifficulty(FsrsRating rating, ChessFsrsParams p) {
  final g = _g(rating);
  final d = p.w4 - (g - 3) * p.w5;
  return (d.isNaN ? p.w4 : d).clamp(1.0, 10.0);
}

/// Calculates next difficulty D' upon recall outcome.
double fsrsNextDifficulty(double d, FsrsRating rating, ChessFsrsParams p) {
  final safeD = (d.isNaN || d <= 0) ? p.w4 : d.clamp(1.0, 10.0);
  final g = _g(rating);
  final delta = safeD - p.w6 * (g - 3);
  final reverted = p.w7 * p.w4 + (1 - p.w7) * delta;
  return (reverted.isNaN ? p.w4 : reverted).clamp(1.0, 10.0);
}

/// Initial stability in days for cold-start.
double fsrsInitialStability(FsrsRating rating, ChessFsrsParams p) =>
    rating == FsrsRating.again ? p.w0 : p.w2;

/// Calculates new stability after successful recall (Rating.good).
double fsrsNextStabilitySuccess(double d, double s, double r, ChessFsrsParams p) {
  final safeS = (s.isNaN || s <= 0) ? p.minStabilityDays : s;
  final safeD = (d.isNaN ? p.w4 : d).clamp(1.0, 10.0);
  final safeR = (r.isNaN ? 0.0 : r).clamp(0.0, 1.0);
  final factor =
      math.exp(p.w8) * (11 - safeD) * math.pow(safeS, -p.w9) * (math.exp((1 - safeR) * p.w10) - 1);
  final res = safeS * (1 + factor);
  return (res.isFinite && !res.isNaN && res > 0) ? res : safeS;
}

/// Calculates regressed stability after a lapse (Rating.again).
double fsrsNextStabilityLapse(double d, double s, double r, ChessFsrsParams p) {
  final safeS = (s.isNaN || s <= 0) ? p.minStabilityDays : s;
  final safeD = (d.isNaN ? p.w4 : d).clamp(1.0, 10.0);
  final safeR = (r.isNaN ? 0.0 : r).clamp(0.0, 1.0);
  final raw =
      p.w11 *
      math.pow(safeD, -p.w12) *
      (math.pow(safeS + 1, p.w13) - 1) *
      math.exp((1 - safeR) * p.w14);
  return (raw.isFinite && !raw.isNaN && raw > 0) ? raw : p.minStabilityDays;
}

/// Domain-adapted FSRS-5 spaced repetition scheduler for chess repertoires.
///
/// Implements continuous Difficulty-Stability-Retrievability (DSR) power-law forgetting curves
/// with binary grading (Decision D015) and explicit target retention solving ($R_{\text{target}}$).
class ChessFsrsScheduler implements Scheduler {
  const ChessFsrsScheduler({
    this.params = const ChessFsrsParams.chessDefaults(),
    this.targetRetention = 0.88,
    this.maxIntervalDays = 365 * 3, // 3 years
    this.minIntervalDays = 1 / 1440, // 1 minute
  });

  final ChessFsrsParams params;

  /// Target recall probability (default 88%; 95% in Tournament Mode).
  final double targetRetention;

  final double maxIntervalDays;
  final double minIntervalDays;

  static const int _dayMs = 86400000;

  @override
  bool isDue(ReviewState state, DateTime now) => state.isDueAt(now);

  @override
  ReviewState schedule({
    required ReviewState previous,
    required ReviewResult result,
    required DateTime now,
    bool hintUsed = false,
    bool multipleAttempts = false,
  }) {
    // Binary rating inference (Decision D015)
    final rating = (result == ReviewResult.incorrect || hintUsed || multipleAttempts)
        ? FsrsRating.again
        : FsrsRating.good;

    final anchor = previous.lastReviewedAt ?? previous.firstReviewedAt;
    double elapsedDays = 0.0;
    if (anchor != null) {
      final diffMs = now.difference(anchor).inMilliseconds;
      elapsedDays = diffMs <= 0 ? 0.0 : diffMs / _dayMs;
    }

    final bool isColdStart = previous.repetitionCount == 0 && previous.stability <= 0;

    double newDifficulty;
    double newStabilityDays;

    if (isColdStart) {
      newDifficulty = fsrsInitialDifficulty(rating, params);
      newStabilityDays = fsrsInitialStability(rating, params);
    } else {
      final prevStabilityDays = (previous.stability.isNaN || previous.stability <= 0)
          ? params.minStabilityDays
          : previous.stability / _dayMs;
      final prevDifficulty = (previous.difficulty.isNaN || previous.difficulty <= 0)
          ? fsrsInitialDifficulty(FsrsRating.good, params)
          : previous.difficulty.clamp(1.0, 10.0);

      final r = fsrsRetrievability(elapsedDays, prevStabilityDays);
      newDifficulty = fsrsNextDifficulty(prevDifficulty, rating, params);

      if (elapsedDays < params.sameDayThresholdDays) {
        newStabilityDays = rating == FsrsRating.again
            ? prevStabilityDays * params.sameDayLapseFactor
            : prevStabilityDays * params.sameDayGainFactor;
      } else if (rating == FsrsRating.again) {
        newStabilityDays = fsrsNextStabilityLapse(newDifficulty, prevStabilityDays, r, params);
      } else {
        newStabilityDays = fsrsNextStabilitySuccess(newDifficulty, prevStabilityDays, r, params);
      }
    }

    newStabilityDays = (newStabilityDays.isNaN || !newStabilityDays.isFinite)
        ? params.minStabilityDays
        : newStabilityDays.clamp(params.minStabilityDays, params.maxStabilityDays);

    final effectiveRetention = (targetRetention.isNaN || !targetRetention.isFinite)
        ? 0.88
        : targetRetention.clamp(0.70, 0.99);
    final rawInterval = fsrsIntervalForTarget(newStabilityDays, effectiveRetention);
    final intervalDays = (rawInterval.isNaN || !rawInterval.isFinite)
        ? minIntervalDays
        : rawInterval.clamp(minIntervalDays, maxIntervalDays);

    final nextDue = now.add(Duration(milliseconds: (intervalDays * _dayMs).round()));

    return previous.copyWith(
      firstReviewedAt: previous.firstReviewedAt ?? now,
      lastReviewedAt: now,
      nextDueAt: nextDue,
      repetitionCount: rating == FsrsRating.again
          ? previous.repetitionCount
          : previous.repetitionCount + 1,
      lapseCount: rating == FsrsRating.again ? previous.lapseCount + 1 : previous.lapseCount,
      stability: newStabilityDays * _dayMs,
      difficulty: newDifficulty,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChessFsrsScheduler &&
          targetRetention == other.targetRetention &&
          maxIntervalDays == other.maxIntervalDays &&
          minIntervalDays == other.minIntervalDays;

  @override
  int get hashCode => Object.hash(targetRetention, maxIntervalDays, minIntervalDays);
}

/// Generates a preview of the interval ladder (in days) for consecutive successful recalls
/// under [targetRetention].
List<double> fsrsIntervalProgressionPreview({
  required double targetRetention,
  int steps = 5,
  ChessFsrsParams params = const ChessFsrsParams.chessDefaults(),
}) {
  final intervals = <double>[];
  var d = fsrsInitialDifficulty(FsrsRating.good, params);
  var s = params.w2; // Initial stability for Rating.good in days
  final effectiveR = targetRetention.clamp(0.70, 0.99);

  for (var i = 0; i < steps; i++) {
    final intervalDays = fsrsIntervalForTarget(s, effectiveR);
    intervals.add(intervalDays);
    d = fsrsNextDifficulty(d, FsrsRating.good, params);
    s = fsrsNextStabilitySuccess(d, s, effectiveR, params);
  }
  return List.unmodifiable(intervals);
}
