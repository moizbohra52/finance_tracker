/// Tags are #words inside a transaction note, e.g. "Dinner #office #goa".
/// Searching the notes for "#goa" finds them, so tags need no column of their
/// own (docs/01_PRODUCT_REQUIREMENTS.md).
// shortcut: that search is a substring match, so "#goa" also finds "#goatrip";
// match whole tags in TransactionRepository if users run into it.
abstract final class NoteTags {
  // Starts with a letter (so "#2" in "Invoice #2" is not a tag), then letters
  // of any script with their marks, or digits. No `_`: the transaction search
  // drops it as a LIKE wildcard, so such a tag could never be found.
  static final RegExp _tag = RegExp(r'#\p{L}[\p{L}\p{M}\p{N}]*', unicode: true);

  /// The tags in [text] as first written, without repeats (ignoring case).
  static List<String> of(String? text) {
    final Set<String> seen = <String>{};
    return <String>[
      for (final Match m in _tag.allMatches(text ?? ''))
        if (seen.add(m.group(0)!.toLowerCase())) m.group(0)!,
    ];
  }

  /// [note] with [tag] appended, unless it already has it.
  static String add(String note, String tag) {
    final String lower = tag.toLowerCase();
    if (of(note).any((String t) => t.toLowerCase() == lower)) return note;
    final String trimmed = note.trimRight();
    return trimmed.isEmpty ? tag : '$trimmed $tag';
  }
}
