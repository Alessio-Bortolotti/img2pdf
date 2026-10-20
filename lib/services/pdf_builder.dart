import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'image_processor.dart';

enum PageSizeOption {
  a4('A4', PdfPageFormat.a4),
  a3('A3', PdfPageFormat.a3),
  a5('A5', PdfPageFormat.a5),
  letter('Letter', PdfPageFormat.letter),
  legal('Legal', PdfPageFormat.legal),
  fitImage('Come l\'immagine', null);

  const PageSizeOption(this.label, this.format);
  final String label;
  final PdfPageFormat? format;
}

enum PageOrientationOption { auto, portrait, landscape }

enum FitOption { contain, cover }

@immutable
class PdfSettings {
  const PdfSettings({
    this.size = PageSizeOption.a4,
    this.orientation = PageOrientationOption.auto,
    this.fit = FitOption.contain,
    this.marginMm = 5,
    this.quality = 90,
  });

  final PageSizeOption size;
  final PageOrientationOption orientation;
  final FitOption fit;
  final double marginMm;
  final int quality; // qualità JPEG 50..100

  PdfSettings copyWith({
    PageSizeOption? size,
    PageOrientationOption? orientation,
    FitOption? fit,
    double? marginMm,
    int? quality,
  }) =>
      PdfSettings(
        size: size ?? this.size,
        orientation: orientation ?? this.orientation,
        fit: fit ?? this.fit,
        marginMm: marginMm ?? this.marginMm,
        quality: quality ?? this.quality,
      );

  @override
  bool operator ==(Object other) =>
      other is PdfSettings &&
      other.size == size &&
      other.orientation == orientation &&
      other.fit == fit &&
      other.marginMm == marginMm &&
      other.quality == quality;

  @override
  int get hashCode => Object.hash(size, orientation, fit, marginMm, quality);
}

class PdfBuilder {
  /// Risoluzione usata per "Come l'immagine": 150 dpi.
  static const double _fitDpi = 150;

  /// Formato della pagina che conterrà [im] con le impostazioni [s].
  static PdfPageFormat pageFormatFor(RenderedImage im, PdfSettings s) {
    final margin = s.marginMm * PdfPageFormat.mm;
    final base = s.size.format;
    if (base == null) {
      final w = im.width * 72 / _fitDpi;
      final h = im.height * 72 / _fitDpi;
      return PdfPageFormat(w + 2 * margin, h + 2 * margin);
    }
    final landscape = switch (s.orientation) {
      PageOrientationOption.auto => im.width > im.height,
      PageOrientationOption.portrait => false,
      PageOrientationOption.landscape => true,
    };
    return landscape ? base.landscape : base.portrait;
  }

  static Future<Uint8List> build(
    List<RenderedImage> images,
    PdfSettings s, {
    String title = 'Documento',
  }) {
    final doc = pw.Document(title: title, creator: 'FotoPDF');
    final margin = s.marginMm * PdfPageFormat.mm;

    for (final im in images) {
      final image = pw.MemoryImage(im.bytes);
      final format = pageFormatFor(im, s);

      doc.addPage(
        pw.Page(
          pageFormat: format,
          margin: pw.EdgeInsets.all(margin),
          build: (context) => pw.SizedBox.expand(
            child: s.fit == FitOption.cover
                ? pw.ClipRect(
                    child: pw.Image(image,
                        fit: pw.BoxFit.cover, alignment: pw.Alignment.center),
                  )
                : pw.Image(image,
                    fit: pw.BoxFit.contain, alignment: pw.Alignment.center),
          ),
        ),
      );
    }
    return doc.save();
  }
}
