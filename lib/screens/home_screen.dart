import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../demo.dart';
import '../models/edit_params.dart';
import '../services/image_processor.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'editor_screen.dart';
import 'pdf_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// Un file in arrivo (dal selettore o da una condivisione).
class _Incoming {
  const _Incoming(this.name, this.load, [this.params = const EditParams()]);
  final String name;
  final Future<Uint8List?> Function() load;
  final EditParams params;
}

class _HomeScreenState extends State<HomeScreen> {
  final List<PageItem> _items = [];
  String? _loading;
  StreamSubscription<List<SharedMediaFile>>? _shareSub;
  Future<void> _importQueue = Future.value();
  final _firstMenuKey = GlobalKey<PopupMenuButtonState<String>>();

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && Platform.isAndroid) _listenShares();
    if (kDemo) _loadDemo();
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------------ import

  /// Immagini condivise da Galleria/Foto/altre app ("Condividi → FotoPDF").
  void _listenShares() {
    final rsi = ReceiveSharingIntent.instance;
    _shareSub = rsi.getMediaStream().listen(_onShared, onError: (_) {});
    rsi.getInitialMedia().then((files) {
      _onShared(files);
      rsi.reset();
    });
  }

  void _onShared(List<SharedMediaFile> files) {
    final incoming = [
      for (final f in files)
        if (f.type == SharedMediaType.image || f.type == SharedMediaType.file)
          _Incoming(
            f.path.split(Platform.pathSeparator).last,
            () => File(f.path).readAsBytes(),
          ),
    ];
    if (incoming.isEmpty) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    _enqueue(incoming);
  }

  Future<void> _pick() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    _enqueue([
      for (final f in res.files)
        _Incoming(f.name, () async {
          if (f.bytes != null) return f.bytes;
          if (f.path != null) return File(f.path!).readAsBytes();
          return null;
        }),
    ]);
  }

  void _enqueue(List<_Incoming> files) {
    _importQueue = _importQueue.then((_) => _import(files));
  }

  Future<void> _import(List<_Incoming> files) async {
    final failed = <String>[];
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      if (!mounted) return;
      setState(() => _loading = 'Carico ${i + 1} di ${files.length}…');
      try {
        final bytes = await f.load();
        if (bytes == null) throw const FormatException();
        final prep = await ImageProcessor.prepare(bytes);
        final thumb = await ImageProcessor.renderPreview(
            prep.previewBase, f.params,
            maxSide: 480);
        final item = PageItem(
          id: PageItem.newId(),
          name: f.name,
          original: bytes,
          previewBase: prep.previewBase,
          width: prep.width,
          height: prep.height,
          params: f.params,
          thumbnail: thumb.bytes,
        );
        if (!mounted) return;
        setState(() => _items.add(item));
      } catch (_) {
        failed.add(f.name);
      }
    }
    if (!mounted) return;
    setState(() => _loading = null);
    if (failed.isNotEmpty) {
      _snack('Impossibile aprire: ${failed.join(', ')} '
          '(formato non supportato, es. HEIC)');
    }
  }

  Future<void> _loadDemo() async {
    Future<Uint8List?> asset(String n) async =>
        (await rootBundle.load('assets/demo/$n.jpg')).buffer.asUint8List();
    _enqueue([
      _Incoming('IMG_2041.jpg', () => asset('1'),
          const EditParams(crop: CropRect(0.08, 0.1, 0.84, 0.8))),
      _Incoming('Scontrino.jpg', () => asset('2'),
          const EditParams(filter: ImageFilter.document)),
      _Incoming('Spiaggia.png', () => asset('3')),
    ]);
    await _importQueue;
    if (!mounted) return;
    switch (demoScreen()) {
      case 'menu':
        _firstMenuKey.currentState?.showButtonMenu();
      case 'editor':
        _edit(_items.first, initialTab: demoTab());
      case 'pdf':
        _openPdf();
    }
  }

  // ------------------------------------------------------------------ azioni

  Future<void> _edit(PageItem item, {int initialTab = 0}) async {
    final result = await Navigator.push<EditParams>(
      context,
      MaterialPageRoute(
          builder: (_) => EditorScreen(item: item, initialTab: initialTab)),
    );
    if (result == null || result == item.params) return;
    await _applyParams(item, result);
  }

  Future<void> _quickRotate(PageItem item, {required bool clockwise}) =>
      _applyParams(
          item,
          clockwise
              ? item.params.rotateClockwise()
              : item.params.rotateCounterClockwise());

  Future<void> _applyParams(PageItem item, EditParams params) async {
    setState(() => item.params = params);
    final thumb = await ImageProcessor.renderPreview(item.previewBase, params,
        maxSide: 480);
    if (!mounted || item.params != params) return;
    setState(() => item.thumbnail = thumb.bytes);
  }

  void _openPdf() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PdfScreen(items: List.of(_items))),
    );
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        title: const Text('Rimuovere tutte le immagini?'),
        content: const Text(
            'I file originali nella galleria non vengono toccati.',
            style: TextStyle(color: AppColors.muted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Annulla')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Rimuovi')),
        ],
      ),
    );
    if (ok == true) setState(_items.clear);
  }

  void _moveTo(String id, int target) {
    final from = _items.indexWhere((e) => e.id == id);
    if (from < 0 || from == target) return;
    setState(() => _items.insert(target, _items.removeAt(from)));
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final busy = _loading != null;
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(
          child: CustomScrollView(slivers: [
            SliverToBoxAdapter(child: SafeArea(bottom: false, child: _header())),
            if (_items.isEmpty)
              SliverFillRemaining(hasScrollBody: false, child: _empty())
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(20, 18, 20, 120 + bottomInset),
                sliver: _grid(),
              ),
          ]),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 130 + bottomInset,
          child: const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  stops: [0.5, 1],
                  colors: [AppColors.bg, Color(0x000E0F14)],
                ),
              ),
            ),
          ),
        ),
        if (_items.isNotEmpty)
          Positioned(
            left: 16,
            right: 16,
            bottom: 18 + bottomInset,
            child: Row(children: [
              SquareIconButton(
                icon: Icons.add_rounded,
                iconSize: 28,
                size: 60,
                radius: 20,
                color: AppColors.surface2,
                iconColor: AppColors.primary,
                tooltip: 'Aggiungi immagini',
                onTap: busy ? null : _pick,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GradientButton(
                  icon: Icons.description_outlined,
                  label: 'Crea PDF',
                  trailing: '· ${_items.length} pag.',
                  onTap: busy ? null : _openPdf,
                ),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _header() {
    final n = _items.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              gradient: AppColors.gradient,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.description_outlined,
                size: 17, color: Colors.white),
          ),
          const SizedBox(width: 9),
          const Text('FotoPDF',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: AppColors.primary)),
          const Spacer(),
          if (n > 0)
            SquareIconButton(
              icon: Icons.delete_outline_rounded,
              tooltip: 'Rimuovi tutto',
              onTap: _loading == null ? _clearAll : null,
            ),
        ]),
        const SizedBox(height: 18),
        Text(n == 0 ? 'Crea un PDF' : 'Il tuo documento',
            style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
                color: AppColors.text)),
        const SizedBox(height: 8),
        if (_loading != null)
          Row(children: [
            const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Text(_loading!,
                style: const TextStyle(color: AppColors.muted, fontSize: 14)),
          ])
        else if (n > 0)
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text('$n ${n == 1 ? 'pagina' : 'pagine'}',
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12)),
            ),
            const SizedBox(width: 8),
            const Flexible(
              child: Text('tieni premuto per riordinare',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.muted, fontSize: 14)),
            ),
          ])
        else
          const Text('Scegli le immagini, sistemale e salva il PDF.',
              style: TextStyle(color: AppColors.muted, fontSize: 15)),
      ]),
    );
  }

  Widget _empty() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      child: Column(children: [
        _AddTile(
          height: 300,
          big: true,
          onTap: _loading == null ? _pick : null,
        ),
        const SizedBox(height: 20),
        const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.muted),
          SizedBox(width: 8),
          Text('Tutto resta sul tuo dispositivo',
              style: TextStyle(color: AppColors.muted, fontSize: 13)),
        ]),
        const SizedBox(height: 6),
        const Text('Puoi anche condividere le foto dalla Galleria',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 13)),
      ]),
    );
  }

  Widget _grid() {
    return SliverLayoutBuilder(builder: (context, constraints) {
      final w = constraints.crossAxisExtent;
      final cols = w >= 900 ? 4 : (w >= 600 ? 3 : 2);
      const gap = 14.0;
      final cardW = (w - gap * (cols - 1)) / cols;
      final thumbH = (cardW - 20) * 4 / 3;
      final cardH = thumbH + 66;
      final count = _items.length + 1;

      return SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          crossAxisSpacing: gap,
          mainAxisSpacing: gap,
          mainAxisExtent: cardH,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            if (i == _items.length) {
              return _AddTile(
                key: const ValueKey('__add__'),
                onTap: _loading == null ? _pick : null,
              );
            }
            final item = _items[i];
            final card = _PageCard(
              item: item,
              index: i,
              menuKey: i == 0 ? _firstMenuKey : null,
              onTap: () => _edit(item),
              onAction: (a) => _onAction(a, item),
            );
            return DragTarget<String>(
              key: ValueKey(item.id),
              onWillAcceptWithDetails: (d) {
                _moveTo(d.data, i);
                return true;
              },
              builder: (context, _, __) => LongPressDraggable<String>(
                data: item.id,
                onDragStarted: HapticFeedback.selectionClick,
                feedback: Material(
                  type: MaterialType.transparency,
                  child: SizedBox(
                    width: cardW,
                    height: cardH,
                    child: Transform.scale(scale: 1.05, child: card),
                  ),
                ),
                childWhenDragging: Opacity(opacity: 0.25, child: card),
                child: card,
              ),
            );
          },
          childCount: count,
          findChildIndexCallback: (key) {
            if (key is ValueKey<String>) {
              if (key.value == '__add__') return _items.length;
              final idx = _items.indexWhere((e) => e.id == key.value);
              return idx < 0 ? null : idx;
            }
            return null;
          },
        ),
      );
    });
  }

  void _onAction(String a, PageItem item) {
    switch (a) {
      case 'edit':
        _edit(item);
      case 'rotR':
        _quickRotate(item, clockwise: true);
      case 'rotL':
        _quickRotate(item, clockwise: false);
      case 'dup':
        final i = _items.indexOf(item);
        setState(() => _items.insert(i + 1, item.duplicate()));
      case 'del':
        setState(() => _items.remove(item));
    }
  }
}

