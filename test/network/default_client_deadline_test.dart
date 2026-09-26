// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:chess_srs/src/network/http.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A request must not be able to hang forever.
///
/// This client is what the fork's large downloads go through — the opening database, the NNUE
/// weights, the Maia book — where upstream's traffic is mostly short cloud calls. A server that
/// accepts the connection and then says nothing used to leave the request pending indefinitely:
/// no error, no timeout, and an app that simply waits. [LichessClient] has always had a deadline
/// here; this pins that its sibling does too.
void main() {
  group('DefaultClient deadline', () {
    test('gives up on a request the server never answers', () async {
      // A server that took the connection and then went quiet: the handler never completes.
      final neverAnswers = Completer<http.Response>();
      final client = DefaultClient(
        MockClient((_) => neverAnswers.future),
        userAgent: 'test',
        timeout: const Duration(milliseconds: 50),
      );

      await expectLater(
        client.get(Uri.parse('https://lichess.dev/api/thing')),
        throwsA(isA<TimeoutException>()),
        reason: 'a request with no reply must not stay pending forever',
      );
    });

    test('passes a request through when the server answers', () async {
      final client = DefaultClient(
        MockClient((_) async => http.Response('ok', 200)),
        userAgent: 'test',
        timeout: const Duration(seconds: 5),
      );

      final response = await client.get(Uri.parse('https://lichess.dev/api/thing'));

      expect(response.statusCode, 200);
    });

    test('defaults to the same deadline LichessClient uses', () {
      expect(
        DefaultClient.defaultRequestTimeout,
        LichessClient.defaultRequestTimeout,
        reason: 'one deadline for the app, not two that drift apart',
      );
    });
  });
}
