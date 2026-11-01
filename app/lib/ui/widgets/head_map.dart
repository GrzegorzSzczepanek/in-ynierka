import 'package:flutter/material.dart';

import '../../core/session/session_models.dart';
import '../theme/pixel_theme.dart';

/// Położenia elektrod 10-20 na czepku BrainAccess (rys. 3, instrukcja czepka),
/// współrzędne w pikselach rysunku, środek (419, 650), promień ok. 210.
const _cap = {
  'AF3': (354, 509),
  'AFz': (419, 509),
  'AF4': (484, 509),
  'F7': (256, 535),
  'Fz': (419, 561),
  'F8': (579, 536),
  'F3': (331, 552),
  'F4': (507, 552),
  'FC5': (288, 591),
  'FC1': (360, 603),
  'FC2': (484, 603),
  'FC6': (558, 591),
  'T7': (217, 646),
  'C3': (312, 646),
  'Cz': (419, 646),
  'C4': (527, 646),
  'T8': (622, 646),
  'CP5': (270, 696),
  'CP1': (360, 687),
  'CP2': (479, 687),
  'CP6': (568, 696),
  'P7': (248, 764),
  'P3': (334, 741),
  'Pz': (419, 732),
  'P4': (505, 741),
  'P8': (590, 764),
  'PO3': (354, 796),
  'POz': (419, 796),
  'PO4': (484, 796),
  'O1': (358, 851),
  'Oz': (419, 860),
  'O2': (480, 851),
};

/// Mapa głowy z kanałami; kanały o nieznanych nazwach nie są rysowane.
class HeadMap extends StatelessWidget {
  const HeadMap({super.key, required this.channels, this.training = const []});

  final List<ChannelContact> channels;
  final List<String> training;

  /// Mapa ma sens, gdy wiekszosc kanalow ma znane nazwy 10-20.
  static bool canDraw(List<ChannelContact> channels) =>
      channels.where((c) => _cap.containsKey(c.name)).length * 2 >=
      channels.length;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1.05,
    child: LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final h = c.maxHeight;
        Offset pos((int, int) p) => Offset(
          w / 2 + (p.$1 - 419) / 250 * (w / 2),
          h * 0.52 + (p.$2 - 650) / 250 * (h / 2),
        );
        return Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _HeadPainter())),
            for (final ch in channels)
              if (_cap[ch.name] != null)
                Positioned(
                  left: pos(_cap[ch.name]!).dx - 17,
                  top: pos(_cap[ch.name]!).dy - 11,
                  child: Container(
                    width: 34,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: ch.contact ? Px.accent : Px.panel,
                      border: Border.all(
                        color: Px.ink,
                        width: training.contains(ch.name)
                            ? 3
                            : (ch.contact ? 1 : 2),
                        strokeAlign: BorderSide.strokeAlignInside,
                      ),
                    ),
                    child: Text(
                      ch.name,
                      style: Px.t(
                        6,
                        color: ch.contact ? Colors.white : Px.ink2,
                        height: 1,
                      ),
                    ),
                  ),
                ),
          ],
        );
      },
    ),
  );
}

class _HeadPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(
      4,
      size.height * 0.04,
      size.width - 8,
      size.height * 0.94,
    );
    final head = RRect.fromRectAndRadius(r, Radius.circular(size.width * 0.32));
    canvas.drawRRect(head, Paint()..color = Px.panel);
    canvas.drawRRect(
      head,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Px.ink
        ..isAntiAlias = false,
    );
    final nose = Path()
      ..moveTo(size.width / 2 - 14, size.height * 0.045)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width / 2 + 14, size.height * 0.045);
    canvas.drawPath(
      nose,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Px.ink,
    );
  }

  @override
  bool shouldRepaint(_HeadPainter old) => false;
}
