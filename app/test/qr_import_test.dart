import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nox/src/qr_import.dart';
import 'package:qr/qr.dart';

img.Image render(String data, {bool inverted = false}) {
  final q = QrImage(
    QrCode(
      payload: QrPayload.fromString(data),
      errorCorrectLevel: QrErrorCorrectLevel.medium,
    ),
  );
  const s = 8, quiet = 4;
  final n = q.moduleCount, w = (n + quiet * 2) * s;
  final bg = inverted ? img.ColorRgb8(0, 0, 0) : img.ColorRgb8(255, 255, 255);
  final fg = inverted ? img.ColorRgb8(255, 255, 255) : img.ColorRgb8(0, 0, 0);
  final im = img.Image(width: w, height: w)..clear(bg);
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      if (q.isDark(y, x)) {
        img.fillRect(
          im,
          x1: (x + quiet) * s,
          y1: (y + quiet) * s,
          x2: (x + quiet + 1) * s - 1,
          y2: (y + quiet + 1) * s - 1,
          color: fg,
        );
      }
    }
  }
  return im;
}

void main() {
  const link =
      'vless://11111111-2222-3333-4444-555555555555@nl.example.com:443?type=tcp&security=reality#NL';
  test(
    'decodes a PNG QR',
    () => expect(decodeQrBytes(img.encodePng(render(link))), link),
  );
  test(
    'decodes an inverted (AMOLED) QR',
    () => expect(
      decodeQrBytes(img.encodePng(render(link, inverted: true))),
      link,
    ),
  );
  test(
    'no QR -> null',
    () => expect(
      decodeQrBytes(img.encodePng(img.Image(width: 50, height: 50))),
      isNull,
    ),
  );
}
