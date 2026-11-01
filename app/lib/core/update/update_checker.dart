import 'dart:convert';
import 'dart:io';

/// Pobiera tresc odpowiedzi GET; rzuca wyjatek przy kodzie innym niz 200.
typedef UpdateFetch = Future<String> Function(
  Uri url,
  Map<String, String> headers,
);

class UpdateInfo {
  const UpdateInfo({
    required this.tag,
    required this.version,
    required this.pageUrl,
    this.assetUrl,
    this.notes = '',
  });

  final String tag;
  final String version;

  /// Strona wydania na GitHubie.
  final String pageUrl;

  /// Bezposredni plik dla tej platformy (dziala dla publicznego repozytorium).
  final String? assetUrl;
  final String notes;
}

/// Czesci liczbowe wersji z tagu, np. "v0.1.2+3" -> [0, 1, 2].
List<int> parseVersion(String v) {
  final core = v
      .trim()
      .replaceFirst(RegExp('^[vV]'), '')
      .split(RegExp('[+-]'))
      .first;
  return [for (final p in core.split('.')) int.tryParse(p) ?? 0];
}

bool isNewerVersion(String candidate, String current) {
  final a = parseVersion(candidate);
  final b = parseVersion(current);
  for (var i = 0; i < (a.length > b.length ? a.length : b.length); i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

/// Sprawdza najnowsze wydanie na GitHubie. Repozytorium prywatne wymaga tokena
/// z prawem odczytu; bez niego odpowiedz to 404 i sprawdzenie sie nie udaje.
class UpdateChecker {
  UpdateChecker({
    required this.currentVersion,
    required this.fetch,
    this.repo = 'GrzegorzSzczepanek/in-ynierka',
    this.token = '',
    this.platform,
  });

  final String currentVersion;
  final UpdateFetch fetch;
  final String repo;
  final String token;

  /// "android" lub "macos"; wybiera plik wydania. Domyslnie z systemu.
  final String? platform;

  /// Nowsze wydanie albo null, gdy aplikacja jest aktualna.
  Future<UpdateInfo?> check() async {
    final body = await fetch(
      Uri.https('api.github.com', '/repos/$repo/releases/latest'),
      {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'neurotchi-app',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
    );
    final json = jsonDecode(body) as Map<String, dynamic>;
    if (json['draft'] == true || json['prerelease'] == true) return null;
    final tag = json['tag_name'] as String? ?? '';
    if (tag.isEmpty || !isNewerVersion(tag, currentVersion)) return null;
    final want = platform ?? (Platform.isAndroid ? 'android' : 'macos');
    String? asset;
    for (final a in (json['assets'] as List? ?? const [])) {
      final name = (a as Map)['name'] as String? ?? '';
      if (name.toLowerCase().contains(want))
        asset = a['browser_download_url'] as String?;
    }
    return UpdateInfo(
      tag: tag,
      version: tag.replaceFirst(RegExp('^[vV]'), ''),
      pageUrl:
          json['html_url'] as String? ??
          'https://github.com/$repo/releases/latest',
      assetUrl: asset,
      notes: json['body'] as String? ?? '',
    );
  }
}

/// Prawdziwy GET przez dart:io z limitem czasu.
Future<String> httpFetch(Uri url, Map<String, String> headers) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final req = await client.getUrl(url).timeout(const Duration(seconds: 8));
    headers.forEach(req.headers.set);
    final res = await req.close().timeout(const Duration(seconds: 8));
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) {
      throw HttpException('GitHub odpowiedział ${res.statusCode}', uri: url);
    }
    return text;
  } finally {
    client.close(force: true);
  }
}
