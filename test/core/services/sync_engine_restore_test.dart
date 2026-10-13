import 'dart:convert';

import 'package:finance_tracker/core/services/backup_service.dart';
import 'package:finance_tracker/core/services/sync_engine.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:finance_tracker/data/models/sync_queue_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A restored backup going up through the real SyncEngine, against a fake
/// PostgREST that records every request.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const BackupService backups = BackupService();
  const Map<String, String> jsonHeaders = <String, String>{
    'content-type': 'application/json',
  };

  late AppDatabase database;
  late List<http.Request> requests;

  /// Live server ids per table, which the replace step reads.
  late Map<String, List<String>> serverIds;
  late bool failIdReads;

  setUp(() async {
    database = await AppDatabase.inMemory();
    requests = <http.Request>[];
    serverIds = <String, List<String>>{};
    failIdReads = false;
  });

  tearDown(() async {
    await database.close();
  });

  Future<SupabaseClient> signedInClient() async {
    final SupabaseClient client = SupabaseClient(
      'https://test.supabase.co',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((http.Request request) async {
        requests.add(request);
        final Map<String, String> query = request.url.queryParameters;
        if (request.method != 'GET') {
          return http.Response('', 204, request: request);
        }
        if (query['select'] != 'id') {
          // Pulls: the server has nothing new.
          return http.Response(
            '[]',
            200,
            headers: jsonHeaders,
            request: request,
          );
        }
        if (failIdReads) {
          return http.Response(
            '{"code":"PGRST000","message":"rejected"}',
            400,
            headers: jsonHeaders,
            request: request,
          );
        }
        final String table = request.url.pathSegments.last;
        final String? after = query['id']?.replaceFirst('gt.', '');
        final List<String> ids = (serverIds[table] ?? <String>[])
            .where((String id) => after == null || id.compareTo(after) > 0)
            .take(int.parse(query['limit']!))
            .toList();
        return http.Response(
          jsonEncode(<Map<String, String>>[
            for (final String id in ids) <String, String>{'id': id},
          ]),
          200,
          headers: jsonHeaders,
          request: request,
        );
      }),
    );
    await client.auth.setInitialSession(
      jsonEncode(<String, dynamic>{
        'access_token': 'test-token',
        'token_type': 'bearer',
        'user': <String, dynamic>{
          'id': 'user-1',
          'aud': 'authenticated',
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
          'created_at': '2026-01-01T00:00:00Z',
        },
      }),
    );
    return client;
  }

  Map<String, dynamic> account(String id) => <String, dynamic>{
    'id': id,
    'user_id': 'user-1',
    'name': 'Cash',
    'type': 'cash',
    'opening_balance': '0',
    'opening_balance_date': '2026-10-01',
    'is_active': 1,
    'created_at': '2026-10-01T00:00:00Z',
    'updated_at': '2026-10-01T00:00:00Z',
    'deleted_at': null,
    'sync_status': 'synced',
  };

  List<http.Request> sent(String method, String table) => requests
      .where(
        (http.Request r) =>
            r.method == method && r.url.path == '/rest/v1/$table',
      )
      .toList();

  test(
    'a clean restore soft-deletes the server entries it does not hold, then uploads the backup',
    () async {
      final List<String> stale = <String>[
        for (int i = 0; i < 150; i++) 'old-${i.toString().padLeft(3, '0')}',
      ];
      serverIds['accounts'] = <String>['acc-1', ...stale];

      await backups.restoreBackup(
        database,
        <String, List<Map<String, dynamic>>>{
          'accounts': <Map<String, dynamic>>[account('acc-1')],
          'user_settings': <Map<String, dynamic>>[
            <String, dynamic>{
              'user_id': 'user-1',
              'date_format': 'yyyy-MM-dd',
              'number_format': 'indian',
              'first_day_of_week': 'sunday',
              'language_code': 'en',
              'default_account_id': 'acc-1',
            },
          ],
          'profiles': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'user-1',
              'full_name': 'Restored Name',
              'mobile': '9999999999',
              'avatar_url': 'user-1/old.jpg',
              'currency_code': 'USD',
              'timezone': 'Asia/Kolkata',
            },
          ],
        },
        replaceExisting: true,
        userId: 'user-1',
      );

      final SyncEngine engine = SyncEngine(
        database: database,
        client: await signedInClient(),
      );
      await engine.syncAll();

      expect(engine.lastError.value, isNull);
      expect(await database.getPendingQueueCount(), 0);

      // Ids are read page by page until an empty page.
      final List<http.Request> idReads = sent('GET', 'accounts')
          .where((http.Request r) => r.url.queryParameters['select'] == 'id')
          .toList();
      expect(idReads.length, 2);
      expect(idReads.last.url.queryParameters['id'], 'gt.old-149');
      expect(idReads.first.url.queryParameters['user_id'], 'eq.user-1');
      expect(idReads.first.url.queryParameters['deleted_at'], 'is.null');

      // Everything not in the backup is tombstoned, 100 ids per request.
      final List<http.Request> tombstones = sent('PATCH', 'accounts');
      expect(tombstones.length, 2);
      final List<String> tombstoned = <String>[
        for (final http.Request r in tombstones)
          ...r.url.queryParameters['id']!
              .replaceFirst('in.(', '')
              .replaceFirst(')', '')
              .replaceAll('"', '')
              .split(','),
      ];
      expect(tombstoned, stale);
      expect(
        (jsonDecode(tombstones.first.body) as Map<String, dynamic>).containsKey(
          'deleted_at',
        ),
        isTrue,
      );

      // Then the restored row goes up as an upsert that also clears any
      // server tombstone.
      final List<http.Request> upserts = sent('POST', 'accounts');
      expect(upserts.length, 1);
      expect(
        requests.indexOf(tombstones.last),
        lessThan(requests.indexOf(upserts.single)),
      );
      expect(upserts.single.headers['Prefer'], contains('merge-duplicates'));
      final Map<String, dynamic> row =
          jsonDecode(upserts.single.body) as Map<String, dynamic>;
      expect(row['id'], 'acc-1');
      expect(row['user_id'], 'user-1');
      expect(row.containsKey('deleted_at'), isTrue);
      expect(row['deleted_at'], isNull);
      for (final String key in <String>[
        'created_at',
        'updated_at',
        'sync_status',
        '__restore',
      ]) {
        expect(row.containsKey(key), isFalse, reason: key);
      }

      // Settings and profile are updates of the user's own rows.
      final http.Request settings = sent('PATCH', 'user_settings').single;
      expect(settings.url.queryParameters['user_id'], 'eq.user-1');
      expect(jsonDecode(settings.body), <String, dynamic>{
        'date_format': 'yyyy-MM-dd',
        'number_format': 'indian',
        'first_day_of_week': 'sunday',
        'language_code': 'en',
        'default_account_id': 'acc-1',
      });
      final http.Request profile = sent('PATCH', 'profiles').single;
      expect(profile.url.queryParameters['id'], 'eq.user-1');
      expect(jsonDecode(profile.body), <String, dynamic>{
        'full_name': 'Restored Name',
        'mobile': '9999999999',
        'currency_code': 'USD',
        'timezone': 'Asia/Kolkata',
      });
    },
  );

  test('a failed replace holds back everything queued after it', () async {
    failIdReads = true;
    await backups.restoreBackup(
      database,
      <String, List<Map<String, dynamic>>>{
        'accounts': <Map<String, dynamic>>[account('acc-1')],
      },
      replaceExisting: true,
      userId: 'user-1',
    );

    final SyncEngine engine = SyncEngine(
      database: database,
      client: await signedInClient(),
    );
    await engine.syncAll();

    // The sync stops (no pull either) and nothing is written to the server.
    expect(engine.lastError.value, contains('rejected'));
    expect(requests.where((http.Request r) => r.method != 'GET'), isEmpty);
    expect(
      requests.where(
        (http.Request r) => r.url.queryParameters['select'] != 'id',
      ),
      isEmpty,
    );

    final List<SyncQueueItem> queue = await database.getPendingQueue(limit: 50);
    expect(queue.first.operation, SyncOperation.replace);
    expect(queue.first.retryCount, 1);
    expect(queue.first.errorMessage, contains('rejected'));
    expect(queue.skip(1).every((SyncQueueItem q) => q.retryCount == 0), isTrue);
    expect(
      '${queue.last.operation.name}:${queue.last.entityId}',
      'create:acc-1',
    );
  });
}
