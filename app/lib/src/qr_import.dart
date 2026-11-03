import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:image/image.dart' as img;
import 'package:pasteboard/pasteboard.dart';
import 'package:zxing2/qrcode.dart';

/// Decodes a QR code from image bytes (PNG/JPEG/BMP/WebP…). Null when none is found.
String? decodeQrBytes(Uint8List bytes) {
  final im = img.decodeImage(bytes);
  if (im == null) return null;
  String? tryOne(img.Image src) {
    final rgba = src.convert(numChannels: 4);
    final px = rgba.getBytes(order: img.ChannelOrder.rgba).buffer.asInt32List();
    // zxing2 wants ARGB ints; luminance only needs the channel values, swap R/B to ARGB order
    final argb = Int32List(px.length);
    for (var i = 0; i < px.length; i++) {
      final v = px[i];
      final r = v & 0xFF,
          g = (v >> 8) & 0xFF,
          b = (v >> 16) & 0xFF,
          a = (v >> 24) & 0xFF;
      argb[i] = (a << 24) | (r << 16) | (g << 8) | b;
    }
    final src2 = RGBLuminanceSource(rgba.width, rgba.height, argb);
    for (final bin in [HybridBinarizer(src2), GlobalHistogramBinarizer(src2)]) {
      try {
        return QRCodeReader()
            .decode(
              BinaryBitmap(bin),
              hints: DecodeHints()..put(DecodeHintType.tryHarder),
            )
            .text;
      } catch (_) {}
    }
    return null;
  }

  var r = tryOne(im);
  if (r != null) return r;
  // large screenshots: a downscaled copy often decodes better/faster
  if (im.width > 1200 || im.height > 1200) {
    r = tryOne(
      img.copyResize(
        im,
        width: im.width > im.height ? 1000 : null,
        height: im.height >= im.width ? 1000 : null,
      ),
    );
    if (r != null) return r;
  }
  // light-on-dark codes (e.g. AMOLED screenshots)
  return tryOne(img.invert(im.clone()));
}

/// Desktop: pick a QR image file. Null when cancelled; "error:noqr" when no code was found.
Future<String?> qrFromFile() async {
  const t = XTypeGroup(
    label: 'Изображения',
    extensions: ['png', 'jpg', 'jpeg', 'bmp', 'gif', 'webp'],
  );
  final f = await openFile(acceptedTypeGroups: [t]);
  if (f == null) return null;
  return decodeQrBytes(await f.readAsBytes()) ?? 'error:noqr';
}

/// Desktop: QR from an image on the clipboard (screenshot / copied picture).
/// "error:noimage" when the clipboard has no image, "error:noqr" when no code was found.
Future<String?> qrFromClipboard() async {
  Uint8List? b;
  try {
    b = await Pasteboard.image;
  } catch (_) {}
  if (b == null || b.isEmpty) return 'error:noimage';
  return decodeQrBytes(b) ?? 'error:noqr';
}

String qrError(String e) => switch (e) {
  'error:denied' => 'Нет доступа к камере',
  'error:nocamera' => 'Камера недоступна',
  'error:busy' => 'Сканер уже открыт',
  'error:noimage' => 'В буфере обмена нет картинки',
  'error:noqr' => 'QR-код не найден на изображении',
  _ => 'Не удалось прочитать QR-код',
};
