import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/adapter/smart_tv_adapter.dart';
import '../remote/remote_session.dart';
import 'macro.dart';

enum StepStatus { pending, running, done, skipped, failed, notRun }

class StepOutcome {
  const StepOutcome(this.status, [this.message]);
  final StepStatus status;
  final String? message;
}

class MacroRunState {
  const MacroRunState({
    this.macro,
    this.outcomes = const [],
    this.running = false,
  });

  final Macro? macro;
  final List<StepOutcome> outcomes;
  final bool running;

  bool get succeeded =>
      !running &&
      macro != null &&
      outcomes.every(
        (o) => o.status == StepStatus.done || o.status == StepStatus.skipped,
      );
}

/// Runs one macro at a time against the remote session.
///
/// Each step runs only if the TV supports it; unsupported steps are skipped
/// with the reason. A step that fails stops the macro when
/// [Macro.stopOnError] is set, otherwise the macro carries on.
class MacroRunner extends Notifier<MacroRunState> {
  /// Gap between repeated key presses within one step.
  static const keyRepeatGap = Duration(milliseconds: 200);
  static const pollInterval = Duration(milliseconds: 250);
  static const nudgeInterval = Duration(seconds: 5);

  bool _cancelled = false;

  @override
  MacroRunState build() => const MacroRunState();

  RemoteSession get _session => ref.read(remoteSessionProvider.notifier);
  RemoteSessionState get _state => ref.read(remoteSessionProvider);

  void cancel() => _cancelled = true;

  void _set(int index, StepOutcome outcome) {
    final outcomes = [...state.outcomes]..[index] = outcome;
    state = MacroRunState(
      macro: state.macro,
      outcomes: outcomes,
      running: state.running,
    );
  }

  Future<MacroRunState> run(Macro macro) async {
    if (state.running) return state;
    _cancelled = false;
    state = MacroRunState(
      macro: macro,
      outcomes: [
        for (final _ in macro.steps) const StepOutcome(StepStatus.pending),
      ],
      running: true,
    );
    await _selectDevice(macro);

    for (var i = 0; i < macro.steps.length; i++) {
      if (_cancelled) {
        _markRemaining(i, 'Cancelled');
        break;
      }
      _set(i, const StepOutcome(StepStatus.running));
      final outcome = await _runStep(macro.steps[i]);
      _set(i, outcome);
      if (outcome.status == StepStatus.failed && macro.stopOnError) {
        _markRemaining(i + 1, 'Stopped after an earlier step failed');
        break;
      }
    }
    state = MacroRunState(
      macro: macro,
      outcomes: state.outcomes,
      running: false,
    );
    return state;
  }

  void _markRemaining(int from, String reason) {
    for (var j = from; j < state.outcomes.length; j++) {
      _set(j, StepOutcome(StepStatus.notRun, reason));
    }
  }

  /// Switches to the macro's TV. Connecting may fail while the TV is off;
  /// a Power on / Wait step then takes care of it.
  Future<void> _selectDevice(Macro macro) async {
    final id = macro.deviceId;
    if (id == null || _state.device?.id == id) return;
    final device = await ref.read(deviceRepositoryProvider).getDevice(id);
    if (device != null) await _session.connect(device);
  }

  Future<StepOutcome> _runStep(MacroStep step) async {
    switch (step) {
      case DelayStep(:final milliseconds):
        await _sleep(Duration(milliseconds: milliseconds));
        return const StepOutcome(StepStatus.done);
      case WaitConnectedStep(:final timeoutSeconds):
        return await _waitConnected(Duration(seconds: timeoutSeconds))
            ? const StepOutcome(StepStatus.done)
            : StepOutcome(
                StepStatus.failed,
                'The TV did not respond within $timeoutSeconds s',
              );
      case PowerOnStep():
        if (_state.isConnected && !_state.capabilities.powerOn) {
          return const StepOutcome(StepStatus.skipped, 'The TV is already on');
        }
        if (!_state.canPowerOn) {
          return const StepOutcome(
            StepStatus.failed,
            'No way to turn this TV on from the phone (connect once while '
            'it is on so the app learns its network address)',
          );
        }
        return await _session.powerOn()
            ? const StepOutcome(StepStatus.done)
            : _failure();
      case KeyStep() || LaunchAppStep() || VolumeStep() || TextStep():
        if (!_state.isConnected) {
          return const StepOutcome(
            StepStatus.failed,
            'Not connected to the TV',
          );
        }
        final reason = step.unsupportedReason(_state.capabilities);
        if (reason != null) return StepOutcome(StepStatus.skipped, reason);
        final ok = await switch (step) {
          KeyStep(:final key, :final times) => _repeat(
            times,
            () => _session.sendKey(key),
          ),
          LaunchAppStep(:final appId) => _session.launchApp(appId),
          VolumeStep(:final level) => _session.setVolume(level),
          TextStep(:final text, :final submit) => _session.typeText(
            text,
            submit: submit,
          ),
          _ => Future.value(false),
        };
        return ok ? const StepOutcome(StepStatus.done) : _failure();
    }
  }

  StepOutcome _failure() {
    final error = _state.error;
    _session.clearError();
    return StepOutcome(StepStatus.failed, error?.message ?? 'The TV refused');
  }

  Future<bool> _repeat(int times, Future<bool> Function() action) async {
    for (var i = 0; i < times; i++) {
      if (_cancelled) return false;
      if (!await action()) return false;
      if (i < times - 1) await _sleep(keyRepeatGap);
    }
    return true;
  }

  Future<bool> _waitConnected(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    DateTime? lastNudge;
    while (!_state.isConnected) {
      final now = DateTime.now();
      if (_cancelled || now.isAfter(deadline)) return false;
      // If nothing is connecting (e.g. after Wake-on-LAN the TV needs a few
      // seconds), start an attempt; never interrupt one in progress.
      final idle =
          _state.status == ConnectionStatus.disconnected &&
          !_state.reconnecting;
      if (idle &&
          _state.device != null &&
          (lastNudge == null || now.difference(lastNudge) > nudgeInterval)) {
        lastNudge = now;
        unawaited(_session.reconnect());
      }
      await _sleep(pollInterval);
    }
    return true;
  }

  /// Sleeps in short slices so Cancel takes effect quickly.
  Future<void> _sleep(Duration duration) async {
    final end = DateTime.now().add(duration);
    while (!_cancelled && DateTime.now().isBefore(end)) {
      final left = end.difference(DateTime.now());
      await Future<void>.delayed(left < pollInterval ? left : pollInterval);
    }
  }
}

final macroRunnerProvider = NotifierProvider<MacroRunner, MacroRunState>(
  MacroRunner.new,
);
