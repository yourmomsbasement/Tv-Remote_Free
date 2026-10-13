import 'dart:ui';

import '../../core/capabilities/remote_key.dart';

/// What a touchpad gesture should do on the TV.
sealed class TouchpadAction {
  const TouchpadAction();
}

class PointerMove extends TouchpadAction {
  const PointerMove(this.delta);
  final Offset delta;
}

class PointerScroll extends TouchpadAction {
  const PointerScroll(this.delta);
  final Offset delta;
}

class ArrowKey extends TouchpadAction {
  const ArrowKey(this.key);
  final RemoteKey key;
}

/// Turns finger movement into TV actions.
///
/// - One finger moves the pointer on TVs that have one; elsewhere every
///   [swipeStep] of travel becomes an arrow key.
/// - Two fingers scroll on TVs that support it; elsewhere a vertical
///   two-finger drag steps Up/Down, a little slower than one finger.
///
/// [sensitivity] (0.5–3) scales pointer speed and shortens the swipe step.
class TouchpadGestures {
  TouchpadGestures({
    required this.pointer,
    required this.scroll,
    this.sensitivity = 1,
  });

  final bool pointer;
  final bool scroll;
  final double sensitivity;

  static const pointerSpeed = 1.6;
  static const baseSwipeStep = 48.0;
  static const baseScrollStep = 64.0;

  double get swipeStep => baseSwipeStep / sensitivity;
  double get scrollStep => baseScrollStep / sensitivity;

  Offset _swipe = Offset.zero;
  int _fingers = 0;

  /// Call when a gesture starts or the number of fingers changes.
  void reset() {
    _swipe = Offset.zero;
    _fingers = 0;
  }

  List<TouchpadAction> update({required int fingers, required Offset delta}) {
    if (fingers != _fingers) {
      // Lifting or adding a finger starts a fresh stroke.
      _swipe = Offset.zero;
      _fingers = fingers;
    }
    if (fingers >= 2) {
      if (scroll) {
        // Natural scrolling: content follows the fingers.
        return [PointerScroll(-delta * sensitivity)];
      }
      return _steps(Offset(0, delta.dy), scrollStep);
    }
    if (pointer) return [PointerMove(delta * pointerSpeed * sensitivity)];
    return _steps(delta, swipeStep);
  }

  List<TouchpadAction> _steps(Offset delta, double step) {
    _swipe += delta;
    final out = <TouchpadAction>[];
    while (_swipe.distance >= step) {
      if (_swipe.dx.abs() > _swipe.dy.abs()) {
        out.add(ArrowKey(_swipe.dx > 0 ? RemoteKey.right : RemoteKey.left));
        _swipe = Offset(_swipe.dx - step * _swipe.dx.sign, 0);
      } else {
        out.add(ArrowKey(_swipe.dy > 0 ? RemoteKey.down : RemoteKey.up));
        _swipe = Offset(0, _swipe.dy - step * _swipe.dy.sign);
      }
    }
    return out;
  }
}
