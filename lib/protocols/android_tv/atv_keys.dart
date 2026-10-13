import '../../core/capabilities/remote_key.dart';

/// Android KeyEvent key codes used by the remote protocol.
const androidKeyCodes = <RemoteKey, int>{
  RemoteKey.home: 3,
  RemoteKey.back: 4,
  RemoteKey.up: 19,
  RemoteKey.down: 20,
  RemoteKey.left: 21,
  RemoteKey.right: 22,
  RemoteKey.select: 23,
  RemoteKey.volumeUp: 24,
  RemoteKey.volumeDown: 25,
  RemoteKey.power: 26,
  RemoteKey.enter: 66,
  RemoteKey.backspace: 67,
  RemoteKey.menu: 82,
  RemoteKey.search: 84,
  RemoteKey.playPause: 85,
  RemoteKey.stop: 86,
  RemoteKey.rewind: 89,
  RemoteKey.fastForward: 90,
  RemoteKey.play: 126,
  RemoteKey.pause: 127,
  RemoteKey.mute: 164,
  RemoteKey.info: 165,
  RemoteKey.channelUp: 166,
  RemoteKey.channelDown: 167,
  RemoteKey.input: 178,
  RemoteKey.powerOff: 223, // KEYCODE_SLEEP
  RemoteKey.powerOn: 224, // KEYCODE_WAKEUP
};
