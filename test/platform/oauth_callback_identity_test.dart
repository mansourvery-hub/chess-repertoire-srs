// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:chess_srs/src/constants.dart';
import 'package:chess_srs/src/model/auth/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// The OAuth callback has to be spelled the same way in all three places it appears.
///
/// The Dart side builds the redirect URI it hands the browser, Android only routes that callback
/// back into the app for the scheme its intent filter names, and iOS only claims the URL scheme
/// its Info.plist lists. When the three disagree the browser hands the callback to a scheme the
/// installed app does not answer to: the sign-in looks like it hangs, never completes, and
/// reports no error to show for it.
///
/// The Dart value is derived from a constant and is asserted in auth_repository_test.dart. What
/// nothing checked was the native side keeping up — a rename applied to constants.dart alone
/// leaves both platforms still registered under the old scheme, which is the whole failure.
void main() {
  group('OAuth callback identity', () {
    late final String androidManifest;
    late final String iosPlist;
    late final Uri redirect;

    setUpAll(() {
      androidManifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      iosPlist = File('ios/Runner/Info.plist').readAsStringSync();
      redirect = Uri.parse(kOAuthRedirectUri);
    });

    /// Every `scheme://host` the OAuth callback receiver is willing to be routed back for.
    Set<String> androidCallbackTargets() => RegExp(
      r'android:scheme="([^"]+)"\s+android:host="([^"]+)"',
    ).allMatches(androidManifest).map((m) => '${m.group(1)}://${m.group(2)}').toSet();

    /// Every scheme iOS will hand to the app.
    Set<String> iosRegisteredSchemes() {
      final array = RegExp(
        r'CFBundleURLSchemes</key>\s*<array>(.*?)</array>',
        dotAll: true,
      ).firstMatch(iosPlist);
      expect(array, isNotNull, reason: 'the app registers no URL scheme on iOS');
      return RegExp(
        '<string>([^<]+)</string>',
      ).allMatches(array!.group(1)!).map((m) => m.group(1)!).toSet();
    }

    test('the redirect the app asks for is the app-owned scheme', () {
      expect(
        redirect.scheme,
        equals(kLichessCustomUriSchemeName),
        reason: 'the redirect must be built from the one identity the app owns',
      );
      expect(redirect.host, isNotEmpty, reason: 'the redirect names no callback host');
    });

    test('Android routes the callback back for exactly that redirect', () {
      expect(
        androidCallbackTargets(),
        contains(kOAuthRedirectUri),
        reason:
            'the intent filter does not accept the URI the app sends the browser to, so Android '
            'has nowhere to deliver the callback and sign-in cannot complete',
      );
    });

    test('iOS registers the scheme that redirect uses', () {
      expect(
        iosRegisteredSchemes(),
        contains(redirect.scheme),
        reason:
            'iOS only hands an app a URL whose scheme it lists; a redirect on an unlisted scheme '
            'leaves the callback in the browser',
      );
    });
  });
}
