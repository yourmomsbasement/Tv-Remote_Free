import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote_free/core/adapter/smart_tv_adapter.dart';
import 'package:tv_remote_free/core/capabilities/device_capabilities.dart';
import 'package:tv_remote_free/core/errors.dart';
import 'package:tv_remote_free/features/keyboard/keyboard_controller.dart';

import '../support/fake_adapter.dart';

void main() {
  late FakeAdapter tv;
  late KeyboardController keyboard;

  // Futures created outside a fakeAsync zone complete on the real event loop,
  // so timing tests build their controller inside the zone.
  KeyboardController newKeyboard() =>
      KeyboardController(batchDelay: const Duration(milliseconds: 40))
        ..attach(tv, tv.capabilities);

  setUp(() {
    tv = FakeAdapter();
    keyboard = newKeyboard();
  });

  tearDown(() => keyboard.dispose());

  test('starts connected and becomes active when opened manually', () {
    expect(keyboard.state, KeyboardState.connected);
    keyboard.open();
    expect(keyboard.state, KeyboardState.keyboardActive);
  });

  test('batches keystrokes typed within the window into one send', () {
    fakeAsync((async) {
      keyboard = newKeyboard();
      keyboard.open();
      for (final t in ['h', 'he', 'hel', 'hell', 'hello']) {
        keyboard.updateText(t);
        async.elapse(const Duration(milliseconds: 10));
      }
      async.elapse(const Duration(milliseconds: 100));
      expect(tv.calls, ['text:hello']);
      expect(keyboard.state, KeyboardState.textEditing);
    });
  });

  test('never duplicates text on an append-only TV', () {
    fakeAsync((async) {
      keyboard = newKeyboard();
      keyboard.open();
      keyboard.updateText('net');
      async.elapse(const Duration(milliseconds: 50));
      keyboard.updateText('netflix');
      async.elapse(const Duration(milliseconds: 50));
      keyboard.updateText('netfli');
      async.elapse(const Duration(milliseconds: 50));
      keyboard.updateText('netflip');
      async.elapse(const Duration(milliseconds: 50));
      expect(tv.tvText, 'netflip');
      expect(tv.calls, ['text:net', 'text:flix', 'delete:1', 'text:p']);
    });
  });

  test('editing in the middle rewrites only the changed tail', () {
    fakeAsync((async) {
      keyboard = newKeyboard();
      keyboard.open();
      keyboard.updateText('the cat sat');
      async.elapse(const Duration(milliseconds: 50));
      keyboard.updateText('the cot sat');
      async.elapse(const Duration(milliseconds: 50));
      expect(tv.tvText, 'the cot sat');
      expect(tv.calls.last, 'text:ot sat');
    });
  });

  test('backspace with an empty buffer deletes existing TV text', () async {
    tv.tvText = 'old';
    keyboard.open();
    await keyboard.backspace();
    expect(tv.calls, ['delete:1']);
    expect(tv.tvText, 'ol');
  });

  test('backspace with typed text removes the last character', () async {
    keyboard.open();
    keyboard.updateText('ab😀');
    await keyboard.flush();
    await keyboard.backspace();
    expect(keyboard.text, 'ab');
    expect(tv.tvText, 'ab');
  });

  test(
    'submit flushes pending text, sends enter, and clears buffers',
    () async {
      keyboard.open();
      keyboard.updateText('news');
      await keyboard.submit();
      expect(tv.calls, ['text:news', 'submit']);
      expect(keyboard.state, KeyboardState.textSubmitted);
      expect(keyboard.text, isEmpty);
      // The next entry starts fresh rather than diffing against "news".
      keyboard.updateText('x');
      await keyboard.flush();
      expect(tv.calls.last, 'text:x');
    },
  );

  test('manual mode holds text until Send', () {
    fakeAsync((async) {
      keyboard = newKeyboard();
      keyboard
        ..mode = KeyboardSyncMode.manual
        ..open()
        ..updateText('hello');
      async.elapse(const Duration(seconds: 1));
      expect(tv.calls, isEmpty);
      expect(keyboard.hasPendingText, isTrue);
      keyboard.flush();
      async.flushMicrotasks();
      expect(tv.calls, ['text:hello']);
    });
  });

  test('clear removes everything this session typed', () async {
    keyboard.open();
    keyboard.updateText('abc');
    await keyboard.flush();
    await keyboard.clear();
    expect(tv.tvText, isEmpty);
    expect(tv.calls.last, 'delete:3');
  });

  test('TV focus events drive the state machine and mark sensitivity', () {
    keyboard.onTextFieldFocus(
      const TextFieldFocusChanged(focused: true, sensitive: true),
    );
    expect(keyboard.state, KeyboardState.textFieldDetected);
    expect(keyboard.sensitive, isTrue);
    keyboard.open();
    expect(keyboard.state, KeyboardState.keyboardActive);
    keyboard.updateText('hunter2');
    keyboard.onTextFieldFocus(const TextFieldFocusChanged(focused: false));
    expect(keyboard.state, KeyboardState.keyboardClosed);
    // Sensitive text is not retained after the session closes.
    expect(keyboard.text, isEmpty);
    expect(keyboard.sensitive, isFalse);
  });

  test('a failed send is reported and marks the field out of sync', () async {
    keyboard.open();
    tv.failNext = const TvRemoteException(TvErrorCode.unreachable, 'gone');
    keyboard.updateText('abc');
    await keyboard.flush();
    expect(keyboard.lastError?.code, TvErrorCode.unreachable);
    expect(keyboard.outOfSync, isTrue);
    // A later edit does not resend "abc".
    keyboard.updateText('abcd');
    await keyboard.flush();
    expect(tv.calls, ['text:d']);
  });

  test('detach clears state and blocks further sends', () async {
    keyboard.open();
    keyboard.updateText('abc');
    keyboard.detach();
    expect(keyboard.state, KeyboardState.disconnected);
    expect(keyboard.text, isEmpty);
    await keyboard.flush();
    expect(tv.calls, isEmpty);
  });

  test('refuses to open on TVs without text input', () {
    keyboard.attach(tv, const DeviceCapabilities(keys: {}));
    expect(keyboard.isAvailable, isFalse);
    expect(
      () => keyboard.open(),
      throwsA(
        isA<TvRemoteException>().having(
          (e) => e.code,
          'code',
          TvErrorCode.unsupported,
        ),
      ),
    );
  });
}
