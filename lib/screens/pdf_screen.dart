import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../models/edit_params.dart';
import '../services/image_processor.dart';
import '../services/pdf_builder.dart';
import '../theme.dart';
import '../widgets/ui.dart';

class PdfScreen extends StatefulWidget {
  const PdfScreen({super.key, required this.items});
  final List<PageItem> items;

  @override
  State<PdfScreen> createState() => _PdfScreenState();
}

/// Anteprima di una pagina: render reale del PDF (Android/desktop) oppure,
/// sul web, composizione equivalente dell'immagine nella pagina.
class _PageImage {
  const _PageImage(this.png, this.aspect)
      : image = null,
        marginFrac = 0,
        cover = false;
  const _PageImage.composed(RenderedImage this.image, this.aspect,
      this.marginFrac, this.cover)
      : png = null;
  final Uint8List? png;
  final RenderedImage? image;
  final double aspect; // larghezza / altezza
  final double marginFrac; // margine / larghezza pagina
  final bool cover;
}

class _PdfScreenState extends State<PdfScreen> {
  PdfSettings _settings = const PdfSettings();
  final _nameCtrl = TextEditingController(text: 'documento');
  final Map<String, RenderedImage> _cache = {};
  final _pageCtrl = PageController(viewportFraction: 0.6);

  Uint8List? _pdf;
  PdfSettings? _pdfSettings;
  List<_PageImage> _pages = [];
  int _page = 0;
  String? _status = 'Preparazione…';
  String? _error;
  int _gen = 0;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _regenerate();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _nameCtrl.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  String get _fileName {
    var n = _nameCtrl.text.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (n.isEmpty) n = 'documento';
    return n.toLowerCase().endsWith('.pdf') ? n : '$n.pdf';
  }

