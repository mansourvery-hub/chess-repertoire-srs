// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:chess_srs/src/design/theme_bridge.dart';
import 'package:chess_srs/src/design/tokens.dart';
import 'package:chess_srs/src/model/settings/general_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../binding.dart';

/// The accent has to outlive the process, or the settings screen is offering a choice the app
/// discards. The only honest way to test that is to throw the container away and read the value
/// back from storage the way a relaunch would, so that is what these do rather than asserting
/// on the notifier that just wrote it.
void main() {
  setUpAll(TestLichessBinding.ensureInitialized);

  setUp(() async {
    await TestLichessBinding.instance.sharedPreferences.clear();
  });

  /// Reads the accent as a freshly launched app would: a new container over the same storage.
  SrsAccent accentAfterRestart() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container.read(srsAccentProvider);
  }

  group('Srs accent persistence', () {
    test('a chosen accent is still chosen after a restart', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(srsAccentProvider.notifier).accent = SrsAccent.verdigris;
      await pumpEventQueue();

      expect(accentAfterRestart(), SrsAccent.verdigris);
    });

    test('the accent is stored with the rest of the general preferences', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(srsAccentProvider.notifier).accent = SrsAccent.ochre;
      await pumpEventQueue();

      // Not in a key of its own: the design contract asks for the accent to be persisted the way
      // other preferences are, so it belongs in the same stored document.
      final stored = TestLichessBinding.instance.sharedPreferences.getString('preferences.general');
      expect(stored, isNotNull);
      final json = jsonDecode(stored!) as Map<String, dynamic>;
      expect(json['accent'], 'ochre');
      expect(GeneralPrefs.fromJson(json).accent, SrsAccent.ochre);
    });

    test('defaults to the default accent, not to whatever was last chosen', () {
      expect(accentAfterRestart(), kSrsDefaultAccent);
    });

    test('preferences stored before accents existed still decode', () {
      // Every preference document written by an earlier build has no 'accent' key. Decoding must
      // not fail, because the failure would cost the user every other setting they have, not just
      // the accent.
      final legacy =
          jsonDecode(jsonEncode(GeneralPrefs.defaults.copyWith(accent: SrsAccent.ochre).toJson()))
              as Map<String, dynamic>;
      legacy.remove('accent');

      final decoded = GeneralPrefs.fromJson(legacy);
      expect(decoded.accent, kSrsDefaultAccent);
      // The rest of the document survives, which is the part that matters.
      expect(decoded.masterVolume, GeneralPrefs.defaults.masterVolume);
      expect(decoded.isSoundEnabled, GeneralPrefs.defaults.isSoundEnabled);
    });

    test('an accent this build does not recognise falls back instead of failing the decode', () {
      final json = jsonDecode(jsonEncode(GeneralPrefs.defaults.toJson())) as Map<String, dynamic>;
      json['accent'] = 'chartreuse';

      final decoded = GeneralPrefs.fromJson(json);
      expect(decoded.accent, kSrsDefaultAccent);
    });
  });
}
