import 'package:flutter/material.dart';

/// The privacy policy, available inside the app (App Store guideline
/// 5.1.1 requires it to be easy to find). Mirrors docs/PRIVACY.md.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static const policyUrl =
      'https://github.com/yourmomsbasement/Tv-Remote_Free/blob/master/docs/PRIVACY.md';

  static const _sections = <(String, String)>[
    (
      'What we collect',
      'Nothing. The app has no accounts, analytics, advertising or tracking, '
          'and sends no information to the developers or any third party.',
    ),
    (
      'What stays on your phone',
      'Your TVs (name, model, network address and, where reported, hardware '
          'address for Wake-on-LAN); pairing keys in the phone\'s secure '
          'storage; your settings, themes, layouts, macros, watchlist and '
          'profiles (the PIN only as a one-way hash); optionally recent '
          'keyboard searches (never password fields); and app icons from your '
          'TVs. Delete any of it in the app or by uninstalling.',
    ),
    (
      'Network use',
      'The app only talks to TVs on your local network using their own '
          'remote-control protocols. Text you type is sent to your TV. The app '
          'does not contact the internet.',
    ),
    (
      'Permissions',
      'Local network access finds and controls your TVs; vibration gives '
          'button feedback. Files are read or written only when you import or '
          'export.',
    ),
    (
      'Children',
      'The app is not directed at children and collects no data from anyone.',
    ),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Privacy')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final (title, body) in _sections) ...[
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(body),
          const SizedBox(height: 16),
        ],
        const SelectableText('Full policy: $policyUrl'),
      ],
    ),
  );
}
