/// Why a picked photo cannot be used. The storage bucket enforces the same
/// limits on the server; checking first gives a clear message and skips a
/// pointless upload.
enum AvatarProblem {
  empty,
  unsupportedType,
  tooLarge;

  String get message => switch (this) {
    AvatarProblem.empty => 'That photo is empty. Choose another one.',
    AvatarProblem.unsupportedType => 'Choose a JPG, PNG or WebP image.',
    AvatarProblem.tooLarge =>
      'That photo is larger than 2 MB. Choose a smaller one.',
  };
}

/// The rules for a profile photo: JPEG, PNG or WebP, at most 2 MiB, and not
/// empty. Matches the `avatars` bucket limits in the Phase 10 migration.
abstract final class AvatarRules {
  static const int maxBytes = 2 * 1024 * 1024;

  /// File extension (lower case) to MIME type for every accepted format.
  static const Map<String, String> contentTypes = <String, String>{
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
  };

  /// The problem with a photo named [fileName] of [byteLength] bytes, or null
  /// when it can be uploaded.
  static AvatarProblem? check({
    required String fileName,
    required int byteLength,
  }) {
    if (byteLength == 0) return AvatarProblem.empty;
    if (!contentTypes.containsKey(extensionOf(fileName))) {
      return AvatarProblem.unsupportedType;
    }
    if (byteLength > maxBytes) return AvatarProblem.tooLarge;
    return null;
  }

  /// Lower-case extension without the dot, or '' when there is none.
  static String extensionOf(String fileName) {
    final int dot = fileName.lastIndexOf('.');
    return dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  }
}
