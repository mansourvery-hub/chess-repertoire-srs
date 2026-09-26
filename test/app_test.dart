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

  // Was quarantined on 2026-09-26 with skip: true, because it failed on every CI run while
  // passing on a developer machine. Not a product defect: nothing in the app changed, the test's
  // own waiting strategy was the problem.
  //
  // It waited by pumping frames in a loop, and pumping advances fake time while the work it was
  // waiting for — a fire-and-forget request issued from a provider build that first awaits several
  // platform channels — only advances on the real event loop. So the test asserted on however much
  // of that a machine happened to finish inside its fake-time budget. Waiting in runAsync instead
  // keeps the bound and drops the machine-speed dependence.
  //
  // The earlier diagnosis that the mock was not intercepting does not hold up: the request is
  // built from httpClientFactoryProvider directly, and the seeded token is asserted to have been
  // read before the request count is checked, so a failure now names which of the two broke
  // instead of just reporting a zero.
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

    final container = ProviderScope.containerOf(tester.element(find.byType(Application)));

    // The token check is fired from a provider build and deliberately not awaited, and that
    // provider's own build first waits on several platform channels (package info, device
    // info, total RAM, two directories). Pumping frames advances *fake* time, which does not
    // move real async work along, so a loop of pumps is really a bet on how much of that the
    // machine got through — which is how this test came to pass on a fast machine and fail on a
    // slower runner. Waiting on the real event loop is bounded the same way, so a genuine
    // regression still fails rather than hanging, but it no longer depends on machine speed.
    await tester.runAsync(() async {
      for (var i = 0; i < 100 && tokenTestRequests == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });

    // Assert the precondition separately, so a failure says which half broke. The request can
    // only be made if the stored token was actually read back; if it was not, the count below
    // would be zero and this assertion would have said why.
    final preloaded = await container.read(preloadedDataProvider.future);
    expect(
      preloaded.authUser,
      isNotNull,
      reason: 'the seeded token was not read back, so no token check was ever attempted',
    );

    // should have made a request to test the token
    expect(tokenTestRequests, 1);

    // The stale login is cleared once the 401 has been handled, which lands after the token
    // check above.
    await tester.runAsync(() async {
      for (var i = 0; i < 100 && container.read(authControllerProvider) != null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });

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
