import 'package:flutter_test/flutter_test.dart';
import 'package:drift_globe_poc/features/intention/intention_engine.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test('six categories are defined', () {
    expect(intentionCategories, [
      'Peace', 'Mystery', 'Adventure', 'Inspiration', 'Discovery', 'Connection'
    ]);
  });

  test('description only boosts compatible categories', () {
    expect(IntentionEngine.descriptionBonus('Peace', 'quiet forest', 'natural=wood'), 8);
    expect(IntentionEngine.descriptionBonus('Peace', 'busy nightlife', 'natural=wood'), 0);
    expect(IntentionEngine.descriptionBonus('Connection', 'beach', 'natural=beach'), 8);
    expect(IntentionEngine.descriptionBonus('Mystery', 'castle', 'historic=castle'), 8);
    expect(IntentionEngine.descriptionBonus('Adventure', 'castle', 'historic=castle'), 0);
  });

  test('invalid intention fails before any network request', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{}', 200);
    });
    addTearDown(client.close);
    final engine = IntentionEngine(client: client);
    await expectLater(
      engine.generate(origin: const LatLng(40, -80), radiusMeters: 5000,
          category: 'Unknown'),
      throwsArgumentError,
    );
    expect(calls, 0);
  });

  test('geographic API failure produces a useful error', () async {
    final client = MockClient((request) async => http.Response('Unavailable', 503));
    addTearDown(client.close);
    final engine = IntentionEngine(client: client);
    await expectLater(
      engine.generate(origin: const LatLng(40, -80), radiusMeters: 5000,
          category: 'Peace'),
      throwsA(isA<StateError>().having(
        (error) => error.message, 'message',
        contains('Geographic context is temporarily unavailable'),
      )),
    );
  });

  test('empty geographic results fail without routing calls', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      return http.Response('{"elements":[]}', 200);
    });
    addTearDown(client.close);
    final engine = IntentionEngine(client: client);
    await expectLater(
      engine.generate(origin: const LatLng(40, -80), radiusMeters: 40,
          category: 'Peace'),
      throwsA(isA<StateError>().having(
        (error) => error.message, 'message',
        contains('No matching route-verified point'),
      )),
    );
    expect(requests, 1);
  });
}
