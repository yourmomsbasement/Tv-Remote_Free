/// The minimal edit that turns the text the TV has into the text the user has,
/// assuming the TV cursor sits at the end of its field.
///
/// Deleting [deleteCount] characters and then inserting [insert] is valid for
/// append-only protocols (character key events plus backspace) as well as for
/// text APIs, so the TV never receives the whole buffer twice.
class TextEdit {
  const TextEdit(this.deleteCount, this.insert);

  static const none = TextEdit(0, '');

  /// Number of Unicode code points to delete from the end.
  final int deleteCount;
  final String insert;

  bool get isEmpty => deleteCount == 0 && insert.isEmpty;

  /// Computed on code points: TV protocols delete per character, and a
  /// UTF-16 based diff could split a surrogate pair.
  static TextEdit between(String current, String target) {
    if (current == target) return none;
    final a = current.runes.toList();
    final b = target.runes.toList();
    var prefix = 0;
    final limit = a.length < b.length ? a.length : b.length;
    while (prefix < limit && a[prefix] == b[prefix]) {
      prefix++;
    }
    return TextEdit(a.length - prefix, String.fromCharCodes(b.sublist(prefix)));
  }

  @override
  bool operator ==(Object other) =>
      other is TextEdit &&
      other.deleteCount == deleteCount &&
      other.insert == insert;

  @override
  int get hashCode => Object.hash(deleteCount, insert);

  // Never include the text itself: it may be a password.
  @override
  String toString() =>
      'TextEdit(delete: $deleteCount, insert: ${insert.runes.length} chars)';
}
