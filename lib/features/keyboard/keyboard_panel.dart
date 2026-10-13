import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/capabilities/device_capabilities.dart';
import '../../core/capabilities/remote_key.dart';
import '../../core/platform/haptics.dart';
import '../../ui/components/remote_button.dart';
import '../remote/remote_session.dart';
import '../settings/app_settings.dart';
import 'keyboard_controller.dart';
import 'search_history.dart';

/// TV text fields are single-line: line breaks in pasted text become
/// spaces rather than reaching the TV as Enter presses.
String singleLineForTv(String text) =>
    text.replaceAll(RegExp(r'[ \t]*[\r\n]+[ \t]*'), ' ').trim();

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

  /// Submits and, for non-password text, remembers it in search history.
  Future<void> _submit() async {
    final hidden = _hideText;
    final submitted = await _keyboard.submit();
    if (submitted != null && !hidden) {
      await ref.read(searchHistoryProvider.notifier).record(submitted);
    }
  }

  /// Types a remembered entry into the TV field.
  Future<void> _useHistory(String entry) async {
    if (!_keyboard.isAvailable) return;
    if (_keyboard.state != KeyboardState.textEditing &&
        _keyboard.state != KeyboardState.keyboardActive &&
        _keyboard.state != KeyboardState.textFieldDetected) {
      _keyboard.open();
    }
    _keyboard.updateText(entry);
    await _keyboard.flush();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final pasted = data?.text == null ? null : singleLineForTv(data!.text!);
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
    final history = ref.watch(searchHistoryProvider).value ?? const [];
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
            _submit();
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
        if (!hidden && history.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Recent', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final entry in history.take(8))
                InputChip(
                  label: Text(entry, overflow: TextOverflow.ellipsis),
                  tooltip: 'Type "$entry" on the TV',
                  onPressed: available
                      ? _withHaptic(() => _useHistory(entry))
                      : null,
                  deleteButtonTooltipMessage: 'Remove from history',
                  onDeleted: () =>
                      ref.read(searchHistoryProvider.notifier).remove(entry),
                ),
            ],
          ),
        ],
        if (session.capabilities.navigation) ...[
          const SizedBox(height: 12),
          _ArrowRow(enabled: session.isConnected),
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
              onPressed: available ? _withHaptic(_submit) : null,
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

/// Arrow keys on the keyboard screen, so moving between TV fields or
/// results does not mean leaving the keyboard.
class _ArrowRow extends ConsumerWidget {
  const _ArrowRow({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remote = ref.read(remoteSessionProvider.notifier);
    final haptics = ref.watch(settingsProvider.select((s) => s.hapticStrength));
    final caps = ref.watch(remoteSessionProvider.select((s) => s.capabilities));
    Widget key(
      RemoteKey k,
      IconData icon,
      String label, {
      bool repeat = true,
    }) => RemoteButton(
      icon: icon,
      label: label,
      size: 44,
      repeat: repeat,
      haptics: haptics,
      onPressed: enabled ? () => remote.sendKey(k) : null,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        if (caps.supportsKey(RemoteKey.back))
          key(RemoteKey.back, Icons.arrow_back, 'Back', repeat: false),
        key(RemoteKey.left, Icons.keyboard_arrow_left, 'Left'),
        key(RemoteKey.up, Icons.keyboard_arrow_up, 'Up'),
        key(RemoteKey.down, Icons.keyboard_arrow_down, 'Down'),
        key(RemoteKey.right, Icons.keyboard_arrow_right, 'Right'),
        key(RemoteKey.select, Icons.radio_button_checked, 'OK', repeat: false),
      ],
    );
  }
}
