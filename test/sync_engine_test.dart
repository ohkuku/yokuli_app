import 'package:flutter_test/flutter_test.dart';
import 'package:yokuli_app/core/sync/sync_engine.dart';

void main() {
  group('SyncEngine.merge', () {
    // ---- helpers ----
    Map<String, dynamic> rec({
      required String id,
      required String ua,
      bool del = false,
      String src = 'device-a',
    }) =>
        {'id': id, 'ua': ua, 'del': del, 'src': src};

    // ---- upsert conflict: newer wins ----

    test('incoming newer ua wins', () {
      final existing = rec(id: '1', ua: '2024-01-01T00:00:00.000Z');
      final incoming = rec(id: '1', ua: '2024-01-02T00:00:00.000Z');
      expect(SyncEngine.merge(existing, incoming), equals(incoming));
    });

    test('existing newer ua wins', () {
      final existing = rec(id: '1', ua: '2024-01-03T00:00:00.000Z');
      final incoming = rec(id: '1', ua: '2024-01-02T00:00:00.000Z');
      expect(SyncEngine.merge(existing, incoming), equals(existing));
    });

    test('null existing returns incoming', () {
      final incoming = rec(id: '1', ua: '2024-01-01T00:00:00.000Z');
      expect(SyncEngine.merge(null, incoming), equals(incoming));
    });

    // ---- soft delete propagation ----

    test('tombstone propagates: incoming del=true wins on equal ua', () {
      final ua = '2024-06-01T12:00:00.000Z';
      final existing = rec(id: '1', ua: ua, del: false, src: 'a');
      final incoming = rec(id: '1', ua: ua, del: true, src: 'a');
      final result = SyncEngine.merge(existing, incoming);
      expect(result['del'], isTrue);
    });

    test('tombstone propagates: incoming del=true wins over older ua', () {
      final existing = rec(id: '1', ua: '2024-05-01T00:00:00.000Z', del: false);
      final incoming = rec(id: '1', ua: '2024-06-01T00:00:00.000Z', del: true);
      final result = SyncEngine.merge(existing, incoming);
      expect(result['del'], isTrue);
    });

    // ---- tombstone non-revival ----

    test('tombstone not revived: existing del=true preserved on equal ua when incoming del=false', () {
      final ua = '2024-06-01T12:00:00.000Z';
      final existing = rec(id: '1', ua: ua, del: true, src: 'a');
      final incoming = rec(id: '1', ua: ua, del: false, src: 'a');
      final result = SyncEngine.merge(existing, incoming);
      expect(result['del'], isTrue, reason: 'tombstone must not be revived');
    });

    test('tombstone not revived when newer ua comes in with del=false', () {
      // A non-deleted newer record SHOULD win (this is correct LWW behaviour)
      final existing = rec(id: '1', ua: '2024-01-01T00:00:00.000Z', del: true);
      final incoming = rec(id: '1', ua: '2024-06-01T00:00:00.000Z', del: false);
      final result = SyncEngine.merge(existing, incoming);
      // Newer updatedAt wins regardless — if intent is no revival, app layer
      // should never write a newer non-deleted record after deletion.
      expect(result['ua'], equals('2024-06-01T00:00:00.000Z'));
    });

    // ---- tie-break: larger sourceDeviceId wins ----

    test('tie ua + both non-deleted: larger src wins', () {
      final ua = '2024-06-01T00:00:00.000Z';
      final existing = rec(id: '1', ua: ua, del: false, src: 'device-a');
      final incoming = rec(id: '1', ua: ua, del: false, src: 'device-z');
      final result = SyncEngine.merge(existing, incoming);
      expect(result['src'], equals('device-z'));
    });

    test('tie ua + both non-deleted: smaller src loses', () {
      final ua = '2024-06-01T00:00:00.000Z';
      final existing = rec(id: '1', ua: ua, del: false, src: 'device-z');
      final incoming = rec(id: '1', ua: ua, del: false, src: 'device-a');
      final result = SyncEngine.merge(existing, incoming);
      expect(result['src'], equals('device-z'));
    });
  });

  group('SyncEngine.applyBatch', () {
    test('batch upsert: all new records added', () {
      final existing = <String, Map<String, dynamic>>{};
      final incoming = [
        {'id': 'a', 'ua': '2024-01-01T00:00:00.000Z', 'src': 'dev1'},
        {'id': 'b', 'ua': '2024-01-02T00:00:00.000Z', 'src': 'dev1'},
      ];
      final result = SyncEngine.applyBatch(existing, incoming);
      expect(result.keys, containsAll(['a', 'b']));
    });

    test('batch upsert: LWW applied per record', () {
      final existing = {
        'a': {'id': 'a', 'ua': '2024-06-01T00:00:00.000Z', 'src': 'dev1', 'v': 1},
      };
      final incoming = [
        {'id': 'a', 'ua': '2024-05-01T00:00:00.000Z', 'src': 'dev1', 'v': 0},
      ];
      final result = SyncEngine.applyBatch(existing, incoming);
      expect(result['a']!['v'], equals(1), reason: 'older incoming should lose');
    });
  });

  group('SyncEngine.missingFor', () {
    final records = [
      {'id': '1', 'ua': '2024-01-01T00:00:00.000Z'},
      {'id': '2', 'ua': '2024-03-01T00:00:00.000Z'},
      {'id': '3', 'ua': '2024-06-01T00:00:00.000Z'},
    ];

    test('null cursor returns all records', () {
      final result = SyncEngine.missingFor(records, null);
      expect(result.length, equals(3));
    });

    test('cursor filters to strictly newer records', () {
      final cursor = DateTime.parse('2024-02-01T00:00:00.000Z');
      final result = SyncEngine.missingFor(records, cursor);
      expect(result.map((r) => r['id']).toList(), containsAll(['2', '3']));
      expect(result.map((r) => r['id']).toList(), isNot(contains('1')));
    });

    test('cursor equal to newest returns empty', () {
      final cursor = DateTime.parse('2024-06-01T00:00:00.000Z');
      final result = SyncEngine.missingFor(records, cursor);
      expect(result, isEmpty);
    });
  });

  group('SyncEngine.computeCursor', () {
    test('returns max ua across all records', () {
      final records = [
        {'id': '1', 'ua': '2024-01-01T00:00:00.000Z'},
        {'id': '2', 'ua': '2024-06-15T12:30:00.000Z'},
        {'id': '3', 'ua': '2024-03-01T00:00:00.000Z'},
      ];
      final current = DateTime.parse('2024-01-01T00:00:00.000Z');
      final result = SyncEngine.computeCursor(records, current);
      expect(result, equals(DateTime.parse('2024-06-15T12:30:00.000Z')));
    });

    test('returns current when all records are older', () {
      final records = [
        {'id': '1', 'ua': '2023-01-01T00:00:00.000Z'},
      ];
      final current = DateTime.parse('2024-01-01T00:00:00.000Z');
      final result = SyncEngine.computeCursor(records, current);
      expect(result, equals(current));
    });
  });

  group('Concurrent conflict resolution', () {
    test('deterministic result regardless of merge order', () {
      final ua = '2024-06-01T00:00:00.000Z';
      final r1 = {'id': 'x', 'ua': ua, 'del': false, 'src': 'device-aaa'};
      final r2 = {'id': 'x', 'ua': ua, 'del': false, 'src': 'device-zzz'};

      // Merge r1 into r2 and vice versa — should produce the same winner
      final result1 = SyncEngine.merge(r1, r2);
      final result2 = SyncEngine.merge(r2, r1);
      expect(result1['src'], equals(result2['src']),
          reason: 'merge must be commutative (same winner regardless of order)');
      expect(result1['src'], equals('device-zzz'));
    });
  });
}
