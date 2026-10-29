import 'dart:io';

const _relative = 'vendor/mac_os_testing/BrainAccessCore-4.0.0-macos/lib/libbacore.dylib';

/// Szuka biblioteki libbacore: wskazana sciezka, zmienna BACORE_LIB, pakiet
/// aplikacji (Frameworks), potem katalog vendor/ w drzewie projektu (w gore od
/// pliku wykonywalnego i od biezacego katalogu). Zwraca sciezke lub null.
String? findBacoreLib({
  String? override,
  Map<String, String>? environment,
  String? executable,
  String? cwd,
}) {
  bool ok(String? p) => p != null && p.isNotEmpty && File(p).existsSync();
  if (ok(override)) return override;
  final env = (environment ?? Platform.environment)['BACORE_LIB'];
  if (ok(env)) return env;

  final exe = executable ?? Platform.resolvedExecutable;
  final bundled = '${File(exe).parent.parent.path}/Frameworks/libbacore.dylib';
  if (ok(bundled)) return bundled;

  for (final start in [exe, cwd ?? Directory.current.path]) {
    var dir = FileSystemEntity.isDirectorySync(start) ? Directory(start) : File(start).parent;
    for (var i = 0; i < 10; i++) {
      final candidate = '${dir.path}/$_relative';
      if (File(candidate).existsSync()) return candidate;
      if (dir.parent.path == dir.path) break;
      dir = dir.parent;
    }
  }
  return null;
}
