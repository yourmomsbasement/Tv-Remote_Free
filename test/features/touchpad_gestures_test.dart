import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote_free/core/capabilities/remote_key.dart';
import 'package:tv_remote_free/features/touchpad/touchpad_gestures.dart';

List<RemoteKey> keys(List<TouchpadAction> actions) => [
  for (final a in actions)
    if (a is ArrowKey) a.key,
];

void main() {
  test('one finger moves the pointer, scaled by sensitivity', () {
    final g = TouchpadGestures(pointer: true, scroll: true, sensitivity: 2);
    final a = g.update(fingers: 1, delta: const Offset(10, -5)).single;
    expect(
      (a as PointerMove).delta,
      const Offset(10, -5) * TouchpadGestures.pointerSpeed * 2,
    );
  });

  test('without a pointer, swipes become arrow keys per step', () {
    final g = TouchpadGestures(pointer: false, scroll: false);
    expect(keys(g.update(fingers: 1, delta: const Offset(30, 0))), isEmpty);
    expect(keys(g.update(fingers: 1, delta: const Offset(30, 0))), [
      RemoteKey.right,
    ]);
    expect(keys(g.update(fingers: 1, delta: const Offset(0, -100))), [
      RemoteKey.up,
      RemoteKey.up,
    ]);
  });

  test('higher sensitivity needs less travel per key', () {
    final slow = TouchpadGestures(pointer: false, scroll: false);
    final fast = TouchpadGestures(
      pointer: false,
      scroll: false,
      sensitivity: 2,
    );
    const swipe = Offset(0, 50);
    expect(keys(slow.update(fingers: 1, delta: swipe)), hasLength(1));
    expect(keys(fast.update(fingers: 1, delta: swipe)), hasLength(2));
  });

  test('two fingers scroll naturally where supported', () {
    final g = TouchpadGestures(pointer: true, scroll: true);
    final a = g.update(fingers: 2, delta: const Offset(0, -20)).single;
    expect((a as PointerScroll).delta, const Offset(0, 20));
  });

  test('two fingers without scroll step vertically only', () {
    final g = TouchpadGestures(pointer: true, scroll: false);
    expect(keys(g.update(fingers: 2, delta: const Offset(500, 0))), isEmpty);
    expect(keys(g.update(fingers: 2, delta: const Offset(0, 130))), [
      RemoteKey.down,
      RemoteKey.down,
    ]);
  });

  test('changing finger count starts a fresh stroke', () {
    final g = TouchpadGestures(pointer: false, scroll: false);
    g.update(fingers: 1, delta: const Offset(40, 0));
    // The partial 40px does not carry over into the two-finger stroke.
    expect(keys(g.update(fingers: 2, delta: const Offset(0, 40))), isEmpty);
    expect(keys(g.update(fingers: 1, delta: const Offset(40, 0))), isEmpty);
  });
}
