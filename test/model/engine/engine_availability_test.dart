// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/model/engine/position_evaluator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isLocalEngineOffered', () {
    // The three inputs, named so the table below reads as a statement about the product
    // rather than a truth table.
    bool offer({bool allowed = true, bool enabled = true, bool supported = true}) =>
        isLocalEngineOffered(allowed: allowed, enabled: enabled, supported: supported);

    test('is offered when permitted, switched on, and runnable', () {
      expect(offer(), isTrue);
    });

    test('is not offered when the platform cannot run a native engine', () {
      // Android, iOS and web aside, the engine resolves to null and no evaluation can ever
      // arrive. Offering the gauge here is offering a control that cannot answer.
      expect(
        offer(supported: false),
        isFalse,
        reason: 'desktop has no native engine, so nothing would ever be evaluated',
      );
    });

    test('is not offered when the feature is not permitted', () {
      expect(offer(allowed: false), isFalse);
    });

    test('is not offered when the user has switched it off', () {
      expect(offer(enabled: false), isFalse);
    });

    test('a platform that cannot run one is never rescued by the other two', () {
      for (final allowed in [true, false]) {
        for (final enabled in [true, false]) {
          expect(
            isLocalEngineOffered(allowed: allowed, enabled: enabled, supported: false),
            isFalse,
            reason: 'allowed=$allowed enabled=$enabled must not matter without a working engine',
          );
        }
      }
    });
  });

  group('isNativeEngineSupported', () {
    test('is true in the test environment, which is why the rule is exercised separately', () {
      // The real check reads Platform, and FLUTTER_TEST is set here — so this branch is the
      // only one a test suite can reach. The rule above is what gets tested for the platforms
      // that cannot run an engine; this assertion documents why that indirection is needed.
      expect(isNativeEngineSupported, isTrue);
    });
  });
}
