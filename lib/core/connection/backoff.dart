import 'dart:math';

/// Exponential backoff with jitter for reconnect attempts.
class Backoff {
  Backoff({
    this.initial = const Duration(milliseconds: 500),
    this.max = const Duration(seconds: 30),
    this.factor = 2.0,
    Random? random,
  }) : _random = random ?? Random();

  final Duration initial;
  final Duration max;
  final double factor;
  final Random _random;
  int _attempt = 0;

  int get attempt => _attempt;

  /// Delay before the next attempt; grows until [max], with ±20% jitter.
  Duration next() {
    final base = initial.inMilliseconds * pow(factor, _attempt);
    _attempt++;
    final capped = min(base, max.inMilliseconds.toDouble());
    final jitter = capped * 0.2 * (_random.nextDouble() * 2 - 1);
    return Duration(milliseconds: (capped + jitter).round());
  }

  void reset() => _attempt = 0;
}
