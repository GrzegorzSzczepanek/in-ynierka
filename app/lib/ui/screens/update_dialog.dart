import 'package:flutter/material.dart';

import '../../core/update/update_checker.dart';
import '../theme/pixel_theme.dart';

enum UpdateChoice { download, later, skip }

/// Pyta, czy pobrac nowa wersje. Zwraca wybor uzytkownika (zamkniecie = pozniej).
Future<UpdateChoice> showUpdateDialog(
  BuildContext context,
  UpdateInfo info,
  String currentVersion,
) async {
  final choice = await showDialog<UpdateChoice>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PkDialog(
            text:
                'NOWA WERSJA ${info.version}\nMasz $currentVersion. Pobrać nową?',
            more: false,
          ),
          const SizedBox(height: 8),
          PkAction(
            label: 'POBIERZ',
            onTap: () => Navigator.of(ctx).pop(UpdateChoice.download),
          ),
          const SizedBox(height: 8),
          PkAction(
            label: 'PÓŹNIEJ',
            primary: false,
            onTap: () => Navigator.of(ctx).pop(UpdateChoice.later),
          ),
          const SizedBox(height: 8),
          PkAction(
            label: 'POMIŃ TĘ WERSJĘ',
            primary: false,
            onTap: () => Navigator.of(ctx).pop(UpdateChoice.skip),
          ),
        ],
      ),
    ),
  );
  return choice ?? UpdateChoice.later;
}
