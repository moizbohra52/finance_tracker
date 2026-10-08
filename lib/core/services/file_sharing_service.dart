import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Service to save exported documents and trigger platform share sheets.
class FileSharingService {
  const FileSharingService();

  /// Saves content string as a file and opens the platform share sheet.
  Future<ShareResult> saveAndShareString({
    required String fileName,
    required String content,
    String? mimeType,
    String? subject,
  }) async {
    final Directory tempDir = await getTemporaryDirectory();
    final File file = File(p.join(tempDir.path, fileName));
    // Write as UTF-8 bytes to ensure correct character representation
    await file.writeAsBytes(utf8.encode(content), flush: true);

    return SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(file.path, mimeType: mimeType, name: fileName)],
        subject: subject ?? fileName,
      ),
    );
  }

  /// Saves binary bytes as a file and opens the platform share sheet.
  Future<ShareResult> saveAndShareBytes({
    required String fileName,
    required List<int> bytes,
    String? mimeType,
    String? subject,
  }) async {
    final Directory tempDir = await getTemporaryDirectory();
    final File file = File(p.join(tempDir.path, fileName));
    await file.writeAsBytes(bytes, flush: true);

    return SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(file.path, mimeType: mimeType, name: fileName)],
        subject: subject ?? fileName,
      ),
    );
  }
}
