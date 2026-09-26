// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The app must not claim to be the verified handler for links it cannot be verified as.
///
/// `autoVerify` on Android and an `applinks:` entry in the iOS associated-domains entitlement
/// are both assertions that an association file on lichess.org names this app. That file names
/// the official Lichess identity, so the claim cannot be satisfied: the links do not reach the
/// app either way, and what is left is an entitlement that misrepresents the app and is a review
/// risk.
///
/// The claim is therefore removed until the records are published. These tests exist so that
/// putting it back is a deliberate act with the records in hand, rather than something that
/// drifts back in during unrelated work. When the association files are deployed, delete these
/// tests and restore the attribute and the entitlement together — audit.md M20.
void main() {
  group('verified link claims', () {
    /// The file with its XML comments removed.
    ///
    /// These assertions are about what the platform is actually told, and the explanation for the
    /// removal necessarily names the very attribute being removed — so a comment that discusses
    /// `autoVerify` must not read as a claim of it.
    String withoutComments(String path) =>
        File(path).readAsStringSync().replaceAll(RegExp('<!--.*?-->', dotAll: true), '');

    test('Android does not auto-verify lichess.org links', () {
      final manifest = withoutComments('android/app/src/main/AndroidManifest.xml');

      // The filter itself must stay, so a link can still reach the app through the chooser.
      expect(
        manifest,
        contains('android:host="lichess.org"'),
        reason: 'the lichess.org filter is what lets a link reach the app at all',
      );
      expect(
        manifest,
        isNot(contains('autoVerify')),
        reason:
            'autoVerify asserts an association file naming org.chesssrs.app exists. Until one is '
            'published the assertion is false and links are not routed on the strength of it',
      );
    });

    test('iOS claims no associated domains', () {
      final entitlements = withoutComments('ios/Runner/Runner.entitlements');

      // A commented-out entry is the failure mode this guards: the key comes back, with its
      // explanation still attached, and nothing says the record was ever published.
      expect(
        entitlements,
        isNot(contains('applinks:')),
        reason:
            'an applinks entry asserts an apple-app-site-association naming org.chesssrs.app, '
            'which does not exist for this app',
      );
    });

    test('the removal is documented where it happened', () {
      // Whoever publishes the records needs to find this, and the comment has to say what to
      // restore and how — otherwise it reads as an unexplained deletion and gets reverted.
      for (final path in [
        'android/app/src/main/AndroidManifest.xml',
        'ios/Runner/Runner.entitlements',
      ]) {
        expect(
          File(path).readAsStringSync(),
          contains('M20'),
          reason: '$path should point at the audit finding that tracks restoring this',
        );
      }
    });
  });
}
