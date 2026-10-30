import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neurotchi/core/update/update_checker.dart';

String release({String tag = 'v0.2.0', bool draft = false, bool pre = false}) => jsonEncode({
      'tag_name': tag,
      'draft': draft,
      'prerelease': pre,
      'html_url': 'https://github.com/x/y/releases/tag/$tag',
      'body': 'zmiany',
      'assets': [
        {'name': 'neurotchi-android.apk', 'browser_download_url': 'https://dl/android.apk'},
        {'name': 'neurotchi-macos.zip', 'browser_download_url': 'https://dl/macos.zip'},
      ],
    });

void main() {
  test('porownanie wersji', () {
    expect(isNewerVersion('v0.1.1', '0.1.0'), isTrue);
    expect(isNewerVersion('v0.1.0', '0.1.0+5'), isFalse);
    expect(isNewerVersion('v1.0', '0.9.9'), isTrue);
    expect(isNewerVersion('v0.10.0', '0.9.0'), isTrue);
    expect(isNewerVersion('v0.1.0', '0.1.1'), isFalse);
    expect(parseVersion('v2.3.4-rc1'), [2, 3, 4]);
  });

  test('nowsze wydanie: plik dla platformy i token w naglowku', () async {
    Map<String, String>? seen;
    Uri? url;
    final checker = UpdateChecker(
      currentVersion: '0.1.0',
      token: 'tok',
      platform: 'android',
      fetch: (u, h) async {
        url = u;
        seen = h;
        return release();
      },
    );
    final info = await checker.check();
    expect(info!.version, '0.2.0');
    expect(info.assetUrl, 'https://dl/android.apk');
    expect(info.pageUrl, contains('/releases/tag/v0.2.0'));
    expect(url.toString(), 'https://api.github.com/repos/GrzegorzSzczepanek/in-ynierka/releases/latest');
    expect(seen!['Authorization'], 'Bearer tok');
  });

  test('aktualna wersja, szkic i prerelease dają null, blad sieci wyjatek', () async {
    Future<UpdateInfo?> run(String body) =>
        UpdateChecker(currentVersion: '0.2.0', platform: 'macos', fetch: (_, _) async => body).check();
    expect(await run(release(tag: 'v0.2.0')), isNull);
    expect(await run(release(tag: 'v0.3.0', draft: true)), isNull);
    expect(await run(release(tag: 'v0.3.0', pre: true)), isNull);
    expect(
      UpdateChecker(currentVersion: '0.2.0', fetch: (_, _) async => throw Exception('offline')).check(),
      throwsException,
    );
  });
}
