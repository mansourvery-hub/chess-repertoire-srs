import 'dart:convert';

import 'package:chess_srs/l10n/l10n.dart';
import 'package:chess_srs/src/app.dart';
import 'package:chess_srs/src/model/auth/auth_controller.dart';
import 'package:chess_srs/src/model/settings/general_preferences.dart';
import 'package:chess_srs/src/model/settings/preferences_storage.dart';
import 'package:chess_srs/src/network/http.dart';
import 'package:chess_srs/src/view/review/review_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

import 'model/auth/fake_auth_storage.dart';
import 'network/fake_http_client_factory.dart';
import 'test_helpers.dart';
import 'test_provider_scope.dart';

void main() {
  testWidgets('App loads', (tester) async {
    final app = await makeTestProviderScope(tester, child: const Application());

    await tester.pumpWidget(app);

    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(ReviewScreen), findsOneWidget);
  }, variant: kPlatformVariant);

  testWidgets('App loads with system theme, which defaults to light', (tester) async {
    final app = await makeTestProviderScope(tester, child: const Application());

    await tester.pumpWidget(app);

    expect(Theme.of(tester.element(find.byType(MaterialApp))).brightness, Brightness.light);
  }, variant: kPlatformVariant);

  // Skipped on 2026-09-26 because it failed on every CI run while passing on a developer
  // machine, and un-skipped once the cause turned out to be neither this test nor the app.
  //
  // QuickActionService.start() calls the quick_actions plugin on Android and iOS, and this test
  // runs under kPlatformVariant — so it is Android and iOS. With no handler on the plugin's
  // channel the call threw MissingPluginException from inside the app's startup, which aborted
  // the boot before the token check was ever made. That is why the earlier diagnostic saw no
  // request through the mock at all: the request had not been skipped, the app had stopped
  // starting. Whether the throw landed inside this test's window or after it was down to
  // timing, which is what made it read as a machine-speed problem.
  //
  // The channel is now mocked in the shared test binding, so the fix is not in this file. The
  // wait below is unchanged from the version that passed locally, deliberately: one variable at
  // a time, so the run that re-enables this says something.
  testWidgets('App will delete a stored authUser on startup if one request return 401', (
    tester,
  ) async {
    int tokenTestRequests = 0;
    final mockClient = MockClient((request) {
      if (request.url.path == '/api/token/test') {
        tokenTestRequests++;
        return mockResponse('''
{
  "${fakeAuthUser.token}": null
}
        ''', 200);
      } else if (request.url.path == '/api/account') {
        return mockResponse('{"error": "Unauthorized"}', 401);
      }
      return mockResponse('', 404);
    });

    final app = await makeTestProviderScope(
      tester,
      child: const Application(),
      authUser: fakeAuthUser,
      overrides: {
        httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
          (ref) => FakeHttpClientFactory(() => mockClient),
        ),
      },
    );

    await tester.pumpWidget(app);

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(ReviewScreen), findsOneWidget);

    // Both the startup token check and the 401 handling that follows are fire-and-forget
    // requests rather than anything tied to a frame, so pumpAndSettle has no relationship to
    // them: it returns once animations stop scheduling frames, and its duration is the gap
    // between pumps rather than a total wait. That made this test depend on machine speed —
    // it passed on a fast one and failed on a slower runner with the request never sent.
    // Wait for the condition itself, bounded so a real regression still fails rather than
    // hanging. The loops exit as soon as the condition holds, so the common case is one pass.
    for (var i = 0; i < 100 && tokenTestRequests == 0; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // should have made a request to test the token
    expect(tokenTestRequests, 1);

    final container = ProviderScope.containerOf(tester.element(find.byType(Application)));

    // The stale login is cleared once the 401 has been handled, which lands after the token
    // check above.
    if (container.read(authControllerProvider) != null) {
      for (var i = 0; i < 100 && container.read(authControllerProvider) != null; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    // authUser is not active anymore
    expect(container.read(authControllerProvider), isNull);
  }, variant: kPlatformVariant);

  testWidgets(
    'Root screen has no bottom navigation and mounts ReviewScreen',
    variant: kPlatformVariant,
    (tester) async {
      final app = await makeTestProviderScope(tester, child: const Application());

      await tester.pumpWidget(app);

      expect(find.byType(ReviewScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(BottomNavigationBar), findsNothing);
    },
  );

  testWidgets('language support', (tester) async {
    for (final locale in AppLocalizations.supportedLocales) {
      final app = await makeTestProviderScope(
        tester,
        child: const Application(),
        defaultPreferences: {
          PrefCategory.general.storageKey: jsonEncode(
            GeneralPrefs.defaults.copyWith(locale: locale).toJson(),
          ),
        },
        key: ValueKey('locale_$locale'),
      );

      await tester.pumpWidget(app);

      expect(find.byType(MaterialApp), findsOneWidget, reason: 'app loads with locale: $locale');

      // TODO find the reason why home does not load with eo
      // expect(find.byType(HomeTabScreen), findsOneWidget, reason: 'Home loads with locale: $locale');
    }
  }, variant: kPlatformVariant);
}
