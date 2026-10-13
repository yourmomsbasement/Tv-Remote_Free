import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote_free/core/content/content_link.dart';

void main() {
  test('recognises YouTube links in all their shapes', () {
    for (final url in [
      'https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42',
      'https://youtu.be/dQw4w9WgXcQ?si=abc',
      'https://m.youtube.com/shorts/dQw4w9WgXcQ',
    ]) {
      final link = ContentLink.parse(url)!;
      expect(link.service, StreamingService.youtube, reason: url);
      expect(link.contentId, 'dQw4w9WgXcQ', reason: url);
    }
  });

  test('recognises Netflix titles and other services', () {
    final netflix = ContentLink.parse(
      'https://www.netflix.com/title/80057281',
    )!;
    expect(netflix.service, StreamingService.netflix);
    expect(netflix.contentId, '80057281');
    expect(
      ContentLink.parse('https://www.disneyplus.com/video/abc')!.service,
      StreamingService.disneyPlus,
    );
    expect(
      ContentLink.parse('https://example.com/x')!.service,
      StreamingService.other,
    );
  });

  test('finds the link inside shared text and suggests a title', () {
    const shared =
        'Watch "Stranger Things" on Netflix: '
        'https://www.netflix.com/title/80057281.';
    final link = ContentLink.parse(shared)!;
    expect(link.url.toString(), 'https://www.netflix.com/title/80057281');
    expect(
      ContentLink.suggestTitle(shared, link),
      'Watch "Stranger Things" on Netflix',
    );
    expect(
      ContentLink.suggestTitle(link.url.toString(), link),
      'Netflix 80057281',
    );
    expect(ContentLink.parse('no links here'), isNull);
  });

  test('matches TV app names to services', () {
    expect(StreamingService.youtube.matchesApp('YouTube'), isTrue);
    expect(StreamingService.youtube.matchesApp('YouTube Kids'), isFalse);
    expect(StreamingService.disneyPlus.matchesApp('Disney+'), isTrue);
    expect(StreamingService.primeVideo.matchesApp('Prime Video'), isTrue);
    expect(StreamingService.netflix.matchesApp('Hulu'), isFalse);
  });
}
