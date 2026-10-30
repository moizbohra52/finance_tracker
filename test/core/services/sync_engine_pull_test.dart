import 'dart:convert';

import 'package:finance_tracker/core/services/sync_engine.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:finance_tracker/data/models/sync_queue_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Pulls and uploads through the real SyncEngine against a fake PostgREST
/// that pages like the real one (at most 1000 rows per response).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const Map<String, String> jsonHeaders = <String, String>{
    'content-type': 'application/json',
  };

  late AppDatabase database;
  late List<http.Request> requests;
  late List<Map<String, dynamic>> serverTransactions;

  setUp(() async {
    database = await AppDatabase.inMemory();
    requests = <http.Request>[];
    serverTransactions = <Map<String, dynamic>>[];
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
        if (request.method != 'GET') {
          return http.Response('', 204, request: request);
        }
        final Map<String, String> query = request.url.queryParameters;
        final List<Map<String, dynamic>> rows =
            request.url.pathSegments.last == 'transactions'
            ? serverTransactions
                  .skip(int.parse(query['offset'] ?? '0'))
                  .take(
                    // The server cap, whatever the client asks for.
                    int.parse(query['limit'] ?? '1000').clamp(0, 1000),
                  )
                  .toList()
            : <Map<String, dynamic>>[];
        return http.Response(
          jsonEncode(rows),
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

  Map<String, dynamic> serverRow(int i, {String? date}) => <String, dynamic>{
    'id': 'tx-${i.toString().padLeft(5, '0')}',
    'user_id': 'user-1',
    'account_id': 'acc-1',
    'type': 'expense',
    'amount': 10,
    'transaction_date': date ?? '2026-10-01T00:00:00+00:00',
    'created_at': '2026-10-01T00:00:00+00:00',
    'updated_at': '2026-10-01T00:00:00.123456+00:00',
    'deleted_at': null,
  };

  Future<int> localCount() async {
    final List<Map<String, Object?>> rows = await database.db.rawQuery(
      'SELECT COUNT(*) AS n FROM transactions',
    );
    return rows.first['n']! as int;
  }

  test('a first sync pulls every row, not just the first 1000', () async {
    serverTransactions = <Map<String, dynamic>>[
      for (int i = 0; i < 2300; i++) serverRow(i),
    ];

    final SyncEngine engine = SyncEngine(
      database: database,
      client: await signedInClient(),
    );
    await engine.syncAll();

    expect(engine.lastError.value, isNull);
    expect(await localCount(), 2300);
  });

  test('pulled timestamps are stored as UTC "Z" text, so date filters find '
      'a row dated at local midnight', () async {
    serverTransactions = <Map<String, dynamic>>[
      serverRow(1, date: '2026-09-30T18:30:00+00:00'),
    ];

    await SyncEngine(
      database: database,
      client: await signedInClient(),
    ).syncAll();

    final List<Map<String, Object?>> rows = await database.db.query(
      'transactions',
      where: 'transaction_date >= ?',
      whereArgs: <Object>['2026-09-30T18:30:00.000Z'],
    );
    expect(rows, hasLength(1));
    expect(rows.first['transaction_date'], '2026-09-30T18:30:00.000Z');
    expect(rows.first['updated_at'], '2026-10-01T00:00:00.123456Z');
    // A plain date column is not a timestamp and stays as it is.
    expect(rows.first['account_id'], 'acc-1');
  });

  test('an upload cut off mid-request is sent again, and a create clears '
      'any server tombstone', () async {
    final int id = await database.enqueue(
      SyncQueueItem(
        operation: SyncOperation.create,
        entity: 'split_expense_parts',
        entityId: 'part-1',
        payload: <String, dynamic>{'id': 'part-1', 'amount': '50'},
        createdAt: DateTime.now(),
      ),
    );
    await database.updateQueueItemStatus(
      id: id,
      status: SyncItemStatus.processing,
    );
    expect(await database.getPendingQueueCount(), 1);

    final SyncEngine engine = SyncEngine(
      database: database,
      client: await signedInClient(),
    );
    await engine.syncAll();

    final List<http.Request> upserts = requests
        .where(
          (http.Request r) =>
              r.method == 'POST' &&
              r.url.path == '/rest/v1/split_expense_parts',
        )
        .toList();
    expect(upserts, hasLength(1));
    final Map<String, dynamic> body =
        jsonDecode(upserts.single.body) as Map<String, dynamic>;
    expect(body.containsKey('deleted_at'), isTrue);
    expect(body['deleted_at'], isNull);
    expect(await database.getPendingQueueCount(), 0);
  });

  test('upgrading to version 6 rewrites server-format timestamps', () async {
    await database.db.insert('transactions', <String, Object?>{
      'id': 'old-1',
      'account_id': 'acc-1',
      'type': 'expense',
      'amount': '10',
      'transaction_date': '2026-09-30T18:30:00+00:00',
      'created_at': '2026-09-30T18:30:00.5+00:00',
      'updated_at': '2026-09-30T18:30:00.000Z',
    });
    await database.db.insert('accounts', <String, Object?>{
      'id': 'acc-1',
      'name': 'Cash',
      'type': 'cash',
      'opening_balance': '0',
      'opening_balance_date': '2026-10-01',
      'created_at': '2026-10-01T00:00:00+00:00',
      'updated_at': '2026-10-01T00:00:00+00:00',
    });

    await AppDatabase.upgrade(database.db, 5, 6);

    final Map<String, Object?> tx = (await database.db.query(
      'transactions',
    )).single;
    expect(tx['transaction_date'], '2026-09-30T18:30:00.000Z');
    expect(tx['created_at'], '2026-09-30T18:30:00.500Z');
    expect(tx['updated_at'], '2026-09-30T18:30:00.000Z');
    final Map<String, Object?> account = (await database.db.query(
      'accounts',
    )).single;
    expect(account['opening_balance_date'], '2026-10-01');
    expect(account['created_at'], '2026-10-01T00:00:00.000Z');
  });
}
