import 'dart:convert';

import 'package:chess_srs/src/model/analysis/analysis_controller.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/eval.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/engine/evaluation_mixin.dart';
import 'package:chess_srs/src/network/http.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

import '../../network/fake_http_client_factory.dart';
import '../../test_provider_scope.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Unauthenticated HTTP Cloud Evaluation', () {
    testWidgets('fetches cloud eval via unauthenticated HTTP and updates tree node', (
      tester,
    ) async {
      final mockCloudResponse = jsonEncode({
        'depth': 35,
        'knodes': 2500,
        'pvs': [
          {'moves': 'e7e5 g1f3 b8c6', 'cp': 15},
        ],
      });

      http.Request? capturedRequest;
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/cloud-eval') {
          capturedRequest = request;
          return http.Response(mockCloudResponse, 200);
        }
        return http.Response('Not found', 404);
      });

      final app = await makeTestProviderScopeApp(
        tester,
        home: const SizedBox(key: Key('test-home')),
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(() => mockClient);
          }),
        },
      );
      await tester.pumpWidget(app);

      const options = AnalysisOptions.pgn(
        id: StringId('test-cloud-eval'),
        orientation: Side.white,
        pgn: '1. e4',
        variant: Variant.standard,
        isComputerAnalysisAllowed: true,
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('test-home'))),
      );

      // Keep autoDispose provider alive
      final sub = container.listen(analysisControllerProvider(options), (_, _) {});
      addTearDown(sub.close);

      // Read controller to trigger initial load
      final state = await container.read(analysisControllerProvider(options).future);
      expect(state, isNotNull);

      // Trigger requestEval
      final controller = container.read(analysisControllerProvider(options).notifier);
      controller.requestEval();

      // Pump debounce timer
      await tester.pump(kRequestEvalDebounceDelay + const Duration(milliseconds: 50));
      // Pump async HTTP microtasks
      await tester.pump(const Duration(milliseconds: 50));

      // Verify that unauthenticated HTTP request was dispatched to /api/cloud-eval
      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.url.path, '/api/cloud-eval');
      expect(capturedRequest!.headers.containsKey('Authorization'), isFalse);

      // Verify node eval was populated with CloudEval
      final updatedState = container.read(analysisControllerProvider(options)).requireValue;
      final eval = updatedState.currentNode.eval;
      expect(eval, isA<CloudEval>());
      expect((eval! as CloudEval).depth, 35);
      expect(eval.cp, 15);
      expect(eval.pvs.first.moves.first, 'e7e5');
    });

    testWidgets('fetches cloud eval beyond ply 15', (tester) async {
      // 16-ply game (8 full moves)
      const pgn16Ply =
          '1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6 5. O-O Be7 6. Re1 b5 7. Bb3 d6 8. c3 O-O';

      final mockCloudResponse = jsonEncode({
        'depth': 40,
        'knodes': 5000,
        'pvs': [
          {'moves': 'h2h3 c6a5', 'cp': 30},
        ],
      });

      var requestCount = 0;
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/cloud-eval') {
          requestCount++;
          return http.Response(mockCloudResponse, 200);
        }
        return http.Response('Not found', 404);
      });

      final app = await makeTestProviderScopeApp(
        tester,
        home: const SizedBox(key: Key('test-home-2')),
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(() => mockClient);
          }),
        },
      );
      await tester.pumpWidget(app);

      const options = AnalysisOptions.pgn(
        id: StringId('test-cloud-eval-ply16'),
        orientation: Side.white,
        pgn: pgn16Ply,
        variant: Variant.standard,
        isComputerAnalysisAllowed: true,
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('test-home-2'))),
      );
      final sub = container.listen(analysisControllerProvider(options), (_, _) {});
      addTearDown(sub.close);

      final state = await container.read(analysisControllerProvider(options).future);
      expect(state.currentPosition.ply, 16);

      final controller = container.read(analysisControllerProvider(options).notifier);
      controller.requestEval();

      await tester.pump(kRequestEvalDebounceDelay + const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      expect(requestCount, greaterThanOrEqualTo(1));
      final updatedState = container.read(analysisControllerProvider(options)).requireValue;
      final eval = updatedState.currentNode.eval;
      expect(eval, isA<CloudEval>());
      expect((eval! as CloudEval).depth, 40);
      expect(eval.cp, 30);
    });
  });
}
