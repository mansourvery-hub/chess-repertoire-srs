// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The PGN type has to be spelled the same way in all three places it appears.
///
/// The app exports a type, iOS only offers the Share Extension for a type its activation rule
/// names, and the extension then reads the attachment by identifier. A rename that reaches the
/// first and not the others leaves an extension that is never offered for the app's own files,
/// which is exactly what happened when the type was renamed away from the upstream identifier.
void main() {
  group('iOS PGN share extension', () {
    late final String appPlist;
    late final String extensionPlist;
    late final String controllerSource;

    setUpAll(() {
      appPlist = File('ios/Runner/Info.plist').readAsStringSync();
      extensionPlist = File('ios/ShareExtension/Info.plist').readAsStringSync();
      controllerSource = File('ios/ShareExtension/ShareViewController.swift').readAsStringSync();
    });

    /// The identifier the app declares as the type it exports, e.g. `org.chesssrs.pgn`.
    String exportedType() {
      final match = RegExp(
        'UTTypeIdentifier</key>\\s*<string>([^<]+)</string>',
      ).firstMatch(appPlist);
      expect(match, isNotNull, reason: 'the app declares no exported PGN type');
      return match!.group(1)!;
    }

    /// Every type the extension's activation rule will accept.
    Set<String> activationRuleTypes() => RegExp(
      'UTI-CONFORMS-TO "([^"]+)"',
    ).allMatches(extensionPlist).map((m) => m.group(1)!).toSet();

    test('the app exports a PGN type', () {
      expect(exportedType(), isNotEmpty);
    });

    test('the extension is activated for the type the app exports', () {
      expect(
        activationRuleTypes(),
        contains(exportedType()),
        reason:
            'iOS decides whether to offer the extension from this rule alone, so a type that is '
            'not named here can never reach the extension however it is shared',
      );
    });

    test('the extension reads the attachment by the type the app exports', () {
      final match = RegExp(r'pgnTypeIdentifier\s*=\s*"([^"]+)"').firstMatch(controllerSource);
      expect(match, isNotNull, reason: 'the extension declares no PGN type identifier');
      expect(
        match!.group(1),
        equals(exportedType()),
        reason: 'the extension would look for a type no shared file carries',
      );
    });

    test('the app opens files of the type it exports', () {
      final documentTypes = RegExp(
        r'LSItemContentTypes</key>\s*<array>\s*<string>([^<]+)</string>',
      ).firstMatch(appPlist);
      expect(documentTypes, isNotNull, reason: 'the app registers no document type');
      expect(
        documentTypes!.group(1),
        equals(exportedType()),
        reason: 'the app would not open its own exported files',
      );
    });
  });
}
