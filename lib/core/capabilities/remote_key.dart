/// Protocol-neutral remote keys. Each adapter maps these to its own key codes
/// and reports which ones it supports through [DeviceCapabilities.keys].
enum RemoteKey {
  up,
  down,
  left,
  right,
  select,
  back,
  home,
  menu,
  info,
  power,
  powerOff,
  powerOn,
  volumeUp,
  volumeDown,
  mute,
  channelUp,
  channelDown,
  play,
  pause,
  playPause,
  stop,
  rewind,
  fastForward,
  replay,
  search,
  input,
  backspace,
  enter,
}

const navigationKeys = {
  RemoteKey.up,
  RemoteKey.down,
  RemoteKey.left,
  RemoteKey.right,
  RemoteKey.select,
};

const mediaKeys = {
  RemoteKey.play,
  RemoteKey.pause,
  RemoteKey.playPause,
  RemoteKey.stop,
  RemoteKey.rewind,
  RemoteKey.fastForward,
  RemoteKey.replay,
};

/// Keys that are safe to auto-repeat while held down.
const repeatableKeys = {
  RemoteKey.up,
  RemoteKey.down,
  RemoteKey.left,
  RemoteKey.right,
  RemoteKey.volumeUp,
  RemoteKey.volumeDown,
  RemoteKey.channelUp,
  RemoteKey.channelDown,
  RemoteKey.backspace,
};
