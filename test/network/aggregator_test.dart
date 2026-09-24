import 'package:chess_srs/src/model/game/exported_game.dart';
import 'package:chess_srs/src/model/user/user.dart';
import 'package:chess_srs/src/network/aggregator.dart';
import 'package:chess_srs/src/network/http.dart';
import 'package:fake_async/fake_async.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import '../test_container.dart';
import '../test_helpers.dart';
import 'fake_http_client_factory.dart';
import 'http_test.dart';

typedef _UnreadCount = ({int unread, bool lichess});

void main() {
  setUp(() {
    FakeClient.reset();
  });

  Future<Aggregator> fakeClientAggregator() async {
    final container = await makeContainer(
      overrides: {
        httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
          return FakeHttpClientFactory(() => FakeClient());
        }),
      },
    );
    return await container.read(aggregatorProvider);
  }

  Future<Aggregator> mockClientAggregator(MockClient client) async {
    final container = await lichessClientContainer(client);
    return await container.read(aggregatorProvider);
  }

  final String aggrInterval = '${kAggregationInterval.inMilliseconds}ms';

  group('Aggregator', () {
    test(
      'if only one request is made within $aggrInterval, it will make an atomic request',
      () async {
        final aggregator = await fakeClientAggregator();
        final uri = Uri(path: '/api/test');

        final response = await aggregator.readJson(uri, atomicMapper: (data) => data);

        final requests = FakeClient.verifyRequests();
        expect(requests.length, 1);
        expect(requests.first.url.path, uri.path);
        expect(response, isNotNull);
      },
    );

    test(
      'non supported uris will not aggregate and make atomic request after $aggrInterval',
      () async {
        final aggregator = await fakeClientAggregator();

        final uri1 = Uri(path: '/api/test1');
        final uri2 = Uri(path: '/api/test2');

        fakeAsync((async) {
          aggregator.readJson(uri1, atomicMapper: (data) => data);
          aggregator.readJson(uri2, atomicMapper: (data) => data);

          async.elapse(kAggregationInterval);

          // Check that the requests were made separately
          final requests = FakeClient.verifyRequests();
          expect(requests.length, 2);
        });
      },
    );

    test('supported uris will not aggregate if group has less than half of target group', () async {
      int requestsCount = 0;

      final mockClient = MockClient((request) {
        requestsCount++;
        if (request.url.path == '/api/account') {
          return mockResponse(accountResponse, 200);
        }
        if (request.url.path == '/inbox/unread-count') {
          return mockResponse('{"unread": 0, "lichess": false}', 200);
        }
        return mockResponse('', 404);
      });

      final aggregator = await mockClientAggregator(mockClient);

      final accountUri = Uri(path: '/api/account');
      final inboxUri = Uri(path: '/inbox/unread-count');

      final [account, inbox] = await Future.wait([
        aggregator.readJson(
          accountUri,
          atomicMapper: User.fromServerJson,
          aggregatedMapper: (json) => User.fromServerJson(json as Map<String, dynamic>),
        ),
        aggregator.readJson(
          inboxUri,
          atomicMapper: (Map<String, dynamic> json) {
            return (unread: json['unread'] as int, lichess: json['lichess'] as bool? ?? false);
          },
        ),
      ]);

      expect(requestsCount, 2);
      expect(account, isA<User>());
      expect(inbox, isA<_UnreadCount>());
    });

    test('aggregates home endpoint', () async {
      int requestsCount = 0;

      final mockClient = MockClient((request) {
        requestsCount++;
        if (request.url.path == '/api/mobile/home') {
          return mockResponse(homeEndpointResponse, 200);
        }
        return mockResponse('', 404);
      });

      final aggregator = await mockClientAggregator(mockClient);

      final accountUri = Uri(path: '/api/account');
      final recentGamesUri = Uri(path: '/api/games/user/testuser');
      final inboxUri = Uri(path: '/inbox/unread-count');

      final [account, recentGames, inbox] = await Future.wait([
        aggregator.readJson(
          accountUri,
          atomicMapper: User.fromServerJson,
          aggregatedMapper: (json) => User.fromServerJson(json as Map<String, dynamic>),
        ),
        aggregator.readNdJsonList(recentGamesUri, mapper: LightExportedGame.fromServerJson),
        aggregator.readJson(
          inboxUri,
          atomicMapper: (Map<String, dynamic> json) {
            return (unread: json['unread'] as int, lichess: json['lichess'] as bool? ?? false);
          },
        ),
      ]);

      expect(requestsCount, 1);
      expect(account, isA<User>());
      expect(recentGames, isA<IList<LightExportedGame>>());
      expect(inbox, isA<_UnreadCount>());
    });
  });
}

