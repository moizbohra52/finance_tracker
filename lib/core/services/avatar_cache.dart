import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Local disk cache for profile avatars so they are permanently available
/// offline and across account switching without relying on expired signed URLs.
abstract final class AvatarCache {
  static Directory? _cachedDir;

  static Future<Directory> get _avatarsDir async {
    final Directory? dir = _cachedDir;
    if (dir != null) return dir;
    final Directory appDocDir = await getApplicationDocumentsDirectory();
    final Directory avatars = Directory(p.join(appDocDir.path, 'avatars'));
    if (!avatars.existsSync()) {
      await avatars.create(recursive: true);
    }
    _cachedDir = avatars;
    return avatars;
  }

  /// Returns the path to the cached avatar file for [userId], or null if it does not exist.
  static Future<String?> getCachedPath(String userId) async {
    if (userId.isEmpty) return null;
    try {
      final Directory dir = await _avatarsDir;
      final File file = File(p.join(dir.path, '$userId.jpg'));
      if (await file.exists()) {
        return file.path;
      }
    } catch (_) {}
    return null;
  }

  /// Saves raw image [bytes] for [userId] and returns the local file path.
  static Future<String?> saveBytes(String userId, Uint8List bytes) async {
    if (userId.isEmpty || bytes.isEmpty) return null;
    try {
      final Directory dir = await _avatarsDir;
      final File file = File(p.join(dir.path, '$userId.jpg'));
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// Downloads an image from [url] and caches it for [userId]. Returns the local file path or null.
  static Future<String?> cacheFromUrl(String userId, String url) async {
    if (userId.isEmpty || url.isEmpty) return null;
    try {
      if (url.startsWith('/') || !url.startsWith('http')) {
        if (File(url).existsSync()) return url;
      }
      final HttpClient client = HttpClient();
      final HttpClientRequest req = await client.getUrl(Uri.parse(url));
      final HttpClientResponse res = await req.close();
      if (res.statusCode == 200) {
        final Uint8List bytes = await consolidateHttpClientResponseBytes(res);
        return await saveBytes(userId, bytes);
      }
    } catch (_) {}
    return null;
  }

  /// Deletes the cached avatar for [userId].
  static Future<void> delete(String userId) async {
    if (userId.isEmpty) return null;
    try {
      final Directory dir = await _avatarsDir;
      final File file = File(p.join(dir.path, '$userId.jpg'));
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
