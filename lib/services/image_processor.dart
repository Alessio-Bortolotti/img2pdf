import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/edit_params.dart';

class PreparedImage {
  const PreparedImage(this.previewBase, this.width, this.height);
  final Uint8List previewBase;
  final int width;
  final int height;
}

class RenderedImage {
  const RenderedImage(this.bytes, this.width, this.height);
  final Uint8List bytes; // JPEG
  final int width;
  final int height;
}

/// Tutta l'elaborazione avviene in locale, in un isolate separato
/// per non bloccare l'interfaccia.
class ImageProcessor {
  static const int previewMaxSide = 1400;

  /// Decodifica il file, applica l'orientamento EXIF e crea la base per le anteprime.
  static Future<PreparedImage> prepare(Uint8List bytes) {
    return Isolate.run(() {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        throw const FormatException('Formato immagine non supportato');
      }
      final baked = _flatten(img.bakeOrientation(decoded));
      final preview = _fitMax(baked, previewMaxSide);
      return PreparedImage(
        img.encodeJpg(preview, quality: 90),
        baked.width,
        baked.height,
      );
    });
  }

  /// Anteprima veloce a partire dalla base ridotta (il ridimensionamento
  /// non viene applicato perché cambia solo la risoluzione).
  static Future<RenderedImage> renderPreview(
    Uint8List previewBase,
    EditParams params, {
    bool skipCrop = false,
    int maxSide = previewMaxSide,
  }) {
    return Isolate.run(() {
      final base = img.decodeImage(previewBase)!;
      var out = applyEdits(base, params, skipCrop: skipCrop, skipResize: true);
      out = _fitMax(out, maxSide);
      return RenderedImage(img.encodeJpg(out, quality: 85), out.width, out.height);
    });
  }

  /// Render a piena risoluzione per il PDF.
  static Future<RenderedImage> renderFull(
    Uint8List original,
    EditParams params, {
    int quality = 90,
  }) {
    return Isolate.run(() {
      final decoded = img.decodeImage(original)!;
      final base = _flatten(img.bakeOrientation(decoded));
      final out = applyEdits(base, params);
      return RenderedImage(
          img.encodeJpg(out, quality: quality), out.width, out.height);
    });
  }

  /// Miniature di tutti i filtri per il selettore.
  static Future<List<Uint8List>> filterThumbnails(Uint8List previewBase) {
    return Isolate.run(() {
      final base = _fitMax(img.decodeImage(previewBase)!, 160);
      return [
        for (final f in ImageFilter.values)
          img.encodeJpg(_applyFilter(base.clone(), f), quality: 80),
      ];
    });
  }

  // ---------------------------------------------------------------------------
  // Pipeline

  static img.Image applyEdits(
    img.Image src,
    EditParams p, {
    bool skipCrop = false,
    bool skipResize = false,
  }) {
    var im = src;
    final q = p.quarterTurns % 4;
    if (q != 0) im = img.copyRotate(im, angle: 90 * q);
    if (p.flipH) im = img.flipHorizontal(im);
    if (p.flipV) im = img.flipVertical(im);
    if (p.fineAngle.abs() > 0.05) im = _rotateFine(im, p.fineAngle);
    final c = p.crop;
    if (!skipCrop && c != null && !c.isFull) im = _crop(im, c);
    if (!skipResize && p.scale < 0.999) {
      final w = math.max(1, (im.width * p.scale).round());
      im = img.copyResize(im, width: w, interpolation: img.Interpolation.average);
    }
    _adjust(im, p.brightness, p.contrast, p.saturation);
    im = _applyFilter(im, p.filter);
    return im;
  }

  /// Converte in RGB 8 bit, appiattendo la trasparenza su sfondo bianco.
  static img.Image _flatten(img.Image src) {
    var im = src;
    if (im.format != img.Format.uint8 ||
        im.hasPalette ||
        (im.numChannels != 3 && im.numChannels != 4)) {
      im = im.convert(format: img.Format.uint8, numChannels: src.hasAlpha ? 4 : 3);
    }
    if (im.numChannels == 4) {
      final out = img.Image(width: im.width, height: im.height, numChannels: 3);
      img.fill(out, color: img.ColorRgb8(255, 255, 255));
      img.compositeImage(out, im);
      im = out;
    }
    return im;
  }

  static img.Image _fitMax(img.Image im, int maxSide) {
    if (math.max(im.width, im.height) <= maxSide) return im;
    return im.width >= im.height
        ? img.copyResize(im, width: maxSide, interpolation: img.Interpolation.average)
        : img.copyResize(im, height: maxSide, interpolation: img.Interpolation.average);
  }

  static img.Image _rotateFine(img.Image im, double angle) {
    final withAlpha = im.convert(numChannels: 4, alpha: 255);
    final rotated = img.copyRotate(withAlpha,
        angle: angle, interpolation: img.Interpolation.linear);
    final canvas =
        img.Image(width: rotated.width, height: rotated.height, numChannels: 3);
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(canvas, rotated);
    return canvas;
  }

  static img.Image _crop(img.Image im, CropRect c) {
    final x = (c.left * im.width).round().clamp(0, im.width - 1);
    final y = (c.top * im.height).round().clamp(0, im.height - 1);
    final w = (c.width * im.width).round().clamp(1, im.width - x);
    final h = (c.height * im.height).round().clamp(1, im.height - y);
    return img.copyCrop(im, x: x, y: y, width: w, height: h);
  }

  static int _c8(num v) => v < 0 ? 0 : (v > 255 ? 255 : v.round());

  static void _adjust(img.Image im, double b, double c, double s) {
    if (b == 0 && c == 0 && s == 0) return;
    final off = b * 100;
    final cf = c >= 0 ? 1 + c * 1.5 : 1 + c * 0.9;
    final sf = 1 + s;
    for (final px in im) {
      double r = px.r.toDouble() + off;
      double g = px.g.toDouble() + off;
      double bl = px.b.toDouble() + off;
      r = (r - 128) * cf + 128;
      g = (g - 128) * cf + 128;
      bl = (bl - 128) * cf + 128;
      final l = 0.299 * r + 0.587 * g + 0.114 * bl;
      px
        ..r = _c8(l + (r - l) * sf)
        ..g = _c8(l + (g - l) * sf)
        ..b = _c8(l + (bl - l) * sf);
    }
  }

  static img.Image _applyFilter(img.Image im, ImageFilter f) {
    switch (f) {
      case ImageFilter.none:
        return im;
      case ImageFilter.grayscale:
        return img.grayscale(im);
      case ImageFilter.sepia:
        return img.sepia(im);
      case ImageFilter.invert:
        return img.invert(im);
      case ImageFilter.vintage:
        img.sepia(im, amount: 0.55);
        return img.vignette(im);
      case ImageFilter.blur:
        final radius = math.max(1, (math.max(im.width, im.height) / 300).round());
        return img.gaussianBlur(im, radius: radius);
      case ImageFilter.sharpen:
        return img.convolution(im, filter: const [0, -1, 0, -1, 5, -1, 0, -1, 0]);
      case ImageFilter.document:
        for (final px in im) {
          final l = 0.299 * px.r + 0.587 * px.g + 0.114 * px.b;
          final v = _c8((l - 128) * 1.6 + 128 + 25);
          px
            ..r = v
            ..g = v
            ..b = v;
        }
        return im;
      case ImageFilter.blackWhite:
        for (final px in im) {
          final l = 0.299 * px.r + 0.587 * px.g + 0.114 * px.b;
          final v = l > 140 ? 255 : 0;
          px
            ..r = v
            ..g = v
            ..b = v;
        }
        return im;
      case ImageFilter.warm:
        for (final px in im) {
          px
            ..r = _c8(px.r * 1.06 + 12)
            ..g = _c8(px.g * 1.02)
            ..b = _c8(px.b * 0.88);
        }
        return im;
      case ImageFilter.cool:
        for (final px in im) {
          px
            ..r = _c8(px.r * 0.88)
            ..g = _c8(px.g * 1.0)
            ..b = _c8(px.b * 1.06 + 12);
        }
        return im;
    }
  }
}
