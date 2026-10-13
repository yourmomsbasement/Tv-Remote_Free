import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'remote_session.dart';

/// Asks for the pairing code the TV is displaying.
class PinDialog extends ConsumerStatefulWidget {
  const PinDialog({super.key});

  @override
  ConsumerState<PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends ConsumerState<PinDialog> {
  final _pin = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await ref
        .read(remoteSessionProvider.notifier)
        .submitPin(_pin.text);
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context);
    } else {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Close if pairing ends some other way (cancelled on the TV, timeout).
    ref.listen(remoteSessionProvider.select((s) => s.awaitingPin), (
      _,
      awaiting,
    ) {
      if (!awaiting && mounted) Navigator.maybePop(context);
    });
    return AlertDialog(
      title: const Text('Pair with TV'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Type the 6-character code shown on the TV screen.'),
          const SizedBox(height: 16),
          TextField(
            controller: _pin,
            autofocus: true,
            maxLength: 6,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(
              fontSize: 28,
              letterSpacing: 8,
              fontFamily: 'monospace',
            ),
            textAlign: TextAlign.center,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
              TextInputFormatter.withFunction(
                (_, value) => value.copyWith(text: value.text.toUpperCase()),
              ),
            ],
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              errorText: _error,
              errorMaxLines: 3,
            ),
            onChanged: (v) {
              if (v.length == 6 && !_busy) _submit();
            },
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            ref.read(remoteSessionProvider.notifier).disconnect();
            Navigator.pop(context);
          },
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Pair'),
        ),
      ],
    );
  }
}
