import 'package:chess_srs/src/design/design.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'srs_test_app.dart';

void main() {
  group('SrsSubHead', () {
    srsPhoneTestWidgets('names the destination on the back affordance', (tester) async {
      await pumpSrs(
        tester,
        SrsSubHead(backLabel: 'Library', onBack: () {}, trailing: const SizedBox.shrink()),
      );

      expect(find.text('Library'), findsOneWidget);
      expect(find.text('Back'), findsNothing);
    });

    srsPhoneTestWidgets('reports the tap', (tester) async {
      var backs = 0;
      await pumpSrs(
        tester,
        SrsSubHead(backLabel: 'Review', onBack: () => backs++, trailing: const SizedBox.shrink()),
      );

      await tester.tap(find.text('Review'));
      expect(backs, 1);
    });

    srsPhoneTestWidgets('carries an optional trailing action', (tester) async {
      var flips = 0;
      await pumpSrs(
        tester,
        SrsSubHead(
          backLabel: 'Library',
          onBack: () {},
          trailing: SrsTextButton(label: 'Flip board', onPressed: () => flips++),
        ),
      );

      expect(find.text('Flip board'), findsOneWidget);
      await tester.tap(find.text('Flip board'));
      expect(flips, 1);
      // The trailing action must not be a second back button.
      expect(find.text('Library'), findsOneWidget);
    });

    srsPhoneTestWidgets('back affordance clears the 44px touch target', (tester) async {
      await pumpSrs(
        tester,
        SrsSubHead(backLabel: 'Library', onBack: () {}, trailing: const SizedBox.shrink()),
      );

      expect(tester.getSize(find.byType(SrsPressable)).height, greaterThanOrEqualTo(44));
    });

    srsPhoneTestWidgets('announces its label exactly once', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpSrs(
        tester,
        SrsSubHead(backLabel: 'Library', onBack: () {}, trailing: const SizedBox.shrink()),
      );

      expect(tester.getSemantics(find.byType(SrsPressable)).label, 'Library');
      handle.dispose();
    });
  });
}
