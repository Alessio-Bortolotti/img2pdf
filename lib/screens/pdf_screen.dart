import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../models/edit_params.dart';
import '../services/image_processor.dart';
import '../services/pdf_builder.dart';

class PdfScreen extends StatefulWidget {
  const PdfScreen({super.key, required this.items});
  final List<PageItem> items;

  @override
  State<PdfScreen> createState() => _PdfScreenState();
}

class _PdfScreenState extends State<PdfScreen> {
  PdfSettings _settings = const PdfSettings();
  final _nameCtrl = TextEditingController(text: 'documento');
  final _progress = ValueNotifier<String>('Preparazione…');
  final Map<String, RenderedImage> _cache = {};

  Uint8List? _pdf;
  PdfSettings? _pdfSettings;
  String? _sizeInfo;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _progress.dispose();
    super.dispose();
  }

  String get _fileName {
    var n = _nameCtrl.text.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (n.isEmpty) n = 'documento';
    return n.toLowerCase().endsWith('.pdf') ? n : '$n.pdf';
  }

  Future<Uint8List> _buildPdf() async {
    final s = _settings;
    if (_pdf != null && _pdfSettings == s) return _pdf!;

    final images = <RenderedImage>[];
    final items = widget.items;
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      final key = '${it.id}_${it.params.hashCode}_${s.quality}';
      var r = _cache[key];
      if (r == null) {
        _progress.value = 'Elaboro pagina ${i + 1} di ${items.length}…';
        r = await ImageProcessor.renderFull(it.original, it.params,
            quality: s.quality);
        _cache[key] = r;
      }
      images.add(r);
    }
    _progress.value = 'Creo il PDF…';
    final bytes = await PdfBuilder.build(images, s, title: _fileName);
    if (mounted && s == _settings) {
      setState(() {
        _pdf = bytes;
        _pdfSettings = s;
        _sizeInfo = _formatSize(bytes.length);
      });
    }
    return bytes;
  }

  String _formatSize(int b) {
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _setSettings(PdfSettings s) {
    if (s == _settings) return;
    setState(() => _settings = s);
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _save() async {
    final bytes = await _buildPdf();
    try {
      if (Platform.isAndroid || Platform.isIOS) {
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
      // Ripiego: foglio di condivisione del sistema (include "Salva su file").
      await Printing.sharePdf(bytes: bytes, filename: _fileName);
    }
  }

  Future<void> _share() async {
    final bytes = await _buildPdf();
    await Printing.sharePdf(bytes: bytes, filename: _fileName);
  }

  Future<void> _print() async {
    final bytes = await _buildPdf();
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: _fileName);
  }

  void _openSettingsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: _SettingsPanel(
              settings: _settings,
              nameCtrl: _nameCtrl,
              onChanged: (s) {
                _setSettings(s);
                setSheet(() {});
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = PdfPreview(
      key: ValueKey(_settings),
      build: (_) => _buildPdf(),
      useActions: false,
      canChangePageFormat: false,
      canChangeOrientation: false,
      canDebug: false,
      allowPrinting: false,
      allowSharing: false,
      maxPageWidth: 800,
      pdfFileName: _fileName,
      loadingWidget: ValueListenableBuilder<String>(
        valueListenable: _progress,
        builder: (_, v, __) => Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(v),
        ]),
      ),
      onError: (context, error) =>
          Center(child: Text('Errore nella creazione del PDF:\n$error')),
    );

    return LayoutBuilder(builder: (context, cons) {
      final wide = cons.maxWidth >= 900;
      return Scaffold(
        appBar: AppBar(
          title: Text(_sizeInfo == null
              ? 'Anteprima PDF'
              : 'Anteprima PDF · $_sizeInfo'),
          actions: [
            if (!wide)
              IconButton(
                tooltip: 'Impostazioni pagina',
                icon: const Icon(Icons.tune),
                onPressed: _openSettingsSheet,
              ),
          ],
        ),
        body: wide
            ? Row(children: [
                SizedBox(
                  width: 340,
                  child: SingleChildScrollView(
                    child: _SettingsPanel(
                      settings: _settings,
                      nameCtrl: _nameCtrl,
                      onChanged: _setSettings,
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: preview),
              ])
            : preview,
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(children: [
              IconButton.outlined(
                tooltip: 'Stampa',
                onPressed: _print,
                icon: const Icon(Icons.print_outlined),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Condividi',
                onPressed: _share,
                icon: const Icon(Icons.ios_share),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                  onPressed: _save,
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Salva PDF'),
                ),
              ),
            ]),
          ),
        ),
      );
    });
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
  // Valori "live" degli slider: si applicano al rilascio per non
  // rigenerare il PDF ad ogni movimento.
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
    final t = Theme.of(context).textTheme;
    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Text(text, style: t.titleSmall),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label('Nome file'),
          TextField(
            controller: widget.nameCtrl,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              suffixText: '.pdf',
              isDense: true,
            ),
          ),
          label('Formato pagina'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final o in PageSizeOption.values)
              ChoiceChip(
                label: Text(o.label),
                selected: s.size == o,
                onSelected: (_) => widget.onChanged(s.copyWith(size: o)),
              ),
          ]),
          label('Orientamento'),
          SegmentedButton<PageOrientationOption>(
            segments: const [
              ButtonSegment(
                  value: PageOrientationOption.auto,
                  label: Text('Auto'),
                  icon: Icon(Icons.auto_mode)),
              ButtonSegment(
                  value: PageOrientationOption.portrait,
                  label: Text('Vert.'),
                  icon: Icon(Icons.crop_portrait)),
              ButtonSegment(
                  value: PageOrientationOption.landscape,
                  label: Text('Oriz.'),
                  icon: Icon(Icons.crop_landscape)),
            ],
            selected: {s.orientation},
            onSelectionChanged: s.size == PageSizeOption.fitImage
                ? null
                : (v) => widget.onChanged(s.copyWith(orientation: v.first)),
          ),
          label('Adattamento immagine'),
          SegmentedButton<FitOption>(
            segments: const [
              ButtonSegment(
                  value: FitOption.contain,
                  label: Text('Intera'),
                  icon: Icon(Icons.fit_screen)),
              ButtonSegment(
                  value: FitOption.cover,
                  label: Text('Riempi pagina'),
                  icon: Icon(Icons.crop_square)),
            ],
            selected: {s.fit},
            onSelectionChanged: (v) => widget.onChanged(s.copyWith(fit: v.first)),
          ),
          label('Margini: ${_margin.round()} mm'),
          Slider(
            value: _margin,
            min: 0,
            max: 30,
            divisions: 6,
            label: '${_margin.round()} mm',
            onChanged: (v) => setState(() => _margin = v),
            onChangeEnd: (v) => widget.onChanged(s.copyWith(marginMm: v)),
          ),
          label('Qualità immagini: ${_quality.round()}%'),
          Slider(
            value: _quality,
            min: 50,
            max: 100,
            divisions: 10,
            label: '${_quality.round()}%',
            onChanged: (v) => setState(() => _quality = v),
            onChangeEnd: (v) => widget.onChanged(s.copyWith(quality: v.round())),
          ),
          Text(
            'Qualità più bassa = file più leggero. Per ridurre ancora usa '
            '"Dimensione" nell\'editor.',
            style: t.bodySmall,
          ),
        ],
      ),
    );
  }
}
