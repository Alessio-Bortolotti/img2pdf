import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/edit_params.dart';

enum _Drag { none, move, tl, tr, bl, br, l, t, r, b }

/// Area di ritaglio trascinabile sopra l'immagine.
class CropEditor extends StatefulWidget {
  const CropEditor({
    super.key,
    required this.imageBytes,
    required this.imageAspect,
    required this.rect,
    required this.onChanged,
    this.aspect,
  });

  final Uint8List imageBytes;

  /// Larghezza/altezza dell'immagine mostrata.
  final double imageAspect;

  /// Ritaglio normalizzato corrente.
  final CropRect rect;

  /// Proporzione bloccata (larghezza/altezza) o null per libero.
  final double? aspect;

  final ValueChanged<CropRect> onChanged;

  /// Il ritaglio più grande possibile, centrato, con proporzione [aspect].
  static CropRect maxRectFor(double imageAspect, double aspect) {
    if (imageAspect > aspect) {
      final w = aspect / imageAspect;
      return CropRect((1 - w) / 2, 0, w, 1);
    } else {
      final h = imageAspect / aspect;
      return CropRect(0, (1 - h) / 2, 1, h);
    }
  }

  @override
  State<CropEditor> createState() => _CropEditorState();
}

class _CropEditorState extends State<CropEditor> {
  _Drag _drag = _Drag.none;
  Rect _start = Rect.zero;
  Offset _startPos = Offset.zero;

  static double _cl(double v, double lo, double hi) =>
      hi < lo ? lo : (v < lo ? lo : (v > hi ? hi : v));

  Rect _toDisplay(CropRect c, Size s) => Rect.fromLTWH(
      c.left * s.width, c.top * s.height, c.width * s.width, c.height * s.height);

  CropRect _toNorm(Rect r, Size s) => CropRect(
      r.left / s.width, r.top / s.height, r.width / s.width, r.height / s.height);

  _Drag _hit(Offset p, Rect c) {
    const t = 28.0;
    bool near(Offset a) => (a - p).distance <= t;
    if (near(c.topLeft)) return _Drag.tl;
    if (near(c.topRight)) return _Drag.tr;
    if (near(c.bottomLeft)) return _Drag.bl;
    if (near(c.bottomRight)) return _Drag.br;
    if (widget.aspect == null) {
      const e = 20.0;
      final inY = p.dy > c.top && p.dy < c.bottom;
      final inX = p.dx > c.left && p.dx < c.right;
      if (inY && (p.dx - c.left).abs() <= e) return _Drag.l;
      if (inY && (p.dx - c.right).abs() <= e) return _Drag.r;
      if (inX && (p.dy - c.top).abs() <= e) return _Drag.t;
      if (inX && (p.dy - c.bottom).abs() <= e) return _Drag.b;
    }
    if (c.contains(p)) return _Drag.move;
    return _Drag.none;
  }

  Rect _update(Rect s, Offset d, Size bounds) {
    if (_drag == _Drag.move) {
      final dx = _cl(d.dx, -s.left, bounds.width - s.right);
      final dy = _cl(d.dy, -s.top, bounds.height - s.bottom);
      return s.shift(Offset(dx, dy));
    }
    final minSize = math.min(40.0, math.min(bounds.width, bounds.height) / 4);
    final mL = _drag == _Drag.tl || _drag == _Drag.bl || _drag == _Drag.l;
    final mR = _drag == _Drag.tr || _drag == _Drag.br || _drag == _Drag.r;
    final mT = _drag == _Drag.tl || _drag == _Drag.tr || _drag == _Drag.t;
    final mB = _drag == _Drag.bl || _drag == _Drag.br || _drag == _Drag.b;

    double left = s.left, top = s.top, right = s.right, bottom = s.bottom;
    if (mL) left = _cl(s.left + d.dx, 0, s.right - minSize);
    if (mR) right = _cl(s.right + d.dx, s.left + minSize, bounds.width);
    if (mT) top = _cl(s.top + d.dy, 0, s.bottom - minSize);
    if (mB) bottom = _cl(s.bottom + d.dy, s.top + minSize, bounds.height);

    final a = widget.aspect;
    if (a != null && (mL || mR) && (mT || mB)) {
      final ax = mL ? s.right : s.left;
      final ay = mT ? s.bottom : s.top;
      final maxW = mL ? ax : bounds.width - ax;
      final maxH = mT ? ay : bounds.height - ay;
      double w = right - left;
      double h = w / a;
      final hDrag = bottom - top;
      if (hDrag * a > w) {
        w = hDrag * a;
        h = hDrag;
      }
      if (w > maxW) {
        w = maxW;
        h = w / a;
      }
      if (h > maxH) {
        h = maxH;
        w = h * a;
      }
      left = mL ? ax - w : ax;
      right = left + w;
      top = mT ? ay - h : ay;
      bottom = top + h;
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, cons) {
      const pad = 24.0;
      final availW = math.max(1.0, cons.maxWidth - 2 * pad);
      final availH = math.max(1.0, cons.maxHeight - 2 * pad);
      double w = availW, h = w / widget.imageAspect;
      if (h > availH) {
        h = availH;
        w = h * widget.imageAspect;
      }
      final imgRect = Rect.fromLTWH(
          (cons.maxWidth - w) / 2, (cons.maxHeight - h) / 2, w, h);
      final crop = _toDisplay(widget.rect, imgRect.size);

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) {
          final local = d.localPosition - imgRect.topLeft;
          _drag = _hit(local, crop);
          _start = crop;
          _startPos = local;
        },
        onPanUpdate: (d) {
          if (_drag == _Drag.none) return;
          final local = d.localPosition - imgRect.topLeft;
          final r = _update(_start, local - _startPos, imgRect.size);
          widget.onChanged(_toNorm(r, imgRect.size));
        },
        onPanEnd: (_) => _drag = _Drag.none,
        child: Stack(children: [
          Positioned.fromRect(
            rect: imgRect,
            child: Image.memory(widget.imageBytes,
                fit: BoxFit.fill, gaplessPlayback: true),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: _CropPainter(imgRect, crop.shift(imgRect.topLeft)),
            ),
          ),
        ]),
      );
    });
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.image, this.crop);
  final Rect image;
  final Rect crop;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()..color = const Color(0x99000000);
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(image)
        ..addRect(crop),
      dim,
    );

    final thin = Paint()
      ..color = const Color(0x80FFFFFF)
      ..strokeWidth = 0.8;
    for (var i = 1; i < 3; i++) {
      final x = crop.left + crop.width * i / 3;
      final y = crop.top + crop.height * i / 3;
      canvas.drawLine(Offset(x, crop.top), Offset(x, crop.bottom), thin);
      canvas.drawLine(Offset(crop.left, y), Offset(crop.right, y), thin);
    }

    canvas.drawRect(
      crop,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    final handle = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final len = math.min(22.0, crop.shortestSide / 3);
    void corner(Offset p, double dx, double dy) {
      canvas.drawLine(p, p + Offset(dx * len, 0), handle);
      canvas.drawLine(p, p + Offset(0, dy * len), handle);
    }

    corner(crop.topLeft, 1, 1);
    corner(crop.topRight, -1, 1);
    corner(crop.bottomLeft, 1, -1);
    corner(crop.bottomRight, -1, -1);
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.crop != crop || old.image != image;
}
