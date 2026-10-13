import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import 'macro.dart';

/// The user's saved macros.
class MacroLibrary extends AsyncNotifier<List<Macro>> {
  @override
  Future<List<Macro>> build() async {
    final rows = await ref.watch(deviceRepositoryProvider).listMacros();
    final macros = <Macro>[];
    for (final (id, json) in rows) {
      try {
        macros.add(Macro.decode(id, json));
      } on Object catch (e) {
        // Written by a newer app version; skip rather than fail the list.
        debugPrint('Skipping macro $id: $e');
      }
    }
    return macros;
  }

  static String newId() =>
      'macro-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}';

  Future<void> save(Macro macro) async {
    await ref
        .read(deviceRepositoryProvider)
        .saveMacro(macro.id, macro.encode());
    ref.invalidateSelf();
    await future;
  }

  Future<void> remove(Macro macro) async {
    await ref.read(deviceRepositoryProvider).deleteMacro(macro.id);
    ref.invalidateSelf();
    await future;
  }
}

final macroLibraryProvider = AsyncNotifierProvider<MacroLibrary, List<Macro>>(
  MacroLibrary.new,
);