const homeEndpointResponse = '''
{
  "account": {
    "id": "testUser",
    "username": "testUser",
    "createdAt": 1290415680000,
    "seenAt": 1290415680000,
    "title": "GM",
    "patron": true,
    "patronColor": 1,
    "perfs": {
      "blitz": {
        "games": 2340,
        "rating": 1681,
        "rd": 30,
        "prog": 10
      },
      "rapid": {
        "games": 2340,
        "rating": 1677,
        "rd": 30,
        "prog": 10
      },
      "classical": {
        "games": 2340,
        "rating": 1618,
        "rd": 30,
        "prog": 10
      }
    },
    "profile": {
      "country": "France",
      "location": "Lille",
      "bio": "test bio",
      "firstName": "John",
      "lastName": "Doe",
      "fideRating": 1800,
      "links": "http://test.com"
    }
  },
  "ongoingGames": [
    {
      "gameId": "rCRw1AuO",
      "fullId": "rCRw1AuOvonq",
      "color": "black",
      "fen": "r1bqkbnr/pppp2pp/2n1pp2/8/8/3PP3/PPPB1PPP/RN1QKBNR w KQkq - 2 4",
      "hasMoved": true,
      "isMyTurn": false,
      "lastMove": "b8c6",
      "opponent": {
        "id": "philippe",
        "rating": 1790,
        "username": "Philippe"
      },
      "perf": "correspondence",
      "rated": false,
      "secondsLeft": 1209600,
      "source": "friend",
      "speed": "correspondence",
      "variant": {
        "key": "standard",
        "name": "Standard"
      }
    }
  ],
  "recentGames": [
    {"id":"Huk88k3D","rated":false,"variant":"fromPosition","speed":"blitz","perf":"blitz","createdAt":1673716450321,"lastMoveAt":1673716450321,"status":"noStart","players":{"white":{"user":{"name":"MightyNanook","id":"mightynanook"},"rating":1116,"provisional":true},"black":{"user":{"name":"Thibault","patron":true,"id":"thibault"},"rating":1772}},"initialFen":"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w - - 0 1","winner":"black","tournament":"ZZQ9tunK","clock":{"initial":300,"increment":0,"totalTime":300},"lastFen":"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w - - 0 1"},
    {"id":"g2bzFol8","rated":true,"variant":"standard","speed":"blitz","perf":"blitz","createdAt":1673553626465,"lastMoveAt":1673553936657,"status":"resign","players":{"white":{"user":{"name":"SchallUndRausch","id":"schallundrausch"},"rating":1751,"ratingDiff":-5},"black":{"user":{"name":"Thibault","patron":true,"id":"thibault"},"rating":1767,"ratingDiff":5}},"winner":"black","clock":{"initial":180,"increment":2,"totalTime":260},"lastFen":"r7/pppk4/4p1B1/3pP3/6Pp/q1P1P1nP/P1QK1r2/R5R1 w - - 1 1"},
    {"id":"9WLmxmiB","rated":true,"variant":"standard","speed":"blitz","perf":"blitz","createdAt":1673553299064,"lastMoveAt":1673553615438,"status":"resign","players":{"white":{"user":{"name":"Dr-Alaakour","id":"dr-alaakour"},"rating":1806,"ratingDiff":5},"black":{"user":{"name":"Thibault","patron":true,"id":"thibault"},"rating":1772,"ratingDiff":-5}},"winner":"white","clock":{"initial":180,"increment":0,"totalTime":180},"lastFen":"2b1Q1k1/p1r4p/1p2p1p1/3pN3/2qP4/P4R2/1P3PPP/4R1K1 b - - 0 1"}
  ],
  "challenges": {"in": [ { "socketVersion": 0, "id": "H9fIRZUk", "url": "https://lichess.org/H9fIRZUk", "status": "created", "challenger": { "id": "bot1", "name": "Bot1", "rating": 1500, "title": "BOT", "provisional": true, "online": true, "lag": 4 }, "destUser": { "id": "bobby", "name": "Bobby", "rating": 1635, "title": "GM", "provisional": true, "online": true, "lag": 4 }, "variant": { "key": "standard", "name": "Standard", "short": "Std" }, "rated": true, "speed": "rapid", "timeControl": { "type": "clock", "limit": 600, "increment": 0, "show": "10+0" }, "color": "random", "finalColor": "black", "perf": { "icon": "", "name": "Rapid" }, "direction": "out" } ], "out": [ { "socketVersion": 0, "id": "H9fIRZUk", "url": "https://lichess.org/H9fIRZUk", "status": "created", "challenger": { "id": "bot1", "name": "Bot1", "rating": 1500, "title": "BOT", "provisional": true, "online": true, "lag": 4 }, "destUser": { "id": "bobby", "name": "Bobby", "rating": 1635, "title": "GM", "provisional": true, "online": true, "lag": 4 }, "variant": { "key": "standard", "name": "Standard", "short": "Std" }, "rated": true, "speed": "rapid", "timeControl": { "type": "clock", "limit": 600, "increment": 0, "show": "10+0" }, "color": "random", "finalColor": "black", "perf": { "icon": "", "name": "Rapid" }, "direction": "out" } ] },
  "inbox": {
    "unread": 5
  }
}
''';

const accountResponse = '''
{
  "id": "testUser",
    "username": "testUser",
    "createdAt": 1290415680000,
    "seenAt": 1290415680000,
    "title": "GM",
    "patron": true,
    "patronColor": 1,
    "perfs": {
      "blitz": {
        "games": 2340,
        "rating": 1681,
        "rd": 30,
        "prog": 10
      },
      "rapid": {
        "games": 2340,
        "rating": 1677,
        "rd": 30,
        "prog": 10
      },
      "classical": {
        "games": 2340,
        "rating": 1618,
        "rd": 30,
        "prog": 10
      }
    },
    "profile": {
      "country": "France",
      "location": "Lille",
      "bio": "test bio",
      "firstName": "John",
      "lastName": "Doe",
      "fideRating": 1800,
      "links": "http://test.com"
    }
}
''';
