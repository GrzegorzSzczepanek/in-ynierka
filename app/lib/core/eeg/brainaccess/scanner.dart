import 'dart:io' show Platform;
import 'dart:isolate';

import 'bacore.dart';
import 'brainaccess_android_source.dart';

/// Wyszukiwanie czepkow BrainAccess w zasiegu BLE (w osobnym izolacie, bo skan blokuje).
class BrainAccessScanner {
  static Future<List<String>> scan(String libPath) => Isolate.run(() {
    final core = BaCore.open(libPath);
    core.coreInit();
    try {
      return core.scanNames();
    } finally {
      core.coreClose();
    }
  });
}

/// Skan wlasciwy dla platformy: SDK Kotlin na Androidzie, libbacore na macOS.
Future<List<String>> platformScan(String libPath) =>
    Platform.isAndroid ? scanAndroid() : BrainAccessScanner.scan(libPath);

/// Android ma SDK w aplikacji, macOS wymaga biblioteki libbacore.
bool get platformNeedsLibrary => !Platform.isAndroid;
