import 'dart:isolate';

import 'bacore.dart';

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
