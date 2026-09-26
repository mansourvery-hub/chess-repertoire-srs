import 'dart:convert';

import 'package:chess_srs/l10n/l10n.dart';
import 'package:chess_srs/src/app.dart';
import 'package:chess_srs/src/model/auth/auth_controller.dart';
import 'package:chess_srs/src/model/common/preloaded_data.dart';
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

  // STILL SKIPPED, but no longer a mystery. What is now known, from the runner's own logs:
  //
  // 1. The test used to fail on CI with `MissingPluginException(No implementation found for
  //    method getLaunchAction on channel plugins.flutter.io/quick_actions)`.
  //    QuickActionService.start() calls that plugin on Android and iOS, and this test runs under
  //    kPlatformVariant, so it is Android and iOS. The throw came from inside the app's startup
  //    and stopped the boot there. That channel is now mocked in the shared test binding, which
  //    is a real fix and may yet matter to other tests — but it was masking the rest.
  //
  // 2. With it mocked, the failure becomes the assertion this test was always making:
  //    `Expected: <1> Actual: <0>` — the token check request is never issued on the runner.
  //
  // 3. The override is *not* the problem, which the first diagnosis assumed. The test now records
  //    every request the mock serves, and on the runner it serves three — a connectivity probe, a
  //    logo, and an FCM registration — all through this test's own client. `/api/token/test`
  //    appears zero times in the entire run. On a developer machine the same mock serves it,
  //    along with `/api/account`.
  //
  // So the request is genuinely never sent there, while the stored token *is* read back (asserted
  // below, and it passes on the runner). The remaining difference is environmental and has not
  // been isolated. Two earlier attempts reasoned about the request and were wrong; this comment
  // records the evidence instead of another theory, because the next person should start from
  // the three requests the mock does serve, not from a guess about the fourth.
  //
  // Un-skipping this needs that difference found first. Everything else here is worth keeping
  // either way: the diagnostics cost nothing and turn the next failure into an answer.
  testWidgets(
    'App will delete a stored authUser on startup if one request return 401',
    (tester) async {
      int tokenTestRequests = 0;
      // Every request the mock is asked to serve, so that a failure can report what did reach it
      // rather than only what was expected. A developer machine and the runner can disagree about
      // *which* request goes missing, and a bare counter cannot show that.
      final seenRequests = <String>[];
      final mockClient = MockClient((request) {
        seenRequests.add('${request.method} ${request.url}');
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
      // them. Waiting by pumping advances *fake* time, while the work being waited for — a request
      // issued from a provider build that first awaits several platform channels — only advances on
      // the real event loop, so a pump loop is a bet on how much of that a machine got through.
      // That is the whole of the "passes here, fails on the runner" behaviour: with the missing
      // plugin mock fixed, the runner reports `Expected: <1> Actual: <0>` here, and only here.
      //
      // Waiting on the real loop keeps the same 5s bound, so a real regression still fails rather
      // than hanging, and both loops exit as soon as their condition holds.
      final container = ProviderScope.containerOf(tester.element(find.byType(Application)));

      await tester.runAsync(() async {
        for (var i = 0; i < 100 && tokenTestRequests == 0; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });

      // The request can only be made if the stored token was read back, so assert that first.
      // Otherwise a failure reports a bare zero and gives no clue which half broke — which is
      // exactly what the original diagnostic run could not establish.
      final preloaded = await container.read(preloadedDataProvider.future);
      expect(
        preloaded.authUser,
        isNotNull,
        reason: 'the seeded token was never read back, so no token check was attempted',
      );

      // should have made a request to test the token
      expect(
        tokenTestRequests,
        1,
        reason: 'the mock served ${seenRequests.length} request(s): $seenRequests',
      );

      // The stale login is cleared once the 401 has been handled, which lands after the token
      // check above.
      await tester.runAsync(() async {
        for (var i = 0; i < 100 && container.read(authControllerProvider) != null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });

      // authUser is not active anymore
      expect(container.read(authControllerProvider), isNull);
    },
    variant: kPlatformVariant,
    skip: true,
  );

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
