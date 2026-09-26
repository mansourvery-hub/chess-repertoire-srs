// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/persistence/persistence.dart';

/// A [SqliteStudyRepository] that can be made to stall on one study's decisions.
///
/// Loading a review scope reads a chapter's decisions part-way through, so a caller can hold a
/// session start open there and start a second one behind it. That turns "the database happened
/// to answer out of order" into something a test can arrange on purpose, which is the only way
/// to pin down which of two competing session starts is meant to win.
class GatedStudyRepository extends SqliteStudyRepository {
  GatedStudyRepository(super.db);

  /// The study whose [getDecisionsByStudy] stalls.
  String? gatedStudyId;

  /// Released to let the stalled call proceed.
  Completer<void>? gate;

  /// Completed once the stalled call has actually reached the gate, so a test can wait for the
  /// stall to happen rather than guessing at a delay that may or may not be long enough.
  Completer<void>? reachedGate;

  @override
  Future<List<RepertoireDecision>> getDecisionsByStudy(String studyId) async {
    if (studyId == gatedStudyId) {
      final reached = reachedGate;
      if (reached != null && !reached.isCompleted) {
        reached.complete();
      }
      await gate?.future;
    }
    return await super.getDecisionsByStudy(studyId);
  }
}
