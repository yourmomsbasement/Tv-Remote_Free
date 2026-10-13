import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/capabilities/remote_key.dart';
import 'remote_session.dart';

class SleepTimerState {
  const SleepTimerState({this.endsAt, this.deviceId, this.deviceName});

  final DateTime? endsAt;
  final String? deviceId;
  final String? deviceName;

  bool get active => endsAt != null;

  Duration remaining([DateTime? now]) {
    final end = endsAt;
    if (end == null) return Duration.zero;
    final left = end.difference(now ?? DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }
}

/// Turns the TV off after a delay.
///
/// Runs in the app, so the app has to stay running: the remote keeps its
/// connection open in the background while a timer is set, but a phone may
/// still stop a backgrounded app (iOS in particular).
class SleepTimer extends Notifier<SleepTimerState> {
  Timer? _timer;

  /// Overridable in tests.
  DateTime Function() clock = DateTime.now;

  @override
  SleepTimerState build() {
    ref.onDispose(() => _timer?.cancel());
    return const SleepTimerState();
  }

  /// Whether the connected TV can be switched off by the timer.
  static bool supported(RemoteSessionState session) =>
      session.capabilities.powerOff ||
      session.capabilities.supportsKey(RemoteKey.power);

  void start(Duration duration) {
    final session = ref.read(remoteSessionProvider);
    _timer?.cancel();
    _timer = Timer(duration, _fire);
    state = SleepTimerState(
      endsAt: clock().add(duration),
      deviceId: session.device?.id,
      deviceName: session.device?.name,
    );
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    state = const SleepTimerState();
  }

  Future<void> _fire() async {
    final target = state.deviceId;
    state = const SleepTimerState();
    final remote = ref.read(remoteSessionProvider.notifier);
    var session = ref.read(remoteSessionProvider);
    if (session.device?.id != target) return; // user switched TVs meanwhile
    if (!session.isConnected) {
      await remote.reconnect();
      session = ref.read(remoteSessionProvider);
      if (!session.isConnected) return;
    }
    // Prefer an explicit "off"; the Power toggle is safe here because the
    // TV was reachable, so it is on.
    await remote.sendKey(
      session.capabilities.powerOff ? RemoteKey.powerOff : RemoteKey.power,
    );
  }
}

final sleepTimerProvider = NotifierProvider<SleepTimer, SleepTimerState>(
  SleepTimer.new,
);
