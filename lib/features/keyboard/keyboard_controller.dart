import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/adapter/smart_tv_adapter.dart';
import '../../core/capabilities/device_capabilities.dart';
import '../../core/errors.dart';
import 'text_diff.dart';

/// States from the design's keyboard synchronization machine.
enum KeyboardState {
  disconnected,
  connected,
  textFieldDetected,
  keyboardActive,
  textEditing,
  textSubmitted,
  keyboardClosed,
}

/// How typed text reaches the TV.
enum KeyboardSyncMode {
  /// Edits are diffed and streamed as the user types (batched).
  live,

  /// Text is held on the phone until the user presses Send.
  manual,
}

/// Keeps the phone's text buffer and the TV's text field in step.
///
/// The controller remembers what it has already sent and only transmits the
/// difference, so append-only TVs never get duplicated characters. All
/// operations are serialized so edits arrive in order.
///
/// Text content is never logged, and buffers are cleared when a session
/// ends or a sensitive (password) session closes.
class KeyboardController extends ChangeNotifier {
  KeyboardController({this.batchDelay = const Duration(milliseconds: 40)});

  /// How long to wait for more keystrokes before sending (20–75 ms).
  Duration batchDelay;

  SmartTVAdapter? _adapter;
  DeviceCapabilities _capabilities = DeviceCapabilities.none;
  KeyboardState _state = KeyboardState.disconnected;
  KeyboardSyncMode _mode = KeyboardSyncMode.live;
  String _local = '';
  String _sent = '';
  bool _sensitive = false;
  bool _outOfSync = false;
  TvRemoteException? _lastError;
  Timer? _batchTimer;
  Future<void> _queue = Future.value();

  KeyboardState get state => _state;
  KeyboardSyncMode get mode => _mode;
  bool get sensitive => _sensitive;

  /// True after a failed send: the TV may hold different text than the phone.
  bool get outOfSync => _outOfSync;
  TvRemoteException? get lastError => _lastError;
  bool get isAvailable => _adapter != null && _capabilities.textInput;
  bool get detectsTextFields => _capabilities.textFieldDetection;
  String get text => _local;

  /// Number of characters the phone believes are in the TV field.
  int get sentLength => _sent.runes.length;
  bool get hasPendingText => _local != _sent;

  bool get isActive =>
      _state == KeyboardState.keyboardActive ||
      _state == KeyboardState.textEditing ||
      _state == KeyboardState.textFieldDetected;

  void attach(SmartTVAdapter adapter, DeviceCapabilities capabilities) {
    _adapter = adapter;
    _capabilities = capabilities;
    _mode = capabilities.textInput ? _mode : KeyboardSyncMode.manual;
    _resetBuffers();
    _setState(KeyboardState.connected);
  }

  void detach() {
    _adapter = null;
    _capabilities = DeviceCapabilities.none;
    _resetBuffers();
    _setState(KeyboardState.disconnected);
  }

  set mode(KeyboardSyncMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    if (mode == KeyboardSyncMode.live) _scheduleFlush();
    notifyListeners();
  }

  /// The TV reported a text field gaining or losing focus.
  void onTextFieldFocus(TextFieldFocusChanged event) {
    if (_adapter == null) return;
    if (event.focused) {
      // A newly focused field: whatever we sent before belongs to another field.
      _resetBuffers();
      _sensitive = event.sensitive;
      _setState(KeyboardState.textFieldDetected);
    } else {
      _close();
    }
  }

  /// The user opened the keyboard manually (no focus detection, or override).
  void open({bool sensitive = false}) {
    _requireAvailable();
    if (_state != KeyboardState.textFieldDetected) _resetBuffers();
    _sensitive = _sensitive || sensitive;
    _setState(KeyboardState.keyboardActive);
  }

  /// New contents of the phone text field.
  void updateText(String text) {
    if (!isAvailable || text == _local) return;
    _local = text;
    _setState(KeyboardState.textEditing);
    if (_mode == KeyboardSyncMode.live) _scheduleFlush();
  }

  /// Backspace pressed. With an empty buffer this deletes text that was
  /// already in the TV field before typing started.
  Future<void> backspace() {
    if (!isAvailable) return Future.value();
    if (_local.isEmpty) {
      return _enqueue(() => _adapter!.deleteText(1));
    }
    final runes = _local.runes.toList()..removeLast();
    updateText(String.fromCharCodes(runes));
    return _mode == KeyboardSyncMode.live ? flush() : Future.value();
  }

  /// Removes everything this session typed into the TV field.
  Future<void> clear() {
    if (!isAvailable) return Future.value();
    _local = '';
    return flush();
  }

  /// Sends any pending text immediately (also used by "Send" in manual mode).
  Future<void> flush() {
    _batchTimer?.cancel();
    _batchTimer = null;
    return _enqueue(_sendDiff);
  }

  /// Sends pending text, then Enter, then starts a fresh buffer.
  Future<void> submit() async {
    if (!isAvailable) return;
    await flush();
    await _enqueue(() => _adapter!.submitText());
    _setState(KeyboardState.textSubmitted);
    // The TV usually moves on (search results, next field). Clear sensitive
    // text right away and start over for the next entry.
    _resetBuffers();
    notifyListeners();
  }

  /// The user dismissed the keyboard.
  Future<void> close() async {
    if (_mode == KeyboardSyncMode.live) await flush();
    _close();
  }

  void _close() {
    _batchTimer?.cancel();
    _resetBuffers();
    if (_adapter != null) _setState(KeyboardState.keyboardClosed);
  }

  void _scheduleFlush() {
    _batchTimer?.cancel();
    _batchTimer = Timer(batchDelay, () {
      _batchTimer = null;
      _enqueue(_sendDiff);
    });
  }

  Future<void> _sendDiff() async {
    final target = _local;
    final edit = TextEdit.between(_sent, target);
    if (edit.isEmpty) return;
    // Record the new state before sending: if the send partly fails, resending
    // the same edit could duplicate characters on append-only TVs.
    _sent = target;
    if (edit.deleteCount > 0) await _adapter!.deleteText(edit.deleteCount);
    if (edit.insert.isNotEmpty) await _adapter!.sendText(edit.insert);
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final adapter = _adapter;
    final next = _queue.then((_) async {
      if (adapter == null || !identical(adapter, _adapter)) return;
      try {
        await operation();
        if (_lastError != null) {
          _lastError = null;
          notifyListeners();
        }
      } on TvRemoteException catch (e) {
        _lastError = e;
        _outOfSync = true;
        notifyListeners();
      }
    });
    _queue = next;
    return next;
  }

  void _requireAvailable() {
    if (_adapter == null) throw const TvRemoteException.notConnected();
    if (!_capabilities.textInput) {
      throw const TvRemoteException.unsupported('Keyboard input');
    }
  }

  void _resetBuffers() {
    _batchTimer?.cancel();
    _batchTimer = null;
    _local = '';
    _sent = '';
    _sensitive = false;
    _outOfSync = false;
  }

  void _setState(KeyboardState state) {
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _batchTimer?.cancel();
    _resetBuffers();
    super.dispose();
  }
}