  String _formatSize(int b) {
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} MB';
  }

  // ------------------------------------------------------------ generazione

  List<RenderedImage> _lastImages = [];

  Future<Uint8List> _buildPdf(PdfSettings s, {void Function(String)? onStatus}) async {
    if (_pdf != null && _pdfSettings == s) return _pdf!;
    final images = <RenderedImage>[];
    final items = widget.items;
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      final key = '${it.id}_${it.params.hashCode}_${s.quality}';
      var r = _cache[key];
      if (r == null) {
        onStatus?.call('Elaboro pagina ${i + 1} di ${items.length}…');
        r = await ImageProcessor.renderFull(it.original, it.params,
            quality: s.quality);
        _cache[key] = r;
      }
      images.add(r);
    }
    _lastImages = images;
    onStatus?.call('Creo il PDF…');
    final bytes = await PdfBuilder.build(images, s, title: _fileName);
    if (s == _settings) {
      _pdf = bytes;
      _pdfSettings = s;
    }
    return bytes;
  }

  /// Rigenera PDF e miniature delle pagine (con piccolo ritardo per gli slider).
  void _regenerate({bool debounce = false}) {
    _debounce?.cancel();
    _debounce = Timer(Duration(milliseconds: debounce ? 250 : 0), () async {
      final id = ++_gen;
      final s = _settings;
      setState(() {
        _status = 'Preparazione…';
        _error = null;
      });
      try {
        final bytes = await _buildPdf(s, onStatus: (t) {
          if (mounted && id == _gen) setState(() => _status = t);
        });
        if (!mounted || id != _gen) return;
        setState(() => _status = 'Creo l\'anteprima…');

        // Risoluzione delle miniature: ~900 px di larghezza.
        final dpi = _previewDpi(s);
        final pages = <_PageImage>[];
        if (kIsWeb) {
          for (final im in _lastImages) {
            final f = PdfBuilder.pageFormatFor(im, s);
            pages.add(_PageImage.composed(im, f.width / f.height,
                s.marginMm * PdfPageFormat.mm / f.width, s.fit == FitOption.cover));
          }
        } else {
          await for (final r in Printing.raster(bytes, dpi: dpi)) {
            if (!mounted || id != _gen) return;
            pages.add(_PageImage(await r.toPng(), r.width / r.height));
          }
        }
        if (!mounted || id != _gen) return;
        setState(() {
          _pages = pages;
          _page = math.min(_page, math.max(0, pages.length - 1));
          _status = null;
        });
      } catch (e) {
        if (mounted && id == _gen) {
          setState(() {
            _status = null;
            _error = '$e';
          });
        }
      }
    });
  }

  double _previewDpi(PdfSettings s) {
    final f = s.size.format;
    double maxWidthPt;
    if (f == null) {
      final maxPx = _cache.values.fold<int>(1, (m, r) => math.max(m, r.width));
      maxWidthPt = maxPx * 72 / 150;
    } else {
      maxWidthPt = math.max(f.width, f.height);
    }
    return (72 * 900 / maxWidthPt).clamp(30, 150).toDouble();
  }

  void _setSettings(PdfSettings s) {
    if (s == _settings) return;
    setState(() => _settings = s);
    _regenerate(debounce: true);
  }

  // ------------------------------------------------------------ azioni

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _save() async {
    final bytes = await _buildPdf(_settings);
    try {
      if (kIsWeb) {
        await Printing.sharePdf(bytes: bytes, filename: _fileName);
      } else if (Platform.isAndroid || Platform.isIOS) {
        final path = await FilePicker.platform.saveFile(
          dialogTitle: 'Salva PDF',
          fileName: _fileName,
          type: FileType.custom,
          allowedExtensions: const ['pdf'],
          bytes: bytes,
        );
        if (path != null) _snack('PDF salvato');
      } else {
        final path = await FilePicker.platform.saveFile(
          dialogTitle: 'Salva PDF',
          fileName: _fileName,
          type: FileType.custom,
          allowedExtensions: const ['pdf'],
        );
        if (path == null) return;
        final out = path.toLowerCase().endsWith('.pdf') ? path : '$path.pdf';
        await File(out).writeAsBytes(bytes, flush: true);
        _snack('Salvato in $out');
      }
    } catch (e) {
      await Printing.sharePdf(bytes: bytes, filename: _fileName);
    }
  }

  Future<void> _share() async {
    final bytes = await _buildPdf(_settings);
    await Printing.sharePdf(bytes: bytes, filename: _fileName);
  }

  Future<void> _print() async {
    final bytes = await _buildPdf(_settings);
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: _fileName);
  }

  // ------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final busy = _status != null;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(builder: (context, cons) {
          final wide = cons.maxWidth >= 900;
          final preview = _preview();
          final settings = _SettingsPanel(
            settings: _settings,
            nameCtrl: _nameCtrl,
            onChanged: _setSettings,
          );
          final dock = Padding(
            padding: EdgeInsets.fromLTRB(
                16, 10, 16, 16 + MediaQuery.of(context).padding.bottom),
            child: Row(children: [
              SquareIconButton(
                icon: Icons.ios_share_rounded,
                size: 60,
                radius: 20,
                iconSize: 24,
                color: AppColors.surface2,
                iconColor: AppColors.primary,
                tooltip: 'Condividi',
                onTap: busy ? null : _share,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GradientButton(
                  icon: Icons.file_download_outlined,
                  label: 'Salva PDF',
                  onTap: busy ? null : _save,
                ),
              ),
            ]),
          );

          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
              child: Row(children: [
                SquareIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Indietro',
                  onTap: () => Navigator.pop(context),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Anteprima',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text)),
                ),
                SquareIconButton(
                  icon: Icons.print_outlined,
                  tooltip: 'Stampa',
                  onTap: busy ? null : _print,
                ),
              ]),
            ),
            Expanded(
              child: wide
                  ? Row(children: [
                      Expanded(child: preview),
                      SizedBox(
                        width: 380,
                        child: Container(
                          margin: const EdgeInsets.fromLTRB(0, 8, 16, 0),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: SingleChildScrollView(child: settings),
                        ),
                      ),
                    ])
                  : Column(children: [
                      Expanded(child: preview),
                      Container(
                        constraints:
                            BoxConstraints(maxHeight: cons.maxHeight * 0.42),
                        decoration: const BoxDecoration(
                          color: AppColors.surface,
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(28)),
                        ),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                            width: 40,
                            height: 5,
                            margin: const EdgeInsets.only(top: 10, bottom: 2),
                            decoration: BoxDecoration(
                              color: AppColors.line,
                              borderRadius: BorderRadius.circular(9),
                            ),
                          ),
                          Flexible(child: SingleChildScrollView(child: settings)),
                        ]),
                      ),
                    ]),
            ),
            ColoredBox(
              color: wide ? AppColors.bg : AppColors.surface,
              child: dock,
            ),
          ]);
        }),
      ),
    );
  }

  Widget _preview() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Errore nella creazione del PDF:\n$_error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.danger)),
        ),
      );
    }
    final sizeText = _pdf != null && _pdfSettings == _settings
        ? ' · ≈ ${_formatSize(_pdf!.length)}'
        : '';
    return Stack(children: [
      Column(children: [
        Expanded(
          child: _pages.isEmpty
              ? const SizedBox()
              : PageView.builder(
                  controller: _pageCtrl,
                  itemCount: _pages.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, i) {
                    final pg = _pages[i];
                    return AnimatedScale(
                      duration: const Duration(milliseconds: 220),
                      scale: i == _page ? 1 : 0.9,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 220),
                        opacity: i == _page ? 1 : 0.5,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 16),
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: pg.aspect,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                  boxShadow: const [
                                    BoxShadow(
                                        color: Color(0xAA000000),
                                        blurRadius: 30,
                                        offset: Offset(0, 14)),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: pg.png != null
                                      ? Image.memory(pg.png!,
                                          fit: BoxFit.fill, gaplessPlayback: true)
                                      : LayoutBuilder(
                                          builder: (context, c) => Padding(
                                            padding: EdgeInsets.all(
                                                c.maxWidth * pg.marginFrac),
                                            child: ClipRect(
                                              child: Image.memory(
                                                pg.image!.bytes,
                                                fit: pg.cover
                                                    ? BoxFit.cover
                                                    : BoxFit.contain,
                                                width: double.infinity,
                                                height: double.infinity,
                                                gaplessPlayback: true,
                                              ),
                                            ),
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (_pages.length > 1)
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < _pages.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _page ? 20 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == _page ? AppColors.primary : AppColors.line,
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
          ]),
        const SizedBox(height: 8),
        Text(
          _pages.isEmpty
              ? ' '
              : 'Pagina ${_page + 1} di ${_pages.length}$sizeText',
          style: const TextStyle(color: AppColors.muted, fontSize: 13),
        ),
        const SizedBox(height: 12),
      ]),
      if (_status != null)
        Positioned.fill(
          child: ColoredBox(
            color: _pages.isEmpty ? Colors.transparent : const Color(0x990E0F14),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 14),
                Text(_status!,
                    style: const TextStyle(color: AppColors.textSoft)),
              ]),
            ),
          ),
        ),
    ]);
  }
}

