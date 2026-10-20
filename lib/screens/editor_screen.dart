import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/edit_params.dart';
import '../services/image_processor.dart';
import '../theme.dart';
import '../widgets/crop_editor.dart';
import '../widgets/ui.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.item, this.initialTab = 0});
  final PageItem item;
  final int initialTab;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  static const _aspects = <(String, double?)>[
    ('Libero', null),
    ('1:1', 1),
    ('4:3', 4 / 3),
    ('3:4', 3 / 4),
    ('16:9', 16 / 9),
    ('9:16', 9 / 16),
    ('A4 vert.', 1 / 1.41421),
    ('A4 oriz.', 1.41421),
  ];

  late EditParams _p = widget.item.params;
  late int _tab = widget.initialTab;
  double? _cropAspect;

  RenderedImage? _view;
  Object? _viewKey;
  int _reqId = 0;
  bool _busy = false;
  Timer? _debounce;
  List<Uint8List>? _filterThumbs;

  bool get _cropTab => _tab == 0;

  /// Chiave di ciò che si vede: la scala non cambia l'aspetto, e nella
  /// scheda Ritaglia si mostra l'immagine non ritagliata.
  Object _keyFor(EditParams p, bool cropTab) {
    final k = p.copyWith(scale: 1);
    return cropTab ? k.withoutCrop() : k;
  }

  @override
  void initState() {
    super.initState();
    _schedule(immediate: true);
    ImageProcessor.filterThumbnails(widget.item.previewBase).then((t) {
      if (mounted) setState(() => _filterThumbs = t);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _update(EditParams np) {
    setState(() => _p = np);
    _schedule();
  }

  void _schedule({bool immediate = false}) {
    final key = _keyFor(_p, _cropTab);
    if (key == _viewKey) return;
    _debounce?.cancel();
    _debounce = Timer(Duration(milliseconds: immediate ? 0 : 90), () async {
      final id = ++_reqId;
      final params = _p;
      final cropTab = _cropTab;
      setState(() => _busy = true);
      try {
        final r = await ImageProcessor.renderPreview(
            widget.item.previewBase, params,
            skipCrop: cropTab);
        if (!mounted || id != _reqId) return;
        setState(() {
          _view = r;
          _viewKey = _keyFor(params, cropTab);
          _busy = false;
        });
      } catch (e) {
        if (mounted && id == _reqId) setState(() => _busy = false);
      }
    });
  }

  void _apply() {
    final c = _p.crop;
    Navigator.pop(context, (c != null && c.isFull) ? _p.withoutCrop() : _p);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.editorBg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
            child: Row(children: [
              SquareIconButton(
                icon: Icons.close_rounded,
                tooltip: 'Annulla',
                onTap: () => Navigator.pop(context),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(widget.item.name,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                ),
              ),
              SquareIconButton(
                icon: Icons.restart_alt_rounded,
                tooltip: 'Ripristina originale',
                onTap: () {
                  _cropAspect = null;
                  _update(const EditParams());
                },
              ),
              const SizedBox(width: 8),
              Material(
                color: AppColors.primaryDeep,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _apply,
                  child: const SizedBox(
                    height: 42,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Row(children: [
                        Icon(Icons.check_rounded, size: 18, color: Colors.white),
                        SizedBox(width: 6),
                        Text('Fatto',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15)),
                      ]),
                    ),
                  ),
                ),
              ),
            ]),
          ),
          Expanded(child: _buildCanvas()),
          SizedBox(
            height: 2,
            child: _busy ? const LinearProgressIndicator(minHeight: 2) : null,
          ),
          SizedBox(height: 146, child: _buildPanel()),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Container(
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(26),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  for (final (i, icon, label) in const [
                    (0, Icons.crop_rounded, 'Ritaglia'),
                    (1, Icons.rotate_right_rounded, 'Ruota'),
                    (2, Icons.open_in_full_rounded, 'Misura'),
                    (3, Icons.auto_awesome_outlined, 'Filtri'),
                    (4, Icons.tune_rounded, 'Regola'),
                  ])
                    _ToolTab(
                      icon: icon,
                      label: label,
                      selected: _tab == i,
                      onTap: () {
                        setState(() => _tab = i);
                        _schedule(immediate: true);
                      },
                    ),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildCanvas() {
    final view = _view;
    if (view == null) return const Center(child: CircularProgressIndicator());

    if (_cropTab) {
      // Mostra il riquadro solo quando l'immagine visibile è quella non ritagliata.
      if (_viewKey != _keyFor(_p, true)) {
        return const Center(child: CircularProgressIndicator());
      }
      return CropEditor(
        imageBytes: view.bytes,
        imageAspect: view.width / view.height,
        rect: _p.crop ?? CropRect.full,
        aspect: _cropAspect,
        onChanged: (r) => setState(() => _p = _p.copyWith(crop: r)),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: InteractiveViewer(
        maxScale: 6,
        child: Center(child: Image.memory(view.bytes, gaplessPlayback: true)),
      ),
    );
  }

  Widget _buildPanel() {
    switch (_tab) {
      case 0:
        return _cropPanel();
      case 1:
        return _rotatePanel();
      case 2:
        return _resizePanel();
      case 3:
        return _filterPanel();
      default:
        return _adjustPanel();
    }
  }

  Widget _cropPanel() {
    final view = _view;
    final ready = view != null && _viewKey == _keyFor(_p, true);
    final imgAspect = view == null ? 1.0 : view.width / view.height;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final (label, a) in _aspects)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: AppChip(
                    label: label,
                    selected: _cropAspect == a,
                    selectedColor: Colors.white,
                    selectedTextColor: AppColors.editorBg,
                    onTap: !ready
                        ? null
                        : () {
                            setState(() {
                              _cropAspect = a;
                              if (a != null) {
                                _p = _p.copyWith(
                                    crop: CropEditor.maxRectFor(imgAspect, a));
                              }
                            });
                          },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: AppColors.muted),
          onPressed: () => setState(() {
            _cropAspect = null;
            _p = _p.withoutCrop();
          }),
          icon: const Icon(Icons.crop_free_rounded, size: 18),
          label: const Text('Rimuovi ritaglio'),
        ),
      ],
    );
  }

  Widget _rotatePanel() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _toolButton(Icons.rotate_left, 'Ruota a sinistra',
                  () => _update(_p.rotateCounterClockwise())),
              _toolButton(Icons.rotate_right, 'Ruota a destra',
                  () => _update(_p.rotateClockwise())),
              _toolButton(Icons.flip, 'Specchia orizzontale',
                  () => _update(_p.toggleFlipH())),
              _toolButton(Icons.flip, 'Specchia verticale',
                  () => _update(_p.toggleFlipV()),
                  quarterTurns: 1),
            ],
          ),
          Row(children: [
            const Icon(Icons.straighten_rounded, size: 20, color: AppColors.muted),
            Expanded(
              child: Slider(
                value: _p.fineAngle,
                min: -45,
                max: 45,
                divisions: 180,
                label: '${_p.fineAngle.toStringAsFixed(1)}°',
                onChanged: (v) => _update(_p.copyWith(fineAngle: v)),
              ),
            ),
            SizedBox(
              width: 56,
              child: Text('${_p.fineAngle.toStringAsFixed(1)}°',
                  textAlign: TextAlign.end),
            ),
            IconButton(
              tooltip: 'Azzera',
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: () => _update(_p.copyWith(fineAngle: 0)),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _toolButton(IconData icon, String tip, VoidCallback onTap,
      {int quarterTurns = 0}) {
    return Tooltip(
      message: tip,
      child: Material(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: SizedBox(
            width: 58,
            height: 50,
            child: RotatedBox(
                quarterTurns: quarterTurns,
                child: Icon(icon, color: AppColors.text, size: 24)),
          ),
        ),
      ),
    );
  }

  Widget _resizePanel() {
    final item = widget.item;
    final (ow, oh) = _p.outputSize(item.width, item.height);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Originale ${item.width}×${item.height} px  →  risultato $ow×$oh px',
              style: const TextStyle(color: AppColors.textSoft, fontSize: 13)),
          Slider(
            value: _p.scale,
            min: 0.1,
            max: 1,
            divisions: 18,
            label: '${(_p.scale * 100).round()}%',
            onChanged: (v) => _update(_p.copyWith(scale: v)),
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final s in const [1.0, 0.75, 0.5, 0.25])
                AppChip(
                  label: '${(s * 100).round()}%',
                  selected: (_p.scale - s).abs() < 0.001,
                  selectedColor: Colors.white,
                  selectedTextColor: AppColors.editorBg,
                  onTap: () => _update(_p.copyWith(scale: s)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterPanel() {
    final thumbs = _filterThumbs;
    if (thumbs == null) return const Center(child: CircularProgressIndicator());
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      itemCount: ImageFilter.values.length,
      separatorBuilder: (_, __) => const SizedBox(width: 10),
      itemBuilder: (context, i) {
        final f = ImageFilter.values[i];
        final selected = _p.filter == f;
        final scheme = Theme.of(context).colorScheme;
        return GestureDetector(
          onTap: () => _update(_p.copyWith(filter: f)),
          child: Column(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 76,
              height: 76,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? scheme.primary : Colors.transparent,
                  width: 2.5,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(thumbs[i], fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 4),
            Text(f.label,
                style: TextStyle(
                  fontSize: 12,
                  color: selected ? scheme.primary : null,
                  fontWeight: selected ? FontWeight.w600 : null,
                )),
          ]),
        );
      },
    );
  }

  Widget _adjustPanel() {
    Widget row(IconData icon, String label, double value,
        EditParams Function(double) apply) {
      return Row(children: [
        Icon(icon, size: 20, color: AppColors.muted),
        const SizedBox(width: 8),
        SizedBox(
            width: 88,
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.textSoft,
                    fontSize: 13,
                    fontWeight: FontWeight.w600))),
        Expanded(
          child: Slider(
            value: value,
            min: -1,
            max: 1,
            divisions: 200,
            label: '${(value * 100).round()}',
            onChanged: (v) => _update(apply(v)),
          ),
        ),
        SizedBox(
            width: 36,
            child: Text('${(value * 100).round()}', textAlign: TextAlign.end)),
      ]);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          row(Icons.brightness_6, 'Luminosità', _p.brightness,
              (v) => _p.copyWith(brightness: v)),
          row(Icons.contrast, 'Contrasto', _p.contrast,
              (v) => _p.copyWith(contrast: v)),
          row(Icons.palette_outlined, 'Saturazione', _p.saturation,
              (v) => _p.copyWith(saturation: v)),
        ],
      ),
    );
  }
}

class _ToolTab extends StatelessWidget {
  const _ToolTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 36,
      child: SizedBox(
        width: 64,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 48,
            height: 36,
            decoration: BoxDecoration(
              color: selected ? AppColors.primaryDeep : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon,
                size: 22, color: selected ? Colors.white : AppColors.muted),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : AppColors.muted)),
        ]),
      ),
    );
  }
}