/// Scheda di una pagina nella griglia.
class _PageCard extends StatelessWidget {
  const _PageCard({
    required this.item,
    required this.index,
    required this.onTap,
    required this.onAction,
    this.menuKey,
  });

  final PageItem item;
  final int index;
  final VoidCallback onTap;
  final ValueChanged<String> onAction;
  final GlobalKey<PopupMenuButtonState<String>>? menuKey;

  String? get _tag {
    final p = item.params;
    if (p.isIdentity) return null;
    if (p.filter != ImageFilter.none) return p.filter.label;
    if (p.crop != null) return 'Ritagliata';
    if (p.quarterTurns != 0 || p.fineAngle != 0) return 'Ruotata';
    return 'Modificata';
  }

  @override
  Widget build(BuildContext context) {
    final (w, h) = item.params.outputSize(item.width, item.height);
    final tag = _tag;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AspectRatio(
              aspectRatio: 3 / 4,
              child: Stack(fit: StackFit.expand, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: item.thumbnail == null
                      ? const ColoredBox(color: AppColors.surface2)
                      : Image.memory(item.thumbnail!,
                          fit: BoxFit.cover, gaplessPlayback: true),
                ),
                Positioned(
                  left: 8,
                  top: 8,
                  child: Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: AppColors.bg,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Color(0x66000000), blurRadius: 6)],
                    ),
                    child: Text('${index + 1}',
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                  ),
                ),
                Positioned(right: 4, top: 4, child: _menu()),
                if (tag != null)
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xE60E0F14),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(tag,
                          style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 9),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text)),
            ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text('$w×$h px',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _menu() {
    return PopupMenuButton<String>(
      key: menuKey,
      tooltip: 'Azioni',
      padding: EdgeInsets.zero,
      offset: const Offset(0, 40),
      onSelected: onAction,
      itemBuilder: (ctx) => [
        PopupMenuItem<String>(
          enabled: false,
          height: 72,
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
          child: IconTheme(
            data: const IconThemeData(opacity: 1, color: AppColors.primary),
            child: Row(children: [
              Expanded(
                child: _QuickButton(
                  icon: Icons.rotate_left_rounded,
                  label: 'Sinistra',
                  onTap: () => Navigator.pop(ctx, 'rotL'),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _QuickButton(
                  icon: Icons.rotate_right_rounded,
                  label: 'Destra',
                  onTap: () => Navigator.pop(ctx, 'rotR'),
                ),
              ),
            ]),
          ),
        ),
        const PopupMenuDivider(height: 8),
        _item('edit', Icons.tune_rounded, 'Modifica'),
        _item('dup', Icons.copy_rounded, 'Duplica'),
        _item('del', Icons.delete_outline_rounded, 'Elimina',
            color: AppColors.danger),
      ],
      child: Container(
        width: 32,
        height: 32,
        margin: const EdgeInsets.all(4),
        decoration: const BoxDecoration(
          color: Color(0x99000000),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.more_vert_rounded, size: 18, color: Colors.white),
      ),
    );
  }

  PopupMenuItem<String> _item(String v, IconData icon, String label,
      {Color color = AppColors.text}) {
    return PopupMenuItem<String>(
      value: v,
      height: 46,
      child: Row(children: [
        Icon(icon, size: 20, color: color == AppColors.text ? AppColors.textSoft : color),
        const SizedBox(width: 12),
        Text(label,
            style: TextStyle(
                color: color, fontSize: 14, fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

class _QuickButton extends StatelessWidget {
  const _QuickButton(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          height: 56,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: AppColors.primary),
              const SizedBox(height: 3),
              Text(label,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Casella tratteggiata "Aggiungi immagini".
class _AddTile extends StatelessWidget {
  const _AddTile({super.key, required this.onTap, this.height, this.big = false});
  final VoidCallback? onTap;
  final double? height;
  final bool big;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: const DashedBorderPainter(),
        child: Material(
          color: const Color(0x0F7C8AFF),
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: big ? 64 : 52,
                  height: big ? 64 : 52,
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: onTap == null
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(strokeWidth: 2.5))
                      : Icon(Icons.add_rounded,
                          size: big ? 32 : 26, color: AppColors.primary),
                ),
                const SizedBox(height: 12),
                Text(big ? 'Scegli le immagini' : 'Aggiungi immagini',
                    style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: big ? 16 : 14)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
