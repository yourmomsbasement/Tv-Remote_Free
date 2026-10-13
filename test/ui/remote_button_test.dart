import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote_free/core/platform/haptics.dart';
import 'package:tv_remote_free/ui/components/remote_button.dart';

void main() {
  late List<String> haptics;

  setUp(() {
    haptics = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(
              (call.arguments as String?)?.split('.').last ?? 'vibrate',
            );
          }
          return null;
        });
  });

  Future<int> pumpButton(
    WidgetTester tester, {
    bool repeat = false,
    HapticStrength strength = HapticStrength.medium,
  }) async {
    var presses = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RemoteButton(
              icon: Icons.keyboard_arrow_up,
              label: 'Up',
              repeat: repeat,
              haptics: strength,
              onPressed: () => presses++,
            ),
          ),
        ),
      ),
    );
    return presses;
  }

  testWidgets('a tap vibrates once and presses once', (tester) async {
    var presses = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RemoteButton(
            icon: Icons.home,
            label: 'Home',
            onPressed: () => presses++,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(RemoteButton));
    await tester.pump();
    expect(presses, 1);
    expect(haptics, ['lightImpact']);
  });

  testWidgets('holding gives a strong pulse, then a tick per repeat, '
      'and releasing does not add an extra press', (tester) async {
    var presses = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RemoteButton(
            icon: Icons.keyboard_arrow_up,
            label: 'Up',
            repeat: true,
            onPressed: () => presses++,
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(RemoteButton)),
    );
    await tester.pump(const Duration(milliseconds: 360)); // hold engages
    await tester.pump(const Duration(milliseconds: 150)); // repeat 1
    await tester.pump(const Duration(milliseconds: 150)); // repeat 2
    await gesture.up();
    await tester.pump(const Duration(seconds: 1));
    expect(presses, 3);
    expect(haptics, ['heavyImpact', 'selectionClick', 'selectionClick']);
  });

  testWidgets('a quick tap on a repeating button is a single press', (
    tester,
  ) async {
    await pumpButton(tester, repeat: true);
    await tester.tap(find.byType(RemoteButton));
    await tester.pump(const Duration(seconds: 1));
    expect(haptics, ['lightImpact']);
  });

  testWidgets('strength off means no vibration', (tester) async {
    await pumpButton(tester, strength: HapticStrength.off);
    await tester.tap(find.byType(RemoteButton));
    await tester.pump();
    expect(haptics, isEmpty);
  });

  test('stronger settings never feel weaker', () {
    for (final event in HapticEvent.values) {
      final levels = [
        for (final s in [
          HapticStrength.light,
          HapticStrength.medium,
          HapticStrength.strong,
        ])
          Haptics.effectFor(event, s)!.index,
      ];
      expect(levels, orderedEquals([...levels]..sort()));
    }
    // A hold always feels at least as strong as a tap.
    for (final s in HapticStrength.values.skip(1)) {
      expect(
        Haptics.effectFor(HapticEvent.hold, s)!.index,
        greaterThanOrEqualTo(Haptics.effectFor(HapticEvent.press, s)!.index),
      );
    }
  });
}
