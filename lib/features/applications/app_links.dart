import '../../core/adapter/smart_tv_adapter.dart';

/// Well-known app links for TVs that can open links but cannot list their
/// installed apps (Android TV). A link opens the app only if it is installed
/// and registered for that link.
const knownAppLinks = <TvApp>[
  TvApp(id: 'https://www.youtube.com', name: 'YouTube'),
  TvApp(id: 'https://www.netflix.com/title', name: 'Netflix'),
  TvApp(id: 'https://app.primevideo.com', name: 'Prime Video'),
  TvApp(id: 'https://www.disneyplus.com', name: 'Disney+'),
  TvApp(id: 'https://tv.apple.com', name: 'Apple TV'),
  TvApp(id: 'https://play.max.com', name: 'Max'),
  TvApp(id: 'https://www.hulu.com', name: 'Hulu'),
  TvApp(id: 'spotify://', name: 'Spotify'),
  TvApp(id: 'plex://', name: 'Plex'),
  TvApp(id: 'twitch://home', name: 'Twitch'),
];