class _SettingsPanel extends StatefulWidget {
  const _SettingsPanel({
    required this.settings,
    required this.nameCtrl,
    required this.onChanged,
  });

  final PdfSettings settings;
  final TextEditingController nameCtrl;
  final ValueChanged<PdfSettings> onChanged;

  @override
  State<_SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<_SettingsPanel> {
  late double _margin = widget.settings.marginMm;
  late double _quality = widget.settings.quality.toDouble();

  @override
  void didUpdateWidget(covariant _SettingsPanel old) {
    super.didUpdateWidget(old);
    _margin = widget.settings.marginMm;
    _quality = widget.settings.quality.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Formato'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final o in PageSizeOption.values)
              AppChip(
                label: o.label,
                selected: s.size == o,
                onTap: () => widget.onChanged(s.copyWith(size: o)),
              ),
          ]),
          const SectionLabel('Orientamento'),
          Segmented<PageOrientationOption>(
            value: s.orientation,
            onChanged: s.size == PageSizeOption.fitImage
                ? null
                : (v) => widget.onChanged(s.copyWith(orientation: v)),
            options: const [
              (PageOrientationOption.auto, 'Auto', Icons.autorenew_rounded),
              (PageOrientationOption.portrait, 'Vert.', Icons.crop_portrait_rounded),
              (PageOrientationOption.landscape, 'Oriz.', Icons.crop_landscape_rounded),
            ],
          ),
          const SectionLabel('Immagine nella pagina'),
          Segmented<FitOption>(
            value: s.fit,
            onChanged: (v) => widget.onChanged(s.copyWith(fit: v)),
            options: const [
              (FitOption.contain, 'Intera', Icons.fit_screen_rounded),
              (FitOption.cover, 'Riempi pagina', Icons.crop_square_rounded),
            ],
          ),
          SectionLabel('Margini · ${_margin.round()} mm'),
          Slider(
            value: _margin,
            min: 0,
            max: 30,
            divisions: 6,
            label: '${_margin.round()} mm',
            onChanged: (v) => setState(() => _margin = v),
            onChangeEnd: (v) => widget.onChanged(s.copyWith(marginMm: v)),
          ),
          SectionLabel('Qualità immagini · ${_quality.round()}%'),
          Slider(
            value: _quality,
            min: 50,
            max: 100,
            divisions: 10,
            label: '${_quality.round()}%',
            onChanged: (v) => setState(() => _quality = v),
            onChangeEnd: (v) => widget.onChanged(s.copyWith(quality: v.round())),
          ),
          const SectionLabel('Nome file'),
          TextField(
            controller: widget.nameCtrl,
            style: const TextStyle(color: AppColors.text),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.surface2,
              isDense: true,
              suffixText: '.pdf',
              suffixStyle: const TextStyle(color: AppColors.muted),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
