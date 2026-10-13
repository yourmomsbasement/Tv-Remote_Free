import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/capabilities/device_capabilities.dart';
import '../../core/platform/haptics.dart';
import '../remote/remote_session.dart';
import '../settings/app_settings.dart';
import 'keyboard_controller.dart';

/// Phone-keyboard text entry for the TV's focused text field.
class KeyboardPanel extends ConsumerStatefulWidget {
  const KeyboardPanel({super.key, this.focusNode});

  final FocusNode? focusNode;

  @override
  ConsumerState<KeyboardPanel> createState() => _KeyboardPanelState();
}

class _KeyboardPanelState extends ConsumerState<KeyboardPanel> {
  final _text = TextEditingController();
  late final FocusNode _focus = widget.focusNode ?? FocusNode();
  late final KeyboardController _keyboard = ref
      .read(remoteSessionProvider.notifier)
      .keyboard;
  bool _hideText = false;

  @override
  void initState() {
    super.initState();
    _keyboard.addListener(_syncFromController);
  }

  /// The controller clears its buffer on submit, focus changes and
  /// disconnects; mirror that in the text field.
  void _syncFromController() {
    if (!mounted) return;
    if (_text.text != _keyboard.text) {
      _text.value = TextEditingValue(
        text: _keyboard.text,
        selection: TextSelection.collapsed(offset: _keyboard.text.length),
      );
    }
    setState(() {});
  }

  @override
  void dispose() {
    _keyboard.removeListener(_syncFromController);
    if (widget.focusNode == null) _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    final batch = ref.read(settingsProvider).keyboardBatchMs;
    _keyboard.batchDelay = Duration(milliseconds: batch);
    if (_keyboard.state == KeyboardState.connected ||
        _keyboard.state == KeyboardState.keyboardClosed ||
        _keyboard.state == KeyboardState.textSubmitted) {
      _keyboard.open(sensitive: _hideText);
    }
    _keyboard.updateText(value);
  }

  /// Wraps a button action with press feedback.
  VoidCallback _withHaptic(void Function() action) => () {
    Haptics.play(HapticEvent.press, ref.read(settingsProvider).hapticStrength);
    action();
  };

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final pasted = data?.text;
    if (pasted == null || pasted.isEmpty) return;
    final value = _text.text + pasted;
    _text.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _onChanged(value);
  }

  String _statusText(RemoteSessionState session) {
    if (!session.isConnected) return 'Not connected';
    if (!_keyboard.isAvailable) {
      return 'This TV does not accept text from the phone. Use the arrow keys '
          'on the TV\'s on-screen keyboard instead.';
    }
    if (_keyboard.detectsTextFields) {
      return session.textFieldFocused
          ? 'TV text field selected — type below'
          : 'Select a text field on the TV, or type below to send anyway';
    }
    return 'Open a search or text field on the TV, then type below. This TV '
        'does not report when a text field is selected.';
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(remoteSessionProvider);
    final scheme = Theme.of(context).colorScheme;
    final available = session.isConnected && _keyboard.isAvailable;
    final live = _keyboard.mode == KeyboardSyncMode.live;
    final hidden = _hideText || _keyboard.sensitive;
    final appendOnly =
        session.capabilities.textInputStrategy ==
        TextInputStrategy.characterEvents;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Icon(
              session.textFieldFocused
                  ? Icons.keyboard
                  : Icons.keyboard_outlined,
              color: session.textFieldFocused ? scheme.primary : null,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(_statusText(session))),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _text,
          focusNode: _focus,
          enabled: available,
          autofocus: available,
          obscureText: hidden,
          enableSuggestions: !hidden,
          autocorrect: false,
          // Autocorrect rewrites earlier words, which append-only TVs can only
          // apply by deleting and retyping; keep it off.
          enableIMEPersonalizedLearning: !hidden,
          keyboardType: hidden
              ? TextInputType.visiblePassword
              : TextInputType.text,
          textInputAction: TextInputAction.send,
          onChanged: _onChanged,
          onSubmitted: (_) {
            _keyboard.submit();
            _focus.requestFocus();
          },
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: 'Text for TV',
            helperText: live
                ? (appendOnly
                      ? 'Sent as you type. Edits are applied by deleting from '
                            'the end on the TV.'
                      : 'Sent as you type')
                : 'Press Send to type this on the TV',
            suffixIcon: IconButton(
              tooltip: hidden ? 'Show text' : 'Hide text (password)',
              icon: Icon(hidden ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _hideText = !_hideText),
            ),
          ),
        ),
        if (_keyboard.lastError != null || _keyboard.outOfSync) ...[
          const SizedBox(height: 8),
          Text(
            _keyboard.lastError?.message ??
                'The TV text may not match the phone. Use Clear to reset.',
            style: TextStyle(color: scheme.error),
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: available ? _withHaptic(_keyboard.backspace) : null,
              icon: const Icon(Icons.backspace_outlined),
              label: const Text('Delete'),
            ),
            OutlinedButton.icon(
              onPressed: available ? _withHaptic(_keyboard.clear) : null,
              icon: const Icon(Icons.clear_all),
              label: const Text('Clear'),
            ),
            OutlinedButton.icon(
              onPressed: available ? _withHaptic(_paste) : null,
              icon: const Icon(Icons.content_paste),
              label: const Text('Paste'),
            ),
            if (!live)
              FilledButton.tonalIcon(
                onPressed: available && _keyboard.hasPendingText
                    ? _withHaptic(_keyboard.flush)
                    : null,
                icon: const Icon(Icons.send),
                label: const Text('Send'),
              ),
            FilledButton.icon(
              onPressed: available ? _withHaptic(_keyboard.submit) : null,
              icon: const Icon(Icons.keyboard_return),
              label: const Text('Enter'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SegmentedButton<KeyboardSyncMode>(
          segments: const [
            ButtonSegment(
              value: KeyboardSyncMode.live,
              label: Text('Live typing'),
              icon: Icon(Icons.bolt),
            ),
            ButtonSegment(
              value: KeyboardSyncMode.manual,
              label: Text('Send manually'),
              icon: Icon(Icons.send_outlined),
            ),
          ],
          selected: {_keyboard.mode},
          onSelectionChanged: available
              ? (s) => setState(() => _keyboard.mode = s.first)
              : null,
        ),
      ],
    );
  }
}
