/// Registration manifest sent to the TV. The permissions are what the TV
/// lists on its "allow this device?" prompt.
const webOsPermissions = [
  'APP_TO_APP',
  'CLOSE',
  'CONTROL_AUDIO',
  'CONTROL_DISPLAY',
  'CONTROL_INPUT_JOYSTICK',
  'CONTROL_INPUT_MEDIA_PLAYBACK',
  'CONTROL_INPUT_MEDIA_RECORDING',
  'CONTROL_INPUT_TEXT',
  'CONTROL_INPUT_TV',
  'CONTROL_MOUSE_AND_KEYBOARD',
  'CONTROL_POWER',
  'LAUNCH',
  'LAUNCH_WEBAPP',
  'READ_APP_STATUS',
  'READ_CURRENT_CHANNEL',
  'READ_INPUT_DEVICE_LIST',
  'READ_INSTALLED_APPS',
  'READ_NETWORK_STATE',
  'READ_POWER_STATE',
  'READ_RUNNING_APPS',
  'READ_TV_CHANNEL_LIST',
];

Map<String, Object?> webOsRegisterPayload({String? clientKey}) => {
  'forcePairing': false,
  'pairingType': 'PROMPT',
  'client-key': ?clientKey,
  'manifest': {
    'manifestVersion': 1,
    'appVersion': '1.0',
    'permissions': webOsPermissions,
  },
};
