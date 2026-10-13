import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote_free/features/keyboard/text_diff.dart';

void main() {
  test('pure append inserts only the new characters', () {
    expect(TextEdit.between('hel', 'hello'), const TextEdit(0, 'lo'));
  });

  test('deleting from the end sends only deletes', () {
    expect(TextEdit.between('hello', 'he'), const TextEdit(3, ''));
  });

  test('a change in the middle deletes the tail and retypes it', () {
    expect(TextEdit.between('cat', 'cot'), const TextEdit(2, 'ot'));
  });

  test('identical text needs no edit', () {
    expect(TextEdit.between('same', 'same').isEmpty, isTrue);
  });

  test('counts emoji and other astral characters as one code point', () {
    expect(TextEdit.between('hi😀', 'hi'), const TextEdit(1, ''));
    expect(TextEdit.between('hi', 'hi😀!'), const TextEdit(0, '😀!'));
    // Same leading surrogate, different emoji: must not split the pair.
    expect(TextEdit.between('😀', '😁'), const TextEdit(1, '😁'));
  });

  test('toString never reveals the text', () {
    expect(
      TextEdit.between('', 'secret').toString(),
      isNot(contains('secret')),
    );
  });
}
