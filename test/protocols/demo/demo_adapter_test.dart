import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote_free/core/adapter/smart_tv_adapter.dart';
import 'package:tv_remote_free/core/capabilities/remote_key.dart';
import 'package:tv_remote_free/protocols/demo/demo_adapter.dart';

void main() {
  test('demo TV simulates apps, playback, volume and text fields', () async {
    final tv = DemoAdapter(latency: Duration.zero);
    final events = <DeviceEvent>[];
    tv.events.listen(events.add);
    await tv.connect();
    expect(tv.status, ConnectionStatus.connected);
    final caps = await tv.getCapabilities();
    expect(caps.navigation && caps.textInput && caps.appLaunch, isTrue);

    expect(await tv.listApps(), isNotEmpty);
    await tv.launchApp('demo.movies');
    await tv.sendKey(RemoteKey.playPause);
    await tv.sendKey(RemoteKey.volumeUp);
    await tv.sendKey(RemoteKey.search);
    await tv.sendText('hello');
    await tv.submitText();
    await Future<void>.delayed(Duration.zero);

    final activity = events.whereType<ActivityChanged>().last.activity;
    expect(activity.appName, 'Movies');
    expect(activity.state, PlaybackState.paused);
    expect(events.whereType<VolumeChanged>().last.level, 16);
    expect(events.whereType<TextFieldFocusChanged>().map((e) => e.focused), [
      true,
      false,
    ]);
    await tv.disconnect();
  });
}
