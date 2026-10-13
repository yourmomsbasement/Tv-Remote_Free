/// Streaming services the app knows how to open, with the names TVs use
/// for their apps.
enum StreamingService {
  youtube('YouTube', ['youtube.com', 'youtu.be'], rokuAppId: '837'),
  netflix('Netflix', ['netflix.com'], rokuAppId: '12'),
  primeVideo('Prime Video', ['primevideo.com', 'amazon.com'], rokuAppId: '13'),
  disneyPlus('Disney+', ['disneyplus.com'], rokuAppId: '291097'),
  hulu('Hulu', ['hulu.com'], rokuAppId: '2285'),
  max('Max', ['max.com', 'hbomax.com'], rokuAppId: '61322'),
  appleTv('Apple TV', ['tv.apple.com'], rokuAppId: '551012'),
  plex('Plex', ['plex.tv'], rokuAppId: '13535'),
  spotify('Spotify', ['spotify.com'], rokuAppId: '22297'),
  twitch('Twitch', ['twitch.tv']),
  other('Link', []);

  const StreamingService(this.displayName, this.domains, {this.rokuAppId});

  final String displayName;
  final List<String> domains;

  /// Roku channel id, used when the TV's app list cannot be read.
  final String? rokuAppId;

  static StreamingService forHost(String host) {
    final h = host.toLowerCase();
    for (final s in values) {
      if (s.domains.any((d) => h == d || h.endsWith('.$d'))) return s;
    }
    return other;
  }

  static String _normalize(String name) =>
      name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9+]'), '');

  /// Other names the same app goes by on some TVs.
  List<String> get _aliases => switch (this) {
    primeVideo => const ['amazonprimevideo', 'primevideo', 'amazon'],
    disneyPlus => const ['disneyplus'],
    max => const ['hbomax'],
    appleTv => const ['appletv+'],
    _ => const [],
  };

  /// Whether a TV app called [appName] is this service's app. Exact names
  /// only, so "YouTube Kids" is not mistaken for YouTube.
  bool matchesApp(String appName) {
    final n = _normalize(appName);
    return n == _normalize(displayName) || _aliases.contains(n);
  }
}

/// A movie, show or video link, as shared from a phone app.
class ContentLink {
  const ContentLink({required this.url, required this.service, this.contentId});

  final Uri url;
  final StreamingService service;

  /// The service's id for the item (YouTube video id, Netflix title id).
  final String? contentId;

  static final _urlPattern = RegExp(
    r'https?://[^\s<>"]+',
    caseSensitive: false,
  );

  /// Finds the first http(s) link in [text] (shared text often has a title
  /// around it). Returns null if there is none.
  static ContentLink? parse(String text) {
    final match = _urlPattern.firstMatch(text);
    if (match == null) return null;
    final raw = match[0]!.replaceAll(RegExp(r'[).,;!?]+$'), '');
    final url = Uri.tryParse(raw);
    if (url == null || url.host.isEmpty) return null;
    final service = StreamingService.forHost(url.host);
    return ContentLink(
      url: url,
      service: service,
      contentId: _contentId(service, url),
    );
  }

  static String? _contentId(StreamingService service, Uri url) {
    final segments = url.pathSegments.where((s) => s.isNotEmpty).toList();
    switch (service) {
      case StreamingService.youtube:
        if (url.host.toLowerCase().endsWith('youtu.be') &&
            segments.isNotEmpty) {
          return segments.first;
        }
        final v = url.queryParameters['v'];
        if (v != null && v.isNotEmpty) return v;
        final i = segments.indexWhere((s) => s == 'shorts' || s == 'live');
        return i >= 0 && i + 1 < segments.length ? segments[i + 1] : null;
      case StreamingService.netflix:
        final i = segments.indexWhere((s) => s == 'title' || s == 'watch');
        final id = i >= 0 && i + 1 < segments.length ? segments[i + 1] : null;
        return id != null && RegExp(r'^\d+$').hasMatch(id) ? id : null;
      default:
        return null;
    }
  }

  /// A title from shared text with the link removed, or a fallback.
  static String suggestTitle(String sharedText, ContentLink link) {
    final withoutUrl = sharedText
        .replaceAll(_urlPattern, ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'''^["'“”]+|["'“”:\-–—]+$'''), '')
        .trim();
    if (withoutUrl.isNotEmpty) {
      return withoutUrl.length > 80
          ? '${withoutUrl.substring(0, 80)}…'
          : withoutUrl;
    }
    return switch (link.service) {
      StreamingService.other => link.url.host,
      final s => '${s.displayName} ${link.contentId ?? 'link'}',
    };
  }
}
