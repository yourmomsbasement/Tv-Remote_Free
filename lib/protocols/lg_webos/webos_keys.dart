import '../../core/capabilities/remote_key.dart';

/// Button names accepted by the webOS pointer input socket.
const webOsButtonNames = <RemoteKey, String>{
  RemoteKey.up: 'UP',
  RemoteKey.down: 'DOWN',
  RemoteKey.left: 'LEFT',
  RemoteKey.right: 'RIGHT',
  RemoteKey.select: 'ENTER',
  RemoteKey.back: 'BACK',
  RemoteKey.home: 'HOME',
  RemoteKey.menu: 'MENU',
  RemoteKey.info: 'INFO',
  RemoteKey.volumeUp: 'VOLUMEUP',
  RemoteKey.volumeDown: 'VOLUMEDOWN',
  RemoteKey.mute: 'MUTE',
  RemoteKey.channelUp: 'CHANNELUP',
  RemoteKey.channelDown: 'CHANNELDOWN',
  RemoteKey.play: 'PLAY',
  RemoteKey.pause: 'PAUSE',
  RemoteKey.stop: 'STOP',
  RemoteKey.rewind: 'REWIND',
  RemoteKey.fastForward: 'FASTFORWARD',
  RemoteKey.input: 'INPUT_HUB',
};

/// Keys handled through SSAP requests rather than the pointer socket.
const webOsSsapKeys = <RemoteKey, String>{
  RemoteKey.powerOff: 'ssap://system/turnOff',
  RemoteKey.enter: 'ssap://com.webos.service.ime/sendEnterKey',
};

String webOsButtonMessage(String name) => 'type:button\nname:$name\n\n';

String webOsMoveMessage(int dx, int dy) =>
    'type:move\ndx:$dx\ndy:$dy\ndown:0\n\n';

const webOsClickMessage = 'type:click\n\n';

String webOsScrollMessage(int dx, int dy) => 'type:scroll\ndx:$dx\ndy:$dy\n\n';
