import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// Filtri disponibili nell'editor.
enum ImageFilter {
  none('Originale'),
  grayscale('Grigi'),
  document('Documento'),
  blackWhite('B/N netto'),
  sepia('Seppia'),
  vintage('Vintage'),
  warm('Caldo'),
  cool('Freddo'),
  invert('Negativo'),
  sharpen('Nitidezza'),
  blur('Sfocatura');

  const ImageFilter(this.label);
  final String label;
}

/// Rettangolo di ritaglio in coordinate normalizzate (0..1) rispetto
/// all'immagine già ruotata/specchiata.
@immutable
class CropRect {
  const CropRect(this.left, this.top, this.width, this.height);

  final double left;
  final double top;
  final double width;
  final double height;

  static const full = CropRect(0, 0, 1, 1);

  bool get isFull =>
      left <= 0.0005 && top <= 0.0005 && width >= 0.999 && height >= 0.999;

  CropRect rotatedClockwise() => CropRect(1 - top - height, left, height, width);
  CropRect rotatedCounterClockwise() =>
      CropRect(top, 1 - left - width, height, width);
  CropRect flippedH() => CropRect(1 - left - width, top, width, height);
  CropRect flippedV() => CropRect(left, 1 - top - height, width, height);

  @override
  bool operator ==(Object other) =>
      other is CropRect &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);
}

/// Modifiche non distruttive applicate a un'immagine.
/// Ordine della pipeline: rotazione 90° → specchio → raddrizza → ritaglio →
/// ridimensiona → regolazioni → filtro.
@immutable
class EditParams {
  const EditParams({
    this.quarterTurns = 0,
    this.flipH = false,
    this.flipV = false,
    this.fineAngle = 0,
    this.crop,
    this.scale = 1,
    this.filter = ImageFilter.none,
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
  });

  final int quarterTurns; // 0..3 in senso orario
  final bool flipH;
  final bool flipV;
  final double fineAngle; // gradi, -45..45
  final CropRect? crop;
  final double scale; // 0.1..1
  final ImageFilter filter;
  final double brightness; // -1..1
  final double contrast; // -1..1
  final double saturation; // -1..1

  bool get isIdentity => this == const EditParams();

  EditParams copyWith({
    int? quarterTurns,
    bool? flipH,
    bool? flipV,
    double? fineAngle,
    CropRect? crop,
    bool clearCrop = false,
    double? scale,
    ImageFilter? filter,
    double? brightness,
    double? contrast,
    double? saturation,
  }) {
    return EditParams(
      quarterTurns: quarterTurns ?? this.quarterTurns,
      flipH: flipH ?? this.flipH,
      flipV: flipV ?? this.flipV,
      fineAngle: fineAngle ?? this.fineAngle,
      crop: clearCrop ? null : (crop ?? this.crop),
      scale: scale ?? this.scale,
      filter: filter ?? this.filter,
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
    );
  }

  EditParams withoutCrop() => copyWith(clearCrop: true);

  bool get _oddFlip => flipH != flipV;

  // Le operazioni sotto si comportano come se fossero applicate
  // all'immagine così come appare ora (lo stato resta coerente con la pipeline).
  EditParams rotateClockwise() => copyWith(
        quarterTurns: (quarterTurns + (_oddFlip ? 3 : 1)) % 4,
        crop: crop?.rotatedClockwise(),
      );

  EditParams rotateCounterClockwise() => copyWith(
        quarterTurns: (quarterTurns + (_oddFlip ? 1 : 3)) % 4,
        crop: crop?.rotatedCounterClockwise(),
      );

  EditParams toggleFlipH() =>
      copyWith(flipH: !flipH, fineAngle: -fineAngle, crop: crop?.flippedH());

  EditParams toggleFlipV() =>
      copyWith(flipV: !flipV, fineAngle: -fineAngle, crop: crop?.flippedV());

  /// Dimensione in pixel del risultato partendo dall'originale [w]×[h].
  (int, int) outputSize(int w, int h) {
    double ow = (quarterTurns.isOdd ? h : w).toDouble();
    double oh = (quarterTurns.isOdd ? w : h).toDouble();
    if (fineAngle.abs() > 0.05) {
      final a = fineAngle.abs() * math.pi / 180;
      final nw = ow * math.cos(a) + oh * math.sin(a);
      final nh = ow * math.sin(a) + oh * math.cos(a);
      ow = nw;
      oh = nh;
    }
    final c = crop;
    if (c != null && !c.isFull) {
      ow *= c.width;
      oh *= c.height;
    }
    return (
      math.max(1, (ow * scale).round()),
      math.max(1, (oh * scale).round()),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EditParams &&
      other.quarterTurns == quarterTurns &&
      other.flipH == flipH &&
      other.flipV == flipV &&
      other.fineAngle == fineAngle &&
      other.crop == crop &&
      other.scale == scale &&
      other.filter == filter &&
      other.brightness == brightness &&
      other.contrast == contrast &&
      other.saturation == saturation;

  @override
  int get hashCode => Object.hash(quarterTurns, flipH, flipV, fineAngle, crop,
      scale, filter, brightness, contrast, saturation);
}

/// Una pagina del futuro PDF.
class PageItem {
  PageItem({
    required this.id,
    required this.name,
    required this.original,
    required this.previewBase,
    required this.width,
    required this.height,
    this.params = const EditParams(),
    this.thumbnail,
  });

  final String id;
  final String name;

  /// Byte originali del file (mai modificati).
  final Uint8List original;

  /// Versione ridotta (JPEG, lato lungo max 1400px) usata per le anteprime.
  final Uint8List previewBase;

  /// Dimensioni dell'originale dopo la correzione EXIF.
  final int width;
  final int height;

  EditParams params;
  Uint8List? thumbnail;

  static int _counter = 0;
  static String newId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${_counter++}';

  PageItem duplicate() => PageItem(
        id: newId(),
        name: name,
        original: original,
        previewBase: previewBase,
        width: width,
        height: height,
        params: params,
        thumbnail: thumbnail,
      );
}
