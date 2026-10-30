import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/data/repositories/photo_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// PhotoStore against a fake storage server that keeps uploaded objects.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String objects = '/storage/v1/object/avatars/';
  late Map<String, Uint8List> server;
  late List<http.Request> requests;
  late List<Directory> phones;

  setUp(() {
    server = <String, Uint8List>{};
    requests = <http.Request>[];
    phones = <Directory>[];
  });

  tearDown(() async {
    for (final Directory dir in phones) {
      await dir.delete(recursive: true);
    }
  });

  /// A store on a new phone (its own documents folder), same server.
  Future<PhotoStore> phone() async {
    final Directory documents = await Directory.systemTemp.createTemp(
      'photos_test',
    );
    phones.add(documents);
    final SupabaseClient client = SupabaseClient(
      'https://test.supabase.co',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((http.Request request) async {
        requests.add(request);
        final String path = request.url.path;
        if (request.method == 'POST' && path.startsWith(objects)) {
          final String key = path.substring(objects.length);
          server[key] = request.bodyBytes;
          return http.Response(
            jsonEncode(<String, String>{'Key': 'avatars/$key'}),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }
        if (request.method == 'DELETE') {
          final List<dynamic> keys =
              (jsonDecode(request.body) as Map<String, dynamic>)['prefixes']
                  as List<dynamic>;
          keys.forEach(server.remove);
          return http.Response(
            '[]',
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }
        for (final MapEntry<String, Uint8List> object in server.entries) {
          if (path.endsWith(object.key)) {
            return http.Response.bytes(object.value, 200);
          }
        }
        return http.Response(
          '{"statusCode":"404","error":"not_found","message":"Object not found"}',
          400,
          headers: <String, String>{'content-type': 'application/json'},
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
    return PhotoStore(client, documents: () async => documents);
  }

  final Uint8List jpeg = Uint8List.fromList(List<int>.filled(64, 7));

  int gets() => requests.where((http.Request r) => r.method == 'GET').length;

  test('an upload goes under the user and stays on the phone', () async {
    final PhotoStore store = await phone();

    final String path = await store.upload(
      folder: PhotoStore.contacts,
      id: 'c1',
      bytes: jpeg,
      fileName: 'IMG_1.jpg',
    );

    expect(path, matches(RegExp(r'^user-1/contacts/c1-\d+\.jpg$')));
    expect(server.containsKey(path), isTrue);
    final File? file = await store.file(path);
    expect(await file!.readAsBytes(), jpeg);
    expect(gets(), 0, reason: 'the uploading phone already has it');
  });

  test('another phone downloads a photo once, then shows its copy', () async {
    final String path = await (await phone()).upload(
      folder: PhotoStore.groups,
      id: 'g1',
      bytes: jpeg,
      fileName: 'pic.png',
    );
    final PhotoStore other = await phone();

    // The fake keeps the request body as sent, which is what comes back.
    expect(await (await other.file(path))!.readAsBytes(), server[path]);
    expect(await (await other.file(path))!.readAsBytes(), server[path]);
    expect(gets(), 1);
  });

  test(
    'a photo that cannot be fetched shows nothing and is tried again',
    () async {
      final PhotoStore store = await phone();

      expect(await store.file('user-1/contacts/missing-1.jpg'), isNull);
      expect(await store.file('user-1/contacts/missing-1.jpg'), isNull);
      expect(gets(), 2);
    },
  );

  test('remove deletes the server object and the copy', () async {
    final PhotoStore store = await phone();
    final String path = await store.upload(
      folder: PhotoStore.contacts,
      id: 'c1',
      bytes: jpeg,
      fileName: 'IMG_1.jpg',
    );
    final File file = (await store.file(path))!;

    await store.remove(path);

    expect(server.containsKey(path), isFalse);
    expect(await file.exists(), isFalse);
  });

  test('a file the bucket would refuse is not sent', () async {
    final PhotoStore store = await phone();

    await expectLater(
      store.upload(
        folder: PhotoStore.contacts,
        id: 'c1',
        bytes: jpeg,
        fileName: 'scan.gif',
      ),
      throwsA(isA<StorageFailure>()),
    );
    expect(requests, isEmpty);
  });
}
