import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../models/edit_params.dart';
import '../services/image_processor.dart';
import 'editor_screen.dart';
import 'pdf_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// Un file in arrivo (dal selettore o da una condivisione).
class _Incoming {
  const _Incoming(this.name, this.load);
  final String name;
  final Future<Uint8List?> Function() load;
}

class _HomeScreenState extends State<HomeScreen> {
  final List<PageItem> _items = [];
  String? _loading;
  StreamSubscription<List<SharedMediaFile>>? _shareSub;
  Future<void> _importQueue = Future.value();

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) _listenShares();
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    super.dispose();
  }

  /// Immagini condivise da Galleria/Foto/altre app ("Condividi → Immagini → PDF").
  void _listenShares() {
    final rsi = ReceiveSharingIntent.instance;
    // App già aperta
    _shareSub = rsi.getMediaStream().listen(_onShared, onError: (_) {});
    // App avviata dalla condivisione
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
    // Torna all'elenco se l'utente era in un'altra schermata.
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
            prep.previewBase, const EditParams(),
            maxSide: 480);
        final item = PageItem(
          id: PageItem.newId(),
          name: f.name,
          original: bytes,
          previewBase: prep.previewBase,
          width: prep.width,
          height: prep.height,
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

  Future<void> _edit(PageItem item) async {
    final result = await Navigator.push<EditParams>(
      context,
      MaterialPageRoute(builder: (_) => EditorScreen(item: item)),
    );
    if (result == null || result == item.params) return;
    final thumb = await ImageProcessor.renderPreview(item.previewBase, result,
        maxSide: 480);
    if (!mounted) return;
    setState(() {
      item.params = result;
      item.thumbnail = thumb.bytes;
    });
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
        title: const Text('Rimuovere tutte le immagini?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Annulla')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Rimuovi')),
        ],
      ),
    );
    if (ok == true) setState(_items.clear);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Immagini → PDF'),
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              tooltip: 'Rimuovi tutto',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _loading == null ? _clearAll : null,
            ),
        ],
        bottom: _loading == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_loading!,
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                ),
              ),
      ),
      body: _items.isEmpty ? _empty(scheme) : _list(scheme),
      floatingActionButton: _items.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _loading == null ? _pick : null,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Aggiungi'),
            ),
      bottomNavigationBar: _items.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                  onPressed: _loading == null ? _openPdf : null,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(
                      'Anteprima PDF (${_items.length} ${_items.length == 1 ? 'pagina' : 'pagine'})'),
                ),
              ),
            ),
    );
  }

  Widget _empty(ColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.collections_outlined, size: 72, color: scheme.primary),
          const SizedBox(height: 16),
          Text('Crea un PDF dalle tue immagini',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            'Scegli una o più immagini, modificale e controlla l\'anteprima. '
            'Tutto resta sul tuo dispositivo.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          if (_loading != null)
            const CircularProgressIndicator()
          else
            FilledButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Scegli immagini'),
            ),
        ]),
      ),
    );
  }

  Widget _list(ColorScheme scheme) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      itemCount: _items.length,
      onReorder: (oldIndex, newIndex) {
        setState(() {
          if (newIndex > oldIndex) newIndex -= 1;
          _items.insert(newIndex, _items.removeAt(oldIndex));
        });
      },
      itemBuilder: (context, i) {
        final item = _items[i];
        final (w, h) = item.params.outputSize(item.width, item.height);
        return Card(
          key: ValueKey(item.id),
          clipBehavior: Clip.antiAlias,
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: InkWell(
            onTap: () => _edit(item),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(children: [
                SizedBox(
                  width: 28,
                  child: Text('${i + 1}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontWeight: FontWeight.w600, color: scheme.primary)),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: item.thumbnail == null
                        ? const ColoredBox(color: Colors.black12)
                        : Image.memory(item.thumbnail!,
                            fit: BoxFit.cover, gaplessPlayback: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text('$w×$h px',
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant)),
                      if (!item.params.isIdentity)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('Modificata',
                              style: TextStyle(
                                  fontSize: 12, color: scheme.tertiary)),
                        ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    switch (v) {
                      case 'edit':
                        _edit(item);
                      case 'dup':
                        setState(() => _items.insert(i + 1, item.duplicate()));
                      case 'del':
                        setState(() => _items.removeAt(i));
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Modifica')),
                    PopupMenuItem(value: 'dup', child: Text('Duplica')),
                    PopupMenuItem(value: 'del', child: Text('Elimina')),
                  ],
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}
