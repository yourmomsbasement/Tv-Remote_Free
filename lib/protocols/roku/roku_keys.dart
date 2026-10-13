import '../../core/capabilities/remote_key.dart';

/// ECP key names. Volume, power and channel keys only work on Roku TVs.
const rokuKeyNames = <RemoteKey, String>{
  RemoteKey.up: 'Up',
  RemoteKey.down: 'Down',
  RemoteKey.left: 'Left',
  RemoteKey.right: 'Right',
  RemoteKey.select: 'Select',
  RemoteKey.back: 'Back',
  RemoteKey.home: 'Home',
  RemoteKey.info: 'Info',
  RemoteKey.playPause: 'Play',
  RemoteKey.rewind: 'Rev',
  RemoteKey.fastForward: 'Fwd',
  RemoteKey.replay: 'InstantReplay',
  RemoteKey.search: 'Search',
  RemoteKey.backspace: 'Backspace',
  RemoteKey.enter: 'Enter',
  RemoteKey.power: 'Power',
  RemoteKey.powerOff: 'PowerOff',
  RemoteKey.powerOn: 'PowerOn',
  RemoteKey.volumeUp: 'VolumeUp',
  RemoteKey.volumeDown: 'VolumeDown',
  RemoteKey.mute: 'VolumeMute',
  RemoteKey.channelUp: 'ChannelUp',
  RemoteKey.channelDown: 'ChannelDown',
};

const rokuTvOnlyKeys = {
  RemoteKey.power,
  RemoteKey.volumeUp,
  RemoteKey.volumeDown,
  RemoteKey.mute,
  RemoteKey.channelUp,
  RemoteKey.channelDown,
};

const rokuPowerKeys = {RemoteKey.powerOff, RemoteKey.powerOn};

/// ECP literal for one Unicode character: `Lit_` + URL-encoded UTF-8.
String rokuLiteral(String character) => 'Lit_${Uri.encodeComponent(character)}';
